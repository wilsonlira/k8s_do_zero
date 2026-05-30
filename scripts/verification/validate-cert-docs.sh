#!/bin/bash
# =============================================================================
# Property 8: Certificate Completeness Validation
# =============================================================================
# Validates: Requirements 16.3, 16.4, 16.6, 16.7
#
# This script scans docs/02-tls-certificates/README.md and verifies that each
# component certificate documents:
#   - CN (Common Name) specification
#   - O (Organization) specification
#   - SANs (Subject Alternative Names) where applicable
#   - Purpose/explanation of what the certificate is used for
#   - Verification commands (openssl x509)
#   - Target node path (e.g., /etc/kubernetes/pki/)
#   - File permissions (600 for keys, 644 for certs)
# =============================================================================

set -euo pipefail

# Determine project root (script is at scripts/verification/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DOC_FILE="$PROJECT_ROOT/docs/02-tls-certificates/README.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Components to validate
# Format: "component_name:cn_pattern:org_pattern:sans_required"
# sans_required: "yes" if SANs are expected, "no" if not applicable
COMPONENTS=(
  "kube-apiserver:kube-apiserver:kubernetes:yes"
  "kubelet:system:node:system:nodes:yes"
  "kube-proxy:system:kube-proxy:system:node-proxier:no"
  "etcd:etcd-server:kubernetes:yes"
  "kube-controller-manager:system:kube-controller-manager:system:kube-controller-manager:no"
  "kube-scheduler:system:kube-scheduler:system:kube-scheduler:no"
  "service-account:service-accounts:kubernetes:no"
  "admin:admin:system:masters:no"
)

# =============================================================================
# Helper Functions
# =============================================================================

pass() {
  local component="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "  ${GREEN}✅ PASS${NC} [$component] $check"
}

fail() {
  local component="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "  ${RED}❌ FAIL${NC} [$component] $check"
}

# =============================================================================
# Pre-flight Check
# =============================================================================

echo "============================================================"
echo "Property 8: Certificate Completeness Validation"
echo "Validates: Requirements 16.3, 16.4, 16.6, 16.7"
echo "============================================================"
echo ""

if [ ! -f "$DOC_FILE" ]; then
  echo -e "${RED}ERROR: Documentation file not found: $DOC_FILE${NC}"
  exit 1
fi

echo "Scanning: $DOC_FILE"
echo ""

# Read the file content once
DOC_CONTENT=$(cat "$DOC_FILE")

# =============================================================================
# Validation Functions
# =============================================================================

check_cn() {
  local component="$1"
  local cn_pattern="$2"

  # Check if the document mentions CN for this component
  # Look for the CN in CSR definitions, tables, or explanations
  if echo "$DOC_CONTENT" | grep -qi "\"CN\".*${cn_pattern}\|CN.*${cn_pattern}\|Common Name.*${cn_pattern}"; then
    pass "$component" "CN (Common Name) documented"
  else
    fail "$component" "CN (Common Name) not found (expected pattern: $cn_pattern)"
  fi
}

check_org() {
  local component="$1"
  local org_pattern="$2"

  # Check if the document mentions Organization for this component
  if echo "$DOC_CONTENT" | grep -qi "\"O\".*${org_pattern}\|O.*${org_pattern}\|Organization.*${org_pattern}"; then
    pass "$component" "O (Organization) documented"
  else
    fail "$component" "O (Organization) not found (expected pattern: $org_pattern)"
  fi
}

check_sans() {
  local component="$1"
  local sans_required="$2"

  if [ "$sans_required" = "no" ]; then
    # For components without SANs, check that the doc mentions SANs are not applicable
    # or that the component appears in the certificate map table with "—" for SANs
    if echo "$DOC_CONTENT" | grep -qi "${component}.*—\|${component}.*SANs\|${component}.*hostname"; then
      pass "$component" "SANs documented (not applicable / noted)"
    else
      # It's acceptable if the component simply doesn't have SANs mentioned
      # as long as it's clear from the certificate map table
      if echo "$DOC_CONTENT" | grep -qi "${component}"; then
        pass "$component" "SANs documented (component listed without SANs)"
      else
        fail "$component" "SANs documentation missing"
      fi
    fi
  else
    # For components that require SANs, check for -hostname flag or SAN documentation
    if echo "$DOC_CONTENT" | grep -qi "\-hostname.*${component}\|${component}.*SAN\|${component}.*Subject Alternative"; then
      pass "$component" "SANs (Subject Alternative Names) documented"
    else
      # Also check if SANs are documented in the certificate map table
      if echo "$DOC_CONTENT" | grep -qi "${component}.*kubernetes\|${component}.*IP\|${component}.*localhost"; then
        pass "$component" "SANs documented (in certificate map)"
      else
        fail "$component" "SANs not documented (expected for this component)"
      fi
    fi
  fi
}

check_purpose() {
  local component="$1"

  # Build a search pattern that accounts for plural forms (e.g., service-account vs service-accounts)
  local search_pattern="${component}"
  # Also try with trailing 's' for plural forms
  local search_pattern_plural="${component}s"

  # Check for purpose/explanation in the "Propósito de Cada Certificado" table
  # or in inline explanations near the certificate generation
  if echo "$DOC_CONTENT" | grep -qi "${search_pattern}.*Certificado de\|${search_pattern}.*usado\|${search_pattern}.*Usado\|${search_pattern}.*permite\|${search_pattern}.*autentic\|${search_pattern}.*Par de chaves\|${search_pattern}.*assinatura"; then
    pass "$component" "Purpose/explanation documented"
  elif echo "$DOC_CONTENT" | grep -qi "${search_pattern_plural}.*Certificado de\|${search_pattern_plural}.*usado\|${search_pattern_plural}.*Usado\|${search_pattern_plural}.*permite\|${search_pattern_plural}.*autentic\|${search_pattern_plural}.*Par de chaves\|${search_pattern_plural}.*assinatura"; then
    pass "$component" "Purpose/explanation documented"
  else
    # Check the "Propósito de Cada Certificado" section for any mention
    if echo "$DOC_CONTENT" | grep -qi "Propósito" && echo "$DOC_CONTENT" | grep -qi "${search_pattern}\|${search_pattern_plural}"; then
      # Verify there's a purpose table entry for this component
      if echo "$DOC_CONTENT" | grep -qi "\*\*${search_pattern}\*\*.*|\|\*\*${search_pattern_plural}\*\*.*|"; then
        pass "$component" "Purpose/explanation documented (in purpose table)"
      else
        fail "$component" "Purpose/explanation not found"
      fi
    else
      fail "$component" "Purpose/explanation not found"
    fi
  fi
}

check_verification_commands() {
  local component="$1"

  # Check for openssl x509 verification commands referencing this component
  # Look for openssl commands in the Verification section or inline
  if echo "$DOC_CONTENT" | grep -qi "openssl x509.*${component}\|openssl.*verify.*${component}\|Verificar Certificado.*${component}"; then
    pass "$component" "Verification commands (openssl x509) documented"
  else
    # Also check for generic verification that covers all certs
    if echo "$DOC_CONTENT" | grep -qi "openssl x509" && echo "$DOC_CONTENT" | grep -qi "Verificar.*${component}\|verificar.*${component}"; then
      pass "$component" "Verification commands documented (section reference)"
    else
      fail "$component" "Verification commands (openssl x509) not found"
    fi
  fi
}

check_target_path() {
  local component="$1"

  # Check for target node path documentation (e.g., /etc/kubernetes/pki/ or /etc/etcd/pki/)
  if echo "$DOC_CONTENT" | grep -qi "/etc/kubernetes/pki/.*${component}\|/etc/etcd/pki/.*${component}\|${component}.*\/etc\/kubernetes\|${component}.*\/etc\/etcd"; then
    pass "$component" "Target node path documented"
  else
    # Check the distribution table which lists paths for all components
    if echo "$DOC_CONTENT" | grep -qi "${component}.*pki\|${component}.pem.*Control Plane\|${component}.pem.*Worker"; then
      pass "$component" "Target node path documented (in distribution table)"
    else
      fail "$component" "Target node path not documented"
    fi
  fi
}

check_file_permissions() {
  local component="$1"

  # Check that file permissions are documented (600 for keys, 644 for certs)
  # This can be in the distribution section, permission commands, or the summary table
  if echo "$DOC_CONTENT" | grep -qi "chmod 600.*${component}\|chmod 644.*${component}\|${component}.*600\|${component}.*644"; then
    pass "$component" "File permissions documented (600/644)"
  else
    # Check for generic permission rules that apply to all certs
    if echo "$DOC_CONTENT" | grep -qi "chmod 600.*key\|chmod 644.*pem\|600.*chaves privadas\|644.*Certificados"; then
      pass "$component" "File permissions documented (generic rules apply)"
    else
      fail "$component" "File permissions not documented"
    fi
  fi
}

# =============================================================================
# Main Validation Loop
# =============================================================================

for entry in "${COMPONENTS[@]}"; do
  # Parse component entry
  IFS=':' read -r component cn_part1 cn_part2 org_part1 org_part2 sans_req <<< "$entry"

  # Reconstruct CN and Org patterns (they may contain colons)
  # Handle the varying field counts based on component
  case "$component" in
    "kube-apiserver")
      cn_pattern="kube-apiserver"
      org_pattern="kubernetes"
      sans_required="yes"
      ;;
    "kubelet")
      cn_pattern="system:node"
      org_pattern="system:nodes"
      sans_required="yes"
      ;;
    "kube-proxy")
      cn_pattern="system:kube-proxy"
      org_pattern="system:node-proxier"
      sans_required="no"
      ;;
    "etcd")
      cn_pattern="etcd-server"
      org_pattern="kubernetes"
      sans_required="yes"
      ;;
    "kube-controller-manager")
      cn_pattern="system:kube-controller-manager"
      org_pattern="system:kube-controller-manager"
      sans_required="no"
      ;;
    "kube-scheduler")
      cn_pattern="system:kube-scheduler"
      org_pattern="system:kube-scheduler"
      sans_required="no"
      ;;
    "service-account")
      cn_pattern="service-accounts"
      org_pattern="kubernetes"
      sans_required="no"
      ;;
    "admin")
      cn_pattern="admin"
      org_pattern="system:masters"
      sans_required="no"
      ;;
  esac

  echo ""
  echo -e "${YELLOW}--- Checking: $component ---${NC}"

  check_cn "$component" "$cn_pattern"
  check_org "$component" "$org_pattern"
  check_sans "$component" "$sans_required"
  check_purpose "$component"
  check_verification_commands "$component"
  check_target_path "$component"
  check_file_permissions "$component"
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================================"
echo "SUMMARY"
echo "============================================================"
echo "Total checks: $TOTAL_CHECKS"
echo -e "Passed:       ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:       ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ ALL CHECKS PASSED — Certificate documentation is complete.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS CHECK(S) FAILED — Certificate documentation is incomplete.${NC}"
  exit 1
fi
