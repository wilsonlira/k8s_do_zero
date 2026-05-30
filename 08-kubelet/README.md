# Módulo 08 — kubelet

## Objetivo

Instalar e configurar o kubelet no worker node do cluster Kubernetes. Ao final deste módulo, você terá:

- Compreensão do papel do kubelet como agente primário do nó
- Entendimento do gerenciamento de ciclo de vida de Pods e reporte de status do nó
- kubelet instalado e configurado como serviço systemd no Worker Node
- Kubeconfig do kubelet gerado para autenticação com o kube-apiserver
- Worker node registrado no cluster e reportando status Ready
- Compreensão da comunicação entre kubelet e container runtime via CRI

## Teoria

### O Papel do kubelet no Kubernetes

O **kubelet** é o **agente primário** que roda em cada nó do cluster Kubernetes. Ele é o componente responsável por garantir que os containers descritos nas especificações de Pod estejam rodando e saudáveis no nó.

Diferente dos componentes do control plane (apiserver, scheduler, controller-manager) que rodam apenas no nó master, o kubelet roda em **todos os nós** — tanto no control plane quanto nos worker nodes.

**Responsabilidades principais do kubelet:**

| Responsabilidade | Descrição |
|-----------------|-----------|
| **Gerenciamento de Pods** | Recebe especificações de Pod do API server e garante que os containers estejam rodando conforme definido. |
| **Reporte de Status do Nó** | Reporta periodicamente o status do nó (capacidade, condições, endereços) ao control plane. |
| **Health Monitoring** | Executa probes de saúde (liveness, readiness, startup) nos containers e toma ações corretivas. |
| **Registro do Nó** | Registra o nó no cluster ao iniciar, informando seus recursos disponíveis. |
| **Gerenciamento de Volumes** | Monta volumes definidos na spec do Pod antes de iniciar os containers. |
| **Coleta de Métricas** | Coleta métricas de uso de recursos (CPU, memória) dos containers via cAdvisor integrado. |

### Ciclo de Vida de um Pod no kubelet

Quando o kube-scheduler atribui um Pod a um nó (define `spec.nodeName`), o kubelet desse nó detecta a atribuição via watch no API server e inicia o processo de criação:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Ciclo de Vida do Pod no kubelet                            │
│                                                                              │
│  ┌──────────────┐    ┌─────────┐    ┌────────────┐    ┌──────────────────┐  │
│  │kube-apiserver│───►│ kubelet │───►│ containerd │───►│  Container(s)    │  │
│  │              │    │         │    │  (via CRI) │    │   Running        │  │
│  │ Pod assigned │    │ 1. Sync │    │            │    │                  │  │
│  │ to this node │    │ 2. Pull │    │ 3. Create  │    │ 4. Start         │  │
│  │              │    │    image│    │    sandbox │    │    containers    │  │
│  └──────────────┘    │ 5. Probe│    │            │    │                  │  │
│                      │    health│    └────────────┘    └──────────────────┘  │
│                      └─────────┘                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Etapas detalhadas:**

1. **Watch & Sync** — O kubelet observa o API server e detecta Pods atribuídos ao seu nó
2. **Pull Image** — Solicita ao container runtime o download da imagem do container
3. **Create Sandbox** — Cria o sandbox do Pod (network namespace compartilhado entre containers)
4. **Start Containers** — Inicia cada container definido na spec do Pod
5. **Health Probes** — Executa probes de saúde periodicamente e reporta status ao API server
6. **Status Update** — Atualiza o status do Pod no API server (Running, Succeeded, Failed)

### Reporte de Status do Nó

O kubelet reporta periodicamente o status do nó ao control plane. Esse reporte inclui:

- **Node Conditions** — condições como `Ready`, `MemoryPressure`, `DiskPressure`, `PIDPressure`
- **Node Capacity** — recursos totais do nó (CPU, memória, pods máximos)
- **Node Allocatable** — recursos disponíveis para Pods (capacity menos reservas do sistema)
- **Node Addresses** — IPs internos e externos do nó
- **Node Info** — informações do sistema (kernel, OS, container runtime, versão do kubelet)

O nó é considerado **Ready** quando:
- O kubelet está rodando e se comunicando com o API server
- O container runtime está funcional
- A rede do nó está configurada corretamente
- Não há condições de pressão (memória, disco, PIDs)

Se o API server não receber um heartbeat do kubelet dentro do timeout configurado (padrão: 40 segundos), o nó é marcado como **NotReady** e o controller-manager pode iniciar a evicção de Pods.

### Comunicação com o Container Runtime via CRI

O kubelet **não gerencia containers diretamente**. Ele delega todas as operações de container ao **container runtime** através da interface **CRI (Container Runtime Interface)**.

**CRI** é uma API gRPC padronizada que define dois serviços:

| Serviço | Responsabilidade |
|---------|-----------------|
| **RuntimeService** | Gerencia o ciclo de vida de Pods e containers (criar, iniciar, parar, remover). |
| **ImageService** | Gerencia imagens de container (pull, list, remove). |

**Comunicação via socket Unix:**

O kubelet se conecta ao container runtime através de um **socket Unix**. No caso do containerd:

```
kubelet ──── gRPC ────► unix:///run/containerd/containerd.sock ────► containerd
```

**Fluxo de criação de um Pod via CRI:**

1. kubelet chama `RunPodSandbox()` → containerd cria o network namespace e configura a rede (via CNI)
2. kubelet chama `PullImage()` → containerd baixa a imagem do registry
3. kubelet chama `CreateContainer()` → containerd cria o container dentro do sandbox
4. kubelet chama `StartContainer()` → containerd inicia o processo do container
5. kubelet chama `ContainerStatus()` periodicamente → containerd retorna o estado atual

> **Nota**: No nosso lab, usamos o containerd como container runtime (instalado no Módulo 03). O socket está em `/run/containerd/containerd.sock`.

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — certificados do kubelet gerados e distribuídos
- [Módulo 03 — Container Runtime](../03-container-runtime/) — containerd instalado e rodando no worker node
- [Módulo 05 — kube-apiserver](../05-kube-apiserver/) — API server instalado e acessível

Você precisará dos seguintes itens dos módulos anteriores:

- Certificado da CA (`/etc/kubernetes/pki/ca.pem`)
- Certificado do kubelet (`/etc/kubernetes/pki/kubelet.pem`)
- Chave privada do kubelet (`/etc/kubernetes/pki/kubelet-key.pem`)
- containerd rodando e socket acessível em `/run/containerd/containerd.sock`
- kube-apiserver rodando e acessível em `https://${CONTROL_PLANE_IP}:6443`
- Acesso SSH ao Worker Node

> **Nota**: Todos os comandos deste módulo devem ser executados no **Worker Node** via SSH, exceto quando explicitamente indicado.

## Comandos Passo a Passo

> **Nota**: Todos os comandos desta seção devem ser executados no nó **Worker Node**. Conecte-se via SSH antes de prosseguir.

### 1. Conectar ao Worker Node

Conecte-se ao worker node via SSH para executar todos os comandos deste módulo:

```bash
# Conectar ao worker node via SSH
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${WORKER_NODE_PUBLIC_IP}
```

**Saída esperada:**
```
Welcome to Ubuntu 22.04.3 LTS (GNU/Linux 5.15.0-1051-aws x86_64)
...
ubuntu@k8s-worker-01:~$
```

### 2. Criar Diretórios de Configuração

Crie os diretórios necessários para armazenar os binários, configurações e certificados do kubelet:

```bash
# Criar diretórios para configuração do kubelet
sudo mkdir -p /etc/kubernetes/pki
sudo mkdir -p /etc/kubernetes/manifests
sudo mkdir -p /var/lib/kubelet
```

**Saída esperada:** Nenhuma saída indica sucesso.

**Explicação dos diretórios:**

| Diretório | Propósito |
|-----------|-----------|
| `/etc/kubernetes/pki` | Armazena certificados TLS e chaves privadas do kubelet. |
| `/etc/kubernetes/manifests` | Diretório para static pods (pods gerenciados diretamente pelo kubelet sem API server). |
| `/var/lib/kubelet` | Diretório de trabalho do kubelet (estado, plugins, pods). |

### 3. Baixar o Binário do kubelet

Baixe a versão 1.29.0 do kubelet do repositório oficial do Kubernetes:

```bash
# Definir a versão do Kubernetes
K8S_VERSION="1.29.0"

# Baixar o binário do kubelet
wget -q --show-progress \
  "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kubelet"
```

**Saída esperada:**
```
kubelet         100%[===================>] 112.5M  12.8MB/s    in 8.8s
```

### 4. Instalar o Binário

Torne o binário executável e mova-o para um diretório no PATH do sistema:

```bash
# Tornar executável
chmod +x kubelet

# Mover para /usr/local/bin
sudo mv kubelet /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

Verifique que o binário foi instalado corretamente:

```bash
# Verificar versão do kubelet
kubelet --version
```

**Saída esperada:**
```
Kubernetes v1.29.0
```

### 5. Distribuir Certificados TLS

Copie os certificados gerados no Módulo 02 para o worker node. Se os certificados já foram distribuídos durante o Módulo 02, verifique que estão nos caminhos corretos:

```bash
# Verificar se os certificados já estão no worker node
ls -la /etc/kubernetes/pki/ca.pem
ls -la /etc/kubernetes/pki/kubelet.pem
ls -la /etc/kubernetes/pki/kubelet-key.pem
```

**Saída esperada:**
```
-rw-r--r-- 1 root root 1350 Jan  1 00:00 /etc/kubernetes/pki/ca.pem
-rw-r--r-- 1 root root 1521 Jan  1 00:00 /etc/kubernetes/pki/kubelet.pem
-rw------- 1 root root 1675 Jan  1 00:00 /etc/kubernetes/pki/kubelet-key.pem
```

Se os certificados não estiverem presentes, copie-os da máquina local (onde foram gerados):

```bash
# Executar na máquina LOCAL (não no worker node)
scp -i ~/.ssh/k8s-lab-key.pem \
  configs/pki/ca.pem \
  configs/pki/kubelet.pem \
  configs/pki/kubelet-key.pem \
  ubuntu@${WORKER_NODE_PUBLIC_IP}:/tmp/

# Executar no WORKER NODE — mover para o diretório correto
sudo mv /tmp/ca.pem /etc/kubernetes/pki/
sudo mv /tmp/kubelet.pem /etc/kubernetes/pki/
sudo mv /tmp/kubelet-key.pem /etc/kubernetes/pki/

# Ajustar permissões (chave privada deve ser restrita)
sudo chmod 644 /etc/kubernetes/pki/ca.pem
sudo chmod 644 /etc/kubernetes/pki/kubelet.pem
sudo chmod 600 /etc/kubernetes/pki/kubelet-key.pem
sudo chown root:root /etc/kubernetes/pki/*.pem
```

**Saída esperada:** Nenhuma saída indica sucesso.

> **Importante**: A chave privada (`kubelet-key.pem`) deve ter permissão `600` (leitura apenas pelo root). Permissões mais abertas representam um risco de segurança.

### 6. Gerar o Kubeconfig do kubelet

O kubelet precisa de um kubeconfig para se autenticar com o kube-apiserver. O certificado de cliente do kubelet usa o CN `system:node:<nome-do-nó>` e a organização `system:nodes`, que são reconhecidos pelo RBAC do Kubernetes para conceder as permissões necessárias ao nó:

```bash
# Definir variáveis (ajuste CONTROL_PLANE_IP com o IP real do control plane)
CONTROL_PLANE_IP="<IP_DO_CONTROL_PLANE>"
NODE_NAME="k8s-worker-01"

# Gerar o kubeconfig do kubelet
kubectl config set-cluster k8s-lab \
  --certificate-authority=/etc/kubernetes/pki/ca.pem \
  --server=https://${CONTROL_PLANE_IP}:6443 \
  --kubeconfig=/etc/kubernetes/kubeconfig-kubelet.yaml

kubectl config set-credentials system:node:${NODE_NAME} \
  --client-certificate=/etc/kubernetes/pki/kubelet.pem \
  --client-key=/etc/kubernetes/pki/kubelet-key.pem \
  --kubeconfig=/etc/kubernetes/kubeconfig-kubelet.yaml

kubectl config set-context default \
  --cluster=k8s-lab \
  --user=system:node:${NODE_NAME} \
  --kubeconfig=/etc/kubernetes/kubeconfig-kubelet.yaml

kubectl config use-context default \
  --kubeconfig=/etc/kubernetes/kubeconfig-kubelet.yaml
```

**Saída esperada:**
```
Cluster "k8s-lab" set.
User "system:node:k8s-worker-01" set.
Context "default" created.
Switched to context "default".
```

**Explicação dos comandos do kubeconfig:**

| Comando | Descrição |
|---------|-----------|
| `set-cluster` | Define o cluster alvo com o endereço do API server e o certificado da CA para validar a conexão TLS. |
| `set-credentials` | Define as credenciais do kubelet usando certificado de cliente e chave privada. O CN `system:node:<nome>` é reconhecido pelo Node Authorizer do Kubernetes. |
| `set-context` | Associa o cluster às credenciais em um contexto nomeado. |
| `use-context` | Define o contexto ativo que será usado por padrão. |

> **Importante**: O nome do usuário no kubeconfig (`system:node:k8s-worker-01`) deve corresponder exatamente ao CN do certificado do kubelet. O Node Authorizer usa esse padrão para conceder permissões específicas ao nó.

### 7. Verificar o Kubeconfig Gerado

Confirme que o kubeconfig foi criado corretamente:

```bash
# Verificar conteúdo do kubeconfig (sem exibir dados sensíveis)
kubectl config view --kubeconfig=/etc/kubernetes/kubeconfig-kubelet.yaml
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
    user: system:node:k8s-worker-01
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: system:node:k8s-worker-01
  user:
    client-certificate: /etc/kubernetes/pki/kubelet.pem
    client-key: /etc/kubernetes/pki/kubelet-key.pem
```

### 8. Criar o Arquivo de Configuração do kubelet

O kubelet pode receber configuração via flags de linha de comando ou via arquivo de configuração YAML. Usaremos o arquivo de configuração (recomendado pela documentação oficial) para melhor organização:

```bash
# Criar arquivo de configuração do kubelet
cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/etc/kubernetes/pki/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.96.0.10"
podCIDR: "10.244.0.0/16"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/etc/kubernetes/pki/kubelet.pem"
tlsPrivateKeyFile: "/etc/kubernetes/pki/kubelet-key.pem"
containerRuntimeEndpoint: "unix:///run/containerd/containerd.sock"
cgroupDriver: "systemd"
EOF
```

**Saída esperada:** O conteúdo do arquivo de configuração será exibido no terminal (comportamento do `tee`).

### 9. Explicação dos Parâmetros de Configuração

Cada parâmetro do arquivo `kubelet-config.yaml` tem um propósito específico. Entender cada um é fundamental para troubleshooting:

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `authentication.anonymous.enabled` | `false` | Desabilita acesso anônimo aos endpoints do kubelet. Todas as requisições devem ser autenticadas. Isso previne que qualquer processo no nó acesse a API do kubelet sem credenciais. |
| `authentication.webhook.enabled` | `true` | Habilita autenticação via webhook. O kubelet delega a validação de tokens bearer ao kube-apiserver (TokenReview API). Permite que o API server e outros componentes autorizados acessem os endpoints do kubelet. |
| `authentication.x509.clientCAFile` | `/etc/kubernetes/pki/ca.pem` | Caminho para o certificado da CA usado para validar certificados de cliente. Requisições com certificados assinados por esta CA são consideradas autenticadas. |
| `authorization.mode` | `Webhook` | Modo de autorização para requisições ao kubelet. No modo Webhook, o kubelet consulta o API server (SubjectAccessReview) para verificar se o chamador tem permissão para a ação solicitada. |
| `clusterDomain` | `cluster.local` | Domínio DNS do cluster. Usado para configurar o DNS dos containers — nomes de serviço são resolvidos como `<service>.<namespace>.svc.cluster.local`. |
| `clusterDNS` | `["10.96.0.10"]` | Endereço IP do serviço CoreDNS no cluster. O kubelet configura o `/etc/resolv.conf` de cada container para usar este IP como nameserver. Deve corresponder ao ClusterIP do serviço `kube-dns`. |
| `podCIDR` | `10.244.0.0/16` | Range de IPs disponível para Pods neste nó. O CNI plugin usa este CIDR para atribuir IPs aos Pods. Deve ser consistente com a configuração do CNI e do controller-manager. |
| `resolvConf` | `/run/systemd/resolve/resolv.conf` | Caminho para o arquivo resolv.conf do host. Em sistemas com systemd-resolved, este caminho evita loops de DNS. O kubelet usa este arquivo como base para o DNS dos containers. |
| `runtimeRequestTimeout` | `15m` | Timeout para requisições ao container runtime. Operações como pull de imagens grandes podem demorar — 15 minutos é suficiente para a maioria dos cenários. |
| `tlsCertFile` | `/etc/kubernetes/pki/kubelet.pem` | Certificado TLS do servidor kubelet. Usado para servir os endpoints HTTPS do kubelet (porta 10250). O API server usa este certificado para verificar a identidade do kubelet. |
| `tlsPrivateKeyFile` | `/etc/kubernetes/pki/kubelet-key.pem` | Chave privada correspondente ao certificado TLS do kubelet. Deve ter permissões restritas (600). |
| `containerRuntimeEndpoint` | `unix:///run/containerd/containerd.sock` | Endereço do socket Unix do container runtime. O kubelet se comunica com o containerd via gRPC através deste socket para todas as operações de container (CRI). |
| `cgroupDriver` | `systemd` | Driver de cgroups usado pelo kubelet. Deve ser o mesmo configurado no containerd (`SystemdCgroup = true`). Inconsistência entre kubelet e runtime causa falhas na criação de containers. |

### 10. Criar o Arquivo de Serviço systemd

Crie o unit file do systemd para gerenciar o kubelet como um serviço do sistema:

```bash
# Criar unit file do kubelet
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --kubeconfig=/etc/kubernetes/kubeconfig-kubelet.yaml \\
  --register-node=true \\
  --hostname-override=k8s-worker-01 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

**Saída esperada:** O conteúdo do unit file será exibido no terminal (comportamento do `tee`).

### 11. Explicação dos Parâmetros do Serviço systemd

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--config` | `/var/lib/kubelet/kubelet-config.yaml` | Caminho para o arquivo de configuração YAML do kubelet. Contém todos os parâmetros de runtime (autenticação, DNS, CIDR, TLS, etc.). Preferido sobre flags individuais para melhor organização. |
| `--kubeconfig` | `/etc/kubernetes/kubeconfig-kubelet.yaml` | Caminho para o kubeconfig usado pelo kubelet para se autenticar com o kube-apiserver. Contém o certificado de cliente, chave privada e endereço do API server. |
| `--register-node` | `true` | Habilita o registro automático do nó no cluster. Quando `true`, o kubelet cria automaticamente um objeto Node no API server ao iniciar. Se `false`, o nó deve ser criado manualmente. |
| `--hostname-override` | `k8s-worker-01` | Nome que o kubelet usa para se registrar no cluster. Sobrescreve o hostname do sistema. Deve corresponder ao CN do certificado (`system:node:k8s-worker-01`). |
| `--v` | `2` | Nível de verbosidade dos logs (0=mínimo, 5=máximo). Nível 2 mostra informações úteis sem excesso de detalhes. |

**Parâmetros do systemd unit file:**

| Parâmetro | Descrição |
|-----------|-----------|
| `After=containerd.service` | Garante que o kubelet só inicia após o containerd estar disponível. |
| `Requires=containerd.service` | Define dependência forte — se o containerd parar, o kubelet também para. |
| `Restart=on-failure` | Reinicia automaticamente se o processo falhar (exit code ≠ 0). |
| `RestartSec=5` | Aguarda 5 segundos antes de reiniciar após falha. |

### 12. Iniciar o Serviço kubelet

Recarregue a configuração do systemd e inicie o kubelet:

```bash
# Recarregar configuração do systemd
sudo systemctl daemon-reload

# Habilitar o kubelet para iniciar no boot
sudo systemctl enable kubelet

# Iniciar o serviço kubelet
sudo systemctl start kubelet
```

**Saída esperada:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/kubelet.service → /etc/systemd/system/kubelet.service.
```

Verifique que o serviço está rodando:

```bash
# Verificar status do serviço
sudo systemctl status kubelet
```

**Saída esperada:**
```
● kubelet.service - Kubernetes Kubelet
     Loaded: loaded (/etc/systemd/system/kubelet.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 5s ago
       Docs: https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/
   Main PID: 3456 (kubelet)
      Tasks: 12 (limit: 1024)
     Memory: 45.0M
        CPU: 500ms
     CGroup: /system.slice/kubelet.service
             └─3456 /usr/local/bin/kubelet --config=/var/lib/kubelet/kubelet-config.yaml ...
```

**Linhas-chave para confirmar sucesso:**
- `Active: active (running)` — o serviço está rodando
- `enabled` — configurado para iniciar no boot

## Verificação

### 1. Verificar Status do Serviço kubelet

Confirme que o kubelet está rodando sem erros:

```bash
# Verificar que o kubelet está ativo
sudo systemctl is-active kubelet
```

**Saída esperada:**
```
active
```

### 2. Verificar Registro do Nó no Cluster

Após o kubelet iniciar, ele se registra automaticamente no cluster. Verifique no **control plane** que o worker node aparece na lista de nós:

```bash
# Executar no CONTROL PLANE — verificar nós registrados
kubectl get nodes --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

**Saída esperada:**
```
NAME             STATUS   ROLES    AGE   VERSION
k8s-worker-01   Ready    <none>   30s   v1.29.0
```

**Linhas-chave:**
- `STATUS: Ready` — o nó está saudável e pronto para receber Pods
- `VERSION: v1.29.0` — confirma a versão do kubelet instalada

> **Nota**: O status pode aparecer como `NotReady` inicialmente se o CNI plugin ainda não foi instalado (Módulo 10). Isso é esperado — o nó só fica `Ready` quando a rede de Pods está configurada.

### 3. Verificar Detalhes do Nó

Inspecione os detalhes do nó para confirmar que o kubelet está reportando informações corretamente:

```bash
# Executar no CONTROL PLANE — detalhes do worker node
kubectl describe node k8s-worker-01 \
  --kubeconfig=/etc/kubernetes/kubeconfig-admin.yaml
```

**Saída esperada (seções relevantes):**
```
Name:               k8s-worker-01
Roles:              <none>
Labels:             kubernetes.io/hostname=k8s-worker-01
                    kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
Conditions:
  Type             Status  Reason                       Message
  ----             ------  ------                       -------
  MemoryPressure   False   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure      False   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready            True    KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  10.0.1.x
  Hostname:    k8s-worker-01
Capacity:
  cpu:                1
  memory:             1006892Ki
  pods:               110
System Info:
  Container Runtime Version:  containerd://1.7.13
  Kubelet Version:            v1.29.0
```

**Linhas-chave:**
- `Ready True KubeletReady` — o kubelet está saudável
- `Container Runtime Version: containerd://1.7.13` — runtime detectado corretamente
- `Kubelet Version: v1.29.0` — versão correta do kubelet
