#!/bin/bash
# =============================================================================
# Kubernetes Lab - Full Cleanup
# =============================================================================
# Removes ALL AWS resources created for the Kubernetes lab in reverse
# dependency order:
#   1. EC2 instances (must be terminated before networking can be removed)
#   2. Networking resources (VPC, subnets, gateways, security groups, key pair)
#
# Sources variables.env for configuration.
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

# Script directory for sourcing sub-scripts
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
preflight_checks() {
    echo_info "Running pre-flight checks..."

    # Check AWS CLI is available
    if ! command -v aws &> /dev/null; then
        echo_error "AWS CLI is not installed or not in PATH."
        exit 1
    fi

    # Check AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        echo_error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi

    echo_info "Pre-flight checks passed."
}

# -----------------------------------------------------------------------------
# Summary of resources to be deleted
# -----------------------------------------------------------------------------
show_summary() {
    echo ""
    echo "============================================="
    echo " RESOURCES TO BE DELETED"
    echo "============================================="
    echo ""
    echo " Region: ${AWS_REGION}"
    echo ""
    echo " 1. EC2 Instances:"
    echo "    - ${CONTROL_PLANE_NAME}"
    echo "    - ${WORKER_NODE_NAME}"
    echo ""
    echo " 2. Networking:"
    echo "    - VPC (CIDR: ${VPC_CIDR})"
    echo "    - Subnet (CIDR: ${SUBNET_CIDR})"
    echo "    - Internet Gateway"
    echo "    - Route Tables"
    echo "    - Security Groups"
    echo "    - SSH Key Pair: ${KEY_NAME}"
    echo ""
    echo "============================================="
    echo ""
    echo -e "${RED}WARNING: This action is IRREVERSIBLE.${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================="
    echo " Kubernetes Lab - Full Cleanup"
    echo "============================================="
    echo ""
    echo " This script will remove ALL AWS resources"
    echo " created for the Kubernetes lab."
    echo ""

    preflight_checks
    show_summary

    # Confirmation prompt
    read -p "Are you sure you want to delete ALL lab resources? Type 'yes' to confirm: " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo_info "Cleanup cancelled."
        exit 0
    fi

    echo ""

    # Step 1: Terminate EC2 instances first (dependency: networking depends on no active instances)
    echo "============================================="
    echo " Step 1/2: Terminating EC2 Instances"
    echo "============================================="
    echo ""

    if [[ -x "${SCRIPT_DIR}/cleanup-instances.sh" ]]; then
        # Run non-interactively by piping 'yes'
        echo "yes" | "${SCRIPT_DIR}/cleanup-instances.sh" || {
            echo_warn "Instance cleanup encountered issues. Continuing with networking cleanup..."
        }
    else
        echo_error "cleanup-instances.sh not found or not executable at ${SCRIPT_DIR}/cleanup-instances.sh"
        echo_warn "Skipping instance cleanup. Attempting networking cleanup..."
    fi

    echo ""

    # Step 2: Remove networking resources
    echo "============================================="
    echo " Step 2/2: Removing Networking Resources"
    echo "============================================="
    echo ""

    if [[ -x "${SCRIPT_DIR}/cleanup-networking.sh" ]]; then
        # Run non-interactively by piping 'yes'
        echo "yes" | "${SCRIPT_DIR}/cleanup-networking.sh" || {
            echo_error "Networking cleanup encountered issues."
            echo_warn "Some resources may need to be manually deleted."
        }
    else
        echo_error "cleanup-networking.sh not found or not executable at ${SCRIPT_DIR}/cleanup-networking.sh"
        echo_error "Networking cleanup skipped."
    fi

    echo ""
    echo "============================================="
    echo_info "Full cleanup process complete."
    echo ""
    echo_info "Verify no resources remain with:"
    echo "  aws ec2 describe-instances --region ${AWS_REGION} --filters 'Name=tag:Name,Values=${CONTROL_PLANE_NAME},${WORKER_NODE_NAME}' --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' --output table"
    echo "  aws ec2 describe-vpcs --region ${AWS_REGION} --filters 'Name=cidr-block,Values=${VPC_CIDR}' --query 'Vpcs[*].VpcId' --output text"
    echo ""
}

main "$@"
