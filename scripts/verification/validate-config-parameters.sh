#!/bin/bash
# =============================================================================
# Property 3: Configuration Parameter Documentation Validation
# =============================================================================
# Validates: Requirements 2.4, 3.3, 4.4, 5.4, 6.3, 7.3, 8.3, 10.3, 11.3
#
# This script cross-references configuration files in configs/ with
# documentation in docs/ modules, verifying each parameter/flag has an
# explanation in the corresponding README.md.
#
# Property Statement:
#   "For any configuration parameter or flag used in any component's setup
#    (containerd config, etcd flags, kube-apiserver flags, kube-controller-manager
#    flags, kube-scheduler flags, kubelet parameters, kube-proxy parameters,
#    CoreDNS Corefile plugins, kubeconfig sections), the documentation SHALL
#    include an explanation of the parameter's purpose."
#
# Mapping:
#   configs/containerd/config.toml                    → docs/03-container-runtime/README.md  (Req 2.4)
#   configs/systemd/etcd.service                      → docs/04-etcd/README.md               (Req 3.3)
#   configs/systemd/kube-apiserver.service            → docs/05-kube-apiserver/README.md     (Req 4.4)
#   configs/systemd/kube-controller-manager.service   → docs/06-kube-controller-manager/README.md (Req 5.4)
#   configs/systemd/kube-scheduler.service            → docs/07-kube-scheduler/README.md     (Req 6.3)
#   configs/systemd/kubelet.service                   → docs/08-kubelet/README.md            (Req 7.3)
#   configs/systemd/kube-proxy.service                → docs/09-kube-proxy/README.md         (Req 8.3)
#   configs/coredns/coredns.yaml                      → docs/11-coredns/README.md            (Req 10.3)
#   configs/kubernetes/kubeconfig-*.yaml              → docs/12-kubectl-kubeconfig/README.md  (Req 11.3)
#
# Usage:
#   ./scripts/verification/validate-config-parameters.sh
#
# Exit codes:
#   0 - All configuration parameters are documented
#   1 - One or more parameters lack documentation
# =============================================================================

set -uo pipefail

# Determine project root (script is at scripts/verification/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Track failed items for summary
declare -a FAILED_ITEMS=()

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
  FAILED_ITEMS+=("[$component] $check")
  echo -e "  ${RED}❌ FAIL${NC} [$component] $check"
}

warn() {
  local component="$1"
  local check="$2"
  WARNINGS=$((WARNINGS + 1))
  echo -e "  ${YELLOW}⚠️  WARN${NC} [$component] $check"
}

section_header() {
  local title="$1"
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  $title${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# Extraction Functions
# =============================================================================

# Extract flags from systemd service ExecStart block
# Returns --flag-name entries from non-comment lines in ExecStart
extract_systemd_flags() {
  local service_file="$1"
  grep -v '^\s*#' "$service_file" | \
    sed -n '/^ExecStart=/,/^[A-Z]/p' | \
    grep -oP '(?<=\s)--[a-z][a-z0-9-]*' | sort -u
}

# Extract key TOML parameters from containerd config
# Returns parameter names (keys before = sign) from non-comment lines
extract_toml_params() {
  local toml_file="$1"
  grep -v '^\s*#' "$toml_file" | \
    grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*=' | \
    sed 's/^\s*//; s/\s*=.*//' | sort -u
}

# Extract CoreDNS Corefile plugins from the YAML manifest
# Returns plugin names found in the Corefile ConfigMap data
extract_corefile_plugins() {
  local yaml_file="$1"
  # Extract plugin names: lines that start with a word (after indentation)
  # within the Corefile block, excluding comments and known non-plugin lines
  sed -n '/Corefile:/,/^---/p' "$yaml_file" | \
    grep -oP '^\s{8}[a-z][a-z]*' | \
    sed 's/^\s*//' | \
    grep -v '^lameduck$\|^pods$\|^fallthrough$\|^ttl$\|^max_concurrent$' | \
    sort -u
}

# =============================================================================
# Validation Functions
# =============================================================================

# Check if a flag/parameter is documented in a README
# Searches for the flag name (with or without --) in the documentation
check_flag_documented() {
  local component="$1"
  local flag="$2"
  local doc_file="$3"

  # Remove leading -- for search flexibility
  local flag_name="${flag#--}"

  # Also create underscore variant for flexible matching
  local flag_underscore="${flag_name//-/_}"

  # Search for the flag in the documentation (case-insensitive)
  # Match: --flag-name, flag-name, or flag_name
  if grep -qi "\-\-${flag_name}\|${flag_name}\|${flag_underscore}" "$doc_file" 2>/dev/null; then
    pass "$component" "Flag '${flag}' is documented"
  else
    fail "$component" "Flag '${flag}' is NOT documented in README"
  fi
}

# Check if a TOML parameter is documented in a README
check_toml_param_documented() {
  local component="$1"
  local param="$2"
  local doc_file="$3"

  # Search case-insensitively for the parameter name
  if grep -qi "${param}" "$doc_file" 2>/dev/null; then
    pass "$component" "Parameter '${param}' is documented"
  else
    fail "$component" "Parameter '${param}' is NOT documented in README"
  fi
}

# Check if a CoreDNS plugin is documented in a README
check_plugin_documented() {
  local component="$1"
  local plugin="$2"
  local doc_file="$3"

  # Search for the plugin name as a word boundary match
  if grep -qi "\b${plugin}\b" "$doc_file" 2>/dev/null; then
    pass "$component" "Plugin '${plugin}' is documented"
  else
    fail "$component" "Plugin '${plugin}' is NOT documented in README"
  fi
}

# Check if a kubeconfig section/field is documented in a README
check_kubeconfig_section_documented() {
  local component="$1"
  local section="$2"
  local doc_file="$3"

  if grep -qi "${section}" "$doc_file" 2>/dev/null; then
    pass "$component" "Section '${section}' is documented"
  else
    fail "$component" "Section '${section}' is NOT documented in README"
  fi
}

# =============================================================================
# Main Validation
# =============================================================================

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Property 3: Configuration Parameter Documentation${NC}"
echo -e "${BOLD}  Validates: Requirements 2.4, 3.3, 4.4, 5.4, 6.3, 7.3, 8.3, 10.3, 11.3${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""
echo "This script verifies that every configuration parameter/flag in"
echo "configs/ has a corresponding explanation in the module documentation."

# =============================================================================
# 1. containerd config.toml → docs/03-container-runtime/README.md (Req 2.4)
# =============================================================================
section_header "1. containerd config.toml → 03-container-runtime (Req 2.4)"

CONFIG_FILE="$PROJECT_ROOT/configs/containerd/config.toml"
DOC_FILE="$PROJECT_ROOT/docs/03-container-runtime/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "containerd" "Config file not found: configs/containerd/config.toml"
elif [ ! -f "$DOC_FILE" ]; then
  fail "containerd" "Documentation not found: docs/03-container-runtime/README.md"
else
  # Key containerd parameters that MUST be documented per Req 2.4:
  # "explain each configuration parameter in the containerd config file,
  #  including the SystemdCgroup setting and the CRI plugin sandbox image"
  CONTAINERD_PARAMS=(
    "SystemdCgroup"
    "sandbox_image"
    "address"
    "root"
    "state"
    "bin_dir"
    "conf_dir"
    "runtime_type"
    "default_runtime_name"
  )

  for param in "${CONTAINERD_PARAMS[@]}"; do
    check_toml_param_documented "containerd" "$param" "$DOC_FILE"
  done
fi

# =============================================================================
# 2. etcd.service → docs/04-etcd/README.md (Req 3.3)
# =============================================================================
section_header "2. etcd.service → 04-etcd (Req 3.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/etcd.service"
DOC_FILE="$PROJECT_ROOT/docs/04-etcd/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "etcd" "Config file not found: configs/systemd/etcd.service"
elif [ ! -f "$DOC_FILE" ]; then
  fail "etcd" "Documentation not found: docs/04-etcd/README.md"
else
  ETCD_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  if [ -z "$ETCD_FLAGS" ]; then
    warn "etcd" "No flags extracted from etcd.service"
  else
    for flag in $ETCD_FLAGS; do
      check_flag_documented "etcd" "$flag" "$DOC_FILE"
    done
  fi
fi

# =============================================================================
# 3. kube-apiserver.service → docs/05-kube-apiserver/README.md (Req 4.4)
# =============================================================================
section_header "3. kube-apiserver.service → 05-kube-apiserver (Req 4.4)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-apiserver.service"
DOC_FILE="$PROJECT_ROOT/docs/05-kube-apiserver/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-apiserver" "Config file not found: configs/systemd/kube-apiserver.service"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-apiserver" "Documentation not found: docs/05-kube-apiserver/README.md"
else
  APISERVER_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  if [ -z "$APISERVER_FLAGS" ]; then
    warn "kube-apiserver" "No flags extracted from kube-apiserver.service"
  else
    for flag in $APISERVER_FLAGS; do
      check_flag_documented "kube-apiserver" "$flag" "$DOC_FILE"
    done
  fi
fi

# =============================================================================
# 4. kube-controller-manager.service → docs/06-kube-controller-manager/README.md (Req 5.4)
# =============================================================================
section_header "4. kube-controller-manager.service → 06-kube-controller-manager (Req 5.4)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-controller-manager.service"
DOC_FILE="$PROJECT_ROOT/docs/06-kube-controller-manager/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-controller-manager" "Config file not found: configs/systemd/kube-controller-manager.service"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-controller-manager" "Documentation not found: docs/06-kube-controller-manager/README.md"
else
  CM_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  if [ -z "$CM_FLAGS" ]; then
    warn "kube-controller-manager" "No flags extracted from kube-controller-manager.service"
  else
    for flag in $CM_FLAGS; do
      check_flag_documented "kube-controller-manager" "$flag" "$DOC_FILE"
    done
  fi
fi

# =============================================================================
# 5. kube-scheduler.service → docs/07-kube-scheduler/README.md (Req 6.3)
# =============================================================================
section_header "5. kube-scheduler.service → 07-kube-scheduler (Req 6.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-scheduler.service"
DOC_FILE="$PROJECT_ROOT/docs/07-kube-scheduler/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-scheduler" "Config file not found: configs/systemd/kube-scheduler.service"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-scheduler" "Documentation not found: docs/07-kube-scheduler/README.md"
else
  SCHED_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  if [ -z "$SCHED_FLAGS" ]; then
    warn "kube-scheduler" "No flags extracted from kube-scheduler.service"
  else
    for flag in $SCHED_FLAGS; do
      check_flag_documented "kube-scheduler" "$flag" "$DOC_FILE"
    done
  fi
fi

# =============================================================================
# 6. kubelet.service → docs/08-kubelet/README.md (Req 7.3)
# =============================================================================
section_header "6. kubelet.service → 08-kubelet (Req 7.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kubelet.service"
DOC_FILE="$PROJECT_ROOT/docs/08-kubelet/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kubelet" "Config file not found: configs/systemd/kubelet.service"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kubelet" "Documentation not found: docs/08-kubelet/README.md"
else
  KUBELET_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  if [ -z "$KUBELET_FLAGS" ]; then
    warn "kubelet" "No flags extracted from kubelet.service"
  else
    for flag in $KUBELET_FLAGS; do
      check_flag_documented "kubelet" "$flag" "$DOC_FILE"
    done
  fi
fi

# =============================================================================
# 7. kube-proxy.service → docs/09-kube-proxy/README.md (Req 8.3)
# =============================================================================
section_header "7. kube-proxy.service → 09-kube-proxy (Req 8.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-proxy.service"
DOC_FILE="$PROJECT_ROOT/docs/09-kube-proxy/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-proxy" "Config file not found: configs/systemd/kube-proxy.service"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-proxy" "Documentation not found: docs/09-kube-proxy/README.md"
else
  PROXY_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  if [ -z "$PROXY_FLAGS" ]; then
    warn "kube-proxy" "No flags extracted from kube-proxy.service"
  else
    for flag in $PROXY_FLAGS; do
      check_flag_documented "kube-proxy" "$flag" "$DOC_FILE"
    done
  fi
fi

# =============================================================================
# 8. coredns.yaml (Corefile plugins) → docs/11-coredns/README.md (Req 10.3)
# =============================================================================
section_header "8. coredns.yaml (Corefile) → 11-coredns (Req 10.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/coredns/coredns.yaml"
DOC_FILE="$PROJECT_ROOT/docs/11-coredns/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "coredns" "Config file not found: configs/coredns/coredns.yaml"
elif [ ! -f "$DOC_FILE" ]; then
  fail "coredns" "Documentation not found: docs/11-coredns/README.md"
else
  # CoreDNS Corefile plugins that must be documented per Req 10.3:
  # "explain the CoreDNS Corefile configuration, covering at minimum:
  #  kubernetes, forward, cache, errors, health, and ready"
  COREDNS_PLUGINS=(
    "kubernetes"
    "forward"
    "cache"
    "errors"
    "health"
    "ready"
    "loop"
    "reload"
    "loadbalance"
    "prometheus"
  )

  for plugin in "${COREDNS_PLUGINS[@]}"; do
    check_plugin_documented "coredns" "$plugin" "$DOC_FILE"
  done
fi

# =============================================================================
# 9. kubeconfig files → docs/12-kubectl-kubeconfig/README.md (Req 11.3)
# =============================================================================
section_header "9. kubeconfig files → 12-kubectl-kubeconfig (Req 11.3)"

DOC_FILE="$PROJECT_ROOT/docs/12-kubectl-kubeconfig/README.md"

if [ ! -f "$DOC_FILE" ]; then
  fail "kubeconfig" "Documentation not found: docs/12-kubectl-kubeconfig/README.md"
else
  # Kubeconfig structural sections that must be documented per Req 11.3:
  # "explain each section of the kubeconfig file (clusters, users, contexts)
  #  including how to define multiple contexts and set the current-context"
  KUBECONFIG_SECTIONS=(
    "clusters"
    "users"
    "contexts"
    "current-context"
    "certificate-authority"
    "client-certificate"
    "client-key"
    "server"
  )

  for section in "${KUBECONFIG_SECTIONS[@]}"; do
    check_kubeconfig_section_documented "kubeconfig" "$section" "$DOC_FILE"
  done
fi

# =============================================================================
# Summary Report
# =============================================================================

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  SUMMARY${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "  Total checks:  $TOTAL_CHECKS"
echo -e "  Passed:        ${GREEN}$PASSED_CHECKS${NC}"
echo -e "  Failed:        ${RED}$FAILED_CHECKS${NC}"
echo -e "  Warnings:      ${YELLOW}$WARNINGS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ ALL CHECKS PASSED${NC}"
  echo "   All configuration parameters/flags have corresponding documentation."
  echo ""
  exit 0
else
  PASS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
  echo -e "${RED}❌ VALIDATION FAILED${NC}"
  echo "   $FAILED_CHECKS parameter(s) lack documentation."
  echo "   Pass rate: ${PASS_RATE}% ($PASSED_CHECKS/$TOTAL_CHECKS)"
  echo ""
  echo "  Failed items:"
  for item in "${FAILED_ITEMS[@]}"; do
    echo -e "    ${RED}•${NC} $item"
  done
  echo ""
  echo "  To fix: Add explanations for the undocumented parameters in the"
  echo "  corresponding module README.md files."
  echo ""
  exit 1
fi
