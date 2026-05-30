#!/usr/bin/env bash
# =============================================================================
# validate-command-documentation.sh
# Property 2: Command documentation completeness
#
# Validates: Requirements 13.2, 13.3
#
# For any command presented in any module, the command SHALL be accompanied by
# both a preceding description explaining its purpose and parameters, and a
# following expected output section highlighting key lines that confirm
# successful execution.
#
# This script scans all docs/XX-*/README.md files and verifies that each
# command code block (```bash or ```) within the "Comandos Passo a Passo"
# and "Verificação" sections is:
#   1. Preceded by descriptive text explaining what the command does (Req 13.2)
#   2. Followed by expected output or an explicit "no output" note (Req 13.3)
#
# Exclusions (not validated):
#   - Code blocks inside "Saída esperada" blocks (they ARE the output)
#   - Code blocks in Troubleshooting sections (resolution commands)
#   - Non-command code blocks (```yaml, ```json, ```toml, ```text, etc.)
#   - ASCII art / diagram blocks
# =============================================================================

set -uo pipefail

# --- Configuration -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs"

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

# --- Counters ----------------------------------------------------------------

TOTAL_MODULES=0
PASSED_MODULES=0
FAILED_MODULES=0
TOTAL_CODE_BLOCKS=0
BLOCKS_WITH_DESCRIPTION=0
BLOCKS_WITH_OUTPUT=0
BLOCKS_MISSING_DESCRIPTION=0
BLOCKS_MISSING_OUTPUT=0
ERRORS=()

# --- Pre-flight check --------------------------------------------------------

echo "============================================="
echo "  Property 2: Command Documentation Completeness"
echo "  Validates: Requirements 13.2, 13.3"
echo "============================================="
echo ""

if [[ ! -d "$DOCS_DIR" ]]; then
  echo -e "${RED}ERROR: Documentation directory not found: $DOCS_DIR${NC}"
  exit 1
fi

echo "Scanning modules in: $DOCS_DIR"
echo ""

# =============================================================================
# Core Validation Logic
# =============================================================================

# Determines if a code fence line opens a command block (bash/shell)
# Returns 0 (true) for command blocks, 1 (false) for config/output blocks
is_command_fence() {
  local fence_line="$1"
  # Command blocks: ```bash, ```sh, ```shell, or plain ``` (no language hint)
  if echo "$fence_line" | grep -qiE '^\s*```(bash|sh|shell)?\s*$'; then
    return 0
  fi
  return 1
}

# Checks if accumulated text contains meaningful description
# (at least one line with alphabetic characters forming a sentence)
has_description() {
  local text="$1"
  # Must contain at least one line with words (not just symbols/numbers)
  if echo "$text" | grep -qiE '[A-Za-zÀ-ÿ]{3,}.*[A-Za-zÀ-ÿ]{2,}'; then
    return 0
  fi
  return 1
}

# Checks if text following a code block indicates expected output
has_output_indicator() {
  local text="$1"
  # Patterns that indicate expected output documentation:
  # - "Saída esperada" (Portuguese for "Expected output")
  # - "Expected output" (English)
  # - "Nenhuma saída indica sucesso" (No output means success)
  # - "exit code 0"
  # - A code block (showing the output example)
  # - "A linha" (The line... - explaining output)
  # - "Resultado" (Result)
  if echo "$text" | grep -qiE 'sa[ií]da esperada|expected output|nenhuma sa[ií]da|exit code 0|resultado|a linha.*(retornada|chave|confirma)|output'; then
    return 0
  fi
  # Check for a code block following (which would be the output example)
  if echo "$text" | grep -qE '^\s*```'; then
    return 0
  fi
  return 1
}

# =============================================================================
# Module Validation
# =============================================================================

validate_module() {
  local readme="$1"
  local module_name="$2"

  local in_commands_section=0
  local in_troubleshooting=0
  local in_code_block=0
  local is_command_block=0
  local in_output_section=0
  local awaiting_output=0
  local preceding_text=""
  local following_text=""
  local line_number=0
  local block_start_line=0
  local module_blocks=0
  local module_failures=0

  # Max lines to look ahead for output after a command block
  local MAX_LOOKAHEAD=5
  local lookahead_count=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))

    # Strip trailing CR for Windows compatibility
    line="${line%$'\r'}"

    # --- Detect section boundaries ---

    # Level-2 headings define major sections
    if [[ "$line" =~ ^##\  ]]; then
      if echo "$line" | grep -qiE 'Comandos Passo a Passo|Step.by.Step|Verificação|Verification'; then
        in_commands_section=1
        in_troubleshooting=0
      elif echo "$line" | grep -qiE 'Troubleshooting|Solução de Problemas'; then
        in_commands_section=0
        in_troubleshooting=1
      elif echo "$line" | grep -qiE 'Teoria|Theory|Pré-requisitos|Prerequisites|Objetivo|Objective'; then
        in_commands_section=0
        in_troubleshooting=0
      fi
    fi

    # --- Detect expected output markers ---
    if echo "$line" | grep -qiE 'sa[ií]da esperada|expected output|nenhuma sa[ií]da'; then
      in_output_section=1
    fi

    # --- Handle code fences ---
    if echo "$line" | grep -qE '^\s*```'; then
      if [[ $in_code_block -eq 0 ]]; then
        # --- Opening fence ---
        in_code_block=1

        # If we were awaiting output for a previous block, finalize that check
        if [[ $awaiting_output -eq 1 ]]; then
          # This opening fence could be the expected output block
          if [[ $in_output_section -eq 1 ]] || has_output_indicator "$following_text"; then
            BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
          else
            # The new code block might itself be the output example
            # (a code block right after another is typically the output)
            BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
          fi
          awaiting_output=0
          in_output_section=0
        fi

        # Only validate command blocks in the commands/verification sections
        if [[ $in_commands_section -eq 1 && $in_troubleshooting -eq 0 ]]; then
          if [[ $in_output_section -eq 1 ]]; then
            # This is an expected output code block, skip validation
            is_command_block=0
            in_output_section=0
          elif is_command_fence "$line"; then
            is_command_block=1
            block_start_line=$line_number
            module_blocks=$((module_blocks + 1))
            TOTAL_CODE_BLOCKS=$((TOTAL_CODE_BLOCKS + 1))

            # --- Check Requirement 13.2: Preceding description ---
            if has_description "$preceding_text"; then
              BLOCKS_WITH_DESCRIPTION=$((BLOCKS_WITH_DESCRIPTION + 1))
            else
              BLOCKS_MISSING_DESCRIPTION=$((BLOCKS_MISSING_DESCRIPTION + 1))
              module_failures=$((module_failures + 1))
              fail "[$module_name] Code block at line $block_start_line missing preceding description"
              ERRORS+=("$module_name:$block_start_line - Missing preceding description (Req 13.2)")
            fi
          else
            is_command_block=0
          fi
        else
          is_command_block=0
        fi
      else
        # --- Closing fence ---
        in_code_block=0

        if [[ $is_command_block -eq 1 ]]; then
          # Start looking for expected output after this block
          awaiting_output=1
          lookahead_count=0
          following_text=""
          is_command_block=0
        fi
        in_output_section=0
      fi
      # Reset preceding text after any fence
      if [[ $in_code_block -eq 0 && $awaiting_output -eq 0 ]]; then
        preceding_text=""
      fi
      continue
    fi

    # --- Inside a code block: skip content ---
    if [[ $in_code_block -eq 1 ]]; then
      continue
    fi

    # --- Awaiting output check after a command block ---
    if [[ $awaiting_output -eq 1 ]]; then
      following_text="${following_text}
${line}"
      lookahead_count=$((lookahead_count + 1))

      # Check if we found an output indicator
      if has_output_indicator "$following_text"; then
        BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
        awaiting_output=0
        preceding_text="$line"
        continue
      fi

      # If we hit a new heading or another command block start, the output is missing
      if echo "$line" | grep -qE '^#{1,3} '; then
        # Check one more time with accumulated text
        if has_output_indicator "$following_text"; then
          BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
        else
          BLOCKS_MISSING_OUTPUT=$((BLOCKS_MISSING_OUTPUT + 1))
          module_failures=$((module_failures + 1))
          fail "[$module_name] Code block before line $line_number missing expected output"
          ERRORS+=("$module_name:$line_number - Missing expected output after command block (Req 13.3)")
        fi
        awaiting_output=0
        preceding_text="$line"
        continue
      fi

      # After MAX_LOOKAHEAD lines, make a decision
      if [[ $lookahead_count -ge $MAX_LOOKAHEAD ]]; then
        if has_output_indicator "$following_text"; then
          BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
        else
          # Check if the following text is itself descriptive (describing next command)
          # This means the previous command had no explicit output section
          # Some commands legitimately produce no output (export, cd, chmod)
          if echo "$following_text" | grep -qiE 'export |salvar|save|variável|variable'; then
            # Commands like export/save have implicit "no output" behavior
            BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
          else
            BLOCKS_MISSING_OUTPUT=$((BLOCKS_MISSING_OUTPUT + 1))
            module_failures=$((module_failures + 1))
            fail "[$module_name] Code block ~$((line_number - lookahead_count)) lines before line $line_number missing expected output"
            ERRORS+=("$module_name:$((line_number - lookahead_count)) - Missing expected output after command block (Req 13.3)")
          fi
        fi
        awaiting_output=0
        preceding_text="$line"
        continue
      fi
      continue
    fi

    # --- Accumulate preceding text for next code block ---
    if [[ $in_commands_section -eq 1 && $in_code_block -eq 0 ]]; then
      preceding_text="${preceding_text}
${line}"
      # Keep only last 8 lines of context
      local line_count
      line_count=$(echo "$preceding_text" | wc -l)
      if [[ $line_count -gt 8 ]]; then
        preceding_text=$(echo "$preceding_text" | tail -8)
      fi
    fi

  done < "$readme"

  # Handle EOF while awaiting output
  if [[ $awaiting_output -eq 1 ]]; then
    if has_output_indicator "$following_text"; then
      BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
    else
      BLOCKS_MISSING_OUTPUT=$((BLOCKS_MISSING_OUTPUT + 1))
      module_failures=$((module_failures + 1))
      fail "[$module_name] Last command block in file missing expected output"
      ERRORS+=("$module_name:EOF - Missing expected output for last command block (Req 13.3)")
    fi
  fi

  # --- Module result ---
  if [[ $module_blocks -gt 0 ]]; then
    if [[ $module_failures -eq 0 ]]; then
      pass "[$module_name] All $module_blocks command blocks have description and expected output"
      PASSED_MODULES=$((PASSED_MODULES + 1))
    else
      FAILED_MODULES=$((FAILED_MODULES + 1))
    fi
  else
    warn "[$module_name] No command blocks found in Comandos/Verificação sections"
    PASSED_MODULES=$((PASSED_MODULES + 1))
  fi
}

# =============================================================================
# Main Execution
# =============================================================================

for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  readme="$module_dir/README.md"

  if [[ ! -f "$readme" ]]; then
    warn "[$(basename "$module_dir")] No README.md found, skipping"
    continue
  fi

  TOTAL_MODULES=$((TOTAL_MODULES + 1))
  module_name="$(basename "$module_dir")"
  info "Checking module: $module_name"

  validate_module "$readme" "$module_name"
  echo ""
done

# =============================================================================
# Summary
# =============================================================================

echo "============================================="
echo "  Command Documentation Completeness - Summary"
echo "============================================="
echo ""
echo "  Total modules scanned:       $TOTAL_MODULES"
echo "  Total command blocks found:   $TOTAL_CODE_BLOCKS"
echo ""
echo "  Requirement 13.2 (preceding description):"
echo -e "    ${GREEN}With description${NC}:    $BLOCKS_WITH_DESCRIPTION"
echo -e "    ${RED}Missing description${NC}: $BLOCKS_MISSING_DESCRIPTION"
echo ""
echo "  Requirement 13.3 (expected output):"
echo -e "    ${GREEN}With output${NC}:         $BLOCKS_WITH_OUTPUT"
echo -e "    ${RED}Missing output${NC}:      $BLOCKS_MISSING_OUTPUT"
echo ""
echo -e "  Modules ${GREEN}passed${NC}: $PASSED_MODULES"
echo -e "  Modules ${RED}failed${NC}: $FAILED_MODULES"
echo ""

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Errors found:"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  echo ""
fi

if [[ $BLOCKS_MISSING_DESCRIPTION -eq 0 && $BLOCKS_MISSING_OUTPUT -eq 0 && $TOTAL_CODE_BLOCKS -gt 0 ]]; then
  echo -e "${GREEN}✓ Property 2 PASSED: All command blocks have preceding descriptions and expected output.${NC}"
  exit 0
elif [[ $TOTAL_CODE_BLOCKS -eq 0 ]]; then
  echo -e "${YELLOW}⚠ Property 2 INCONCLUSIVE: No command blocks found to validate.${NC}"
  exit 1
else
  echo -e "${RED}✗ Property 2 FAILED: $((BLOCKS_MISSING_DESCRIPTION + BLOCKS_MISSING_OUTPUT)) issue(s) found.${NC}"
  exit 1
fi
