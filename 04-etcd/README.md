# Módulo 04 — etcd

## Objetivo

Instalar e configurar o etcd como armazenamento de estado do cluster Kubernetes. Ao final deste módulo, você terá:

- Compreensão do papel do etcd como banco de dados distribuído do Kubernetes
- Entendimento do algoritmo de consenso Raft e do modelo de consistência
- etcd instalado e configurado como serviço systemd no nó Control Plane
- Comunicação TLS configurada entre etcd e seus clientes
- Conhecimento sobre a hierarquia de chaves usada pelo Kubernetes no etcd
- Capacidade de realizar backup e restore do etcd para disaster recovery

## Teoria

### O Papel do etcd no Kubernetes

O **etcd** é um banco de dados distribuído de chave-valor (key-value store) que serve como a **única fonte de verdade** do cluster Kubernetes. Todo o estado do cluster é armazenado no etcd:

- Definições de Pods, Services, Deployments, ConfigMaps, Secrets
- Estado dos nós (nodes) e seus recursos disponíveis
- Configurações de RBAC (Roles, RoleBindings)
- Leases de liderança dos componentes do control plane
- Estado de endpoints e service accounts

**Importante**: O etcd é o único componente de armazenamento persistente do Kubernetes. Se o etcd for perdido sem backup, todo o estado do cluster é irrecuperável.

### Arquitetura do etcd

```
┌─────────────────────────────────────────────────────────────┐
│                    Cluster Kubernetes                         │
│                                                              │
│  ┌──────────────┐         ┌──────────────────────────────┐  │
│  │kube-apiserver│◄──TLS──►│           etcd               │  │
│  │              │         │                              │  │
│  │  (único      │         │  ┌────────────────────────┐  │  │
│  │   cliente    │         │  │  /registry/            │  │  │
│  │   do etcd)   │         │  │    ├── pods/           │  │  │
│  └──────────────┘         │  │    ├── services/       │  │  │
│                           │  │    ├── deployments/    │  │  │
│                           │  │    ├── secrets/        │  │  │
│                           │  │    ├── configmaps/     │  │  │
│                           │  │    └── ...             │  │  │
│                           │  └────────────────────────┘  │  │
│                           └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Fluxo de dados:**
1. O `kube-apiserver` recebe uma requisição (ex: criar um Pod)
2. Valida a requisição (autenticação, autorização, admission controllers)
3. Persiste o objeto no etcd via gRPC + TLS
4. Retorna confirmação ao cliente
5. Outros componentes (scheduler, controller-manager) observam mudanças via watch API

> **Nota**: Apenas o kube-apiserver se comunica diretamente com o etcd. Nenhum outro componente do Kubernetes acessa o etcd diretamente.

### Consenso Raft

O etcd utiliza o algoritmo de consenso **Raft** para garantir consistência dos dados em ambientes distribuídos (múltiplos nós etcd). Mesmo no nosso lab com um único nó, é importante entender como funciona:

**Conceitos fundamentais do Raft:**

| Conceito | Descrição |
|----------|-----------|
| **Leader** | Nó responsável por processar todas as escritas. Replica dados para os followers. |
| **Follower** | Nó que replica dados do leader. Pode atender leituras (dependendo da configuração). |
| **Candidate** | Estado temporário durante uma eleição de novo leader. |
| **Term** | Período de tempo com um leader eleito. Incrementa a cada nova eleição. |
| **Log** | Sequência ordenada de entradas que representam mudanças de estado. |
| **Quorum** | Maioria dos nós necessária para confirmar uma escrita (N/2 + 1). |

**Como funciona uma escrita:**

1. O cliente envia uma escrita ao **leader**
2. O leader adiciona a entrada ao seu log
3. O leader replica a entrada para os **followers**
4. Quando a **maioria** (quorum) confirma, a entrada é "committed"
5. O leader aplica a entrada à state machine e responde ao cliente

**No nosso lab**: Usamos um único nó etcd (single-node), então o quorum é 1 e o nó é sempre o leader. Em produção, recomenda-se 3 ou 5 nós para tolerância a falhas.

### Modelo de Consistência

O etcd oferece **linearizabilidade** (linearizable reads/writes):

- **Escritas**: Sempre processadas pelo leader, garantindo ordem total
- **Leituras linearizáveis**: Refletem o estado mais recente (passam pelo leader)
- **Leituras serializáveis**: Podem retornar dados ligeiramente desatualizados (mais rápidas, atendidas por qualquer nó)

O Kubernetes usa leituras linearizáveis por padrão para garantir consistência.

### Hierarquia de Chaves do Kubernetes no etcd

O Kubernetes armazena todos os objetos sob o prefixo `/registry/`. A estrutura segue o padrão:

```
/registry/<tipo-recurso>/<namespace>/<nome>
```

**Exemplos de chaves:**

| Chave | Conteúdo |
|-------|----------|
| `/registry/pods/default/nginx` | Definição do Pod "nginx" no namespace "default" |
| `/registry/services/specs/kube-system/kube-dns` | Spec do Service "kube-dns" no namespace "kube-system" |
| `/registry/deployments/default/my-app` | Deployment "my-app" no namespace "default" |
| `/registry/secrets/default/my-secret` | Secret "my-secret" no namespace "default" |
| `/registry/namespaces/kube-system` | Definição do namespace "kube-system" |
| `/registry/clusterroles/cluster-admin` | ClusterRole "cluster-admin" (sem namespace) |

**Operações de leitura e escrita:**

- **PUT (escrita)**: Cria ou atualiza uma chave com um valor (objeto Kubernetes serializado em protobuf)
- **GET (leitura)**: Recupera o valor de uma chave específica
- **GET com prefixo**: Lista todos os objetos de um tipo (ex: todos os pods)
- **WATCH**: Observa mudanças em uma chave ou prefixo (usado pelo apiserver para notificar componentes)
- **DELETE**: Remove uma chave (quando um objeto é deletado)
- **Transação (Txn)**: Operações atômicas condicionais (compare-and-swap)

### Importância do Backup

Como o etcd contém **todo o estado do cluster**, backups regulares são essenciais:

- **Sem backup**: Perda do etcd = perda total do cluster (pods, services, secrets, tudo)
- **Com backup**: É possível restaurar o cluster para um estado anterior
- **Recomendação**: Backups automáticos a cada 30 minutos em produção
- **Armazenamento**: Backups devem ser armazenados fora do nó etcd (ex: S3, outro servidor)

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 00 — Pré-requisitos](../00-prerequisites/) — ferramentas básicas instaladas
- [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/) — instâncias EC2 provisionadas
- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — certificados do etcd gerados e distribuídos

Você precisará dos seguintes itens do módulo anterior:

- Certificado do servidor etcd (`/etc/etcd/pki/etcd-server.pem`)
- Chave privada do servidor etcd (`/etc/etcd/pki/etcd-server-key.pem`)
- Certificado da CA (`/etc/etcd/pki/ca.pem`)
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

### 2. Baixar o Binário do etcd

Baixe a versão específica do etcd (3.5.11) do repositório oficial do GitHub. O pacote inclui tanto o servidor `etcd` quanto a ferramenta de linha de comando `etcdctl`:

```bash
# Definir a versão do etcd
ETCD_VERSION="3.5.11"

# Baixar o pacote do etcd
wget -q --show-progress \
  "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz"
```

**Saída esperada:**
```
etcd-v3.5.11-linux-amd64.tar.gz  100%[===================>]  22.1M  10.5MB/s    in 2.1s
```

### 3. Extrair e Instalar os Binários

Extraia o pacote e mova os binários para um diretório no PATH do sistema:

```bash
# Extrair o pacote
tar -xzf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz

# Mover binários para /usr/local/bin
sudo mv etcd-v${ETCD_VERSION}-linux-amd64/etcd /usr/local/bin/
sudo mv etcd-v${ETCD_VERSION}-linux-amd64/etcdctl /usr/local/bin/
sudo mv etcd-v${ETCD_VERSION}-linux-amd64/etcdutl /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

Verifique que os binários foram instalados corretamente:

```bash
# Verificar versão do etcd
etcd --version
```

**Saída esperada:**
```
etcd Version: 3.5.11
Git SHA: e7c1ef7e4
Go Version: go1.21.5
Go OS/Arch: linux/amd64
```

```bash
# Verificar versão do etcdctl
etcdctl version
```

**Saída esperada:**
```
etcdctl version: 3.5.11
API version: 3.5
```

### 4. Limpar Arquivos Temporários

Remova o pacote baixado e o diretório extraído que não são mais necessários:

```bash
# Limpar arquivos temporários
rm -rf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz etcd-v${ETCD_VERSION}-linux-amd64/
```

**Saída esperada:** Nenhuma saída indica sucesso.

### 5. Criar Diretório de Dados do etcd

O etcd armazena todos os dados (WAL logs, snapshots, membros) em um diretório dedicado. Este diretório deve ter permissões restritas:

```bash
# Criar diretório de dados do etcd
sudo mkdir -p /var/lib/etcd

# Definir permissões restritas (apenas root pode acessar)
sudo chmod 700 /var/lib/etcd
```

**Saída esperada:** Nenhuma saída indica sucesso.

**Explicação:**
- `/var/lib/etcd` — diretório padrão para dados do etcd
- `chmod 700` — apenas o owner (root) pode ler, escrever e acessar. Isso protege os dados do cluster que incluem Secrets em texto claro.

### 6. Verificar Certificados TLS

Antes de configurar o etcd, confirme que os certificados necessários estão no lugar correto:

```bash
# Verificar presença dos certificados do etcd
ls -la /etc/etcd/pki/
```

**Saída esperada:**
```
total 20
drwxr-xr-x 2 root root 4096 Jan  1 00:00 .
drwxr-xr-x 3 root root 4096 Jan  1 00:00 ..
-rw-r--r-- 1 root root 1318 Jan  1 00:00 ca.pem
-rw------- 1 root root 1675 Jan  1 00:00 etcd-server-key.pem
-rw-r--r-- 1 root root 1399 Jan  1 00:00 etcd-server.pem
```

Se os arquivos não estiverem presentes, volte ao [Módulo 02](../02-tls-certificates/) e execute a distribuição de certificados.

### 7. Obter o IP Interno do Nó

O etcd precisa saber o IP interno do nó para configurar as URLs de escuta e anúncio:

```bash
# Obter o IP interno do nó
INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo "IP interno: ${INTERNAL_IP}"
```

**Saída esperada:**
```
IP interno: 10.0.1.x
```

### 8. Criar o Arquivo de Serviço systemd

Crie o unit file do systemd para gerenciar o etcd como um serviço do sistema. Este arquivo define como o etcd é iniciado, com quais parâmetros, e como o systemd deve gerenciá-lo:

```bash
# Criar unit file do etcd
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name=etcd-server \\
  --data-dir=/var/lib/etcd \\
  --listen-client-urls=https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls=https://${INTERNAL_IP}:2379 \\
  --listen-peer-urls=https://${INTERNAL_IP}:2380 \\
  --initial-advertise-peer-urls=https://${INTERNAL_IP}:2380 \\
  --initial-cluster=etcd-server=https://${INTERNAL_IP}:2380 \\
  --initial-cluster-token=etcd-cluster-lab \\
  --initial-cluster-state=new \\
  --cert-file=/etc/etcd/pki/etcd-server.pem \\
  --key-file=/etc/etcd/pki/etcd-server-key.pem \\
  --trusted-ca-file=/etc/etcd/pki/ca.pem \\
  --client-cert-auth=true \\
  --peer-cert-file=/etc/etcd/pki/etcd-server.pem \\
  --peer-key-file=/etc/etcd/pki/etcd-server-key.pem \\
  --peer-trusted-ca-file=/etc/etcd/pki/ca.pem \\
  --peer-client-cert-auth=true
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

**Saída esperada:** O conteúdo do unit file será exibido no terminal (comportamento do `tee`).

### 9. Explicação dos Parâmetros de Configuração

Cada flag do etcd tem um propósito específico. Entender cada uma é fundamental para troubleshooting:

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `--name` | `etcd-server` | Nome único deste membro no cluster etcd. Usado para identificação interna. |
| `--data-dir` | `/var/lib/etcd` | Diretório onde o etcd armazena dados persistentes (WAL logs, snapshots, member info). Deve ter permissão 700. |
| `--listen-client-urls` | `https://${IP}:2379,https://127.0.0.1:2379` | URLs nas quais o etcd escuta conexões de clientes (kube-apiserver). Inclui IP interno e localhost para acesso local com etcdctl. |
| `--advertise-client-urls` | `https://${IP}:2379` | URLs que o etcd anuncia para clientes se conectarem. Clientes usam estas URLs para descobrir o etcd. |
| `--listen-peer-urls` | `https://${IP}:2380` | URLs nas quais o etcd escuta conexões de outros membros do cluster (peer-to-peer). Porta 2380 é padrão para comunicação entre peers. |
| `--initial-advertise-peer-urls` | `https://${IP}:2380` | URLs que este membro anuncia para outros membros se conectarem a ele. |
| `--initial-cluster` | `etcd-server=https://${IP}:2380` | Lista de todos os membros do cluster no formato `nome=url`. Para single-node, apenas este membro. |
| `--initial-cluster-token` | `etcd-cluster-lab` | Token único que identifica este cluster. Previne que membros de clusters diferentes se juntem acidentalmente. |
| `--initial-cluster-state` | `new` | Estado inicial do cluster: `new` para um cluster novo, `existing` para adicionar membro a cluster existente. |
| `--cert-file` | `/etc/etcd/pki/etcd-server.pem` | Certificado TLS do servidor etcd. Apresentado aos clientes para autenticação do servidor. |
| `--key-file` | `/etc/etcd/pki/etcd-server-key.pem` | Chave privada correspondente ao certificado do servidor. |
| `--trusted-ca-file` | `/etc/etcd/pki/ca.pem` | Certificado da CA usada para validar certificados de clientes. Clientes devem apresentar certificado assinado por esta CA. |
| `--client-cert-auth` | `true` | Exige que clientes apresentem um certificado válido (mTLS). Sem isso, qualquer cliente poderia acessar o etcd. |
| `--peer-cert-file` | `/etc/etcd/pki/etcd-server.pem` | Certificado TLS para comunicação entre peers (membros do cluster). |
| `--peer-key-file` | `/etc/etcd/pki/etcd-server-key.pem` | Chave privada para comunicação entre peers. |
| `--peer-trusted-ca-file` | `/etc/etcd/pki/ca.pem` | CA usada para validar certificados de outros peers. |
| `--peer-client-cert-auth` | `true` | Exige autenticação mútua TLS entre peers do cluster. |

**Parâmetros do systemd unit file:**

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `Type=notify` | — | O etcd notifica o systemd quando está pronto para aceitar conexões. |
| `Restart=on-failure` | — | Reinicia automaticamente se o processo falhar (exit code ≠ 0). |
| `RestartSec=5` | — | Aguarda 5 segundos antes de reiniciar após falha. |
| `LimitNOFILE=65536` | — | Aumenta o limite de file descriptors abertos (etcd usa muitos para watches). |

### 10. Iniciar o Serviço etcd

Recarregue a configuração do systemd e inicie o etcd:

```bash
# Recarregar configuração do systemd
sudo systemctl daemon-reload

# Habilitar o etcd para iniciar no boot
sudo systemctl enable etcd

# Iniciar o serviço etcd
sudo systemctl start etcd
```

**Saída esperada:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/etcd.service → /etc/systemd/system/etcd.service.
```

Verifique que o serviço está rodando:

```bash
# Verificar status do serviço
sudo systemctl status etcd
```

**Saída esperada:**
```
● etcd.service - etcd
     Loaded: loaded (/etc/systemd/system/etcd.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 5s ago
       Docs: https://github.com/etcd-io/etcd
   Main PID: 1234 (etcd)
      Tasks: 8 (limit: 1024)
     Memory: 25.0M
        CPU: 200ms
     CGroup: /system.slice/etcd.service
             └─1234 /usr/local/bin/etcd --name=etcd-server ...
```

**Linhas-chave para confirmar sucesso:**
- `Active: active (running)` — o serviço está rodando
- `enabled` — configurado para iniciar no boot

## Verificação

### 1. Verificar Saúde do Endpoint

Use o `etcdctl` para verificar que o etcd está saudável e respondendo. Os flags TLS são necessários porque configuramos autenticação mútua:

```bash
# Verificar saúde do endpoint
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada:**
```
https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 1.234ms
```

**Explicação dos flags do etcdctl:**
- `ETCDCTL_API=3` — usa a API v3 do etcd (obrigatória para Kubernetes)
- `--endpoints` — URL do etcd para conectar
- `--cacert` — CA para validar o certificado do servidor
- `--cert` — certificado de cliente para autenticação
- `--key` — chave privada do certificado de cliente

### 2. Listar Membros do Cluster

Verifique os membros do cluster etcd. No nosso lab single-node, haverá apenas um membro:

```bash
# Listar membros do cluster
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem \
  --write-out=table
```

**Saída esperada:**
```
+------------------+---------+-------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |    NAME     |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-------------+----------------------------+----------------------------+------------+
| 8e9e05c52164694d | started | etcd-server | https://10.0.1.x:2380      | https://10.0.1.x:2379      |      false |
+------------------+---------+-------------+----------------------------+----------------------------+------------+
```

**Linhas-chave:**
- `STATUS: started` — o membro está ativo
- `IS LEARNER: false` — é um membro votante (não um learner/observador)

### 3. Testar Operações de Leitura e Escrita

Verifique que o etcd aceita operações de escrita e leitura corretamente:

```bash
# Escrever um valor de teste
sudo ETCDCTL_API=3 etcdctl put /test/hello "world" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada:**
```
OK
```

```bash
# Ler o valor de teste
sudo ETCDCTL_API=3 etcdctl get /test/hello \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada:**
```
/test/hello
world
```

A primeira linha é a chave e a segunda é o valor. Isso confirma que o etcd está aceitando escritas e leituras corretamente.

```bash
# Limpar o valor de teste (opcional)
sudo ETCDCTL_API=3 etcdctl del /test/hello \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada:**
```
1
```

O número `1` indica que uma chave foi deletada com sucesso.

### 4. Verificar o Prefixo /registry (Após Instalação do kube-apiserver)

Após o kube-apiserver ser instalado e conectado ao etcd (Módulo 05), você poderá verificar os objetos do Kubernetes armazenados:

```bash
# Listar chaves sob /registry (executar após módulo 05)
sudo ETCDCTL_API=3 etcdctl get /registry --prefix --keys-only --limit=20 \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada (após apiserver conectado):**
```
/registry/apiregistration.k8s.io/apiservices/v1.
/registry/apiregistration.k8s.io/apiservices/v1.apps
/registry/apiregistration.k8s.io/apiservices/v1.authentication.k8s.io
/registry/clusterrolebindings/cluster-admin
/registry/clusterroles/cluster-admin
/registry/namespaces/default
/registry/namespaces/kube-node-lease
/registry/namespaces/kube-public
/registry/namespaces/kube-system
/registry/serviceaccounts/default/default
...
```

Isso demonstra como o Kubernetes organiza seus objetos no etcd sob o prefixo `/registry/`.

### 5. Backup do etcd — Snapshot Save

O backup do etcd é feito através de snapshots. Um snapshot captura o estado completo do etcd em um único arquivo:

```bash
# Criar diretório para backups
sudo mkdir -p /var/lib/etcd-backups

# Realizar snapshot backup
sudo ETCDCTL_API=3 etcdctl snapshot save /var/lib/etcd-backups/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada:**
```
{"level":"info","ts":"2024-01-01T00:00:00.000Z","caller":"snapshot/v3_snapshot.go:65","msg":"created temporary db file","path":"/var/lib/etcd-backups/etcd-snapshot.db.part"}
{"level":"info","ts":"2024-01-01T00:00:00.000Z","caller":"snapshot/v3_snapshot.go:75","msg":"fetching snapshot","endpoint":"https://127.0.0.1:2379"}
{"level":"info","ts":"2024-01-01T00:00:00.000Z","caller":"snapshot/v3_snapshot.go:90","msg":"fetched snapshot","endpoint":"https://127.0.0.1:2379","size":"20 kB","took":"10ms"}
{"level":"info","ts":"2024-01-01T00:00:00.000Z","caller":"snapshot/v3_snapshot.go:99","msg":"saved","path":"/var/lib/etcd-backups/etcd-snapshot.db"}
Snapshot saved at /var/lib/etcd-backups/etcd-snapshot.db
```

### 6. Verificar Integridade do Snapshot

Após criar o backup, verifique que o snapshot está íntegro e contém dados válidos:

```bash
# Verificar status do snapshot
sudo ETCDCTL_API=3 etcdctl snapshot status /var/lib/etcd-backups/etcd-snapshot.db \
  --write-out=table
```

**Saída esperada:**
```
+---------+----------+------------+------------+
|  HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+---------+----------+------------+------------+
| 3c28abc |        4 |          9 |      20 kB |
+---------+----------+------------+------------+
```

**Explicação dos campos:**
- `HASH` — hash de integridade do snapshot
- `REVISION` — revisão do etcd no momento do snapshot
- `TOTAL KEYS` — número total de chaves no snapshot
- `TOTAL SIZE` — tamanho do snapshot em disco

### 7. Restore do etcd a partir de Snapshot

O restore cria um **novo diretório de dados** a partir do snapshot. O etcd original não é modificado. Após o restore, você deve apontar o etcd para o novo diretório.

> **Atenção**: O restore deve ser feito com o etcd **parado**. Em produção, isso causa downtime do cluster.

```bash
# Parar o serviço etcd
sudo systemctl stop etcd

# Restaurar snapshot para um novo diretório de dados
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-backups/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored \
  --name=etcd-server \
  --initial-cluster=etcd-server=https://${INTERNAL_IP}:2380 \
  --initial-cluster-token=etcd-cluster-lab \
  --initial-advertise-peer-urls=https://${INTERNAL_IP}:2380
```

**Saída esperada:**
```
{"level":"info","ts":"2024-01-01T00:00:00.000Z","caller":"snapshot/v3_snapshot.go:250","msg":"restoring snapshot","path":"/var/lib/etcd-backups/etcd-snapshot.db"}
{"level":"info","ts":"2024-01-01T00:00:00.000Z","caller":"membership/cluster.go:392","msg":"added member","cluster-id":"...","local-member-id":"...","added-peer-id":"..."}
{"level":"info","ts":"2024-01-01T00:00:00.000Z","caller":"snapshot/v3_snapshot.go:271","msg":"restored snapshot","path":"/var/lib/etcd-backups/etcd-snapshot.db"}
```

**Explicação dos parâmetros do restore:**

| Parâmetro | Descrição |
|-----------|-----------|
| `--data-dir` | Novo diretório onde os dados restaurados serão escritos. Não use o diretório original para evitar corrupção. |
| `--name` | Nome do membro (deve ser o mesmo usado na configuração original). |
| `--initial-cluster` | Configuração do cluster (deve corresponder à configuração original). |
| `--initial-cluster-token` | Token do cluster (deve corresponder ao original). |
| `--initial-advertise-peer-urls` | URLs de peer (deve corresponder à configuração original). |

Para usar o diretório restaurado, atualize o `--data-dir` no unit file do etcd:

```bash
# Fazer backup do diretório de dados antigo
sudo mv /var/lib/etcd /var/lib/etcd-old

# Mover o diretório restaurado para o local original
sudo mv /var/lib/etcd-restored /var/lib/etcd

# Garantir permissões corretas
sudo chmod 700 /var/lib/etcd

# Reiniciar o etcd
sudo systemctl start etcd
```

**Saída esperada:** Nenhuma saída indica sucesso.

Verifique que o etcd está saudável após o restore:

```bash
# Verificar saúde após restore
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

**Saída esperada:**
```
https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 1.567ms
```

## Troubleshooting

### Problema 1: etcd não inicia — "permission denied" no data-dir

**Sintoma:**
```
Error: cannot access data directory: open /var/lib/etcd/member: permission denied
```

**Causa provável:** O diretório de dados não tem as permissões corretas ou pertence a outro usuário.

**Resolução:**

```bash
# Verificar permissões atuais
ls -la /var/lib/ | grep etcd

# Corrigir permissões
sudo chmod 700 /var/lib/etcd
sudo chown root:root /var/lib/etcd

# Reiniciar o serviço
sudo systemctl restart etcd
```

### Problema 2: etcd não inicia — "tls: failed to find any PEM data"

**Sintoma:**
```
embed: rejected connection from "127.0.0.1:xxxxx" (error "tls: failed to find any PEM data in certificate input", ServerName "")
```

**Causa provável:** O caminho do certificado está incorreto ou o arquivo está vazio/corrompido.

**Resolução:**

```bash
# Verificar que os arquivos de certificado existem e não estão vazios
ls -la /etc/etcd/pki/
file /etc/etcd/pki/etcd-server.pem
file /etc/etcd/pki/etcd-server-key.pem
file /etc/etcd/pki/ca.pem

# Verificar conteúdo do certificado
openssl x509 -in /etc/etcd/pki/etcd-server.pem -text -noout | head -20

# Se o certificado estiver corrompido, regenere-o (voltar ao Módulo 02)
# Após corrigir, reiniciar:
sudo systemctl restart etcd
```

### Problema 3: etcd não inicia — "address already in use"

**Sintoma:**
```
listen tcp 10.0.1.x:2379: bind: address already in use
```

**Causa provável:** Outra instância do etcd ou outro processo está usando a porta 2379 ou 2380.

**Resolução:**

```bash
# Identificar o processo usando a porta
sudo ss -tlnp | grep -E '2379|2380'

# Se for uma instância antiga do etcd, mate o processo
sudo kill $(sudo ss -tlnp | grep 2379 | awk '{print $NF}' | grep -oP 'pid=\K[0-9]+')

# Ou pare qualquer serviço etcd existente
sudo systemctl stop etcd
sudo killall etcd 2>/dev/null

# Reiniciar o serviço
sudo systemctl start etcd
```

### Problema 4: etcdctl retorna "context deadline exceeded"

**Sintoma:**
```
{"level":"warn","ts":"...","msg":"health check failed","endpoint":"https://127.0.0.1:2379","error":"context deadline exceeded"}
```

**Causa provável:** O etcd não está rodando, ou os certificados TLS usados pelo etcdctl não correspondem aos configurados no servidor.

**Resolução:**

```bash
# Verificar se o etcd está rodando
sudo systemctl status etcd

# Verificar logs do etcd para erros
sudo journalctl -u etcd --no-pager -l --since "5 minutes ago"

# Verificar que os certificados do etcdctl são os mesmos do servidor
openssl x509 -in /etc/etcd/pki/etcd-server.pem -noout -issuer
openssl x509 -in /etc/etcd/pki/ca.pem -noout -subject

# O issuer do certificado deve corresponder ao subject da CA
# Se não corresponder, os certificados foram gerados por CAs diferentes

# Reiniciar o etcd após correções
sudo systemctl restart etcd
```

### Problema 5: Backup falha — "snapshot file already exists"

**Sintoma:**
```
Error: snapshot file "/var/lib/etcd-backups/etcd-snapshot.db" already exists
```

**Causa provável:** Já existe um arquivo de snapshot no caminho especificado. O etcdctl não sobrescreve snapshots existentes por segurança.

**Resolução:**

```bash
# Opção 1: Usar um nome de arquivo com timestamp
sudo ETCDCTL_API=3 etcdctl snapshot save \
  /var/lib/etcd-backups/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem

# Opção 2: Remover o snapshot antigo (se não for mais necessário)
sudo rm /var/lib/etcd-backups/etcd-snapshot.db

# Então executar o backup novamente
```

### Problema 6: Restore falha — "data-dir already exists"

**Sintoma:**
```
Error: data-dir "/var/lib/etcd-restored" already exists
```

**Causa provável:** O diretório de destino do restore já existe. O etcdctl não sobrescreve diretórios existentes para evitar perda de dados.

**Resolução:**

```bash
# Remover o diretório de restore anterior (se não for necessário)
sudo rm -rf /var/lib/etcd-restored

# Executar o restore novamente
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-backups/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored \
  --name=etcd-server \
  --initial-cluster=etcd-server=https://${INTERNAL_IP}:2380 \
  --initial-cluster-token=etcd-cluster-lab \
  --initial-advertise-peer-urls=https://${INTERNAL_IP}:2380
```

### Problema 7: Restore falha — "snapshot corrupt: missing hash"

**Sintoma:**
```
Error: expected sha256 hash, got none: snapshot file appears to be corrupt
```

**Causa provável:** O arquivo de snapshot está corrompido (download incompleto, disco com erro, ou arquivo truncado).

**Resolução:**

```bash
# Verificar integridade do snapshot
sudo ETCDCTL_API=3 etcdctl snapshot status /var/lib/etcd-backups/etcd-snapshot.db

# Se falhar, o snapshot está corrompido. Use um backup anterior:
ls -la /var/lib/etcd-backups/

# Criar um novo snapshot (se o etcd ainda estiver rodando)
sudo ETCDCTL_API=3 etcdctl snapshot save /var/lib/etcd-backups/etcd-snapshot-new.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.pem \
  --cert=/etc/etcd/pki/etcd-server.pem \
  --key=/etc/etcd/pki/etcd-server-key.pem
```

### Problema 8: etcd não inicia após restore — "member count is unequal"

**Sintoma:**
```
rafthttp: failed to find member ... in cluster
```

**Causa provável:** Os parâmetros `--initial-cluster`, `--name`, ou `--initial-cluster-token` usados no restore não correspondem à configuração original do etcd.

**Resolução:**

```bash
# Verificar a configuração atual do unit file
cat /etc/systemd/system/etcd.service | grep -E 'name|initial-cluster'

# Os valores no restore DEVEM corresponder exatamente aos do unit file:
# --name deve ser igual ao --name do unit file
# --initial-cluster deve ser igual ao --initial-cluster do unit file
# --initial-cluster-token deve ser igual ao --initial-cluster-token do unit file

# Se necessário, refazer o restore com os parâmetros corretos
sudo systemctl stop etcd
sudo rm -rf /var/lib/etcd
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-backups/etcd-snapshot.db \
  --data-dir=/var/lib/etcd \
  --name=etcd-server \
  --initial-cluster=etcd-server=https://${INTERNAL_IP}:2380 \
  --initial-cluster-token=etcd-cluster-lab \
  --initial-advertise-peer-urls=https://${INTERNAL_IP}:2380

sudo chmod 700 /var/lib/etcd
sudo systemctl start etcd
```

### Problema 9: Certificado TLS com SAN incorreto

**Sintoma:**
```
transport: authentication handshake failed: x509: certificate is valid for 10.0.1.100, not 10.0.1.200
```

**Causa provável:** O IP do nó mudou (ex: após reiniciar a instância EC2) e não corresponde mais aos SANs do certificado do etcd.

**Resolução:**

```bash
# Verificar os SANs do certificado atual
openssl x509 -in /etc/etcd/pki/etcd-server.pem -noout -text | grep -A1 "Subject Alternative Name"

# Verificar o IP atual do nó
hostname -I

# Se o IP mudou, você precisa regenerar o certificado do etcd
# com o novo IP nos SANs (voltar ao Módulo 02)
# Após regenerar e copiar o novo certificado:
sudo systemctl restart etcd
```

### Diagnóstico Geral — Verificar Logs do etcd

Para qualquer problema não listado acima, os logs do etcd são a melhor fonte de informação:

```bash
# Ver logs recentes do etcd
sudo journalctl -u etcd --no-pager -l --since "10 minutes ago"

# Ver logs em tempo real (Ctrl+C para sair)
sudo journalctl -u etcd -f

# Filtrar apenas erros e warnings
sudo journalctl -u etcd --no-pager -l -p err
```

**Padrão de troubleshooting:**
1. **Identificar** — `sudo systemctl status etcd` (verificar se está rodando)
2. **Diagnosticar** — `sudo journalctl -u etcd --no-pager -l` (ler logs de erro)
3. **Resolver** — aplicar a correção específica para o erro encontrado
4. **Verificar** — `etcdctl endpoint health` (confirmar que voltou ao normal)
