#!/bin/bash
# =============================================================================
# Property 6: Distribuição de Pesos dos Domínios CKA
# =============================================================================
# Validates: Requirements 14.4
#
# Este script lê cka-simulator/scoring.md, extrai os pesos dos domínios e
# verifica que:
#   1. A soma de todos os pesos = 100%
#   2. Cada domínio está dentro de ±5% do peso-alvo do CKA:
#      - Cluster Architecture, Installation & Configuration: 25%
#      - Workloads & Scheduling: 15%
#      - Services & Networking: 20%
#      - Storage: 10%
#      - Troubleshooting: 30%
# =============================================================================

set -euo pipefail

# Determinar raiz do projeto (script está em scripts/validation/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SCORING_FILE="$PROJECT_ROOT/cka-simulator/scoring.md"

# Cores para saída
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # Sem cor

# Contadores
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Pesos-alvo do CKA (valores oficiais)
declare -A TARGET_WEIGHTS
TARGET_WEIGHTS["Cluster Architecture"]=25
TARGET_WEIGHTS["Workloads & Scheduling"]=15
TARGET_WEIGHTS["Services & Networking"]=20
TARGET_WEIGHTS["Storage"]=10
TARGET_WEIGHTS["Troubleshooting"]=30

# Tolerância permitida (±5%)
TOLERANCE=5

# =============================================================================
# Funções Auxiliares
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

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 6: Distribuição de Pesos dos Domínios CKA"
echo "Validates: Requirements 14.4"
echo "============================================================"
echo ""

if [ ! -f "$SCORING_FILE" ]; then
  echo -e "${RED}ERRO: Arquivo de scoring não encontrado: $SCORING_FILE${NC}"
  exit 1
fi

echo "Analisando: $SCORING_FILE"
echo ""

# =============================================================================
# Extração dos Pesos do scoring.md
# =============================================================================

echo -e "${YELLOW}--- Extraindo pesos dos domínios ---${NC}"
echo ""

# Extrair linhas da tabela de pesos (formato: | # | Domínio | Peso | Tarefas |)
# Procurar linhas com percentual (XX%) na tabela de pesos por domínio
declare -A EXTRACTED_WEIGHTS
WEIGHT_SUM=0

# Extrair peso de Cluster Architecture
ARCH_WEIGHT=$(grep -i "Cluster Architecture" "$SCORING_FILE" | grep -oP '\d+(?=%)' | head -1)
if [ -n "$ARCH_WEIGHT" ]; then
  EXTRACTED_WEIGHTS["Cluster Architecture"]=$ARCH_WEIGHT
  WEIGHT_SUM=$((WEIGHT_SUM + ARCH_WEIGHT))
  echo "  Cluster Architecture: ${ARCH_WEIGHT}%"
else
  echo -e "  ${RED}Cluster Architecture: NÃO ENCONTRADO${NC}"
fi

# Extrair peso de Workloads & Scheduling
WORK_WEIGHT=$(grep -i "Workloads.*Scheduling" "$SCORING_FILE" | grep -oP '\d+(?=%)' | head -1)
if [ -n "$WORK_WEIGHT" ]; then
  EXTRACTED_WEIGHTS["Workloads & Scheduling"]=$WORK_WEIGHT
  WEIGHT_SUM=$((WEIGHT_SUM + WORK_WEIGHT))
  echo "  Workloads & Scheduling: ${WORK_WEIGHT}%"
else
  echo -e "  ${RED}Workloads & Scheduling: NÃO ENCONTRADO${NC}"
fi

# Extrair peso de Services & Networking
NET_WEIGHT=$(grep -i "Services.*Networking" "$SCORING_FILE" | grep -oP '\d+(?=%)' | head -1)
if [ -n "$NET_WEIGHT" ]; then
  EXTRACTED_WEIGHTS["Services & Networking"]=$NET_WEIGHT
  WEIGHT_SUM=$((WEIGHT_SUM + NET_WEIGHT))
  echo "  Services & Networking: ${NET_WEIGHT}%"
else
  echo -e "  ${RED}Services & Networking: NÃO ENCONTRADO${NC}"
fi

# Extrair peso de Storage
STOR_WEIGHT=$(grep -i "Storage" "$SCORING_FILE" | grep -oP '\d+(?=%)' | head -1)
if [ -n "$STOR_WEIGHT" ]; then
  EXTRACTED_WEIGHTS["Storage"]=$STOR_WEIGHT
  WEIGHT_SUM=$((WEIGHT_SUM + STOR_WEIGHT))
  echo "  Storage: ${STOR_WEIGHT}%"
else
  echo -e "  ${RED}Storage: NÃO ENCONTRADO${NC}"
fi

# Extrair peso de Troubleshooting
TROUBLE_WEIGHT=$(grep -i "Troubleshooting" "$SCORING_FILE" | grep -oP '\d+(?=%)' | head -1)
if [ -n "$TROUBLE_WEIGHT" ]; then
  EXTRACTED_WEIGHTS["Troubleshooting"]=$TROUBLE_WEIGHT
  WEIGHT_SUM=$((WEIGHT_SUM + TROUBLE_WEIGHT))
  echo "  Troubleshooting: ${TROUBLE_WEIGHT}%"
else
  echo -e "  ${RED}Troubleshooting: NÃO ENCONTRADO${NC}"
fi

echo ""
echo "  Soma total extraída: ${WEIGHT_SUM}%"
echo ""

# =============================================================================
# Validação 1: Todos os domínios foram encontrados
# =============================================================================

echo -e "${YELLOW}--- Verificando presença de todos os domínios ---${NC}"
echo ""

DOMAINS_FOUND=${#EXTRACTED_WEIGHTS[@]}
DOMAINS_EXPECTED=5

if [ "$DOMAINS_FOUND" -eq "$DOMAINS_EXPECTED" ]; then
  pass "Todos os $DOMAINS_EXPECTED domínios encontrados no scoring.md"
else
  fail "Esperados $DOMAINS_EXPECTED domínios, encontrados $DOMAINS_FOUND"
fi

# =============================================================================
# Validação 2: Soma dos pesos = 100%
# =============================================================================

echo ""
echo -e "${YELLOW}--- Verificando soma dos pesos = 100% ---${NC}"
echo ""

if [ "$WEIGHT_SUM" -eq 100 ]; then
  pass "Soma dos pesos dos domínios = 100% (valor: ${WEIGHT_SUM}%)"
else
  fail "Soma dos pesos dos domínios ≠ 100% (valor: ${WEIGHT_SUM}%)"
fi

# =============================================================================
# Validação 3: Cada domínio dentro de ±5% do alvo
# =============================================================================

echo ""
echo -e "${YELLOW}--- Verificando tolerância ±${TOLERANCE}% por domínio ---${NC}"
echo ""

for domain in "Cluster Architecture" "Workloads & Scheduling" "Services & Networking" "Storage" "Troubleshooting"; do
  target=${TARGET_WEIGHTS[$domain]}
  actual=${EXTRACTED_WEIGHTS[$domain]:-0}

  if [ "$actual" -eq 0 ]; then
    fail "[$domain] Peso não encontrado no documento"
    continue
  fi

  # Calcular diferença absoluta
  diff=$((actual - target))
  if [ "$diff" -lt 0 ]; then
    diff=$((-diff))
  fi

  if [ "$diff" -le "$TOLERANCE" ]; then
    pass "[$domain] Peso ${actual}% está dentro de ±${TOLERANCE}% do alvo ${target}% (diferença: ${diff}%)"
  else
    fail "[$domain] Peso ${actual}% está FORA de ±${TOLERANCE}% do alvo ${target}% (diferença: ${diff}%)"
  fi
done

# =============================================================================
# Resumo
# =============================================================================

echo ""
echo "============================================================"
echo "RESUMO"
echo "============================================================"
echo "Total de verificações: $TOTAL_CHECKS"
echo -e "Aprovadas:             ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Reprovadas:            ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Distribuição de pesos CKA está correta.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Distribuição de pesos CKA está incorreta.${NC}"
  exit 1
fi
