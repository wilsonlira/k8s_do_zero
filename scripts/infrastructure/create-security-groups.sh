#!/bin/bash
# =============================================================================
# Create Security Groups for Kubernetes Cluster
# =============================================================================
# This script creates security groups with the required inbound rules for
# Kubernetes components to communicate. Two security groups are created:
#   1. Control Plane SG — ports for API server, etcd, scheduler, controller-manager
#   2. Worker Node SG — ports for kubelet, NodePort services, and inter-node traffic
#
# Required ports (from Requirements 1.2):
#   - 22        : SSH access
#   - 6443      : Kubernetes API server
#   - 2379-2380 : etcd client and peer communication
#   - 10250     : kubelet API
#   - 10259     : kube-scheduler
#   - 10257     : kube-controller-manager
#   - 30000-32767: NodePort services
#
# Requirements: 1.2, 1.6
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

echo "============================================="
echo " Creating Security Groups"
echo " Region: ${AWS_REGION}"
echo "============================================="

# -----------------------------------------------------------------------------
# Validate prerequisites
# -----------------------------------------------------------------------------
if [ -z "${VPC_ID:-}" ]; then
    echo "ERROR: VPC_ID is not set. Run create-vpc.sh first or export VPC_ID."
    echo "  export VPC_ID=\"vpc-xxxxxxxxx\""
    exit 1
fi

echo ""
echo "Using VPC: ${VPC_ID}"

# -----------------------------------------------------------------------------
# Step 1: Create Control Plane Security Group
# -----------------------------------------------------------------------------
# The control plane security group allows traffic to the components that run
# on the control plane node: API server, etcd, scheduler, and controller-manager.
echo ""
echo "[1/3] Creating Control Plane Security Group..."

CP_SG_ID=$(aws ec2 create-security-group \
    --group-name "${CLUSTER_NAME}-control-plane-sg" \
    --description "Security group for Kubernetes control plane node" \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${CLUSTER_NAME}-control-plane-sg},{Key=Project,Value=${CLUSTER_NAME}}]" \
    --query 'GroupId' \
    --output text)

if [ -z "${CP_SG_ID}" ]; then
    echo "ERROR: Failed to create Control Plane Security Group."
    exit 1
fi

echo "  ✓ Control Plane SG created: ${CP_SG_ID}"

# Add inbound rules for control plane
echo ""
echo "  Adding inbound rules to Control Plane SG..."

# SSH access (port 22) — allows the Learner to connect to the instance
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr "0.0.0.0/0" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=SSH}]" > /dev/null
echo "    ✓ Port 22 (SSH) — remote access"

# Kubernetes API server (port 6443) — the main entry point for all API requests
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 6443 \
    --cidr "0.0.0.0/0" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=KubeAPI}]" > /dev/null
echo "    ✓ Port 6443 (kube-apiserver) — Kubernetes API"

# etcd client communication (port 2379-2380) — used by API server to read/write cluster state
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 2379-2380 \
    --cidr "${VPC_CIDR}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=etcd}]" > /dev/null
echo "    ✓ Ports 2379-2380 (etcd) — cluster state store"

# kubelet API (port 10250) — used by API server to communicate with kubelet on this node
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 10250 \
    --cidr "${VPC_CIDR}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=Kubelet}]" > /dev/null
echo "    ✓ Port 10250 (kubelet) — node agent API"

# kube-scheduler (port 10259) — scheduler health/metrics endpoint
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 10259 \
    --cidr "${VPC_CIDR}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=Scheduler}]" > /dev/null
echo "    ✓ Port 10259 (kube-scheduler) — scheduler"

# kube-controller-manager (port 10257) — controller-manager health/metrics endpoint
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 10257 \
    --cidr "${VPC_CIDR}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=ControllerManager}]" > /dev/null
echo "    ✓ Port 10257 (kube-controller-manager) — controller manager"

# -----------------------------------------------------------------------------
# Step 2: Create Worker Node Security Group
# -----------------------------------------------------------------------------
# The worker node security group allows traffic to components running on
# worker nodes: kubelet, kube-proxy, and NodePort services.
echo ""
echo "[2/3] Creating Worker Node Security Group..."

WORKER_SG_ID=$(aws ec2 create-security-group \
    --group-name "${CLUSTER_NAME}-worker-sg" \
    --description "Security group for Kubernetes worker nodes" \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${CLUSTER_NAME}-worker-sg},{Key=Project,Value=${CLUSTER_NAME}}]" \
    --query 'GroupId' \
    --output text)

if [ -z "${WORKER_SG_ID}" ]; then
    echo "ERROR: Failed to create Worker Node Security Group."
    exit 1
fi

echo "  ✓ Worker Node SG created: ${WORKER_SG_ID}"

# Add inbound rules for worker nodes
echo ""
echo "  Adding inbound rules to Worker Node SG..."

# SSH access (port 22)
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr "0.0.0.0/0" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=SSH}]" > /dev/null
echo "    ✓ Port 22 (SSH) — remote access"

# kubelet API (port 10250) — used by API server to exec into pods, get logs, etc.
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol tcp \
    --port 10250 \
    --cidr "${VPC_CIDR}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=Kubelet}]" > /dev/null
echo "    ✓ Port 10250 (kubelet) — node agent API"

# NodePort services (ports 30000-32767) — exposes services externally
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol tcp \
    --port 30000-32767 \
    --cidr "0.0.0.0/0" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=NodePort}]" > /dev/null
echo "    ✓ Ports 30000-32767 (NodePort) — external service access"

# -----------------------------------------------------------------------------
# Step 3: Allow inter-node communication
# -----------------------------------------------------------------------------
# Kubernetes nodes need to communicate freely with each other for pod networking,
# DNS, and component communication. We allow all traffic between the two
# security groups within the VPC CIDR.
echo ""
echo "[3/3] Configuring inter-node communication..."

# Allow all traffic from control plane SG to worker SG
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol -1 \
    --source-group "${CP_SG_ID}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=FromControlPlane}]" > /dev/null
echo "  ✓ Worker allows all traffic from Control Plane SG"

# Allow all traffic from worker SG to control plane SG
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol -1 \
    --source-group "${WORKER_SG_ID}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=FromWorker}]" > /dev/null
echo "  ✓ Control Plane allows all traffic from Worker SG"

# Allow all traffic within the same security group (for multi-node scenarios)
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol -1 \
    --source-group "${CP_SG_ID}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=SelfCP}]" > /dev/null
echo "  ✓ Control Plane allows traffic from itself"

aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol -1 \
    --source-group "${WORKER_SG_ID}" \
    --region "${AWS_REGION}" \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=SelfWorker}]" > /dev/null
echo "  ✓ Worker allows traffic from itself"

# -----------------------------------------------------------------------------
# Export Resource IDs
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
echo " Security Groups Created Successfully"
echo "============================================="
echo ""
echo "Resource IDs:"
echo "  CP_SG_ID=${CP_SG_ID}"
echo "  WORKER_SG_ID=${WORKER_SG_ID}"
echo ""
echo "Control Plane SG Inbound Rules:"
echo "  - TCP 22       (0.0.0.0/0)    : SSH"
echo "  - TCP 6443     (0.0.0.0/0)    : Kubernetes API"
echo "  - TCP 2379-2380 (${VPC_CIDR}) : etcd"
echo "  - TCP 10250    (${VPC_CIDR})  : kubelet"
echo "  - TCP 10259    (${VPC_CIDR})  : kube-scheduler"
echo "  - TCP 10257    (${VPC_CIDR})  : kube-controller-manager"
echo "  - ALL from Worker SG           : inter-node"
echo ""
echo "Worker Node SG Inbound Rules:"
echo "  - TCP 22       (0.0.0.0/0)    : SSH"
echo "  - TCP 10250    (${VPC_CIDR})  : kubelet"
echo "  - TCP 30000-32767 (0.0.0.0/0) : NodePort services"
echo "  - ALL from Control Plane SG    : inter-node"
echo ""
echo "Export these variables for use in subsequent scripts:"
echo ""
echo "  export CP_SG_ID=\"${CP_SG_ID}\""
echo "  export WORKER_SG_ID=\"${WORKER_SG_ID}\""
echo ""

# Export for use in subsequent scripts in the same session
export CP_SG_ID
export WORKER_SG_ID
