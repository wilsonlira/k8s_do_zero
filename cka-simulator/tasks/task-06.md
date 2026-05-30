# Tarefa 06 — Criação e Gerenciamento de DaemonSet

**Domínio:** Workloads & Scheduling
**Peso:** 5%
**Tempo recomendado:** 7 minutos

---

## Cenário

A equipe de operações precisa implantar um agente de monitoramento em **todos os nós** do cluster para coletar métricas de sistema. O agente deve ser executado como um DaemonSet para garantir que exatamente uma instância rode em cada nó, incluindo novos nós que forem adicionados ao cluster no futuro.

Além disso, o agente precisa de acesso a diretórios do host para coletar logs do sistema.

---

## Requisitos

1. Crie o namespace `monitoring` (caso não exista).

2. Crie um DaemonSet chamado `node-monitor` no namespace `monitoring` com as seguintes especificações:
   - Imagem: `busybox:1.36`
   - Labels no pod: `app=node-monitor, type=daemon`
   - Comando: `sh -c "while true; do echo $(date) - Node monitoring active; sleep 30; done"`
   - Monte o diretório `/var/log` do host no container no caminho `/host-logs` (somente leitura)

3. Configure o DaemonSet com **resource limits**:
   - Requests: CPU `50m`, Memória `64Mi`
   - Limits: CPU `100m`, Memória `128Mi`

4. Verifique que o DaemonSet está rodando em **todos os nós** do cluster (incluindo o control plane, se aplicável, ou apenas nos worker nodes conforme a configuração de taints do cluster).

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace monitoring existe
kubectl get namespace monitoring
# Esperado: STATUS = Active

# 2. Verificar que o DaemonSet existe e está pronto
kubectl get daemonset node-monitor -n monitoring
# Esperado: DESIRED = CURRENT = READY (número igual ao de nós elegíveis)

# 3. Verificar que o número de pods é igual ao número de nós elegíveis
NODES=$(kubectl get nodes --no-headers | wc -l)
PODS=$(kubectl get pods -n monitoring -l app=node-monitor --no-headers | grep -c "Running")
echo "Nós: $NODES, Pods DaemonSet: $PODS"
# Esperado: Pods >= 1 (pelo menos 1 por nó elegível)

# 4. Verificar os resource limits configurados
kubectl get daemonset node-monitor -n monitoring -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}'
# Esperado: 100m

kubectl get daemonset node-monitor -n monitoring -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'
# Esperado: 128Mi

# 5. Verificar que o volume hostPath está montado
kubectl get daemonset node-monitor -n monitoring -o jsonpath='{.spec.template.spec.volumes[*].hostPath.path}'
# Esperado: /var/log

# 6. Verificar as labels dos pods
kubectl get pods -n monitoring -l app=node-monitor,type=daemon --no-headers | wc -l
# Esperado: número >= 1 (pelo menos 1 pod com ambas as labels)
```


---

## Critérios de Aprovação

- ✅ Namespace `monitoring` criado
- ✅ DaemonSet `node-monitor` criado com imagem `busybox:1.36`
- ✅ Labels `app=node-monitor` e `type=daemon` configuradas nos pods
- ✅ Volume hostPath `/var/log` montado em `/host-logs` (somente leitura)
- ✅ Resource requests (CPU 50m, Memória 64Mi) e limits (CPU 100m, Memória 128Mi) configurados
- ✅ Pods do DaemonSet rodando em todos os nós elegíveis
