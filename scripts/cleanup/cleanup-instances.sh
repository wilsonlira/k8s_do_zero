#!/bin/bash
# =============================================================================
# Kubernetes Lab - Cleanup EC2 Instances
# =============================================================================
# Terminates all EC2 instances created for the Kubernetes lab.
# Sources variables.env for configuration.
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Find lab instances by Name tag
# -----------------------------------------------------------------------------
find_lab_instances() {
    echo_info "Searching for lab EC2 instances..."

    INSTANCE_IDS=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters \
            "Name=tag:Name,Values=${CONTROL_PLANE_NAME},${WORKER_NODE_NAME}" \
            "Name=instance-state-name,Values=running,stopped,pending" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text 2>/dev/null || true)

    if [[ -z "${INSTANCE_IDS}" ]]; then
        echo_info "No lab instances found."
        return 1
    fi

    echo_info "Found instances: ${INSTANCE_IDS}"
    return 0
}

# -----------------------------------------------------------------------------
# Display instance details before termination
# -----------------------------------------------------------------------------
display_instances() {
    echo ""
    echo "Instances to be terminated:"
    echo "----------------------------"
    aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --instance-ids ${INSTANCE_IDS} \
        --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value|[0],State.Name,PublicIpAddress]" \
        --output table 2>/dev/null || true
    echo ""
}

# -----------------------------------------------------------------------------
# Terminate instances
# -----------------------------------------------------------------------------
terminate_instances() {
    echo_info "Terminating instances: ${INSTANCE_IDS}"

    aws ec2 terminate-instances \
        --region "${AWS_REGION}" \
        --instance-ids ${INSTANCE_IDS} \
        --output text > /dev/null

    if [[ $? -ne 0 ]]; then
        echo_error "Failed to terminate instances."
        return 1
    fi

    echo_info "Terminate command sent. Waiting for instances to terminate..."

    aws ec2 wait instance-terminated \
        --region "${AWS_REGION}" \
        --instance-ids ${INSTANCE_IDS} 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo_info "All instances terminated successfully."
    else
        echo_warn "Timeout waiting for termination. Instances may still be shutting down."
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================="
    echo " Kubernetes Lab - EC2 Instance Cleanup"
    echo "============================================="
    echo ""

    if ! find_lab_instances; then
        echo_info "Nothing to clean up."
        exit 0
    fi

    display_instances

    # Confirmation prompt
    read -p "Are you sure you want to terminate these instances? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo_info "Cleanup cancelled."
        exit 0
    fi

    terminate_instances

    echo ""
    echo_info "Instance cleanup complete."
}

main "$@"
