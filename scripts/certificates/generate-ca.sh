#!/bin/bash
# =============================================================================
# Generate Certificate Authority (CA) Key Pair
# =============================================================================
# This script generates the root CA certificate and private key used to sign
# all other certificates in the Kubernetes cluster.
#
# Prerequisites:
#   - cfssl and cfssljson installed
#   - variables.env configured
#
# Output:
#   - configs/pki/ca.pem        (CA certificate)
#   - configs/pki/ca-key.pem    (CA private key)
#   - configs/pki/ca-config.json (CA signing configuration)
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

    if ! command -v cfssl &>/dev/null; then
        log_error "cfssl is not installed. Install it with:"
        log_error "  go install github.com/cloudflare/cfssl/cmd/cfssl@latest"
        log_error "  or download from https://github.com/cloudflare/cfssl/releases"
        exit 1
    fi

    if ! command -v cfssljson &>/dev/null; then
        log_error "cfssljson is not installed. Install it with:"
        log_error "  go install github.com/cloudflare/cfssl/cmd/cfssljson@latest"
        exit 1
    fi

    log_info "All prerequisites met."
}

create_output_directory() {
    log_info "Creating PKI output directory: ${PKI_DIR}"
    mkdir -p "${PKI_DIR}"
}

generate_ca_config() {
    log_info "Generating CA configuration file..."

    cat > "${PKI_DIR}/ca-config.json" <<EOF
{
  "signing": {
    "default": {
      "expiry": "${CERT_VALIDITY_DAYS}h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ],
        "expiry": "${CERT_VALIDITY_DAYS}h"
      }
    }
  }
}
EOF

    # Convert days to hours for cfssl (cfssl uses hours)
    local expiry_hours=$((CERT_VALIDITY_DAYS * 24))
    cat > "${PKI_DIR}/ca-config.json" <<EOF
{
  "signing": {
    "default": {
      "expiry": "${expiry_hours}h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ],
        "expiry": "${expiry_hours}h"
      }
    }
  }
}
EOF

    log_success "CA configuration file created: ${PKI_DIR}/ca-config.json"
}

generate_ca_certificate() {
    log_info "Generating CA certificate and private key (${CA_KEY_SIZE}-bit RSA)..."

    cat > "${PKI_DIR}/ca-csr.json" <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": ${CA_KEY_SIZE}
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "Kubernetes",
      "OU": "k8s-lab",
      "ST": "Sao Paulo"
    }
  ]
}
EOF

    cd "${PKI_DIR}"
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca

    # Clean up CSR file (not needed after generation)
    rm -f "${PKI_DIR}/ca.csr"

    log_success "CA certificate generated:"
    log_success "  Certificate: ${PKI_DIR}/ca.pem"
    log_success "  Private Key: ${PKI_DIR}/ca-key.pem"
}

verify_ca_certificate() {
    log_info "Verifying CA certificate..."

    if [[ ! -f "${PKI_DIR}/ca.pem" ]]; then
        log_error "CA certificate not found at ${PKI_DIR}/ca.pem"
        exit 1
    fi

    if [[ ! -f "${PKI_DIR}/ca-key.pem" ]]; then
        log_error "CA private key not found at ${PKI_DIR}/ca-key.pem"
        exit 1
    fi

    # Display certificate details
    log_info "CA Certificate details:"
    openssl x509 -in "${PKI_DIR}/ca.pem" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|Public-Key)"

    log_success "CA certificate verification passed."
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    log_info "=========================================="
    log_info "Generating Kubernetes CA Key Pair"
    log_info "=========================================="

    check_prerequisites
    create_output_directory
    generate_ca_config
    generate_ca_certificate
    verify_ca_certificate

    log_info "=========================================="
    log_success "CA generation complete!"
    log_info "=========================================="
    log_info ""
    log_info "Next step: Run generate-component-certs.sh to generate component certificates."
}

main "$@"
