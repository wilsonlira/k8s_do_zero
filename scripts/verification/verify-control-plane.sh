#!/bin/bash
# =============================================================================
# Verificação dos Componentes do Control Plane
# =============================================================================
# Este script verifica a saúde dos componentes do control plane do Kubernetes:
#   - etcd: health endpoint e member list
#   - kube-apiserver: /healthz e /livez endpoints
#   - kube-controller-manager: /healthz endpoint
#   - kube-scheduler: /healthz endpoint
#
# Executa verificações via SSH no nó do control plane para confirmar que
# todos os componentes estão operacionais e respondendo corretamente.
#
# Pré-requisitos:
#   - Instância do control plane no estado "running"
#   - Conectividade SSH configurada (verify-connectivity.sh)
#   - Componentes do control plane instalados e configurados
#
# Requirements: 12.1 (verificar cada componente do control plane reportando
#               status running sem condições de erro no health endpoint)
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
WARNINGS=0

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

# Registra um aviso (não é falha, mas requer atenção)
check_warn() {
    local msg="$1"
    echo "  ⚠ ${msg}"
    ((WARNINGS++))
}

# Executa comando remoto via SSH no control plane
ssh_exec() {
    local cmd="$1"
    ssh ${SSH_OPTIONS} -i "${SSH_KEY_PATH}" "${SSH_USER}@${CP_PUBLIC_IP}" "${cmd}" 2>/dev/null
}

# Obtém o IP público do control plane via AWS CLI
get_control_plane_ip() {
    local ip

    # Se CONTROL_PLANE_IP está definido no variables.env, usa ele
    if [ -n "${CONTROL_PLANE_IP:-}" ]; then
        echo "${CONTROL_PLANE_IP}"
        return
    fi

    # Caso contrário, busca via AWS CLI
    ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=${CLUSTER_NAME}" \
                  "Name=tag:Role,Values=control-plane" \
                  "Name=instance-state-name,Values=running" \
        --region "${AWS_REGION}" \
        --query 'Reservations[].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null || echo "")

    if [ -z "${ip}" ] || [ "${ip}" = "None" ]; then
        echo ""
    else
        echo "${ip}"
    fi
}

# =============================================================================
# INÍCIO DA VERIFICAÇÃO
# =============================================================================

echo "============================================="
echo " Verificação do Control Plane"
echo " Cluster: ${CLUSTER_NAME}"
echo " Região: ${AWS_REGION}"
echo "============================================="
echo ""

# -----------------------------------------------------------------------------
# Obter IP do Control Plane
# -----------------------------------------------------------------------------
echo "Obtendo endereço do control plane..."

CP_PUBLIC_IP=$(get_control_plane_ip)

if [ -z "${CP_PUBLIC_IP}" ]; then
    echo "  ERRO: Não foi possível obter o IP do control plane."
    echo "    → Verifique se a instância está running"
    echo "    → Execute: scripts/verification/verify-infrastructure.sh"
    echo "    → Ou defina CONTROL_PLANE_IP em variables.env"
    exit 1
fi

echo "  ✓ Control Plane IP: ${CP_PUBLIC_IP}"
echo ""

# Verifica conectividade SSH antes de prosseguir
echo "Verificando conectividade SSH..."
SSH_TEST=$(ssh_exec "echo 'OK'" 2>&1 || echo "FAILED")
if [ "${SSH_TEST}" != "OK" ]; then
    echo "  ERRO: Não foi possível conectar via SSH ao control plane (${CP_PUBLIC_IP})"
    echo "    → Execute: scripts/verification/verify-connectivity.sh"
    echo "    → Verifique a chave SSH: ${SSH_KEY_PATH}"
    exit 1
fi
echo "  ✓ Conexão SSH estabelecida"
echo ""

# -----------------------------------------------------------------------------
# Seção 1: Verificar etcd
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [1/4] Verificando etcd"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verifica se o serviço etcd está ativo
ETCD_ACTIVE=$(ssh_exec "systemctl is-active etcd 2>/dev/null || echo 'inactive'")
if [ "${ETCD_ACTIVE}" = "active" ]; then
    check_pass "Serviço etcd: active (running)"
else
    check_fail "Serviço etcd: ${ETCD_ACTIVE}"
    echo "    → Verifique logs: journalctl -u etcd --no-pager -n 20"
    echo "    → Reinicie: sudo systemctl restart etcd"
fi

# Verifica health endpoint do etcd
ETCD_HEALTH=$(ssh_exec "sudo ETCDCTL_API=3 etcdctl endpoint health \
    --endpoints=https://127.0.0.1:${ETCD_CLIENT_PORT} \
    --cacert=${CERT_DIR}/ca.pem \
    --cert=${CERT_DIR}/etcd.pem \
    --key=${CERT_DIR}/etcd-key.pem 2>&1 || echo 'HEALTH_FAIL'")

if echo "${ETCD_HEALTH}" | grep -q "is healthy"; then
    check_pass "etcd health endpoint: healthy"
else
    check_fail "etcd health endpoint: não saudável"
    echo "    → Resposta: ${ETCD_HEALTH}"
    echo "    → Verifique certificados TLS do etcd"
    echo "    → Verifique se o data directory tem permissões corretas"
fi

# Verifica member list do etcd
ETCD_MEMBERS=$(ssh_exec "sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:${ETCD_CLIENT_PORT} \
    --cacert=${CERT_DIR}/ca.pem \
    --cert=${CERT_DIR}/etcd.pem \
    --key=${CERT_DIR}/etcd-key.pem 2>&1 || echo 'MEMBERS_FAIL'")

if echo "${ETCD_MEMBERS}" | grep -q "started"; then
    MEMBER_COUNT=$(echo "${ETCD_MEMBERS}" | grep -c "started" || echo "0")
    check_pass "etcd member list: ${MEMBER_COUNT} membro(s) ativo(s)"
else
    check_fail "etcd member list: não foi possível listar membros"
    echo "    → Resposta: ${ETCD_MEMBERS}"
fi

# Verifica se etcd responde a operações de leitura/escrita
ETCD_RW=$(ssh_exec "sudo ETCDCTL_API=3 etcdctl put /health-check/test 'ok' \
    --endpoints=https://127.0.0.1:${ETCD_CLIENT_PORT} \
    --cacert=${CERT_DIR}/ca.pem \
    --cert=${CERT_DIR}/etcd.pem \
    --key=${CERT_DIR}/etcd-key.pem 2>&1 && \
    sudo ETCDCTL_API=3 etcdctl get /health-check/test \
    --endpoints=https://127.0.0.1:${ETCD_CLIENT_PORT} \
    --cacert=${CERT_DIR}/ca.pem \
    --cert=${CERT_DIR}/etcd.pem \
    --key=${CERT_DIR}/etcd-key.pem 2>&1 || echo 'RW_FAIL'")

if echo "${ETCD_RW}" | grep -q "ok"; then
    check_pass "etcd leitura/escrita: operacional"
    # Limpa a chave de teste
    ssh_exec "sudo ETCDCTL_API=3 etcdctl del /health-check/test \
        --endpoints=https://127.0.0.1:${ETCD_CLIENT_PORT} \
        --cacert=${CERT_DIR}/ca.pem \
        --cert=${CERT_DIR}/etcd.pem \
        --key=${CERT_DIR}/etcd-key.pem" &>/dev/null || true
else
    check_fail "etcd leitura/escrita: falhou"
    echo "    → Verifique permissões e espaço em disco no data directory"
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 2: Verificar kube-apiserver
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [2/4] Verificando kube-apiserver"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verifica se o serviço kube-apiserver está ativo
API_ACTIVE=$(ssh_exec "systemctl is-active kube-apiserver 2>/dev/null || echo 'inactive'")
if [ "${API_ACTIVE}" = "active" ]; then
    check_pass "Serviço kube-apiserver: active (running)"
else
    check_fail "Serviço kube-apiserver: ${API_ACTIVE}"
    echo "    → Verifique logs: journalctl -u kube-apiserver --no-pager -n 20"
    echo "    → Verifique se etcd está acessível"
    echo "    → Verifique certificados TLS"
fi

# Verifica /healthz endpoint
API_HEALTHZ=$(ssh_exec "curl -sk https://127.0.0.1:${KUBERNETES_API_PORT}/healthz 2>/dev/null || echo 'FAIL'")
if [ "${API_HEALTHZ}" = "ok" ]; then
    check_pass "kube-apiserver /healthz: ok"
else
    check_fail "kube-apiserver /healthz: ${API_HEALTHZ}"
    echo "    → Endpoint: https://127.0.0.1:${KUBERNETES_API_PORT}/healthz"
    echo "    → Verifique se o apiserver está escutando na porta ${KUBERNETES_API_PORT}"
fi

# Verifica /livez endpoint
API_LIVEZ=$(ssh_exec "curl -sk https://127.0.0.1:${KUBERNETES_API_PORT}/livez 2>/dev/null || echo 'FAIL'")
if [ "${API_LIVEZ}" = "ok" ]; then
    check_pass "kube-apiserver /livez: ok"
else
    check_fail "kube-apiserver /livez: ${API_LIVEZ}"
    echo "    → O apiserver pode estar em processo de inicialização"
    echo "    → Aguarde alguns segundos e tente novamente"
fi

# Verifica /readyz endpoint
API_READYZ=$(ssh_exec "curl -sk https://127.0.0.1:${KUBERNETES_API_PORT}/readyz 2>/dev/null || echo 'FAIL'")
if [ "${API_READYZ}" = "ok" ]; then
    check_pass "kube-apiserver /readyz: ok"
else
    check_warn "kube-apiserver /readyz: ${API_READYZ}"
    echo "    → O apiserver pode não estar totalmente pronto"
    echo "    → Verifique: curl -sk https://127.0.0.1:${KUBERNETES_API_PORT}/readyz?verbose"
fi

# Verifica se o apiserver responde a requisições de API
API_VERSION=$(ssh_exec "curl -sk https://127.0.0.1:${KUBERNETES_API_PORT}/version 2>/dev/null | grep -o '\"gitVersion\":\"[^\"]*\"' || echo 'FAIL'")
if echo "${API_VERSION}" | grep -q "gitVersion"; then
    VERSION_STR=$(echo "${API_VERSION}" | sed 's/"gitVersion":"//;s/"//')
    check_pass "kube-apiserver versão: ${VERSION_STR}"
else
    check_fail "kube-apiserver: não respondeu à requisição /version"
    echo "    → O apiserver pode não estar aceitando conexões"
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 3: Verificar kube-controller-manager
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [3/4] Verificando kube-controller-manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verifica se o serviço kube-controller-manager está ativo
CM_ACTIVE=$(ssh_exec "systemctl is-active kube-controller-manager 2>/dev/null || echo 'inactive'")
if [ "${CM_ACTIVE}" = "active" ]; then
    check_pass "Serviço kube-controller-manager: active (running)"
else
    check_fail "Serviço kube-controller-manager: ${CM_ACTIVE}"
    echo "    → Verifique logs: journalctl -u kube-controller-manager --no-pager -n 20"
    echo "    → Verifique conectividade com o kube-apiserver"
    echo "    → Verifique o kubeconfig do controller-manager"
fi

# Verifica /healthz endpoint do controller-manager (porta 10257)
CM_HEALTHZ=$(ssh_exec "curl -sk https://127.0.0.1:10257/healthz 2>/dev/null || echo 'FAIL'")
if [ "${CM_HEALTHZ}" = "ok" ]; then
    check_pass "kube-controller-manager /healthz: ok"
else
    check_fail "kube-controller-manager /healthz: ${CM_HEALTHZ}"
    echo "    → Endpoint: https://127.0.0.1:10257/healthz"
    echo "    → Verifique se o controller-manager está escutando na porta 10257"
fi

# Verifica se o controller-manager está registrado como lease holder
CM_LEASE=$(ssh_exec "kubectl --kubeconfig=/etc/kubernetes/admin.kubeconfig \
    get lease kube-controller-manager -n kube-system -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || echo 'FAIL'")
if [ -n "${CM_LEASE}" ] && [ "${CM_LEASE}" != "FAIL" ]; then
    check_pass "kube-controller-manager lease holder: ${CM_LEASE}"
else
    check_warn "kube-controller-manager lease: não foi possível verificar"
    echo "    → Pode ser normal se kubectl não está configurado no control plane"
    echo "    → Verifique manualmente: kubectl get lease -n kube-system"
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 4: Verificar kube-scheduler
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [4/4] Verificando kube-scheduler"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verifica se o serviço kube-scheduler está ativo
SCHED_ACTIVE=$(ssh_exec "systemctl is-active kube-scheduler 2>/dev/null || echo 'inactive'")
if [ "${SCHED_ACTIVE}" = "active" ]; then
    check_pass "Serviço kube-scheduler: active (running)"
else
    check_fail "Serviço kube-scheduler: ${SCHED_ACTIVE}"
    echo "    → Verifique logs: journalctl -u kube-scheduler --no-pager -n 20"
    echo "    → Verifique conectividade com o kube-apiserver"
    echo "    → Verifique o kubeconfig do scheduler"
fi

# Verifica /healthz endpoint do scheduler (porta 10259)
SCHED_HEALTHZ=$(ssh_exec "curl -sk https://127.0.0.1:10259/healthz 2>/dev/null || echo 'FAIL'")
if [ "${SCHED_HEALTHZ}" = "ok" ]; then
    check_pass "kube-scheduler /healthz: ok"
else
    check_fail "kube-scheduler /healthz: ${SCHED_HEALTHZ}"
    echo "    → Endpoint: https://127.0.0.1:10259/healthz"
    echo "    → Verifique se o scheduler está escutando na porta 10259"
fi

# Verifica se o scheduler está registrado como lease holder
SCHED_LEASE=$(ssh_exec "kubectl --kubeconfig=/etc/kubernetes/admin.kubeconfig \
    get lease kube-scheduler -n kube-system -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || echo 'FAIL'")
if [ -n "${SCHED_LEASE}" ] && [ "${SCHED_LEASE}" != "FAIL" ]; then
    check_pass "kube-scheduler lease holder: ${SCHED_LEASE}"
else
    check_warn "kube-scheduler lease: não foi possível verificar"
    echo "    → Pode ser normal se kubectl não está configurado no control plane"
    echo "    → Verifique manualmente: kubectl get lease -n kube-system"
fi

echo ""

# =============================================================================
# RESUMO FINAL
# =============================================================================
echo "============================================="
echo " Resumo da Verificação do Control Plane"
echo "============================================="
echo ""
echo "  Total de verificações: ${TOTAL_CHECKS}"
echo "  Aprovadas:  ${PASSED_CHECKS}"
echo "  Reprovadas: ${FAILED_CHECKS}"
echo "  Avisos:     ${WARNINGS}"
echo ""

if [ "${FAILED_CHECKS}" -eq 0 ] && [ "${WARNINGS}" -eq 0 ]; then
    echo "  ✓ RESULTADO: Control Plane saudável — todos os componentes operacionais"
    echo ""
    exit 0
elif [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo "  ⚠ RESULTADO: Control Plane funcional, mas com avisos"
    echo "    Revise os avisos acima para garantir estabilidade."
    echo ""
    exit 0
else
    echo "  ✗ RESULTADO: Control Plane com problemas"
    echo "    Corrija os itens reprovados antes de prosseguir."
    echo ""
    echo "  Troubleshooting geral:"
    echo "    1. Verifique logs dos serviços:"
    echo "       ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${CP_PUBLIC_IP}"
    echo "       sudo journalctl -u etcd --no-pager -n 30"
    echo "       sudo journalctl -u kube-apiserver --no-pager -n 30"
    echo "       sudo journalctl -u kube-controller-manager --no-pager -n 30"
    echo "       sudo journalctl -u kube-scheduler --no-pager -n 30"
    echo ""
    echo "    2. Verifique certificados TLS:"
    echo "       openssl x509 -in ${CERT_DIR}/apiserver.pem -noout -dates"
    echo ""
    echo "    3. Reinicie os serviços na ordem correta:"
    echo "       sudo systemctl restart etcd"
    echo "       sudo systemctl restart kube-apiserver"
    echo "       sudo systemctl restart kube-controller-manager"
    echo "       sudo systemctl restart kube-scheduler"
    echo ""
    exit 1
fi
