#!/bin/bash
# =============================================================================
# Kubernetes Lab - Cleanup Networking Resources
# =============================================================================
# Removes VPC, subnets, internet gateway, route tables, and security groups
# created for the Kubernetes lab.
# Resources are removed in correct dependency order.
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
# Find VPC by CIDR and Name tag
# -----------------------------------------------------------------------------
find_lab_vpc() {
    echo_info "Searching for lab VPC (CIDR: ${VPC_CIDR})..."

    VPC_ID=$(aws ec2 describe-vpcs \
        --region "${AWS_REGION}" \
        --filters \
            "Name=cidr-block,Values=${VPC_CIDR}" \
            "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" \
        --query "Vpcs[0].VpcId" \
        --output text 2>/dev/null || true)

    if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
        echo_info "No lab VPC found."
        return 1
    fi

    echo_info "Found VPC: ${VPC_ID}"
    return 0
}

# -----------------------------------------------------------------------------
# Delete security groups (non-default)
# -----------------------------------------------------------------------------
delete_security_groups() {
    echo_info "Deleting security groups in VPC ${VPC_ID}..."

    SG_IDS=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text 2>/dev/null || true)

    if [[ -z "${SG_IDS}" ]]; then
        echo_info "No custom security groups found."
        return 0
    fi

    for SG_ID in ${SG_IDS}; do
        echo_info "  Deleting security group: ${SG_ID}"
        aws ec2 delete-security-group \
            --region "${AWS_REGION}" \
            --group-id "${SG_ID}" 2>/dev/null || {
            echo_warn "  Failed to delete security group ${SG_ID}. It may have dependencies."
        }
    done
}

# -----------------------------------------------------------------------------
# Delete subnets
# -----------------------------------------------------------------------------
delete_subnets() {
    echo_info "Deleting subnets in VPC ${VPC_ID}..."

    SUBNET_IDS=$(aws ec2 describe-subnets \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[*].SubnetId" \
        --output text 2>/dev/null || true)

    if [[ -z "${SUBNET_IDS}" ]]; then
        echo_info "No subnets found."
        return 0
    fi

    for SUBNET_ID in ${SUBNET_IDS}; do
        echo_info "  Deleting subnet: ${SUBNET_ID}"
        aws ec2 delete-subnet \
            --region "${AWS_REGION}" \
            --subnet-id "${SUBNET_ID}" 2>/dev/null || {
            echo_warn "  Failed to delete subnet ${SUBNET_ID}."
        }
    done
}

# -----------------------------------------------------------------------------
# Detach and delete internet gateway
# -----------------------------------------------------------------------------
delete_internet_gateway() {
    echo_info "Removing internet gateway from VPC ${VPC_ID}..."

    IGW_ID=$(aws ec2 describe-internet-gateways \
        --region "${AWS_REGION}" \
        --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
        --query "InternetGateways[0].InternetGatewayId" \
        --output text 2>/dev/null || true)

    if [[ -z "${IGW_ID}" || "${IGW_ID}" == "None" ]]; then
        echo_info "No internet gateway found."
        return 0
    fi

    echo_info "  Detaching internet gateway: ${IGW_ID}"
    aws ec2 detach-internet-gateway \
        --region "${AWS_REGION}" \
        --internet-gateway-id "${IGW_ID}" \
        --vpc-id "${VPC_ID}" 2>/dev/null || {
        echo_warn "  Failed to detach internet gateway ${IGW_ID}."
    }

    echo_info "  Deleting internet gateway: ${IGW_ID}"
    aws ec2 delete-internet-gateway \
        --region "${AWS_REGION}" \
        --internet-gateway-id "${IGW_ID}" 2>/dev/null || {
        echo_warn "  Failed to delete internet gateway ${IGW_ID}."
    }
}

# -----------------------------------------------------------------------------
# Delete custom route tables (non-main)
# -----------------------------------------------------------------------------
delete_route_tables() {
    echo_info "Deleting custom route tables in VPC ${VPC_ID}..."

    RT_IDS=$(aws ec2 describe-route-tables \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" \
        --output text 2>/dev/null || true)

    if [[ -z "${RT_IDS}" ]]; then
        echo_info "No custom route tables found."
        return 0
    fi

    for RT_ID in ${RT_IDS}; do
        echo_info "  Deleting route table: ${RT_ID}"
        aws ec2 delete-route-table \
            --region "${AWS_REGION}" \
            --route-table-id "${RT_ID}" 2>/dev/null || {
            echo_warn "  Failed to delete route table ${RT_ID}."
        }
    done
}

# -----------------------------------------------------------------------------
# Delete VPC
# -----------------------------------------------------------------------------
delete_vpc() {
    echo_info "Deleting VPC: ${VPC_ID}..."

    aws ec2 delete-vpc \
        --region "${AWS_REGION}" \
        --vpc-id "${VPC_ID}" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo_info "VPC ${VPC_ID} deleted successfully."
    else
        echo_error "Failed to delete VPC ${VPC_ID}. There may be remaining dependencies."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Delete SSH key pair
# -----------------------------------------------------------------------------
delete_key_pair() {
    echo_info "Deleting SSH key pair: ${KEY_NAME}..."

    aws ec2 describe-key-pairs \
        --region "${AWS_REGION}" \
        --key-names "${KEY_NAME}" > /dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        echo_info "Key pair '${KEY_NAME}' not found."
        return 0
    fi

    aws ec2 delete-key-pair \
        --region "${AWS_REGION}" \
        --key-name "${KEY_NAME}" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo_info "Key pair '${KEY_NAME}' deleted."
    else
        echo_warn "Failed to delete key pair '${KEY_NAME}'."
    fi

    # Remove local private key file if it exists
    if [[ -f "${HOME}/.ssh/${KEY_NAME}.pem" ]]; then
        rm -f "${HOME}/.ssh/${KEY_NAME}.pem"
        echo_info "Removed local key file: ${HOME}/.ssh/${KEY_NAME}.pem"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================="
    echo " Kubernetes Lab - Networking Cleanup"
    echo "============================================="
    echo ""

    if ! find_lab_vpc; then
        echo_info "Nothing to clean up."
        exit 0
    fi

    echo ""
    echo "The following networking resources will be removed:"
    echo "  - Security groups (non-default) in VPC ${VPC_ID}"
    echo "  - Subnets in VPC ${VPC_ID}"
    echo "  - Internet gateway attached to VPC ${VPC_ID}"
    echo "  - Custom route tables in VPC ${VPC_ID}"
    echo "  - VPC ${VPC_ID}"
    echo "  - SSH key pair: ${KEY_NAME}"
    echo ""

    # Confirmation prompt
    read -p "Are you sure you want to delete these networking resources? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo_info "Cleanup cancelled."
        exit 0
    fi

    # Delete in correct dependency order
    delete_security_groups
    delete_subnets
    delete_internet_gateway
    delete_route_tables
    delete_vpc
    delete_key_pair

    echo ""
    echo_info "Networking cleanup complete."
}

main "$@"
