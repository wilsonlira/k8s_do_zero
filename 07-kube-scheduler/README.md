# Módulo 07 — kube-scheduler

## Objetivo

Instalar e configurar o kube-scheduler no cluster Kubernetes. Ao final deste módulo, você terá:

- Compreensão do papel do scheduler na atribuição de Pods a nós
- Entendimento do algoritmo de scheduling: fase de filtragem e fase de pontuação
- kube-scheduler instalado e configurado como serviço systemd no nó Control Plane
- Kubeconfig do scheduler gerado para autenticação com o kube-apiserver
- Capacidade de verificar o funcionamento do scheduler observando Pods transitarem de Pending para Running

## Teoria

### O Papel do kube-scheduler no Kubernetes

O **kube-scheduler** é o componente do control plane responsável por **decidir em qual nó cada Pod será executado**. Quando um novo Pod é criado (via Deployment, Job, ou diretamente), ele inicialmente não tem um nó atribuído — seu campo `spec.nodeName` está vazio e o Pod fica no estado **Pending**.

O scheduler observa (watch) o kube-apiserver em busca de Pods sem nó atribuído e, para cada um, executa o algoritmo de scheduling para selecionar o melhor nó disponível.

**Fluxo de scheduling:**

1. Um Pod é criado via API (ex: `kubectl create deployment nginx --image=nginx`)
2. O kube-apiserver persiste o Pod no etcd com `spec.nodeName` vazio
3. O kube-scheduler detecta o Pod sem nó atribuído via watch
4. O scheduler executa o algoritmo de scheduling (filtragem + pontuação)
5. O scheduler atualiza o Pod no apiserver com o nó selecionado (`spec.nodeName = "worker-01"`)
6. O kubelet do nó selecionado detecta o Pod atribuído a ele e inicia os containers

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Fluxo de Scheduling                                │
│                                                                      │
│  ┌────────┐    ┌──────────────┐    ┌───────────────┐    ┌────────┐  │
│  │ kubectl│───►│kube-apiserver│◄───│kube-scheduler │    │kubelet │  │
│  │        │    │              │    │               │    │        │  │
│  │ create │    │  Pod criado  │    │  1. Filtragem │    │ Inicia │  │
│  │  pod   │    │  (Pending)   │    │  2. Pontuação │    │  Pod   │  │
│  └────────┘    │              │    │  3. Binding   │    │        │  │
│                │  Pod bound   │───►│               │    │        │  │
│                │  (nodeName)  │    └───────────────┘    │        │  │
│                │              │─────────────────────────►│        │  │
│                └──────────────┘                          └────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Algoritmo de Scheduling

O algoritmo de scheduling do Kubernetes é dividido em duas fases principais:

#### Fase 1: Filtragem (Filtering)

A fase de filtragem **elimina nós que não podem executar o Pod**. O scheduler aplica uma série de predicados (filtros) e remove da lista qualquer nó que não satisfaça todos os requisitos.

**Filtros aplicados:**

| Filtro | Descrição |
|--------|-----------|
| **NodeResourcesFit** | Verifica se o nó tem CPU e memória suficientes para os `requests` do Pod. |
| **NodeName** | Se o Pod especifica `spec.nodeName`, apenas esse nó passa. |
| **NodeSelector** | Verifica se o nó tem os labels exigidos pelo `spec.nodeSelector` do Pod. |
| **TaintToleration** | Verifica se o Pod tolera os taints do nó. |
| **NodeAffinity** | Avalia regras de afinidade (`requiredDuringSchedulingIgnoredDuringExecution`). |
| **NodePorts** | Verifica se as portas `hostPort` solicitadas estão disponíveis no nó. |
| **PodFitsVolumes** | Verifica se os volumes persistentes podem ser montados no nó. |
| **NodeUnschedulable** | Exclui nós marcados como `Unschedulable` (cordon). |

**Resultado**: Lista de nós elegíveis (pode ser vazia → Pod fica Pending).

#### Fase 2: Pontuação (Scoring)

A fase de pontuação **classifica os nós elegíveis** para determinar o melhor candidato. Cada plugin de scoring atribui uma nota (0-100) a cada nó, e as notas são ponderadas.

**Plugins de scoring:**

| Plugin | Descrição |
|--------|-----------|
| **NodeResourcesBalancedAllocation** | Favorece nós onde CPU e memória ficam balanceados após o scheduling. |
| **NodeResourcesLeastAllocated** | Favorece nós com mais recursos livres (espalha carga). |
| **InterPodAffinity** | Pontua baseado em regras de afinidade/anti-afinidade entre Pods. |
| **TaintToleration** | Nós com menos taints tolerados recebem pontuação maior. |
| **ImageLocality** | Favorece nós que já possuem a imagem do container em cache. |
| **NodeAffinity** | Pontua baseado em regras de afinidade preferencial (`preferredDuringScheduling`). |

**Resultado**: O nó com maior pontuação total é selecionado. Em caso de empate, um nó é escolhido aleatoriamente.

### Binding

Após selecionar o nó, o scheduler cria um **Binding** — uma requisição ao kube-apiserver para atualizar o campo `spec.nodeName` do Pod. A partir desse momento, o kubelet do nó selecionado assume a responsabilidade de iniciar os containers do Pod.

### Scheduling no Nosso Lab

No nosso lab com um único worker node, o algoritmo de scheduling é simplificado:

- **Filtragem**: O único worker node deve satisfazer todos os predicados (recursos, taints, etc.)
- **Pontuação**: Com apenas um nó elegível, ele sempre recebe a pontuação máxima
- **Resultado prático**: Todos os Pods são atribuídos ao worker node (exceto se ele estiver com recursos insuficientes ou marcado como Unschedulable)

> **Nota**: Pods de sistema (como CoreDNS) podem ser agendados no control plane se configurado com as tolerations adequadas.

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — certificados gerados e distribuídos
- [Módulo 05 — kube-apiserver](../05-kube-apiserver/) — API server instalado e rodando

Você precisará dos seguintes itens dos módulos anteriores:

- Certificado da CA (`/etc/kubernetes/pki/ca.pem`)
- Certificado do kube-scheduler (`/etc/kubernetes/pki/kube-scheduler.pem`)
- Chave privada do kube-scheduler (`/etc/kubernetes/pki/kube-scheduler-key.pem`)
- kube-apiserver rodando e acessível em `https://${CONTROL_PLANE_IP}:6443`
- Acesso SSH ao nó Control Plane

> **Nota**: Todos os comandos deste módulo devem ser executados no **nó Control Plane** via SSH.

## Comandos Passo a Passo

> **Nota**: Todos os comandos desta seção devem ser executados no nó **Control Plane**. Conecte-se via SSH antes de prosseguir.

### 1. Conectar ao Nó Control Plane

Conecte-se ao nó control plane via SSH para executar todos os comandos deste módulo:

```bash
# Conectar ao control plane via SSH
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_PUBLIC_IP}
```

**Saída esperada:**
```
Welcome to Ubuntu 22.04.3 LTS (GNU/Linux 5.15.0-1051-aws x86_64)
...
ubuntu@k8s-control-plane:~$
```

### 2. Baixar o Binário do kube-scheduler

Baixe a versão 1.29.0 do kube-scheduler do repositório oficial do Kubernetes:

```bash
# Definir a versão do Kubernetes
K8S_VERSION="1.29.0"

# Baixar o binário do kube-scheduler
wget -q --show-progress \
  "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kube-scheduler"
```

**Saída esperada:**
```
kube-scheduler  100%[===================>]  52.3M  11.2MB/s    in 4.7s
```

### 3. Instalar o Binário

Torne o binário executável e mova-o para um diretório no PATH do sistema:

```bash
# Tornar executável
chmod +x kube-scheduler

# Mover para /usr/local/bin
sudo mv kube-scheduler /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

Verifique que o binário foi instalado corretamente:

```bash
# Verificar versão do kube-scheduler
kube-scheduler --version
```

**Saída esperada:**
```
Kubernetes v1.29.0
```

### 4. Gerar o Kubeconfig do kube-scheduler

O kube-scheduler precisa de um kubeconfig para se autenticar com o kube-apiserver. Este arquivo contém o certificado de cliente, a chave privada e o endereço do API server:

```bash
# Obter o IP interno do nó
INTERNAL_IP=$(hostname -I | awk '{print $1}')

# Gerar o kubeconfig do kube-scheduler
kubectl config set-cluster k8s-lab \
  --certificate-authority=/etc/kubernetes/pki/ca.pem \
  --server=https://${INTERNAL_IP}:6443 \
  --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=/etc/kubernetes/pki/kube-scheduler.pem \
  --client-key=/etc/kubernetes/pki/kube-scheduler-key.pem \
  --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml

kubectl config set-context default \
  --cluster=k8s-lab \
  --user=system:kube-scheduler \
  --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml

kubectl config use-context default \
  --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml
```

**Saída esperada:**
```
Cluster "k8s-lab" set.
User "system:kube-scheduler" set.
Context "default" created.
Switched to context "default".
```

**Explicação dos comandos do kubeconfig:**

| Comando | Descrição |
|---------|-----------|
| `set-cluster` | Define o cluster alvo com o endereço do API server e o certificado da CA para validar a conexão TLS. |
| `set-credentials` | Define as credenciais do scheduler usando certificado de cliente e chave privada. O CN do certificado deve ser `system:kube-scheduler`. |
| `set-context` | Associa o cluster às credenciais em um contexto nomeado. |
| `use-context` | Define o contexto ativo que será usado por padrão. |

### 5. Verificar o Kubeconfig Gerado

Confirme que o kubeconfig foi criado corretamente:

```bash
# Verificar conteúdo do kubeconfig (sem exibir dados sensíveis)
kubectl config view --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml
```

**Saída esperada:**
```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.pem
    server: https://10.0.1.x:6443
  name: k8s-lab
contexts:
- context:
    cluster: k8s-lab
    user: system:kube-scheduler
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: system:kube-scheduler
  user:
    client-certificate: /etc/kubernetes/pki/kube-scheduler.pem
    client-key: /etc/kubernetes/pki/kube-scheduler-key.pem
```

### 6. Criar o Arquivo de Serviço systemd

Crie o unit file do systemd para gerenciar o kube-scheduler como um serviço do sistema:

```bash
# Criar unit file do kube-scheduler
cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kube-scheduler/
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml \\
  --authentication-kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml \\
  --authorization-kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml \\
  --bind-address=0.0.0.0 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

**Saída esperada:** O conteúdo do unit file será exibido no terminal (comportamento do `tee`).

### 7. Explicação dos Parâmetros de Configuração

Cada flag do kube-scheduler tem um propósito específico. Entender cada uma é fundamental para troubleshooting:

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--kubeconfig` | `/etc/kubernetes/kubeconfig-scheduler.yaml` | Caminho para o arquivo kubeconfig usado pelo scheduler para se conectar ao kube-apiserver. Contém credenciais de cliente (certificado + chave) e o endereço do API server. |
| `--authentication-kubeconfig` | `/etc/kubernetes/kubeconfig-scheduler.yaml` | Kubeconfig usado para autenticar requisições recebidas no endpoint seguro do scheduler (ex: health checks). Permite que o scheduler valide tokens de quem acessa seus endpoints. |
| `--authorization-kubeconfig` | `/etc/kubernetes/kubeconfig-scheduler.yaml` | Kubeconfig usado para verificar autorização de requisições recebidas. O scheduler consulta o API server para verificar se o chamador tem permissão (SubjectAccessReview). |
| `--bind-address` | `0.0.0.0` | Endereço IP no qual o scheduler escuta para servir seus endpoints HTTP (métricas em `/metrics` e health check em `/healthz`). `0.0.0.0` aceita conexões de qualquer interface. |
| `--leader-elect` | `true` | Habilita eleição de líder para alta disponibilidade. Em um setup com múltiplos schedulers, apenas o líder executa o scheduling. Os demais ficam em standby. No nosso lab single-node, o scheduler sempre será o líder. |
| `--v` | `2` | Nível de verbosidade dos logs (0=mínimo, 5=máximo). Nível 2 mostra informações úteis sem excesso de detalhes. |

**Parâmetros do systemd unit file:**

| Parâmetro | Descrição |
|-----------|-----------|
| `After=network.target` | Garante que o serviço só inicia após a rede estar disponível. |
| `Restart=on-failure` | Reinicia automaticamente se o processo falhar (exit code ≠ 0). |
| `RestartSec=5` | Aguarda 5 segundos antes de reiniciar após falha. |

### 8. Iniciar o Serviço kube-scheduler

Recarregue a configuração do systemd e inicie o kube-scheduler:

```bash
# Recarregar configuração do systemd
sudo systemctl daemon-reload

# Habilitar o kube-scheduler para iniciar no boot
sudo systemctl enable kube-scheduler

# Iniciar o serviço kube-scheduler
sudo systemctl start kube-scheduler
```

**Saída esperada:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/kube-scheduler.service → /etc/systemd/system/kube-scheduler.service.
```

Verifique que o serviço está rodando:

```bash
# Verificar status do serviço
sudo systemctl status kube-scheduler
```

**Saída esperada:**
```
● kube-scheduler.service - Kubernetes Scheduler
     Loaded: loaded (/etc/systemd/system/kube-scheduler.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 5s ago
       Docs: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-scheduler/
   Main PID: 2345 (kube-scheduler)
      Tasks: 7 (limit: 1024)
     Memory: 18.0M
        CPU: 150ms
     CGroup: /system.slice/kube-scheduler.service
             └─2345 /usr/local/bin/kube-scheduler --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml ...
```

**Linhas-chave para confirmar sucesso:**
- `Active: active (running)` — o serviço está rodando
- `enabled` — configurado para iniciar no boot

## Verificação

### 1. Verificar Saúde do Endpoint

O kube-scheduler expõe um endpoint `/healthz` para verificação de saúde. Consulte-o para confirmar que o scheduler está operacional:

```bash
# Verificar endpoint de saúde do scheduler
curl -s http://127.0.0.1:10259/healthz --insecure
```

**Saída esperada:**
```
ok
```

A resposta `ok` confirma que o kube-scheduler está saudável e pronto para processar requisições de scheduling.

> **Nota**: A porta 10259 é a porta segura padrão do kube-scheduler. O flag `--insecure` é necessário porque o endpoint usa HTTPS com certificado auto-assinado.

### 2. Verificar Logs do Scheduler

Verifique os logs para confirmar que o scheduler iniciou corretamente e está conectado ao API server:

```bash
# Verificar logs recentes do kube-scheduler
sudo journalctl -u kube-scheduler --no-pager -l --since "2 minutes ago"
```

**Saída esperada (linhas-chave):**
```
kube-scheduler: I0101 00:00:00.000000    2345 leaderelection.go:250] attempting to acquire leader lease kube-system/kube-scheduler...
kube-scheduler: I0101 00:00:00.000000    2345 leaderelection.go:260] successfully acquired lease kube-system/kube-scheduler
kube-scheduler: I0101 00:00:00.000000    2345 server.go:152] "Starting Kubernetes Scheduler" version="v1.29.0"
```

**Linhas-chave:**
- `successfully acquired lease` — o scheduler obteve a liderança (leader election)
- `Starting Kubernetes Scheduler` — o scheduler iniciou com sucesso

### 3. Verificar Leader Election

Confirme que o scheduler adquiriu o lease de liderança no namespace `kube-system`:

```bash
# Verificar lease do scheduler
kubectl get lease kube-scheduler -n kube-system \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

**Saída esperada:**
```
NAME             HOLDER                                            AGE
kube-scheduler   k8s-control-plane_xxxxxxxx-xxxx-xxxx-xxxx-xxxx   30s
```

**Explicação:**
- `HOLDER` — identifica o nó que detém a liderança do scheduler
- Se o campo HOLDER estiver preenchido, o scheduler está ativo e processando scheduling

### 4. Verificar Component Status via API

Verifique o status do scheduler através do kube-apiserver:

```bash
# Verificar component status
kubectl get componentstatuses \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

**Saída esperada:**
```
NAME                 STATUS    MESSAGE   ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   ok
```

A linha `scheduler Healthy ok` confirma que o kube-apiserver consegue se comunicar com o scheduler e que ele está saudável.

### 5. Demonstração de Scheduling — Pod Pending → Running

Esta é a verificação mais importante: demonstrar que o scheduler está efetivamente atribuindo Pods a nós. Crie um Pod de teste e observe a transição de Pending para Running.

> **Nota**: Esta demonstração requer que o kubelet esteja instalado e rodando em pelo menos um worker node (Módulo 08). Se o kubelet ainda não estiver configurado, o Pod ficará em Pending após o binding — isso é esperado e confirma que o scheduler fez sua parte (atribuiu o nó).

**Passo 1 — Criar um Pod de teste:**

```bash
# Criar um Pod de teste para demonstrar scheduling
kubectl run test-scheduler --image=nginx:1.25 --restart=Never \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

**Saída esperada:**
```
pod/test-scheduler created
```

**Passo 2 — Observar o estado do Pod:**

```bash
# Verificar o estado do Pod (imediatamente após criação)
kubectl get pod test-scheduler -o wide \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

**Saída esperada (com kubelet rodando no worker):**
```
NAME             READY   STATUS    RESTARTS   AGE   IP           NODE            NOMINATED NODE   READINESS GATES
test-scheduler   1/1     Running   0          10s   10.244.0.5   k8s-worker-01   <none>           <none>
```

**Saída esperada (sem kubelet — scheduler fez binding mas kubelet não iniciou o Pod):**
```
NAME             READY   STATUS    RESTARTS   AGE   IP       NODE            NOMINATED NODE   READINESS GATES
test-scheduler   0/1     Pending   0          10s   <none>   k8s-worker-01   <none>           <none>
```

**Linhas-chave:**
- `NODE: k8s-worker-01` — o scheduler atribuiu o Pod a um nó (binding realizado com sucesso)
- `STATUS: Running` — o kubelet iniciou o Pod com sucesso (fluxo completo)

**Passo 3 — Verificar eventos de scheduling:**

```bash
# Verificar eventos do Pod para ver a decisão do scheduler
kubectl describe pod test-scheduler \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml | grep -A 5 "Events:"
```

**Saída esperada:**
```
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  15s   default-scheduler  Successfully assigned default/test-scheduler to k8s-worker-01
  Normal  Pulling    14s   kubelet            Pulling image "nginx:1.25"
  Normal  Pulled     10s   kubelet            Successfully pulled image "nginx:1.25"
  Normal  Created    10s   kubelet            Created container test-scheduler
  Normal  Started    10s   kubelet            Started container test-scheduler
```

**Linhas-chave:**
- `Reason: Scheduled` — confirma que o kube-scheduler tomou a decisão
- `From: default-scheduler` — identifica qual scheduler fez o binding
- `Successfully assigned default/test-scheduler to k8s-worker-01` — mostra o nó selecionado

**Passo 4 — Limpar o Pod de teste:**

```bash
# Remover o Pod de teste
kubectl delete pod test-scheduler \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

**Saída esperada:**
```
pod "test-scheduler" deleted
```

## Troubleshooting

### Problema 1: kube-scheduler não inicia — "unable to load client CA file"

**Sintoma:**
```
E0101 00:00:00.000000    2345 run.go:74] "command failed" err="unable to load client CA file: open /etc/kubernetes/pki/ca.pem: no such file or directory"
```

**Causa provável:** O certificado da CA não está no caminho esperado ou o arquivo não existe. Isso pode ocorrer se os certificados não foram distribuídos corretamente no Módulo 02.

**Resolução:**

```bash
# Verificar se os certificados existem
ls -la /etc/kubernetes/pki/ca.pem
ls -la /etc/kubernetes/pki/kube-scheduler.pem
ls -la /etc/kubernetes/pki/kube-scheduler-key.pem

# Se não existirem, volte ao Módulo 02 e redistribua os certificados
# Após corrigir, reiniciar:
sudo systemctl restart kube-scheduler

# Verificar logs após reinício
sudo journalctl -u kube-scheduler --no-pager -l --since "1 minute ago"
```

### Problema 2: kube-scheduler não inicia — "invalid kubeconfig"

**Sintoma:**
```
E0101 00:00:00.000000    2345 run.go:74] "command failed" err="unable to build config from flags: unable to read kubeconfig: open /etc/kubernetes/kubeconfig-scheduler.yaml: no such file or directory"
```

**Causa provável:** O arquivo kubeconfig do scheduler não foi criado ou está em um caminho diferente do especificado no unit file.

**Resolução:**

```bash
# Verificar se o kubeconfig existe
ls -la /etc/kubernetes/kubeconfig-scheduler.yaml

# Se não existir, gere novamente (Passo 4 deste módulo)
# Verificar conteúdo do kubeconfig
kubectl config view --kubeconfig=/etc/kubernetes/kubeconfig-scheduler.yaml

# Verificar que o server URL está correto
grep "server:" /etc/kubernetes/kubeconfig-scheduler.yaml

# Após corrigir, reiniciar:
sudo systemctl restart kube-scheduler
```

### Problema 3: kube-scheduler não conecta ao API server — "connection refused"

**Sintoma:**
```
E0101 00:00:00.000000    2345 leaderelection.go:330] error retrieving resource lock kube-system/kube-scheduler: Get "https://10.0.1.x:6443/apis/coordination.k8s.io/v1/namespaces/kube-system/leases/kube-scheduler": dial tcp 10.0.1.x:6443: connect: connection refused
```

**Causa provável:** O kube-apiserver não está rodando ou não está escutando no endereço/porta configurado no kubeconfig do scheduler.

**Resolução:**

```bash
# Verificar se o kube-apiserver está rodando
sudo systemctl status kube-apiserver

# Se não estiver rodando, inicie-o
sudo systemctl start kube-apiserver

# Verificar que o apiserver está escutando na porta 6443
sudo ss -tlnp | grep 6443

# Verificar o endereço do server no kubeconfig do scheduler
grep "server:" /etc/kubernetes/kubeconfig-scheduler.yaml

# Testar conectividade com o apiserver
curl -k https://127.0.0.1:6443/healthz

# Se o IP estiver incorreto, regenere o kubeconfig (Passo 4)
# Após corrigir, reiniciar:
sudo systemctl restart kube-scheduler
```

### Problema 4: kube-scheduler não conecta ao API server — "x509: certificate signed by unknown authority"

**Sintoma:**
```
E0101 00:00:00.000000    2345 leaderelection.go:330] error retrieving resource lock kube-system/kube-scheduler: Get "https://10.0.1.x:6443/...": x509: certificate signed by unknown authority
```

**Causa provável:** O certificado da CA no kubeconfig do scheduler não corresponde à CA que assinou o certificado do kube-apiserver. Isso ocorre quando certificados foram regenerados parcialmente.

**Resolução:**

```bash
# Verificar o issuer do certificado do apiserver
openssl s_client -connect 127.0.0.1:6443 2>/dev/null | openssl x509 -noout -issuer

# Verificar o subject da CA no kubeconfig do scheduler
openssl x509 -in /etc/kubernetes/pki/ca.pem -noout -subject

# O issuer do apiserver deve corresponder ao subject da CA
# Se não corresponder, os certificados foram gerados por CAs diferentes

# Solução: Regenerar certificados com a mesma CA (voltar ao Módulo 02)
# Após corrigir, reiniciar:
sudo systemctl restart kube-scheduler
```

### Problema 5: Pod fica Pending — "no nodes available to schedule pods"

**Sintoma:**
```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  10s   default-scheduler  0/0 nodes are available: no nodes available to schedule pods
```

**Causa provável:** Nenhum worker node está registrado no cluster. O kubelet ainda não foi instalado ou não conseguiu se registrar com o API server.

**Resolução:**

```bash
# Verificar nós registrados no cluster
kubectl get nodes --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml

# Se nenhum nó aparecer, o kubelet não está rodando ou não se registrou
# Verifique o Módulo 08 (kubelet) para instalação do worker node

# Se nós existem mas estão NotReady, verifique o kubelet:
# (executar no worker node)
sudo systemctl status kubelet
sudo journalctl -u kubelet --no-pager -l --since "5 minutes ago"
```

### Problema 6: Pod fica Pending — "Insufficient cpu" ou "Insufficient memory"

**Sintoma:**
```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  10s   default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
```

**Causa provável:** O Pod solicita mais recursos (CPU ou memória) do que o nó tem disponível. Em instâncias t2.micro (1 vCPU, 1GB RAM), os recursos são limitados.

**Resolução:**

```bash
# Verificar recursos disponíveis no nó
kubectl describe node k8s-worker-01 \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml | grep -A 10 "Allocated resources"

# Verificar requests do Pod
kubectl describe pod <pod-name> \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml | grep -A 5 "Requests"

# Solução: Reduzir os requests do Pod ou remover Pods existentes para liberar recursos
# Exemplo: criar Pod sem requests explícitos
kubectl run test --image=nginx:1.25 --restart=Never \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

### Problema 7: kube-scheduler não inicia — "bind: address already in use"

**Sintoma:**
```
E0101 00:00:00.000000    2345 serving.go:150] "Failed to listen" err="listen tcp 0.0.0.0:10259: bind: address already in use"
```

**Causa provável:** Outra instância do kube-scheduler ou outro processo está usando a porta 10259.

**Resolução:**

```bash
# Identificar o processo usando a porta 10259
sudo ss -tlnp | grep 10259

# Se for uma instância antiga do scheduler, mate o processo
sudo kill $(sudo ss -tlnp | grep 10259 | awk '{print $NF}' | grep -oP 'pid=\K[0-9]+')

# Ou pare qualquer instância existente
sudo systemctl stop kube-scheduler
sudo killall kube-scheduler 2>/dev/null

# Reiniciar o serviço
sudo systemctl start kube-scheduler
```
