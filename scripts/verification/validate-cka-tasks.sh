#!/bin/bash
# =============================================================================
# Property 7: CKA Task Completeness Validation
# =============================================================================
# Validates: Requirements 14.2, 14.3, 14.5, 14.6
#
# Este script escaneia todos os arquivos cka-simulator/tasks/task-*.md e verifica
# que cada tarefa possui:
#   1. Tempo limite entre 5 e 20 minutos
#   2. Comandos/requisitos a serem executados no cluster
#   3. Arquivo de solução correspondente em cka-simulator/solutions/
#   4. Seção de comandos de verificação
# =============================================================================

set -u

# Determinar raiz do projeto (script está em scripts/verification/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TASKS_DIR="$PROJECT_ROOT/cka-simulator/tasks"
SOLUTIONS_DIR="$PROJECT_ROOT/cka-simulator/solutions"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Contadores
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
TASKS_FOUND=0

# =============================================================================
# Funções Auxiliares
# =============================================================================

pass() {
  local task="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "  ${GREEN}✅ PASS${NC} [$task] $check"
}

fail() {
  local task="$1"
  local check="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "  ${RED}❌ FAIL${NC} [$task] $check"
}

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 7: CKA Task Completeness Validation"
echo "Validates: Requirements 14.2, 14.3, 14.5, 14.6"
echo "============================================================"
echo ""

if [ ! -d "$TASKS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de tarefas não encontrado: $TASKS_DIR${NC}"
  exit 1
fi

if [ ! -d "$SOLUTIONS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de soluções não encontrado: $SOLUTIONS_DIR${NC}"
  exit 1
fi

# Coletar todos os arquivos de tarefa
TASK_FILES=$(find "$TASKS_DIR" -name "task-*.md" -type f | sort)

if [ -z "$TASK_FILES" ]; then
  echo -e "${RED}ERRO: Nenhum arquivo task-*.md encontrado em $TASKS_DIR${NC}"
  exit 1
fi

echo "Diretório de tarefas: $TASKS_DIR"
echo "Diretório de soluções: $SOLUTIONS_DIR"
echo ""

# =============================================================================
# Funções de Validação
# =============================================================================

# Verifica se a tarefa possui tempo limite entre 5 e 20 minutos
# Req 14.2: cada tarefa com tempo recomendado entre 5 e 20 minutos
check_time_limit() {
  local task_file="$1"
  local task_name="$2"
  local content="$3"

  # Procurar padrão "Tempo recomendado: X minutos" ou variações
  local time_line
  time_line=$(echo "$content" | grep -iE '(Tempo recomendado|Time limit|Tempo).*[0-9]+.*min' || true)

  local time_value=""
  if [ -n "$time_line" ]; then
    time_value=$(echo "$time_line" | grep -oE '[0-9]+' | head -1 || true)
  fi

  if [ -z "$time_value" ]; then
    fail "$task_name" "Tempo limite não encontrado"
    return
  fi

  if [ "$time_value" -ge 5 ] && [ "$time_value" -le 20 ]; then
    pass "$task_name" "Tempo limite: ${time_value} min (dentro de 5-20 min)"
  else
    fail "$task_name" "Tempo limite: ${time_value} min (fora do intervalo 5-20 min)"
  fi
}

# Verifica se a tarefa possui requisitos/comandos a serem executados
# Req 14.3: tarefas que requerem execução de comandos no cluster
check_commands_to_execute() {
  local task_file="$1"
  local task_name="$2"
  local content="$3"

  # Verificar presença de seção "Requisitos" ou "Requirements"
  local has_section
  has_section=$(echo "$content" | grep -ciE '^#{1,3}\s*(Requisitos|Requirements|Tarefas|Tasks)' || true)

  if [ "$has_section" -gt 0 ]; then
    # Verificar que a seção contém itens numerados ou comandos kubectl/etcdctl/etc.
    local has_commands
    has_commands=$(echo "$content" | grep -ciE '^[0-9]+\.\s+|kubectl|etcdctl|curl|systemctl|crictl|kubeadm' || true)
    if [ "$has_commands" -gt 0 ]; then
      pass "$task_name" "Comandos/requisitos para execução no cluster presentes"
    else
      fail "$task_name" "Seção de requisitos encontrada mas sem comandos de cluster"
    fi
  else
    fail "$task_name" "Seção de Requisitos não encontrada"
  fi
}

# Verifica se existe arquivo de solução correspondente
# Req 14.5: solução com comandos, output esperado e explicação
check_corresponding_solution() {
  local task_file="$1"
  local task_name="$2"

  # Extrair número da tarefa do nome do arquivo (task-01.md -> 01)
  local task_number
  task_number=$(basename "$task_file" | grep -oP '\d+')

  # Verificar se existe arquivo de solução correspondente
  local solution_file="$SOLUTIONS_DIR/task-${task_number}-solution.md"

  if [ -f "$solution_file" ]; then
    # Verificar que a solução não está vazia (tem conteúdo significativo)
    local solution_size
    solution_size=$(wc -c < "$solution_file")
    if [ "$solution_size" -gt 100 ]; then
      pass "$task_name" "Solução correspondente encontrada: task-${task_number}-solution.md"
    else
      fail "$task_name" "Arquivo de solução existe mas parece vazio (< 100 bytes)"
    fi
  else
    fail "$task_name" "Solução não encontrada: task-${task_number}-solution.md"
  fi
}

# Verifica se a tarefa possui seção de comandos de verificação
# Req 14.6: comandos de verificação com resultados esperados para auto-avaliação
check_verification_commands() {
  local task_file="$1"
  local task_name="$2"
  local content="$3"

  # Verificar presença de seção "Comandos de Verificação" ou "Verification"
  local has_section
  has_section=$(echo "$content" | grep -ciE '^#{1,3}\s*(Comandos de Verificação|Verification Commands|Verificação|Critérios de Aprovação)' || true)

  if [ "$has_section" -gt 0 ]; then
    # Verificar que contém blocos de código com comandos
    local has_code_blocks
    has_code_blocks=$(echo "$content" | grep -c '```' || true)
    if [ "$has_code_blocks" -gt 0 ]; then
      # Verificar que contém comentários de resultado esperado
      local has_expected
      has_expected=$(echo "$content" | grep -ciE '(Esperado|Expected|#.*Verificar|#.*Check)' || true)
      if [ "$has_expected" -gt 0 ]; then
        pass "$task_name" "Comandos de verificação com resultados esperados presentes"
      else
        fail "$task_name" "Comandos de verificação sem resultados esperados documentados"
      fi
    else
      fail "$task_name" "Seção de verificação sem blocos de código"
    fi
  else
    fail "$task_name" "Seção de Comandos de Verificação não encontrada"
  fi
}

# =============================================================================
# Loop Principal de Validação
# =============================================================================

while IFS= read -r task_file; do
  TASKS_FOUND=$((TASKS_FOUND + 1))
  task_name=$(basename "$task_file" .md)

  echo ""
  echo -e "${YELLOW}--- Verificando: $task_name ---${NC}"

  # Ler conteúdo do arquivo uma vez
  content=$(cat "$task_file")

  # Executar todas as verificações
  check_time_limit "$task_file" "$task_name" "$content"
  check_commands_to_execute "$task_file" "$task_name" "$content"
  check_corresponding_solution "$task_file" "$task_name"
  check_verification_commands "$task_file" "$task_name" "$content"

done <<< "$TASK_FILES"

# =============================================================================
# Verificação de Quantidade Mínima de Tarefas
# =============================================================================

echo ""
echo -e "${YELLOW}--- Verificação Adicional ---${NC}"

if [ "$TASKS_FOUND" -ge 15 ]; then
  pass "global" "Quantidade mínima de tarefas: $TASKS_FOUND (≥ 15 requeridas)"
else
  fail "global" "Quantidade insuficiente de tarefas: $TASKS_FOUND (mínimo 15 requeridas)"
fi

# =============================================================================
# Resumo
# =============================================================================

echo ""
echo "============================================================"
echo "RESUMO"
echo "============================================================"
echo "Tarefas encontradas: $TASKS_FOUND"
echo "Total de verificações: $TOTAL_CHECKS"
echo -e "Aprovadas:            ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Reprovadas:           ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Tarefas CKA estão completas.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Tarefas CKA estão incompletas.${NC}"
  exit 1
fi
