#!/bin/bash
# =============================================================================
# Verificação de Conectividade SSH
# =============================================================================
# Este script verifica a conectividade SSH para cada instância do cluster.
# Testa:
#   - Resolução de IP público de cada instância
#   - Conectividade na porta 22 (SSH)
#   - Autenticação SSH com a chave do projeto
#   - Execução de comando remoto básico
#
# Pré-requisitos:
#   - Instâncias EC2 provisionadas e no estado "running"
#   - Chave SSH gerada (scripts/infrastructure/create-keypair.sh)
#   - Security groups com porta 22 aberta
#
# Requirements: 1.5 (verificar recursos provisionados)
#               12.1 (verificar componentes reportando status)
# =============================================================================

set -euo pipefail

# Carrega variáveis centralizadas do projeto
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../variables.env"

# -----------------------------------------------------------------------------
# Variáveis de controle
# -----------------------------------------------------------------------------
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Configurações de SSH
SSH_USER="ubuntu"
SSH_KEY_PATH="${SCRIPT_DIR}/../../keys/${KEY_NAME}.pem"
SSH_TIMEOUT=10
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes -o LogLevel=ERROR"

# -----------------------------------------------------------------------------
# Funções auxiliares
# -----------------------------------------------------------------------------

# Registra um check que passou
check_pass() {
    local msg="$1"
    echo "  ✓ ${msg}"
    ((TOTAL_CHECKS++))
    ((PASSED_CHECKS++))
}

# Registra um check que falhou
check_fail() {
    local msg="$1"
    echo "  ✗ ${msg}"
    ((TOTAL_CHECKS++))
    ((FAILED_CHECKS++))
}

# Testa conectividade TCP em uma porta específica
test_tcp_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    # Usa timeout + bash /dev/tcp ou nc para testar a porta
    if command -v nc &> /dev/null; then
        nc -z -w "${timeout}" "${host}" "${port}" &> /dev/null
    elif command -v timeout &> /dev/null; then
        timeout "${timeout}" bash -c "echo >/dev/tcp/${host}/${port}" &> /dev/null
    else
        bash -c "echo >/dev/tcp/${host}/${port}" &> /dev/null
    fi
}

# Testa conexão SSH completa com execução de comando
test_ssh_connection() {
    local host="$1"
    local key="$2"

    ssh ${SSH_OPTIONS} -i "${key}" "${SSH_USER}@${host}" "echo 'SSH_OK'" 2>/dev/null
}

# Obtém informações do sistema remoto via SSH
get_remote_info() {
    local host="$1"
    local key="$2"

    ssh ${SSH_OPTIONS} -i "${key}" "${SSH_USER}@${host}" \
        "hostname && uname -r && cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"'" 2>/dev/null
}

# =============================================================================
# INÍCIO DA VERIFICAÇÃO
# =============================================================================

echo "============================================="
echo " Verificação de Conectividade SSH"
echo " Região: ${AWS_REGION}"
echo " Projeto: ${CLUSTER_NAME}"
echo "============================================="
echo ""

# -----------------------------------------------------------------------------
# Verificar pré-requisitos locais
# -----------------------------------------------------------------------------
echo "Verificando pré-requisitos locais..."

# Verifica se a chave SSH existe
if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo "  ERRO: Chave SSH não encontrada: ${SSH_KEY_PATH}"
    echo "    → Execute scripts/infrastructure/create-keypair.sh"
    echo "    → Ou exporte KEY_NAME com o nome correto da chave"
    exit 1
fi
echo "  ✓ Chave SSH encontrada: ${SSH_KEY_PATH}"

# Verifica permissões da chave (deve ser 400 ou 600)
KEY_PERMS=$(stat -c "%a" "${SSH_KEY_PATH}" 2>/dev/null || stat -f "%Lp" "${SSH_KEY_PATH}" 2>/dev/null || echo "unknown")
if [ "${KEY_PERMS}" = "400" ] || [ "${KEY_PERMS}" = "600" ]; then
    echo "  ✓ Permissões da chave: ${KEY_PERMS}"
elif [ "${KEY_PERMS}" = "unknown" ]; then
    echo "  ℹ Não foi possível verificar permissões da chave (Windows?)"
else
    echo "  ⚠ Permissões da chave: ${KEY_PERMS} (recomendado: 400)"
    echo "    → Execute: chmod 400 ${SSH_KEY_PATH}"
fi

# Verifica se ssh está disponível
if ! command -v ssh &> /dev/null; then
    echo "  ERRO: Comando 'ssh' não encontrado."
    echo "    → Instale o OpenSSH client"
    exit 1
fi
echo "  ✓ Cliente SSH disponível"
echo ""

# -----------------------------------------------------------------------------
# Obter IPs das instâncias
# -----------------------------------------------------------------------------
echo "Obtendo endereços IP das instâncias..."
echo ""

# Busca instâncias do projeto
INSTANCES_JSON=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" \
              "Name=instance-state-name,Values=running" \
    --region "${AWS_REGION}" \
    --query 'Reservations[].Instances[]' \
    --output json 2>/dev/null || echo "[]")

INSTANCE_COUNT=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "${INSTANCE_COUNT}" -eq 0 ]; then
    echo "  ERRO: Nenhuma instância running encontrada com tag Project='${CLUSTER_NAME}'"
    echo "    → Verifique se as instâncias estão no estado 'running'"
    echo "    → Execute: scripts/verification/verify-infrastructure.sh"
    exit 1
fi

echo "  Instâncias running encontradas: ${INSTANCE_COUNT}"
echo ""

# -----------------------------------------------------------------------------
# Testar conectividade para cada instância
# -----------------------------------------------------------------------------
for i in $(seq 0 $((INSTANCE_COUNT - 1))); do
    INST_ID=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[${i}]['InstanceId'])")
    INST_PUBLIC_IP=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[${i}].get('PublicIpAddress',''))")
    INST_PRIVATE_IP=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[${i}].get('PrivateIpAddress',''))")
    INST_NAME=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); tags=d[${i}].get('Tags',[]); print(next((t['Value'] for t in tags if t['Key']=='Name'),'sem-nome'))")
    INST_ROLE=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); tags=d[${i}].get('Tags',[]); print(next((t['Value'] for t in tags if t['Key']=='Role'),'desconhecido'))")

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Testando: ${INST_NAME} (${INST_ROLE})"
    echo " ID: ${INST_ID}"
    echo " IP Público: ${INST_PUBLIC_IP:-N/A}"
    echo " IP Privado: ${INST_PRIVATE_IP}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Verifica se tem IP público
    if [ -z "${INST_PUBLIC_IP}" ] || [ "${INST_PUBLIC_IP}" = "None" ]; then
        check_fail "IP público não disponível — não é possível conectar via SSH externo"
        echo "    → Verifique se a subnet tem 'auto-assign public IP' habilitado"
        echo "    → Ou associe um Elastic IP à instância"
        echo ""
        continue
    fi

    # Teste 1: Conectividade TCP na porta 22
    echo "  [1/3] Testando porta 22 (TCP)..."
    if test_tcp_port "${INST_PUBLIC_IP}" 22 "${SSH_TIMEOUT}"; then
        check_pass "Porta 22 acessível em ${INST_PUBLIC_IP}"
    else
        check_fail "Porta 22 NÃO acessível em ${INST_PUBLIC_IP}"
        echo "    → Verifique o security group (porta 22 deve estar aberta para 0.0.0.0/0)"
        echo "    → Verifique se a instância está running"
        echo "    → Verifique se há um Internet Gateway na VPC"
        echo ""
        continue
    fi

    # Teste 2: Autenticação SSH
    echo "  [2/3] Testando autenticação SSH..."
    SSH_RESULT=$(test_ssh_connection "${INST_PUBLIC_IP}" "${SSH_KEY_PATH}" 2>&1 || echo "FAILED")

    if [ "${SSH_RESULT}" = "SSH_OK" ]; then
        check_pass "Autenticação SSH bem-sucedida com chave ${KEY_NAME}"
    else
        check_fail "Autenticação SSH falhou"
        echo "    → Verifique se a chave '${KEY_NAME}' é a mesma usada na criação da instância"
        echo "    → Verifique se o usuário '${SSH_USER}' é correto para a AMI"
        echo "    → Erro: ${SSH_RESULT}"
        echo ""
        continue
    fi

    # Teste 3: Informações do sistema remoto
    echo "  [3/3] Obtendo informações do sistema remoto..."
    REMOTE_INFO=$(get_remote_info "${INST_PUBLIC_IP}" "${SSH_KEY_PATH}" 2>&1 || echo "")

    if [ -n "${REMOTE_INFO}" ]; then
        REMOTE_HOSTNAME=$(echo "${REMOTE_INFO}" | sed -n '1p')
        REMOTE_KERNEL=$(echo "${REMOTE_INFO}" | sed -n '2p')
        REMOTE_OS=$(echo "${REMOTE_INFO}" | sed -n '3p')

        check_pass "Sistema remoto acessível e respondendo"
        echo "      Hostname: ${REMOTE_HOSTNAME}"
        echo "      Kernel:   ${REMOTE_KERNEL}"
        echo "      OS:       ${REMOTE_OS}"
    else
        check_fail "Não foi possível obter informações do sistema remoto"
    fi

    echo ""
done

# -----------------------------------------------------------------------------
# Teste de conectividade inter-nós (se ambos acessíveis)
# -----------------------------------------------------------------------------
if [ "${INSTANCE_COUNT}" -ge 2 ] && [ "${PASSED_CHECKS}" -ge 2 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Testando Conectividade Inter-Nós"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Obtém IPs do control plane e worker
    CP_PUBLIC=$(echo "${INSTANCES_JSON}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for i in d:
    tags = i.get('Tags', [])
    if any(t.get('Value') == 'control-plane' for t in tags):
        print(i.get('PublicIpAddress', ''))
        break
" 2>/dev/null || echo "")

    WORKER_PRIVATE=$(echo "${INSTANCES_JSON}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for i in d:
    tags = i.get('Tags', [])
    if any(t.get('Value') == 'worker' for t in tags):
        print(i.get('PrivateIpAddress', ''))
        break
" 2>/dev/null || echo "")

    if [ -n "${CP_PUBLIC}" ] && [ "${CP_PUBLIC}" != "None" ] && [ -n "${WORKER_PRIVATE}" ]; then
        echo "  Testando ping do Control Plane → Worker Node (IP privado: ${WORKER_PRIVATE})..."

        PING_RESULT=$(ssh ${SSH_OPTIONS} -i "${SSH_KEY_PATH}" "${SSH_USER}@${CP_PUBLIC}" \
            "ping -c 2 -W 3 ${WORKER_PRIVATE} &>/dev/null && echo 'PING_OK' || echo 'PING_FAIL'" 2>/dev/null || echo "SSH_FAIL")

        if [ "${PING_RESULT}" = "PING_OK" ]; then
            check_pass "Control Plane → Worker Node: comunicação via rede privada OK"
        elif [ "${PING_RESULT}" = "PING_FAIL" ]; then
            check_fail "Control Plane → Worker Node: ping falhou na rede privada"
            echo "    → Verifique as regras de security group para tráfego inter-nós"
            echo "    → Verifique se ambas instâncias estão na mesma subnet/VPC"
        else
            check_fail "Não foi possível testar conectividade inter-nós (SSH falhou)"
        fi
    else
        echo "  ℹ Não foi possível identificar Control Plane e Worker para teste inter-nós"
    fi

    echo ""
fi

# =============================================================================
# RESUMO FINAL
# =============================================================================
echo "============================================="
echo " Resumo da Verificação de Conectividade"
echo "============================================="
echo ""
echo "  Total de verificações: ${TOTAL_CHECKS}"
echo "  Aprovadas:  ${PASSED_CHECKS}"
echo "  Reprovadas: ${FAILED_CHECKS}"
echo ""

if [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo "  ✓ RESULTADO: Conectividade SSH OK para todas as instâncias"
    echo ""
    echo "  Comandos de acesso rápido:"

    for i in $(seq 0 $((INSTANCE_COUNT - 1))); do
        INST_PUBLIC_IP=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[${i}].get('PublicIpAddress',''))")
        INST_NAME=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); tags=d[${i}].get('Tags',[]); print(next((t['Value'] for t in tags if t['Key']=='Name'),'sem-nome'))")

        if [ -n "${INST_PUBLIC_IP}" ] && [ "${INST_PUBLIC_IP}" != "None" ]; then
            echo "    ${INST_NAME}: ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${INST_PUBLIC_IP}"
        fi
    done

    echo ""
    exit 0
else
    echo "  ✗ RESULTADO: Problemas de conectividade detectados"
    echo ""
    echo "  Troubleshooting:"
    echo "    1. Verifique se as instâncias estão running:"
    echo "       aws ec2 describe-instances --filters \"Name=tag:Project,Values=${CLUSTER_NAME}\" \\"
    echo "         --query 'Reservations[].Instances[].[Tags[?Key==\`Name\`].Value|[0],State.Name]' --output table"
    echo ""
    echo "    2. Verifique security groups (porta 22):"
    echo "       aws ec2 describe-security-groups --filters \"Name=tag:Project,Values=${CLUSTER_NAME}\" \\"
    echo "         --query 'SecurityGroups[].[GroupName,IpPermissions[?FromPort==\`22\`]]' --output json"
    echo ""
    echo "    3. Verifique a chave SSH:"
    echo "       ls -la ${SSH_KEY_PATH}"
    echo "       ssh-keygen -l -f ${SSH_KEY_PATH}"
    echo ""
    exit 1
fi
