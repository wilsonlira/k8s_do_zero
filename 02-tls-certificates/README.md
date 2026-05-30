# Módulo 02 — Certificados TLS

## Objetivo

Gerar e configurar todos os certificados TLS necessários para a comunicação segura entre os componentes do cluster Kubernetes. Ao final deste módulo, você terá:

- Compreensão do modelo PKI (Public Key Infrastructure) usado pelo Kubernetes
- Uma Autoridade Certificadora (CA) própria para o cluster
- Certificados individuais para cada componente (kube-apiserver, kubelet, kube-proxy, etcd, service accounts)
- Conhecimento sobre rotação, expiração e renovação de certificados
- Certificados distribuídos nos nós corretos com permissões adequadas

## Teoria

### Modelo PKI no Kubernetes

O Kubernetes utiliza **PKI (Public Key Infrastructure)** para garantir que toda comunicação entre componentes seja autenticada e criptografada. Isso significa que:

1. **Cada componente possui uma identidade** — representada por um certificado digital
2. **Toda comunicação é criptografada** — usando TLS (Transport Layer Security)
3. **Autenticação mútua (mTLS)** — tanto o cliente quanto o servidor verificam a identidade um do outro

### Cadeia de Confiança (Trust Chain)

A cadeia de confiança no Kubernetes segue uma hierarquia simples:

```
┌─────────────────────────────────────────────────┐
│           Certificate Authority (CA)             │
│         (Raiz da cadeia de confiança)            │
└─────────────────────┬───────────────────────────┘
                      │ Assina
          ┌───────────┼───────────────┐
          │           │               │
          ▼           ▼               ▼
┌─────────────┐ ┌──────────┐ ┌──────────────┐
│  Cert API   │ │Cert etcd │ │ Cert kubelet │ ...
│  Server     │ │          │ │              │
└─────────────┘ └──────────┘ └──────────────┘
```

**Como funciona:**

- A **CA (Certificate Authority)** é a entidade raiz que assina todos os outros certificados
- Cada componente confia na CA — se um certificado foi assinado pela CA, ele é considerado válido
- Quando o kubelet se conecta ao kube-apiserver, ambos apresentam seus certificados
- Cada lado verifica se o certificado do outro foi assinado pela mesma CA

### Tipos de Certificados

| Tipo | Uso | Exemplo |
|------|-----|---------|
| **Certificado de Servidor** | Prova a identidade do servidor para clientes | kube-apiserver serving cert |
| **Certificado de Cliente** | Prova a identidade do cliente para o servidor | kubelet → apiserver |
| **Certificado CA** | Assina e valida outros certificados | ca.pem |

### Campos Importantes de um Certificado

- **CN (Common Name)**: Identifica o "dono" do certificado. No Kubernetes, é usado como nome de usuário para autenticação
- **O (Organization)**: Identifica o grupo ao qual o dono pertence. No Kubernetes, mapeia para grupos RBAC
- **SANs (Subject Alternative Names)**: Lista de nomes DNS e IPs adicionais para os quais o certificado é válido. Essencial para certificados de servidor que são acessados por múltiplos nomes/IPs

### Autenticação por Certificado no Kubernetes

Quando um componente se conecta ao kube-apiserver usando um certificado de cliente:

1. O apiserver verifica se o certificado foi assinado pela CA confiável
2. Extrai o **CN** como nome de usuário (ex: `system:kube-controller-manager`)
3. Extrai o **O** como grupo (ex: `system:masters`)
4. Aplica regras RBAC baseadas no usuário e grupo identificados

### Mapa de Certificados do Cluster

| Certificado | CN | O | SANs | Usado por |
|---|---|---|---|---|
| CA | kubernetes-ca | kubernetes | — | Todos (validação) |
| kube-apiserver | kube-apiserver | — | kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local, IP do control plane, 10.96.0.1 | kube-apiserver |
| etcd-server | etcd-server | — | IP do control plane, localhost, 127.0.0.1 | etcd |
| kubelet | system:node:\<hostname\> | system:nodes | IP do nó, hostname | kubelet |
| kube-proxy | system:kube-proxy | system:node-proxier | — | kube-proxy |
| kube-controller-manager | system:kube-controller-manager | system:kube-controller-manager | — | kube-controller-manager |
| kube-scheduler | system:kube-scheduler | system:kube-scheduler | — | kube-scheduler |
| admin | admin | system:masters | — | kubectl (admin) |
| service-accounts | service-accounts | kubernetes | — | kube-apiserver (assinatura de tokens) |

### Propósito de Cada Certificado

| Certificado | Propósito |
|---|---|
| **CA** | Raiz de confiança. Assina todos os outros certificados. Distribuído para todos os nós para validação. |
| **kube-apiserver** | Certificado de servidor do API server. Permite que clientes (kubectl, kubelet, etc.) verifiquem a identidade do apiserver via TLS. |
| **etcd-server** | Certificado de servidor do etcd. O apiserver usa para verificar a identidade do etcd ao conectar como cliente. |
| **kubelet** | Certificado de cliente e servidor do kubelet. Usado para autenticar o kubelet no apiserver (cliente) e para o apiserver se conectar ao kubelet (servidor). |
| **kube-proxy** | Certificado de cliente do kube-proxy. Usado para autenticar o kube-proxy no apiserver. |
| **kube-controller-manager** | Certificado de cliente do controller-manager. Usado para autenticar no apiserver. |
| **kube-scheduler** | Certificado de cliente do scheduler. Usado para autenticar no apiserver. |
| **admin** | Certificado de cliente administrativo. Usado pelo kubectl para acesso total ao cluster (grupo system:masters). |
| **service-accounts** | Par de chaves para assinatura de tokens de Service Account. O apiserver usa a chave privada para assinar tokens e a pública para validá-los. |

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 00 — Pré-requisitos](../00-prerequisites/) — ferramentas openssl e cfssl instaladas
- [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/) — instâncias EC2 provisionadas com IPs conhecidos

Você precisará dos seguintes dados do módulo anterior:

- IP público e privado do nó Control Plane (`CONTROL_PLANE_IP`)
- IP público e privado do nó Worker (`WORKER_NODE_IP`)
- Acesso SSH configurado para ambos os nós

## Comandos Passo a Passo

> **Nota**: Todos os comandos desta seção devem ser executados na máquina local (não nas instâncias EC2). Os certificados serão gerados localmente e depois distribuídos para os nós.

### 1. Preparar Diretório de Trabalho

Crie um diretório dedicado para armazenar todos os certificados e chaves gerados:

```bash
# Criar diretório para certificados
mkdir -p configs/pki
cd configs/pki
```

**Saída esperada:** Nenhuma saída indica sucesso.

### 2. Configurar Variáveis de Ambiente

Carregue as variáveis do projeto e defina os IPs dos nós. Substitua os valores de IP pelos IPs reais das suas instâncias EC2:

```bash
# Carregar variáveis do projeto
source ../../variables.env

# Definir IPs das instâncias (substitua pelos IPs reais)
export CONTROL_PLANE_IP="<IP_PRIVADO_CONTROL_PLANE>"
export CONTROL_PLANE_PUBLIC_IP="<IP_PUBLICO_CONTROL_PLANE>"
export WORKER_NODE_IP="<IP_PRIVADO_WORKER>"
export WORKER_NODE_PUBLIC_IP="<IP_PUBLICO_WORKER>"
```

**Saída esperada:** Nenhuma saída indica sucesso.

### 3. Gerar a Autoridade Certificadora (CA)

A CA é a raiz de confiança do cluster. Todos os outros certificados serão assinados por ela. Usamos RSA com mínimo de 2048 bits e validade de 10 anos (3650 dias).

#### 3.1 Criar configuração da CA para o cfssl

O arquivo `ca-config.json` define os perfis de assinatura que a CA usará para emitir certificados:

```bash
# Criar arquivo de configuração da CA
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ],
        "expiry": "8760h"
      }
    }
  }
}
EOF
```

**Saída esperada:** Nenhuma saída indica sucesso. O arquivo `ca-config.json` será criado.

**Explicação dos campos:**
- `expiry: "8760h"` — validade de 1 ano (365 dias × 24 horas). Para produção, use valores menores.
- `profiles.kubernetes` — perfil usado para certificados do cluster
- `usages` — define os usos permitidos do certificado:
  - `signing` — pode assinar dados
  - `key encipherment` — pode criptografar chaves de sessão
  - `server auth` — válido como certificado de servidor TLS
  - `client auth` — válido como certificado de cliente TLS

#### 3.2 Criar CSR (Certificate Signing Request) da CA

O arquivo `ca-csr.json` define os dados de identidade da CA:

```bash
# Criar CSR da CA
cat > ca-csr.json <<EOF
{
  "CN": "kubernetes-ca",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "kubernetes",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Saída esperada:** Nenhuma saída indica sucesso.

**Explicação dos campos:**
- `CN: "kubernetes-ca"` — Common Name que identifica esta CA
- `key.algo: "rsa"` — algoritmo RSA para a chave
- `key.size: 2048` — tamanho mínimo de 2048 bits (segurança adequada para labs; produção usa 4096)
- `names` — informações organizacionais (país, estado, cidade, organização, unidade)

#### 3.3 Gerar o certificado e chave da CA

Este comando gera o par de chaves (pública e privada) e o certificado auto-assinado da CA:

```bash
# Gerar CA
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generating a new CA key and certificate from CSR
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:**
- `ca.pem` — Certificado público da CA (distribuído para todos os nós)
- `ca-key.pem` — Chave privada da CA (manter segura, usada apenas para assinar)
- `ca.csr` — Certificate Signing Request (pode ser descartado)

### 4. Gerar Certificado do Admin (kubectl)

O certificado admin é usado pelo kubectl para autenticação no cluster com privilégios totais. O grupo `system:masters` concede acesso administrativo via RBAC.

```bash
# Criar CSR do admin
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "system:masters",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "admin"` — nome de usuário que será reconhecido pelo RBAC
- `O: "system:masters"` — grupo com permissões administrativas totais no cluster

```bash
# Gerar certificado admin assinado pela CA
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `admin.pem`, `admin-key.pem`, `admin.csr`

### 5. Gerar Certificado do kube-controller-manager

O controller-manager se autentica no apiserver como `system:kube-controller-manager`. Este é um certificado de cliente.

```bash
# Criar CSR do kube-controller-manager
cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "system:kube-controller-manager",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "system:kube-controller-manager"` — identidade reconhecida pelo RBAC do Kubernetes
- `O: "system:kube-controller-manager"` — grupo do controller-manager

```bash
# Gerar certificado do controller-manager
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `kube-controller-manager.pem`, `kube-controller-manager-key.pem`

### 6. Gerar Certificado do kube-scheduler

O scheduler se autentica no apiserver como `system:kube-scheduler`. Este é um certificado de cliente.

```bash
# Criar CSR do kube-scheduler
cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "system:kube-scheduler",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "system:kube-scheduler"` — identidade do scheduler no RBAC
- `O: "system:kube-scheduler"` — grupo do scheduler

```bash
# Gerar certificado do scheduler
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `kube-scheduler.pem`, `kube-scheduler-key.pem`

### 7. Gerar Certificado do kube-proxy

O kube-proxy se autentica no apiserver como `system:kube-proxy`. Este é um certificado de cliente.

```bash
# Criar CSR do kube-proxy
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "system:node-proxier",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "system:kube-proxy"` — identidade do kube-proxy no RBAC
- `O: "system:node-proxier"` — grupo que concede permissões de proxy via ClusterRoleBinding padrão

```bash
# Gerar certificado do kube-proxy
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `kube-proxy.pem`, `kube-proxy-key.pem`

### 8. Gerar Certificado do kubelet (Worker Node)

O kubelet usa um certificado com CN no formato `system:node:<hostname>` e organização `system:nodes`. Isso permite que o Node Authorizer do apiserver identifique e autorize o nó.

```bash
# Criar CSR do kubelet para o worker node
cat > kubelet-worker-01-csr.json <<EOF
{
  "CN": "system:node:k8s-worker-01",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "system:nodes",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "system:node:k8s-worker-01"` — identifica o nó específico. O formato `system:node:<nome>` é obrigatório para o Node Authorizer
- `O: "system:nodes"` — grupo que concede permissões de nó via RBAC

```bash
# Gerar certificado do kubelet com SANs incluindo IP e hostname do worker
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=k8s-worker-01,${WORKER_NODE_IP},${WORKER_NODE_PUBLIC_IP} \
  -profile=kubernetes \
  kubelet-worker-01-csr.json | cfssljson -bare kubelet-worker-01
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `kubelet-worker-01.pem`, `kubelet-worker-01-key.pem`

> **Nota**: Se você tiver múltiplos worker nodes, repita este processo para cada nó, alterando o hostname e IPs no CSR e no parâmetro `-hostname`.

### 9. Gerar Certificado do kube-apiserver

O certificado do apiserver é o mais complexo porque precisa incluir todos os nomes e IPs pelos quais o apiserver pode ser acessado (SANs). Se um cliente se conectar usando um nome/IP que não está nos SANs, a conexão TLS falhará.

```bash
# Criar CSR do kube-apiserver
cat > kube-apiserver-csr.json <<EOF
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "kubernetes",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "kube-apiserver"` — identidade do API server
- `O: "kubernetes"` — organização do cluster

O parâmetro `-hostname` define os SANs (Subject Alternative Names) — todos os nomes e IPs válidos para acessar o apiserver:

```bash
# Gerar certificado do apiserver com todos os SANs necessários
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.96.0.1,${CONTROL_PLANE_IP},${CONTROL_PLANE_PUBLIC_IP},127.0.0.1,localhost,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local \
  -profile=kubernetes \
  kube-apiserver-csr.json | cfssljson -bare kube-apiserver
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `kube-apiserver.pem`, `kube-apiserver-key.pem`

**Detalhamento dos SANs:**
- `10.96.0.1` — primeiro IP do Service CIDR (IP do serviço `kubernetes` no namespace default)
- `${CONTROL_PLANE_IP}` — IP privado do nó control plane
- `${CONTROL_PLANE_PUBLIC_IP}` — IP público (para acesso externo via kubectl)
- `127.0.0.1`, `localhost` — acesso local no próprio nó
- `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`, `kubernetes.default.svc.cluster.local` — nomes DNS internos do serviço kubernetes

### 10. Gerar Certificado do etcd

O etcd precisa de um certificado de servidor para aceitar conexões TLS do kube-apiserver. Os SANs incluem os IPs e nomes pelos quais o etcd é acessado.

```bash
# Criar CSR do etcd
cat > etcd-server-csr.json <<EOF
{
  "CN": "etcd-server",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "kubernetes",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "etcd-server"` — identidade do servidor etcd
- Os SANs incluem o IP do control plane (onde o etcd roda) e localhost

```bash
# Gerar certificado do etcd com SANs
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${CONTROL_PLANE_IP},127.0.0.1,localhost \
  -profile=kubernetes \
  etcd-server-csr.json | cfssljson -bare etcd-server
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `etcd-server.pem`, `etcd-server-key.pem`

### 11. Gerar Par de Chaves para Service Accounts

O Kubernetes usa um par de chaves RSA para assinar e validar tokens de Service Account. O kube-apiserver usa a chave privada para assinar tokens, e o kube-controller-manager usa a chave pública para validá-los.

```bash
# Criar CSR para service accounts
cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "kubernetes",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "service-accounts"` — identifica o par de chaves de service accounts
- Este certificado não é usado para autenticação TLS diretamente, mas o par de chaves é usado para assinatura de tokens JWT

```bash
# Gerar par de chaves para service accounts
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `service-account.pem`, `service-account-key.pem`

### 12. Gerar Certificado de Cliente do apiserver para etcd

O kube-apiserver precisa de um certificado de cliente para se autenticar no etcd. Este certificado é apresentado quando o apiserver se conecta ao etcd.

```bash
# Criar CSR do apiserver-etcd-client
cat > apiserver-etcd-client-csr.json <<EOF
{
  "CN": "kube-apiserver-etcd-client",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BR",
      "L": "Sao Paulo",
      "O": "system:masters",
      "OU": "k8s-lab",
      "ST": "SP"
    }
  ]
}
EOF
```

**Explicação:**
- `CN: "kube-apiserver-etcd-client"` — identifica o apiserver como cliente do etcd
- `O: "system:masters"` — grupo com acesso total (o etcd não usa RBAC do Kubernetes, mas mantemos consistência)

```bash
# Gerar certificado de cliente do apiserver para etcd
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  apiserver-etcd-client-csr.json | cfssljson -bare apiserver-etcd-client
```

**Saída esperada:**
```
2024/01/01 00:00:00 [INFO] generate received request
2024/01/01 00:00:00 [INFO] received CSR
2024/01/01 00:00:00 [INFO] generating key: rsa-2048
2024/01/01 00:00:00 [INFO] encoded CSR
2024/01/01 00:00:00 [INFO] signed certificate with serial number ...
```

**Arquivos gerados:** `apiserver-etcd-client.pem`, `apiserver-etcd-client-key.pem`

### 13. Verificar Arquivos Gerados

Após gerar todos os certificados, verifique que todos os arquivos esperados existem:

```bash
# Listar todos os certificados e chaves gerados
ls -la *.pem
```

**Saída esperada:**
```
-rw-r--r-- 1 user user 1350 Jan  1 00:00 admin-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 admin.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 apiserver-etcd-client-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 apiserver-etcd-client.pem
-rw-r--r-- 1 user user 1675 Jan  1 00:00 ca-key.pem
-rw-r--r-- 1 user user 1318 Jan  1 00:00 ca.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 etcd-server-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 etcd-server.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 kube-apiserver-key.pem
-rw-r--r-- 1 user user 1590 Jan  1 00:00 kube-apiserver.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 kube-controller-manager-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 kube-controller-manager.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 kube-proxy-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 kube-proxy.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 kube-scheduler-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 kube-scheduler.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 kubelet-worker-01-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 kubelet-worker-01.pem
-rw-r--r-- 1 user user 1350 Jan  1 00:00 service-account-key.pem
-rw-r--r-- 1 user user 1399 Jan  1 00:00 service-account.pem
```

### 14. Distribuir Certificados para os Nós

Os certificados precisam ser copiados para os nós corretos com as permissões adequadas. Cada componente precisa apenas dos certificados que utiliza.

#### 14.1 Distribuir para o Control Plane

O nó control plane precisa dos certificados de todos os componentes que rodam nele (etcd, apiserver, controller-manager, scheduler):

```bash
# Copiar certificados para o nó control plane
scp -i ~/.ssh/k8s-lab-key.pem \
  ca.pem ca-key.pem \
  kube-apiserver.pem kube-apiserver-key.pem \
  etcd-server.pem etcd-server-key.pem \
  apiserver-etcd-client.pem apiserver-etcd-client-key.pem \
  service-account.pem service-account-key.pem \
  kube-controller-manager.pem kube-controller-manager-key.pem \
  kube-scheduler.pem kube-scheduler-key.pem \
  admin.pem admin-key.pem \
  ubuntu@${CONTROL_PLANE_PUBLIC_IP}:~/
```

**Saída esperada:**
```
ca.pem                              100% 1318     1.3KB/s   00:00
ca-key.pem                          100% 1675     1.7KB/s   00:00
kube-apiserver.pem                  100% 1590     1.6KB/s   00:00
...
```

Após copiar, organize os certificados no diretório padrão do Kubernetes:

```bash
# Conectar no control plane e organizar certificados
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_PUBLIC_IP} << 'EOF'
# Criar diretório de PKI do Kubernetes
sudo mkdir -p /etc/kubernetes/pki /etc/etcd/pki

# Mover certificados para os diretórios corretos
sudo mv ca.pem ca-key.pem /etc/kubernetes/pki/
sudo mv kube-apiserver.pem kube-apiserver-key.pem /etc/kubernetes/pki/
sudo mv apiserver-etcd-client.pem apiserver-etcd-client-key.pem /etc/kubernetes/pki/
sudo mv service-account.pem service-account-key.pem /etc/kubernetes/pki/
sudo mv kube-controller-manager.pem kube-controller-manager-key.pem /etc/kubernetes/pki/
sudo mv kube-scheduler.pem kube-scheduler-key.pem /etc/kubernetes/pki/
sudo mv admin.pem admin-key.pem /etc/kubernetes/pki/
sudo mv etcd-server.pem etcd-server-key.pem /etc/etcd/pki/

# Copiar CA para o diretório do etcd também
sudo cp /etc/kubernetes/pki/ca.pem /etc/etcd/pki/

# Definir permissões corretas
sudo chmod 600 /etc/kubernetes/pki/*-key.pem
sudo chmod 644 /etc/kubernetes/pki/*.pem
sudo chmod 600 /etc/etcd/pki/*-key.pem
sudo chmod 644 /etc/etcd/pki/*.pem
sudo chown root:root /etc/kubernetes/pki/*
sudo chown root:root /etc/etcd/pki/*
EOF
```

**Saída esperada:** Nenhuma saída indica sucesso.

#### 14.2 Distribuir para o Worker Node

O worker node precisa apenas do certificado CA (para validação), do certificado do kubelet e do kube-proxy:

```bash
# Copiar certificados para o worker node
scp -i ~/.ssh/k8s-lab-key.pem \
  ca.pem \
  kubelet-worker-01.pem kubelet-worker-01-key.pem \
  kube-proxy.pem kube-proxy-key.pem \
  ubuntu@${WORKER_NODE_PUBLIC_IP}:~/
```

**Saída esperada:**
```
ca.pem                              100% 1318     1.3KB/s   00:00
kubelet-worker-01.pem               100% 1399     1.4KB/s   00:00
kubelet-worker-01-key.pem           100% 1350     1.4KB/s   00:00
kube-proxy.pem                      100% 1399     1.4KB/s   00:00
kube-proxy-key.pem                  100% 1350     1.4KB/s   00:00
```

Organize os certificados no worker node:

```bash
# Conectar no worker node e organizar certificados
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${WORKER_NODE_PUBLIC_IP} << 'EOF'
# Criar diretório de PKI do Kubernetes
sudo mkdir -p /etc/kubernetes/pki

# Mover certificados para o diretório correto
sudo mv ca.pem /etc/kubernetes/pki/
sudo mv kubelet-worker-01.pem /etc/kubernetes/pki/kubelet.pem
sudo mv kubelet-worker-01-key.pem /etc/kubernetes/pki/kubelet-key.pem
sudo mv kube-proxy.pem kube-proxy-key.pem /etc/kubernetes/pki/

# Definir permissões corretas
sudo chmod 600 /etc/kubernetes/pki/*-key.pem
sudo chmod 644 /etc/kubernetes/pki/*.pem
sudo chown root:root /etc/kubernetes/pki/*
EOF
```

**Saída esperada:** Nenhuma saída indica sucesso.

#### 14.3 Resumo da Distribuição de Certificados

| Arquivo | Nó | Caminho de Destino | Permissão |
|---|---|---|---|
| `ca.pem` | Control Plane | `/etc/kubernetes/pki/ca.pem` | 644 |
| `ca-key.pem` | Control Plane | `/etc/kubernetes/pki/ca-key.pem` | 600 |
| `kube-apiserver.pem` | Control Plane | `/etc/kubernetes/pki/kube-apiserver.pem` | 644 |
| `kube-apiserver-key.pem` | Control Plane | `/etc/kubernetes/pki/kube-apiserver-key.pem` | 600 |
| `apiserver-etcd-client.pem` | Control Plane | `/etc/kubernetes/pki/apiserver-etcd-client.pem` | 644 |
| `apiserver-etcd-client-key.pem` | Control Plane | `/etc/kubernetes/pki/apiserver-etcd-client-key.pem` | 600 |
| `service-account.pem` | Control Plane | `/etc/kubernetes/pki/service-account.pem` | 644 |
| `service-account-key.pem` | Control Plane | `/etc/kubernetes/pki/service-account-key.pem` | 600 |
| `kube-controller-manager.pem` | Control Plane | `/etc/kubernetes/pki/kube-controller-manager.pem` | 644 |
| `kube-controller-manager-key.pem` | Control Plane | `/etc/kubernetes/pki/kube-controller-manager-key.pem` | 600 |
| `kube-scheduler.pem` | Control Plane | `/etc/kubernetes/pki/kube-scheduler.pem` | 644 |
| `kube-scheduler-key.pem` | Control Plane | `/etc/kubernetes/pki/kube-scheduler-key.pem` | 600 |
| `admin.pem` | Control Plane | `/etc/kubernetes/pki/admin.pem` | 644 |
| `admin-key.pem` | Control Plane | `/etc/kubernetes/pki/admin-key.pem` | 600 |
| `etcd-server.pem` | Control Plane | `/etc/etcd/pki/etcd-server.pem` | 644 |
| `etcd-server-key.pem` | Control Plane | `/etc/etcd/pki/etcd-server-key.pem` | 600 |
| `ca.pem` | Control Plane | `/etc/etcd/pki/ca.pem` | 644 |
| `ca.pem` | Worker Node | `/etc/kubernetes/pki/ca.pem` | 644 |
| `kubelet.pem` | Worker Node | `/etc/kubernetes/pki/kubelet.pem` | 644 |
| `kubelet-key.pem` | Worker Node | `/etc/kubernetes/pki/kubelet-key.pem` | 600 |
| `kube-proxy.pem` | Worker Node | `/etc/kubernetes/pki/kube-proxy.pem` | 644 |
| `kube-proxy-key.pem` | Worker Node | `/etc/kubernetes/pki/kube-proxy-key.pem` | 600 |

**Regras de permissão:**
- Certificados públicos (`.pem`): `644` (leitura para todos, escrita apenas root)
- Chaves privadas (`-key.pem`): `600` (leitura/escrita apenas root)
- Proprietário: `root:root` para todos os arquivos

### 15. Rotação e Monitoramento de Certificados

#### 15.1 Verificar Data de Expiração

Certificados expirados causam falhas imediatas de comunicação entre componentes. Monitore regularmente as datas de expiração:

```bash
# Verificar expiração de um certificado específico
openssl x509 -in /etc/kubernetes/pki/kube-apiserver.pem -noout -dates
```

**Saída esperada:**
```
notBefore=Jan  1 00:00:00 2024 GMT
notAfter=Jan  1 00:00:00 2025 GMT
```

Para verificar todos os certificados de uma vez:

```bash
# Script para verificar expiração de todos os certificados
for cert in /etc/kubernetes/pki/*.pem; do
  if [[ "$cert" != *"-key"* ]]; then
    echo "=== $cert ==="
    openssl x509 -in "$cert" -noout -enddate
    echo ""
  fi
done
```

**Saída esperada:**
```
=== /etc/kubernetes/pki/ca.pem ===
notAfter=Jan  1 00:00:00 2034 GMT

=== /etc/kubernetes/pki/kube-apiserver.pem ===
notAfter=Jan  1 00:00:00 2025 GMT

...
```

#### 15.2 Verificar Certificados Próximos da Expiração

O comando abaixo identifica certificados que expiram nos próximos 30 dias:

```bash
# Verificar certificados que expiram em 30 dias
for cert in /etc/kubernetes/pki/*.pem; do
  if [[ "$cert" != *"-key"* ]]; then
    if openssl x509 -in "$cert" -noout -checkend 2592000 2>/dev/null; then
      echo "✅ OK: $cert"
    else
      echo "⚠️  EXPIRA EM BREVE: $cert"
      openssl x509 -in "$cert" -noout -enddate
    fi
  fi
done
```

**Saída esperada (todos válidos):**
```
✅ OK: /etc/kubernetes/pki/ca.pem
✅ OK: /etc/kubernetes/pki/kube-apiserver.pem
✅ OK: /etc/kubernetes/pki/kube-controller-manager.pem
...
```

#### 15.3 Regenerar Certificados Expirados

Quando um certificado expira, é necessário regenerá-lo usando a mesma CA e reiniciar o componente afetado.

**Processo de renovação (exemplo para kube-apiserver):**

```bash
# 1. Regenerar o certificado (na máquina local, no diretório configs/pki/)
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.96.0.1,${CONTROL_PLANE_IP},${CONTROL_PLANE_PUBLIC_IP},127.0.0.1,localhost,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local \
  -profile=kubernetes \
  kube-apiserver-csr.json | cfssljson -bare kube-apiserver

# 2. Copiar novo certificado para o nó
scp -i ~/.ssh/k8s-lab-key.pem \
  kube-apiserver.pem kube-apiserver-key.pem \
  ubuntu@${CONTROL_PLANE_PUBLIC_IP}:~/

# 3. No control plane: substituir certificado e reiniciar
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_PUBLIC_IP} << 'EOF'
sudo mv ~/kube-apiserver.pem /etc/kubernetes/pki/kube-apiserver.pem
sudo mv ~/kube-apiserver-key.pem /etc/kubernetes/pki/kube-apiserver-key.pem
sudo chmod 644 /etc/kubernetes/pki/kube-apiserver.pem
sudo chmod 600 /etc/kubernetes/pki/kube-apiserver-key.pem
sudo chown root:root /etc/kubernetes/pki/kube-apiserver*
sudo systemctl restart kube-apiserver
EOF
```

**Saída esperada:** Nenhuma saída indica sucesso. Verifique o status do serviço após reiniciar.

#### 15.4 Reiniciar Componentes Após Renovação

Após substituir um certificado, o componente correspondente deve ser reiniciado para carregar o novo certificado:

| Certificado Renovado | Componente a Reiniciar | Comando |
|---|---|---|
| `kube-apiserver.pem` | kube-apiserver | `sudo systemctl restart kube-apiserver` |
| `etcd-server.pem` | etcd | `sudo systemctl restart etcd` |
| `kube-controller-manager.pem` | kube-controller-manager | `sudo systemctl restart kube-controller-manager` |
| `kube-scheduler.pem` | kube-scheduler | `sudo systemctl restart kube-scheduler` |
| `kubelet.pem` | kubelet | `sudo systemctl restart kubelet` |
| `kube-proxy.pem` | kube-proxy | `sudo systemctl restart kube-proxy` |
| `ca.pem` | **Todos os componentes** | Reiniciar todos os serviços em todos os nós |

> **Importante**: Se a CA for renovada, TODOS os certificados assinados por ela devem ser regenerados e TODOS os componentes reiniciados.

## Verificação

Após gerar e distribuir todos os certificados, execute os comandos abaixo para validar que tudo está correto.

### Verificar Certificado da CA

```bash
openssl x509 -in /etc/kubernetes/pki/ca.pem -noout -text | head -20
```

**Saída esperada:**
```
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: ...
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
        Validity
            Not Before: Jan  1 00:00:00 2024 GMT
            Not After : Jan  1 00:00:00 2034 GMT
        Subject: C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

**Linhas-chave:**
- `Issuer` e `Subject` devem ser idênticos (certificado auto-assinado)
- `CN = kubernetes-ca` confirma a identidade da CA
- `Not After` confirma a validade de 10 anos

### Verificar Certificado do kube-apiserver

```bash
openssl x509 -in /etc/kubernetes/pki/kube-apiserver.pem -noout -text | grep -A 1 "Subject:"
```

**Saída esperada:**
```
        Subject: C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kube-apiserver
```

Verificar os SANs (Subject Alternative Names):

```bash
openssl x509 -in /etc/kubernetes/pki/kube-apiserver.pem -noout -text | grep -A 10 "Subject Alternative Name"
```

**Saída esperada:**
```
            X509v3 Subject Alternative Name:
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:localhost, IP Address:10.96.0.1, IP Address:<CONTROL_PLANE_IP>, IP Address:<CONTROL_PLANE_PUBLIC_IP>, IP Address:127.0.0.1
```

**Linhas-chave:** Todos os nomes DNS e IPs listados nos SANs devem estar presentes.

### Verificar Certificado do etcd

```bash
openssl x509 -in /etc/etcd/pki/etcd-server.pem -noout -subject -issuer
```

**Saída esperada:**
```
subject=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = etcd-server
issuer=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

**Linhas-chave:**
- `subject` contém `CN = etcd-server`
- `issuer` contém `CN = kubernetes-ca` (assinado pela CA)

Verificar SANs do etcd:

```bash
openssl x509 -in /etc/etcd/pki/etcd-server.pem -noout -text | grep -A 5 "Subject Alternative Name"
```

**Saída esperada:**
```
            X509v3 Subject Alternative Name:
                DNS:localhost, IP Address:<CONTROL_PLANE_IP>, IP Address:127.0.0.1
```

### Verificar Certificado do kubelet

```bash
openssl x509 -in /etc/kubernetes/pki/kubelet.pem -noout -subject -issuer
```

**Saída esperada:**
```
subject=C = BR, ST = SP, L = Sao Paulo, O = system:nodes, OU = k8s-lab, CN = system:node:k8s-worker-01
issuer=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

**Linhas-chave:**
- `O = system:nodes` — grupo correto para o Node Authorizer
- `CN = system:node:k8s-worker-01` — formato obrigatório para identificação do nó

### Verificar Certificado do kube-proxy

```bash
openssl x509 -in /etc/kubernetes/pki/kube-proxy.pem -noout -subject -issuer
```

**Saída esperada:**
```
subject=C = BR, ST = SP, L = Sao Paulo, O = system:node-proxier, OU = k8s-lab, CN = system:kube-proxy
issuer=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

**Linhas-chave:**
- `O = system:node-proxier` — grupo correto para permissões de proxy
- `CN = system:kube-proxy` — identidade do kube-proxy

### Verificar Certificado do kube-controller-manager

```bash
openssl x509 -in /etc/kubernetes/pki/kube-controller-manager.pem -noout -subject -issuer
```

**Saída esperada:**
```
subject=C = BR, ST = SP, L = Sao Paulo, O = system:kube-controller-manager, OU = k8s-lab, CN = system:kube-controller-manager
issuer=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

### Verificar Certificado do kube-scheduler

```bash
openssl x509 -in /etc/kubernetes/pki/kube-scheduler.pem -noout -subject -issuer
```

**Saída esperada:**
```
subject=C = BR, ST = SP, L = Sao Paulo, O = system:kube-scheduler, OU = k8s-lab, CN = system:kube-scheduler
issuer=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

### Verificar Certificado do Admin

```bash
openssl x509 -in /etc/kubernetes/pki/admin.pem -noout -subject -issuer
```

**Saída esperada:**
```
subject=C = BR, ST = SP, L = Sao Paulo, O = system:masters, OU = k8s-lab, CN = admin
issuer=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

**Linhas-chave:**
- `O = system:masters` — grupo com acesso administrativo total

### Verificar Certificado de Service Accounts

```bash
openssl x509 -in /etc/kubernetes/pki/service-account.pem -noout -subject -issuer
```

**Saída esperada:**
```
subject=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = service-accounts
issuer=C = BR, ST = SP, L = Sao Paulo, O = kubernetes, OU = k8s-lab, CN = kubernetes-ca
```

### Verificar Cadeia de Confiança

Confirme que todos os certificados foram assinados pela CA correta:

```bash
# Verificar que o certificado do apiserver foi assinado pela CA
openssl verify -CAfile /etc/kubernetes/pki/ca.pem /etc/kubernetes/pki/kube-apiserver.pem
```

**Saída esperada:**
```
/etc/kubernetes/pki/kube-apiserver.pem: OK
```

Verifique todos os certificados de uma vez:

```bash
# Verificar cadeia de confiança de todos os certificados
for cert in /etc/kubernetes/pki/*.pem; do
  if [[ "$cert" != *"-key"* ]] && [[ "$cert" != *"ca.pem" ]]; then
    result=$(openssl verify -CAfile /etc/kubernetes/pki/ca.pem "$cert" 2>&1)
    if echo "$result" | grep -q "OK"; then
      echo "✅ $cert"
    else
      echo "❌ $cert: $result"
    fi
  fi
done
```

**Saída esperada:**
```
✅ /etc/kubernetes/pki/admin.pem
✅ /etc/kubernetes/pki/apiserver-etcd-client.pem
✅ /etc/kubernetes/pki/kube-apiserver.pem
✅ /etc/kubernetes/pki/kube-controller-manager.pem
✅ /etc/kubernetes/pki/kube-proxy.pem
✅ /etc/kubernetes/pki/kube-scheduler.pem
✅ /etc/kubernetes/pki/kubelet.pem
✅ /etc/kubernetes/pki/service-account.pem
```

### Verificar Permissões de Arquivos

```bash
# Verificar permissões no control plane
ls -la /etc/kubernetes/pki/
```

**Saída esperada:**
```
-rw------- 1 root root 1675 Jan  1 00:00 ca-key.pem
-rw-r--r-- 1 root root 1318 Jan  1 00:00 ca.pem
-rw------- 1 root root 1350 Jan  1 00:00 kube-apiserver-key.pem
-rw-r--r-- 1 root root 1590 Jan  1 00:00 kube-apiserver.pem
...
```

**Linhas-chave:**
- Chaves privadas (`-key.pem`): permissão `600` (`-rw-------`)
- Certificados públicos (`.pem`): permissão `644` (`-rw-r--r--`)
- Proprietário: `root root`

### Script de Verificação Completa

Execute o script abaixo para validar todos os certificados de uma vez:

```bash
#!/bin/bash
echo "=== Verificação de Certificados TLS do Cluster Kubernetes ==="
echo ""

CA_CERT="/etc/kubernetes/pki/ca.pem"
PKI_DIR="/etc/kubernetes/pki"
ETCD_DIR="/etc/etcd/pki"

# Verificar existência da CA
echo -n "[1/5] CA Certificate....... "
if [ -f "$CA_CERT" ]; then
    expiry=$(openssl x509 -in "$CA_CERT" -noout -enddate | cut -d= -f2)
    echo "✅ OK (expira: $expiry)"
else
    echo "❌ NÃO ENCONTRADO"
fi

# Verificar certificados do control plane
echo ""
echo "[2/5] Certificados Control Plane:"
for cert in kube-apiserver kube-controller-manager kube-scheduler admin service-account apiserver-etcd-client; do
    echo -n "  $cert... "
    cert_file="$PKI_DIR/${cert}.pem"
    key_file="$PKI_DIR/${cert}-key.pem"
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        if openssl verify -CAfile "$CA_CERT" "$cert_file" &>/dev/null; then
            echo "✅ OK"
        else
            echo "❌ FALHA NA VERIFICAÇÃO"
        fi
    else
        echo "❌ ARQUIVO AUSENTE"
    fi
done

# Verificar certificados do etcd
echo ""
echo "[3/5] Certificados etcd:"
echo -n "  etcd-server... "
if [ -f "$ETCD_DIR/etcd-server.pem" ] && [ -f "$ETCD_DIR/etcd-server-key.pem" ]; then
    if openssl verify -CAfile "$CA_CERT" "$ETCD_DIR/etcd-server.pem" &>/dev/null; then
        echo "✅ OK"
    else
        echo "❌ FALHA NA VERIFICAÇÃO"
    fi
else
    echo "❌ ARQUIVO AUSENTE"
fi

# Verificar permissões
echo ""
echo "[4/5] Permissões de chaves privadas:"
all_ok=true
for key in "$PKI_DIR"/*-key.pem "$ETCD_DIR"/*-key.pem; do
    if [ -f "$key" ]; then
        perms=$(stat -c %a "$key" 2>/dev/null || stat -f %Lp "$key" 2>/dev/null)
        if [ "$perms" = "600" ]; then
            echo "  ✅ $key (600)"
        else
            echo "  ❌ $key ($perms - deveria ser 600)"
            all_ok=false
        fi
    fi
done

# Verificar expiração
echo ""
echo "[5/5] Certificados próximos da expiração (30 dias):"
for cert in "$PKI_DIR"/*.pem "$ETCD_DIR"/*.pem; do
    if [ -f "$cert" ] && [[ "$cert" != *"-key"* ]]; then
        if ! openssl x509 -in "$cert" -noout -checkend 2592000 &>/dev/null; then
            echo "  ⚠️  EXPIRA EM BREVE: $cert"
        fi
    fi
done
echo "  (nenhum alerta = todos válidos por mais de 30 dias)"

echo ""
echo "=== Verificação concluída ==="
```

**Saída esperada (todos os certificados válidos):**
```
=== Verificação de Certificados TLS do Cluster Kubernetes ===

[1/5] CA Certificate....... ✅ OK (expira: Jan  1 00:00:00 2034 GMT)

[2/5] Certificados Control Plane:
  kube-apiserver... ✅ OK
  kube-controller-manager... ✅ OK
  kube-scheduler... ✅ OK
  admin... ✅ OK
  service-account... ✅ OK
  apiserver-etcd-client... ✅ OK

[3/5] Certificados etcd:
  etcd-server... ✅ OK

[4/5] Permissões de chaves privadas:
  ✅ /etc/kubernetes/pki/ca-key.pem (600)
  ✅ /etc/kubernetes/pki/kube-apiserver-key.pem (600)
  ...

[5/5] Certificados próximos da expiração (30 dias):
  (nenhum alerta = todos válidos por mais de 30 dias)

=== Verificação concluída ===
```

## Troubleshooting

### Problema: Componente não inicia — "certificate signed by unknown authority"

**Sintoma:**
```
E0101 00:00:00.000000   12345 run.go:74] "command failed" err="open /etc/kubernetes/pki/ca.pem: no such file or directory"
```
ou nos logs do componente:
```
transport: authentication handshake failed: x509: certificate signed by unknown authority
```

**Causa provável:** O certificado CA não foi copiado para o nó, ou o componente está referenciando um caminho incorreto para o CA.

**Resolução:**
```bash
# 1. Verificar se o CA existe no caminho esperado
ls -la /etc/kubernetes/pki/ca.pem

# 2. Se não existir, copiar da máquina local
scp -i ~/.ssh/k8s-lab-key.pem configs/pki/ca.pem ubuntu@<NODE_IP>:~/
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@<NODE_IP> "sudo mv ~/ca.pem /etc/kubernetes/pki/ && sudo chmod 644 /etc/kubernetes/pki/ca.pem"

# 3. Verificar que o certificado do componente foi assinado por esta CA
openssl verify -CAfile /etc/kubernetes/pki/ca.pem /etc/kubernetes/pki/<componente>.pem

# 4. Reiniciar o componente
sudo systemctl restart <componente>
```

---

### Problema: Conexão TLS falha — "certificate is valid for X, not Y"

**Sintoma:**
```
x509: certificate is valid for 10.0.1.10, not 10.0.1.20
```
ou:
```
x509: certificate is valid for kubernetes, not kube-apiserver.example.com
```

**Causa provável:** O cliente está se conectando ao servidor usando um IP ou hostname que não está listado nos SANs (Subject Alternative Names) do certificado do servidor.

**Resolução:**
```bash
# 1. Verificar os SANs do certificado
openssl x509 -in /etc/kubernetes/pki/kube-apiserver.pem -noout -text | grep -A 5 "Subject Alternative Name"

# 2. Identificar qual IP/hostname está sendo usado para conexão
# Verificar no kubeconfig ou na configuração do componente

# 3. Regenerar o certificado incluindo o IP/hostname correto nos SANs
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=<LISTA_COMPLETA_DE_SANS_INCLUINDO_O_NOVO> \
  -profile=kubernetes \
  kube-apiserver-csr.json | cfssljson -bare kube-apiserver

# 4. Redistribuir e reiniciar
scp -i ~/.ssh/k8s-lab-key.pem kube-apiserver.pem kube-apiserver-key.pem ubuntu@<CONTROL_PLANE_IP>:~/
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@<CONTROL_PLANE_IP> << 'EOF'
sudo mv ~/kube-apiserver.pem /etc/kubernetes/pki/
sudo mv ~/kube-apiserver-key.pem /etc/kubernetes/pki/
sudo chmod 644 /etc/kubernetes/pki/kube-apiserver.pem
sudo chmod 600 /etc/kubernetes/pki/kube-apiserver-key.pem
sudo systemctl restart kube-apiserver
EOF
```

---

### Problema: Certificado expirado — "certificate has expired or is not yet valid"

**Sintoma:**
```
x509: certificate has expired or is not yet valid: current time 2025-02-01T10:00:00Z is after 2025-01-01T00:00:00Z
```

**Causa provável:** O certificado ultrapassou sua data de validade (`notAfter`). Certificados com validade de 1 ano (8760h) expiram após esse período.

**Resolução:**
```bash
# 1. Identificar qual certificado expirou
openssl x509 -in /etc/kubernetes/pki/<componente>.pem -noout -dates
# Verificar se "notAfter" está no passado

# 2. Regenerar o certificado (na máquina local)
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  <componente>-csr.json | cfssljson -bare <componente>

# 3. Redistribuir para o nó correto
scp -i ~/.ssh/k8s-lab-key.pem \
  <componente>.pem <componente>-key.pem \
  ubuntu@<NODE_IP>:~/

# 4. Substituir e reiniciar
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@<NODE_IP> << 'EOF'
sudo mv ~/<componente>.pem /etc/kubernetes/pki/
sudo mv ~/<componente>-key.pem /etc/kubernetes/pki/
sudo chmod 644 /etc/kubernetes/pki/<componente>.pem
sudo chmod 600 /etc/kubernetes/pki/<componente>-key.pem
sudo systemctl restart <componente>
EOF

# 5. Verificar que o componente está saudável
sudo systemctl status <componente>
```

---

### Problema: Permissão negada ao ler chave privada

**Sintoma:**
```
error reading key file: open /etc/kubernetes/pki/kube-apiserver-key.pem: permission denied
```

**Causa provável:** A chave privada não tem as permissões corretas ou o serviço está rodando com um usuário que não tem acesso ao arquivo.

**Resolução:**
```bash
# 1. Verificar permissões atuais
ls -la /etc/kubernetes/pki/*-key.pem

# 2. Corrigir permissões (chaves privadas devem ser 600, owner root)
sudo chmod 600 /etc/kubernetes/pki/*-key.pem
sudo chown root:root /etc/kubernetes/pki/*-key.pem

# 3. Verificar que o serviço roda como root (padrão para componentes K8s)
systemctl show <componente> | grep User

# 4. Reiniciar o componente
sudo systemctl restart <componente>
```

---

### Problema: cfssl falha ao gerar certificado — "failed to sign"

**Sintoma:**
```
Error: {"code":5100,"message":"failed to sign the certificate"}
```

**Causa provável:** O arquivo `ca-key.pem` está corrompido, ausente, ou não corresponde ao `ca.pem`. Também pode ocorrer se o `ca-config.json` tem erros de sintaxe JSON.

**Resolução:**
```bash
# 1. Verificar que ca.pem e ca-key.pem formam um par válido
openssl x509 -in ca.pem -noout -modulus | md5sum
openssl rsa -in ca-key.pem -noout -modulus | md5sum
# Os hashes MD5 devem ser IDÊNTICOS

# 2. Verificar sintaxe do ca-config.json
python3 -c "import json; json.load(open('ca-config.json'))" && echo "JSON válido" || echo "JSON inválido"

# 3. Se os hashes não coincidem, regenerar a CA (ATENÇÃO: todos os certificados existentes serão invalidados)
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

> **Atenção**: Regenerar a CA invalida TODOS os certificados existentes. Todos os componentes precisarão de novos certificados.

---

### Problema: kubelet não registra o nó — "Unauthorized"

**Sintoma:**
```
E0101 00:00:00.000000   12345 kubelet.go:2419] "Error getting node" err="node \"k8s-worker-01\" not found"
```
ou:
```
Unauthorized
```

**Causa provável:** O certificado do kubelet tem CN ou O incorretos. O Node Authorizer exige que o CN siga o formato `system:node:<hostname>` e O seja `system:nodes`.

**Resolução:**
```bash
# 1. Verificar CN e O do certificado do kubelet
openssl x509 -in /etc/kubernetes/pki/kubelet.pem -noout -subject
# Deve mostrar: CN = system:node:k8s-worker-01, O = system:nodes

# 2. Se incorreto, regenerar com os valores corretos
# No CSR, garantir:
#   "CN": "system:node:k8s-worker-01"
#   "O": "system:nodes"

# 3. Regenerar e redistribuir
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=k8s-worker-01,${WORKER_NODE_IP},${WORKER_NODE_PUBLIC_IP} \
  -profile=kubernetes \
  kubelet-worker-01-csr.json | cfssljson -bare kubelet-worker-01

# 4. Copiar para o worker e reiniciar kubelet
scp -i ~/.ssh/k8s-lab-key.pem kubelet-worker-01.pem kubelet-worker-01-key.pem ubuntu@${WORKER_NODE_PUBLIC_IP}:~/
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${WORKER_NODE_PUBLIC_IP} << 'EOF'
sudo mv ~/kubelet-worker-01.pem /etc/kubernetes/pki/kubelet.pem
sudo mv ~/kubelet-worker-01-key.pem /etc/kubernetes/pki/kubelet-key.pem
sudo chmod 644 /etc/kubernetes/pki/kubelet.pem
sudo chmod 600 /etc/kubernetes/pki/kubelet-key.pem
sudo systemctl restart kubelet
EOF
```

---

### Problema: etcd recusa conexão do apiserver — "remote error: tls: bad certificate"

**Sintoma (nos logs do kube-apiserver):**
```
connection error: desc = "transport: authentication handshake failed: remote error: tls: bad certificate"
```

**Causa provável:** O certificado de cliente que o apiserver apresenta ao etcd (`apiserver-etcd-client.pem`) não foi assinado pela mesma CA que o etcd confia, ou o certificado está expirado.

**Resolução:**
```bash
# 1. Verificar que o apiserver-etcd-client foi assinado pela mesma CA
openssl verify -CAfile /etc/kubernetes/pki/ca.pem /etc/kubernetes/pki/apiserver-etcd-client.pem

# 2. Verificar que o etcd está usando a mesma CA para validação
# No systemd unit do etcd, verificar a flag --trusted-ca-file

# 3. Verificar validade do certificado
openssl x509 -in /etc/kubernetes/pki/apiserver-etcd-client.pem -noout -dates

# 4. Se necessário, regenerar o certificado de cliente
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  apiserver-etcd-client-csr.json | cfssljson -bare apiserver-etcd-client

# 5. Redistribuir e reiniciar
scp -i ~/.ssh/k8s-lab-key.pem apiserver-etcd-client.pem apiserver-etcd-client-key.pem ubuntu@${CONTROL_PLANE_PUBLIC_IP}:~/
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_PUBLIC_IP} << 'EOF'
sudo mv ~/apiserver-etcd-client.pem /etc/kubernetes/pki/
sudo mv ~/apiserver-etcd-client-key.pem /etc/kubernetes/pki/
sudo chmod 644 /etc/kubernetes/pki/apiserver-etcd-client.pem
sudo chmod 600 /etc/kubernetes/pki/apiserver-etcd-client-key.pem
sudo systemctl restart kube-apiserver
EOF
```

---

### Problema: kubectl retorna "Unable to connect to the server: x509"

**Sintoma:**
```
Unable to connect to the server: x509: certificate signed by unknown authority
```

**Causa provável:** O kubeconfig está referenciando uma CA diferente da que assinou o certificado do apiserver, ou o arquivo CA no kubeconfig está incorreto/ausente.

**Resolução:**
```bash
# 1. Verificar qual CA o kubeconfig está usando
kubectl config view --raw | grep certificate-authority

# 2. Verificar que o certificado do apiserver foi assinado por essa CA
openssl verify -CAfile <CA_DO_KUBECONFIG> /etc/kubernetes/pki/kube-apiserver.pem

# 3. Se necessário, atualizar o kubeconfig com a CA correta
kubectl config set-cluster k8s-lab \
  --certificate-authority=/path/to/ca.pem \
  --server=https://${CONTROL_PLANE_PUBLIC_IP}:6443

# 4. Testar conectividade
kubectl cluster-info
```

---

### Problema: Relógio do sistema dessincronizado causa falha TLS

**Sintoma:**
```
x509: certificate has expired or is not yet valid: current time 2020-01-01T00:00:00Z is before 2024-01-01T00:00:00Z
```

**Causa provável:** O relógio do sistema está incorreto. Certificados TLS são validados contra o horário atual — se o relógio estiver no passado, certificados válidos parecem "ainda não válidos"; se estiver no futuro, parecem "expirados".

**Resolução:**
```bash
# 1. Verificar horário atual do sistema
date

# 2. Sincronizar com NTP
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# 3. Verificar sincronização
timedatectl status
# Deve mostrar "System clock synchronized: yes"

# 4. Reiniciar o componente afetado
sudo systemctl restart <componente>
```

---

### Resumo de Diagnóstico Rápido

| Erro | Causa Mais Comum | Primeira Ação |
|---|---|---|
| `certificate signed by unknown authority` | CA incorreta ou ausente | Verificar CA no nó |
| `certificate is valid for X, not Y` | SANs incompletos | Verificar SANs com `openssl x509 -text` |
| `certificate has expired` | Certificado expirado | Verificar datas com `openssl x509 -dates` |
| `permission denied` | Permissões incorretas | `chmod 600` nas chaves |
| `bad certificate` | Certificado não assinado pela CA esperada | `openssl verify -CAfile` |
| `Unauthorized` | CN/O incorretos no certificado | Verificar subject com `openssl x509 -subject` |

---

## Próximo Módulo

Após gerar e distribuir todos os certificados TLS, prossiga para:

➡️ [Módulo 03 — Container Runtime (containerd)](../03-container-runtime/)

Os certificados gerados neste módulo serão referenciados em todos os módulos subsequentes para configurar a comunicação TLS entre os componentes do cluster.
