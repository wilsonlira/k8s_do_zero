#!/bin/bash
# =============================================================================
# Create VPC, Subnets, Internet Gateway, and Route Tables
# =============================================================================
# This script provisions the core networking infrastructure for the Kubernetes
# lab on AWS. It creates a VPC with a public subnet, attaches an internet
# gateway for external connectivity, and configures route tables so instances
# can reach the internet (required for package downloads during setup).
#
# Requirements: 1.2 (VPC, subnets, networking for inter-node communication)
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

echo "============================================="
echo " Creating VPC Infrastructure"
echo " Region: ${AWS_REGION}"
echo "============================================="

# -----------------------------------------------------------------------------
# Step 1: Create VPC
# -----------------------------------------------------------------------------
# The VPC (Virtual Private Cloud) provides an isolated network environment
# for our Kubernetes cluster. We use a /16 CIDR block which gives us 65,536
# IP addresses — more than enough for a lab environment.
echo ""
echo "[1/6] Creating VPC with CIDR ${VPC_CIDR}..."

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "${VPC_CIDR}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${CLUSTER_NAME}-vpc},{Key=Project,Value=${CLUSTER_NAME}}]" \
    --query 'Vpc.VpcId' \
    --output text)

if [ -z "${VPC_ID}" ]; then
    echo "ERROR: Failed to create VPC."
    exit 1
fi

echo "  ✓ VPC created: ${VPC_ID}"

# Enable DNS hostnames so instances get public DNS names
# This is required for SSH access using public DNS and for Kubernetes
# components to resolve each other by hostname.
aws ec2 modify-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --enable-dns-hostnames '{"Value": true}' \
    --region "${AWS_REGION}"

echo "  ✓ DNS hostnames enabled"

# Enable DNS support (enabled by default, but explicit for clarity)
aws ec2 modify-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --enable-dns-support '{"Value": true}' \
    --region "${AWS_REGION}"

echo "  ✓ DNS support enabled"

# -----------------------------------------------------------------------------
# Step 2: Create Subnet
# -----------------------------------------------------------------------------
# We create a single public subnet in one availability zone. For a production
# cluster you'd want multiple subnets across AZs, but for a Free Tier lab
# a single subnet keeps things simple and cost-free.
echo ""
echo "[2/6] Creating subnet with CIDR ${SUBNET_CIDR}..."

SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "${VPC_ID}" \
    --cidr-block "${SUBNET_CIDR}" \
    --region "${AWS_REGION}" \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-subnet},{Key=Project,Value=${CLUSTER_NAME}}]" \
    --query 'Subnet.SubnetId' \
    --output text)

if [ -z "${SUBNET_ID}" ]; then
    echo "ERROR: Failed to create subnet."
    exit 1
fi

echo "  ✓ Subnet created: ${SUBNET_ID}"

# Enable auto-assign public IP so instances get a public IP on launch.
# This is necessary for SSH access and for instances to download packages.
aws ec2 modify-subnet-attribute \
    --subnet-id "${SUBNET_ID}" \
    --map-public-ip-on-launch \
    --region "${AWS_REGION}"

echo "  ✓ Auto-assign public IP enabled"

# -----------------------------------------------------------------------------
# Step 3: Create Internet Gateway
# -----------------------------------------------------------------------------
# The Internet Gateway (IGW) allows instances in the VPC to communicate with
# the internet. Without it, instances cannot download packages or be accessed
# via SSH from outside the VPC.
echo ""
echo "[3/6] Creating Internet Gateway..."

IGW_ID=$(aws ec2 create-internet-gateway \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${CLUSTER_NAME}-igw},{Key=Project,Value=${CLUSTER_NAME}}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

if [ -z "${IGW_ID}" ]; then
    echo "ERROR: Failed to create Internet Gateway."
    exit 1
fi

echo "  ✓ Internet Gateway created: ${IGW_ID}"

# -----------------------------------------------------------------------------
# Step 4: Attach Internet Gateway to VPC
# -----------------------------------------------------------------------------
# The IGW must be attached to the VPC to enable internet connectivity.
echo ""
echo "[4/6] Attaching Internet Gateway to VPC..."

aws ec2 attach-internet-gateway \
    --internet-gateway-id "${IGW_ID}" \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}"

echo "  ✓ Internet Gateway attached to VPC"

# -----------------------------------------------------------------------------
# Step 5: Create Route Table and Add Route
# -----------------------------------------------------------------------------
# A route table contains rules (routes) that determine where network traffic
# is directed. We create a custom route table with a default route pointing
# to the IGW, so all outbound traffic goes to the internet.
echo ""
echo "[5/6] Creating Route Table..."

RTB_ID=$(aws ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${CLUSTER_NAME}-rtb},{Key=Project,Value=${CLUSTER_NAME}}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

if [ -z "${RTB_ID}" ]; then
    echo "ERROR: Failed to create Route Table."
    exit 1
fi

echo "  ✓ Route Table created: ${RTB_ID}"

# Add default route to Internet Gateway
# 0.0.0.0/0 means "all traffic not matching a more specific route" goes to IGW
aws ec2 create-route \
    --route-table-id "${RTB_ID}" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "${IGW_ID}" \
    --region "${AWS_REGION}" > /dev/null

echo "  ✓ Default route (0.0.0.0/0 → IGW) added"

# -----------------------------------------------------------------------------
# Step 6: Associate Route Table with Subnet
# -----------------------------------------------------------------------------
# Associate the route table with our subnet so instances in the subnet
# use our custom routes (including the internet route).
echo ""
echo "[6/6] Associating Route Table with Subnet..."

ASSOCIATION_ID=$(aws ec2 associate-route-table \
    --route-table-id "${RTB_ID}" \
    --subnet-id "${SUBNET_ID}" \
    --region "${AWS_REGION}" \
    --query 'AssociationId' \
    --output text)

echo "  ✓ Route Table associated with Subnet (${ASSOCIATION_ID})"

# -----------------------------------------------------------------------------
# Export Resource IDs
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
echo " VPC Infrastructure Created Successfully"
echo "============================================="
echo ""
echo "Resource IDs:"
echo "  VPC_ID=${VPC_ID}"
echo "  SUBNET_ID=${SUBNET_ID}"
echo "  IGW_ID=${IGW_ID}"
echo "  RTB_ID=${RTB_ID}"
echo ""
echo "Export these variables for use in subsequent scripts:"
echo ""
echo "  export VPC_ID=\"${VPC_ID}\""
echo "  export SUBNET_ID=\"${SUBNET_ID}\""
echo "  export IGW_ID=\"${IGW_ID}\""
echo "  export RTB_ID=\"${RTB_ID}\""
echo ""

# Export for use in subsequent scripts in the same session
export VPC_ID
export SUBNET_ID
export IGW_ID
export RTB_ID
