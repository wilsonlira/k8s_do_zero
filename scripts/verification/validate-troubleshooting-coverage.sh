#!/bin/bash
# =============================================================================
# Property 5: Troubleshooting Coverage Validation
# =============================================================================
# Validates: Requirements 13.4
#
# This script identifies commands that may fail in each module and verifies
# the Troubleshooting section provides at least 2 error scenarios per command
# that may fail.
#
# "Commands that may fail" are defined as:
#   - Service start/restart commands (systemctl start/restart/enable)
#   - Installation commands (apt install, wget, curl downloads)
#   - Verification/health check commands (curl endpoints, kubectl get, etcdctl)
#   - Configuration commands that depend on external state (ssh, scp, aws cli)
#
# Each error scenario must include:
#   - Symptom (error message or observed behavior)
#   - Cause (probable reason for the failure)
#   - Resolution (commands or steps to fix)
# =============================================================================

set -u

# Determine project root (script is at scripts/verification/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DOCS_DIR="$PROJECT_ROOT/docs"

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
MODULES_CHECKED=0

# Minimum error scenarios required per failable command category
MIN_SCENARIOS=2

# =============================================================================
# Helper Functions
# =============================================================================

pass() {
  local module="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "  ${GREEN}✅ PASS${NC} [$module] $check"
}

fail() {
  local module="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "  ${RED}❌ FAIL${NC} [$module] $check"
}

info() {
  local message="$1"
  echo -e "  ${CYAN}ℹ️  INFO${NC} $message"
}

# =============================================================================
# Failable Command Detection
# =============================================================================

# Identifies categories of commands that may fail in a module's content.
# Returns a list of failable command categories found.
#
# Categories:
#   service_start    - systemctl start/restart/enable commands
#   download_install - wget, curl, apt-get install, tar extraction
#   health_check     - curl to health endpoints, etcdctl health, kubectl get
#   network_connect  - ssh, scp, aws cli commands
#   config_apply     - kubectl apply, systemctl daemon-reload
detect_failable_commands() {
  local content="$1"
  local categories=""

  # Service start/restart commands
  if echo "$content" | grep -qE 'systemctl\s+(start|restart|enable)'; then
    categories="${categories}service_start "
  fi

  # Download and installation commands
  if echo "$content" | grep -qE '(wget|curl\s+.*-[oOL]|apt-get\s+install|apt\s+install|dpkg\s+-i|tar\s+.*-x)'; then
    categories="${categories}download_install "
  fi

  # Health check / verification commands
  if echo "$content" | grep -qE '(curl\s+.*(/healthz|/livez|/readyz|:2379|:6443|:10250|:10259|:10257)|etcdctl\s+.*endpoint\s+health|kubectl\s+get|kubectl\s+cluster-info|nslookup|dig\s+)'; then
    categories="${categories}health_check "
  fi

  # Network/remote connectivity commands
  if echo "$content" | grep -qE '(ssh\s+|scp\s+|aws\s+(ec2|iam|s3))'; then
    categories="${categories}network_connect "
  fi

  # Configuration apply commands
  if echo "$content" | grep -qE '(kubectl\s+apply|kubectl\s+create|kubectl\s+delete)'; then
    categories="${categories}config_apply "
  fi

  echo "$categories"
}

# =============================================================================
# Troubleshooting Section Analysis
# =============================================================================

# Extracts the Troubleshooting section from a module README
extract_troubleshooting_section() {
  local file="$1"

  # Extract everything after "## Troubleshooting" until the next "## " section or EOF
  sed -n '/^## Troubleshooting/,/^## [^T]/p' "$file" | sed '$d' 2>/dev/null || \
  sed -n '/^## Troubleshooting/,$p' "$file" 2>/dev/null
}

# Counts the number of error scenarios (### Problema headings) in the troubleshooting section
count_error_scenarios() {
  local troubleshooting_content="$1"

  # Count headings that indicate individual error scenarios
  # Patterns: "### Problema", "### Problem", "### Error", or numbered "### Problema N:"
  local result
  result=$(echo "$troubleshooting_content" | grep -cE '^###\s+(Problema|Problem|Error|Issue)' 2>/dev/null || true)
  result=$(echo "$result" | head -1 | tr -d '[:space:]')
  if [ -z "$result" ] || ! [[ "$result" =~ ^[0-9]+$ ]]; then
    result=0
  fi
  echo "$result"
}

# Checks if troubleshooting scenarios cover a specific command category
# by looking for related keywords in the troubleshooting section
check_category_coverage() {
  local troubleshooting_content="$1"
  local category="$2"
  local count=0

  case "$category" in
    service_start)
      # Look for scenarios mentioning service start failures
      count=$(echo "$troubleshooting_content" | grep -ciE '(não inicia|fails to start|service.*fail|status.*failed|cannot start|not start|systemctl|Active:.*failed)' 2>/dev/null || true)
      ;;
    download_install)
      # Look for scenarios mentioning download/install failures
      count=$(echo "$troubleshooting_content" | grep -ciE '(download.*fail|install.*fail|not found|command not found|permission denied|wget|curl.*error|404|package)' 2>/dev/null || true)
      ;;
    health_check)
      # Look for scenarios mentioning health check failures
      count=$(echo "$troubleshooting_content" | grep -ciE '(unhealthy|health.*fail|connection refused|timeout|deadline exceeded|not ready|NotReady|endpoint.*fail|503|refused)' 2>/dev/null || true)
      ;;
    network_connect)
      # Look for scenarios mentioning network/connectivity failures
      count=$(echo "$troubleshooting_content" | grep -ciE '(connection refused|timeout|unreachable|ssh.*fail|permission denied|security group|port.*closed|cannot connect)' 2>/dev/null || true)
      ;;
    config_apply)
      # Look for scenarios mentioning configuration apply failures
      count=$(echo "$troubleshooting_content" | grep -ciE '(apply.*fail|invalid|error.*creat|not found|already exists|forbidden|unauthorized|RBAC)' 2>/dev/null || true)
      ;;
  esac

  # Ensure count is a valid integer (take first line, default to 0)
  count=$(echo "$count" | head -1 | tr -d '[:space:]')
  if [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
    count=0
  fi

  echo "$count"
}

# =============================================================================
# Main Validation Logic
# =============================================================================

echo "============================================================"
echo "Property 5: Troubleshooting Coverage Validation"
echo "Validates: Requirements 13.4"
echo "============================================================"
echo ""
echo "Minimum error scenarios required per failable command: $MIN_SCENARIOS"
echo "Docs directory: $DOCS_DIR"
echo ""

# Verify docs directory exists
if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}ERROR: Docs directory not found: $DOCS_DIR${NC}"
  exit 1
fi

# Find all module README files
MODULE_FILES=$(find "$DOCS_DIR" -maxdepth 2 -name "README.md" -path "*/docs/[0-9]*" | sort)

if [ -z "$MODULE_FILES" ]; then
  echo -e "${RED}ERROR: No module README.md files found in $DOCS_DIR${NC}"
  exit 1
fi

# Process each module
while IFS= read -r module_file; do
  MODULES_CHECKED=$((MODULES_CHECKED + 1))

  # Extract module name from path (e.g., "04-etcd")
  module_name=$(basename "$(dirname "$module_file")")

  echo ""
  echo -e "${YELLOW}--- Module: $module_name ---${NC}"

  # Read module content
  content=$(cat "$module_file")

  # 1. Check that Troubleshooting section exists
  if ! echo "$content" | grep -q '^## Troubleshooting'; then
    fail "$module_name" "Troubleshooting section not found"
    continue
  fi

  # 2. Extract troubleshooting section
  troubleshooting=$(extract_troubleshooting_section "$module_file")

  # 3. Count total error scenarios in troubleshooting
  scenario_count=$(count_error_scenarios "$troubleshooting")
  info "Total error scenarios in Troubleshooting: $scenario_count"

  # 4. Detect failable command categories in the module
  failable_categories=$(detect_failable_commands "$content")

  if [ -z "$failable_categories" ]; then
    info "No failable command categories detected — skipping"
    pass "$module_name" "No failable commands detected (module may be purely informational)"
    continue
  fi

  info "Failable command categories detected: $failable_categories"

  # 5. For each failable category, verify troubleshooting coverage
  for category in $failable_categories; do
    coverage_count=$(check_category_coverage "$troubleshooting" "$category")

    # Format category name for display
    category_display=$(echo "$category" | tr '_' ' ')

    if [ "$coverage_count" -ge "$MIN_SCENARIOS" ]; then
      pass "$module_name" "Category '$category_display': $coverage_count references found (≥ $MIN_SCENARIOS required)"
    else
      fail "$module_name" "Category '$category_display': only $coverage_count references found (≥ $MIN_SCENARIOS required)"
    fi
  done

  # 6. Verify overall minimum: at least 2 distinct error scenarios total
  if [ "$scenario_count" -ge "$MIN_SCENARIOS" ]; then
    pass "$module_name" "Overall scenario count: $scenario_count (≥ $MIN_SCENARIOS required)"
  else
    fail "$module_name" "Overall scenario count: $scenario_count (< $MIN_SCENARIOS required)"
  fi

  # 7. Verify each scenario has symptom, cause, and resolution
  # Check for structured troubleshooting entries
  symptom_count=$(echo "$troubleshooting" | grep -ciE '(Sintoma|Symptom|\*\*Sintoma|Erro:|Error:)' 2>/dev/null || true)
  symptom_count=$(echo "$symptom_count" | head -1 | tr -d '[:space:]')
  if [ -z "$symptom_count" ] || ! [[ "$symptom_count" =~ ^[0-9]+$ ]]; then symptom_count=0; fi

  cause_count=$(echo "$troubleshooting" | grep -ciE '(Causa|Cause|\*\*Causa|provável|probable)' 2>/dev/null || true)
  cause_count=$(echo "$cause_count" | head -1 | tr -d '[:space:]')
  if [ -z "$cause_count" ] || ! [[ "$cause_count" =~ ^[0-9]+$ ]]; then cause_count=0; fi

  resolution_count=$(echo "$troubleshooting" | grep -ciE '(Resolução|Resolution|\*\*Resolução|Solução|Solution|```bash)' 2>/dev/null || true)
  resolution_count=$(echo "$resolution_count" | head -1 | tr -d '[:space:]')
  if [ -z "$resolution_count" ] || ! [[ "$resolution_count" =~ ^[0-9]+$ ]]; then resolution_count=0; fi

  if [ "$symptom_count" -ge "$MIN_SCENARIOS" ]; then
    pass "$module_name" "Symptom descriptions: $symptom_count found (≥ $MIN_SCENARIOS)"
  else
    fail "$module_name" "Symptom descriptions: only $symptom_count found (≥ $MIN_SCENARIOS required)"
  fi

  if [ "$cause_count" -ge "$MIN_SCENARIOS" ]; then
    pass "$module_name" "Cause explanations: $cause_count found (≥ $MIN_SCENARIOS)"
  else
    fail "$module_name" "Cause explanations: only $cause_count found (≥ $MIN_SCENARIOS required)"
  fi

  if [ "$resolution_count" -ge "$MIN_SCENARIOS" ]; then
    pass "$module_name" "Resolution steps: $resolution_count found (≥ $MIN_SCENARIOS)"
  else
    fail "$module_name" "Resolution steps: only $resolution_count found (≥ $MIN_SCENARIOS required)"
  fi

done <<< "$MODULE_FILES"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================================"
echo "SUMMARY"
echo "============================================================"
echo "Modules checked:    $MODULES_CHECKED"
echo "Total checks:       $TOTAL_CHECKS"
echo -e "Passed:             ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:             ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ ALL CHECKS PASSED — Troubleshooting coverage is adequate.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS CHECK(S) FAILED — Troubleshooting coverage is incomplete.${NC}"
  exit 1
fi
