# Módulo 06 — kube-controller-manager

## Objetivo

Instalar e configurar o kube-controller-manager no cluster Kubernetes. Ao final deste módulo, você terá:

- Compreensão do papel do controller-manager como guardião do estado desejado do cluster
- Entendimento dos principais controllers (node, replication, endpoints, service account)
- Entendimento do loop de reconciliação (reconciliation loop)
- kube-controller-manager instalado e configurado como serviço systemd no nó Control Plane
- Kubeconfig dedicado para autenticação do controller-manager com o API server
- Capacidade de verificar a saúde do controller-manager e diagnosticar problemas

## Teoria

### O Papel do kube-controller-manager

O **kube-controller-manager** é o componente do control plane responsável por **manter o estado real do cluster igual ao estado desejado**. Ele executa múltiplos controllers em um único processo, onde cada controller observa o estado atual via API server e toma ações corretivas quando detecta divergências.

**Analogia**: Se o kube-apiserver é o "cérebro" que recebe comandos, o controller-manager é o "sistema nervoso autônomo" que mantém tudo funcionando sem intervenção manual.

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Control Plane                                    │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │              kube-controller-manager                            │  │
│  │                                                                │  │
│  │  ┌──────────────┐  ┌──────────────────┐  ┌────────────────┐   │  │
│  │  │    Node       │  │   Replication    │  │   Endpoints    │   │  │
│  │  │  Controller   │  │   Controller     │  │   Controller   │   │  │
│  │  └──────┬───────┘  └────────┬─────────┘  └───────┬────────┘   │  │
│  │         │                   │                     │            │  │
│  │  ┌──────┴───────┐  ┌───────┴──────────┐  ┌──────┴─────────┐  │  │
│  │  │Service Account│  │   Namespace      │  │     Job        │  │  │
│  │  │  Controller   │  │   Controller     │  │   Controller   │  │  │
│  │  └──────────────┘  └──────────────────┘  └────────────────┘   │  │
│  └────────────────────────────┬───────────────────────────────────┘  │
│                               │                                      │
│                               ▼                                      │
│                      ┌─────────────────┐                             │
│                      │  kube-apiserver  │                             │
│                      └─────────────────┘                             │
└─────────────────────────────────────────────────────────────────────┘
```

### Principais Controllers

O kube-controller-manager executa dezenas de controllers, mas os mais importantes para entender são:

| Controller | Responsabilidade |
|------------|-----------------|
| **Node Controller** | Monitora o estado dos nós do cluster. Detecta quando um nó para de responder (via heartbeats) e marca-o como `NotReady`. Após um timeout configurável, inicia a evicção dos pods do nó indisponível. |
| **Replication Controller** | Garante que o número correto de réplicas de pods está rodando. Se um pod morre, cria um novo. Se há pods em excesso, remove os extras. Trabalha com ReplicaSets e ReplicationControllers. |
| **Endpoints Controller** | Popula os objetos Endpoints associados a cada Service. Observa mudanças em Pods e Services, atualizando a lista de IPs dos pods que correspondem ao selector do Service. |
| **Service Account Controller** | Cria automaticamente a ServiceAccount "default" em cada novo namespace. Garante que todo namespace tenha pelo menos uma ServiceAccount disponível para pods. |
| **Namespace Controller** | Gerencia o ciclo de vida dos namespaces. Quando um namespace é deletado, remove todos os recursos dentro dele (pods, services, secrets, etc.). |
| **Job Controller** | Gerencia Jobs e CronJobs, garantindo que o número correto de pods complete com sucesso. |
| **Deployment Controller** | Gerencia rollouts de Deployments, criando e escalando ReplicaSets conforme a estratégia de atualização. |

### O Loop de Reconciliação (Reconciliation Loop)

O conceito fundamental do controller-manager é o **loop de reconciliação**. Cada controller segue este padrão:

```
┌─────────────────────────────────────────────────────────┐
│              Loop de Reconciliação                        │
│                                                          │
│   ┌──────────┐     ┌──────────────┐     ┌───────────┐  │
│   │ Observar │────►│   Comparar   │────►│   Agir    │  │
│   │  (Watch) │     │ Real vs      │     │ (Criar/   │  │
│   │          │     │ Desejado     │     │  Deletar/ │  │
│   └──────────┘     └──────────────┘     │  Atualizar│  │
│        ▲                                 └─────┬─────┘  │
│        │                                       │        │
│        └───────────────────────────────────────┘        │
│                    (loop contínuo)                        │
└─────────────────────────────────────────────────────────┘
```

**Funcionamento detalhado:**

1. **Observar (Watch)**: O controller usa a Watch API do kube-apiserver para receber notificações em tempo real sobre mudanças nos recursos que ele gerencia.

2. **Comparar**: Quando recebe uma notificação, compara o **estado atual** (o que existe no cluster) com o **estado desejado** (o que foi declarado pelo usuário via manifests).

3. **Agir**: Se houver divergência, toma ações corretivas:
   - Se faltam réplicas → cria novos pods
   - Se há réplicas em excesso → deleta pods extras
   - Se um nó está indisponível → marca como NotReady e agenda evicção

4. **Repetir**: O loop é contínuo. Mesmo após agir, o controller continua observando para detectar novas divergências.

**Exemplo prático — Replication Controller:**
- Usuário declara: "Quero 3 réplicas do pod nginx"
- Estado atual: 2 pods nginx rodando (um morreu)
- Divergência detectada: 2 ≠ 3
- Ação: Criar 1 novo pod nginx
- Resultado: 3 pods nginx rodando (estado real = estado desejado)

### Leader Election

Em clusters com múltiplos nós control plane (alta disponibilidade), apenas **uma instância** do controller-manager está ativa por vez. As demais ficam em standby. O mecanismo de **leader election** usa leases no Kubernetes para determinar qual instância é o leader.

No nosso lab com um único nó control plane, o controller-manager é sempre o leader.

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 00 — Pré-requisitos](../00-prerequisites/) — ferramentas básicas instaladas
- [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/) — instâncias EC2 provisionadas
- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — certificados gerados e distribuídos
- [Módulo 04 — etcd](../04-etcd/) — etcd instalado e rodando
- [Módulo 05 — kube-apiserver](../05-kube-apiserver/) — API server instalado e rodando

Você precisará dos seguintes itens dos módulos anteriores:

- **kube-apiserver rodando** e acessível em `https://${CONTROL_PLANE_IP}:6443`
- Certificado da CA (`/etc/kubernetes/pki/ca.pem`)
- Certificado do controller-manager (`/etc/kubernetes/pki/kube-controller-manager.pem`)
- Chave privada do controller-manager (`/etc/kubernetes/pki/kube-controller-manager-key.pem`)
- Chave privada da Service Account (`/etc/kubernetes/pki/service-account-key.pem`)
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

### 2. Baixar o Binário do kube-controller-manager

Baixe a versão específica do kube-controller-manager (1.29.0) do repositório oficial do Kubernetes:

```bash
# Definir a versão do Kubernetes
K8S_VERSION="1.29.0"

# Baixar o binário do kube-controller-manager
wget -q --show-progress \
  "https://dl.k8s.io/v${K8S_VERSION}/bin/linux/amd64/kube-controller-manager"
```

**Saída esperada:**
```
kube-controller-manager  100%[===================>] 117.2M  11.2MB/s    in 10s
```

### 3. Instalar o Binário

Torne o binário executável e mova-o para um diretório no PATH do sistema:

```bash
# Tornar executável
chmod +x kube-controller-manager

# Mover para /usr/local/bin
sudo mv kube-controller-manager /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

Verifique que o binário foi instalado corretamente:

```bash
# Verificar versão
kube-controller-manager --version
```

**Saída esperada:**
```
Kubernetes v1.29.0
```

### 4. Verificar Certificados Necessários

Antes de configurar o controller-manager, confirme que os certificados necessários estão no lugar correto:

```bash
# Verificar presença dos certificados
ls -la /etc/kubernetes/pki/ca.pem \
       /etc/kubernetes/pki/kube-controller-manager.pem \
       /etc/kubernetes/pki/kube-controller-manager-key.pem \
       /etc/kubernetes/pki/service-account-key.pem
```

**Saída esperada:**
```
-rw-r--r-- 1 root root 1318 Jan  1 00:00 /etc/kubernetes/pki/ca.pem
-rw-r--r-- 1 root root 1399 Jan  1 00:00 /etc/kubernetes/pki/kube-controller-manager.pem
-rw------- 1 root root 1675 Jan  1 00:00 /etc/kubernetes/pki/kube-controller-manager-key.pem
-rw------- 1 root root 1675 Jan  1 00:00 /etc/kubernetes/pki/service-account-key.pem
```

Se algum arquivo estiver ausente, volte ao [Módulo 02](../02-tls-certificates/) e execute a geração e distribuição de certificados.

### 5. Gerar o Kubeconfig do Controller-Manager

O controller-manager precisa de um kubeconfig para se autenticar com o kube-apiserver. Este arquivo contém as credenciais (certificado de cliente) e o endpoint do API server:

```bash
# Obter o IP interno do nó
INTERNAL_IP=$(hostname -I | awk '{print $1}')

# Criar diretório para kubeconfigs
sudo mkdir -p /etc/kubernetes/config
```

**Saída esperada:** Nenhuma saída indica sucesso.

Gere o kubeconfig usando `kubectl config`:

```bash
# Configurar o cluster no kubeconfig
kubectl config set-cluster k8s-lab \
  --certificate-authority=/etc/kubernetes/pki/ca.pem \
  --embed-certs=true \
  --server=https://${INTERNAL_IP}:6443 \
  --kubeconfig=/etc/kubernetes/config/kube-controller-manager.kubeconfig
```

**Saída esperada:**
```
Cluster "k8s-lab" set.
```

```bash
# Configurar as credenciais do controller-manager
kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=/etc/kubernetes/pki/kube-controller-manager.pem \
  --client-key=/etc/kubernetes/pki/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=/etc/kubernetes/config/kube-controller-manager.kubeconfig
```

**Saída esperada:**
```
User "system:kube-controller-manager" set.
```

```bash
# Configurar o contexto
kubectl config set-context default \
  --cluster=k8s-lab \
  --user=system:kube-controller-manager \
  --kubeconfig=/etc/kubernetes/config/kube-controller-manager.kubeconfig
```

**Saída esperada:**
```
Context "default" created.
```

```bash
# Definir o contexto padrão
kubectl config use-context default \
  --kubeconfig=/etc/kubernetes/config/kube-controller-manager.kubeconfig
```

**Saída esperada:**
```
Switched to context "default".
```

**Explicação do kubeconfig:**

| Seção | Campo | Descrição |
|-------|-------|-----------|
| `cluster` | `certificate-authority` | CA usada para validar o certificado do API server |
| `cluster` | `server` | Endpoint do kube-apiserver (HTTPS na porta 6443) |
| `user` | `client-certificate` | Certificado de cliente do controller-manager para autenticação mTLS |
| `user` | `client-key` | Chave privada correspondente ao certificado de cliente |
| `context` | `cluster` + `user` | Associa o cluster com as credenciais do controller-manager |

> **Nota**: O flag `--embed-certs=true` incorpora o conteúdo dos certificados diretamente no kubeconfig, eliminando dependência de caminhos de arquivo em tempo de execução.

### 6. Criar o Arquivo de Serviço systemd

Crie o unit file do systemd para gerenciar o kube-controller-manager como um serviço do sistema:

```bash
# Criar unit file do kube-controller-manager
cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=${POD_CIDR:-10.244.0.0/16} \\
  --cluster-name=k8s-lab \\
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \\
  --kubeconfig=/etc/kubernetes/config/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/etc/kubernetes/pki/ca.pem \\
  --service-account-private-key-file=/etc/kubernetes/pki/service-account-key.pem \\
  --service-cluster-ip-range=${SERVICE_CIDR:-10.96.0.0/12} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

**Saída esperada:** O conteúdo do unit file será exibido no terminal (comportamento do `tee`).

### 7. Explicação dos Parâmetros de Configuração

Cada flag do kube-controller-manager tem um propósito específico. A tabela abaixo detalha cada um com seu valor padrão e o valor usado no lab:

| Parâmetro | Padrão | Valor no Lab | Descrição |
|-----------|--------|--------------|-----------|
| `--bind-address` | `0.0.0.0` | `0.0.0.0` | Endereço IP no qual o controller-manager escuta para servir o endpoint de health check (/healthz). `0.0.0.0` aceita conexões de qualquer interface. |
| `--allocate-node-cidrs` | `false` | `true` | Habilita a alocação automática de sub-redes de pod CIDR para cada nó. Quando `true`, o Node Controller atribui um bloco /24 do `--cluster-cidr` a cada nó que se registra no cluster. Necessário para que o CNI plugin saiba qual range de IPs usar em cada nó. |
| `--cluster-cidr` | (nenhum) | `10.244.0.0/16` | Range CIDR de IPs para pods no cluster. Usado pelo Node Controller para alocar sub-redes de pod CIDR a cada nó. Deve corresponder ao CIDR configurado no CNI plugin. |
| `--cluster-name` | `kubernetes` | `k8s-lab` | Nome do cluster. Usado como prefixo em recursos criados pelo controller-manager. |
| `--cluster-signing-cert-file` | (nenhum) | `/etc/kubernetes/pki/ca.pem` | Certificado da CA usado para assinar novos certificados quando CSRs (Certificate Signing Requests) são aprovados. Permite que o controller-manager atue como CA para o cluster. |
| `--cluster-signing-key-file` | (nenhum) | `/etc/kubernetes/pki/ca-key.pem` | Chave privada da CA correspondente ao certificado de assinatura. Usada junto com `--cluster-signing-cert-file` para assinar CSRs. |
| `--kubeconfig` | (nenhum) | `/etc/kubernetes/config/kube-controller-manager.kubeconfig` | Caminho para o arquivo kubeconfig com credenciais para autenticação com o kube-apiserver. Contém certificado de cliente e endpoint do API server. |
| `--leader-elect` | `true` | `true` | Habilita leader election para alta disponibilidade. Apenas o leader executa os controllers. Em single-node, este nó é sempre o leader. |
| `--root-ca-file` | (nenhum) | `/etc/kubernetes/pki/ca.pem` | Certificado da CA raiz incluído nos tokens de ServiceAccount. Pods usam este CA para validar o certificado do API server ao se comunicar com ele. |
| `--service-account-private-key-file` | (nenhum) | `/etc/kubernetes/pki/service-account-key.pem` | Chave privada usada para assinar tokens de ServiceAccount (JWT). O API server usa a chave pública correspondente para validar estes tokens. |
| `--service-cluster-ip-range` | `10.0.0.0/24` | `10.96.0.0/12` | Range CIDR de IPs virtuais para Services do tipo ClusterIP. Deve ser idêntico ao configurado no kube-apiserver. |
| `--use-service-account-credentials` | `false` | `true` | Quando habilitado, cada controller usa sua própria ServiceAccount e credenciais separadas, em vez de compartilhar as credenciais do controller-manager. Melhora a segurança com princípio de menor privilégio. |
| `--v` | `0` | `2` | Nível de verbosidade dos logs. 0=mínimo, 2=informações úteis para debugging, 5=trace detalhado. Valor 2 é recomendado para labs. |

**Parâmetros do systemd unit file:**

| Parâmetro | Descrição |
|-----------|-----------|
| `Restart=on-failure` | Reinicia automaticamente se o processo falhar (exit code ≠ 0). |
| `RestartSec=5` | Aguarda 5 segundos antes de reiniciar após falha. |
| `After=network.target` | Garante que a rede esteja disponível antes de iniciar o controller-manager. |

### 8. Iniciar o Serviço kube-controller-manager

Recarregue a configuração do systemd e inicie o controller-manager:

```bash
# Recarregar configuração do systemd
sudo systemctl daemon-reload

# Habilitar o kube-controller-manager para iniciar no boot
sudo systemctl enable kube-controller-manager

# Iniciar o serviço
sudo systemctl start kube-controller-manager
```

**Saída esperada:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/kube-controller-manager.service → /etc/systemd/system/kube-controller-manager.service.
```

Verifique que o serviço está rodando:

```bash
# Verificar status do serviço
sudo systemctl status kube-controller-manager
```

**Saída esperada:**
```
● kube-controller-manager.service - Kubernetes Controller Manager
     Loaded: loaded (/etc/systemd/system/kube-controller-manager.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 5s ago
       Docs: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/
   Main PID: 2345 (kube-controller-)
      Tasks: 7 (limit: 1024)
     Memory: 45.0M
        CPU: 500ms
     CGroup: /system.slice/kube-controller-manager.service
             └─2345 /usr/local/bin/kube-controller-manager --bind-address=0.0.0.0 ...
```

**Linhas-chave para confirmar sucesso:**
- `Active: active (running)` — o serviço está rodando
- `enabled` — configurado para iniciar no boot

## Verificação

### 1. Verificar o Endpoint /healthz

O kube-controller-manager expõe um endpoint HTTP de health check na porta 10257 (HTTPS). Verifique que está respondendo com HTTP 200:

```bash
# Verificar saúde via /healthz (HTTPS na porta 10257)
curl -k https://127.0.0.1:10257/healthz
```

**Saída esperada:**
```
ok
```

A resposta `ok` indica que o controller-manager está saudável e operacional.

Para obter mais detalhes sobre cada verificação de saúde individual:

```bash
# Verificar saúde detalhada (verbose)
curl -k https://127.0.0.1:10257/healthz?verbose
```

**Saída esperada:**
```
[+]ping ok
[+]log ok
[+]etcd ok
[+]informer-sync ok
[+]poststarthook/start-kube-controller-manager-informers ok
[+]poststarthook/start-service-account-token-controller ok
healthz check passed
```

Cada linha `[+]` indica um sub-check que passou com sucesso.

### 2. Verificar Leader Election (Lease Holder)

Em um cluster Kubernetes, o controller-manager usa um objeto Lease no namespace `kube-system` para coordenar leader election. Verifique que este nó é o leader:

```bash
# Verificar o lease do controller-manager
kubectl get lease kube-controller-manager -n kube-system -o yaml \
  --kubeconfig=/etc/kubernetes/config/admin.kubeconfig
```

**Saída esperada:**
```yaml
apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  name: kube-controller-manager
  namespace: kube-system
spec:
  holderIdentity: k8s-control-plane_<uuid>
  leaseDurationSeconds: 15
  acquireTime: "2024-01-01T00:00:00.000000Z"
  renewTime: "2024-01-01T00:00:05.000000Z"
  leaseTransitions: 0
```

**Campos-chave:**
- `holderIdentity` — identifica o nó que é o leader atual
- `renewTime` — timestamp da última renovação do lease (deve ser recente)
- `leaseTransitions` — número de vezes que a liderança mudou (0 = nunca mudou)

Alternativamente, use um comando mais simples para verificar o holder:

```bash
# Verificar quem é o leader do controller-manager
kubectl get endpoints kube-controller-manager -n kube-system \
  --kubeconfig=/etc/kubernetes/config/admin.kubeconfig \
  -o jsonpath='{.metadata.annotations.control-plane\.alpha\.kubernetes\.io/leader}' | python3 -m json.tool
```

**Saída esperada:**
```json
{
    "holderIdentity": "k8s-control-plane_<uuid>",
    "leaseDurationSeconds": 15,
    "acquireTime": "2024-01-01T00:00:00Z",
    "renewTime": "2024-01-01T00:00:05Z",
    "leaderTransitions": 0
}
```

### 3. Verificar Logs do Controller-Manager

Verifique os logs para confirmar que os controllers foram iniciados com sucesso:

```bash
# Verificar logs recentes
sudo journalctl -u kube-controller-manager --no-pager -l --since "2 minutes ago" | head -30
```

**Saída esperada (linhas-chave):**
```
kube-controller-manager: "Starting controller" controller="node-controller"
kube-controller-manager: "Starting controller" controller="replication-controller"
kube-controller-manager: "Starting controller" controller="endpoint-controller"
kube-controller-manager: "Starting controller" controller="serviceaccount-controller"
kube-controller-manager: "Starting controller" controller="namespace-controller"
kube-controller-manager: "Starting controller" controller="deployment-controller"
kube-controller-manager: "Started leader election"
kube-controller-manager: "Successfully acquired lease" lease="kube-system/kube-controller-manager"
```

As mensagens "Starting controller" confirmam que cada controller individual foi iniciado. A mensagem "Successfully acquired lease" confirma que este nó é o leader.

### 4. Verificar Component Status via API Server

Verifique que o kube-apiserver reconhece o controller-manager como saudável:

```bash
# Verificar component status
kubectl get componentstatuses \
  --kubeconfig=/etc/kubernetes/config/admin.kubeconfig
```

**Saída esperada:**
```
NAME                 STATUS    MESSAGE   ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-0               Healthy   ok
```

A linha `controller-manager   Healthy   ok` confirma que o API server consegue se comunicar com o controller-manager e que ele está saudável.

> **Nota**: O comando `kubectl get componentstatuses` está deprecated em versões mais recentes do Kubernetes, mas ainda funciona na versão 1.29.0.

## Troubleshooting

### Problema 1: Controller-manager não inicia — "unable to load client CA file"

**Sintoma:**
```
error: unable to load client CA file "/etc/kubernetes/pki/ca.pem": open /etc/kubernetes/pki/ca.pem: no such file or directory
```

**Causa provável:** O caminho do certificado da CA está incorreto ou o arquivo não foi distribuído para o nó.

**Resolução:**

```bash
# Verificar se o arquivo existe
ls -la /etc/kubernetes/pki/ca.pem

# Se não existir, verificar o diretório de certificados
ls -la /etc/kubernetes/pki/

# Se o diretório não existir, criá-lo e redistribuir certificados
sudo mkdir -p /etc/kubernetes/pki

# Voltar ao Módulo 02 e executar a distribuição de certificados
# Após corrigir, reiniciar:
sudo systemctl restart kube-controller-manager
```

### Problema 2: Controller-manager não inicia — "failed to start controller"

**Sintoma:**
```
error: failed to start controller: unable to create service account controller: the service account key file "/etc/kubernetes/pki/service-account-key.pem" does not exist
```

**Causa provável:** A chave privada da Service Account não foi gerada ou não está no caminho esperado.

**Resolução:**

```bash
# Verificar se a chave existe
ls -la /etc/kubernetes/pki/service-account-key.pem

# Verificar permissões (deve ser legível pelo processo)
stat /etc/kubernetes/pki/service-account-key.pem

# Se não existir, gerar a chave (voltar ao Módulo 02)
# Ou verificar se está com outro nome:
ls -la /etc/kubernetes/pki/ | grep service-account

# Após corrigir, reiniciar:
sudo systemctl restart kube-controller-manager
```

### Problema 3: Controller-manager não conecta ao API server — "connection refused"

**Sintoma:**
```
error: Get "https://10.0.1.x:6443/api/v1/namespaces": dial tcp 10.0.1.x:6443: connect: connection refused
```

**Causa provável:** O kube-apiserver não está rodando ou o endpoint no kubeconfig está incorreto.

**Resolução:**

```bash
# Verificar se o kube-apiserver está rodando
sudo systemctl status kube-apiserver

# Se não estiver rodando, iniciar:
sudo systemctl start kube-apiserver

# Verificar o endpoint no kubeconfig do controller-manager
cat /etc/kubernetes/config/kube-controller-manager.kubeconfig | grep server

# Testar conectividade com o API server
curl -k https://127.0.0.1:6443/healthz

# Se o IP estiver incorreto, regenerar o kubeconfig (Passo 5 deste módulo)

# Após corrigir, reiniciar:
sudo systemctl restart kube-controller-manager
```

### Problema 4: Controller-manager não conecta ao API server — "x509: certificate signed by unknown authority"

**Sintoma:**
```
error: Get "https://10.0.1.x:6443/api/v1/namespaces": x509: certificate signed by unknown authority
```

**Causa provável:** O certificado da CA no kubeconfig do controller-manager não corresponde à CA que assinou o certificado do API server. Isso acontece quando certificados foram regenerados sem atualizar o kubeconfig.

**Resolução:**

```bash
# Verificar o issuer do certificado do API server
openssl s_client -connect 127.0.0.1:6443 -showcerts 2>/dev/null | \
  openssl x509 -noout -issuer

# Verificar o subject da CA no kubeconfig
# Extrair a CA do kubeconfig (se embed-certs foi usado)
kubectl config view --kubeconfig=/etc/kubernetes/config/kube-controller-manager.kubeconfig \
  --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | \
  base64 -d | openssl x509 -noout -subject

# Se não corresponderem, regenerar o kubeconfig com a CA correta (Passo 5)
# Após corrigir, reiniciar:
sudo systemctl restart kube-controller-manager
```

### Problema 5: Controller-manager não inicia — "bind: address already in use"

**Sintoma:**
```
error: listen tcp 0.0.0.0:10257: bind: address already in use
```

**Causa provável:** Outra instância do controller-manager ou outro processo está usando a porta 10257.

**Resolução:**

```bash
# Identificar o processo usando a porta
sudo ss -tlnp | grep 10257

# Se for uma instância antiga, mate o processo
sudo kill $(sudo ss -tlnp | grep 10257 | awk '{print $NF}' | grep -oP 'pid=\K[0-9]+')

# Ou pare qualquer instância existente
sudo systemctl stop kube-controller-manager
sudo killall kube-controller-manager 2>/dev/null

# Reiniciar o serviço
sudo systemctl start kube-controller-manager
```

### Problema 6: Controller-manager em CrashLoopBackOff — "invalid kubeconfig"

**Sintoma:**
```
error: invalid configuration: no configuration has been provided, try setting KUBERNETES_MASTER environment variable
```

Ou nos logs do systemd:
```
kube-controller-manager: error loading kubeconfig: invalid configuration: [no clusters, no users, no contexts]
```

**Causa provável:** O arquivo kubeconfig está vazio, corrompido, ou o caminho no flag `--kubeconfig` está incorreto.

**Resolução:**

```bash
# Verificar se o kubeconfig existe e não está vazio
ls -la /etc/kubernetes/config/kube-controller-manager.kubeconfig
cat /etc/kubernetes/config/kube-controller-manager.kubeconfig

# Verificar que o kubeconfig tem as seções necessárias
kubectl config view --kubeconfig=/etc/kubernetes/config/kube-controller-manager.kubeconfig

# Se estiver vazio ou corrompido, regenerar (Passo 5 deste módulo)
# Após corrigir, reiniciar:
sudo systemctl restart kube-controller-manager
```

### Problema 7: Health check falha — "/healthz retorna unhealthy"

**Sintoma:**
```bash
curl -k https://127.0.0.1:10257/healthz
# Retorna: "failed" ou erro de conexão
```

**Causa provável:** O controller-manager está rodando mas com problemas internos, ou não consegue se comunicar com o API server.

**Resolução:**

```bash
# Verificar health check detalhado
curl -k https://127.0.0.1:10257/healthz?verbose

# Verificar logs para identificar o problema específico
sudo journalctl -u kube-controller-manager --no-pager -l --since "5 minutes ago" | tail -50

# Verificar que o API server está acessível
curl -k https://127.0.0.1:6443/healthz

# Se o API server estiver saudável mas o controller-manager não:
# Reiniciar o controller-manager
sudo systemctl restart kube-controller-manager

# Aguardar 10 segundos e verificar novamente
sleep 10
curl -k https://127.0.0.1:10257/healthz
```
