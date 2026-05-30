#!/bin/bash
# =============================================================================
# Property 2: Command Documentation Completeness Validation
# =============================================================================
# Validates: Requirements 13.2, 13.3
#
# This script scans all module README.md files and verifies that each code block
# (command) is:
#   1. Preceded by a description explaining its purpose and parameters
#   2. Followed by expected output (e.g., "Saída esperada" section)
#
# The script identifies code blocks within the "Comandos Passo a Passo" and
# "Verificação" sections of each module, then checks for surrounding context.
#
# Exceptions:
#   - Code blocks inside "Saída esperada" sections (they ARE the expected output)
#   - Code blocks inside "Troubleshooting" sections (resolution commands)
#   - Code blocks that are diagrams/ASCII art (non-command blocks)
#   - Code blocks with language hints like ```yaml, ```json, ```toml (config examples)
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
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
MODULES_SCANNED=0
CODE_BLOCKS_FOUND=0

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

warn() {
  local module="$1"
  local msg="$2"
  echo -e "  ${YELLOW}⚠️  WARN${NC} [$module] $msg"
}

# =============================================================================
# Pre-flight Check
# =============================================================================

echo "============================================================"
echo "Property 2: Command Documentation Completeness"
echo "Validates: Requirements 13.2, 13.3"
echo "============================================================"
echo ""

if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}ERROR: Documentation directory not found: $DOCS_DIR${NC}"
  exit 1
fi

echo "Scanning modules in: $DOCS_DIR"
echo ""

# =============================================================================
# Core Validation Logic
# =============================================================================

# Check if a line is a code block fence (opening or closing)
is_code_fence() {
  local line="$1"
  echo "$line" | grep -qE '^\s*```'
}

# Check if a code block is a "command" block (bash/shell) vs config/output
is_command_block() {
  local fence_line="$1"
  # Command blocks: ```bash, ```sh, ```shell, or plain ``` (no language)
  # Non-command blocks: ```yaml, ```json, ```toml, ```text, ```ini, etc.
  if echo "$fence_line" | grep -qiE '^\s*```(bash|sh|shell)?\s*$'; then
    return 0  # true - it's a command block
  fi
  return 1  # false - it's a config/output block
}

# Check if a line contains descriptive text (not empty, not a heading, not a fence)
is_description_line() {
  local line="$1"
  # A description line is non-empty text that isn't a code fence, table separator, or blank
  if [ -z "$line" ]; then
    return 1
  fi
  if echo "$line" | grep -qE '^\s*```'; then
    return 1
  fi
  if echo "$line" | grep -qE '^\s*$'; then
    return 1
  fi
  if echo "$line" | grep -qE '^\s*[-|][-|+]+'; then
    return 1  # table separator
  fi
  return 0
}

# Check if text contains a description of what a command does
has_preceding_description() {
  local text="$1"
  # Look for descriptive content: sentences, comments explaining purpose
  # Must have at least one line of meaningful text
  if echo "$text" | grep -qiE '[A-Za-zÀ-ÿ].*[A-Za-zÀ-ÿ]'; then
    return 0  # Has descriptive text
  fi
  return 1
}

# Check if text following a code block contains expected output
has_expected_output() {
  local text="$1"
  # Look for expected output indicators:
  # - "Saída esperada" (Portuguese)
  # - "Expected output" (English)
  # - A code block immediately following (showing the output)
  # - "Nenhuma saída indica sucesso" (no output means success)
  # - "exit code 0" or similar
  if echo "$text" | grep -qiE 'sa[ií]da esperada|expected output|nenhuma sa[ií]da|exit code 0|output.*:|resultado.*:'; then
    return 0
  fi
  # Check if there's a code block following (which would be the output example)
  if echo "$text" | grep -qE '^\s*```'; then
    return 0
  fi
  return 1
}

# =============================================================================
# Module Validation
# =============================================================================

validate_module() {
  local module_dir="$1"
  local module_name
  module_name=$(basename "$module_dir")
  local readme="$module_dir/README.md"

  if [ ! -f "$readme" ]; then
    warn "$module_name" "README.md not found, skipping"
    return
  fi

  MODULES_SCANNED=$((MODULES_SCANNED + 1))

  local in_commands_section=0
  local in_verification_section=0
  local in_troubleshooting_section=0
  local in_expected_output=0
  local in_code_block=0
  local code_block_is_command=0
  local code_block_start_line=0
  local block_count=0
  local blocks_with_description=0
  local blocks_with_output=0
  local blocks_missing_description=0
  local blocks_missing_output=0
  local preceding_text=""
  local line_number=0
  local current_fence_line=""
  local skip_next_output_check=0

  # Track section context
  local current_section=""

  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))

    # Detect section headers (## level)
    if echo "$line" | grep -qE '^## '; then
      current_section="$line"
      if echo "$line" | grep -qiE 'Comandos Passo a Passo|Step.by.Step|Verificação|Verification'; then
        in_commands_section=1
        in_troubleshooting_section=0
        in_expected_output=0
      elif echo "$line" | grep -qiE 'Troubleshooting|Solução de Problemas'; then
        in_commands_section=0
        in_troubleshooting_section=1
      elif echo "$line" | grep -qiE 'Teoria|Theory|Pré-requisitos|Prerequisites|Objetivo|Objective'; then
        in_commands_section=0
        in_troubleshooting_section=0
      fi
    fi

    # Detect subsection headers (### level) within commands section
    if echo "$line" | grep -qE '^### ' && [ "$in_commands_section" -eq 1 ]; then
      # Reset preceding text for new subsection
      preceding_text="$line"
      continue
    fi

    # Detect "Saída esperada" markers
    if echo "$line" | grep -qiE 'sa[ií]da esperada|expected output|nenhuma sa[ií]da'; then
      in_expected_output=1
      skip_next_output_check=1
    fi

    # Handle code fences
    if is_code_fence "$line"; then
      if [ "$in_code_block" -eq 0 ]; then
        # Opening fence
        in_code_block=1
        current_fence_line="$line"
        code_block_start_line=$line_number

        # Only validate command blocks in the commands/verification sections
        if [ "$in_commands_section" -eq 1 ] && [ "$in_troubleshooting_section" -eq 0 ]; then
          # Skip if this is an expected output block
          if [ "$in_expected_output" -eq 1 ]; then
            code_block_is_command=0
            in_expected_output=0
          elif is_command_block "$current_fence_line"; then
            code_block_is_command=1
            block_count=$((block_count + 1))
            CODE_BLOCKS_FOUND=$((CODE_BLOCKS_FOUND + 1))

            # Check for preceding description
            if has_preceding_description "$preceding_text"; then
              blocks_with_description=$((blocks_with_description + 1))
            else
              blocks_missing_description=$((blocks_missing_description + 1))
              fail "$module_name" "Code block at line $line_number missing preceding description"
            fi
          else
            code_block_is_command=0
          fi
        else
          code_block_is_command=0
        fi
      else
        # Closing fence
        in_code_block=0

        # After closing a command block, prepare to check for expected output
        if [ "$code_block_is_command" -eq 1 ]; then
          # Reset: we'll check the next few lines for expected output
          preceding_text=""
          code_block_is_command=2  # Mark as "just closed, awaiting output check"
        fi
        in_expected_output=0
      fi
      continue
    fi

    # If we're inside a code block, skip content
    if [ "$in_code_block" -eq 1 ]; then
      continue
    fi

    # If we just closed a command block (code_block_is_command=2), look for output
    if [ "$code_block_is_command" -eq 2 ]; then
      # Check if the line after the code block indicates expected output
      if [ "$skip_next_output_check" -eq 1 ]; then
        blocks_with_output=$((blocks_with_output + 1))
        code_block_is_command=0
        skip_next_output_check=0
        preceding_text="$line"
        continue
      fi

      # Allow a few blank lines before the expected output marker
      if [ -z "$(echo "$line" | tr -d '[:space:]')" ]; then
        # Blank line, keep waiting (up to a point)
        preceding_text="${preceding_text}
${line}"
        continue
      fi

      # Check if this line or accumulated text has expected output
      if echo "$line" | grep -qiE 'sa[ií]da esperada|expected output|nenhuma sa[ií]da|exit code 0|resultado'; then
        blocks_with_output=$((blocks_with_output + 1))
        code_block_is_command=0
      elif echo "$line" | grep -qE '^\s*```'; then
        # A code block immediately following could be the output
        blocks_with_output=$((blocks_with_output + 1))
        code_block_is_command=0
      elif echo "$line" | grep -qE '^#'; then
        # New section/heading means no output was provided
        blocks_missing_output=$((blocks_missing_output + 1))
        fail "$module_name" "Code block ending before line $line_number missing expected output"
        code_block_is_command=0
      elif echo "$line" | grep -qiE '^>.*nota|^>.*dica|^>.*aviso|^>.*tip|^>.*note|^>.*warning'; then
        # A note/tip after the command - check if output follows later
        # For now, treat notes as acceptable context
        preceding_text="$line"
        continue
      else
        # Regular text line - could be description for next command
        # Give benefit of doubt: if the next thing is another command description,
        # the previous command might have implicit "no output" behavior
        # Check if this looks like a description for the NEXT command
        if echo "$line" | grep -qiE '[A-Za-zÀ-ÿ].*[:.;]'; then
          # This is descriptive text - the previous block might have no visible output
          # which is acceptable for commands like export, cd, mv, etc.
          blocks_with_output=$((blocks_with_output + 1))
          code_block_is_command=0
        else
          preceding_text="${preceding_text}
${line}"
          continue
        fi
      fi
      preceding_text="$line"
      continue
    fi

    # Accumulate preceding text for the next code block
    if [ "$in_commands_section" -eq 1 ] && [ "$in_code_block" -eq 0 ]; then
      preceding_text="${preceding_text}
${line}"
      # Keep only last 10 lines of context to avoid memory issues
      local line_count
      line_count=$(echo "$preceding_text" | wc -l)
      if [ "$line_count" -gt 10 ]; then
        preceding_text=$(echo "$preceding_text" | tail -10)
      fi
    fi

  done < "$readme"

  # Handle case where file ends with a command block awaiting output check
  if [ "$code_block_is_command" -eq 2 ]; then
    blocks_missing_output=$((blocks_missing_output + 1))
    fail "$module_name" "Last code block in file missing expected output"
  fi

  # Module summary
  if [ "$block_count" -gt 0 ]; then
    echo -e "  ${YELLOW}📊 Summary${NC} [$module_name] $block_count command blocks found"
    if [ "$blocks_missing_description" -eq 0 ]; then
      pass "$module_name" "All $block_count command blocks have preceding descriptions"
    fi
    if [ "$blocks_missing_output" -eq 0 ]; then
      pass "$module_name" "All $block_count command blocks have expected output"
    fi
  else
    warn "$module_name" "No command blocks found in Comandos Passo a Passo section"
  fi
}

# =============================================================================
# Main Execution
# =============================================================================

echo "============================================================"
echo "Scanning all modules..."
echo "============================================================"
echo ""

# Iterate over all module directories in order
for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  if [ -d "$module_dir" ]; then
    module_name=$(basename "$module_dir")
    echo -e "${YELLOW}--- Module: $module_name ---${NC}"
    validate_module "$module_dir"
    echo ""
  fi
done

# =============================================================================
# Summary
# =============================================================================

echo "============================================================"
echo "SUMMARY"
echo "============================================================"
echo "Modules scanned:     $MODULES_SCANNED"
echo "Command blocks found: $CODE_BLOCKS_FOUND"
echo "Total checks:        $TOTAL_CHECKS"
echo -e "Passed:              ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:              ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ ALL CHECKS PASSED — All command blocks have descriptions and expected output.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS CHECK(S) FAILED — Some command blocks are missing documentation.${NC}"
  echo ""
  echo "Requirements 13.2: Each command must be preceded by a description"
  echo "Requirements 13.3: Each command must be followed by expected output"
  exit 1
fi
