#!/bin/bash
# =============================================================================
# Property 5: Cobertura de Troubleshooting
# =============================================================================
# Validates: Requirements 13.4
#
# Este script escaneia cada docs/XX-*/README.md e verifica que:
#   1. A seção Troubleshooting existe no módulo
#   2. A seção contém pelo menos 2 cenários de problema/erro
#      (identificados por headings "### Problema" ou similar)
#
# Requisito 13.4: "IF a command fails, THEN THE Documentation_System SHALL
# provide at least 2 common error scenarios per command that may fail, each
# including the error symptom, probable cause, and resolution steps"
# =============================================================================

set -euo pipefail

# Determinar raiz do projeto (script está em scripts/validation/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DOCS_DIR="$PROJECT_ROOT/docs"

# Cores para saída
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sem cor

# Contadores globais
TOTAL_MODULES=0
MODULES_PASSED=0
MODULES_FAILED=0
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Mínimo de cenários de troubleshooting por módulo
MIN_SCENARIOS=2

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

info() {
  local msg="$1"
  echo -e "  ${BLUE}ℹ️  INFO${NC} $msg"
}

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 5: Cobertura de Troubleshooting"
echo "Validates: Requirements 13.4"
echo "============================================================"
echo ""

if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de documentação não encontrado: $DOCS_DIR${NC}"
  exit 1
fi

echo "Diretório de módulos: $DOCS_DIR"
echo "Mínimo de cenários por módulo: $MIN_SCENARIOS"
echo ""

# =============================================================================
# Verificação 1: Seção Troubleshooting existe em cada módulo
# =============================================================================

echo -e "${YELLOW}--- Verificando existência da seção Troubleshooting ---${NC}"
echo ""

for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  # Verificar se o diretório existe
  if [ ! -d "$module_dir" ]; then
    continue
  fi

  module_name=$(basename "$module_dir")
  readme_file="$module_dir/README.md"

  TOTAL_MODULES=$((TOTAL_MODULES + 1))

  if [ ! -f "$readme_file" ]; then
    fail "[$module_name] README.md não encontrado"
    MODULES_FAILED=$((MODULES_FAILED + 1))
    continue
  fi

  # Verificar se a seção Troubleshooting existe
  if grep -qi "^## Troubleshooting" "$readme_file"; then
    pass "[$module_name] Seção Troubleshooting encontrada"
  else
    fail "[$module_name] Seção Troubleshooting NÃO encontrada"
    MODULES_FAILED=$((MODULES_FAILED + 1))
  fi
done

echo ""

# =============================================================================
# Verificação 2: Cada módulo tem pelo menos 2 cenários de problema
# =============================================================================

echo -e "${YELLOW}--- Verificando quantidade de cenários de troubleshooting (mínimo: $MIN_SCENARIOS) ---${NC}"
echo ""

for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  if [ ! -d "$module_dir" ]; then
    continue
  fi

  module_name=$(basename "$module_dir")
  readme_file="$module_dir/README.md"

  if [ ! -f "$readme_file" ]; then
    continue
  fi

  # Contar cenários de problema na seção Troubleshooting
  # Padrões aceitos: "### Problema:", "### Problema 1:", "### Problema: texto"
  scenario_count=$(grep -ci "^### Problema" "$readme_file" || echo "0")

  if [ "$scenario_count" -ge "$MIN_SCENARIOS" ]; then
    pass "[$module_name] $scenario_count cenários de troubleshooting (≥ $MIN_SCENARIOS)"
  else
    fail "[$module_name] Apenas $scenario_count cenário(s) de troubleshooting (mínimo: $MIN_SCENARIOS)"
  fi
done

echo ""

# =============================================================================
# Verificação 3: Cada cenário contém sintoma, causa e resolução
# =============================================================================

echo -e "${YELLOW}--- Verificando estrutura dos cenários (Sintoma, Causa, Resolução) ---${NC}"
echo ""

for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  if [ ! -d "$module_dir" ]; then
    continue
  fi

  module_name=$(basename "$module_dir")
  readme_file="$module_dir/README.md"

  if [ ! -f "$readme_file" ]; then
    continue
  fi

  # Verificar se a seção Troubleshooting existe
  if ! grep -qi "^## Troubleshooting" "$readme_file"; then
    continue
  fi

  # Extrair conteúdo da seção Troubleshooting (do ## Troubleshooting até o próximo ## ou fim do arquivo)
  troubleshooting_content=$(sed -n '/^## Troubleshooting/,/^## [^#]/p' "$readme_file" | head -n -1)
  if [ -z "$troubleshooting_content" ]; then
    # Se não encontrou próximo ##, pegar até o fim do arquivo
    troubleshooting_content=$(sed -n '/^## Troubleshooting/,$p' "$readme_file")
  fi

  # Contar cenários que têm "Sintoma" (ou **Sintoma**)
  sintoma_count=$(echo "$troubleshooting_content" | grep -ci "sintoma" || echo "0")

  # Contar cenários que têm "Causa" ou "Resolução"/"Solução"
  causa_count=$(echo "$troubleshooting_content" | grep -ci "causa\|cause" || echo "0")
  resolucao_count=$(echo "$troubleshooting_content" | grep -ci "resolução\|resolution\|solução" || echo "0")

  # Verificar presença de sintomas
  if [ "$sintoma_count" -ge "$MIN_SCENARIOS" ]; then
    pass "[$module_name] Sintomas documentados: $sintoma_count ocorrências"
  else
    fail "[$module_name] Sintomas insuficientes: $sintoma_count (mínimo esperado: $MIN_SCENARIOS)"
  fi

  # Verificar presença de causas
  if [ "$causa_count" -ge "$MIN_SCENARIOS" ]; then
    pass "[$module_name] Causas documentadas: $causa_count ocorrências"
  else
    fail "[$module_name] Causas insuficientes: $causa_count (mínimo esperado: $MIN_SCENARIOS)"
  fi

  # Verificar presença de resoluções
  if [ "$resolucao_count" -ge "$MIN_SCENARIOS" ]; then
    pass "[$module_name] Resoluções documentadas: $resolucao_count ocorrências"
  else
    fail "[$module_name] Resoluções insuficientes: $resolucao_count (mínimo esperado: $MIN_SCENARIOS)"
  fi
done

echo ""

# =============================================================================
# Verificação 4: Comandos potencialmente falíveis têm cobertura
# =============================================================================

echo -e "${YELLOW}--- Verificando cobertura de comandos que podem falhar ---${NC}"
echo ""

# Padrões de comandos que tipicamente podem falhar em um lab Kubernetes
FAILABLE_PATTERNS=(
  "systemctl start\|systemctl restart\|systemctl enable"
  "apt-get install\|apt install"
  "curl.*download\|wget"
  "kubectl.*create\|kubectl.*apply"
  "ssh "
  "openssl"
  "etcdctl"
  "modprobe"
)

MODULE_PASS_COUNT=0
MODULE_FAIL_COUNT=0

for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  if [ ! -d "$module_dir" ]; then
    continue
  fi

  module_name=$(basename "$module_dir")
  readme_file="$module_dir/README.md"

  if [ ! -f "$readme_file" ]; then
    continue
  fi

  # Verificar se o módulo tem comandos que podem falhar
  has_failable_commands=false
  for pattern in "${FAILABLE_PATTERNS[@]}"; do
    if grep -qi "$pattern" "$readme_file"; then
      has_failable_commands=true
      break
    fi
  done

  if [ "$has_failable_commands" = true ]; then
    # Contar cenários de troubleshooting
    scenario_count=$(grep -ci "^### Problema" "$readme_file" || echo "0")

    if [ "$scenario_count" -ge "$MIN_SCENARIOS" ]; then
      pass "[$module_name] Módulo com comandos falíveis tem $scenario_count cenários de troubleshooting"
      MODULE_PASS_COUNT=$((MODULE_PASS_COUNT + 1))
    else
      fail "[$module_name] Módulo com comandos falíveis tem apenas $scenario_count cenário(s) (mínimo: $MIN_SCENARIOS)"
      MODULE_FAIL_COUNT=$((MODULE_FAIL_COUNT + 1))
    fi
  else
    info "[$module_name] Nenhum comando potencialmente falível identificado (módulo informativo)"
  fi
done

echo ""

# =============================================================================
# Resumo por Módulo
# =============================================================================

echo -e "${YELLOW}--- Resumo de cenários por módulo ---${NC}"
echo ""
printf "  %-35s %s\n" "MÓDULO" "CENÁRIOS"
printf "  %-35s %s\n" "-----------------------------------" "--------"

for module_dir in "$DOCS_DIR"/[0-9][0-9]-*/; do
  if [ ! -d "$module_dir" ]; then
    continue
  fi

  module_name=$(basename "$module_dir")
  readme_file="$module_dir/README.md"

  if [ ! -f "$readme_file" ]; then
    printf "  %-35s %s\n" "$module_name" "N/A (sem README)"
    continue
  fi

  scenario_count=$(grep -ci "^### Problema" "$readme_file" || echo "0")

  if [ "$scenario_count" -ge "$MIN_SCENARIOS" ]; then
    printf "  %-35s ${GREEN}%s${NC}\n" "$module_name" "$scenario_count ✅"
  else
    printf "  %-35s ${RED}%s${NC}\n" "$module_name" "$scenario_count ❌"
  fi
done

echo ""

# =============================================================================
# Resumo Final
# =============================================================================

echo "============================================================"
echo "RESUMO"
echo "============================================================"
echo "Total de módulos analisados: $TOTAL_MODULES"
echo "Total de verificações:       $TOTAL_CHECKS"
echo -e "Aprovadas:                   ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Reprovadas:                  ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Cobertura de troubleshooting está adequada.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Cobertura de troubleshooting está incompleta.${NC}"
  exit 1
fi
