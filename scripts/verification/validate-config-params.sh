#!/bin/bash
# =============================================================================
# Property 3: Configuration Parameter Documentation Validation
# =============================================================================
# Validates: Requirements 2.4, 3.3, 4.4, 5.4, 6.3, 7.3, 8.3, 10.3, 11.3
#
# This script cross-references configuration files in configs/ with
# documentation in modules, verifying each parameter/flag has an explanation.
#
# Mapping:
#   configs/containerd/config.toml           → docs/03-container-runtime/README.md
#   configs/systemd/etcd.service             → docs/04-etcd/README.md
#   configs/systemd/kube-apiserver.service   → docs/05-kube-apiserver/README.md
#   configs/systemd/kube-controller-manager.service → docs/06-kube-controller-manager/README.md
#   configs/systemd/kube-scheduler.service   → docs/07-kube-scheduler/README.md
#   configs/systemd/kubelet.service          → docs/08-kubelet/README.md
#   configs/systemd/kube-proxy.service       → docs/09-kube-proxy/README.md
#   configs/coredns/coredns.yaml             → docs/11-coredns/README.md
#   configs/kubernetes/kubeconfig-admin.yaml  → docs/12-kubectl-kubeconfig/README.md
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
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

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

warn() {
  local component="$1"
  local check="$2"
  WARNINGS=$((WARNINGS + 1))
  echo -e "  ${YELLOW}⚠️  WARN${NC} [$component] $check"
}

section_header() {
  local title="$1"
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  $title${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# Extract flags from systemd service ExecStart block
# Extracts --flag-name only from ExecStart lines (not comments)
# =============================================================================
extract_systemd_flags() {
  local service_file="$1"
  # Only extract flags from non-comment lines within the ExecStart block
  # Filter out comment lines (starting with #) and extract --flag patterns
  grep -v '^\s*#' "$service_file" | \
    sed -n '/^ExecStart=/,/^[A-Z]/p' | \
    grep -oP '(?<=\s)--[a-z][a-z0-9-]*' | sort -u
}

# =============================================================================
# Extract key TOML parameters from containerd config
# Extracts parameter names (keys before = sign)
# =============================================================================
extract_toml_params() {
  local toml_file="$1"
  # Extract key names from TOML (lines with key = value, excluding section headers)
  grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*=' "$toml_file" | \
    sed 's/^\s*//; s/\s*=.*//' | sort -u
}

# =============================================================================
# Extract CoreDNS Corefile plugins
# Extracts plugin names from the Corefile section in the YAML
# =============================================================================
extract_corefile_plugins() {
  local yaml_file="$1"
  # Extract plugin names from Corefile (words at the start of lines within the Corefile block)
  # CoreDNS plugins are single words at the beginning of lines inside the .:53 block
  grep -oP '^\s{8}[a-z]+' "$yaml_file" | sed 's/^\s*//' | sort -u
}

# =============================================================================
# Extract kubeconfig sections
# Extracts the main structural sections from kubeconfig YAML
# =============================================================================
extract_kubeconfig_sections() {
  local yaml_file="$1"
  # Extract top-level keys and important nested keys
  grep -E '^(apiVersion|kind|clusters|users|contexts|current-context):' "$yaml_file" | \
    sed 's/:.*//' | sort -u
}

# =============================================================================
# Check if a flag/parameter is documented in a README
# Searches for the flag name (with or without --) in the documentation
# =============================================================================
check_flag_documented() {
  local component="$1"
  local flag="$2"
  local doc_file="$3"

  # Remove leading -- for search flexibility
  local flag_name="${flag#--}"

  # Search for the flag in the documentation (case-insensitive)
  # Look for: --flag-name, flag-name, flag_name (underscore variant)
  local flag_underscore="${flag_name//-/_}"

  if grep -qi "\-\-${flag_name}\|${flag_name}\|${flag_underscore}" "$doc_file" 2>/dev/null; then
    pass "$component" "Flag '$flag' documented"
  else
    fail "$component" "Flag '$flag' NOT documented in README"
  fi
}

# =============================================================================
# Check if a TOML parameter is documented in a README
# =============================================================================
check_toml_param_documented() {
  local component="$1"
  local param="$2"
  local doc_file="$3"

  if grep -qi "${param}" "$doc_file" 2>/dev/null; then
    pass "$component" "Parameter '$param' documented"
  else
    fail "$component" "Parameter '$param' NOT documented in README"
  fi
}

# =============================================================================
# Check if a CoreDNS plugin is documented in a README
# =============================================================================
check_plugin_documented() {
  local component="$1"
  local plugin="$2"
  local doc_file="$3"

  # Search for the plugin name in the documentation
  if grep -qi "\b${plugin}\b" "$doc_file" 2>/dev/null; then
    pass "$component" "Plugin '$plugin' documented"
  else
    fail "$component" "Plugin '$plugin' NOT documented in README"
  fi
}

# =============================================================================
# Check if a kubeconfig section is documented in a README
# =============================================================================
check_kubeconfig_section_documented() {
  local component="$1"
  local section="$2"
  local doc_file="$3"

  if grep -qi "${section}" "$doc_file" 2>/dev/null; then
    pass "$component" "Section '$section' documented"
  else
    fail "$component" "Section '$section' NOT documented in README"
  fi
}

# =============================================================================
# Pre-flight Check
# =============================================================================

echo "============================================================"
echo "Property 3: Configuration Parameter Documentation"
echo "Validates: Requirements 2.4, 3.3, 4.4, 5.4, 6.3, 7.3, 8.3, 10.3, 11.3"
echo "============================================================"
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# =============================================================================
# 1. Containerd config.toml → docs/03-container-runtime/README.md (Req 2.4)
# =============================================================================
section_header "containerd config.toml → 03-container-runtime (Req 2.4)"

CONFIG_FILE="$PROJECT_ROOT/configs/containerd/config.toml"
DOC_FILE="$PROJECT_ROOT/docs/03-container-runtime/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "containerd" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "containerd" "Documentation not found: $DOC_FILE"
else
  # Key containerd parameters that MUST be documented
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
section_header "etcd.service → 04-etcd (Req 3.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/etcd.service"
DOC_FILE="$PROJECT_ROOT/docs/04-etcd/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "etcd" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "etcd" "Documentation not found: $DOC_FILE"
else
  # Extract flags from etcd service file
  ETCD_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  for flag in $ETCD_FLAGS; do
    check_flag_documented "etcd" "$flag" "$DOC_FILE"
  done
fi

# =============================================================================
# 3. kube-apiserver.service → docs/05-kube-apiserver/README.md (Req 4.4)
# =============================================================================
section_header "kube-apiserver.service → 05-kube-apiserver (Req 4.4)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-apiserver.service"
DOC_FILE="$PROJECT_ROOT/docs/05-kube-apiserver/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-apiserver" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-apiserver" "Documentation not found: $DOC_FILE"
else
  APISERVER_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  for flag in $APISERVER_FLAGS; do
    check_flag_documented "kube-apiserver" "$flag" "$DOC_FILE"
  done
fi

# =============================================================================
# 4. kube-controller-manager.service → docs/06-kube-controller-manager/README.md (Req 5.4)
# =============================================================================
section_header "kube-controller-manager.service → 06-kube-controller-manager (Req 5.4)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-controller-manager.service"
DOC_FILE="$PROJECT_ROOT/docs/06-kube-controller-manager/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-controller-manager" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-controller-manager" "Documentation not found: $DOC_FILE"
else
  CM_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  for flag in $CM_FLAGS; do
    check_flag_documented "kube-controller-manager" "$flag" "$DOC_FILE"
  done
fi

# =============================================================================
# 5. kube-scheduler.service → docs/07-kube-scheduler/README.md (Req 6.3)
# =============================================================================
section_header "kube-scheduler.service → 07-kube-scheduler (Req 6.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-scheduler.service"
DOC_FILE="$PROJECT_ROOT/docs/07-kube-scheduler/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-scheduler" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-scheduler" "Documentation not found: $DOC_FILE"
else
  SCHED_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  for flag in $SCHED_FLAGS; do
    check_flag_documented "kube-scheduler" "$flag" "$DOC_FILE"
  done
fi

# =============================================================================
# 6. kubelet.service → docs/08-kubelet/README.md (Req 7.3)
# =============================================================================
section_header "kubelet.service → 08-kubelet (Req 7.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kubelet.service"
DOC_FILE="$PROJECT_ROOT/docs/08-kubelet/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kubelet" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kubelet" "Documentation not found: $DOC_FILE"
else
  KUBELET_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  for flag in $KUBELET_FLAGS; do
    check_flag_documented "kubelet" "$flag" "$DOC_FILE"
  done
fi

# =============================================================================
# 7. kube-proxy.service → docs/09-kube-proxy/README.md (Req 8.3)
# =============================================================================
section_header "kube-proxy.service → 09-kube-proxy (Req 8.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/systemd/kube-proxy.service"
DOC_FILE="$PROJECT_ROOT/docs/09-kube-proxy/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "kube-proxy" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "kube-proxy" "Documentation not found: $DOC_FILE"
else
  PROXY_FLAGS=$(extract_systemd_flags "$CONFIG_FILE")

  for flag in $PROXY_FLAGS; do
    check_flag_documented "kube-proxy" "$flag" "$DOC_FILE"
  done
fi

# =============================================================================
# 8. coredns.yaml → docs/11-coredns/README.md (Req 10.3)
# =============================================================================
section_header "coredns.yaml → 11-coredns (Req 10.3)"

CONFIG_FILE="$PROJECT_ROOT/configs/coredns/coredns.yaml"
DOC_FILE="$PROJECT_ROOT/docs/11-coredns/README.md"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "coredns" "Config file not found: $CONFIG_FILE"
elif [ ! -f "$DOC_FILE" ]; then
  fail "coredns" "Documentation not found: $DOC_FILE"
else
  # CoreDNS Corefile plugins that must be documented
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
# 9. kubeconfig-admin.yaml → docs/12-kubectl-kubeconfig/README.md (Req 11.3)
# =============================================================================
section_header "kubeconfig files → 12-kubectl-kubeconfig (Req 11.3)"

DOC_FILE="$PROJECT_ROOT/docs/12-kubectl-kubeconfig/README.md"

if [ ! -f "$DOC_FILE" ]; then
  fail "kubeconfig" "Documentation not found: $DOC_FILE"
else
  # Kubeconfig structural sections that must be documented
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
# Summary
# =============================================================================

echo ""
echo "============================================================"
echo "SUMMARY"
echo "============================================================"
echo "Total checks:  $TOTAL_CHECKS"
echo -e "Passed:        ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:        ${RED}$FAILED_CHECKS${NC}"
echo -e "Warnings:      ${YELLOW}$WARNINGS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ ALL CHECKS PASSED — All configuration parameters are documented.${NC}"
  exit 0
else
  PASS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
  echo -e "${RED}❌ $FAILED_CHECKS CHECK(S) FAILED — Some configuration parameters lack documentation.${NC}"
  echo -e "   Pass rate: ${PASS_RATE}% ($PASSED_CHECKS/$TOTAL_CHECKS)"
  exit 1
fi
