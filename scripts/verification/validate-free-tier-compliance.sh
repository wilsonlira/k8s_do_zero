#!/bin/bash
# =============================================================================
# Property 9: Infrastructure Free Tier Compliance Validation
# =============================================================================
# Validates: Requirements 1.1, 1.5, 1.7
#
# Este script escaneia os scripts de infraestrutura e configurações do projeto
# para verificar que apenas configurações elegíveis ao Free Tier são utilizadas:
#   1. Instance types: somente t2.micro ou t3.micro
#   2. EBS total: ≤ 30 GB de armazenamento gp2/gp3
#   3. Nenhum script referencia instance types não-elegíveis
#   4. variables.env está configurado dentro dos limites do Free Tier
# =============================================================================

set -u

# Determinar raiz do projeto (script está em scripts/verification/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INFRA_DIR="$PROJECT_ROOT/scripts/infrastructure"
VARS_FILE="$PROJECT_ROOT/variables.env"
DOCS_INFRA_DIR="$PROJECT_ROOT/docs/01-aws-infrastructure"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Contadores
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Instance types elegíveis ao Free Tier
ELIGIBLE_INSTANCE_TYPES=("t2.micro" "t3.micro")

# Limite de EBS Free Tier
EBS_FREE_TIER_LIMIT=30

# Volume types elegíveis ao Free Tier
ELIGIBLE_VOLUME_TYPES=("gp2" "gp3")

# =============================================================================
# Funções Auxiliares
# =============================================================================

pass() {
  local context="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "  ${GREEN}✅ PASS${NC} [$context] $check"
}

fail() {
  local context="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "  ${RED}❌ FAIL${NC} [$context] $check"
}

is_eligible_instance_type() {
  local type="$1"
  for eligible in "${ELIGIBLE_INSTANCE_TYPES[@]}"; do
    if [ "$type" = "$eligible" ]; then
      return 0
    fi
  done
  return 1
}

is_eligible_volume_type() {
  local type="$1"
  for eligible in "${ELIGIBLE_VOLUME_TYPES[@]}"; do
    if [ "$type" = "$eligible" ]; then
      return 0
    fi
  done
  return 1
}

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 9: Infrastructure Free Tier Compliance"
echo "Validates: Requirements 1.1, 1.5, 1.7"
echo "============================================================"
echo ""

if [ ! -f "$VARS_FILE" ]; then
  echo -e "${RED}ERRO: Arquivo de variáveis não encontrado: $VARS_FILE${NC}"
  exit 1
fi

if [ ! -d "$INFRA_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de infraestrutura não encontrado: $INFRA_DIR${NC}"
  exit 1
fi

echo "Arquivo de variáveis: $VARS_FILE"
echo "Diretório de infraestrutura: $INFRA_DIR"
echo ""

# =============================================================================
# Check 1: variables.env — Instance Type
# =============================================================================
echo -e "${YELLOW}--- [1/5] Verificando INSTANCE_TYPE em variables.env ---${NC}"

CONFIGURED_INSTANCE_TYPE=$(grep -E '^INSTANCE_TYPE=' "$VARS_FILE" | head -1 | cut -d'"' -f2)

if [ -z "$CONFIGURED_INSTANCE_TYPE" ]; then
  fail "variables.env" "INSTANCE_TYPE não definido"
else
  if is_eligible_instance_type "$CONFIGURED_INSTANCE_TYPE"; then
    pass "variables.env" "INSTANCE_TYPE='$CONFIGURED_INSTANCE_TYPE' é elegível ao Free Tier"
  else
    fail "variables.env" "INSTANCE_TYPE='$CONFIGURED_INSTANCE_TYPE' NÃO é elegível ao Free Tier (esperado: t2.micro ou t3.micro)"
  fi
fi

# =============================================================================
# Check 2: variables.env — EBS Total ≤ 30 GB
# =============================================================================
echo ""
echo -e "${YELLOW}--- [2/5] Verificando EBS storage total em variables.env ---${NC}"

CP_DISK_SIZE=$(grep -E '^CONTROL_PLANE_DISK_SIZE=' "$VARS_FILE" | head -1 | grep -oE '[0-9]+')
WORKER_DISK_SIZE=$(grep -E '^WORKER_NODE_DISK_SIZE=' "$VARS_FILE" | head -1 | grep -oE '[0-9]+')
EBS_TYPE=$(grep -E '^EBS_VOLUME_TYPE=' "$VARS_FILE" | head -1 | cut -d'"' -f2)

if [ -z "$CP_DISK_SIZE" ]; then
  fail "variables.env" "CONTROL_PLANE_DISK_SIZE não definido"
else
  echo "  Control Plane disk: ${CP_DISK_SIZE} GB"
fi

if [ -z "$WORKER_DISK_SIZE" ]; then
  fail "variables.env" "WORKER_NODE_DISK_SIZE não definido"
else
  echo "  Worker Node disk: ${WORKER_DISK_SIZE} GB"
fi

if [ -n "$CP_DISK_SIZE" ] && [ -n "$WORKER_DISK_SIZE" ]; then
  TOTAL_EBS=$((CP_DISK_SIZE + WORKER_DISK_SIZE))
  echo "  Total EBS: ${TOTAL_EBS} GB (limite Free Tier: ${EBS_FREE_TIER_LIMIT} GB)"

  if [ "$TOTAL_EBS" -le "$EBS_FREE_TIER_LIMIT" ]; then
    pass "variables.env" "Total EBS (${TOTAL_EBS} GB) ≤ ${EBS_FREE_TIER_LIMIT} GB Free Tier limit"
  else
    fail "variables.env" "Total EBS (${TOTAL_EBS} GB) EXCEDE o limite Free Tier de ${EBS_FREE_TIER_LIMIT} GB"
  fi
fi

# Verificar tipo de volume EBS
if [ -z "$EBS_TYPE" ]; then
  fail "variables.env" "EBS_VOLUME_TYPE não definido"
else
  if is_eligible_volume_type "$EBS_TYPE"; then
    pass "variables.env" "EBS_VOLUME_TYPE='$EBS_TYPE' é elegível ao Free Tier"
  else
    fail "variables.env" "EBS_VOLUME_TYPE='$EBS_TYPE' NÃO é elegível ao Free Tier (esperado: gp2 ou gp3)"
  fi
fi

# =============================================================================
# Check 3: Infrastructure scripts — No non-eligible instance types
# =============================================================================
echo ""
echo -e "${YELLOW}--- [3/5] Verificando instance types nos scripts de infraestrutura ---${NC}"

# Scan all .sh files in infrastructure directory for instance type references
INFRA_SCRIPTS=$(find "$INFRA_DIR" -name "*.sh" -type f 2>/dev/null)

if [ -z "$INFRA_SCRIPTS" ]; then
  fail "scripts" "Nenhum script de infraestrutura encontrado em $INFRA_DIR"
else
  SCRIPTS_WITH_ISSUES=0

  while IFS= read -r script_file; do
    script_name=$(basename "$script_file")

    # Look for --instance-type flags with non-eligible types
    # Pattern: --instance-type followed by a value that is NOT t2.micro or t3.micro
    NON_ELIGIBLE_REFS=$(grep -nE '\-\-instance-type\s+["\x27]?[a-z][0-9]+\.' "$script_file" 2>/dev/null | \
      grep -vE 't2\.micro|t3\.micro|\$\{?INSTANCE_TYPE' || true)

    if [ -n "$NON_ELIGIBLE_REFS" ]; then
      fail "$script_name" "Referência a instance type não-elegível encontrada:"
      echo "    $NON_ELIGIBLE_REFS"
      SCRIPTS_WITH_ISSUES=$((SCRIPTS_WITH_ISSUES + 1))
    fi

    # Look for hardcoded instance types that are not t2.micro/t3.micro
    # Exclude comments, variable assignments that use the eligible types, and variable references
    HARDCODED_TYPES=$(grep -nE '(instance.type|InstanceType)["\x27: =]+[a-z][0-9]+\.' "$script_file" 2>/dev/null | \
      grep -vE 't2\.micro|t3\.micro|\$\{?INSTANCE_TYPE|^[[:space:]]*#' || true)

    if [ -n "$HARDCODED_TYPES" ]; then
      fail "$script_name" "Instance type hardcoded não-elegível encontrado:"
      echo "    $HARDCODED_TYPES"
      SCRIPTS_WITH_ISSUES=$((SCRIPTS_WITH_ISSUES + 1))
    fi
  done <<< "$INFRA_SCRIPTS"

  if [ "$SCRIPTS_WITH_ISSUES" -eq 0 ]; then
    pass "scripts" "Nenhum instance type não-elegível encontrado nos scripts de infraestrutura"
  fi
fi

# =============================================================================
# Check 4: Infrastructure scripts — EBS configurations within limits
# =============================================================================
echo ""
echo -e "${YELLOW}--- [4/5] Verificando configurações EBS nos scripts de infraestrutura ---${NC}"

EBS_ISSUES=0

if [ -n "$INFRA_SCRIPTS" ]; then
  while IFS= read -r script_file; do
    script_name=$(basename "$script_file")

    # Look for hardcoded VolumeSize values that would exceed limits
    # Pattern: "VolumeSize": <number> or VolumeSize=<number>
    VOLUME_SIZES=$(grep -oE 'VolumeSize["\x27: ]*[0-9]+' "$script_file" 2>/dev/null | \
      grep -oE '[0-9]+' || true)

    if [ -n "$VOLUME_SIZES" ]; then
      SCRIPT_TOTAL=0
      while IFS= read -r size; do
        SCRIPT_TOTAL=$((SCRIPT_TOTAL + size))
      done <<< "$VOLUME_SIZES"

      # Only flag if the script uses hardcoded values (not variables)
      HARDCODED_VOLUMES=$(grep -E 'VolumeSize' "$script_file" 2>/dev/null | \
        grep -vE '\$\{|DISK_SIZE' || true)

      if [ -n "$HARDCODED_VOLUMES" ] && [ "$SCRIPT_TOTAL" -gt "$EBS_FREE_TIER_LIMIT" ]; then
        fail "$script_name" "Volumes EBS hardcoded totalizam ${SCRIPT_TOTAL} GB (excede ${EBS_FREE_TIER_LIMIT} GB)"
        EBS_ISSUES=$((EBS_ISSUES + 1))
      fi
    fi

    # Check for non-eligible volume types hardcoded in scripts
    NON_ELIGIBLE_VOL_TYPES=$(grep -nE 'VolumeType["\x27: =]+(io1|io2|st1|sc1|standard)' "$script_file" 2>/dev/null | \
      grep -vE '^\s*#' || true)

    if [ -n "$NON_ELIGIBLE_VOL_TYPES" ]; then
      fail "$script_name" "Volume type não-elegível ao Free Tier encontrado:"
      echo "    $NON_ELIGIBLE_VOL_TYPES"
      EBS_ISSUES=$((EBS_ISSUES + 1))
    fi
  done <<< "$INFRA_SCRIPTS"

  if [ "$EBS_ISSUES" -eq 0 ]; then
    pass "scripts" "Configurações EBS nos scripts estão dentro dos limites Free Tier"
  fi
fi

# =============================================================================
# Check 5: Documentation consistency — Free Tier references
# =============================================================================
echo ""
echo -e "${YELLOW}--- [5/5] Verificando consistência na documentação de infraestrutura ---${NC}"

if [ -d "$DOCS_INFRA_DIR" ]; then
  DOC_FILE="$DOCS_INFRA_DIR/README.md"

  if [ -f "$DOC_FILE" ]; then
    DOC_CONTENT=$(cat "$DOC_FILE")

    # Check that documentation mentions t2.micro or t3.micro
    DOC_INSTANCE_REFS=$(echo "$DOC_CONTENT" | grep -ciE 't2\.micro|t3\.micro' || true)
    if [ "$DOC_INSTANCE_REFS" -gt 0 ]; then
      pass "docs" "Documentação referencia instance types elegíveis ao Free Tier (t2.micro/t3.micro)"
    else
      fail "docs" "Documentação não menciona instance types elegíveis (t2.micro/t3.micro)"
    fi

    # Check that documentation mentions 30 GB EBS limit
    DOC_EBS_LIMIT=$(echo "$DOC_CONTENT" | grep -ciE '30\s*(GB|gb|gigabyte)' || true)
    if [ "$DOC_EBS_LIMIT" -gt 0 ]; then
      pass "docs" "Documentação menciona o limite de 30 GB EBS do Free Tier"
    else
      fail "docs" "Documentação não menciona o limite de 30 GB EBS do Free Tier"
    fi

    # Check that documentation mentions gp2 or gp3 volume types
    DOC_VOL_TYPE=$(echo "$DOC_CONTENT" | grep -ciE 'gp[23]' || true)
    if [ "$DOC_VOL_TYPE" -gt 0 ]; then
      pass "docs" "Documentação menciona volume types elegíveis (gp2/gp3)"
    else
      fail "docs" "Documentação não menciona volume types elegíveis (gp2/gp3)"
    fi

    # Check for any non-eligible instance types explicitly specified in the documentation
    # Look for EC2 instance type patterns (e.g., t2.small, m5.large) that are NOT t2.micro/t3.micro
    # Only match actual AWS instance type patterns: letter+digit+dot+size (e.g., t2.small, m5.large)
    DOC_NON_ELIGIBLE=$(echo "$DOC_CONTENT" | \
      grep -oE '\b[a-z][0-9]+[a-z]*\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)\b' | \
      grep -vE '^(t2\.micro|t3\.micro)$' | sort -u || true)
    if [ -n "$DOC_NON_ELIGIBLE" ]; then
      fail "docs" "Documentação referencia instance types não-elegíveis: $DOC_NON_ELIGIBLE"
    else
      pass "docs" "Documentação não promove instance types não-elegíveis"
    fi
  else
    fail "docs" "README.md não encontrado em $DOCS_INFRA_DIR"
  fi
else
  fail "docs" "Diretório de documentação de infraestrutura não encontrado: $DOCS_INFRA_DIR"
fi

# =============================================================================
# Resumo
# =============================================================================

echo ""
echo "============================================================"
echo "RESUMO — Property 9: Infrastructure Free Tier Compliance"
echo "============================================================"
echo ""
echo "Verificações realizadas: $TOTAL_CHECKS"
echo -e "Aprovadas:              ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Reprovadas:             ${RED}$FAILED_CHECKS${NC}"
echo ""
echo "Critérios Free Tier verificados:"
echo "  • Instance types: somente t2.micro ou t3.micro"
echo "  • EBS total: ≤ 30 GB"
echo "  • Volume types: somente gp2 ou gp3"
echo "  • Scripts sem hardcoded non-eligible configurations"
echo "  • Documentação consistente com Free Tier"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Infraestrutura está em conformidade com o Free Tier.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Infraestrutura NÃO está em conformidade com o Free Tier.${NC}"
  exit 1
fi
