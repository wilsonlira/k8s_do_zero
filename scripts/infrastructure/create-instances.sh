#!/bin/bash
# =============================================================================
# Create EC2 Instances for Kubernetes Cluster
# =============================================================================
# This script provisions EC2 instances for the Kubernetes lab:
#   - 1 Control Plane node (runs etcd, apiserver, scheduler, controller-manager)
#   - 1 Worker Node (runs kubelet, kube-proxy, container runtime, pods)
#
# Both instances use t2.micro (Free Tier eligible) with Ubuntu 22.04 LTS.
# EBS volumes are configured to stay within the 30GB Free Tier limit.
#
# Requirements: 1.1 (EC2 t2.micro instances, Ubuntu 22.04 LTS AMI)
#               1.7 (EBS ≤ 30GB gp2/gp3 total)
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

echo "============================================="
echo " Creating EC2 Instances"
echo " Instance Type: ${INSTANCE_TYPE}"
echo " AMI: ${AMI_ID}"
echo " Region: ${AWS_REGION}"
echo "============================================="

# -----------------------------------------------------------------------------
# Validate prerequisites
# -----------------------------------------------------------------------------
echo ""
echo "Validating prerequisites..."

if [ -z "${SUBNET_ID:-}" ]; then
    echo "ERROR: SUBNET_ID is not set. Run create-vpc.sh first or export SUBNET_ID."
    exit 1
fi

if [ -z "${CP_SG_ID:-}" ]; then
    echo "ERROR: CP_SG_ID is not set. Run create-security-groups.sh first or export CP_SG_ID."
    exit 1
fi

if [ -z "${WORKER_SG_ID:-}" ]; then
    echo "ERROR: WORKER_SG_ID is not set. Run create-security-groups.sh first or export WORKER_SG_ID."
    exit 1
fi

if [ -z "${KEY_NAME:-}" ]; then
    echo "ERROR: KEY_NAME is not set. Run create-keypair.sh first or export KEY_NAME."
    exit 1
fi

echo "  ✓ SUBNET_ID: ${SUBNET_ID}"
echo "  ✓ CP_SG_ID: ${CP_SG_ID}"
echo "  ✓ WORKER_SG_ID: ${WORKER_SG_ID}"
echo "  ✓ KEY_NAME: ${KEY_NAME}"

# -----------------------------------------------------------------------------
# Free Tier validation
# -----------------------------------------------------------------------------
echo ""
echo "Free Tier Check:"
echo "  Instance type: ${INSTANCE_TYPE} (Free Tier eligible: t2.micro or t3.micro)"
echo "  Control Plane disk: ${CONTROL_PLANE_DISK_SIZE} GB ${EBS_VOLUME_TYPE}"
echo "  Worker Node disk: ${WORKER_NODE_DISK_SIZE} GB ${EBS_VOLUME_TYPE}"
TOTAL_DISK=$((CONTROL_PLANE_DISK_SIZE + WORKER_NODE_DISK_SIZE))
echo "  Total EBS storage: ${TOTAL_DISK} GB (Free Tier limit: 30 GB)"

if [ "${TOTAL_DISK}" -gt 30 ]; then
    echo ""
    echo "  ⚠ WARNING: Total EBS storage (${TOTAL_DISK} GB) exceeds Free Tier limit (30 GB)!"
    echo "  Estimated additional cost: ~\$0.08/GB/month for gp3"
    echo "  Consider reducing disk sizes in variables.env"
    echo ""
    read -p "  Continue anyway? (y/N): " CONFIRM
    if [ "${CONFIRM}" != "y" ] && [ "${CONFIRM}" != "Y" ]; then
        echo "  Aborted."
        exit 1
    fi
fi

if [ "${INSTANCE_TYPE}" != "t2.micro" ] && [ "${INSTANCE_TYPE}" != "t3.micro" ]; then
    echo ""
    echo "  ⚠ WARNING: Instance type '${INSTANCE_TYPE}' may NOT be Free Tier eligible!"
    echo "  Free Tier eligible types: t2.micro, t3.micro"
    echo "  Estimated cost: varies by instance type"
    echo ""
    read -p "  Continue anyway? (y/N): " CONFIRM
    if [ "${CONFIRM}" != "y" ] && [ "${CONFIRM}" != "Y" ]; then
        echo "  Aborted."
        exit 1
    fi
fi

echo "  ✓ Free Tier validation passed"

# -----------------------------------------------------------------------------
# Step 1: Create Control Plane Instance
# -----------------------------------------------------------------------------
# The control plane node runs the core Kubernetes management components:
# etcd, kube-apiserver, kube-scheduler, and kube-controller-manager.
echo ""
echo "[1/2] Creating Control Plane instance (${CONTROL_PLANE_NAME})..."

CP_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${KEY_NAME}" \
    --subnet-id "${SUBNET_ID}" \
    --security-group-ids "${CP_SG_ID}" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${CONTROL_PLANE_DISK_SIZE},\"VolumeType\":\"${EBS_VOLUME_TYPE}\",\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${CONTROL_PLANE_NAME}},{Key=Project,Value=${CLUSTER_NAME}},{Key=Role,Value=control-plane}]" \
    --region "${AWS_REGION}" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "${CP_INSTANCE_ID}" ]; then
    echo "ERROR: Failed to create Control Plane instance."
    exit 1
fi

echo "  ✓ Control Plane instance launched: ${CP_INSTANCE_ID}"

# -----------------------------------------------------------------------------
# Step 2: Create Worker Node Instance
# -----------------------------------------------------------------------------
# The worker node runs the workloads (pods). It has kubelet, kube-proxy,
# the container runtime (containerd), and the CNI plugin.
echo ""
echo "[2/2] Creating Worker Node instance (${WORKER_NODE_NAME})..."

WORKER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${KEY_NAME}" \
    --subnet-id "${SUBNET_ID}" \
    --security-group-ids "${WORKER_SG_ID}" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${WORKER_NODE_DISK_SIZE},\"VolumeType\":\"${EBS_VOLUME_TYPE}\",\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${WORKER_NODE_NAME}},{Key=Project,Value=${CLUSTER_NAME}},{Key=Role,Value=worker}]" \
    --region "${AWS_REGION}" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "${WORKER_INSTANCE_ID}" ]; then
    echo "ERROR: Failed to create Worker Node instance."
    exit 1
fi

echo "  ✓ Worker Node instance launched: ${WORKER_INSTANCE_ID}"

# -----------------------------------------------------------------------------
# Step 3: Wait for instances to be running
# -----------------------------------------------------------------------------
echo ""
echo "Waiting for instances to reach 'running' state..."

aws ec2 wait instance-running \
    --instance-ids "${CP_INSTANCE_ID}" "${WORKER_INSTANCE_ID}" \
    --region "${AWS_REGION}"

echo "  ✓ Both instances are running"

# -----------------------------------------------------------------------------
# Step 4: Retrieve public and private IPs
# -----------------------------------------------------------------------------
echo ""
echo "Retrieving instance IP addresses..."

# Control Plane IPs
CP_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "${CP_INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

CP_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "${CP_INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

# Worker Node IPs
WORKER_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "${WORKER_INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

WORKER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "${WORKER_INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

echo "  Control Plane: Public=${CP_PUBLIC_IP}, Private=${CP_PRIVATE_IP}"
echo "  Worker Node:   Public=${WORKER_PUBLIC_IP}, Private=${WORKER_PRIVATE_IP}"

# -----------------------------------------------------------------------------
# Step 5: Update variables.env with instance IPs
# -----------------------------------------------------------------------------
echo ""
echo "Updating variables.env with instance IPs..."

VARS_FILE="$(dirname "$0")/../../variables.env"

# Update CONTROL_PLANE_IP in variables.env
sed -i "s|^CONTROL_PLANE_IP=.*|CONTROL_PLANE_IP=\"${CP_PRIVATE_IP}\"|" "${VARS_FILE}"
sed -i "s|^WORKER_NODE_IP=.*|WORKER_NODE_IP=\"${WORKER_PRIVATE_IP}\"|" "${VARS_FILE}"

echo "  ✓ variables.env updated with private IPs"

# -----------------------------------------------------------------------------
# Export Resource IDs
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
echo " EC2 Instances Created Successfully"
echo "============================================="
echo ""
echo "Instance Details:"
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ Control Plane                                                    │"
echo "  │   Instance ID: ${CP_INSTANCE_ID}"
echo "  │   Public IP:   ${CP_PUBLIC_IP}"
echo "  │   Private IP:  ${CP_PRIVATE_IP}"
echo "  │   Type:        ${INSTANCE_TYPE}"
echo "  │   Disk:        ${CONTROL_PLANE_DISK_SIZE} GB ${EBS_VOLUME_TYPE}"
echo "  ├─────────────────────────────────────────────────────────────────┤"
echo "  │ Worker Node                                                      │"
echo "  │   Instance ID: ${WORKER_INSTANCE_ID}"
echo "  │   Public IP:   ${WORKER_PUBLIC_IP}"
echo "  │   Private IP:  ${WORKER_PRIVATE_IP}"
echo "  │   Type:        ${INSTANCE_TYPE}"
echo "  │   Disk:        ${WORKER_NODE_DISK_SIZE} GB ${EBS_VOLUME_TYPE}"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
echo "SSH Access:"
KEY_FILE="$(dirname "$0")/../../keys/${KEY_NAME}.pem"
echo "  Control Plane: ssh -i ${KEY_FILE} ubuntu@${CP_PUBLIC_IP}"
echo "  Worker Node:   ssh -i ${KEY_FILE} ubuntu@${WORKER_PUBLIC_IP}"
echo ""
echo "Export these variables for use in subsequent scripts:"
echo ""
echo "  export CP_INSTANCE_ID=\"${CP_INSTANCE_ID}\""
echo "  export WORKER_INSTANCE_ID=\"${WORKER_INSTANCE_ID}\""
echo "  export CP_PUBLIC_IP=\"${CP_PUBLIC_IP}\""
echo "  export CP_PRIVATE_IP=\"${CP_PRIVATE_IP}\""
echo "  export WORKER_PUBLIC_IP=\"${WORKER_PUBLIC_IP}\""
echo "  export WORKER_PRIVATE_IP=\"${WORKER_PRIVATE_IP}\""
echo ""

# Export for use in subsequent scripts in the same session
export CP_INSTANCE_ID
export WORKER_INSTANCE_ID
export CP_PUBLIC_IP
export CP_PRIVATE_IP
export WORKER_PUBLIC_IP
export WORKER_PRIVATE_IP
