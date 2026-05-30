#!/usr/bin/env bash
# =============================================================================
# validate-module-structure.sh
# Property 1: Module structure completeness
#
# Validates: Requirements 13.1
#
# Scans each docs/XX-*/README.md and verifies all required sections
# (Objetivo, Teoria, Pré-requisitos, Comandos Passo a Passo, Verificação,
# Troubleshooting) exist in correct order.
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs"

# Required sections in the expected order (Portuguese headings as used in modules)
REQUIRED_SECTIONS=(
  "Objetivo"
  "Teoria"
  "Pré-requisitos"
  "Comandos Passo a Passo"
  "Verificação"
  "Troubleshooting"
)

# --- Color output helpers ----------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}▶${NC} $1"; }

# --- Main validation logic ---------------------------------------------------

TOTAL_MODULES=0
PASSED_MODULES=0
FAILED_MODULES=0
ERRORS=()

# Find all module README files matching docs/XX-*/README.md pattern
for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  readme="$module_dir/README.md"

  if [[ ! -f "$readme" ]]; then
    warn "No README.md found in $module_dir"
    continue
  fi

  TOTAL_MODULES=$((TOTAL_MODULES + 1))
  module_name="$(basename "$module_dir")"
  info "Checking module: $module_name"

  module_passed=true
  previous_line=-1

  for section in "${REQUIRED_SECTIONS[@]}"; do
    # Search for the section as a level-2 heading (## Section Name)
    # Use grep -n to get line numbers; handle CRLF line endings with \r? pattern
    line_number=$(grep -nP "^## ${section}\r?$" "$readme" 2>/dev/null | head -1 | cut -d: -f1 || true)

    if [[ -z "$line_number" ]]; then
      fail "Missing section: '## ${section}'"
      module_passed=false
      ERRORS+=("$module_name: Missing section '## ${section}'")
    else
      # Check ordering: current section must appear after the previous one
      if [[ $previous_line -ge 0 && $line_number -le $previous_line ]]; then
        fail "Section '## ${section}' (line $line_number) is out of order (should be after line $previous_line)"
        module_passed=false
        ERRORS+=("$module_name: Section '## ${section}' is out of order")
      else
        pass "Found '## ${section}' at line $line_number"
      fi
      previous_line=$line_number
    fi
  done

  if [[ "$module_passed" == true ]]; then
    PASSED_MODULES=$((PASSED_MODULES + 1))
  else
    FAILED_MODULES=$((FAILED_MODULES + 1))
  fi

  echo ""
done

# --- Summary -----------------------------------------------------------------

echo "============================================="
echo "  Module Structure Completeness - Summary"
echo "============================================="
echo ""
echo "  Total modules scanned: $TOTAL_MODULES"
echo -e "  ${GREEN}Passed${NC}: $PASSED_MODULES"
echo -e "  ${RED}Failed${NC}: $FAILED_MODULES"
echo ""

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Errors found:"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  echo ""
fi

if [[ $FAILED_MODULES -eq 0 && $TOTAL_MODULES -gt 0 ]]; then
  echo -e "${GREEN}✓ Property 1 PASSED: All modules contain required sections in correct order.${NC}"
  exit 0
else
  echo -e "${RED}✗ Property 1 FAILED: $FAILED_MODULES module(s) have structural issues.${NC}"
  exit 1
fi
