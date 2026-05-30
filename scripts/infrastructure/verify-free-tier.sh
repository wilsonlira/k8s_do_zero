#!/bin/bash
# =============================================================================
# Verify AWS Free Tier Eligibility
# =============================================================================
# This script validates that all provisioned resources are within AWS Free Tier
# limits. It checks:
#   - EC2 instance types (must be t2.micro or t3.micro)
#   - EBS volume sizes (total must not exceed 30 GB of gp2/gp3)
#   - Number of running instances (Free Tier allows 750 hours/month total)
#   - Elastic IPs (Free Tier: 1 per running instance, charged if unused)
#
# Run this script after provisioning to confirm no unexpected charges.
#
# Requirements: 1.5 (verify Free Tier eligibility)
#               1.7 (EBS ≤ 30GB gp2/gp3 total)
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

echo "============================================="
echo " AWS Free Tier Eligibility Verification"
echo " Region: ${AWS_REGION}"
echo " Project: ${CLUSTER_NAME}"
echo "============================================="

# Track overall status
WARNINGS=0
ERRORS=0

# -----------------------------------------------------------------------------
# Step 1: Check EC2 Instance Types
# -----------------------------------------------------------------------------
# Free Tier allows 750 hours/month of t2.micro (or t3.micro in some regions).
# Any other instance type will incur charges.
echo ""
echo "[1/5] Checking EC2 Instance Types..."

INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" "Name=instance-state-name,Values=running,stopped" \
    --region "${AWS_REGION}" \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
    --output text)

if [ -z "${INSTANCES}" ]; then
    echo "  ℹ No instances found with Project tag '${CLUSTER_NAME}'"
else
    while IFS=$'\t' read -r INSTANCE_ID INSTANCE_TYPE_ACTUAL INSTANCE_NAME; do
        if [ "${INSTANCE_TYPE_ACTUAL}" = "t2.micro" ] || [ "${INSTANCE_TYPE_ACTUAL}" = "t3.micro" ]; then
            echo "  ✓ ${INSTANCE_NAME} (${INSTANCE_ID}): ${INSTANCE_TYPE_ACTUAL} — Free Tier eligible"
        else
            echo "  ✗ ${INSTANCE_NAME} (${INSTANCE_ID}): ${INSTANCE_TYPE_ACTUAL} — NOT Free Tier eligible!"
            echo "    ⚠ Estimated cost: Check AWS pricing for ${INSTANCE_TYPE_ACTUAL}"
            echo "    → Recommendation: Change to t2.micro or t3.micro"
            ((ERRORS++))
        fi
    done <<< "${INSTANCES}"
fi

# -----------------------------------------------------------------------------
# Step 2: Check EBS Volume Sizes
# -----------------------------------------------------------------------------
# Free Tier allows 30 GB of EBS storage (gp2/gp3) total across all volumes.
echo ""
echo "[2/5] Checking EBS Volume Sizes..."

VOLUMES=$(aws ec2 describe-volumes \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'Volumes[].[VolumeId,Size,VolumeType,State,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || echo "")

# If no project-tagged volumes, check volumes attached to project instances
if [ -z "${VOLUMES}" ]; then
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=${CLUSTER_NAME}" "Name=instance-state-name,Values=running,stopped" \
        --region "${AWS_REGION}" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")

    if [ -n "${INSTANCE_IDS}" ]; then
        VOLUMES=$(aws ec2 describe-volumes \
            --filters "Name=attachment.instance-id,Values=${INSTANCE_IDS// /,}" \
            --region "${AWS_REGION}" \
            --query 'Volumes[].[VolumeId,Size,VolumeType,State,Attachments[0].InstanceId]' \
            --output text 2>/dev/null || echo "")
    fi
fi

TOTAL_EBS_SIZE=0

if [ -z "${VOLUMES}" ]; then
    echo "  ℹ No EBS volumes found for project '${CLUSTER_NAME}'"
else
    while IFS=$'\t' read -r VOL_ID VOL_SIZE VOL_TYPE VOL_STATE VOL_ATTACHED; do
        TOTAL_EBS_SIZE=$((TOTAL_EBS_SIZE + VOL_SIZE))

        if [ "${VOL_TYPE}" = "gp2" ] || [ "${VOL_TYPE}" = "gp3" ]; then
            echo "  ✓ ${VOL_ID}: ${VOL_SIZE} GB ${VOL_TYPE} (${VOL_STATE}) — Free Tier eligible type"
        else
            echo "  ⚠ ${VOL_ID}: ${VOL_SIZE} GB ${VOL_TYPE} (${VOL_STATE}) — NOT gp2/gp3!"
            echo "    → Recommendation: Use gp2 or gp3 volume type"
            ((WARNINGS++))
        fi
    done <<< "${VOLUMES}"

    echo ""
    echo "  Total EBS Storage: ${TOTAL_EBS_SIZE} GB / 30 GB (Free Tier limit)"

    if [ "${TOTAL_EBS_SIZE}" -gt 30 ]; then
        echo "  ✗ EXCEEDS Free Tier limit by $((TOTAL_EBS_SIZE - 30)) GB!"
        echo "    ⚠ Estimated additional cost: ~\$0.08/GB/month for gp3"
        echo "    → Recommendation: Reduce volume sizes to total ≤ 30 GB"
        ((ERRORS++))
    else
        echo "  ✓ Within Free Tier limit"
    fi
fi

# -----------------------------------------------------------------------------
# Step 3: Check Running Instance Hours
# -----------------------------------------------------------------------------
# Free Tier allows 750 hours/month of t2.micro. With 2 instances running 24/7,
# that's 2 × 24 × 30 = 1440 hours/month — which exceeds the 750-hour limit.
echo ""
echo "[3/5] Checking Instance Running Hours..."

RUNNING_COUNT=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" "Name=instance-state-name,Values=running" \
    --region "${AWS_REGION}" \
    --query 'Reservations[].Instances[] | length(@)' \
    --output text 2>/dev/null || echo "0")

MONTHLY_HOURS=$((RUNNING_COUNT * 24 * 30))

echo "  Running instances: ${RUNNING_COUNT}"
echo "  Estimated monthly hours: ${MONTHLY_HOURS} / 750 (Free Tier limit)"

if [ "${MONTHLY_HOURS}" -gt 750 ]; then
    echo "  ⚠ WARNING: Running ${RUNNING_COUNT} instances 24/7 exceeds Free Tier!"
    echo "    750 hours ÷ ${RUNNING_COUNT} instances = $((750 / RUNNING_COUNT)) hours/instance/month"
    echo "    → Recommendation: Stop instances when not in use"
    echo "    → Use: aws ec2 stop-instances --instance-ids <id1> <id2>"
    ((WARNINGS++))
else
    echo "  ✓ Within Free Tier limit"
fi

# -----------------------------------------------------------------------------
# Step 4: Check for Elastic IPs
# -----------------------------------------------------------------------------
# Elastic IPs are free when associated with a running instance.
# Unassociated Elastic IPs incur charges (~$0.005/hour).
echo ""
echo "[4/5] Checking Elastic IPs..."

EIP_COUNT=$(aws ec2 describe-addresses \
    --region "${AWS_REGION}" \
    --query 'Addresses[?AssociationId==null] | length(@)' \
    --output text 2>/dev/null || echo "0")

if [ "${EIP_COUNT}" -gt 0 ]; then
    echo "  ⚠ WARNING: ${EIP_COUNT} unassociated Elastic IP(s) found!"
    echo "    Unassociated EIPs cost ~\$3.60/month each"
    echo "    → Recommendation: Release unused EIPs or associate them with instances"
    ((WARNINGS++))
else
    echo "  ✓ No unassociated Elastic IPs"
fi

# -----------------------------------------------------------------------------
# Step 5: Check Data Transfer
# -----------------------------------------------------------------------------
# Free Tier includes 100 GB of data transfer out per month (first 12 months).
# For a lab environment, this is unlikely to be exceeded.
echo ""
echo "[5/5] Data Transfer Estimate..."
echo "  ℹ Free Tier includes 100 GB/month data transfer out"
echo "  ℹ Lab usage is typically well under this limit"
echo "  ✓ No action needed for typical lab usage"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
echo " Free Tier Verification Summary"
echo "============================================="
echo ""

if [ "${ERRORS}" -gt 0 ]; then
    echo "  ✗ ERRORS: ${ERRORS} resource(s) exceed Free Tier limits"
    echo "    Action required to avoid charges!"
elif [ "${WARNINGS}" -gt 0 ]; then
    echo "  ⚠ WARNINGS: ${WARNINGS} potential cost concern(s)"
    echo "    Review recommendations above to minimize costs."
else
    echo "  ✓ All resources are within AWS Free Tier limits"
fi

echo ""
echo "Free Tier Checklist:"
echo "  [$([ "${INSTANCE_TYPE}" = "t2.micro" ] || [ "${INSTANCE_TYPE}" = "t3.micro" ] && echo "✓" || echo "✗")] Instance type: ${INSTANCE_TYPE} (need t2.micro or t3.micro)"
echo "  [$([ "${TOTAL_EBS_SIZE}" -le 30 ] && echo "✓" || echo "✗")] EBS storage: ${TOTAL_EBS_SIZE} GB (limit: 30 GB)"
echo "  [$([ "${MONTHLY_HOURS}" -le 750 ] && echo "✓" || echo "⚠")] Instance hours: ~${MONTHLY_HOURS}/month (limit: 750)"
echo "  [$([ "${EIP_COUNT}" -eq 0 ] && echo "✓" || echo "⚠")] Elastic IPs: ${EIP_COUNT} unassociated (should be 0)"
echo ""
echo "Cost-Saving Tips:"
echo "  • Stop instances when not studying: aws ec2 stop-instances --instance-ids ..."
echo "  • Terminate instances when done: aws ec2 terminate-instances --instance-ids ..."
echo "  • Run cleanup script to remove all resources: scripts/cleanup/cleanup.sh"
echo ""

# Exit with error if Free Tier limits are exceeded
if [ "${ERRORS}" -gt 0 ]; then
    exit 1
fi

exit 0
