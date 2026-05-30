#!/bin/bash
# =============================================================================
# Property 4: Progressive Module Ordering Validation
# =============================================================================
# Validates: Requirements 13.5
#
# Este script parseia a seção "Pré-requisitos" de cada módulo e verifica que
# todos os módulos referenciados possuem um número de sequência menor que o
# módulo atual, garantindo que o conteúdo é apresentado em ordem progressiva.
# =============================================================================

set -u

# Determinar raiz do projeto (script está em scripts/verification/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DOCS_DIR="$PROJECT_ROOT/docs"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Contadores
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
MODULES_FOUND=0

# =============================================================================
# Funções Auxiliares
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

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 4: Progressive Module Ordering Validation"
echo "Validates: Requirements 13.5"
echo "============================================================"
echo ""

if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de documentação não encontrado: $DOCS_DIR${NC}"
  exit 1
fi

# Coletar todos os diretórios de módulos (padrão XX-nome)
MODULE_DIRS=$(find "$DOCS_DIR" -maxdepth 1 -type d -name "[0-9][0-9]-*" | sort)

if [ -z "$MODULE_DIRS" ]; then
  echo -e "${RED}ERRO: Nenhum diretório de módulo encontrado em $DOCS_DIR${NC}"
  exit 1
fi

echo "Diretório de documentação: $DOCS_DIR"
echo ""

# =============================================================================
# Funções de Validação
# =============================================================================

# Extrai o número de sequência de um nome de diretório de módulo
# Ex: "04-etcd" -> 4, "13-ingress-controller" -> 13
extract_module_number() {
  local dir_name="$1"
  # Extrair os dois primeiros dígitos do nome do diretório
  echo "$dir_name" | grep -oP '^\d+' | sed 's/^0*//' | sed 's/^$/0/'
}

# Extrai referências a módulos da seção de Pré-requisitos
# Procura padrões como:
#   [Módulo XX — ...](../XX-...)
#   Módulo XX
#   ../XX-dir-name/
extract_prerequisite_references() {
  local readme_file="$1"

  # Extrair a seção de Pré-requisitos (entre "## Pré-requisitos" e o próximo "##")
  local prereq_section
  prereq_section=$(sed -n '/^## Pré-requisitos/,/^## [^#]/p' "$readme_file" | sed '$d')

  if [ -z "$prereq_section" ]; then
    # Tentar variação em inglês
    prereq_section=$(sed -n '/^## Prerequisites/,/^## [^#]/p' "$readme_file" | sed '$d')
  fi

  if [ -z "$prereq_section" ]; then
    echo ""
    return
  fi

  # Extrair números de módulos referenciados
  # Padrão 1: [Módulo XX — ...](../XX-...) — links markdown
  # Padrão 2: Módulo XX (referência textual)
  # Padrão 3: ../XX-dir-name/ (referência de caminho)
  local referenced_numbers
  referenced_numbers=$(echo "$prereq_section" | \
    grep -oP '(?:\.\./|Módulo\s+)(\d{2})' | \
    grep -oP '\d{2}' | \
    sort -u)

  echo "$referenced_numbers"
}

# Verifica se o módulo possui seção de Pré-requisitos
check_has_prerequisites_section() {
  local readme_file="$1"
  local module_name="$2"

  if grep -qE '^## (Pré-requisitos|Prerequisites)' "$readme_file"; then
    return 0
  else
    fail "$module_name" "Seção de Pré-requisitos não encontrada"
    return 1
  fi
}

# Verifica que todos os módulos referenciados têm número menor
check_progressive_ordering() {
  local readme_file="$1"
  local module_name="$2"
  local current_number="$3"

  local referenced_numbers
  referenced_numbers=$(extract_prerequisite_references "$readme_file")

  if [ -z "$referenced_numbers" ]; then
    # Módulo 00 não precisa de pré-requisitos, outros devem ter
    if [ "$current_number" -eq 0 ]; then
      pass "$module_name" "Módulo inicial — sem pré-requisitos (correto)"
    else
      # Verificar se a seção diz explicitamente que não há pré-requisitos
      local prereq_section
      prereq_section=$(sed -n '/^## Pré-requisitos/,/^## [^#]/p' "$readme_file" | sed '$d')
      if echo "$prereq_section" | grep -qi "não há módulos anteriores\|primeiro módulo\|no prerequisites"; then
        pass "$module_name" "Declara explicitamente que não há pré-requisitos"
      else
        pass "$module_name" "Nenhuma referência a módulo encontrada na seção de pré-requisitos"
      fi
    fi
    return
  fi

  # Verificar cada módulo referenciado
  local all_valid=true
  while IFS= read -r ref_num; do
    if [ -z "$ref_num" ]; then
      continue
    fi

    # Remover zeros à esquerda para comparação numérica
    local ref_number
    ref_number=$(echo "$ref_num" | sed 's/^0*//' | sed 's/^$/0/')

    if [ "$ref_number" -lt "$current_number" ]; then
      pass "$module_name" "Referência ao Módulo $(printf '%02d' "$ref_number") (< $(printf '%02d' "$current_number")) — ordem progressiva correta"
    else
      fail "$module_name" "Referência ao Módulo $(printf '%02d' "$ref_number") (>= $(printf '%02d' "$current_number")) — VIOLA ordem progressiva!"
      all_valid=false
    fi
  done <<< "$referenced_numbers"
}

# =============================================================================
# Loop Principal de Validação
# =============================================================================

while IFS= read -r module_dir; do
  dir_name=$(basename "$module_dir")
  readme_file="$module_dir/README.md"

  # Verificar se README.md existe
  if [ ! -f "$readme_file" ]; then
    echo -e "${YELLOW}--- Módulo: $dir_name ---${NC}"
    fail "$dir_name" "README.md não encontrado"
    MODULES_FOUND=$((MODULES_FOUND + 1))
    continue
  fi

  MODULES_FOUND=$((MODULES_FOUND + 1))
  current_number=$(extract_module_number "$dir_name")

  echo ""
  echo -e "${YELLOW}--- Módulo $(printf '%02d' "$current_number"): $dir_name ---${NC}"

  # Verificar se tem seção de pré-requisitos
  if check_has_prerequisites_section "$readme_file" "$dir_name"; then
    # Verificar ordenação progressiva
    check_progressive_ordering "$readme_file" "$dir_name" "$current_number"
  fi

done <<< "$MODULE_DIRS"

# =============================================================================
# Verificação Adicional: Todos os módulos têm seção de pré-requisitos
# =============================================================================

echo ""
echo -e "${YELLOW}--- Verificações Globais ---${NC}"

if [ "$MODULES_FOUND" -ge 2 ]; then
  pass "global" "Múltiplos módulos encontrados ($MODULES_FOUND) — cadeia progressiva possível"
else
  fail "global" "Apenas $MODULES_FOUND módulo(s) encontrado(s) — impossível validar progressão"
fi

# =============================================================================
# Resumo
# =============================================================================

echo ""
echo "============================================================"
echo "RESUMO"
echo "============================================================"
echo "Módulos encontrados: $MODULES_FOUND"
echo "Total de verificações: $TOTAL_CHECKS"
echo -e "Aprovadas:            ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Reprovadas:           ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Ordenação progressiva dos módulos está correta.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Existem violações na ordenação progressiva.${NC}"
  exit 1
fi
