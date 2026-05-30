#!/bin/bash
# =============================================================================
# Property 2: Completude da Documentação de Comandos
# =============================================================================
# Validates: Requirements 13.2, 13.3
#
# Este script escaneia todos os módulos (docs/XX-*/README.md) e verifica que
# cada bloco de código (```bash) na seção "Comandos Passo a Passo" é:
#   1. Precedido por uma descrição explicando o que o comando faz e por quê
#   2. Seguido por uma seção de saída esperada ("Saída esperada:")
#
# Regras de validação:
#   - Blocos de código na seção "Comandos Passo a Passo" devem ter descrição
#   - A descrição deve ser texto não-vazio antes do bloco de código
#   - Após o bloco de código, deve haver "Saída esperada:" (com ou sem **)
#   - Blocos de código em seções Teoria, Pré-requisitos são excluídos
#     (diagramas, exemplos ilustrativos não precisam de saída esperada)
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
TOTAL_CODE_BLOCKS=0
BLOCKS_WITH_DESCRIPTION=0
BLOCKS_WITHOUT_DESCRIPTION=0
BLOCKS_WITH_OUTPUT=0
BLOCKS_WITHOUT_OUTPUT=0
MODULES_CHECKED=0
MODULES_PASSED=0
MODULES_FAILED=0

# =============================================================================
# Funções Auxiliares
# =============================================================================

pass() {
  local msg="$1"
  echo -e "  ${GREEN}✅ PASS${NC} $msg"
}

fail() {
  local msg="$1"
  echo -e "  ${RED}❌ FAIL${NC} $msg"
}

warn() {
  local msg="$1"
  echo -e "  ${YELLOW}⚠️  WARN${NC} $msg"
}

# =============================================================================
# Função principal de validação de um módulo
# =============================================================================

validate_module() {
  local readme_file="$1"
  local module_name="$2"
  local module_errors=0

  # Ler o arquivo inteiro em um array de linhas (removendo \r de CRLF)
  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    lines+=("$line")
  done < "$readme_file"

  local total_lines=${#lines[@]}

  # Encontrar o início da seção "Comandos Passo a Passo"
  local commands_section_start=-1
  local commands_section_end=-1

  for ((i=0; i<total_lines; i++)); do
    if [[ "${lines[$i]}" =~ ^##[[:space:]]+Comandos[[:space:]]+Passo[[:space:]]+a[[:space:]]+Passo ]]; then
      commands_section_start=$i
    fi
  done

  # Se não encontrou a seção de comandos, pular (Property 1 cobre isso)
  if [[ $commands_section_start -eq -1 ]]; then
    warn "[$module_name] Seção 'Comandos Passo a Passo' não encontrada — ignorando"
    return 0
  fi

  # Encontrar o fim da seção (próximo ## de nível 2)
  for ((i=commands_section_start+1; i<total_lines; i++)); do
    if [[ "${lines[$i]}" =~ ^##[[:space:]] && ! "${lines[$i]}" =~ ^###[[:space:]] ]]; then
      commands_section_end=$i
      break
    fi
  done

  # Se não encontrou fim, vai até o final do arquivo
  if [[ $commands_section_end -eq -1 ]]; then
    commands_section_end=$total_lines
  fi

  # Também incluir a seção "Verificação" pois contém comandos documentados
  local verification_section_start=-1
  local verification_section_end=-1

  for ((i=0; i<total_lines; i++)); do
    if [[ "${lines[$i]}" =~ ^##[[:space:]]+Verificação ]]; then
      verification_section_start=$i
    fi
  done

  if [[ $verification_section_start -ne -1 ]]; then
    for ((i=verification_section_start+1; i<total_lines; i++)); do
      if [[ "${lines[$i]}" =~ ^##[[:space:]] && ! "${lines[$i]}" =~ ^###[[:space:]] ]]; then
        verification_section_end=$i
        break
      fi
    done
    if [[ $verification_section_end -eq -1 ]]; then
      verification_section_end=$total_lines
    fi
  fi

  # Iterar sobre blocos de código bash nas seções relevantes
  local in_code_block=0
  local code_block_start=-1
  local code_block_lang=""

  for ((i=0; i<total_lines; i++)); do
    local line="${lines[$i]}"

    # Verificar se estamos dentro de uma seção relevante
    local in_relevant_section=0
    if [[ $i -ge $commands_section_start && $i -lt $commands_section_end ]]; then
      in_relevant_section=1
    fi
    if [[ $verification_section_start -ne -1 && $i -ge $verification_section_start && $i -lt $verification_section_end ]]; then
      in_relevant_section=1
    fi

    # Pular se não estamos em seção relevante
    if [[ $in_relevant_section -eq 0 ]]; then
      continue
    fi

    # Detectar início de bloco de código
    if [[ $in_code_block -eq 0 && "$line" =~ ^\`\`\`(bash|shell|sh)$ ]]; then
      in_code_block=1
      code_block_start=$i
      code_block_lang="${BASH_REMATCH[1]}"
      continue
    fi

    # Detectar fim de bloco de código
    if [[ $in_code_block -eq 1 && "$line" =~ ^\`\`\`$ ]]; then
      in_code_block=0
      local code_block_end=$i
      local line_num=$((code_block_start + 1))  # 1-indexed para exibição

      TOTAL_CODE_BLOCKS=$((TOTAL_CODE_BLOCKS + 1))

      # -----------------------------------------------------------------------
      # Verificação 1: Bloco de código é precedido por descrição
      # -----------------------------------------------------------------------
      # A descrição pode ser:
      #   - Um parágrafo de texto antes do bloco de código
      #   - Um header (###) antes do bloco
      #   - Uma nota (>) antes do bloco
      #   - Uma seção "Explicação:" do bloco anterior (serve como contexto)
      #   - Uma lista (-) antes do bloco
      #   - Texto entre o bloco de código anterior e este bloco
      local has_description=0
      local search_start=$((code_block_start - 1))

      # Procurar para trás, pulando linhas em branco
      for ((j=search_start; j>=0 && j>=(code_block_start-15); j--)); do
        local prev_line="${lines[$j]}"

        # Pular linhas em branco
        if [[ -z "$prev_line" || "$prev_line" =~ ^[[:space:]]*$ ]]; then
          continue
        fi

        # Se encontramos o fim de um bloco de código anterior (```),
        # verificar se há texto descritivo entre esse bloco e o atual
        if [[ "$prev_line" =~ ^\`\`\`$ ]]; then
          # Procurar entre o bloco anterior e este por qualquer texto descritivo
          for ((k=j+1; k<code_block_start; k++)); do
            local between_line="${lines[$k]}"
            # Pular linhas em branco
            if [[ -z "$between_line" || "$between_line" =~ ^[[:space:]]*$ ]]; then
              continue
            fi
            # Qualquer texto com 3+ caracteres conta como descrição
            if [[ ${#between_line} -ge 3 ]]; then
              has_description=1
              break
            fi
          done
          break
        fi

        # Se encontramos texto descritivo (não é apenas um marcador de seção vazio)
        # Aceitar: parágrafos, headers (###), notas (>), listas (-), bold text (**)
        if [[ ${#prev_line} -ge 3 ]]; then
          has_description=1
          break
        fi
      done

      if [[ $has_description -eq 1 ]]; then
        BLOCKS_WITH_DESCRIPTION=$((BLOCKS_WITH_DESCRIPTION + 1))
      else
        BLOCKS_WITHOUT_DESCRIPTION=$((BLOCKS_WITHOUT_DESCRIPTION + 1))
        fail "[$module_name] Linha $line_num: Bloco de código sem descrição precedente"
        module_errors=$((module_errors + 1))
      fi

      # -----------------------------------------------------------------------
      # Verificação 2: Bloco de código é seguido por saída esperada
      # -----------------------------------------------------------------------
      # Aceita como válido:
      #   - "Saída esperada:" (padrão principal)
      #   - "Expected output:" (variação em inglês)
      #   - "Explicação:" (para comandos que não produzem saída visível)
      #   - "Nenhuma saída" (indica que ausência de output é o esperado)
      #   - "Arquivos gerados:" (para comandos que geram arquivos)
      local has_expected_output=0
      local search_end=$((code_block_end + 15))  # Procurar até 15 linhas após

      if [[ $search_end -gt $total_lines ]]; then
        search_end=$total_lines
      fi

      for ((j=code_block_end+1; j<search_end; j++)); do
        local next_line="${lines[$j]}"

        # Pular linhas em branco
        if [[ -z "$next_line" || "$next_line" =~ ^[[:space:]]*$ ]]; then
          continue
        fi

        # Verificar se é "Saída esperada:" (com ou sem bold **)
        if [[ "$next_line" =~ [Ss]aída[[:space:]]+esperada ]]; then
          has_expected_output=1
          break
        fi

        # Verificar variações: "Expected output:"
        if [[ "$next_line" =~ [Ee]xpected[[:space:]]+[Oo]utput ]]; then
          has_expected_output=1
          break
        fi

        # Aceitar "Explicação:" como alternativa válida
        # (para comandos que criam arquivos ou não produzem saída)
        if [[ "$next_line" =~ ^\*\*Explicação ]]; then
          has_expected_output=1
          break
        fi

        # Aceitar "Nenhuma saída" como indicação de output esperado
        if [[ "$next_line" =~ [Nn]enhuma[[:space:]]+saída ]]; then
          has_expected_output=1
          break
        fi

        # Aceitar "Arquivos gerados:" como resultado documentado
        if [[ "$next_line" =~ ^\*\*Arquivos[[:space:]]+gerados ]]; then
          has_expected_output=1
          break
        fi

        # Se encontramos outro bloco de código bash (próximo comando), parar
        if [[ "$next_line" =~ ^\`\`\`(bash|shell|sh)$ ]]; then
          break
        fi

        # Se encontramos um header de seção (### ou ##), parar
        if [[ "$next_line" =~ ^##+ ]]; then
          break
        fi

        # Se encontramos texto que não é saída esperada, continuar procurando
        # (pode ser uma nota ou explicação intermediária)
        continue
      done

      if [[ $has_expected_output -eq 1 ]]; then
        BLOCKS_WITH_OUTPUT=$((BLOCKS_WITH_OUTPUT + 1))
      else
        BLOCKS_WITHOUT_OUTPUT=$((BLOCKS_WITHOUT_OUTPUT + 1))
        fail "[$module_name] Linha $line_num: Bloco de código sem 'Saída esperada' subsequente"
        module_errors=$((module_errors + 1))
      fi

      continue
    fi
  done

  return $module_errors
}

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 2: Completude da Documentação de Comandos"
echo "Validates: Requirements 13.2, 13.3"
echo "============================================================"
echo ""

if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de documentação não encontrado: $DOCS_DIR${NC}"
  exit 1
fi

# Encontrar todos os módulos
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

  echo -e "${YELLOW}--- Módulo: $module_name ---${NC}"

  # Verificar se README.md existe
  if [ ! -f "$readme_file" ]; then
    warn "[$module_name] README.md não encontrado — ignorando"
    echo ""
    continue
  fi

  # Validar o módulo
  module_errors=0
  validate_module "$readme_file" "$module_name" || module_errors=$?

  if [ "$module_errors" -eq 0 ]; then
    pass "[$module_name] Todos os blocos de código têm descrição e saída esperada"
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
echo "Módulos verificados:          $MODULES_CHECKED"
echo -e "Módulos aprovados:            ${GREEN}$MODULES_PASSED${NC}"
echo -e "Módulos reprovados:           ${RED}$MODULES_FAILED${NC}"
echo ""
echo "Total de blocos de código:    $TOTAL_CODE_BLOCKS"
echo -e "Com descrição precedente:     ${GREEN}$BLOCKS_WITH_DESCRIPTION${NC}"
echo -e "Sem descrição precedente:     ${RED}$BLOCKS_WITHOUT_DESCRIPTION${NC}"
echo -e "Com saída esperada:           ${GREEN}$BLOCKS_WITH_OUTPUT${NC}"
echo -e "Sem saída esperada:           ${RED}$BLOCKS_WITHOUT_OUTPUT${NC}"
echo ""

TOTAL_FAILURES=$((BLOCKS_WITHOUT_DESCRIPTION + BLOCKS_WITHOUT_OUTPUT))

if [ "$TOTAL_FAILURES" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Todos os comandos têm descrição e saída esperada.${NC}"
  exit 0
else
  echo -e "${RED}❌ $TOTAL_FAILURES PROBLEMA(S) ENCONTRADO(S) — Alguns comandos não têm descrição ou saída esperada.${NC}"
  exit 1
fi
