#!/bin/bash
# =============================================================================
# Property 4: Ordenação Progressiva dos Módulos
# =============================================================================
# Validates: Requirements 13.5
#
# Este script parseia a seção "Pré-requisitos" de cada módulo e verifica que
# todos os módulos referenciados possuem um número de sequência menor que o
# módulo atual, garantindo que o conteúdo é apresentado em ordem progressiva.
#
# Formato esperado de referência:
#   [Módulo XX — Nome](../XX-dirname/)
#
# Regra: Para todo módulo N, qualquer módulo M referenciado nos pré-requisitos
#         deve satisfazer M < N.
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

# Extrai o número de sequência de um nome de diretório de módulo (ex: "04-etcd" → 4)
extract_module_number() {
  local module_name="$1"
  echo "$module_name" | grep -oP '^\d+' | sed 's/^0*//' | sed 's/^$/0/'
}

# Extrai a seção de Pré-requisitos de um arquivo README.md
# Retorna o conteúdo entre "## Pré-requisitos" e a próxima seção "## "
extract_prerequisites_section() {
  local file="$1"
  sed -n '/^## Pré-requisitos/,/^## [^P]/p' "$file" | head -n -1
}

# Extrai números de módulos referenciados na seção de pré-requisitos
# Busca padrões como: [Módulo XX — ...](../XX-...) ou referências a "Módulo XX"
extract_referenced_modules() {
  local section_content="$1"
  # Padrão 1: Links markdown [Módulo XX — Nome](../XX-dirname/)
  # Padrão 2: Referências textuais "Módulo XX"
  echo "$section_content" | grep -oP '\[Módulo\s+\K\d+' | sort -n | uniq
}

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 4: Ordenação Progressiva dos Módulos"
echo "Validates: Requirements 13.5"
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
    MODULES_FAILED=$((MODULES_FAILED + 1))
    echo ""
    continue
  fi

  # Extrair número de sequência do módulo atual
  CURRENT_NUMBER=$(extract_module_number "$module_name")

  # Verificar se a seção de Pré-requisitos existe
  if ! grep -q "^## Pré-requisitos" "$readme_file"; then
    fail "[$module_name] Seção '## Pré-requisitos' não encontrada"
    MODULE_HAS_ERROR=1
    MODULES_FAILED=$((MODULES_FAILED + 1))
    echo ""
    continue
  fi

  # Extrair conteúdo da seção de Pré-requisitos
  PREREQ_CONTENT=$(extract_prerequisites_section "$readme_file")

  # Extrair módulos referenciados
  REFERENCED_MODULES=$(extract_referenced_modules "$PREREQ_CONTENT")

  # Se não há referências a outros módulos, verificar se é o módulo 00
  if [ -z "$REFERENCED_MODULES" ]; then
    if [ "$CURRENT_NUMBER" -eq 0 ]; then
      pass "[$module_name] Módulo inicial — sem pré-requisitos (correto)"
    else
      # Módulos não-iniciais sem referências explícitas: apenas aviso
      echo -e "  ${YELLOW}⚠️  [$module_name] Nenhuma referência a módulos anteriores encontrada na seção de Pré-requisitos${NC}"
      TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
  else
    # Verificar cada módulo referenciado
    ALL_REFS_VALID=1

    while IFS= read -r ref_num; do
      # Remover zeros à esquerda para comparação numérica
      REF_NUMBER=$(echo "$ref_num" | sed 's/^0*//' | sed 's/^$/0/')

      if [ "$REF_NUMBER" -lt "$CURRENT_NUMBER" ]; then
        pass "[$module_name] Referência ao Módulo $ref_num (seq $REF_NUMBER < $CURRENT_NUMBER) — ordem progressiva válida"
      else
        fail "[$module_name] Referência ao Módulo $ref_num (seq $REF_NUMBER >= $CURRENT_NUMBER) — VIOLA ordem progressiva!"
        MODULE_HAS_ERROR=1
        ALL_REFS_VALID=0
      fi
    done <<< "$REFERENCED_MODULES"

    if [ "$ALL_REFS_VALID" -eq 1 ]; then
      pass "[$module_name] Todas as referências de pré-requisitos respeitam a ordem progressiva"
    fi
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
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Ordenação progressiva dos módulos está correta.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Existem violações na ordem progressiva dos módulos.${NC}"
  exit 1
fi
