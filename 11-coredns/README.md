# Módulo 11 — CoreDNS

## Objetivo

Instalar e configurar o CoreDNS como servidor DNS interno do cluster Kubernetes, habilitando a descoberta de serviços via DNS. Ao final deste módulo, você terá:

- CoreDNS rodando como Deployment no namespace `kube-system`
- O Service `kube-dns` (ClusterIP `10.96.0.10`) disponível para resolução de nomes
- kubelet configurado para usar o CoreDNS como servidor DNS dos Pods
- Resolução funcional de nomes de Services, Pods e lookups cross-namespace
- Compreensão completa do Corefile e seus plugins

## Teoria

### O Papel do CoreDNS no Kubernetes

O CoreDNS é o servidor DNS padrão do Kubernetes desde a versão 1.13. Ele é responsável pela **descoberta de serviços** (service discovery) dentro do cluster, permitindo que Pods se comuniquem usando nomes em vez de endereços IP.

Quando um Pod precisa acessar um Service, ele faz uma consulta DNS ao CoreDNS, que resolve o nome para o ClusterIP correspondente. Isso elimina a necessidade de hardcoding de IPs e permite que Services sejam criados e destruídos dinamicamente.

### Convenção de Nomes DNS no Kubernetes

O Kubernetes segue uma convenção hierárquica para nomes DNS:

```
<service>.<namespace>.svc.cluster.local
```

| Componente | Descrição | Exemplo |
|---|---|---|
| `<service>` | Nome do Service | `nginx` |
| `<namespace>` | Namespace onde o Service existe | `default` |
| `svc` | Indica que é um Service | fixo |
| `cluster.local` | Domínio base do cluster | configurável |

**Exemplos de resolução:**

| Nome Completo (FQDN) | Resolve Para |
|---|---|
| `kubernetes.default.svc.cluster.local` | ClusterIP do API Server |
| `kube-dns.kube-system.svc.cluster.local` | ClusterIP do próprio CoreDNS |
| `nginx.production.svc.cluster.local` | ClusterIP do Service nginx no namespace production |

#### Registros DNS para Pods

Além de Services, o CoreDNS também cria registros para Pods individuais usando o IP do Pod com pontos substituídos por hífens:

```
<pod-ip-com-hifens>.<namespace>.pod.cluster.local
```

**Exemplo:** Um Pod com IP `10.244.1.5` no namespace `default` terá o registro:
```
10-244-1-5.default.pod.cluster.local
```

### Arquitetura do CoreDNS no Cluster

```
┌─────────────────────────────────────────────────────────────┐
│                        Worker Node                           │
│                                                             │
│  ┌──────────┐    DNS Query     ┌──────────────────────┐    │
│  │   Pod    │ ──────────────── │  CoreDNS Pod         │    │
│  │ (app)    │  ◄────────────── │  (kube-system)       │    │
│  └──────────┘    DNS Response  │                      │    │
│       │                        │  Corefile:           │    │
│       │                        │  - kubernetes plugin │    │
│       │                        │  - forward plugin    │    │
│       │                        │  - cache plugin      │    │
│       ▼                        └──────────┬───────────┘    │
│  ┌──────────┐                             │                │
│  │ kubelet  │                             │                │
│  │ (DNS:    │                             ▼                │
│  │ 10.96.   │                  ┌──────────────────────┐    │
│  │  0.10)   │                  │  kube-apiserver      │    │
│  └──────────┘                  │  (watch Services/    │    │
│                                │   Endpoints)         │    │
│                                └──────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**Fluxo de resolução DNS:**

1. Um Pod faz uma consulta DNS (ex: `nginx.default.svc.cluster.local`)
2. O `/etc/resolv.conf` do Pod aponta para `10.96.0.10` (kube-dns Service)
3. A requisição chega ao CoreDNS Pod via o Service `kube-dns`
4. O CoreDNS consulta o kube-apiserver para obter o ClusterIP do Service
5. O CoreDNS retorna o IP ao Pod solicitante
6. Para domínios externos (ex: `google.com`), o CoreDNS encaminha para servidores DNS upstream

### O Corefile — Configuração do CoreDNS

O CoreDNS é configurado através de um arquivo chamado **Corefile**, armazenado em um ConfigMap. O Corefile define zonas DNS e plugins que processam as consultas.

#### Plugins Principais

| Plugin | Função | Descrição |
|---|---|---|
| `kubernetes` | Resolução interna | Responde consultas para `cluster.local` usando dados do API server |
| `forward` | Encaminhamento | Encaminha consultas externas para servidores DNS upstream (ex: `/etc/resolv.conf` do nó) |
| `cache` | Cache | Armazena respostas em cache para reduzir latência e carga no API server |
| `errors` | Logging de erros | Registra erros de consulta no stdout para diagnóstico |
| `health` | Health check | Expõe endpoint HTTP em `:8080/health` para liveness probe |
| `ready` | Readiness check | Expõe endpoint HTTP em `:8181/ready` para readiness probe |
| `log` | Logging completo | Registra todas as consultas DNS (opcional, útil para debug) |
| `loop` | Detecção de loop | Detecta loops de encaminhamento DNS e interrompe o CoreDNS |
| `reload` | Hot reload | Recarrega o Corefile automaticamente quando o ConfigMap é atualizado |
| `loadbalance` | Balanceamento | Randomiza a ordem dos registros A em respostas DNS |

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 08 — kubelet](../08-kubelet/) — kubelet rodando e nó registrado no cluster
- [Módulo 10 — CNI Networking](../10-cni-networking/) — plugin CNI instalado e pod-to-pod networking funcional

Componentes que devem estar operacionais:

- kube-apiserver acessível e respondendo
- kubelet rodando no worker node com status Ready
- Plugin CNI configurado (Pods conseguem obter IPs e se comunicar)
- kubectl configurado para acessar o cluster

## Comandos Passo a Passo

### 1. Criar o ConfigMap do Corefile

O Corefile define como o CoreDNS processa consultas DNS. Ele é armazenado como um ConfigMap no namespace `kube-system` para que possa ser atualizado sem recriar o Pod.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
EOF
```

**Saída esperada:**
```
configmap/coredns created
```

#### Explicação de cada plugin no Corefile

**`.:53`** — Define a zona raiz (`.`) escutando na porta 53 (DNS padrão). Todas as consultas DNS serão processadas por este bloco.

**`errors`** — Habilita o logging de erros no stdout. Quando uma consulta falha, o erro é registrado para facilitar o diagnóstico. Sem parâmetros adicionais, registra apenas erros (não consultas bem-sucedidas).

**`health { lameduck 5s }`** — Expõe um endpoint HTTP em `http://:8080/health` que retorna 200 quando o CoreDNS está saudável. O parâmetro `lameduck 5s` faz o CoreDNS continuar respondendo por 5 segundos após receber um sinal de shutdown, permitindo que conexões em andamento sejam finalizadas graciosamente.

**`ready`** — Expõe um endpoint HTTP em `http://:8181/ready` que retorna 200 quando todos os plugins que implementam a interface `ready` reportam que estão prontos. Usado como readiness probe pelo Kubernetes para saber quando o Pod pode receber tráfego.

**`kubernetes cluster.local in-addr.arpa ip6.arpa`** — O plugin principal para integração com Kubernetes:
- `cluster.local` — domínio base para resolução de Services e Pods
- `in-addr.arpa` — habilita resolução reversa (IP → nome) para IPv4
- `ip6.arpa` — habilita resolução reversa para IPv6
- `pods insecure` — habilita registros DNS para Pods (baseado em IP). O modo `insecure` não verifica se o Pod realmente existe, apenas gera o registro baseado no formato do nome
- `fallthrough in-addr.arpa ip6.arpa` — se a consulta reversa não for encontrada no Kubernetes, passa para o próximo plugin
- `ttl 30` — tempo de vida (em segundos) dos registros DNS retornados. Após 30s, o cliente deve consultar novamente

**`forward . /etc/resolv.conf { max_concurrent 1000 }`** — Encaminha consultas que não são do domínio `cluster.local` para os servidores DNS configurados no `/etc/resolv.conf` do nó (geralmente o DNS da VPC na AWS: `10.0.0.2`). O parâmetro `max_concurrent 1000` limita o número de consultas simultâneas encaminhadas.

**`cache 30`** — Armazena respostas DNS em cache por até 30 segundos. Reduz a latência para consultas repetidas e diminui a carga no kube-apiserver.

**`loop`** — Detecta loops de encaminhamento DNS. Se o CoreDNS detectar que está encaminhando consultas para si mesmo (loop infinito), ele interrompe o processo para evitar consumo excessivo de recursos.

**`reload`** — Monitora o Corefile para alterações e recarrega a configuração automaticamente quando o ConfigMap é atualizado. Isso permite alterar a configuração DNS sem reiniciar o Pod.

**`loadbalance`** — Randomiza a ordem dos registros A (endereços IP) nas respostas DNS. Isso distribui o tráfego entre múltiplos endpoints de um Service de forma round-robin no nível DNS.

---

### 2. Criar o ServiceAccount e ClusterRole para o CoreDNS

O CoreDNS precisa de permissões para consultar o kube-apiserver e obter informações sobre Services, Endpoints, Namespaces e Pods. Criamos um ServiceAccount com as permissões RBAC necessárias.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:coredns
rules:
  - apiGroups: [""]
    resources: ["endpoints", "services", "pods", "namespaces"]
    verbs: ["list", "watch"]
  - apiGroups: ["discovery.k8s.io"]
    resources: ["endpointslices"]
    verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
  - kind: ServiceAccount
    name: coredns
    namespace: kube-system
EOF
```

**Saída esperada:**
```
serviceaccount/coredns created
clusterrole.rbac.authorization.k8s.io/system:coredns created
clusterrolebinding.rbac.authorization.k8s.io/system:coredns created
```

O ClusterRole concede permissões de `list` e `watch` nos recursos que o CoreDNS precisa monitorar para manter seus registros DNS atualizados. Quando um novo Service é criado, o CoreDNS recebe a notificação via watch e atualiza seus registros automaticamente.

---

### 3. Criar o Deployment do CoreDNS

O CoreDNS é implantado como um Deployment com 2 réplicas para alta disponibilidade. Se um Pod falhar, o outro continua respondendo consultas DNS.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
        - key: "node-role.kubernetes.io/control-plane"
          effect: "NoSchedule"
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-cluster-critical
      containers:
        - name: coredns
          image: registry.k8s.io/coredns/coredns:v1.11.1
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              memory: 170Mi
            requests:
              cpu: 100m
              memory: 70Mi
          args: ["-conf", "/etc/coredns/Corefile"]
          volumeMounts:
            - name: config-volume
              mountPath: /etc/coredns
              readOnly: true
          ports:
            - containerPort: 53
              name: dns
              protocol: UDP
            - containerPort: 53
              name: dns-tcp
              protocol: TCP
            - containerPort: 9153
              name: metrics
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
              scheme: HTTP
            initialDelaySeconds: 60
            timeoutSeconds: 5
            successThreshold: 1
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: /ready
              port: 8181
              scheme: HTTP
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
              - key: Corefile
                path: Corefile
EOF
```

**Saída esperada:**
```
deployment.apps/coredns created
```

#### Explicação dos campos do Deployment

| Campo | Valor | Descrição |
|---|---|---|
| `replicas` | `2` | Duas réplicas para alta disponibilidade DNS |
| `strategy.rollingUpdate.maxUnavailable` | `1` | Durante atualizações, no máximo 1 Pod fica indisponível |
| `serviceAccountName` | `coredns` | Usa o ServiceAccount com permissões RBAC criado anteriormente |
| `tolerations` | `CriticalAddonsOnly`, `control-plane` | Permite scheduling em nós com taints de control plane |
| `priorityClassName` | `system-cluster-critical` | Prioridade alta — DNS é crítico para o cluster |
| `image` | `registry.k8s.io/coredns/coredns:v1.11.1` | Imagem oficial do CoreDNS versão 1.11.1 |
| `args` | `["-conf", "/etc/coredns/Corefile"]` | Caminho do arquivo de configuração dentro do container |
| `resources.requests.cpu` | `100m` | Requisição mínima de CPU (100 millicores) |
| `resources.requests.memory` | `70Mi` | Requisição mínima de memória (70 MiB) |
| `resources.limits.memory` | `170Mi` | Limite máximo de memória (170 MiB) |
| `ports` | `53/UDP`, `53/TCP`, `9153/TCP` | DNS (UDP e TCP) e métricas Prometheus |
| `livenessProbe` | `GET /health:8080` | Reinicia o container se não responder em 5s após 5 falhas |
| `readinessProbe` | `GET /ready:8181` | Remove do Service se não estiver pronto |
| `volumes.configMap` | `coredns` | Monta o ConfigMap com o Corefile no container |

---

### 4. Criar o Service kube-dns

O Service `kube-dns` é o ponto de entrada para consultas DNS no cluster. Ele tem um ClusterIP fixo (`10.96.0.10`) que é configurado no kubelet de cada nó como servidor DNS para os Pods.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.96.0.10
  ports:
    - name: dns
      port: 53
      protocol: UDP
      targetPort: 53
    - name: dns-tcp
      port: 53
      protocol: TCP
      targetPort: 53
    - name: metrics
      port: 9153
      protocol: TCP
      targetPort: 9153
EOF
```

**Saída esperada:**
```
service/kube-dns created
```

#### Por que o ClusterIP é fixo?

O IP `10.96.0.10` é definido estaticamente porque o kubelet precisa conhecer o endereço do servidor DNS **antes** de qualquer Service ser criado. Este IP é configurado no parâmetro `--cluster-dns` do kubelet e injetado no `/etc/resolv.conf` de cada Pod criado no cluster.

O IP `10.96.0.10` pertence ao range de Service CIDR (`10.96.0.0/12`) definido no `variables.env`.

---

### 5. Configurar o kubelet para usar o CoreDNS

O kubelet deve ser configurado para informar aos Pods qual servidor DNS usar. Isso é feito através dos parâmetros `--cluster-dns` e `--cluster-domain`.

Edite o arquivo de configuração do kubelet no worker node:

```bash
# No worker node, editar a configuração do kubelet
sudo vi /var/lib/kubelet/kubelet-config.yaml
```

Adicione ou verifique os seguintes parâmetros:

```yaml
clusterDNS:
  - 10.96.0.10
clusterDomain: cluster.local
```

Se o kubelet usa flags de linha de comando (no systemd unit file), verifique:

```bash
# Verificar flags do kubelet no unit file
grep -E "cluster-dns|cluster-domain" /etc/systemd/system/kubelet.service
```

**Saída esperada:**
```
--cluster-dns=10.96.0.10
--cluster-domain=cluster.local
```

Caso precise adicionar as flags, edite o unit file:

```bash
# Editar o unit file do kubelet
sudo vi /etc/systemd/system/kubelet.service
```

Adicione as flags na linha `ExecStart`:
```
--cluster-dns=10.96.0.10 \
--cluster-domain=cluster.local
```

Reinicie o kubelet para aplicar as alterações:

```bash
# Recarregar configuração do systemd e reiniciar kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

**Saída esperada:** Nenhuma saída indica sucesso.

#### Como o kubelet injeta a configuração DNS nos Pods

Quando o kubelet cria um Pod, ele automaticamente configura o `/etc/resolv.conf` do container com:

```
nameserver 10.96.0.10
search <namespace>.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

- **nameserver**: Aponta para o Service `kube-dns` (CoreDNS)
- **search**: Permite usar nomes curtos (ex: `nginx` resolve como `nginx.default.svc.cluster.local`)
- **ndots:5**: Se o nome consultado tiver menos de 5 pontos, o sistema tenta os sufixos de search antes de consultar como FQDN

---

### 6. Verificar o Deployment do CoreDNS

Após aplicar todos os manifests, verifique se os Pods do CoreDNS estão rodando corretamente.

```bash
# Verificar status dos Pods do CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

**Saída esperada:**
```
NAME                       READY   STATUS    RESTARTS   AGE
coredns-5dd5756b68-abc12   1/1     Running   0          30s
coredns-5dd5756b68-def34   1/1     Running   0          30s
```

A linha-chave é `STATUS: Running` e `READY: 1/1` — confirma que ambas as réplicas estão saudáveis.

```bash
# Verificar o Service kube-dns
kubectl get svc -n kube-system kube-dns
```

**Saída esperada:**
```
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   45s
```

A linha-chave é `CLUSTER-IP: 10.96.0.10` — confirma que o Service tem o IP fixo esperado.

```bash
# Verificar endpoints do Service kube-dns
kubectl get endpoints -n kube-system kube-dns
```

**Saída esperada:**
```
NAME       ENDPOINTS                                                  AGE
kube-dns   10.244.0.2:53,10.244.0.3:53,10.244.0.2:53 + 3 more...   1m
```

A linha-chave é que existem endpoints listados — confirma que o Service está conectado aos Pods do CoreDNS.

```bash
# Verificar logs do CoreDNS (deve mostrar que está servindo na porta 53)
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=10
```

**Saída esperada:**
```
.:53
[INFO] plugin/reload: Running configuration SHA512 = abc123...
CoreDNS-1.11.1
linux/amd64, go1.21.x, abc1234
```

A linha-chave é `.:53` — confirma que o CoreDNS está escutando na porta 53.

## Verificação

### Teste 1: Resolução DNS de um Service

Crie um Pod temporário para testar a resolução DNS do Service `kubernetes` (que sempre existe no namespace `default`):

```bash
# Criar Pod de teste com ferramentas DNS
kubectl run dns-test --image=busybox:1.36 --restart=Never -- sleep 3600
```

**Saída esperada:**
```
pod/dns-test created
```

Aguarde o Pod ficar Running:

```bash
kubectl wait --for=condition=Ready pod/dns-test --timeout=60s
```

**Saída esperada:**
```
pod/dns-test condition met
```

Execute a consulta DNS para o Service `kubernetes`:

```bash
# Resolver o Service kubernetes.default.svc.cluster.local
kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local
```

**Saída esperada:**
```
Server:    10.96.0.10
Address:   10.96.0.10:53

Name:      kubernetes.default.svc.cluster.local
Address:   10.96.0.1
```

A linha-chave é `Address: 10.96.0.1` — confirma que o CoreDNS resolveu o nome do Service `kubernetes` para seu ClusterIP.

Teste também com nome curto (sem FQDN):

```bash
# Resolver usando nome curto (search domain será aplicado)
kubectl exec dns-test -- nslookup kubernetes
```

**Saída esperada:**
```
Server:    10.96.0.10
Address:   10.96.0.10:53

Name:      kubernetes.default.svc.cluster.local
Address:   10.96.0.1
```

---

### Teste 2: Resolução DNS de Pod por IP

Verifique o IP do Pod de teste e consulte seu registro DNS reverso:

```bash
# Obter o IP do Pod dns-test
kubectl get pod dns-test -o wide
```

**Saída esperada:**
```
NAME       READY   STATUS    RESTARTS   AGE   IP           NODE
dns-test   1/1     Running   0          2m    10.244.1.5   k8s-worker-01
```

Agora consulte o registro DNS baseado no IP do Pod (substitua o IP pelo valor real):

```bash
# Resolver registro DNS do Pod (substitua 10.244.1.5 pelo IP real)
kubectl exec dns-test -- nslookup 10-244-1-5.default.pod.cluster.local
```

**Saída esperada:**
```
Server:    10.96.0.10
Address:   10.96.0.10:53

Name:      10-244-1-5.default.pod.cluster.local
Address:   10.244.1.5
```

A linha-chave é que o nome `10-244-1-5.default.pod.cluster.local` resolve para o IP `10.244.1.5` — confirma que registros DNS de Pods estão funcionando.

---

### Teste 3: Lookup Cross-Namespace

Crie um Service em outro namespace e verifique que a resolução funciona entre namespaces:

```bash
# Criar namespace de teste
kubectl create namespace test-dns
```

**Saída esperada:**
```
namespace/test-dns created
```

```bash
# Criar um Deployment e Service no namespace test-dns
kubectl create deployment nginx-dns --image=nginx:1.25 -n test-dns
kubectl expose deployment nginx-dns --port=80 -n test-dns
```

**Saída esperada:**
```
deployment.apps/nginx-dns created
service/nginx-dns exposed
```

Aguarde o Pod ficar pronto:

```bash
kubectl wait --for=condition=Ready pod -l app=nginx-dns -n test-dns --timeout=60s
```

**Saída esperada:**
```
pod/nginx-dns-xxxxx condition met
```

Agora, a partir do Pod `dns-test` (no namespace `default`), resolva o Service no namespace `test-dns`:

```bash
# Resolver Service em outro namespace (cross-namespace lookup)
kubectl exec dns-test -- nslookup nginx-dns.test-dns.svc.cluster.local
```

**Saída esperada:**
```
Server:    10.96.0.10
Address:   10.96.0.10:53

Name:      nginx-dns.test-dns.svc.cluster.local
Address:   10.96.X.X
```

A linha-chave é que o nome `nginx-dns.test-dns.svc.cluster.local` resolve para um ClusterIP — confirma que lookups cross-namespace funcionam corretamente.

> **Nota**: O nome curto `nginx-dns` **não** resolve a partir do namespace `default` porque o search domain padrão é `default.svc.cluster.local`. Para acessar Services em outros namespaces, use o FQDN ou pelo menos `nginx-dns.test-dns`.

```bash
# Teste com nome parcial (namespace.svc)
kubectl exec dns-test -- nslookup nginx-dns.test-dns
```

**Saída esperada:**
```
Server:    10.96.0.10
Address:   10.96.0.10:53

Name:      nginx-dns.test-dns.svc.cluster.local
Address:   10.96.X.X
```

---

### Teste 4: Resolução de domínio externo

Verifique que o CoreDNS encaminha consultas externas corretamente:

```bash
# Resolver domínio externo (encaminhado via plugin forward)
kubectl exec dns-test -- nslookup google.com
```

**Saída esperada:**
```
Server:    10.96.0.10
Address:   10.96.0.10:53

Non-authoritative answer:
Name:      google.com
Address:   142.250.X.X
```

A linha-chave é `Non-authoritative answer` seguido de um IP — confirma que o plugin `forward` está encaminhando consultas externas para o DNS upstream.

---

### Limpeza dos recursos de teste

Após concluir os testes, remova os recursos criados:

```bash
# Remover recursos de teste
kubectl delete pod dns-test
kubectl delete namespace test-dns
```

**Saída esperada:**
```
pod "dns-test" deleted
namespace "test-dns" deleted
```

---

### Verificação do /etc/resolv.conf dos Pods

Para confirmar que o kubelet está injetando a configuração DNS corretamente, crie um Pod e inspecione seu `/etc/resolv.conf`:

```bash
# Criar Pod e verificar resolv.conf
kubectl run resolv-check --image=busybox:1.36 --restart=Never -- cat /etc/resolv.conf
```

Aguarde o Pod completar e veja os logs:

```bash
kubectl logs resolv-check
```

**Saída esperada:**
```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

As linhas-chave são:
- `nameserver 10.96.0.10` — aponta para o CoreDNS
- `search default.svc.cluster.local` — permite usar nomes curtos
- `ndots:5` — configuração padrão do Kubernetes

```bash
# Limpar Pod de verificação
kubectl delete pod resolv-check
```

**Saída esperada:**
```
pod "resolv-check" deleted
```
