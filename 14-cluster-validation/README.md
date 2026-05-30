# Módulo 14 — Validação do Cluster

## Objetivo

Validar que o cluster Kubernetes está totalmente funcional, confirmando que todos os componentes trabalham em conjunto corretamente. Ao final deste módulo, você terá:

- Verificado a saúde de cada componente do Control Plane (etcd, kube-apiserver, kube-scheduler, kube-controller-manager)
- Confirmado que todos os Worker Nodes estão em estado Ready com kubelet e kube-proxy funcionando
- Implantado uma aplicação de teste (nginx) exposta como NodePort
- Validado que o pod é agendado, o serviço roteia tráfego, e o DNS resolve nomes de serviço
- Um checklist completo de saúde do cluster com saídas esperadas para cada indicador

## Teoria

### Por que validar o cluster?

Após instalar e configurar cada componente individualmente nos módulos anteriores, é essencial realizar uma validação end-to-end para confirmar que todos os componentes se comunicam corretamente e o cluster está operacional.

A validação do cluster cobre três camadas:

```
┌─────────────────────────────────────────────────────────────┐
│                  Camada 3: Aplicação                          │
│  Pod scheduling, Service routing, DNS resolution             │
├─────────────────────────────────────────────────────────────┤
│                  Camada 2: Worker Nodes                       │
│  Node Ready, kubelet running, kube-proxy running             │
├─────────────────────────────────────────────────────────────┤
│                  Camada 1: Control Plane                      │
│  etcd healthy, apiserver healthy, scheduler, controller-mgr  │
└─────────────────────────────────────────────────────────────┘
```

**Camada 1 — Control Plane**: Os componentes do control plane são responsáveis por gerenciar o estado desejado do cluster. Se qualquer um deles estiver indisponível, o cluster não pode processar novas requisições ou manter o estado desejado.

**Camada 2 — Worker Nodes**: Os worker nodes executam os workloads (pods). Um nó em estado NotReady não receberá novos pods e os pods existentes podem ser rescheduled para outros nós.

**Camada 3 — Aplicação**: A validação final confirma que o cluster pode executar workloads reais — agendar pods, rotear tráfego via Services, e resolver nomes via DNS.

### Componentes e seus Health Endpoints

| Componente | Health Endpoint | Porta |
|---|---|---|
| etcd | `/health` | 2379 |
| kube-apiserver | `/healthz`, `/livez`, `/readyz` | 6443 |
| kube-scheduler | `/healthz` | 10259 |
| kube-controller-manager | `/healthz` | 10257 |
| kubelet | `/healthz` | 10248 |

Cada componente expõe endpoints HTTP(S) que retornam o status de saúde. Um retorno HTTP 200 indica que o componente está saudável.

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 00 — Pré-requisitos](../00-prerequisites/)
- [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/)
- [Módulo 02 — Certificados TLS](../02-tls-certificates/)
- [Módulo 03 — Container Runtime](../03-container-runtime/)
- [Módulo 04 — etcd](../04-etcd/)
- [Módulo 05 — kube-apiserver](../05-kube-apiserver/)
- [Módulo 06 — kube-controller-manager](../06-kube-controller-manager/)
- [Módulo 07 — kube-scheduler](../07-kube-scheduler/)
- [Módulo 08 — kubelet](../08-kubelet/)
- [Módulo 09 — kube-proxy](../09-kube-proxy/)
- [Módulo 10 — CNI Networking](../10-cni-networking/)
- [Módulo 11 — CoreDNS](../11-coredns/)
- [Módulo 12 — kubectl & kubeconfig](../12-kubectl-kubeconfig/)
- [Módulo 13 — Ingress Controller](../13-ingress-controller/)

Todos os componentes do cluster devem estar instalados e configurados conforme os módulos anteriores.

## Comandos Passo a Passo

### 1. Verificar Componentes do Control Plane

A primeira etapa da validação é confirmar que todos os componentes do control plane estão saudáveis e respondendo corretamente.

#### 1.1 Verificar saúde do etcd

O etcd é o armazenamento de estado do cluster. Se o etcd não estiver saudável, nenhum outro componente funcionará corretamente. O comando abaixo usa `etcdctl` com as credenciais TLS para verificar o endpoint de saúde.

```bash
# Verificar saúde do endpoint etcd
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://${CONTROL_PLANE_IP}:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem
```

**Saída esperada:**
```
https://10.0.1.10:2379 is healthy: successfully committed proposal: took = 1.234ms
```

A linha-chave é `is healthy` — confirma que o etcd está aceitando leituras e escritas.

#### 1.2 Verificar membros do cluster etcd

Este comando lista todos os membros do cluster etcd. No nosso lab com um único nó control plane, deve haver exatamente 1 membro.

```bash
# Listar membros do cluster etcd
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://${CONTROL_PLANE_IP}:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem \
  --write-out=table
```

**Saída esperada:**
```
+------------------+---------+--------------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |        NAME        |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+--------------------+----------------------------+----------------------------+------------+
| 8e9e05c52164694d | started | k8s-control-plane  | https://10.0.1.10:2380     | https://10.0.1.10:2379     |      false |
+------------------+---------+--------------------+----------------------------+----------------------------+------------+
```

A linha-chave é `STATUS: started` — confirma que o membro está ativo e participando do cluster.

#### 1.3 Verificar saúde do kube-apiserver

O kube-apiserver é o ponto central de comunicação do cluster. Verificamos três endpoints: `/healthz` (saúde geral), `/livez` (liveness), e `/readyz` (readiness).

```bash
# Verificar endpoint /healthz do kube-apiserver
curl -sk https://${CONTROL_PLANE_IP}:6443/healthz
```

**Saída esperada:**
```
ok
```

```bash
# Verificar endpoint /livez (liveness) do kube-apiserver
curl -sk https://${CONTROL_PLANE_IP}:6443/livez
```

**Saída esperada:**
```
ok
```

```bash
# Verificar endpoint /readyz (readiness) do kube-apiserver
curl -sk https://${CONTROL_PLANE_IP}:6443/readyz
```

**Saída esperada:**
```
ok
```

A resposta `ok` em todos os três endpoints confirma que o kube-apiserver está saudável, vivo e pronto para receber requisições.

```bash
# Verificar detalhes do /readyz (mostra cada check individual)
curl -sk https://${CONTROL_PLANE_IP}:6443/readyz?verbose
```

**Saída esperada:**
```
[+]ping ok
[+]log ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
[+]poststarthook/start-kube-apiserver-admission-initializer ok
[+]poststarthook/generic-apiserver-start-informers ok
[+]poststarthook/start-apiextensions-informers ok
[+]poststarthook/start-apiextensions-controllers ok
[+]poststarthook/crd-informer-synced ok
[+]poststarthook/start-system-namespaces-controller ok
[+]poststarthook/start-cluster-authentication-info-controller ok
[+]shutdown ok
readyz check passed
```

A linha-chave é `readyz check passed` — confirma que todos os sub-checks internos passaram.

#### 1.4 Verificar saúde do kube-scheduler

O kube-scheduler é responsável por atribuir pods a nós. Verificamos seu endpoint de saúde via HTTPS.

```bash
# Verificar endpoint /healthz do kube-scheduler
curl -sk https://127.0.0.1:10259/healthz
```

**Saída esperada:**
```
ok
```

A resposta `ok` confirma que o kube-scheduler está saudável e pronto para agendar pods.

```bash
# Verificar via kubectl (requer kubeconfig configurado)
kubectl get componentstatuses | grep scheduler
```

**Saída esperada:**
```
scheduler            Healthy   ok
```

A linha-chave é `Healthy` — confirma que o API server consegue se comunicar com o scheduler.

#### 1.5 Verificar saúde do kube-controller-manager

O kube-controller-manager executa os loops de reconciliação que mantêm o estado desejado do cluster.

```bash
# Verificar endpoint /healthz do kube-controller-manager
curl -sk https://127.0.0.1:10257/healthz
```

**Saída esperada:**
```
ok
```

A resposta `ok` confirma que o kube-controller-manager está saudável.

```bash
# Verificar via kubectl
kubectl get componentstatuses | grep controller-manager
```

**Saída esperada:**
```
controller-manager   Healthy   ok
```

#### 1.6 Verificar todos os component statuses de uma vez

O comando abaixo fornece uma visão geral de todos os componentes do control plane em uma única consulta.

```bash
# Verificar status de todos os componentes do control plane
kubectl get componentstatuses
```

**Saída esperada:**
```
NAME                 STATUS    MESSAGE   ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   ok
```

Todos os componentes devem mostrar `STATUS: Healthy`. Se qualquer componente mostrar `Unhealthy`, consulte a seção de Troubleshooting.

---

### 2. Verificar Worker Nodes

Após confirmar que o control plane está saudável, verificamos que os worker nodes estão registrados e prontos para executar workloads.

#### 2.1 Verificar status dos nós

O comando abaixo lista todos os nós registrados no cluster e seu status. Todos os nós devem estar em estado `Ready`.

```bash
# Listar todos os nós do cluster com status
kubectl get nodes -o wide
```

**Saída esperada:**
```
NAME               STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k8s-control-plane  Ready    <none>   1d    v1.29.0   10.0.1.10     <PUBLIC_IP>   Ubuntu 22.04.3 LTS   5.15.0-xxx-generic  containerd://1.7.13
k8s-worker-01      Ready    <none>   1d    v1.29.0   10.0.1.20     <PUBLIC_IP>   Ubuntu 22.04.3 LTS   5.15.0-xxx-generic  containerd://1.7.13
```

As linhas-chave são:
- `STATUS: Ready` — o nó está saudável e pronto para receber pods
- `VERSION: v1.29.0` — confirma a versão do kubelet instalada
- `CONTAINER-RUNTIME: containerd://1.7.13` — confirma o runtime configurado

#### 2.2 Verificar kubelet em cada worker node

O kubelet é o agente primário em cada nó. Verificamos que o serviço está ativo e sem erros.

```bash
# No worker node: verificar status do serviço kubelet
sudo systemctl status kubelet
```

**Saída esperada:**
```
● kubelet.service - Kubernetes Kubelet
     Loaded: loaded (/etc/systemd/system/kubelet.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 1 day ago
   Main PID: 1234 (kubelet)
      Tasks: 15 (limit: 1024)
     Memory: 45.2M
        CPU: 5min 30s
     CGroup: /system.slice/kubelet.service
             └─1234 /usr/local/bin/kubelet ...
```

A linha-chave é `Active: active (running)` — confirma que o kubelet está executando sem erros.

```bash
# Verificar que o kubelet não tem erros recentes nos logs
sudo journalctl -u kubelet --no-pager -n 10
```

**Saída esperada:** As últimas 10 linhas de log não devem conter mensagens de erro (`E` no início da linha). Mensagens informativas (`I`) são normais.

#### 2.3 Verificar kube-proxy em cada worker node

O kube-proxy mantém as regras de rede para roteamento de serviços. Verificamos que está ativo em cada nó.

```bash
# No worker node: verificar status do serviço kube-proxy
sudo systemctl status kube-proxy
```

**Saída esperada:**
```
● kube-proxy.service - Kubernetes Kube Proxy
     Loaded: loaded (/etc/systemd/system/kube-proxy.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 1 day ago
   Main PID: 5678 (kube-proxy)
      Tasks: 5 (limit: 1024)
     Memory: 15.8M
        CPU: 1min 20s
     CGroup: /system.slice/kube-proxy.service
             └─5678 /usr/local/bin/kube-proxy ...
```

A linha-chave é `Active: active (running)` — confirma que o kube-proxy está executando.

```bash
# Verificar que regras iptables foram criadas pelo kube-proxy
sudo iptables -t nat -L KUBE-SERVICES | head -20
```

**Saída esperada:**
```
Chain KUBE-SERVICES (2 references)
target     prot opt source               destination
KUBE-SVC-xxx  tcp  --  anywhere             10.96.0.1            /* default/kubernetes:https cluster IP */ tcp dpt:https
KUBE-SVC-xxx  tcp  --  anywhere             10.96.0.10           /* kube-system/kube-dns:dns-tcp cluster IP */ tcp dpt:domain
```

A presença de regras `KUBE-SVC-*` confirma que o kube-proxy está traduzindo Services em regras de rede.

#### 2.4 Verificar condições detalhadas dos nós

O comando abaixo mostra as condições internas de cada nó, incluindo pressão de memória, disco e PIDs.

```bash
# Verificar condições detalhadas do worker node
kubectl describe node ${WORKER_NODE_NAME} | grep -A 5 "Conditions:"
```

**Saída esperada:**
```
Conditions:
  Type                 Status  LastHeartbeatTime                 Reason                       Message
  ----                 ------  -----------------                 ------                       -------
  MemoryPressure       False   Mon, 01 Jan 2024 12:00:00 +0000  KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure         False   Mon, 01 Jan 2024 12:00:00 +0000  KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure          False   Mon, 01 Jan 2024 12:00:00 +0000  KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready                True    Mon, 01 Jan 2024 12:00:00 +0000  KubeletReady                 kubelet is posting ready status
```

As linhas-chave são:
- `MemoryPressure: False` — nó tem memória suficiente
- `DiskPressure: False` — nó tem espaço em disco suficiente
- `PIDPressure: False` — nó tem PIDs suficientes
- `Ready: True` — nó está pronto para receber pods

---

### 3. Implantar Aplicação de Teste

Com o control plane e os worker nodes validados, implantamos uma aplicação de teste para confirmar que o cluster pode executar workloads end-to-end.

#### 3.1 Criar Deployment do nginx

O Deployment cria um pod nginx com 1 réplica. Isso testa a cadeia completa: API server aceita a requisição, scheduler atribui o pod a um nó, kubelet cria o container via containerd.

```bash
# Criar um Deployment com nginx (1 réplica)
kubectl create deployment nginx-test --image=nginx:1.25 --replicas=1
```

**Saída esperada:**
```
deployment.apps/nginx-test created
```

#### 3.2 Verificar que o pod foi agendado e está running

Aguardamos o pod transicionar de `Pending` para `Running`, confirmando que o scheduler e o kubelet estão funcionando.

```bash
# Verificar status do pod (aguardar até Running)
kubectl get pods -l app=nginx-test -o wide
```

**Saída esperada:**
```
NAME                          READY   STATUS    RESTARTS   AGE   IP            NODE            NOMINATED NODE   READINESS GATES
nginx-test-7c5b8d6c88-abc12  1/1     Running   0          30s   10.244.1.5    k8s-worker-01   <none>           <none>
```

As linhas-chave são:
- `STATUS: Running` — o pod está executando com sucesso
- `READY: 1/1` — todos os containers no pod estão prontos
- `NODE: k8s-worker-01` — o scheduler atribuiu o pod ao worker node
- `IP: 10.244.1.5` — o CNI atribuiu um IP do pod CIDR

```bash
# Verificar detalhes do agendamento (eventos do pod)
kubectl describe pod -l app=nginx-test | grep -A 10 "Events:"
```

**Saída esperada:**
```
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  45s   default-scheduler  Successfully assigned default/nginx-test-7c5b8d6c88-abc12 to k8s-worker-01
  Normal  Pulling    44s   kubelet            Pulling image "nginx:1.25"
  Normal  Pulled     30s   kubelet            Successfully pulled image "nginx:1.25" in 14s
  Normal  Created    30s   kubelet            Created container nginx
  Normal  Started    30s   kubelet            Started container nginx
```

Os eventos confirmam a sequência completa: Scheduled → Pulling → Pulled → Created → Started.

#### 3.3 Expor aplicação como NodePort Service

O Service do tipo NodePort expõe a aplicação em uma porta alta (30000-32767) em todos os nós do cluster, permitindo acesso externo.

```bash
# Criar Service do tipo NodePort para o deployment nginx-test
kubectl expose deployment nginx-test --type=NodePort --port=80
```

**Saída esperada:**
```
service/nginx-test exposed
```

```bash
# Verificar o Service criado e a porta atribuída
kubectl get service nginx-test
```

**Saída esperada:**
```
NAME         TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
nginx-test   NodePort   10.96.45.123   <none>        80:31234/TCP   10s
```

As linhas-chave são:
- `TYPE: NodePort` — confirma o tipo de serviço
- `CLUSTER-IP: 10.96.45.123` — IP interno atribuído do SERVICE_CIDR
- `PORT(S): 80:31234/TCP` — porta 80 do container mapeada para NodePort 31234

#### 3.4 Verificar que o Service roteia tráfego para o pod

Testamos o acesso ao nginx via NodePort para confirmar que o kube-proxy está roteando o tráfego corretamente.

```bash
# Obter a NodePort atribuída
NODE_PORT=$(kubectl get service nginx-test -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort: ${NODE_PORT}"
```

**Saída esperada:**
```
NodePort: 31234
```

```bash
# Testar acesso via NodePort no worker node (de dentro do cluster)
curl -s http://${WORKER_NODE_IP}:${NODE_PORT} | head -5
```

**Saída esperada:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
</head>
```

A página padrão do nginx confirma que:
1. O kube-proxy criou as regras de iptables para o NodePort
2. O tráfego é roteado do NodePort para o ClusterIP do Service
3. O Service encaminha o tráfego para o pod nginx

```bash
# Testar acesso via ClusterIP (de dentro de um pod no cluster)
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://nginx-test.default.svc.cluster.local
```

**Saída esperada:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
pod "curl-test" deleted
```

Este teste confirma que o Service é acessível via nome DNS dentro do cluster.

#### 3.5 Verificar resolução DNS do serviço

O CoreDNS deve resolver o nome do serviço para o ClusterIP correto. Isso confirma que a camada de service discovery está funcionando.

```bash
# Verificar resolução DNS do serviço nginx-test
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup nginx-test.default.svc.cluster.local
```

**Saída esperada:**
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      nginx-test.default.svc.cluster.local
Address 1: 10.96.45.123 nginx-test.default.svc.cluster.local
pod "dns-test" deleted
```

As linhas-chave são:
- `Server: 10.96.0.10` — o DNS query foi enviado ao CoreDNS (CLUSTER_DNS definido em `variables.env`)
- `Address 1: 10.96.45.123` — o nome do serviço resolveu para o ClusterIP correto

```bash
# Verificar resolução DNS reversa (IP para nome)
kubectl run dns-reverse-test --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup 10.96.45.123
```

**Saída esperada:**
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      10.96.45.123
Address 1: 10.96.45.123 nginx-test.default.svc.cluster.local
pod "dns-reverse-test" deleted
```

#### 3.6 Verificar endpoints do Service

Os endpoints confirmam que o Service está corretamente vinculado ao pod via label selector.

```bash
# Verificar endpoints do Service
kubectl get endpoints nginx-test
```

**Saída esperada:**
```
NAME         ENDPOINTS        AGE
nginx-test   10.244.1.5:80    2m
```

O endpoint `10.244.1.5:80` corresponde ao IP do pod nginx-test, confirmando que o Service está roteando para o pod correto.

---

### 4. Limpeza dos Recursos de Teste

Após a validação, removemos os recursos de teste para manter o cluster limpo.

```bash
# Remover o Service de teste
kubectl delete service nginx-test
```

**Saída esperada:**
```
service "nginx-test" deleted
```

```bash
# Remover o Deployment de teste
kubectl delete deployment nginx-test
```

**Saída esperada:**
```
deployment.apps "nginx-test" deleted
```

```bash
# Verificar que os recursos foram removidos
kubectl get pods -l app=nginx-test
kubectl get service nginx-test
```

**Saída esperada:**
```
No resources found in default namespace.
Error from server (NotFound): services "nginx-test" not found
```

## Verificação

### Checklist Completo de Saúde do Cluster

Use o checklist abaixo para validar todos os indicadores de saúde do cluster. Cada item inclui o comando e a saída esperada.

#### Control Plane

| # | Indicador | Comando | Saída Esperada |
|---|---|---|---|
| 1 | etcd healthy | `etcdctl endpoint health --endpoints=https://${CONTROL_PLANE_IP}:2379 --cacert=... --cert=... --key=...` | `is healthy: successfully committed proposal` |
| 2 | API server /healthz | `curl -sk https://${CONTROL_PLANE_IP}:6443/healthz` | `ok` |
| 3 | API server /readyz | `curl -sk https://${CONTROL_PLANE_IP}:6443/readyz` | `ok` |
| 4 | Scheduler healthy | `curl -sk https://127.0.0.1:10259/healthz` | `ok` |
| 5 | Controller-manager healthy | `curl -sk https://127.0.0.1:10257/healthz` | `ok` |
| 6 | Component statuses | `kubectl get componentstatuses` | Todos `Healthy` |

#### Worker Nodes

| # | Indicador | Comando | Saída Esperada |
|---|---|---|---|
| 7 | Nodes Ready | `kubectl get nodes` | Todos os nós com `STATUS: Ready` |
| 8 | kubelet running | `systemctl status kubelet` | `Active: active (running)` |
| 9 | kube-proxy running | `systemctl status kube-proxy` | `Active: active (running)` |
| 10 | Node conditions | `kubectl describe node <name> \| grep -A5 Conditions` | `Ready: True`, todas as pressões `False` |
| 11 | iptables rules | `iptables -t nat -L KUBE-SERVICES` | Regras `KUBE-SVC-*` presentes |

#### Networking e DNS

| # | Indicador | Comando | Saída Esperada |
|---|---|---|---|
| 12 | Pod networking | `kubectl get pods -A -o wide` | Todos os pods com IPs do POD_CIDR |
| 13 | CoreDNS running | `kubectl get pods -n kube-system -l k8s-app=kube-dns` | Pods em `Running` |
| 14 | DNS resolution | `nslookup kubernetes.default.svc.cluster.local` (de dentro de um pod) | Resolve para `10.96.0.1` |

#### Aplicação de Teste

| # | Indicador | Comando | Saída Esperada |
|---|---|---|---|
| 15 | Pod scheduled | `kubectl get pods -l app=nginx-test` | `STATUS: Running`, `READY: 1/1` |
| 16 | Service routing | `curl http://<NODE_IP>:<NODE_PORT>` | Página HTML do nginx |
| 17 | DNS resolves service | `nslookup nginx-test.default.svc.cluster.local` (de dentro de um pod) | Resolve para ClusterIP do service |
| 18 | Endpoints bound | `kubectl get endpoints nginx-test` | IP do pod listado |

### Script de Validação Completa

Execute o script abaixo para verificar todos os indicadores de saúde automaticamente:

```bash
#!/bin/bash
# =============================================================================
# Script de Validação Completa do Cluster Kubernetes
# =============================================================================
# Referência: variables.env para parâmetros centralizados
# =============================================================================

source ./variables.env

echo "============================================================"
echo "  VALIDAÇÃO COMPLETA DO CLUSTER KUBERNETES"
echo "============================================================"
echo ""

PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"
    if [ "$result" -eq 0 ]; then
        echo "  ✅ ${description}"
        ((PASS++))
    else
        echo "  ❌ ${description}"
        ((FAIL++))
    fi
}

echo "--- Control Plane ---"
echo ""
```

```bash
# 1. etcd health
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://${CONTROL_PLANE_IP}:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem &>/dev/null
check "etcd endpoint healthy" $?

# 2. kube-apiserver /healthz
curl -sk https://${CONTROL_PLANE_IP}:6443/healthz | grep -q "ok"
check "kube-apiserver /healthz" $?

# 3. kube-apiserver /readyz
curl -sk https://${CONTROL_PLANE_IP}:6443/readyz | grep -q "ok"
check "kube-apiserver /readyz" $?

# 4. kube-scheduler /healthz
curl -sk https://127.0.0.1:10259/healthz | grep -q "ok"
check "kube-scheduler /healthz" $?

# 5. kube-controller-manager /healthz
curl -sk https://127.0.0.1:10257/healthz | grep -q "ok"
check "kube-controller-manager /healthz" $?

echo ""
echo "--- Worker Nodes ---"
echo ""

# 6. All nodes Ready
NOT_READY=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
[ "$NOT_READY" -eq 0 ]
check "All nodes in Ready state" $?

# 7. kubelet running on worker
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${WORKER_NODE_IP} \
  "systemctl is-active kubelet" 2>/dev/null | grep -q "active"
check "kubelet running on worker node" $?

# 8. kube-proxy running on worker
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${WORKER_NODE_IP} \
  "systemctl is-active kube-proxy" 2>/dev/null | grep -q "active"
check "kube-proxy running on worker node" $?

echo ""
echo "--- Networking & DNS ---"
echo ""

# 9. CoreDNS pods running
COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep "Running" | wc -l)
[ "$COREDNS_READY" -gt 0 ]
check "CoreDNS pods running" $?

# 10. DNS resolution
kubectl run dns-check --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local 2>/dev/null | grep -q "Address"
check "DNS resolves kubernetes.default" $?

echo ""
echo "--- Application Test ---"
echo ""

# 11. Deploy test app
kubectl create deployment nginx-validation --image=nginx:1.25 --replicas=1 &>/dev/null
sleep 30

# 12. Pod running
kubectl get pods -l app=nginx-validation --no-headers | grep -q "Running"
check "Test pod running" $?

# 13. Expose as NodePort
kubectl expose deployment nginx-validation --type=NodePort --port=80 &>/dev/null
sleep 5

# 14. Service routes traffic
NODE_PORT=$(kubectl get service nginx-validation -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
curl -s --max-time 5 http://${WORKER_NODE_IP}:${NODE_PORT} | grep -q "nginx"
check "NodePort service routes traffic" $?

# 15. DNS resolves service name
kubectl run dns-svc-check --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup nginx-validation.default.svc.cluster.local 2>/dev/null | grep -q "Address"
check "DNS resolves service name" $?

# Cleanup
kubectl delete deployment nginx-validation &>/dev/null
kubectl delete service nginx-validation &>/dev/null

echo ""
echo "============================================================"
echo "  RESULTADO: ${PASS} passed, ${FAIL} failed"
echo "============================================================"

if [ "$FAIL" -eq 0 ]; then
    echo "  🎉 Cluster totalmente funcional!"
else
    echo "  ⚠️  Verifique os itens com ❌ na seção de Troubleshooting"
fi
```

**Saída esperada (cluster saudável):**
```
============================================================
  VALIDAÇÃO COMPLETA DO CLUSTER KUBERNETES
============================================================

--- Control Plane ---

  ✅ etcd endpoint healthy
  ✅ kube-apiserver /healthz
  ✅ kube-apiserver /readyz
  ✅ kube-scheduler /healthz
  ✅ kube-controller-manager /healthz

--- Worker Nodes ---

  ✅ All nodes in Ready state
  ✅ kubelet running on worker node
  ✅ kube-proxy running on worker node

--- Networking & DNS ---

  ✅ CoreDNS pods running
  ✅ DNS resolves kubernetes.default

--- Application Test ---

  ✅ Test pod running
  ✅ NodePort service routes traffic
  ✅ DNS resolves service name

============================================================
  RESULTADO: 13 passed, 0 failed
============================================================
  🎉 Cluster totalmente funcional!
```

## Troubleshooting

### Problema: etcd endpoint unhealthy

**Sintoma:**
```
https://10.0.1.10:2379 is unhealthy: failed to commit proposal: context deadline exceeded
```

**Causa provável:** O serviço etcd não está rodando, ou os certificados TLS estão incorretos/expirados.

**Resolução:**
```bash
# 1. Verificar se o serviço etcd está ativo
sudo systemctl status etcd

# 2. Se não estiver rodando, verificar logs para identificar o erro
sudo journalctl -u etcd --no-pager -n 50

# 3. Verificar validade dos certificados
openssl x509 -in /etc/etcd/etcd.pem -noout -dates

# 4. Reiniciar o serviço etcd
sudo systemctl restart etcd

# 5. Verificar novamente
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://${CONTROL_PLANE_IP}:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem
```

---

### Problema: kube-apiserver /healthz retorna erro

**Sintoma:**
```
curl: (7) Failed to connect to 10.0.1.10 port 6443: Connection refused
```

Ou:
```
{
  "status": "Failure",
  "message": "forbidden: User \"system:anonymous\" cannot get path \"/healthz\""
}
```

**Causa provável:** O kube-apiserver não está rodando, ou há um problema de conectividade/certificado.

**Resolução:**
```bash
# 1. Verificar se o serviço está ativo
sudo systemctl status kube-apiserver

# 2. Verificar logs do kube-apiserver
sudo journalctl -u kube-apiserver --no-pager -n 50

# 3. Verificar se a porta 6443 está em uso
sudo ss -tlnp | grep 6443

# 4. Verificar conectividade com etcd (dependência principal)
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://${CONTROL_PLANE_IP}:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem

# 5. Reiniciar o kube-apiserver
sudo systemctl restart kube-apiserver
```

---

### Problema: kube-scheduler ou kube-controller-manager unhealthy

**Sintoma:**
```
scheduler            Unhealthy   Get "https://127.0.0.1:10259/healthz": dial tcp 127.0.0.1:10259: connect: connection refused
controller-manager   Unhealthy   Get "https://127.0.0.1:10257/healthz": dial tcp 127.0.0.1:10257: connect: connection refused
```

**Causa provável:** O serviço não está rodando, ou não consegue se conectar ao kube-apiserver.

**Resolução:**
```bash
# 1. Verificar status dos serviços
sudo systemctl status kube-scheduler
sudo systemctl status kube-controller-manager

# 2. Verificar logs para identificar o erro
sudo journalctl -u kube-scheduler --no-pager -n 30
sudo journalctl -u kube-controller-manager --no-pager -n 30

# 3. Verificar que o kube-apiserver está acessível (pré-requisito)
curl -sk https://${CONTROL_PLANE_IP}:6443/healthz

# 4. Verificar kubeconfig dos componentes
cat /var/lib/kubernetes/kube-scheduler.kubeconfig | grep server
cat /var/lib/kubernetes/kube-controller-manager.kubeconfig | grep server

# 5. Reiniciar os serviços
sudo systemctl restart kube-scheduler
sudo systemctl restart kube-controller-manager

# 6. Verificar novamente
kubectl get componentstatuses
```

---

### Problema: Worker node em estado NotReady

**Sintoma:**
```
NAME            STATUS     ROLES    AGE   VERSION
k8s-worker-01  NotReady   <none>   1d    v1.29.0
```

**Causa provável:** O kubelet não está rodando, o CNI plugin não está configurado, ou há problemas de conectividade com o control plane.

**Resolução:**
```bash
# 1. No worker node: verificar status do kubelet
sudo systemctl status kubelet

# 2. Verificar logs do kubelet para identificar o erro
sudo journalctl -u kubelet --no-pager -n 50

# 3. Erros comuns nos logs:
#    - "Unable to update cni config": CNI plugin não instalado
#    - "failed to run Kubelet: unable to load bootstrap kubeconfig": kubeconfig inválido
#    - "certificate has expired": certificado expirado

# 4. Verificar se o CNI plugin está instalado
ls /etc/cni/net.d/
ls /opt/cni/bin/

# 5. Verificar conectividade com o API server
curl -sk https://${CONTROL_PLANE_IP}:6443/healthz

# 6. Verificar certificados do kubelet
openssl x509 -in /var/lib/kubelet/kubelet.pem -noout -dates

# 7. Reiniciar kubelet após corrigir o problema
sudo systemctl restart kubelet

# 8. Aguardar e verificar
sleep 30
kubectl get nodes
```

---

### Problema: Pod fica em estado Pending

**Sintoma:**
```
NAME                          READY   STATUS    RESTARTS   AGE
nginx-test-7c5b8d6c88-abc12  0/1     Pending   0          5m
```

**Causa provável:** O scheduler não consegue encontrar um nó adequado para o pod. Pode ser por falta de recursos, taints nos nós, ou scheduler não está rodando.

**Resolução:**
```bash
# 1. Verificar eventos do pod para entender o motivo
kubectl describe pod -l app=nginx-test | grep -A 5 "Events:"

# Mensagens comuns:
#   "0/2 nodes are available: 2 node(s) had taint..." → Nós com taints
#   "0/2 nodes are available: 2 Insufficient cpu" → Recursos insuficientes
#   "no nodes available to schedule pods" → Nenhum nó Ready

# 2. Verificar se o scheduler está rodando
curl -sk https://127.0.0.1:10259/healthz

# 3. Verificar se há nós disponíveis
kubectl get nodes

# 4. Verificar taints nos nós
kubectl describe nodes | grep -i taint

# 5. Se houver taint no control plane, remover (para labs)
kubectl taint nodes ${CONTROL_PLANE_NAME} node-role.kubernetes.io/control-plane:NoSchedule-

# 6. Verificar recursos disponíveis nos nós
kubectl describe nodes | grep -A 5 "Allocated resources"
```

---

### Problema: Service não roteia tráfego (connection refused no NodePort)

**Sintoma:**
```
curl: (7) Failed to connect to 10.0.1.20 port 31234: Connection refused
```

**Causa provável:** O kube-proxy não está rodando, as regras iptables não foram criadas, ou o pod backend não está running.

**Resolução:**
```bash
# 1. Verificar se o pod backend está running
kubectl get pods -l app=nginx-test

# 2. Verificar se o Service tem endpoints
kubectl get endpoints nginx-test
# Se "ENDPOINTS" estiver vazio: o label selector não corresponde ao pod

# 3. Verificar se o kube-proxy está rodando no worker node
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${WORKER_NODE_IP} \
  "sudo systemctl status kube-proxy"

# 4. Verificar regras iptables para o Service
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${WORKER_NODE_IP} \
  "sudo iptables -t nat -L KUBE-NODEPORTS"

# 5. Verificar se o Security Group permite tráfego na porta NodePort (30000-32767)
aws ec2 describe-security-groups \
  --group-ids <WORKER_SG_ID> \
  --query 'SecurityGroups[].IpPermissions[?FromPort<=`31234` && ToPort>=`31234`]'

# 6. Reiniciar kube-proxy se necessário
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${WORKER_NODE_IP} \
  "sudo systemctl restart kube-proxy"
```

---

### Problema: DNS não resolve nome do serviço

**Sintoma:**
```
** server can't find nginx-test.default.svc.cluster.local: NXDOMAIN
```

Ou:
```
;; connection timed out; no servers could be reached
```

**Causa provável:** CoreDNS não está rodando, o Service kube-dns não tem endpoints, ou o kubelet não está configurado com o DNS correto.

**Resolução:**
```bash
# 1. Verificar se os pods CoreDNS estão running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Verificar logs do CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20

# 3. Verificar se o Service kube-dns existe e tem endpoints
kubectl get service kube-dns -n kube-system
kubectl get endpoints kube-dns -n kube-system

# 4. Verificar configuração DNS do kubelet
# O kubelet deve ter --cluster-dns=10.96.0.10 (CLUSTER_DNS de variables.env)
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${WORKER_NODE_IP} \
  "cat /var/lib/kubelet/kubelet-config.yaml | grep -i dns"

# 5. Verificar resolv.conf dentro de um pod
kubectl run dns-debug --image=busybox:1.36 --rm -it --restart=Never -- \
  cat /etc/resolv.conf

# Saída esperada:
# nameserver 10.96.0.10
# search default.svc.cluster.local svc.cluster.local cluster.local
# ndots:5

# 6. Se CoreDNS não está rodando, verificar o Deployment
kubectl describe deployment coredns -n kube-system
```

---

### Problema: kubelet ou kube-proxy não inicia (serviço failed)

**Sintoma:**
```
● kubelet.service - Kubernetes Kubelet
     Active: failed (Result: exit-code) since ...
```

**Causa provável:** Configuração incorreta, binário não encontrado, certificados inválidos, ou dependência (containerd) não está rodando.

**Resolução:**
```bash
# 1. Verificar o motivo exato da falha
sudo journalctl -u kubelet --no-pager -n 50 | grep -i "error\|fatal\|failed"

# 2. Verificar se o binário existe e é executável
ls -la /usr/local/bin/kubelet
ls -la /usr/local/bin/kube-proxy

# 3. Verificar se o containerd está rodando (dependência do kubelet)
sudo systemctl status containerd

# 4. Verificar se os certificados existem nos caminhos configurados
ls -la /var/lib/kubelet/kubelet.pem
ls -la /var/lib/kubelet/kubelet-key.pem

# 5. Verificar permissões dos arquivos de configuração
ls -la /var/lib/kubelet/kubelet-config.yaml
ls -la /var/lib/kubelet/kubeconfig

# 6. Corrigir o problema identificado e reiniciar
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl restart kube-proxy

# 7. Verificar status após reinício
sudo systemctl status kubelet
sudo systemctl status kube-proxy
```

---

## Próximo Módulo

Parabéns! Se todos os indicadores do checklist estão verdes, seu cluster Kubernetes está totalmente funcional. Você construiu um cluster completo do zero, componente a componente.

O próximo passo é testar seus conhecimentos com o simulador CKA:

➡️ [Simulador CKA](../../cka-simulator/)
