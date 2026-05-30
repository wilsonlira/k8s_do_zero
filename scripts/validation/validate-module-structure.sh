#!/bin/bash
# =============================================================================
# Property 1: Completude da Estrutura dos Módulos
# =============================================================================
# Validates: Requirements 13.1
#
# Este script escaneia cada docs/XX-*/README.md e verifica que todas as seções
# obrigatórias existem na ordem correta:
#   1. Objetivo
#   2. Teoria
#   3. Pré-requisitos
#   4. Comandos Passo a Passo
#   5. Verificação
#   6. Troubleshooting
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
NC='\033[0m' # Sem cor

# Contadores globais
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
MODULES_CHECKED=0
MODULES_PASSED=0
MODULES_FAILED=0

# Seções obrigatórias na ordem esperada
REQUIRED_SECTIONS=(
  "Objetivo"
  "Teoria"
  "Pré-requisitos"
  "Comandos Passo a Passo"
  "Verificação"
  "Troubleshooting"
)

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

# Extrai os números de linha das seções de nível 2 (## ) de um arquivo
# Retorna pares "linha:nome_da_seção"
extract_sections() {
  local file="$1"
  grep -n "^## " "$file" | sed 's/^[0-9]*:## //' || true
}

# Verifica se uma seção existe no arquivo (busca por ## Nome)
section_exists() {
  local file="$1"
  local section="$2"
  grep -q "^## ${section}$" "$file" 2>/dev/null || \
  grep -q "^## ${section}" "$file" 2>/dev/null
}

# Retorna o número da linha onde a seção aparece (0 se não encontrada)
section_line_number() {
  local file="$1"
  local section="$2"
  local line_num
  line_num=$(grep -n "^## ${section}" "$file" 2>/dev/null | head -1 | cut -d: -f1)
  echo "${line_num:-0}"
}

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 1: Completude da Estrutura dos Módulos"
echo "Validates: Requirements 13.1"
echo "============================================================"
echo ""

if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de documentação não encontrado: $DOCS_DIR${NC}"
  exit 1
fi

# Encontrar todos os módulos (diretórios com padrão XX-*)
MODULE_DIRS=$(find "$DOCS_DIR" -maxdepth 1 -type d -name "[0-9][0-9]-*" | sort)

if [ -z "$MODULE_DIRS" ]; then
  echo -e "${RED}ERRO: Nenhum módulo encontrado em $DOCS_DIR${NC}"
  exit 1
fi

MODULE_COUNT=$(echo "$MODULE_DIRS" | wc -l)
echo "Módulos encontrados: $MODULE_COUNT"
echo ""

# =============================================================================
# Validação de Cada Módulo
# =============================================================================

while IFS= read -r module_dir; do
  module_name=$(basename "$module_dir")
  readme_file="$module_dir/README.md"

  MODULES_CHECKED=$((MODULES_CHECKED + 1))
  MODULE_HAS_ERROR=0

  echo -e "${YELLOW}--- Módulo: $module_name ---${NC}"

  # Verificar se README.md existe
  if [ ! -f "$readme_file" ]; then
    fail "[$module_name] README.md não encontrado"
    MODULE_HAS_ERROR=1
    echo ""
    MODULES_FAILED=$((MODULES_FAILED + 1))
    continue
  fi

  # -------------------------------------------------------------------------
  # Verificação 1: Todas as seções obrigatórias existem
  # -------------------------------------------------------------------------
  MISSING_SECTIONS=()

  for section in "${REQUIRED_SECTIONS[@]}"; do
    if section_exists "$readme_file" "$section"; then
      pass "[$module_name] Seção '## $section' encontrada"
    else
      fail "[$module_name] Seção '## $section' NÃO encontrada"
      MISSING_SECTIONS+=("$section")
      MODULE_HAS_ERROR=1
    fi
  done

  # -------------------------------------------------------------------------
  # Verificação 2: Seções estão na ordem correta
  # -------------------------------------------------------------------------
  # Só verifica ordem se todas as seções existem
  if [ ${#MISSING_SECTIONS[@]} -eq 0 ]; then
    PREV_LINE=0
    ORDER_OK=1

    for section in "${REQUIRED_SECTIONS[@]}"; do
      current_line=$(section_line_number "$readme_file" "$section")

      if [ "$current_line" -le "$PREV_LINE" ]; then
        ORDER_OK=0
        fail "[$module_name] Seção '## $section' (linha $current_line) está fora de ordem (deveria vir após linha $PREV_LINE)"
        MODULE_HAS_ERROR=1
      fi

      PREV_LINE=$current_line
    done

    if [ "$ORDER_OK" -eq 1 ]; then
      pass "[$module_name] Todas as seções estão na ordem correta"
    fi
  else
    echo -e "  ${YELLOW}⚠️  Verificação de ordem ignorada — seções ausentes: ${MISSING_SECTIONS[*]}${NC}"
  fi

  # Atualizar contadores de módulos
  if [ "$MODULE_HAS_ERROR" -eq 0 ]; then
    MODULES_PASSED=$((MODULES_PASSED + 1))
  else
    MODULES_FAILED=$((MODULES_FAILED + 1))
  fi

  echo ""
done <<< "$MODULE_DIRS"

# =============================================================================
# Resumo
# =============================================================================

echo "============================================================"
echo "RESUMO"
echo "============================================================"
echo "Módulos verificados:   $MODULES_CHECKED"
echo -e "Módulos aprovados:     ${GREEN}$MODULES_PASSED${NC}"
echo -e "Módulos reprovados:    ${RED}$MODULES_FAILED${NC}"
echo ""
echo "Total de verificações: $TOTAL_CHECKS"
echo -e "Aprovadas:             ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Reprovadas:            ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Estrutura dos módulos está completa e ordenada.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Estrutura dos módulos está incompleta ou desordenada.${NC}"
  exit 1
fi
