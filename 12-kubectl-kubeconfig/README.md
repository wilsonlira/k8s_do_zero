# Módulo 12 — kubectl & kubeconfig

## Objetivo

Instalar e configurar o `kubectl` para interagir com o cluster Kubernetes a partir da máquina local. Ao final deste módulo, você terá:

- O `kubectl` instalado e funcional na máquina local
- Um arquivo kubeconfig criado manualmente com certificados CA, endpoint do API server e credenciais de usuário
- Compreensão completa da estrutura do kubeconfig (clusters, users, contexts)
- Conectividade verificada com o cluster (cluster-info, listagem de nodes)
- Entendimento de como RBAC se integra com os usuários definidos no kubeconfig

## Teoria

### O que é o kubectl?

O `kubectl` é a ferramenta de linha de comando (CLI) oficial do Kubernetes. Ele é o principal ponto de interação entre o administrador/desenvolvedor e o cluster.

**Função principal**: Traduzir comandos do usuário em requisições HTTP REST para o kube-apiserver.

### Como o kubectl se comunica com o API Server

```
┌──────────────┐         HTTPS (TLS mútuo)         ┌──────────────────┐
│   kubectl    │ ──────────────────────────────────▶│  kube-apiserver  │
│  (máquina    │   POST /api/v1/namespaces/default  │  (control plane) │
│   local)     │◀────────────────────────────────── │  porta 6443      │
└──────────────┘         JSON response              └──────────────────┘
```

O fluxo de comunicação funciona assim:

1. O usuário executa um comando (ex: `kubectl get pods`)
2. O kubectl lê o kubeconfig para obter: endpoint do API server, certificado CA, e credenciais do usuário
3. O kubectl traduz o comando em uma requisição HTTP REST:
   - `kubectl get pods` → `GET /api/v1/namespaces/default/pods`
   - `kubectl create deployment nginx --image=nginx` → `POST /apis/apps/v1/namespaces/default/deployments`
   - `kubectl delete pod mypod` → `DELETE /api/v1/namespaces/default/pods/mypod`
4. O kubectl estabelece conexão TLS com o API server, apresentando o certificado do cliente
5. O API server autentica o usuário, verifica autorização (RBAC), e processa a requisição
6. A resposta JSON é formatada e exibida ao usuário

### Tradução de Comandos para API REST

| Comando kubectl | Método HTTP | Endpoint da API |
|---|---|---|
| `kubectl get nodes` | GET | `/api/v1/nodes` |
| `kubectl get pods -n kube-system` | GET | `/api/v1/namespaces/kube-system/pods` |
| `kubectl create namespace test` | POST | `/api/v1/namespaces` |
| `kubectl delete pod nginx` | DELETE | `/api/v1/namespaces/default/pods/nginx` |
| `kubectl apply -f deploy.yaml` | PATCH/POST | `/apis/apps/v1/namespaces/default/deployments` |
| `kubectl scale deploy nginx --replicas=3` | PATCH | `/apis/apps/v1/namespaces/default/deployments/nginx/scale` |

Você pode verificar qual requisição o kubectl faz usando a flag `--v=8` para ver os detalhes HTTP:

```bash
kubectl get nodes --v=8
```

### O que é o kubeconfig?

O kubeconfig é um arquivo YAML que contém todas as informações necessárias para o kubectl se conectar a um ou mais clusters Kubernetes. Ele define **três conceitos fundamentais**:

#### 1. Clusters

Define os clusters Kubernetes disponíveis. Cada entrada contém:
- **server**: URL do kube-apiserver (ex: `https://<CONTROL_PLANE_IP>:6443`)
- **certificate-authority** (ou certificate-authority-data): Certificado CA para validar o certificado TLS do servidor

#### 2. Users

Define as credenciais de autenticação. Cada entrada contém:
- **client-certificate** (ou client-certificate-data): Certificado do cliente para autenticação mTLS
- **client-key** (ou client-key-data): Chave privada correspondente ao certificado do cliente

O API server extrai o CN (Common Name) e O (Organization) do certificado para identificar o usuário e seus grupos.

#### 3. Contexts

Vincula um cluster a um usuário, criando uma "sessão" nomeada. Cada contexto define:
- **cluster**: Nome do cluster (referência à seção clusters)
- **user**: Nome do usuário (referência à seção users)
- **namespace** (opcional): Namespace padrão para comandos

#### current-context

Indica qual contexto está ativo. O kubectl usa este contexto por padrão em todos os comandos.

### Múltiplos Contextos

Um único kubeconfig pode conter múltiplos clusters e usuários. Isso é útil quando você gerencia vários ambientes (dev, staging, production):

```yaml
contexts:
  - context:
      cluster: k8s-lab
      user: admin
    name: lab-admin
  - context:
      cluster: k8s-production
      user: deploy-user
      namespace: production
    name: prod-deploy
current-context: lab-admin
```

Comandos para gerenciar contextos:
- `kubectl config get-contexts` — lista todos os contextos
- `kubectl config use-context <nome>` — alterna o contexto ativo
- `kubectl config current-context` — mostra o contexto atual

### RBAC e kubeconfig

O kubeconfig define **quem** o usuário é (via certificado). O RBAC define **o que** esse usuário pode fazer.

A integração funciona assim:

1. O certificado do cliente contém CN (Common Name) e O (Organization)
2. O API server extrai esses campos durante a autenticação:
   - **CN** → nome do usuário no Kubernetes
   - **O** → grupo(s) do usuário no Kubernetes
3. ClusterRoleBindings e RoleBindings vinculam usuários/grupos a permissões

**Exemplo prático no lab:**

| Certificado (kubeconfig) | CN | O | Binding RBAC | Permissões |
|---|---|---|---|---|
| admin.pem | admin | system:masters | ClusterRoleBinding built-in | cluster-admin (acesso total) |
| kubelet.pem | system:node:k8s-worker-01 | system:nodes | ClusterRoleBinding built-in | Permissões de node |
| kube-proxy.pem | system:kube-proxy | system:node-proxier | ClusterRoleBinding built-in | Permissões de proxy |

O grupo `system:masters` é especial — ele é automaticamente vinculado ao ClusterRole `cluster-admin` por um ClusterRoleBinding built-in que o Kubernetes cria na inicialização. Isso concede acesso irrestrito a todos os recursos do cluster.

**Criando um usuário com permissões limitadas (exemplo):**

```yaml
# ClusterRole com permissões de leitura
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: read-only
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "nodes"]
    verbs: ["get", "list", "watch"]

---
# ClusterRoleBinding vinculando o usuário "developer" ao ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developer-read-only
subjects:
  - kind: User
    name: developer        # Corresponde ao CN do certificado
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: read-only
  apiGroup: rbac.authorization.k8s.io
```

Neste caso, se um certificado com CN=developer for usado no kubeconfig, o usuário terá apenas permissões de leitura em pods, services e nodes.

**RoleBinding vs ClusterRoleBinding:**

| Tipo | Escopo | Uso |
|---|---|---|
| RoleBinding | Namespace específico | Permissões limitadas a um namespace |
| ClusterRoleBinding | Cluster inteiro | Permissões em todos os namespaces |

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 00 — Pré-requisitos](../00-prerequisites/) — ferramentas locais instaladas
- [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/) — instâncias EC2 provisionadas
- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — CA e certificados gerados
- [Módulo 05 — kube-apiserver](../05-kube-apiserver/) — API server rodando e acessível

Você precisa ter disponível:
- O certificado CA do cluster (`ca.pem`)
- O certificado e chave do admin (`admin.pem`, `admin-key.pem`)
- O IP público do nó control plane (variável `CONTROL_PLANE_IP` em `variables.env`)
- O API server rodando e acessível na porta 6443

## Comandos Passo a Passo

### 1. Instalar kubectl

O kubectl é o binário que traduz seus comandos em chamadas REST ao API server. A versão deve ser compatível com a versão do cluster (±1 minor version).

#### Linux (x86_64)

O comando abaixo baixa o binário do kubectl na versão correspondente ao cluster definida em `variables.env` (`K8S_VERSION=1.29.0`):

```bash
# Carregar variáveis do lab
source variables.env

# Baixar o binário do kubectl na versão do cluster
curl -LO "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kubectl"

# Tornar executável
chmod +x kubectl

# Mover para diretório no PATH do sistema
sudo mv kubectl /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso. O binário estará disponível em `/usr/local/bin/kubectl`.

#### macOS (Apple Silicon)

```bash
source variables.env

# Baixar kubectl para macOS ARM64
curl -LO "https://dl.k8s.io/release/v${K8S_VERSION}/bin/darwin/arm64/kubectl"

chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

#### macOS (Intel)

```bash
source variables.env

# Baixar kubectl para macOS AMD64
curl -LO "https://dl.k8s.io/release/v${K8S_VERSION}/bin/darwin/amd64/kubectl"

chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

#### Verificar instalação do kubectl

Confirme que o kubectl foi instalado corretamente e está na versão esperada:

```bash
kubectl version --client
```

**Saída esperada:**
```
Client Version: v1.29.0
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
```

A linha-chave é `Client Version: v1.29.0` — confirma que a versão instalada é compatível com o cluster.

---

### 2. Copiar Certificados para a Máquina Local

Antes de criar o kubeconfig, você precisa ter os certificados na máquina local. Esses certificados foram gerados no [Módulo 02 — Certificados TLS](../02-tls-certificates/).

O comando abaixo copia os certificados necessários do nó control plane para a máquina local:

```bash
source variables.env

# Criar diretório local para certificados do cluster
mkdir -p ~/.kube/certs

# Copiar o certificado CA (usado para validar o API server)
scp -i ~/.ssh/${KEY_NAME}.pem \
  ubuntu@${CONTROL_PLANE_IP}:/etc/kubernetes/pki/ca.pem \
  ~/.kube/certs/ca.pem

# Copiar o certificado do admin (identidade do usuário)
scp -i ~/.ssh/${KEY_NAME}.pem \
  ubuntu@${CONTROL_PLANE_IP}:/etc/kubernetes/pki/admin.pem \
  ~/.kube/certs/admin.pem

# Copiar a chave privada do admin
scp -i ~/.ssh/${KEY_NAME}.pem \
  ubuntu@${CONTROL_PLANE_IP}:/etc/kubernetes/pki/admin-key.pem \
  ~/.kube/certs/admin-key.pem
```

**Saída esperada (para cada comando scp):**
```
ca.pem                                        100% 1350     1.3KB/s   00:00
admin.pem                                     100% 1452     1.4KB/s   00:00
admin-key.pem                                 100% 1679     1.6KB/s   00:00
```

Proteja a chave privada com permissões restritas:

```bash
# Restringir permissões da chave privada (somente leitura pelo dono)
chmod 600 ~/.kube/certs/admin-key.pem
chmod 644 ~/.kube/certs/ca.pem ~/.kube/certs/admin.pem
```

**Saída esperada:** Nenhuma saída indica sucesso.

---

### 3. Criar o Arquivo kubeconfig Manualmente

O kubeconfig é o arquivo que conecta o kubectl ao cluster. Vamos criá-lo manualmente para entender cada seção.

O kubectl procura o kubeconfig no caminho `~/.kube/config` por padrão. Você pode usar outro caminho definindo a variável `KUBECONFIG` ou a flag `--kubeconfig`.

Crie o arquivo `~/.kube/config` com o conteúdo abaixo. Cada seção é explicada em detalhe:

```bash
source variables.env

cat > ~/.kube/config << EOF
apiVersion: v1
kind: Config

# ============================================================================
# CLUSTERS: Define os clusters Kubernetes disponíveis
# ============================================================================
# Cada entrada especifica como se conectar a um cluster:
# - server: URL completa do kube-apiserver (protocolo + IP + porta)
# - certificate-authority: Caminho para o certificado CA que assinou o
#   certificado do API server. Usado para validar a identidade do servidor.
clusters:
  - cluster:
      certificate-authority: ${HOME}/.kube/certs/ca.pem
      server: https://${CONTROL_PLANE_IP}:${KUBERNETES_API_PORT}
    name: ${CLUSTER_NAME}

# ============================================================================
# USERS: Define as credenciais de autenticação
# ============================================================================
# Cada entrada contém as credenciais que o kubectl apresenta ao API server:
# - client-certificate: Certificado X.509 do cliente (contém CN e O)
# - client-key: Chave privada correspondente ao certificado
#
# O API server extrai do certificado:
#   CN (Common Name) = "admin" → nome do usuário
#   O (Organization) = "system:masters" → grupo do usuário
users:
  - name: admin
    user:
      client-certificate: ${HOME}/.kube/certs/admin.pem
      client-key: ${HOME}/.kube/certs/admin-key.pem

# ============================================================================
# CONTEXTS: Vincula um cluster a um usuário
# ============================================================================
# Um contexto é uma combinação nomeada de cluster + user + namespace.
# Permite alternar rapidamente entre diferentes clusters/credenciais.
contexts:
  - context:
      cluster: ${CLUSTER_NAME}
      user: admin
    name: ${CLUSTER_NAME}-admin

# ============================================================================
# CURRENT-CONTEXT: Contexto ativo por padrão
# ============================================================================
# O kubectl usa este contexto quando nenhum --context é especificado.
current-context: ${CLUSTER_NAME}-admin
EOF
```

**Saída esperada:** Nenhuma saída indica sucesso. O arquivo `~/.kube/config` foi criado.

Proteja o kubeconfig com permissões adequadas:

```bash
# Restringir permissões do kubeconfig (contém referências a chaves privadas)
chmod 600 ~/.kube/config
```

**Saída esperada:** Nenhuma saída indica sucesso.

---

### 4. Explicação Detalhada de Cada Seção do kubeconfig

#### Seção `clusters`

| Campo | Valor no Lab | Descrição |
|---|---|---|
| `name` | `k8s-lab` | Nome lógico do cluster (usado como referência nos contexts) |
| `server` | `https://<CONTROL_PLANE_IP>:6443` | URL completa do kube-apiserver. O protocolo HTTPS é obrigatório para comunicação segura |
| `certificate-authority` | `~/.kube/certs/ca.pem` | Caminho para o certificado CA. O kubectl usa este CA para verificar que o certificado apresentado pelo API server é legítimo (previne ataques man-in-the-middle) |

> **Nota**: Você pode usar `certificate-authority-data` em vez de `certificate-authority` para embutir o certificado CA em base64 diretamente no kubeconfig. Isso torna o arquivo portável (não depende de caminhos locais).

#### Seção `users`

| Campo | Valor no Lab | Descrição |
|---|---|---|
| `name` | `admin` | Nome lógico do usuário (usado como referência nos contexts) |
| `client-certificate` | `~/.kube/certs/admin.pem` | Certificado X.509 apresentado ao API server. O CN e O deste certificado determinam a identidade e grupo do usuário |
| `client-key` | `~/.kube/certs/admin-key.pem` | Chave privada RSA correspondente ao certificado. Usada para provar posse do certificado durante o handshake TLS |

#### Seção `contexts`

| Campo | Valor no Lab | Descrição |
|---|---|---|
| `name` | `k8s-lab-admin` | Nome do contexto (usado com `kubectl config use-context`) |
| `cluster` | `k8s-lab` | Referência ao cluster definido na seção clusters |
| `user` | `admin` | Referência ao usuário definido na seção users |
| `namespace` | (não definido) | Namespace padrão. Se omitido, usa `default` |

#### Campo `current-context`

| Campo | Valor no Lab | Descrição |
|---|---|---|
| `current-context` | `k8s-lab-admin` | Contexto usado por padrão pelo kubectl. Pode ser alterado com `kubectl config use-context` |

---

### 5. Criar kubeconfig Usando Comandos kubectl config

Alternativamente ao método manual acima, você pode usar os subcomandos `kubectl config` para construir o kubeconfig incrementalmente. Isso é útil para automação:

```bash
source variables.env

# Definir o cluster (adiciona entrada na seção clusters)
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=${HOME}/.kube/certs/ca.pem \
  --server=https://${CONTROL_PLANE_IP}:${KUBERNETES_API_PORT} \
  --kubeconfig=${HOME}/.kube/config
```

**Saída esperada:**
```
Cluster "k8s-lab" set.
```

```bash
# Definir as credenciais do usuário (adiciona entrada na seção users)
kubectl config set-credentials admin \
  --client-certificate=${HOME}/.kube/certs/admin.pem \
  --client-key=${HOME}/.kube/certs/admin-key.pem \
  --kubeconfig=${HOME}/.kube/config
```

**Saída esperada:**
```
User "admin" set.
```

```bash
# Criar o contexto vinculando cluster + user (adiciona entrada na seção contexts)
kubectl config set-context ${CLUSTER_NAME}-admin \
  --cluster=${CLUSTER_NAME} \
  --user=admin \
  --kubeconfig=${HOME}/.kube/config
```

**Saída esperada:**
```
Context "k8s-lab-admin" set.
```

```bash
# Definir o contexto ativo (define current-context)
kubectl config use-context ${CLUSTER_NAME}-admin \
  --kubeconfig=${HOME}/.kube/config
```

**Saída esperada:**
```
Switched to context "k8s-lab-admin".
```

---

### 6. Verificar o kubeconfig Criado

Confirme que o kubeconfig foi criado corretamente visualizando sua estrutura:

```bash
# Visualizar o kubeconfig completo (sem dados sensíveis)
kubectl config view
```

**Saída esperada:**
```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /home/user/.kube/certs/ca.pem
    server: https://<CONTROL_PLANE_IP>:6443
  name: k8s-lab
contexts:
- context:
    cluster: k8s-lab
    user: admin
  name: k8s-lab-admin
current-context: k8s-lab-admin
kind: Config
preferences: {}
users:
- name: admin
  user:
    client-certificate: /home/user/.kube/certs/admin.pem
    client-key: /home/user/.kube/certs/admin-key.pem
```

A linha-chave é `current-context: k8s-lab-admin` — confirma que o contexto ativo está configurado.

```bash
# Verificar o contexto atual
kubectl config current-context
```

**Saída esperada:**
```
k8s-lab-admin
```

```bash
# Listar todos os contextos disponíveis
kubectl config get-contexts
```

**Saída esperada:**
```
CURRENT   NAME             CLUSTER   AUTHINFO   NAMESPACE
*         k8s-lab-admin    k8s-lab   admin      
```

O asterisco (`*`) indica o contexto ativo.

---

### 7. Gerenciar Múltiplos Contextos

Se no futuro você tiver múltiplos clusters, pode adicionar contextos adicionais ao mesmo kubeconfig:

```bash
# Exemplo: adicionar um segundo cluster (hipotético)
kubectl config set-cluster k8s-production \
  --certificate-authority=/path/to/prod-ca.pem \
  --server=https://prod-api-server:6443

kubectl config set-credentials prod-admin \
  --client-certificate=/path/to/prod-admin.pem \
  --client-key=/path/to/prod-admin-key.pem

kubectl config set-context k8s-production-admin \
  --cluster=k8s-production \
  --user=prod-admin

# Alternar entre contextos
kubectl config use-context k8s-production-admin
```

**Saída esperada:**
```
Switched to context "k8s-production-admin".
```

Para voltar ao cluster do lab:

```bash
kubectl config use-context k8s-lab-admin
```

**Saída esperada:**
```
Switched to context "k8s-lab-admin".
```

Você também pode usar a flag `--context` para executar um comando em um contexto específico sem alterar o current-context:

```bash
# Executar comando no contexto de produção sem alterar o contexto ativo
kubectl --context=k8s-production-admin get nodes
```

## Verificação

Execute os comandos abaixo para confirmar que o kubectl está conectado ao cluster e funcionando corretamente.

### Verificar informações do cluster

O comando `cluster-info` consulta o API server e retorna os endpoints principais do cluster:

```bash
kubectl cluster-info
```

**Saída esperada:**
```
Kubernetes control plane is running at https://<CONTROL_PLANE_IP>:6443
CoreDNS is running at https://<CONTROL_PLANE_IP>:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

A linha-chave é `Kubernetes control plane is running at https://<CONTROL_PLANE_IP>:6443` — confirma que o kubectl consegue se comunicar com o API server.

### Listar nós do cluster

O comando abaixo lista todos os nós registrados no cluster e seu status:

```bash
kubectl get nodes
```

**Saída esperada:**
```
NAME               STATUS   ROLES    AGE   VERSION
k8s-control-plane  Ready    <none>   1d    v1.29.0
k8s-worker-01      Ready    <none>   1d    v1.29.0
```

As linhas-chave são:
- **STATUS: Ready** — indica que o nó está saudável e aceitando workloads
- **VERSION: v1.29.0** — confirma a versão do kubelet em cada nó

> **Nota**: Se os nós aparecem como `NotReady`, verifique se o CNI plugin está instalado (Módulo 10) e se o kubelet está rodando em cada nó (Módulo 08).

### Verificar componentes do cluster

```bash
kubectl get componentstatuses
```

**Saída esperada:**
```
NAME                 STATUS    MESSAGE   ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   ok
```

> **Nota**: O comando `componentstatuses` está deprecated em versões recentes do Kubernetes, mas ainda funciona na v1.29.

### Listar namespaces

```bash
kubectl get namespaces
```

**Saída esperada:**
```
NAME              STATUS   AGE
default           Active   1d
kube-node-lease   Active   1d
kube-public       Active   1d
kube-system       Active   1d
```

### Verificar pods do sistema

```bash
kubectl get pods -n kube-system
```

**Saída esperada:**
```
NAME                       READY   STATUS    RESTARTS   AGE
coredns-5dd5756b68-xxxxx   1/1     Running   0          1d
```

### Verificar permissões do usuário admin

Confirme que o usuário admin tem acesso total ao cluster (cluster-admin):

```bash
# Verificar se o usuário pode fazer tudo em todos os namespaces
kubectl auth can-i '*' '*' --all-namespaces
```

**Saída esperada:**
```
yes
```

A resposta `yes` confirma que o usuário admin (grupo system:masters) tem permissões irrestritas.

```bash
# Verificar permissões específicas
kubectl auth can-i create deployments
kubectl auth can-i delete nodes
kubectl auth can-i get secrets --all-namespaces
```

**Saída esperada (para cada comando):**
```
yes
```

### Testar comunicação direta com a API

Para confirmar que o kubectl está traduzindo comandos corretamente, faça uma chamada direta à API:

```bash
# Listar API resources disponíveis
kubectl api-resources --namespaced=false | head -20
```

**Saída esperada (primeiras linhas):**
```
NAME                              SHORTNAMES   APIVERSION   NAMESPACED   KIND
componentstatuses                 cs           v1           false        ComponentStatus
namespaces                        ns           v1           false        Namespace
nodes                             no           v1           false        Node
persistentvolumes                 pv           v1           false        PersistentVolume
```

### Script de verificação completa

Execute o script abaixo para verificar toda a configuração de uma vez:

```bash
#!/bin/bash
echo "=== Verificação do kubectl & kubeconfig ==="
echo ""

# Verificar kubectl instalado
echo -n "[1/6] kubectl instalado.... "
if kubectl version --client --short 2>/dev/null | grep -q "v1."; then
    echo "✅ OK ($(kubectl version --client --short 2>/dev/null))"
else
    echo "❌ NÃO ENCONTRADO"
fi

# Verificar kubeconfig existe
echo -n "[2/6] kubeconfig existe.... "
if [ -f ~/.kube/config ]; then
    echo "✅ OK (~/.kube/config)"
else
    echo "❌ ARQUIVO NÃO ENCONTRADO"
fi

# Verificar contexto configurado
echo -n "[3/6] Contexto ativo....... "
CONTEXT=$(kubectl config current-context 2>/dev/null)
if [ -n "$CONTEXT" ]; then
    echo "✅ OK ($CONTEXT)"
else
    echo "❌ NENHUM CONTEXTO ATIVO"
fi

# Verificar conectividade com API server
echo -n "[4/6] API server acessível. "
if kubectl cluster-info &>/dev/null; then
    echo "✅ OK"
else
    echo "❌ CONEXÃO FALHOU"
fi

# Verificar nodes
echo -n "[5/6] Nodes visíveis....... "
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -gt 0 ]; then
    echo "✅ OK ($NODE_COUNT nodes)"
else
    echo "❌ NENHUM NODE ENCONTRADO"
fi

# Verificar permissões admin
echo -n "[6/6] Permissões admin..... "
if kubectl auth can-i '*' '*' --all-namespaces 2>/dev/null | grep -q "yes"; then
    echo "✅ OK (cluster-admin)"
else
    echo "❌ PERMISSÕES INSUFICIENTES"
fi

echo ""
echo "=== Verificação concluída ==="
```

**Saída esperada (tudo funcionando):**
```
=== Verificação do kubectl & kubeconfig ===

[1/6] kubectl instalado.... ✅ OK (Client Version: v1.29.0)
[2/6] kubeconfig existe.... ✅ OK (~/.kube/config)
[3/6] Contexto ativo....... ✅ OK (k8s-lab-admin)
[4/6] API server acessível. ✅ OK
[5/6] Nodes visíveis....... ✅ OK (2 nodes)
[6/6] Permissões admin..... ✅ OK (cluster-admin)

=== Verificação concluída ===
```

## Troubleshooting

### Problema: Connection refused ao conectar no API server

**Sintoma:**
```
The connection to the server <CONTROL_PLANE_IP>:6443 was refused - did you specify the right host or port?
```

**Causa provável 1:** O kube-apiserver não está rodando no nó control plane.

**Resolução:**
```bash
# Verificar se o API server está rodando (executar no control plane via SSH)
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_IP} \
  "systemctl status kube-apiserver"

# Se não estiver rodando, iniciar o serviço
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_IP} \
  "sudo systemctl start kube-apiserver"

# Verificar logs para erros
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_IP} \
  "sudo journalctl -u kube-apiserver --no-pager -l --since '5 minutes ago'"
```

**Causa provável 2:** O security group não permite tráfego na porta 6443 a partir do seu IP.

**Resolução:**
```bash
# Verificar regras do security group (porta 6443 deve estar aberta)
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=k8s-lab-control-plane-sg" \
  --query 'SecurityGroups[].IpPermissions[?FromPort==`6443`]' \
  --output table

# Se necessário, adicionar regra para seu IP público
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
  --group-name k8s-lab-control-plane-sg \
  --protocol tcp \
  --port 6443 \
  --cidr ${MY_IP}/32
```

---

### Problema: Certificate validation failure (x509)

**Sintoma:**
```
Unable to connect to the server: x509: certificate signed by unknown authority
```

**Causa provável 1:** O certificado CA no kubeconfig não corresponde ao CA que assinou o certificado do API server.

**Resolução:**
```bash
# Verificar qual CA está configurada no kubeconfig
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority}'

# Verificar o issuer do certificado do API server
echo | openssl s_client -connect ${CONTROL_PLANE_IP}:6443 2>/dev/null | \
  openssl x509 -noout -issuer

# Verificar o subject do CA local
openssl x509 -in ~/.kube/certs/ca.pem -noout -subject -issuer

# Se não corresponderem, copiar o CA correto do control plane
scp -i ~/.ssh/k8s-lab-key.pem \
  ubuntu@${CONTROL_PLANE_IP}:/etc/kubernetes/pki/ca.pem \
  ~/.kube/certs/ca.pem
```

**Causa provável 2:** O certificado CA expirou.

**Resolução:**
```bash
# Verificar validade do certificado CA
openssl x509 -in ~/.kube/certs/ca.pem -noout -dates

# Saída esperada (certificado válido):
# notBefore=Jan  1 00:00:00 2024 GMT
# notAfter=Dec 31 23:59:59 2033 GMT

# Se expirado, regenerar o CA seguindo o Módulo 02 - Certificados TLS
```

---

### Problema: Unauthorized (401) ao executar comandos

**Sintoma:**
```
error: You must be logged in to the server (Unauthorized)
```

**Causa provável 1:** O certificado do cliente (admin.pem) não foi assinado pelo mesmo CA que o API server confia.

**Resolução:**
```bash
# Verificar o issuer do certificado do admin
openssl x509 -in ~/.kube/certs/admin.pem -noout -issuer

# Verificar o subject do certificado do admin (deve ter CN=admin, O=system:masters)
openssl x509 -in ~/.kube/certs/admin.pem -noout -subject

# Saída esperada:
# subject=O = system:masters, CN = admin

# Se o subject estiver incorreto, regenerar o certificado admin
# seguindo o Módulo 02 - Certificados TLS
```

**Causa provável 2:** O certificado do cliente expirou.

**Resolução:**
```bash
# Verificar validade do certificado do admin
openssl x509 -in ~/.kube/certs/admin.pem -noout -dates

# Se expirado, regenerar seguindo o Módulo 02 - Certificados TLS
# e copiar novamente para a máquina local
```

---

### Problema: Timeout ao conectar no API server

**Sintoma:**
```
Unable to connect to the server: dial tcp <CONTROL_PLANE_IP>:6443: i/o timeout
```

**Causa provável 1:** O IP do control plane está incorreto no kubeconfig ou a instância EC2 não está rodando.

**Resolução:**
```bash
# Verificar se a instância está rodando
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${CONTROL_PLANE_NAME}" \
  --query 'Reservations[].Instances[].{State:State.Name,PublicIP:PublicIpAddress}' \
  --output table

# Verificar o IP configurado no kubeconfig
kubectl config view -o jsonpath='{.clusters[0].cluster.server}'

# Se o IP mudou (instância foi reiniciada), atualizar o kubeconfig
kubectl config set-cluster ${CLUSTER_NAME} \
  --server=https://<NOVO_IP>:6443
```

**Causa provável 2:** Problema de rede (firewall local, VPN, ou rota bloqueada).

**Resolução:**
```bash
# Testar conectividade TCP na porta 6443
nc -zv ${CONTROL_PLANE_IP} 6443

# Se timeout, verificar se há firewall local bloqueando
# Em Linux:
sudo iptables -L OUTPUT -n | grep 6443

# Testar com curl (ignora certificado para teste de conectividade)
curl -k --connect-timeout 5 https://${CONTROL_PLANE_IP}:6443/healthz
```

---

### Problema: Forbidden (403) ao executar comandos específicos

**Sintoma:**
```
Error from server (Forbidden): pods is forbidden: User "developer" cannot list resource "pods" in API group "" in the namespace "default"
```

**Causa provável:** O usuário no kubeconfig não tem permissões RBAC suficientes para a operação solicitada.

**Resolução:**
```bash
# Verificar qual usuário está sendo usado
kubectl config view -o jsonpath='{.contexts[?(@.name=="'$(kubectl config current-context)'")].context.user}'

# Verificar as permissões do usuário
kubectl auth can-i --list

# Se precisar de mais permissões, criar um RoleBinding ou ClusterRoleBinding
# (requer acesso com um usuário admin)
kubectl --context=k8s-lab-admin create clusterrolebinding developer-admin \
  --clusterrole=cluster-admin \
  --user=developer
```

---

### Problema: kubeconfig não encontrado

**Sintoma:**
```
The connection to the server localhost:8080 was refused - did you specify the right host or port?
```

**Causa provável:** O kubectl não encontrou o kubeconfig. Quando nenhum kubeconfig é encontrado, o kubectl tenta conectar em `localhost:8080` (padrão sem configuração).

**Resolução:**
```bash
# Verificar se o arquivo existe no caminho padrão
ls -la ~/.kube/config

# Se o arquivo está em outro local, definir a variável KUBECONFIG
export KUBECONFIG=/caminho/para/seu/kubeconfig

# Para tornar permanente
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc

# Verificar que o kubectl encontra o kubeconfig
kubectl config view
```

---

### Problema: Certificado do cliente não corresponde à chave privada

**Sintoma:**
```
Unable to connect to the server: tls: private key does not match public key
```

**Causa provável:** O arquivo `admin.pem` e `admin-key.pem` não formam um par válido. Isso pode ocorrer se os arquivos foram copiados incorretamente ou misturados com certificados de outro componente.

**Resolução:**
```bash
# Verificar se o certificado e a chave correspondem
# (os hashes MD5 devem ser idênticos)
openssl x509 -noout -modulus -in ~/.kube/certs/admin.pem | openssl md5
openssl rsa -noout -modulus -in ~/.kube/certs/admin-key.pem | openssl md5

# Se os hashes forem diferentes, copiar novamente do control plane
scp -i ~/.ssh/k8s-lab-key.pem \
  ubuntu@${CONTROL_PLANE_IP}:/etc/kubernetes/pki/admin.pem \
  ~/.kube/certs/admin.pem

scp -i ~/.ssh/k8s-lab-key.pem \
  ubuntu@${CONTROL_PLANE_IP}:/etc/kubernetes/pki/admin-key.pem \
  ~/.kube/certs/admin-key.pem
```

---

## Próximo Módulo

Após confirmar que o kubectl está conectado ao cluster e funcionando corretamente, prossiga para:

➡️ [Módulo 13 — Ingress Controller](../13-ingress-controller/)
