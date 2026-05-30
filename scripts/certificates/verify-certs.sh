#!/bin/bash
# =============================================================================
# Verify Generated Certificates
# =============================================================================
# This script validates all generated TLS certificates by checking:
#   - File existence
#   - Certificate validity (not expired)
#   - Correct issuer (signed by our CA)
#   - Correct Subject (CN and O fields)
#   - Correct Subject Alternative Names (SANs) where applicable
#   - Key size meets minimum requirements
#
# Prerequisites:
#   - openssl installed
#   - All certificates generated (run generate-ca.sh and generate-component-certs.sh)
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

# Counters for test results
TESTS_PASSED=0
TESTS_FAILED=0

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
    echo "[PASS] $1"
}

log_fail() {
    echo "[FAIL] $1" >&2
}

assert_pass() {
    local description="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "${description}"
}

assert_fail() {
    local description="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "${description}"
}

check_file_exists() {
    local file="$1"
    local description="$2"

    if [[ -f "${file}" ]]; then
        assert_pass "${description} — file exists"
    else
        assert_fail "${description} — file NOT found: ${file}"
    fi
}

check_cert_issuer() {
    local cert_file="$1"
    local description="$2"

    if [[ ! -f "${cert_file}" ]]; then
        assert_fail "${description} — cannot check issuer, file missing"
        return
    fi

    local issuer
    issuer=$(openssl x509 -in "${cert_file}" -noout -issuer 2>/dev/null)

    if echo "${issuer}" | grep -q "CN = Kubernetes"; then
        assert_pass "${description} — issuer is Kubernetes CA"
    else
        assert_fail "${description} — unexpected issuer: ${issuer}"
    fi
}

check_cert_subject() {
    local cert_file="$1"
    local expected_cn="$2"
    local expected_o="${3:-}"
    local description="$4"

    if [[ ! -f "${cert_file}" ]]; then
        assert_fail "${description} — cannot check subject, file missing"
        return
    fi

    local subject
    subject=$(openssl x509 -in "${cert_file}" -noout -subject 2>/dev/null)

    # Check CN
    if echo "${subject}" | grep -q "CN = ${expected_cn}"; then
        assert_pass "${description} — CN=${expected_cn}"
    else
        assert_fail "${description} — expected CN=${expected_cn}, got: ${subject}"
    fi

    # Check O if specified
    if [[ -n "${expected_o}" ]]; then
        if echo "${subject}" | grep -q "O = ${expected_o}"; then
            assert_pass "${description} — O=${expected_o}"
        else
            assert_fail "${description} — expected O=${expected_o}, got: ${subject}"
        fi
    fi
}

check_cert_sans() {
    local cert_file="$1"
    local description="$2"
    shift 2
    local expected_sans=("$@")

    if [[ ! -f "${cert_file}" ]]; then
        assert_fail "${description} — cannot check SANs, file missing"
        return
    fi

    local sans
    sans=$(openssl x509 -in "${cert_file}" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 || true)

    for san in "${expected_sans[@]}"; do
        if echo "${sans}" | grep -q "${san}"; then
            assert_pass "${description} — SAN contains ${san}"
        else
            assert_fail "${description} — SAN missing ${san}. SANs: ${sans}"
        fi
    done
}

check_cert_validity() {
    local cert_file="$1"
    local description="$2"

    if [[ ! -f "${cert_file}" ]]; then
        assert_fail "${description} — cannot check validity, file missing"
        return
    fi

    # Check if certificate is currently valid
    if openssl x509 -in "${cert_file}" -noout -checkend 0 2>/dev/null; then
        assert_pass "${description} — certificate is valid (not expired)"
    else
        assert_fail "${description} — certificate is EXPIRED"
    fi
}

check_key_size() {
    local cert_file="$1"
    local min_size="$2"
    local description="$3"

    if [[ ! -f "${cert_file}" ]]; then
        assert_fail "${description} — cannot check key size, file missing"
        return
    fi

    local key_size
    key_size=$(openssl x509 -in "${cert_file}" -noout -text 2>/dev/null | grep "Public-Key:" | grep -oP '\d+' || echo "0")

    if [[ "${key_size}" -ge "${min_size}" ]]; then
        assert_pass "${description} — key size ${key_size} bits >= ${min_size}"
    else
        assert_fail "${description} — key size ${key_size} bits < ${min_size} minimum"
    fi
}

check_key_matches_cert() {
    local cert_file="$1"
    local key_file="$2"
    local description="$3"

    if [[ ! -f "${cert_file}" ]] || [[ ! -f "${key_file}" ]]; then
        assert_fail "${description} — cannot verify key match, file(s) missing"
        return
    fi

    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -in "${cert_file}" -noout -modulus 2>/dev/null | md5sum)
    key_modulus=$(openssl rsa -in "${key_file}" -noout -modulus 2>/dev/null | md5sum)

    if [[ "${cert_modulus}" == "${key_modulus}" ]]; then
        assert_pass "${description} — private key matches certificate"
    else
        assert_fail "${description} — private key does NOT match certificate"
    fi
}

# -----------------------------------------------------------------------------
# Verification Functions
# -----------------------------------------------------------------------------

verify_ca() {
    log_info ""
    log_info "=== CA Certificate ==="

    check_file_exists "${PKI_DIR}/ca.pem" "CA certificate"
    check_file_exists "${PKI_DIR}/ca-key.pem" "CA private key"
    check_file_exists "${PKI_DIR}/ca-config.json" "CA config"

    # CA is self-signed, so issuer == subject
    local subject issuer
    if [[ -f "${PKI_DIR}/ca.pem" ]]; then
        subject=$(openssl x509 -in "${PKI_DIR}/ca.pem" -noout -subject 2>/dev/null)
        issuer=$(openssl x509 -in "${PKI_DIR}/ca.pem" -noout -issuer 2>/dev/null)

        if echo "${subject}" | grep -q "CN = Kubernetes"; then
            assert_pass "CA — CN=Kubernetes"
        else
            assert_fail "CA — expected CN=Kubernetes, got: ${subject}"
        fi

        check_cert_validity "${PKI_DIR}/ca.pem" "CA"
        check_key_size "${PKI_DIR}/ca.pem" "${CA_KEY_SIZE}" "CA"
        check_key_matches_cert "${PKI_DIR}/ca.pem" "${PKI_DIR}/ca-key.pem" "CA"
    fi
}

verify_admin() {
    log_info ""
    log_info "=== Admin Certificate ==="

    check_file_exists "${PKI_DIR}/admin.pem" "admin certificate"
    check_file_exists "${PKI_DIR}/admin-key.pem" "admin private key"
    check_cert_subject "${PKI_DIR}/admin.pem" "admin" "system:masters" "admin"
    check_cert_issuer "${PKI_DIR}/admin.pem" "admin"
    check_cert_validity "${PKI_DIR}/admin.pem" "admin"
    check_key_matches_cert "${PKI_DIR}/admin.pem" "${PKI_DIR}/admin-key.pem" "admin"
}

verify_kube_apiserver() {
    log_info ""
    log_info "=== kube-apiserver Certificate ==="

    check_file_exists "${PKI_DIR}/kube-apiserver.pem" "kube-apiserver certificate"
    check_file_exists "${PKI_DIR}/kube-apiserver-key.pem" "kube-apiserver private key"
    check_cert_subject "${PKI_DIR}/kube-apiserver.pem" "kube-apiserver" "" "kube-apiserver"
    check_cert_issuer "${PKI_DIR}/kube-apiserver.pem" "kube-apiserver"
    check_cert_validity "${PKI_DIR}/kube-apiserver.pem" "kube-apiserver"
    check_key_matches_cert "${PKI_DIR}/kube-apiserver.pem" "${PKI_DIR}/kube-apiserver-key.pem" "kube-apiserver"

    # Verify SANs
    if [[ -n "${CONTROL_PLANE_IP}" ]]; then
        check_cert_sans "${PKI_DIR}/kube-apiserver.pem" "kube-apiserver" \
            "kubernetes" \
            "kubernetes.default" \
            "kubernetes.default.svc" \
            "kubernetes.default.svc.cluster.local" \
            "10.96.0.1" \
            "${CONTROL_PLANE_IP}" \
            "127.0.0.1"
    else
        log_info "  Skipping SAN verification — CONTROL_PLANE_IP not set"
    fi
}

verify_etcd() {
    log_info ""
    log_info "=== etcd Certificate ==="

    check_file_exists "${PKI_DIR}/etcd.pem" "etcd certificate"
    check_file_exists "${PKI_DIR}/etcd-key.pem" "etcd private key"
    check_cert_subject "${PKI_DIR}/etcd.pem" "etcd" "" "etcd"
    check_cert_issuer "${PKI_DIR}/etcd.pem" "etcd"
    check_cert_validity "${PKI_DIR}/etcd.pem" "etcd"
    check_key_matches_cert "${PKI_DIR}/etcd.pem" "${PKI_DIR}/etcd-key.pem" "etcd"

    # Verify SANs
    if [[ -n "${CONTROL_PLANE_IP}" ]]; then
        check_cert_sans "${PKI_DIR}/etcd.pem" "etcd" \
            "${CONTROL_PLANE_IP}" \
            "127.0.0.1" \
            "localhost"
    else
        log_info "  Skipping SAN verification — CONTROL_PLANE_IP not set"
    fi
}

verify_kubelet() {
    log_info ""
    log_info "=== kubelet Certificate ==="

    check_file_exists "${PKI_DIR}/kubelet.pem" "kubelet certificate"
    check_file_exists "${PKI_DIR}/kubelet-key.pem" "kubelet private key"
    check_cert_subject "${PKI_DIR}/kubelet.pem" "system:node:${WORKER_NODE_NAME}" "system:nodes" "kubelet"
    check_cert_issuer "${PKI_DIR}/kubelet.pem" "kubelet"
    check_cert_validity "${PKI_DIR}/kubelet.pem" "kubelet"
    check_key_matches_cert "${PKI_DIR}/kubelet.pem" "${PKI_DIR}/kubelet-key.pem" "kubelet"
}

verify_kube_proxy() {
    log_info ""
    log_info "=== kube-proxy Certificate ==="

    check_file_exists "${PKI_DIR}/kube-proxy.pem" "kube-proxy certificate"
    check_file_exists "${PKI_DIR}/kube-proxy-key.pem" "kube-proxy private key"
    check_cert_subject "${PKI_DIR}/kube-proxy.pem" "system:kube-proxy" "system:node-proxier" "kube-proxy"
    check_cert_issuer "${PKI_DIR}/kube-proxy.pem" "kube-proxy"
    check_cert_validity "${PKI_DIR}/kube-proxy.pem" "kube-proxy"
    check_key_matches_cert "${PKI_DIR}/kube-proxy.pem" "${PKI_DIR}/kube-proxy-key.pem" "kube-proxy"
}

verify_kube_controller_manager() {
    log_info ""
    log_info "=== kube-controller-manager Certificate ==="

    check_file_exists "${PKI_DIR}/kube-controller-manager.pem" "kube-controller-manager certificate"
    check_file_exists "${PKI_DIR}/kube-controller-manager-key.pem" "kube-controller-manager private key"
    check_cert_subject "${PKI_DIR}/kube-controller-manager.pem" "system:kube-controller-manager" "" "kube-controller-manager"
    check_cert_issuer "${PKI_DIR}/kube-controller-manager.pem" "kube-controller-manager"
    check_cert_validity "${PKI_DIR}/kube-controller-manager.pem" "kube-controller-manager"
    check_key_matches_cert "${PKI_DIR}/kube-controller-manager.pem" "${PKI_DIR}/kube-controller-manager-key.pem" "kube-controller-manager"
}

verify_kube_scheduler() {
    log_info ""
    log_info "=== kube-scheduler Certificate ==="

    check_file_exists "${PKI_DIR}/kube-scheduler.pem" "kube-scheduler certificate"
    check_file_exists "${PKI_DIR}/kube-scheduler-key.pem" "kube-scheduler private key"
    check_cert_subject "${PKI_DIR}/kube-scheduler.pem" "system:kube-scheduler" "" "kube-scheduler"
    check_cert_issuer "${PKI_DIR}/kube-scheduler.pem" "kube-scheduler"
    check_cert_validity "${PKI_DIR}/kube-scheduler.pem" "kube-scheduler"
    check_key_matches_cert "${PKI_DIR}/kube-scheduler.pem" "${PKI_DIR}/kube-scheduler-key.pem" "kube-scheduler"
}

verify_service_account() {
    log_info ""
    log_info "=== Service Account Certificate ==="

    check_file_exists "${PKI_DIR}/service-account.pem" "service-account certificate"
    check_file_exists "${PKI_DIR}/service-account-key.pem" "service-account private key"
    check_cert_subject "${PKI_DIR}/service-account.pem" "service-accounts" "" "service-account"
    check_cert_issuer "${PKI_DIR}/service-account.pem" "service-account"
    check_cert_validity "${PKI_DIR}/service-account.pem" "service-account"
    check_key_matches_cert "${PKI_DIR}/service-account.pem" "${PKI_DIR}/service-account-key.pem" "service-account"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    log_info "=========================================="
    log_info "Verifying Kubernetes TLS Certificates"
    log_info "=========================================="
    log_info "PKI Directory: ${PKI_DIR}"

    # Check openssl is available
    if ! command -v openssl &>/dev/null; then
        log_error "openssl is not installed."
        exit 1
    fi

    # Run all verifications
    verify_ca
    verify_admin
    verify_kube_apiserver
    verify_etcd
    verify_kubelet
    verify_kube_proxy
    verify_kube_controller_manager
    verify_kube_scheduler
    verify_service_account

    # Print summary
    log_info ""
    log_info "=========================================="
    log_info "Verification Summary"
    log_info "=========================================="
    log_info "  Tests Passed: ${TESTS_PASSED}"
    log_info "  Tests Failed: ${TESTS_FAILED}"
    log_info "  Total Tests:  $((TESTS_PASSED + TESTS_FAILED))"
    log_info ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        log_success "All certificate verifications PASSED!"
        exit 0
    else
        log_fail "${TESTS_FAILED} verification(s) FAILED."
        exit 1
    fi
}

main "$@"
