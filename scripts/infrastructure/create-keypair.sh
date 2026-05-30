#!/bin/bash
# =============================================================================
# Create SSH Key Pair for EC2 Instance Access
# =============================================================================
# This script generates an SSH key pair in AWS and saves the private key
# locally. The key pair is used to SSH into the EC2 instances for installing
# and configuring Kubernetes components.
#
# The private key file is saved with restricted permissions (400) to prevent
# unauthorized access and to satisfy SSH client requirements.
#
# Requirements: 1.6 (SSH key pair and security group rules for SSH access)
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

echo "============================================="
echo " Creating SSH Key Pair"
echo " Key Name: ${KEY_NAME}"
echo " Region: ${AWS_REGION}"
echo "============================================="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
KEY_DIR="$(dirname "$0")/../../keys"
KEY_FILE="${KEY_DIR}/${KEY_NAME}.pem"

# -----------------------------------------------------------------------------
# Step 1: Create keys directory
# -----------------------------------------------------------------------------
echo ""
echo "[1/3] Creating keys directory..."

mkdir -p "${KEY_DIR}"
echo "  ✓ Directory created: ${KEY_DIR}"

# -----------------------------------------------------------------------------
# Step 2: Check if key pair already exists
# -----------------------------------------------------------------------------
echo ""
echo "[2/3] Checking for existing key pair..."

EXISTING_KEY=$(aws ec2 describe-key-pairs \
    --key-names "${KEY_NAME}" \
    --region "${AWS_REGION}" \
    --query 'KeyPairs[0].KeyPairId' \
    --output text 2>/dev/null || echo "None")

if [ "${EXISTING_KEY}" != "None" ] && [ -n "${EXISTING_KEY}" ]; then
    echo "  ⚠ Key pair '${KEY_NAME}' already exists (${EXISTING_KEY})."
    echo ""
    echo "  Options:"
    echo "    1. Use the existing key pair (ensure you have the private key)"
    echo "    2. Delete and recreate:"
    echo "       aws ec2 delete-key-pair --key-name ${KEY_NAME} --region ${AWS_REGION}"
    echo "       Then re-run this script."
    echo ""

    if [ -f "${KEY_FILE}" ]; then
        echo "  ✓ Private key file found at: ${KEY_FILE}"
        echo "  Skipping key pair creation."
        export KEY_NAME
        export KEY_FILE
        exit 0
    else
        echo "  ✗ Private key file NOT found at: ${KEY_FILE}"
        echo "    You must delete the existing key pair and recreate it."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Step 3: Create new key pair
# -----------------------------------------------------------------------------
# AWS generates an RSA 2048-bit key pair. The private key is returned only
# once during creation — it cannot be retrieved later. We save it immediately
# to a local file with restricted permissions.
echo ""
echo "[3/3] Creating new key pair..."

aws ec2 create-key-pair \
    --key-name "${KEY_NAME}" \
    --key-type rsa \
    --key-format pem \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=${KEY_NAME}},{Key=Project,Value=${CLUSTER_NAME}}]" \
    --query 'KeyMaterial' \
    --output text > "${KEY_FILE}"

if [ ! -s "${KEY_FILE}" ]; then
    echo "ERROR: Failed to create key pair or save private key."
    exit 1
fi

# Set restrictive permissions on the private key file
# SSH requires the private key to not be accessible by others (mode 400)
chmod 400 "${KEY_FILE}"

echo "  ✓ Key pair created: ${KEY_NAME}"
echo "  ✓ Private key saved: ${KEY_FILE}"
echo "  ✓ Permissions set to 400 (owner read-only)"

# -----------------------------------------------------------------------------
# Export Resource IDs
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
echo " SSH Key Pair Created Successfully"
echo "============================================="
echo ""
echo "Key Pair Details:"
echo "  KEY_NAME=${KEY_NAME}"
echo "  KEY_FILE=${KEY_FILE}"
echo ""
echo "To SSH into instances after creation:"
echo "  ssh -i ${KEY_FILE} ubuntu@<INSTANCE_PUBLIC_IP>"
echo ""
echo "IMPORTANT: Keep the private key file safe. If lost, you will need to"
echo "create a new key pair and update the instances."
echo ""
echo "Export these variables for use in subsequent scripts:"
echo ""
echo "  export KEY_NAME=\"${KEY_NAME}\""
echo "  export KEY_FILE=\"${KEY_FILE}\""
echo ""

# Export for use in subsequent scripts in the same session
export KEY_NAME
export KEY_FILE
