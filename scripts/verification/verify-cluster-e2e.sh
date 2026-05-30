#!/bin/bash
# =============================================================================
# Verificação End-to-End do Cluster Kubernetes
# =============================================================================
# Este script realiza uma validação completa do cluster implantando uma
# aplicação de teste e verificando o fluxo de tráfego de ponta a ponta:
#   - Deploy de aplicação nginx de teste
#   - Exposição como serviço NodePort
#   - Verificação de roteamento de tráfego (HTTP response)
#   - Verificação de resolução DNS do serviço dentro do cluster
#   - Limpeza de todos os recursos de teste ao final
#
# Pré-requisitos:
#   - Cluster Kubernetes funcional (control plane + worker node)
#   - kubectl configurado e conectado ao cluster
#   - CoreDNS operacional para resolução DNS
#   - CNI plugin instalado para networking entre pods
#
# Requirements: 12.3 (deploy de aplicação de teste exposta como NodePort)
#               12.4 (verificar pod running, service routing, DNS resolution)
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

# Configurações do teste
TEST_NAMESPACE="e2e-test"
TEST_APP_NAME="nginx-e2e-test"
TEST_SERVICE_NAME="nginx-e2e-svc"
TEST_IMAGE="nginx:1.25"
TEST_REPLICAS=1
TEST_NODEPORT=""  # Será atribuído automaticamente pelo Kubernetes
WAIT_TIMEOUT=120  # Segundos para aguardar pod ficar Ready
DNS_TEST_POD="dns-test-pod"

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

# Função de limpeza — remove todos os recursos de teste
cleanup() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Limpeza de Recursos de Teste"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "  Removendo namespace '${TEST_NAMESPACE}' e todos os recursos associados..."

    if kubectl get namespace "${TEST_NAMESPACE}" &>/dev/null; then
        kubectl delete namespace "${TEST_NAMESPACE}" --timeout=60s &>/dev/null && \
            echo "  ✓ Namespace '${TEST_NAMESPACE}' removido com sucesso" || \
            echo "  ⚠ Falha ao remover namespace '${TEST_NAMESPACE}' — remova manualmente"
    else
        echo "  ℹ Namespace '${TEST_NAMESPACE}' não encontrado (já removido ou não criado)"
    fi

    echo ""
}

# Registra trap para garantir limpeza mesmo em caso de erro
trap cleanup EXIT

# Verifica se kubectl está disponível e conectado ao cluster
verify_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        echo "ERRO: kubectl não encontrado no PATH."
        echo "  → Instale kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  → Ou siga o módulo 12-kubectl-kubeconfig"
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        echo "ERRO: kubectl não consegue se conectar ao cluster."
        echo "  → Verifique se o kubeconfig está configurado corretamente"
        echo "  → Execute: kubectl cluster-info"
        echo "  → Verifique se o kube-apiserver está running"
        exit 1
    fi
}

# Aguarda um pod atingir o estado Ready
wait_for_pod_ready() {
    local namespace="$1"
    local label_selector="$2"
    local timeout="$3"

    echo "  Aguardando pod ficar Ready (timeout: ${timeout}s)..."

    if kubectl wait --for=condition=Ready pod \
        -l "${label_selector}" \
        -n "${namespace}" \
        --timeout="${timeout}s" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Obtém o IP público de um worker node para teste de NodePort
get_worker_node_ip() {
    # Tenta obter o IP externo do worker node
    local node_ip=""

    # Primeiro tenta ExternalIP
    node_ip=$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.labels.node-role\.kubernetes\.io/worker)].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null | awk '{print $1}')

    # Se não encontrou por label, tenta qualquer nó que não seja control-plane
    if [ -z "${node_ip}" ]; then
        node_ip=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null | awk '{print $1}')
    fi

    # Se não tem ExternalIP, usa InternalIP
    if [ -z "${node_ip}" ]; then
        node_ip=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | awk '{print $1}')
    fi

    echo "${node_ip}"
}

# =============================================================================
# INÍCIO DA VERIFICAÇÃO END-TO-END
# =============================================================================

echo "============================================="
echo " Verificação End-to-End do Cluster"
echo " Cluster: ${CLUSTER_NAME}"
echo "============================================="
echo ""

# Verifica pré-requisitos
echo "Verificando pré-requisitos..."
verify_kubectl
echo "  ✓ kubectl configurado e conectado ao cluster"
echo ""

# -----------------------------------------------------------------------------
# Seção 1: Criar Namespace de Teste
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [1/5] Criando Namespace de Teste"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Remove namespace anterior se existir (limpeza de execução anterior)
if kubectl get namespace "${TEST_NAMESPACE}" &>/dev/null; then
    echo "  ℹ Namespace '${TEST_NAMESPACE}' já existe — removendo para teste limpo..."
    kubectl delete namespace "${TEST_NAMESPACE}" --timeout=60s &>/dev/null || true
    sleep 5
fi

# Cria namespace isolado para o teste
if kubectl create namespace "${TEST_NAMESPACE}" &>/dev/null; then
    check_pass "Namespace '${TEST_NAMESPACE}' criado com sucesso"
else
    check_fail "Falha ao criar namespace '${TEST_NAMESPACE}'"
    echo "    → Verifique permissões RBAC do usuário kubectl"
    echo ""
    exit 1
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 2: Deploy da Aplicação de Teste (nginx)
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [2/5] Deploy da Aplicação de Teste (nginx)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Cria o Deployment do nginx
echo "  Criando Deployment '${TEST_APP_NAME}' com ${TEST_REPLICAS} réplica(s)..."

kubectl apply -n "${TEST_NAMESPACE}" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TEST_APP_NAME}
  labels:
    app: ${TEST_APP_NAME}
    purpose: e2e-test
spec:
  replicas: ${TEST_REPLICAS}
  selector:
    matchLabels:
      app: ${TEST_APP_NAME}
  template:
    metadata:
      labels:
        app: ${TEST_APP_NAME}
    spec:
      containers:
      - name: nginx
        image: ${TEST_IMAGE}
        ports:
        - containerPort: 80
          name: http
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

if [ $? -eq 0 ]; then
    check_pass "Deployment '${TEST_APP_NAME}' criado"
else
    check_fail "Falha ao criar Deployment '${TEST_APP_NAME}'"
    echo "    → Verifique se o cluster tem capacidade para agendar o pod"
    echo ""
fi

# Aguarda o pod ficar Ready
if wait_for_pod_ready "${TEST_NAMESPACE}" "app=${TEST_APP_NAME}" "${WAIT_TIMEOUT}"; then
    check_pass "Pod está no estado Ready"

    # Exibe informações do pod
    POD_NAME=$(kubectl get pods -n "${TEST_NAMESPACE}" -l "app=${TEST_APP_NAME}" -o jsonpath='{.items[0].metadata.name}')
    POD_NODE=$(kubectl get pod "${POD_NAME}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.nodeName}')
    POD_IP=$(kubectl get pod "${POD_NAME}" -n "${TEST_NAMESPACE}" -o jsonpath='{.status.podIP}')

    echo "      Pod:  ${POD_NAME}"
    echo "      Node: ${POD_NODE}"
    echo "      IP:   ${POD_IP}"
else
    check_fail "Pod não atingiu estado Ready dentro de ${WAIT_TIMEOUT}s"
    echo "    → Verifique eventos do pod:"
    echo "      kubectl describe pod -l app=${TEST_APP_NAME} -n ${TEST_NAMESPACE}"
    echo "    → Verifique logs do pod:"
    echo "      kubectl logs -l app=${TEST_APP_NAME} -n ${TEST_NAMESPACE}"
    echo "    → Possíveis causas: imagem não encontrada, nó sem recursos, CNI não configurado"
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 3: Expor Serviço como NodePort
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [3/5] Expondo Serviço como NodePort"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Cria o Service do tipo NodePort
echo "  Criando Service '${TEST_SERVICE_NAME}' (tipo: NodePort)..."

kubectl apply -n "${TEST_NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${TEST_SERVICE_NAME}
  labels:
    app: ${TEST_APP_NAME}
    purpose: e2e-test
spec:
  type: NodePort
  selector:
    app: ${TEST_APP_NAME}
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
EOF

if [ $? -eq 0 ]; then
    check_pass "Service '${TEST_SERVICE_NAME}' criado (tipo: NodePort)"
else
    check_fail "Falha ao criar Service '${TEST_SERVICE_NAME}'"
fi

# Obtém a porta NodePort atribuída
TEST_NODEPORT=$(kubectl get service "${TEST_SERVICE_NAME}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
CLUSTER_IP=$(kubectl get service "${TEST_SERVICE_NAME}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -n "${TEST_NODEPORT}" ]; then
    check_pass "NodePort atribuído: ${TEST_NODEPORT}"
    echo "      ClusterIP: ${CLUSTER_IP}"
    echo "      NodePort:  ${TEST_NODEPORT}"
else
    check_fail "Não foi possível obter a porta NodePort"
    echo "    → Verifique: kubectl get svc ${TEST_SERVICE_NAME} -n ${TEST_NAMESPACE}"
fi

# Verifica se o Service tem endpoints
ENDPOINTS=$(kubectl get endpoints "${TEST_SERVICE_NAME}" -n "${TEST_NAMESPACE}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")

if [ -n "${ENDPOINTS}" ]; then
    check_pass "Service possui endpoints ativos: ${ENDPOINTS}"
else
    check_fail "Service sem endpoints — pod pode não estar Ready ou labels não correspondem"
    echo "    → Verifique: kubectl get endpoints ${TEST_SERVICE_NAME} -n ${TEST_NAMESPACE}"
    echo "    → Verifique labels do pod: kubectl get pods -n ${TEST_NAMESPACE} --show-labels"
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 4: Verificar Roteamento de Tráfego
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [4/5] Verificando Roteamento de Tráfego"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Teste 4a: Acesso via ClusterIP (de dentro do cluster)
echo "  [4a] Testando acesso via ClusterIP (interno ao cluster)..."

if [ -n "${CLUSTER_IP}" ]; then
    # Usa kubectl exec para testar de dentro do cluster
    CURL_RESULT=$(kubectl run curl-test --rm -i --restart=Never \
        --image=curlimages/curl:latest \
        -n "${TEST_NAMESPACE}" \
        --timeout=30s \
        -- curl -s -o /dev/null -w "%{http_code}" "http://${CLUSTER_IP}:80" 2>/dev/null || echo "000")

    if [ "${CURL_RESULT}" = "200" ]; then
        check_pass "ClusterIP acessível — HTTP 200 retornado"
    else
        check_fail "ClusterIP não acessível — HTTP code: ${CURL_RESULT}"
        echo "    → Verifique se kube-proxy está running nos nós"
        echo "    → Verifique regras iptables/IPVS: iptables -t nat -L KUBE-SERVICES"
    fi
else
    check_fail "ClusterIP não disponível — não foi possível testar acesso interno"
fi

# Teste 4b: Acesso via NodePort (externo ao cluster)
echo "  [4b] Testando acesso via NodePort (externo ao cluster)..."

NODE_IP=$(get_worker_node_ip)

if [ -n "${NODE_IP}" ] && [ -n "${TEST_NODEPORT}" ]; then
    echo "      Testando: http://${NODE_IP}:${TEST_NODEPORT}"

    # Tenta acessar o serviço via NodePort
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
        "http://${NODE_IP}:${TEST_NODEPORT}" 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ]; then
        check_pass "NodePort acessível externamente — HTTP 200 retornado"
    elif [ "${HTTP_CODE}" = "000" ]; then
        check_fail "NodePort não acessível — conexão recusada ou timeout"
        echo "    → Verifique se o security group permite tráfego na porta ${TEST_NODEPORT}"
        echo "    → Portas NodePort: 30000-32767 devem estar abertas no security group"
        echo "    → Verifique se o nó tem IP público acessível"
        echo "    → Teste local no nó: curl http://localhost:${TEST_NODEPORT}"
    else
        check_fail "NodePort retornou HTTP ${HTTP_CODE} (esperado: 200)"
        echo "    → Verifique logs do nginx: kubectl logs -l app=${TEST_APP_NAME} -n ${TEST_NAMESPACE}"
    fi
else
    if [ -z "${NODE_IP}" ]; then
        check_fail "Não foi possível obter IP do nó para teste NodePort"
        echo "    → Verifique: kubectl get nodes -o wide"
    fi
    if [ -z "${TEST_NODEPORT}" ]; then
        check_fail "NodePort não atribuído — não é possível testar acesso externo"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 5: Verificar Resolução DNS
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [5/5] Verificando Resolução DNS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Teste 5a: Resolução DNS do serviço pelo nome curto
echo "  [5a] Testando resolução DNS: ${TEST_SERVICE_NAME} (nome curto)..."

DNS_RESULT_SHORT=$(kubectl run "${DNS_TEST_POD}" --rm -i --restart=Never \
    --image=busybox:1.36 \
    -n "${TEST_NAMESPACE}" \
    --timeout=30s \
    -- nslookup "${TEST_SERVICE_NAME}" 2>/dev/null || echo "FAILED")

if echo "${DNS_RESULT_SHORT}" | grep -q "${CLUSTER_IP}"; then
    check_pass "DNS resolve '${TEST_SERVICE_NAME}' → ${CLUSTER_IP}"
else
    # Tenta extrair o IP resolvido
    RESOLVED_IP=$(echo "${DNS_RESULT_SHORT}" | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -1)
    if [ -n "${RESOLVED_IP}" ]; then
        check_pass "DNS resolve '${TEST_SERVICE_NAME}' → ${RESOLVED_IP}"
    else
        check_fail "DNS não resolve '${TEST_SERVICE_NAME}'"
        echo "    → Verifique se CoreDNS está running: kubectl get pods -n kube-system -l k8s-app=kube-dns"
        echo "    → Verifique logs do CoreDNS: kubectl logs -n kube-system -l k8s-app=kube-dns"
    fi
fi

# Teste 5b: Resolução DNS pelo FQDN completo
echo "  [5b] Testando resolução DNS: ${TEST_SERVICE_NAME}.${TEST_NAMESPACE}.svc.cluster.local (FQDN)..."

FQDN="${TEST_SERVICE_NAME}.${TEST_NAMESPACE}.svc.cluster.local"

DNS_RESULT_FQDN=$(kubectl run "${DNS_TEST_POD}-fqdn" --rm -i --restart=Never \
    --image=busybox:1.36 \
    -n "${TEST_NAMESPACE}" \
    --timeout=30s \
    -- nslookup "${FQDN}" 2>/dev/null || echo "FAILED")

if echo "${DNS_RESULT_FQDN}" | grep -q "${CLUSTER_IP}"; then
    check_pass "DNS resolve FQDN '${FQDN}' → ${CLUSTER_IP}"
else
    RESOLVED_FQDN_IP=$(echo "${DNS_RESULT_FQDN}" | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -1)
    if [ -n "${RESOLVED_FQDN_IP}" ]; then
        check_pass "DNS resolve FQDN '${FQDN}' → ${RESOLVED_FQDN_IP}"
    else
        check_fail "DNS não resolve FQDN '${FQDN}'"
        echo "    → Verifique configuração do CoreDNS Corefile (plugin kubernetes)"
        echo "    → Verifique se o kubelet está configurado com --cluster-dns=${CLUSTER_DNS}"
    fi
fi

# Teste 5c: Resolução DNS de serviço em outro namespace (kube-dns)
echo "  [5c] Testando resolução DNS cross-namespace: kubernetes.default.svc.cluster.local..."

DNS_RESULT_CROSS=$(kubectl run "${DNS_TEST_POD}-cross" --rm -i --restart=Never \
    --image=busybox:1.36 \
    -n "${TEST_NAMESPACE}" \
    --timeout=30s \
    -- nslookup "kubernetes.default.svc.cluster.local" 2>/dev/null || echo "FAILED")

if echo "${DNS_RESULT_CROSS}" | grep -qi "address"; then
    check_pass "DNS cross-namespace resolve 'kubernetes.default.svc.cluster.local'"
else
    check_fail "DNS cross-namespace falhou para 'kubernetes.default.svc.cluster.local'"
    echo "    → Verifique se o CoreDNS está configurado para o domínio cluster.local"
    echo "    → Verifique: kubectl get svc kubernetes -n default"
fi

echo ""

# =============================================================================
# RESUMO FINAL
# =============================================================================
echo "============================================="
echo " Resumo da Verificação End-to-End"
echo "============================================="
echo ""
echo "  Total de verificações: ${TOTAL_CHECKS}"
echo "  Aprovadas:  ${PASSED_CHECKS}"
echo "  Reprovadas: ${FAILED_CHECKS}"
echo ""

if [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo "  ✓ RESULTADO: Cluster funcional — validação end-to-end OK"
    echo ""
    echo "  O cluster está operacional com:"
    echo "    • Deploy de aplicação funcionando"
    echo "    • Service NodePort roteando tráfego"
    echo "    • Resolução DNS interna operacional"
    echo ""
    exit 0
else
    echo "  ✗ RESULTADO: Validação end-to-end com falhas"
    echo ""
    echo "  Troubleshooting:"
    echo "    1. Verifique componentes do control plane:"
    echo "       kubectl get componentstatuses"
    echo ""
    echo "    2. Verifique estado dos nós:"
    echo "       kubectl get nodes -o wide"
    echo ""
    echo "    3. Verifique pods do sistema:"
    echo "       kubectl get pods -n kube-system"
    echo ""
    echo "    4. Verifique eventos recentes:"
    echo "       kubectl get events -n ${TEST_NAMESPACE} --sort-by='.lastTimestamp'"
    echo ""
    echo "    5. Execute verificações individuais:"
    echo "       scripts/verification/verify-control-plane.sh"
    echo "       scripts/verification/verify-worker-nodes.sh"
    echo "       scripts/verification/verify-networking.sh"
    echo ""
    exit 1
fi
