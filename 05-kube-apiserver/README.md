# Módulo 05 — kube-apiserver

## Objetivo

Instalar e configurar o kube-apiserver como componente central do control plane Kubernetes. Ao final deste módulo, você terá:

- Compreensão do papel do kube-apiserver como front-end do control plane
- Entendimento de como o API server processa requisições REST
- Compreensão de que o kube-apiserver é o único componente que se comunica com o etcd
- Certificados TLS gerados para o apiserver (serving cert, etcd client cert, SA signing key)
- kube-apiserver instalado e configurado como serviço systemd no nó Control Plane
- Conhecimento sobre autenticação, autorização RBAC e admission controllers
- Capacidade de verificar a saúde do API server via endpoints /healthz e /livez

## Teoria

### O Papel do kube-apiserver no Kubernetes

O **kube-apiserver** é o **front-end do control plane** do Kubernetes. Ele expõe a API REST do Kubernetes e serve como o ponto central de comunicação entre todos os componentes do cluster.

**Responsabilidades principais:**

| Responsabilidade | Descrição |
|-----------------|-----------|
| **Expor a API REST** | Disponibiliza todos os recursos do Kubernetes (Pods, Services, Deployments, etc.) via endpoints HTTP/HTTPS |
| **Validar requisições** | Verifica autenticação, autorização e aplica admission controllers antes de persistir dados |
| **Comunicar com etcd** | É o **único** componente que lê e escreve diretamente no etcd |
| **Servir como hub** | Todos os outros componentes (scheduler, controller-manager, kubelet) se comunicam através do apiserver |
| **Watch API** | Permite que componentes observem mudanças em recursos em tempo real |

### Arquitetura e Fluxo de Requisições

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Control Plane Node                               │
│                                                                          │
│  ┌────────┐  ┌────────────┐  ┌───────────┐                             │
│  │kubectl │  │controller- │  │ scheduler │                             │
│  │        │  │  manager   │  │           │                             │
│  └───┬────┘  └─────┬──────┘  └─────┬─────┘                             │
│      │              │               │                                    │
│      │    HTTPS     │    HTTPS      │    HTTPS                          │
│      ▼              ▼               ▼                                    │
│  ┌──────────────────────────────────────────────┐                       │
│  │              kube-apiserver                    │                       │
│  │                                               │                       │
│  │  1. Autenticação (quem é você?)              │                       │
│  │  2. Autorização  (pode fazer isso?)          │                       │
│  │  3. Admission    (modificar/validar objeto)  │                       │
│  │  4. Persistência (salvar no etcd)            │                       │
│  └───────────────────────┬──────────────────────┘                       │
│                          │                                               │
│                    gRPC + TLS                                            │
│                          │                                               │
│                    ┌─────▼─────┐                                        │
│                    │   etcd    │                                        │
│                    └───────────┘                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Processamento de Requisições REST

Quando um cliente (kubectl, kubelet, controller-manager) envia uma requisição ao kube-apiserver, ela passa por uma pipeline de processamento:

**1. Autenticação (Authentication)**

O apiserver verifica a identidade do cliente. Métodos suportados no nosso lab:

| Método | Descrição | Uso no Lab |
|--------|-----------|------------|
| **Certificados de cliente (mTLS)** | O cliente apresenta um certificado X.509 assinado pela CA do cluster. O CN do certificado identifica o usuário e o O identifica o grupo. | Usado por kubectl, controller-manager, scheduler, kubelet |
| **Service Account Tokens** | Tokens JWT assinados pela chave privada do service account. Montados automaticamente em Pods. | Usado por Pods para acessar a API |
| **Bootstrap Tokens** | Tokens temporários para bootstrap de novos nós. | Usado durante adição de worker nodes |

**2. Autorização (Authorization)**

Após autenticação, o apiserver verifica se o usuário tem permissão para a ação solicitada:

| Modo | Descrição |
|------|-----------|
| **RBAC** (Role-Based Access Control) | Modo principal. Permissões definidas via Roles/ClusterRoles e vinculadas via RoleBindings/ClusterRoleBindings |
| **Node** | Autorização especial para kubelets. Permite que cada kubelet acesse apenas os recursos dos Pods agendados no seu nó |

No nosso lab, usamos `--authorization-mode=Node,RBAC`.

**3. Admission Controllers**

Após autorização, a requisição passa por admission controllers — plugins que podem modificar ou rejeitar objetos:

| Controller | Tipo | Descrição |
|-----------|------|-----------|
| **NamespaceLifecycle** | Validating | Rejeita requisições em namespaces sendo deletados |
| **LimitRanger** | Mutating | Aplica limites de recursos padrão a Pods sem limites definidos |
| **ServiceAccount** | Mutating | Injeta automaticamente service account tokens em Pods |
| **DefaultStorageClass** | Mutating | Atribui storage class padrão a PVCs sem classe definida |
| **ResourceQuota** | Validating | Verifica se a criação do objeto excede quotas do namespace |
| **NodeRestriction** | Validating | Limita o que kubelets podem modificar (apenas seus próprios nós e Pods) |
| **PodSecurity** | Validating | Aplica políticas de segurança a Pods (substituto do PodSecurityPolicy) |

**Tipos de Admission Controllers:**
- **Mutating**: Podem modificar o objeto antes de persistir (ex: adicionar labels padrão)
- **Validating**: Apenas validam — aceitam ou rejeitam sem modificar

A ordem de execução é: Mutating → Validating → Persistência no etcd.

### O kube-apiserver como Único Comunicador com o etcd

Este é um conceito fundamental: **nenhum outro componente do Kubernetes acessa o etcd diretamente**. Todos passam pelo kube-apiserver:

- O **kube-scheduler** observa Pods sem nó atribuído via Watch API do apiserver
- O **kube-controller-manager** observa e modifica recursos via API REST
- O **kubelet** reporta status do nó e recebe Pods para executar via API
- O **kubectl** envia comandos do usuário via API REST

Isso garante:
- **Consistência**: Todas as validações são aplicadas uniformemente
- **Segurança**: Controle de acesso centralizado (autenticação + autorização)
- **Auditoria**: Todas as operações passam por um único ponto

### Certificados TLS do kube-apiserver

O kube-apiserver utiliza múltiplos certificados TLS para diferentes propósitos:

| Certificado | Propósito | CN / SANs |
|-------------|-----------|-----------|
| **apiserver serving cert** | Apresentado aos clientes que se conectam ao apiserver (kubectl, kubelet, etc.) | CN=kube-apiserver, SANs: kubernetes, kubernetes.default, kubernetes.default.svc, IP do nó, 10.96.0.1 (primeiro IP do SERVICE_CIDR) |
| **etcd client cert** | Usado pelo apiserver para se autenticar ao etcd como cliente | CN=kube-apiserver-etcd-client, O=system:masters |
| **SA signing key pair** | Par de chaves para assinar e verificar Service Account tokens JWT | Chave privada assina tokens, chave pública verifica |
| **kubelet client cert** | Usado pelo apiserver para se conectar aos kubelets (logs, exec, port-forward) | CN=kube-apiserver-kubelet-client, O=system:masters |

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 00 — Pré-requisitos](../00-prerequisites/) — ferramentas básicas instaladas
- [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/) — instâncias EC2 provisionadas
- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — certificados gerados e distribuídos
- [Módulo 03 — Container Runtime](../03-container-runtime/) — containerd instalado (necessário para worker nodes)
- [Módulo 04 — etcd](../04-etcd/) — etcd instalado e rodando no control plane

Você precisará dos seguintes itens dos módulos anteriores:

- Certificado da CA (`/etc/kubernetes/pki/ca.pem`)
- Chave da CA (`/etc/kubernetes/pki/ca-key.pem`) — para gerar certificados do apiserver
- etcd rodando e saudável na porta 2379
- Certificados do etcd para conexão de cliente (`/etc/etcd/pki/ca.pem`)
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

### 2. Gerar Certificados TLS do kube-apiserver

#### 2.1 Gerar o Certificado Serving do API Server

Este certificado é apresentado aos clientes que se conectam ao kube-apiserver. Os SANs (Subject Alternative Names) devem incluir todos os nomes e IPs pelos quais o apiserver pode ser acessado:

```bash
# Obter o IP interno do nó
INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo "IP interno: ${INTERNAL_IP}"

# Definir variáveis
KUBERNETES_SVC_IP="10.96.0.1"  # Primeiro IP do SERVICE_CIDR (10.96.0.0/12)
CERT_DIR="/etc/kubernetes/pki"

# Criar diretório de certificados
sudo mkdir -p ${CERT_DIR}
```

**Saída esperada:**
```
IP interno: 10.0.1.x
```

Crie o arquivo de configuração CSR (Certificate Signing Request) para o apiserver:

```bash
# Criar CSR config para o apiserver serving certificate
cat <<EOF | sudo tee ${CERT_DIR}/apiserver-csr.json
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "São Paulo",
      "O": "Kubernetes",
      "OU": "Lab K8s",
      "ST": "São Paulo"
    }
  ],
  "hosts": [
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local",
    "${INTERNAL_IP}",
    "${KUBERNETES_SVC_IP}",
    "127.0.0.1",
    "localhost"
  ]
}
EOF
```

**Saída esperada:** O conteúdo do JSON será exibido no terminal (comportamento do `tee`).

**Explicação dos SANs (hosts):**
- `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`, `kubernetes.default.svc.cluster.local` — nomes DNS internos do Service "kubernetes" no namespace default
- `${INTERNAL_IP}` — IP privado do nó control plane (para conexões diretas)
- `${KUBERNETES_SVC_IP}` (10.96.0.1) — ClusterIP do Service "kubernetes" (primeiro IP do SERVICE_CIDR)
- `127.0.0.1`, `localhost` — para acesso local (health checks, etcdctl)

Gere o certificado usando cfssl:

```bash
# Gerar o certificado serving do apiserver
cd ${CERT_DIR}
sudo cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  apiserver-csr.json | sudo cfssljson -bare apiserver
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number XXXXX
```

Verifique os arquivos gerados:

```bash
# Verificar certificados gerados
ls -la ${CERT_DIR}/apiserver*
```

**Saída esperada:**
```
-rw-r--r-- 1 root root  xxx Jan  1 00:00 apiserver.pem
-rw------- 1 root root  xxx Jan  1 00:00 apiserver-key.pem
-rw-r--r-- 1 root root  xxx Jan  1 00:00 apiserver.csr
-rw-r--r-- 1 root root  xxx Jan  1 00:00 apiserver-csr.json
```

#### 2.2 Gerar o Certificado de Cliente etcd

Este certificado é usado pelo kube-apiserver para se autenticar ao etcd como cliente:

```bash
# Criar CSR config para o etcd client certificate
cat <<EOF | sudo tee ${CERT_DIR}/apiserver-etcd-client-csr.json
{
  "CN": "kube-apiserver-etcd-client",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "São Paulo",
      "O": "system:masters",
      "OU": "Lab K8s",
      "ST": "São Paulo"
    }
  ]
}
EOF
```

**Saída esperada:** O conteúdo do JSON será exibido no terminal.

```bash
# Gerar o certificado de cliente etcd
sudo cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  apiserver-etcd-client-csr.json | sudo cfssljson -bare apiserver-etcd-client
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number XXXXX
```

#### 2.3 Gerar o Par de Chaves para Service Account

O kube-apiserver usa um par de chaves RSA para assinar (chave privada) e verificar (chave pública) tokens JWT de Service Accounts:

```bash
# Gerar par de chaves para Service Account tokens
sudo openssl genrsa -out ${CERT_DIR}/sa-key.pem 2048
sudo openssl rsa -in ${CERT_DIR}/sa-key.pem -pubout -out ${CERT_DIR}/sa-pub.pem
```

**Saída esperada:**
```
Generating RSA private key, 2048 bit long modulus (2 primes)
...+++++
...+++++
e is 65537 (0x010001)
writing RSA key
```

#### 2.4 Gerar o Certificado de Cliente kubelet

Este certificado é usado pelo apiserver quando precisa se conectar aos kubelets (para operações como `kubectl logs`, `kubectl exec`, `kubectl port-forward`):

```bash
# Criar CSR config para o kubelet client certificate
cat <<EOF | sudo tee ${CERT_DIR}/apiserver-kubelet-client-csr.json
{
  "CN": "kube-apiserver-kubelet-client",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "São Paulo",
      "O": "system:masters",
      "OU": "Lab K8s",
      "ST": "São Paulo"
    }
  ]
}
EOF

# Gerar o certificado
sudo cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  apiserver-kubelet-client-csr.json | sudo cfssljson -bare apiserver-kubelet-client
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number XXXXX
```

#### 2.5 Verificar Todos os Certificados Gerados

Confirme que todos os certificados necessários foram gerados corretamente:

```bash
# Listar todos os certificados do apiserver
ls -la ${CERT_DIR}/apiserver* ${CERT_DIR}/sa-*
```

**Saída esperada:**
```
-rw------- 1 root root 1675 Jan  1 00:00 /etc/kubernetes/pki/apiserver-etcd-client-key.pem
-rw-r--r-- 1 root root 1363 Jan  1 00:00 /etc/kubernetes/pki/apiserver-etcd-client.pem
-rw------- 1 root root 1675 Jan  1 00:00 /etc/kubernetes/pki/apiserver-key.pem
-rw-r--r-- 1 root root 1521 Jan  1 00:00 /etc/kubernetes/pki/apiserver.pem
-rw------- 1 root root 1675 Jan  1 00:00 /etc/kubernetes/pki/apiserver-kubelet-client-key.pem
-rw-r--r-- 1 root root 1363 Jan  1 00:00 /etc/kubernetes/pki/apiserver-kubelet-client.pem
-rw------- 1 root root 1679 Jan  1 00:00 /etc/kubernetes/pki/sa-key.pem
-rw-r--r-- 1 root root  451 Jan  1 00:00 /etc/kubernetes/pki/sa-pub.pem
```

Verifique o conteúdo do certificado serving do apiserver:

```bash
# Inspecionar o certificado serving do apiserver
sudo openssl x509 -in ${CERT_DIR}/apiserver.pem -text -noout | grep -A 1 "Subject:"
sudo openssl x509 -in ${CERT_DIR}/apiserver.pem -text -noout | grep -A 10 "Subject Alternative Name"
```

**Saída esperada:**
```
        Subject: C = BR, ST = São Paulo, L = São Paulo, O = Kubernetes, OU = Lab K8s, CN = kube-apiserver
--
            X509v3 Subject Alternative Name:
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster, DNS:kubernetes.default.svc.cluster.local, IP Address:10.0.1.x, IP Address:10.96.0.1, IP Address:127.0.0.1
```

### 3. Baixar e Instalar o kube-apiserver

Baixe o binário do kube-apiserver da versão 1.29.0 do repositório oficial do Kubernetes:

```bash
# Definir a versão do Kubernetes
K8S_VERSION="1.29.0"

# Baixar o binário do kube-apiserver
wget -q --show-progress \
  "https://dl.k8s.io/v${K8S_VERSION}/bin/linux/amd64/kube-apiserver"
```

**Saída esperada:**
```
kube-apiserver       100%[===================>] 117.2M  15.3MB/s    in 7.7s
```

Instale o binário no PATH do sistema:

```bash
# Tornar executável e mover para /usr/local/bin
chmod +x kube-apiserver
sudo mv kube-apiserver /usr/local/bin/

# Verificar a instalação
kube-apiserver --version
```

**Saída esperada:**
```
Kubernetes v1.29.0
```

### 4. Criar Diretórios Necessários

Crie os diretórios que o kube-apiserver precisa para logs e configurações:

```bash
# Criar diretório para logs de auditoria (opcional, mas recomendado)
sudo mkdir -p /var/log/kubernetes

# Criar diretório para encryption config (se necessário no futuro)
sudo mkdir -p /etc/kubernetes/config
```

**Saída esperada:** Nenhuma saída indica sucesso.

### 5. Criar o Arquivo de Serviço systemd

Crie o unit file do systemd para gerenciar o kube-apiserver como um serviço. Este é o arquivo mais importante — cada flag configura um aspecto do comportamento do apiserver:

```bash
# Obter o IP interno (se não definido anteriormente)
INTERNAL_IP=$(hostname -I | awk '{print $1}')

# Criar unit file do kube-apiserver
cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
After=etcd.service
Requires=etcd.service

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --authorization-mode=Node,RBAC \\
  --client-ca-file=/etc/kubernetes/pki/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/etc/etcd/pki/ca.pem \\
  --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.pem \\
  --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client-key.pem \\
  --etcd-servers=https://127.0.0.1:2379 \\
  --kubelet-certificate-authority=/etc/kubernetes/pki/ca.pem \\
  --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.pem \\
  --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client-key.pem \\
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \\
  --service-account-key-file=/etc/kubernetes/pki/sa-pub.pem \\
  --service-account-signing-key-file=/etc/kubernetes/pki/sa-key.pem \\
  --service-cluster-ip-range=10.96.0.0/12 \\
  --tls-cert-file=/etc/kubernetes/pki/apiserver.pem \\
  --tls-private-key-file=/etc/kubernetes/pki/apiserver-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

**Saída esperada:** O conteúdo do unit file será exibido no terminal (comportamento do `tee`).

### 6. Explicação dos Parâmetros de Configuração

Cada flag do kube-apiserver tem um propósito específico. Entender cada uma é fundamental para troubleshooting e para o exame CKA:

#### Flags de Rede e Identidade

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--advertise-address` | `${INTERNAL_IP}` | IP que o apiserver anuncia para outros componentes se conectarem. Deve ser o IP interno do nó control plane, acessível por todos os nós do cluster. |
| `--service-cluster-ip-range` | `10.96.0.0/12` | Range de IPs virtuais para Services do tipo ClusterIP. O primeiro IP (10.96.0.1) é reservado para o Service "kubernetes". Não deve sobrepor com POD_CIDR ou VPC_CIDR. |
| `--service-node-port-range` | `30000-32767` | Range de portas disponíveis para Services do tipo NodePort. Quando um Service NodePort é criado, o Kubernetes aloca uma porta neste range em todos os nós do cluster. |
| `--allow-privileged` | `true` | Permite que Pods solicitem modo privilegiado (acesso total ao host). Necessário para componentes como kube-proxy e CNI plugins. |
| `--event-ttl` | `1h` | Tempo de vida (TTL) dos eventos no cluster. Eventos mais antigos que este período são automaticamente removidos do etcd para evitar crescimento indefinido do armazenamento. |
| `--runtime-config` | `api/all=true` | Habilita ou desabilita grupos de APIs específicos. O valor `api/all=true` habilita todos os grupos de API disponíveis, incluindo APIs em alpha e beta. |
| `--v` | `2` | Nível de verbosidade dos logs (0=mínimo, 5=debug). Nível 2 é adequado para operação normal. |

#### Flags de Conexão com etcd

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--etcd-servers` | `https://127.0.0.1:2379` | URL(s) do(s) servidor(es) etcd. Usa localhost porque etcd roda no mesmo nó. Em clusters HA, lista múltiplos endpoints separados por vírgula. |
| `--etcd-cafile` | `/etc/etcd/pki/ca.pem` | CA usada para validar o certificado do servidor etcd. Garante que o apiserver está se conectando ao etcd legítimo. |
| `--etcd-certfile` | `/etc/kubernetes/pki/apiserver-etcd-client.pem` | Certificado de cliente que o apiserver apresenta ao etcd para autenticação mTLS. |
| `--etcd-keyfile` | `/etc/kubernetes/pki/apiserver-etcd-client-key.pem` | Chave privada correspondente ao certificado de cliente etcd. |

#### Flags de TLS (Serving)

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--tls-cert-file` | `/etc/kubernetes/pki/apiserver.pem` | Certificado TLS do servidor apiserver. Apresentado aos clientes (kubectl, kubelet, etc.) para autenticação do servidor. Deve conter SANs com todos os nomes/IPs de acesso. |
| `--tls-private-key-file` | `/etc/kubernetes/pki/apiserver-key.pem` | Chave privada correspondente ao certificado serving. Nunca deve ser compartilhada ou ter permissões abertas. |
| `--client-ca-file` | `/etc/kubernetes/pki/ca.pem` | CA usada para validar certificados de clientes. Clientes que apresentam certificados assinados por esta CA são autenticados. O CN do certificado vira o username e o O vira o grupo. |

#### Flags de Comunicação com Kubelet

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--kubelet-certificate-authority` | `/etc/kubernetes/pki/ca.pem` | CA usada para validar o certificado do kubelet quando o apiserver se conecta a ele (para logs, exec, port-forward). |
| `--kubelet-client-certificate` | `/etc/kubernetes/pki/apiserver-kubelet-client.pem` | Certificado que o apiserver apresenta ao kubelet para autenticação. |
| `--kubelet-client-key` | `/etc/kubernetes/pki/apiserver-kubelet-client-key.pem` | Chave privada do certificado de cliente kubelet. |

#### Flags de Service Account

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--service-account-issuer` | `https://kubernetes.default.svc.cluster.local` | Identificador do emissor dos tokens JWT de Service Account. Incluído no campo "iss" do token. |
| `--service-account-key-file` | `/etc/kubernetes/pki/sa-pub.pem` | Chave pública usada para **verificar** tokens JWT de Service Account. Qualquer token assinado pela chave privada correspondente será aceito. |
| `--service-account-signing-key-file` | `/etc/kubernetes/pki/sa-key.pem` | Chave privada usada para **assinar** novos tokens JWT de Service Account. Deve corresponder à chave pública acima. |

#### Flags de Autorização e Admission

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--authorization-mode` | `Node,RBAC` | Modos de autorização habilitados, avaliados em ordem. **Node**: autoriza kubelets a acessar recursos dos seus Pods. **RBAC**: autorização baseada em roles (Roles, ClusterRoles, RoleBindings, ClusterRoleBindings). Se um modo nega, o próximo é consultado. |
| `--enable-admission-plugins` | `NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota` | Lista de admission controllers habilitados. Executados em ordem após autenticação e autorização. Cada um pode mutar ou rejeitar a requisição. |

**Detalhamento dos Admission Controllers habilitados:**

| Plugin | Função |
|--------|--------|
| `NamespaceLifecycle` | Rejeita criação de objetos em namespaces sendo deletados. Previne race conditions durante deleção. |
| `NodeRestriction` | Limita o que kubelets podem modificar — apenas seu próprio Node e Pods agendados nele. Segurança essencial. |
| `LimitRanger` | Aplica limites de recursos padrão (CPU, memória) a containers que não especificam limites. |
| `ServiceAccount` | Injeta automaticamente o token do ServiceAccount default em Pods que não especificam um. |
| `DefaultStorageClass` | Atribui a StorageClass padrão a PersistentVolumeClaims sem classe definida. |
| `ResourceQuota` | Verifica se a criação/atualização de objetos excede as quotas definidas no namespace. |

#### Parâmetros do systemd unit file

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `After=etcd.service` | — | O apiserver só inicia após o etcd estar disponível. Dependência de ordenação. |
| `Requires=etcd.service` | — | Se o etcd falhar, o apiserver também será parado. Dependência forte. |
| `Restart=on-failure` | — | Reinicia automaticamente se o processo falhar (exit code ≠ 0). |
| `RestartSec=5` | — | Aguarda 5 segundos antes de reiniciar após falha. Evita loops de restart rápidos. |
| `LimitNOFILE=65536` | — | Aumenta o limite de file descriptors. O apiserver mantém muitas conexões simultâneas (watches). |

### 7. Iniciar o Serviço kube-apiserver

Recarregue a configuração do systemd e inicie o kube-apiserver:

```bash
# Recarregar configuração do systemd
sudo systemctl daemon-reload

# Habilitar o kube-apiserver para iniciar no boot
sudo systemctl enable kube-apiserver

# Iniciar o serviço kube-apiserver
sudo systemctl start kube-apiserver
```

**Saída esperada:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/kube-apiserver.service → /etc/systemd/system/kube-apiserver.service.
```

Verifique que o serviço está rodando:

```bash
# Verificar status do serviço
sudo systemctl status kube-apiserver
```

**Saída esperada:**
```
● kube-apiserver.service - Kubernetes API Server
     Loaded: loaded (/etc/systemd/system/kube-apiserver.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 5s ago
       Docs: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
   Main PID: 2345 (kube-apiserver)
      Tasks: 12 (limit: 1024)
     Memory: 256.0M
        CPU: 3.5s
     CGroup: /system.slice/kube-apiserver.service
             └─2345 /usr/local/bin/kube-apiserver --advertise-address=10.0.1.x ...
```

**Linhas-chave para confirmar sucesso:**
- `Active: active (running)` — o serviço está rodando
- `enabled` — configurado para iniciar no boot
- Memory ~256M é normal para o apiserver

Aguarde alguns segundos para o apiserver inicializar completamente antes de prosseguir com a verificação.

## Verificação

### 1. Verificar Saúde via /healthz

O endpoint `/healthz` retorna o status geral de saúde do apiserver. Um HTTP 200 indica que todos os subsistemas estão funcionando:

```bash
# Verificar saúde do apiserver via /healthz
curl -k https://127.0.0.1:6443/healthz
```

**Saída esperada:**
```
ok
```

O flag `-k` ignora a validação do certificado TLS (para teste rápido via localhost). Em produção, use o certificado da CA.

Para uma verificação mais detalhada com todos os checks individuais:

```bash
# Verificar saúde detalhada (verbose)
curl -k https://127.0.0.1:6443/healthz?verbose
```

**Saída esperada:**
```
[+]ping ok
[+]log ok
[+]etcd ok
[+]poststarthook/start-kube-apiserver-admission-initializer ok
[+]poststarthook/generic-apiserver-start-informers ok
[+]poststarthook/priority-and-fairness-config-consumer ok
[+]poststarthook/priority-and-fairness-filter ok
[+]poststarthook/storage-object-count-tracker-hook ok
[+]poststarthook/start-apiextensions-informers ok
[+]poststarthook/start-apiextensions-controllers ok
[+]poststarthook/crd-informer-synced ok
[+]poststarthook/start-system-namespaces-controller ok
[+]poststarthook/bootstrap-controller ok
[+]poststarthook/rbac/bootstrap-roles ok
[+]poststarthook/scheduling/bootstrap-system-priority-classes ok
[+]poststarthook/start-cluster-authentication-info-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-garbage-collector ok
healthz check passed
```

**Linhas-chave:**
- `[+]etcd ok` — conexão com etcd está funcionando
- `healthz check passed` — todos os checks passaram

### 2. Verificar Saúde via /livez

O endpoint `/livez` verifica se o apiserver está "vivo" (não travado). Diferente do `/healthz`, foca apenas na capacidade de responder:

```bash
# Verificar liveness do apiserver
curl -k https://127.0.0.1:6443/livez
```

**Saída esperada:**
```
ok
```

### 3. Verificar Saúde via /readyz

O endpoint `/readyz` verifica se o apiserver está pronto para receber tráfego (todos os informers sincronizados):

```bash
# Verificar readiness do apiserver
curl -k https://127.0.0.1:6443/readyz
```

**Saída esperada:**
```
ok
```

### 4. Verificar Acesso à API com Certificado de Cliente

Teste o acesso autenticado usando o certificado de admin:

```bash
# Verificar versão da API usando certificado de cliente
curl --cacert /etc/kubernetes/pki/ca.pem \
  --cert /etc/kubernetes/pki/admin.pem \
  --key /etc/kubernetes/pki/admin-key.pem \
  https://${INTERNAL_IP}:6443/version
```

**Saída esperada:**
```json
{
  "major": "1",
  "minor": "29",
  "gitVersion": "v1.29.0",
  "gitCommit": "3f7a50f38688eb332e2a1b013678c6435d539ae6",
  "gitTreeState": "clean",
  "buildDate": "2023-12-13T08:45:04Z",
  "goVersion": "go1.21.5",
  "compiler": "gc",
  "platform": "linux/amd64"
}
```

### 5. Listar API Resources com kubectl

Configure o kubectl temporariamente para acessar o apiserver e listar os recursos disponíveis:

```bash
# Configurar kubectl para usar o apiserver local
kubectl --server=https://127.0.0.1:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.pem \
  --client-certificate=/etc/kubernetes/pki/admin.pem \
  --client-key=/etc/kubernetes/pki/admin-key.pem \
  api-resources --sort-by=name | head -30
```

**Saída esperada:**
```
NAME                              SHORTNAMES   APIVERSION                        NAMESPACED   KIND
apiservices                                    apiregistration.k8s.io/v1         false        APIService
bindings                                       v1                                true         Binding
clusterrolebindings                            rbac.authorization.k8s.io/v1      false        ClusterRoleBinding
clusterroles                                   rbac.authorization.k8s.io/v1      false        ClusterRole
componentstatuses                 cs           v1                                false        ComponentStatus
configmaps                        cm           v1                                true         ConfigMap
endpoints                         ep           v1                                true         Endpoints
events                            ev           v1                                true         Event
limitranges                       limits       v1                                true         LimitRange
namespaces                        ns           v1                                false        Namespace
nodes                             no           v1                                false        Node
...
```

Isso confirma que o apiserver está respondendo e expondo todos os recursos da API Kubernetes.

### 6. Verificar Namespaces Criados Automaticamente

O apiserver cria automaticamente alguns namespaces ao iniciar pela primeira vez:

```bash
# Listar namespaces
kubectl --server=https://127.0.0.1:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.pem \
  --client-certificate=/etc/kubernetes/pki/admin.pem \
  --client-key=/etc/kubernetes/pki/admin-key.pem \
  get namespaces
```

**Saída esperada:**
```
NAME              STATUS   AGE
default           Active   1m
kube-node-lease   Active   1m
kube-public       Active   1m
kube-system       Active   1m
```

**Explicação dos namespaces:**
- `default` — namespace padrão para objetos sem namespace especificado
- `kube-node-lease` — contém Lease objects para heartbeat dos nós
- `kube-public` — dados públicos acessíveis sem autenticação (cluster-info)
- `kube-system` — componentes do sistema Kubernetes (CoreDNS, kube-proxy, etc.)

### 7. Verificar Conexão com etcd

Confirme que o apiserver está se comunicando com o etcd verificando as chaves criadas:

```bash
# Verificar que o apiserver criou objetos no etcd
sudo ETCDCTL_API=3 etcdctl get /registry --prefix --keys-only --limit=10 \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada:**
```
/registry/apiregistration.k8s.io/apiservices/v1.
/registry/apiregistration.k8s.io/apiservices/v1.admissionregistration.k8s.io
/registry/apiregistration.k8s.io/apiservices/v1.apps
/registry/clusterrolebindings/cluster-admin
/registry/clusterroles/cluster-admin
/registry/namespaces/default
/registry/namespaces/kube-node-lease
/registry/namespaces/kube-public
/registry/namespaces/kube-system
/registry/serviceaccounts/default/default
```

Isso confirma que o apiserver está persistindo objetos no etcd corretamente.

## Troubleshooting

### Problema 1: kube-apiserver não inicia — "bind: address already in use"

**Sintoma:**
```
listen tcp 10.0.1.x:6443: bind: address already in use
```

ou nos logs do journalctl:
```
E0101 00:00:00.000000    2345 run.go:74] "command failed" err="failed to create listener: failed to listen on 10.0.1.x:6443: listen tcp 10.0.1.x:6443: bind: address already in use"
```

**Causa provável:** Outra instância do kube-apiserver ou outro processo está usando a porta 6443.

**Resolução:**

```bash
# Identificar o processo usando a porta 6443
sudo ss -tlnp | grep 6443

# Se for uma instância antiga do apiserver, mate o processo
sudo kill $(sudo ss -tlnp | grep 6443 | awk '{print $NF}' | grep -oP 'pid=\K[0-9]+')

# Ou pare qualquer serviço existente
sudo systemctl stop kube-apiserver
sudo killall kube-apiserver 2>/dev/null

# Aguardar a porta ser liberada
sleep 2

# Reiniciar o serviço
sudo systemctl start kube-apiserver

# Verificar status
sudo systemctl status kube-apiserver
```

### Problema 2: kube-apiserver não inicia — "connection refused" ao etcd

**Sintoma:**
```
E0101 00:00:00.000000    2345 controller.go:152] Unable to remove old endpoints from kubernetes service: StorageError: key not found, Code: 1
```

ou:
```
connection error: desc = "transport: Error while dialing: dial tcp 127.0.0.1:2379: connect: connection refused"
```

**Causa provável:** O etcd não está rodando ou não está acessível na URL configurada.

**Resolução:**

```bash
# Verificar se o etcd está rodando
sudo systemctl status etcd

# Se não estiver rodando, iniciar
sudo systemctl start etcd

# Verificar que o etcd está escutando na porta 2379
sudo ss -tlnp | grep 2379

# Testar conectividade com o etcd
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem

# Após confirmar que o etcd está saudável, reiniciar o apiserver
sudo systemctl restart kube-apiserver
```

### Problema 3: kube-apiserver não inicia — "tls: failed to find any PEM data"

**Sintoma:**
```
E0101 00:00:00.000000    2345 secure_serving.go:200] "Failed to load TLS cert" err="tls: failed to find any PEM data in certificate input"
```

ou:
```
unable to load server certificate: tls: failed to find any PEM data in certificate input
```

**Causa provável:** O caminho do certificado TLS está incorreto, o arquivo está vazio, ou o formato não é PEM válido.

**Resolução:**

```bash
# Verificar que os arquivos de certificado existem e não estão vazios
ls -la /etc/kubernetes/pki/apiserver.pem /etc/kubernetes/pki/apiserver-key.pem

# Verificar que o arquivo contém dados PEM válidos
head -1 /etc/kubernetes/pki/apiserver.pem
# Deve mostrar: -----BEGIN CERTIFICATE-----

head -1 /etc/kubernetes/pki/apiserver-key.pem
# Deve mostrar: -----BEGIN RSA PRIVATE KEY-----

# Verificar que o certificado é válido
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.pem -text -noout | head -5

# Verificar que a chave corresponde ao certificado
CERT_MD5=$(sudo openssl x509 -noout -modulus -in /etc/kubernetes/pki/apiserver.pem | openssl md5)
KEY_MD5=$(sudo openssl rsa -noout -modulus -in /etc/kubernetes/pki/apiserver-key.pem | openssl md5)
echo "Cert: ${CERT_MD5}"
echo "Key:  ${KEY_MD5}"
# Ambos devem ser iguais

# Se o certificado estiver corrompido, regenere-o (voltar ao passo 2 deste módulo)
# Após corrigir, reiniciar:
sudo systemctl restart kube-apiserver
```

### Problema 4: kube-apiserver não inicia — "etcd client certificate" inválido

**Sintoma:**
```
E0101 00:00:00.000000    2345 controller.go:152] Unable to perform initial IP allocation check: unable to refresh the service IP block: StorageError: key not found
```

ou nos logs do etcd:
```
embed: rejected connection from "127.0.0.1:xxxxx" (error "tls: certificate required", ServerName "")
```

**Causa provável:** O certificado de cliente etcd (`apiserver-etcd-client.pem`) não é válido, não foi assinado pela CA do etcd, ou os caminhos estão incorretos.

**Resolução:**

```bash
# Verificar que o certificado de cliente etcd existe
ls -la /etc/kubernetes/pki/apiserver-etcd-client.pem /etc/kubernetes/pki/apiserver-etcd-client-key.pem

# Verificar que foi assinado pela CA do etcd
openssl verify -CAfile /etc/etcd/pki/ca.pem /etc/kubernetes/pki/apiserver-etcd-client.pem

# Saída esperada: /etc/kubernetes/pki/apiserver-etcd-client.pem: OK

# Se a verificação falhar, o certificado foi assinado por outra CA
# Regenere o certificado usando a CA correta do etcd

# Testar conexão manual com o etcd usando o certificado do apiserver
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/kubernetes/pki/apiserver-etcd-client.pem \
  --key=/etc/kubernetes/pki/apiserver-etcd-client-key.pem

# Após corrigir, reiniciar:
sudo systemctl restart kube-apiserver
```

### Problema 5: /healthz retorna "failed" — etcd check falha

**Sintoma:**
```bash
curl -k https://127.0.0.1:6443/healthz?verbose
```
Retorna:
```
[+]ping ok
[+]log ok
[-]etcd failed: reason withheld
...
healthz check failed
```

**Causa provável:** O apiserver perdeu a conexão com o etcd após iniciar. O etcd pode ter caído, reiniciado, ou há um problema de rede/certificado.

**Resolução:**

```bash
# Verificar status do etcd
sudo systemctl status etcd

# Verificar logs recentes do etcd
sudo journalctl -u etcd --no-pager -l --since "5 minutes ago" | tail -20

# Verificar saúde do etcd diretamente
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem

# Se o etcd estiver parado, reiniciar
sudo systemctl restart etcd

# Aguardar o etcd ficar saudável
sleep 5

# Verificar novamente o healthz do apiserver
curl -k https://127.0.0.1:6443/healthz

# Se persistir, reiniciar o apiserver
sudo systemctl restart kube-apiserver
```

### Problema 6: /healthz retorna HTTP 403 — acesso negado

**Sintoma:**
```bash
curl -k https://127.0.0.1:6443/healthz
```
Retorna:
```json
{
  "kind": "Status",
  "apiVersion": "v1",
  "status": "Failure",
  "message": "forbidden: User \"system:anonymous\" cannot get path \"/healthz\"",
  "reason": "Forbidden",
  "code": 403
}
```

**Causa provável:** O endpoint `/healthz` normalmente é acessível sem autenticação. Se retorna 403, pode haver um admission controller ou configuração de RBAC bloqueando acesso anônimo.

**Resolução:**

```bash
# Verificar se o endpoint está acessível com certificado de admin
curl --cacert /etc/kubernetes/pki/ca.pem \
  --cert /etc/kubernetes/pki/admin.pem \
  --key /etc/kubernetes/pki/admin-key.pem \
  https://127.0.0.1:6443/healthz

# Se funcionar com certificado, o problema é com acesso anônimo
# Verificar logs do apiserver para entender a rejeição
sudo journalctl -u kube-apiserver --no-pager -l --since "2 minutes ago" | grep -i "forbidden\|anonymous"

# Normalmente /healthz permite acesso anônimo por padrão no K8s 1.29
# Se o problema persistir, verifique se não há webhook de autorização bloqueando
```

### Problema 7: kube-apiserver não inicia — "service-account-signing-key-file" erro

**Sintoma:**
```
E0101 00:00:00.000000    2345 run.go:74] "command failed" err="service-account-signing-key-file and service-account-key-file must be specified together"
```

ou:
```
unable to load service account key file: open /etc/kubernetes/pki/sa-key.pem: no such file or directory
```

**Causa provável:** O par de chaves do Service Account não foi gerado ou os caminhos estão incorretos.

**Resolução:**

```bash
# Verificar que os arquivos SA existem
ls -la /etc/kubernetes/pki/sa-key.pem /etc/kubernetes/pki/sa-pub.pem

# Se não existirem, gerar novamente
sudo openssl genrsa -out /etc/kubernetes/pki/sa-key.pem 2048
sudo openssl rsa -in /etc/kubernetes/pki/sa-key.pem -pubout -out /etc/kubernetes/pki/sa-pub.pem

# Verificar permissões (chave privada deve ser restrita)
sudo chmod 600 /etc/kubernetes/pki/sa-key.pem
sudo chmod 644 /etc/kubernetes/pki/sa-pub.pem

# Reiniciar o apiserver
sudo systemctl restart kube-apiserver
```

### Problema 8: kubectl retorna "Unable to connect to the server"

**Sintoma:**
```
Unable to connect to the server: dial tcp 10.0.1.x:6443: connect: connection refused
```

ou:
```
Unable to connect to the server: net/http: TLS handshake timeout
```

**Causa provável:** O apiserver não está rodando, não está escutando na porta 6443, ou há um problema de rede/firewall.

**Resolução:**

```bash
# Verificar se o apiserver está rodando
sudo systemctl status kube-apiserver

# Verificar se está escutando na porta 6443
sudo ss -tlnp | grep 6443

# Se não estiver escutando, verificar logs de erro
sudo journalctl -u kube-apiserver --no-pager -l --since "5 minutes ago" | tail -30

# Verificar se o security group permite acesso na porta 6443
# (verificar no console AWS ou via AWS CLI)

# Se o apiserver está rodando mas não responde, pode ser um problema de TLS
# Testar com curl ignorando TLS
curl -k https://127.0.0.1:6443/healthz

# Se funcionar via localhost mas não via IP externo, é problema de firewall/security group
# Se não funcionar nem via localhost, o apiserver tem um problema interno

# Reiniciar o apiserver
sudo systemctl restart kube-apiserver
```

### Dicas Gerais de Troubleshooting

Para qualquer problema com o kube-apiserver, os logs do journalctl são a primeira fonte de informação:

```bash
# Ver logs em tempo real
sudo journalctl -u kube-apiserver -f

# Ver últimas 50 linhas de log
sudo journalctl -u kube-apiserver --no-pager -l -n 50

# Filtrar por erros
sudo journalctl -u kube-apiserver --no-pager -l | grep -i "error\|fatal\|failed"

# Ver logs desde o último restart
sudo journalctl -u kube-apiserver --no-pager -l --since "$(systemctl show kube-apiserver --property=ActiveEnterTimestamp | cut -d= -f2)"
```

