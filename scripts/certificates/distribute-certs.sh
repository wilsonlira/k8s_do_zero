#!/bin/bash
# =============================================================================
# Distribute Certificates to Cluster Nodes
# =============================================================================
# This script copies the generated TLS certificates and keys to the correct
# nodes via SCP, setting proper file permissions.
#
# Distribution:
#   Control Plane Node receives:
#     - CA cert and key
#     - kube-apiserver cert and key
#     - etcd cert and key
#     - service-account cert and key
#     - kube-controller-manager cert and key
#     - kube-scheduler cert and key
#     - admin cert and key
#
#   Worker Node receives:
#     - CA cert (no key — workers only need to verify, not sign)
#     - kubelet cert and key
#     - kube-proxy cert and key
#
# File Permissions:
#   - Certificates (.pem): 644 (readable by all, writable by owner)
#   - Private keys (-key.pem): 600 (readable/writable by owner only)
#
# Prerequisites:
#   - All certificates generated (run generate-ca.sh and generate-component-certs.sh)
#   - SSH access to nodes configured (key pair from infrastructure provisioning)
#   - CONTROL_PLANE_IP and WORKER_NODE_IP set in variables.env
# =============================================================================

set -euo pipefail

# Source centralized variables
source "$(dirname "$0")/../../variables.env"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PKI_DIR="${PROJECT_ROOT}/configs/pki"
SSH_KEY="${PROJECT_ROOT}/keys/${KEY_NAME}.pem"
SSH_USER="ubuntu"
REMOTE_CERT_DIR="/etc/kubernetes/pki"

# SSH options for non-interactive execution
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_success() {
    echo "[SUCCESS] $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if [[ -z "${CONTROL_PLANE_IP}" ]]; then
        log_error "CONTROL_PLANE_IP is not set in variables.env."
        exit 1
    fi

    if [[ -z "${WORKER_NODE_IP}" ]]; then
        log_error "WORKER_NODE_IP is not set in variables.env."
        exit 1
    fi

    if [[ ! -f "${SSH_KEY}" ]]; then
        log_error "SSH key not found at ${SSH_KEY}"
        log_error "Ensure the key pair was created during infrastructure provisioning."
        exit 1
    fi

    # Verify required certificate files exist
    local required_certs=(
        "ca.pem" "ca-key.pem"
        "kube-apiserver.pem" "kube-apiserver-key.pem"
        "etcd.pem" "etcd-key.pem"
        "kubelet.pem" "kubelet-key.pem"
        "kube-proxy.pem" "kube-proxy-key.pem"
        "kube-controller-manager.pem" "kube-controller-manager-key.pem"
        "kube-scheduler.pem" "kube-scheduler-key.pem"
        "service-account.pem" "service-account-key.pem"
        "admin.pem" "admin-key.pem"
    )

    for cert in "${required_certs[@]}"; do
        if [[ ! -f "${PKI_DIR}/${cert}" ]]; then
            log_error "Required certificate file not found: ${PKI_DIR}/${cert}"
            log_error "Run generate-ca.sh and generate-component-certs.sh first."
            exit 1
        fi
    done

    log_info "All prerequisites met."
}

create_remote_directory() {
    local host="$1"
    local node_name="$2"

    log_info "Creating certificate directory on ${node_name} (${host})..."
    ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${host}" \
        "sudo mkdir -p ${REMOTE_CERT_DIR} && sudo chown root:root ${REMOTE_CERT_DIR} && sudo chmod 755 ${REMOTE_CERT_DIR}"
}

scp_file() {
    local file="$1"
    local host="$2"
    local remote_path="$3"
    local permissions="$4"

    # Copy file to temporary location, then move with sudo
    scp ${SSH_OPTS} -i "${SSH_KEY}" "${file}" "${SSH_USER}@${host}:/tmp/$(basename ${file})"
    ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${host}" \
        "sudo mv /tmp/$(basename ${file}) ${remote_path} && sudo chmod ${permissions} ${remote_path} && sudo chown root:root ${remote_path}"
}

distribute_to_control_plane() {
    local host="${CONTROL_PLANE_IP}"
    local node_name="${CONTROL_PLANE_NAME}"

    log_info "=========================================="
    log_info "Distributing certificates to Control Plane"
    log_info "  Host: ${host}"
    log_info "  Target: ${REMOTE_CERT_DIR}"
    log_info "=========================================="

    create_remote_directory "${host}" "${node_name}"

    # CA certificate and key
    log_info "Copying CA certificate and key..."
    scp_file "${PKI_DIR}/ca.pem" "${host}" "${REMOTE_CERT_DIR}/ca.pem" "644"
    scp_file "${PKI_DIR}/ca-key.pem" "${host}" "${REMOTE_CERT_DIR}/ca-key.pem" "600"

    # kube-apiserver certificate and key
    log_info "Copying kube-apiserver certificate and key..."
    scp_file "${PKI_DIR}/kube-apiserver.pem" "${host}" "${REMOTE_CERT_DIR}/kube-apiserver.pem" "644"
    scp_file "${PKI_DIR}/kube-apiserver-key.pem" "${host}" "${REMOTE_CERT_DIR}/kube-apiserver-key.pem" "600"

    # etcd certificate and key
    log_info "Copying etcd certificate and key..."
    scp_file "${PKI_DIR}/etcd.pem" "${host}" "${REMOTE_CERT_DIR}/etcd.pem" "644"
    scp_file "${PKI_DIR}/etcd-key.pem" "${host}" "${REMOTE_CERT_DIR}/etcd-key.pem" "600"

    # service-account certificate and key
    log_info "Copying service-account certificate and key..."
    scp_file "${PKI_DIR}/service-account.pem" "${host}" "${REMOTE_CERT_DIR}/service-account.pem" "644"
    scp_file "${PKI_DIR}/service-account-key.pem" "${host}" "${REMOTE_CERT_DIR}/service-account-key.pem" "600"

    # kube-controller-manager certificate and key
    log_info "Copying kube-controller-manager certificate and key..."
    scp_file "${PKI_DIR}/kube-controller-manager.pem" "${host}" "${REMOTE_CERT_DIR}/kube-controller-manager.pem" "644"
    scp_file "${PKI_DIR}/kube-controller-manager-key.pem" "${host}" "${REMOTE_CERT_DIR}/kube-controller-manager-key.pem" "600"

    # kube-scheduler certificate and key
    log_info "Copying kube-scheduler certificate and key..."
    scp_file "${PKI_DIR}/kube-scheduler.pem" "${host}" "${REMOTE_CERT_DIR}/kube-scheduler.pem" "644"
    scp_file "${PKI_DIR}/kube-scheduler-key.pem" "${host}" "${REMOTE_CERT_DIR}/kube-scheduler-key.pem" "600"

    # admin certificate and key
    log_info "Copying admin certificate and key..."
    scp_file "${PKI_DIR}/admin.pem" "${host}" "${REMOTE_CERT_DIR}/admin.pem" "644"
    scp_file "${PKI_DIR}/admin-key.pem" "${host}" "${REMOTE_CERT_DIR}/admin-key.pem" "600"

    log_success "All certificates distributed to Control Plane."
}

distribute_to_worker() {
    local host="${WORKER_NODE_IP}"
    local node_name="${WORKER_NODE_NAME}"

    log_info "=========================================="
    log_info "Distributing certificates to Worker Node"
    log_info "  Host: ${host}"
    log_info "  Target: ${REMOTE_CERT_DIR}"
    log_info "=========================================="

    create_remote_directory "${host}" "${node_name}"

    # CA certificate only (worker nodes verify but don't sign)
    log_info "Copying CA certificate..."
    scp_file "${PKI_DIR}/ca.pem" "${host}" "${REMOTE_CERT_DIR}/ca.pem" "644"

    # kubelet certificate and key
    log_info "Copying kubelet certificate and key..."
    scp_file "${PKI_DIR}/kubelet.pem" "${host}" "${REMOTE_CERT_DIR}/kubelet.pem" "644"
    scp_file "${PKI_DIR}/kubelet-key.pem" "${host}" "${REMOTE_CERT_DIR}/kubelet-key.pem" "600"

    # kube-proxy certificate and key
    log_info "Copying kube-proxy certificate and key..."
    scp_file "${PKI_DIR}/kube-proxy.pem" "${host}" "${REMOTE_CERT_DIR}/kube-proxy.pem" "644"
    scp_file "${PKI_DIR}/kube-proxy-key.pem" "${host}" "${REMOTE_CERT_DIR}/kube-proxy-key.pem" "600"

    log_success "All certificates distributed to Worker Node."
}

verify_remote_permissions() {
    local host="$1"
    local node_name="$2"

    log_info "Verifying file permissions on ${node_name} (${host})..."

    ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${host}" \
        "ls -la ${REMOTE_CERT_DIR}/"

    # Verify key files have restrictive permissions
    local bad_perms
    bad_perms=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${host}" \
        "find ${REMOTE_CERT_DIR} -name '*-key.pem' ! -perm 600 2>/dev/null" || true)

    if [[ -n "${bad_perms}" ]]; then
        log_error "Some key files have incorrect permissions on ${node_name}:"
        log_error "${bad_perms}"
        return 1
    fi

    log_success "File permissions verified on ${node_name}."
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    log_info "=========================================="
    log_info "Distributing Certificates to Cluster Nodes"
    log_info "=========================================="
    log_info ""

    check_prerequisites

    distribute_to_control_plane
    echo ""
    distribute_to_worker
    echo ""

    # Verify permissions on both nodes
    log_info "=========================================="
    log_info "Verifying remote file permissions"
    log_info "=========================================="
    verify_remote_permissions "${CONTROL_PLANE_IP}" "${CONTROL_PLANE_NAME}"
    verify_remote_permissions "${WORKER_NODE_IP}" "${WORKER_NODE_NAME}"

    log_info ""
    log_info "=========================================="
    log_success "Certificate distribution complete!"
    log_info "=========================================="
    log_info ""
    log_info "Control Plane (${CONTROL_PLANE_IP}) received:"
    log_info "  - ca.pem, ca-key.pem"
    log_info "  - kube-apiserver.pem, kube-apiserver-key.pem"
    log_info "  - etcd.pem, etcd-key.pem"
    log_info "  - service-account.pem, service-account-key.pem"
    log_info "  - kube-controller-manager.pem, kube-controller-manager-key.pem"
    log_info "  - kube-scheduler.pem, kube-scheduler-key.pem"
    log_info "  - admin.pem, admin-key.pem"
    log_info ""
    log_info "Worker Node (${WORKER_NODE_IP}) received:"
    log_info "  - ca.pem (certificate only, no key)"
    log_info "  - kubelet.pem, kubelet-key.pem"
    log_info "  - kube-proxy.pem, kube-proxy-key.pem"
    log_info ""
    log_info "All certificates stored at: ${REMOTE_CERT_DIR}"
    log_info "  Certificates: permissions 644"
    log_info "  Private keys: permissions 600"
}

main "$@"
