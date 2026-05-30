#!/bin/bash
# =============================================================================
# Property 9: Infrastructure Free Tier Compliance
# =============================================================================
# Validates: Requirements 1.1, 1.5, 1.7
#
# This script scans infrastructure scripts and configuration files to verify
# that only Free Tier eligible configurations are used:
#   1. Instance types must be t2.micro or t3.micro
#   2. Total EBS storage must not exceed 30 GB
#   3. EBS volume types must be gp2 or gp3
#   4. No hardcoded non-Free-Tier instance types in scripts or docs
# =============================================================================

set -euo pipefail

# Determine project root (script is in scripts/validation/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VARIABLES_FILE="$PROJECT_ROOT/variables.env"
INFRA_DIR="$PROJECT_ROOT/scripts/infrastructure"
DOCS_INFRA="$PROJECT_ROOT/docs/01-aws-infrastructure/README.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Allowed Free Tier values
ALLOWED_INSTANCE_TYPES=("t2.micro" "t3.micro")
ALLOWED_EBS_TYPES=("gp2" "gp3")
MAX_TOTAL_EBS_GB=30

# =============================================================================
# Helper Functions
# =============================================================================

pass() {
  local check="$1"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "  ${GREEN}✅ PASS${NC} $check"
}

fail() {
  local check="$1"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "  ${RED}❌ FAIL${NC} $check"
}

is_allowed_instance_type() {
  local type="$1"
  for allowed in "${ALLOWED_INSTANCE_TYPES[@]}"; do
    if [ "$type" = "$allowed" ]; then
      return 0
    fi
  done
  return 1
}

is_allowed_ebs_type() {
  local type="$1"
  for allowed in "${ALLOWED_EBS_TYPES[@]}"; do
    if [ "$type" = "$allowed" ]; then
      return 0
    fi
  done
  return 1
}

# =============================================================================
# Pre-execution Checks
# =============================================================================

echo "============================================================"
echo "Property 9: Infrastructure Free Tier Compliance"
echo "Validates: Requirements 1.1, 1.5, 1.7"
echo "============================================================"
echo ""

if [ ! -f "$VARIABLES_FILE" ]; then
  echo -e "${RED}ERROR: variables.env not found: $VARIABLES_FILE${NC}"
  exit 1
fi

if [ ! -d "$INFRA_DIR" ]; then
  echo -e "${RED}ERROR: Infrastructure scripts directory not found: $INFRA_DIR${NC}"
  exit 1
fi

# =============================================================================
# Validation 1: Check INSTANCE_TYPE in variables.env
# =============================================================================

echo -e "${YELLOW}--- Checking variables.env: Instance Type ---${NC}"
echo ""

# Extract INSTANCE_TYPE from variables.env (handle CRLF and inline comments)
CONFIGURED_INSTANCE_TYPE=$(grep -E '^INSTANCE_TYPE=' "$VARIABLES_FILE" | sed 's/^INSTANCE_TYPE=//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | tr -d '\r' | tr -d ' ')

if [ -z "$CONFIGURED_INSTANCE_TYPE" ]; then
  fail "INSTANCE_TYPE not defined in variables.env"
else
  if is_allowed_instance_type "$CONFIGURED_INSTANCE_TYPE"; then
    pass "INSTANCE_TYPE='$CONFIGURED_INSTANCE_TYPE' is Free Tier eligible"
  else
    fail "INSTANCE_TYPE='$CONFIGURED_INSTANCE_TYPE' is NOT Free Tier eligible (allowed: ${ALLOWED_INSTANCE_TYPES[*]})"
  fi
fi

# =============================================================================
# Validation 2: Check EBS configuration in variables.env
# =============================================================================

echo ""
echo -e "${YELLOW}--- Checking variables.env: EBS Configuration ---${NC}"
echo ""

# Extract EBS disk sizes (handle CRLF and inline comments like "15"  # GB)
CP_DISK=$(grep -E '^CONTROL_PLANE_DISK_SIZE=' "$VARIABLES_FILE" | sed 's/^CONTROL_PLANE_DISK_SIZE=//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | tr -d '\r' | tr -d ' ')
WORKER_DISK=$(grep -E '^WORKER_NODE_DISK_SIZE=' "$VARIABLES_FILE" | sed 's/^WORKER_NODE_DISK_SIZE=//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | tr -d '\r' | tr -d ' ')
EBS_TYPE=$(grep -E '^EBS_VOLUME_TYPE=' "$VARIABLES_FILE" | sed 's/^EBS_VOLUME_TYPE=//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | tr -d '\r' | tr -d ' ')

# Check Control Plane disk size is defined and numeric
if [ -z "$CP_DISK" ]; then
  fail "CONTROL_PLANE_DISK_SIZE not defined in variables.env"
else
  if [[ "$CP_DISK" =~ ^[0-9]+$ ]]; then
    pass "CONTROL_PLANE_DISK_SIZE='${CP_DISK}' GB is defined and numeric"
  else
    fail "CONTROL_PLANE_DISK_SIZE='${CP_DISK}' is not a valid number"
  fi
fi

# Check Worker Node disk size is defined and numeric
if [ -z "$WORKER_DISK" ]; then
  fail "WORKER_NODE_DISK_SIZE not defined in variables.env"
else
  if [[ "$WORKER_DISK" =~ ^[0-9]+$ ]]; then
    pass "WORKER_NODE_DISK_SIZE='${WORKER_DISK}' GB is defined and numeric"
  else
    fail "WORKER_NODE_DISK_SIZE='${WORKER_DISK}' is not a valid number"
  fi
fi

# Check total EBS does not exceed 30 GB
if [[ "$CP_DISK" =~ ^[0-9]+$ ]] && [[ "$WORKER_DISK" =~ ^[0-9]+$ ]]; then
  TOTAL_EBS=$((CP_DISK + WORKER_DISK))
  if [ "$TOTAL_EBS" -le "$MAX_TOTAL_EBS_GB" ]; then
    pass "Total EBS storage: ${TOTAL_EBS} GB ≤ ${MAX_TOTAL_EBS_GB} GB (Free Tier limit)"
  else
    fail "Total EBS storage: ${TOTAL_EBS} GB EXCEEDS ${MAX_TOTAL_EBS_GB} GB Free Tier limit"
  fi
fi

# Check EBS volume type
if [ -z "$EBS_TYPE" ]; then
  fail "EBS_VOLUME_TYPE not defined in variables.env"
else
  if is_allowed_ebs_type "$EBS_TYPE"; then
    pass "EBS_VOLUME_TYPE='$EBS_TYPE' is Free Tier eligible"
  else
    fail "EBS_VOLUME_TYPE='$EBS_TYPE' is NOT Free Tier eligible (allowed: ${ALLOWED_EBS_TYPES[*]})"
  fi
fi

# =============================================================================
# Validation 3: Scan infrastructure scripts for hardcoded instance types
# =============================================================================

echo ""
echo -e "${YELLOW}--- Scanning infrastructure scripts for instance types ---${NC}"
echo ""

# Find all instance type references in infrastructure scripts
NON_COMPLIANT_TYPES=0

for script in "$INFRA_DIR"/*.sh; do
  if [ ! -f "$script" ]; then
    continue
  fi

  script_name=$(basename "$script")

  # Extract hardcoded instance types from --instance-type flags or direct assignments
  # Look for patterns like: --instance-type "xxx" or instance_type="xxx" or INSTANCE_TYPE="xxx"
  # Exclude comments and variable references like ${INSTANCE_TYPE}
  HARDCODED_TYPES=$(grep -n -oP '(?<=--instance-type\s)["\x27]?\K[a-z0-9.]+(?=["\x27]?)' "$script" 2>/dev/null || true)

  if [ -n "$HARDCODED_TYPES" ]; then
    while IFS= read -r found_type; do
      if is_allowed_instance_type "$found_type"; then
        pass "[$script_name] Hardcoded instance type '$found_type' is Free Tier eligible"
      else
        fail "[$script_name] Hardcoded instance type '$found_type' is NOT Free Tier eligible"
        NON_COMPLIANT_TYPES=$((NON_COMPLIANT_TYPES + 1))
      fi
    done <<< "$HARDCODED_TYPES"
  fi
done

# Also check that scripts reference the variable (good practice)
for script in "$INFRA_DIR"/*.sh; do
  if [ ! -f "$script" ]; then
    continue
  fi

  script_name=$(basename "$script")

  # Check if the script uses INSTANCE_TYPE variable (for scripts that create instances)
  if grep -q "run-instances" "$script" 2>/dev/null; then
    if grep -q '${INSTANCE_TYPE}' "$script" || grep -q '"${INSTANCE_TYPE}"' "$script"; then
      pass "[$script_name] Uses \${INSTANCE_TYPE} variable for instance creation"
    else
      # Check if it uses a hardcoded but allowed type
      if grep -qP '--instance-type\s+["\x27]?(t2\.micro|t3\.micro)' "$script" 2>/dev/null; then
        pass "[$script_name] Uses hardcoded Free Tier eligible instance type"
      else
        fail "[$script_name] Creates instances without using \${INSTANCE_TYPE} variable or Free Tier type"
      fi
    fi
  fi
done

# =============================================================================
# Validation 4: Scan infrastructure scripts for EBS volume sizes
# =============================================================================

echo ""
echo -e "${YELLOW}--- Scanning infrastructure scripts for EBS volumes ---${NC}"
echo ""

for script in "$INFRA_DIR"/*.sh; do
  if [ ! -f "$script" ]; then
    continue
  fi

  script_name=$(basename "$script")

  # Look for VolumeSize references in block-device-mappings
  VOLUME_SIZES=$(grep -oP '"VolumeSize"\s*:\s*\K[0-9]+' "$script" 2>/dev/null || true)
  VOLUME_TYPES=$(grep -oP '"VolumeType"\s*:\s*"\K[^"]+' "$script" 2>/dev/null || true)

  if [ -n "$VOLUME_SIZES" ]; then
    # Calculate total from hardcoded values in this script
    SCRIPT_TOTAL=0
    while IFS= read -r size; do
      SCRIPT_TOTAL=$((SCRIPT_TOTAL + size))
    done <<< "$VOLUME_SIZES"

    # Check if script uses variables instead of hardcoded values
    if grep -q '${CONTROL_PLANE_DISK_SIZE}' "$script" || grep -q '${WORKER_NODE_DISK_SIZE}' "$script"; then
      pass "[$script_name] Uses disk size variables from variables.env"
    elif [ "$SCRIPT_TOTAL" -le "$MAX_TOTAL_EBS_GB" ]; then
      pass "[$script_name] Hardcoded EBS total: ${SCRIPT_TOTAL} GB ≤ ${MAX_TOTAL_EBS_GB} GB"
    else
      fail "[$script_name] Hardcoded EBS total: ${SCRIPT_TOTAL} GB EXCEEDS ${MAX_TOTAL_EBS_GB} GB"
    fi
  fi

  # Check volume types
  if [ -n "$VOLUME_TYPES" ]; then
    while IFS= read -r vtype; do
      if is_allowed_ebs_type "$vtype"; then
        pass "[$script_name] EBS volume type '$vtype' is Free Tier eligible"
      else
        fail "[$script_name] EBS volume type '$vtype' is NOT Free Tier eligible (allowed: ${ALLOWED_EBS_TYPES[*]})"
      fi
    done <<< "$VOLUME_TYPES"
  fi
done

# =============================================================================
# Validation 5: Check create-instances.sh has Free Tier guard
# =============================================================================

echo ""
echo -e "${YELLOW}--- Checking Free Tier safety guards in scripts ---${NC}"
echo ""

CREATE_INSTANCES="$INFRA_DIR/create-instances.sh"
if [ -f "$CREATE_INSTANCES" ]; then
  # Check for Free Tier validation logic
  if grep -q "t2.micro\|t3.micro" "$CREATE_INSTANCES" && grep -q "Free Tier" "$CREATE_INSTANCES"; then
    pass "[create-instances.sh] Contains Free Tier validation checks"
  else
    fail "[create-instances.sh] Missing Free Tier validation checks"
  fi

  # Check for EBS limit warning
  if grep -q "30" "$CREATE_INSTANCES" && grep -qiE "ebs|disk|storage" "$CREATE_INSTANCES"; then
    pass "[create-instances.sh] Contains EBS storage limit check (30 GB)"
  else
    fail "[create-instances.sh] Missing EBS storage limit check"
  fi
fi

# Check verify-free-tier.sh exists
VERIFY_SCRIPT="$INFRA_DIR/verify-free-tier.sh"
if [ -f "$VERIFY_SCRIPT" ]; then
  pass "[verify-free-tier.sh] Free Tier verification script exists"

  # Check it validates instance types
  if grep -q "t2.micro\|t3.micro" "$VERIFY_SCRIPT"; then
    pass "[verify-free-tier.sh] Validates instance types against Free Tier"
  else
    fail "[verify-free-tier.sh] Does not validate instance types"
  fi

  # Check it validates EBS limits
  if grep -q "30" "$VERIFY_SCRIPT" && grep -qiE "ebs|volume" "$VERIFY_SCRIPT"; then
    pass "[verify-free-tier.sh] Validates EBS storage limits"
  else
    fail "[verify-free-tier.sh] Does not validate EBS storage limits"
  fi
else
  fail "[verify-free-tier.sh] Free Tier verification script does not exist"
fi

# =============================================================================
# Validation 6: Check documentation references Free Tier constraints
# =============================================================================

echo ""
echo -e "${YELLOW}--- Checking documentation for Free Tier references ---${NC}"
echo ""

if [ -f "$DOCS_INFRA" ]; then
  # Check documentation mentions Free Tier eligible instance types
  if grep -q "t2.micro" "$DOCS_INFRA" || grep -q "t3.micro" "$DOCS_INFRA"; then
    pass "[docs/01-aws-infrastructure] Documents Free Tier eligible instance types"
  else
    fail "[docs/01-aws-infrastructure] Does not document Free Tier eligible instance types"
  fi

  # Check documentation mentions 30 GB EBS limit
  if grep -q "30" "$DOCS_INFRA" && grep -qiE "gb|ebs|free.tier" "$DOCS_INFRA"; then
    pass "[docs/01-aws-infrastructure] Documents 30 GB EBS Free Tier limit"
  else
    fail "[docs/01-aws-infrastructure] Does not document 30 GB EBS Free Tier limit"
  fi

  # Check documentation mentions gp2/gp3
  if grep -qE "gp[23]" "$DOCS_INFRA"; then
    pass "[docs/01-aws-infrastructure] Documents gp2/gp3 volume types"
  else
    fail "[docs/01-aws-infrastructure] Does not document gp2/gp3 volume types"
  fi

  # Check documentation has cost warnings
  if grep -qiE "aviso|warning|custo|cost" "$DOCS_INFRA"; then
    pass "[docs/01-aws-infrastructure] Contains cost/Free Tier warnings"
  else
    fail "[docs/01-aws-infrastructure] Missing cost/Free Tier warnings"
  fi
else
  fail "[docs/01-aws-infrastructure] Documentation file not found: $DOCS_INFRA"
fi

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
  echo -e "${GREEN}✅ ALL CHECKS PASSED — Infrastructure is Free Tier compliant.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS CHECK(S) FAILED — Infrastructure has Free Tier compliance issues.${NC}"
  exit 1
fi
