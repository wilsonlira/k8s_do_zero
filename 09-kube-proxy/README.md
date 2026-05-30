# Módulo 09 — kube-proxy

## Objetivo

Instalar e configurar o kube-proxy nos worker nodes do cluster Kubernetes. Ao final deste módulo, você terá:

- Compreensão do papel do kube-proxy na manutenção de regras de rede para comunicação entre Services
- Entendimento de como o kube-proxy observa o API server para mudanças em Services e Endpoints
- Conhecimento dos modos de proxy (iptables vs IPVS) e seus trade-offs
- kube-proxy instalado e configurado como serviço systemd no Worker Node
- Capacidade de verificar regras de rede criadas e acessibilidade de ClusterIP Services

## Teoria

### O Papel do kube-proxy no Kubernetes

O **kube-proxy** é o componente de rede executado em cada nó do cluster, responsável por **manter regras de rede que permitem a comunicação com os Pods através de Services**. Ele é o mecanismo que torna os Services do Kubernetes funcionais no nível de rede.

Quando você cria um Service no Kubernetes (ex: `kubectl expose deployment nginx --port=80`), o Service recebe um **ClusterIP** — um IP virtual que não pertence a nenhuma interface de rede real. O kube-proxy é quem faz a "mágica" de traduzir requisições destinadas a esse IP virtual em conexões reais para os Pods backend.

**Responsabilidades do kube-proxy:**

1. **Observar (watch) o API server** — monitora continuamente mudanças em objetos Service e Endpoint/EndpointSlice
2. **Traduzir Services em regras de rede** — converte a definição abstrata de um Service em regras concretas (iptables ou IPVS) no nó
3. **Balancear carga** — distribui tráfego entre os Pods backend de um Service
4. **Manter regras atualizadas** — quando Pods são criados/removidos, atualiza as regras automaticamente

**Fluxo de funcionamento:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Fluxo do kube-proxy                                    │
│                                                                          │
│  ┌──────────────┐    ┌───────────────┐    ┌──────────────────────────┐  │
│  │kube-apiserver│◄───│  kube-proxy   │───►│  Regras de Rede (nó)     │  │
│  │              │    │               │    │                          │  │
│  │  Service     │    │  1. Watch     │    │  iptables / IPVS rules   │  │
│  │  criado/     │    │  2. Traduzir  │    │                          │  │
│  │  atualizado  │    │  3. Aplicar   │    │  ClusterIP → Pod IPs     │  │
│  └──────────────┘    └───────────────┘    └──────────────────────────┘  │
│                                                                          │
│  Exemplo: Service "nginx-svc" (ClusterIP 10.96.0.100:80)                │
│           → Pod 10.244.0.5:80, Pod 10.244.0.6:80                        │
│                                                                          │
│  Quando um Pod acessa 10.96.0.100:80, o kube-proxy redireciona          │
│  para um dos Pods backend (10.244.0.5 ou 10.244.0.6)                    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Como o kube-proxy Observa Services e Endpoints

O kube-proxy utiliza o mecanismo de **watch** do Kubernetes API para monitorar dois tipos de objetos:

#### 1. Services

Quando um Service é criado, atualizado ou removido, o kube-proxy recebe uma notificação e atualiza as regras de rede correspondentes.

**Informações extraídas do Service:**
- ClusterIP (IP virtual do Service)
- Portas (port, targetPort, protocol)
- Tipo (ClusterIP, NodePort, LoadBalancer)
- Session affinity (se configurada)

#### 2. Endpoints / EndpointSlices

Os Endpoints representam os Pods reais que estão por trás de um Service. O kube-controller-manager mantém os Endpoints atualizados baseado nos label selectors do Service.

**Informações extraídas dos Endpoints:**
- IPs dos Pods backend
- Portas dos containers
- Estado de readiness de cada Pod

**Ciclo de atualização:**

1. Um Deployment cria 3 réplicas de nginx
2. O kube-controller-manager cria um Endpoint com os 3 IPs dos Pods
3. O kube-proxy detecta o novo Endpoint via watch
4. O kube-proxy cria regras de rede mapeando o ClusterIP para os 3 IPs dos Pods
5. Se um Pod morre, o Endpoint é atualizado e o kube-proxy remove a regra correspondente

### Modos de Proxy

O kube-proxy suporta diferentes modos de operação para implementar as regras de rede. Cada modo tem características distintas em termos de desempenho, escalabilidade e funcionalidades.

#### Modo iptables (Padrão)

O modo **iptables** é o modo padrão desde o Kubernetes 1.2. Neste modo, o kube-proxy programa regras diretamente nas tabelas do netfilter (iptables) do kernel Linux.

**Como funciona:**
1. Para cada Service/porta, o kube-proxy cria regras na chain `KUBE-SERVICES`
2. Para cada Endpoint, cria regras na chain `KUBE-SEP-*` (Service Endpoint)
3. O balanceamento é feito via módulo `statistic` do iptables (probabilidade aleatória)
4. O kernel processa os pacotes diretamente — sem passagem pelo userspace

**Vantagens:**
- Simples e estável — modo padrão há muitas versões
- Não requer módulos adicionais do kernel
- Funciona em qualquer distribuição Linux moderna
- Menor overhead de memória para clusters pequenos

**Desvantagens:**
- Desempenho degrada com muitos Services (regras são avaliadas sequencialmente — O(n))
- Não suporta algoritmos de balanceamento avançados (apenas random)
- Atualização de regras é lenta em clusters grandes (reescreve todas as regras)
- Difícil de debugar com milhares de regras

#### Modo IPVS (IP Virtual Server)

O modo **IPVS** utiliza o módulo IPVS do kernel Linux, que é projetado especificamente para balanceamento de carga no nível de transporte (Layer 4).

**Como funciona:**
1. O kube-proxy cria um servidor virtual IPVS para cada ClusterIP:porta
2. Cada Pod backend é adicionado como "real server" no IPVS
3. O kernel roteia pacotes diretamente via tabela hash — O(1)
4. Suporta múltiplos algoritmos de scheduling

**Vantagens:**
- Desempenho superior em clusters grandes (lookup O(1) via hash table)
- Suporta múltiplos algoritmos de balanceamento:
  - `rr` — Round Robin
  - `lc` — Least Connections
  - `dh` — Destination Hashing
  - `sh` — Source Hashing
  - `sed` — Shortest Expected Delay
  - `nq` — Never Queue
- Atualização incremental de regras (não reescreve tudo)
- Melhor visibilidade com `ipvsadm` para debugging

**Desvantagens:**
- Requer módulos do kernel IPVS carregados (`ip_vs`, `ip_vs_rr`, `ip_vs_wrr`, `ip_vs_sh`, `nf_conntrack`)
- Maior complexidade de configuração
- Pode não estar disponível em todos os kernels/distribuições
- Maior consumo de memória para a tabela hash

#### Comparação: iptables vs IPVS

| Característica | iptables | IPVS |
|----------------|----------|------|
| **Complexidade de lookup** | O(n) — sequencial | O(1) — hash table |
| **Escalabilidade** | Até ~5.000 Services | 10.000+ Services |
| **Algoritmos de balanceamento** | Apenas random | rr, lc, dh, sh, sed, nq |
| **Atualização de regras** | Reescreve todas | Incremental |
| **Requisitos de kernel** | Nenhum adicional | Módulos IPVS |
| **Debugging** | `iptables -L` (complexo) | `ipvsadm -Ln` (claro) |
| **Uso recomendado** | Clusters pequenos/médios | Clusters grandes |
| **Padrão no Kubernetes** | Sim (desde 1.2) | Não (opt-in) |

#### Escolha para o Lab

Neste lab, utilizaremos o modo **iptables** porque:
- É o modo padrão e mais simples de configurar
- Nosso cluster tem poucos Services (não há problema de escala)
- Não requer módulos adicionais do kernel
- É o modo mais comum em ambientes de produção pequenos/médios
- É o modo cobrado no exame CKA

> **Nota**: Em ambientes de produção com centenas de Services, considere migrar para IPVS para melhor desempenho.

### Tradução de Services em Regras de Rede

Para entender concretamente o que o kube-proxy faz, veja como um Service é traduzido em regras iptables:

**Service exemplo:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
  # ClusterIP atribuído: 10.96.0.100
```

**Regras iptables criadas pelo kube-proxy:**
```
# Chain KUBE-SERVICES — intercepta tráfego para ClusterIPs
-A KUBE-SERVICES -d 10.96.0.100/32 -p tcp --dport 80 -j KUBE-SVC-XXXXX

# Chain KUBE-SVC-XXXXX — balanceia entre endpoints
-A KUBE-SVC-XXXXX -m statistic --mode random --probability 0.5 -j KUBE-SEP-AAAAA
-A KUBE-SVC-XXXXX -j KUBE-SEP-BBBBB

# Chain KUBE-SEP-AAAAA — redireciona para Pod 1
-A KUBE-SEP-AAAAA -p tcp -j DNAT --to-destination 10.244.0.5:80

# Chain KUBE-SEP-BBBBB — redireciona para Pod 2
-A KUBE-SEP-BBBBB -p tcp -j DNAT --to-destination 10.244.0.6:80
```

Isso significa que qualquer pacote destinado a `10.96.0.100:80` será redirecionado (DNAT) para um dos Pods backend com probabilidade igual.

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — certificados gerados e distribuídos
- [Módulo 05 — kube-apiserver](../05-kube-apiserver/) — API server instalado e rodando

Você precisará dos seguintes itens dos módulos anteriores:

- Certificado da CA (`/etc/kubernetes/pki/ca.pem`)
- Certificado do kube-proxy (`/etc/kubernetes/pki/kube-proxy.pem`)
- Chave privada do kube-proxy (`/etc/kubernetes/pki/kube-proxy-key.pem`)
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

### 2. Baixar o Binário do kube-proxy

Baixe a versão 1.29.0 do kube-proxy do repositório oficial do Kubernetes:

```bash
# Definir a versão do Kubernetes
K8S_VERSION="1.29.0"

# Baixar o binário do kube-proxy
wget -q --show-progress \
  "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kube-proxy"
```

**Saída esperada:**
```
kube-proxy      100%[===================>]  46.1M  10.8MB/s    in 4.3s
```

### 3. Instalar o Binário

Torne o binário executável e mova-o para um diretório no PATH do sistema:

```bash
# Tornar executável
chmod +x kube-proxy

# Mover para /usr/local/bin
sudo mv kube-proxy /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

Verifique que o binário foi instalado corretamente:

```bash
# Verificar versão do kube-proxy
kube-proxy --version
```

**Saída esperada:**
```
Kubernetes v1.29.0
```

### 4. Gerar o Kubeconfig do kube-proxy

O kube-proxy precisa de um kubeconfig para se autenticar com o kube-apiserver. Este arquivo contém o certificado de cliente, a chave privada e o endereço do API server:

```bash
# Definir o IP do control plane (substitua pelo IP real)
CONTROL_PLANE_IP="<IP_DO_CONTROL_PLANE>"

# Gerar o kubeconfig do kube-proxy
kubectl config set-cluster k8s-lab \
  --certificate-authority=/etc/kubernetes/pki/ca.pem \
  --server=https://${CONTROL_PLANE_IP}:6443 \
  --kubeconfig=/etc/kubernetes/kubeconfig-kube-proxy.yaml

kubectl config set-credentials system:kube-proxy \
  --client-certificate=/etc/kubernetes/pki/kube-proxy.pem \
  --client-key=/etc/kubernetes/pki/kube-proxy-key.pem \
  --kubeconfig=/etc/kubernetes/kubeconfig-kube-proxy.yaml

kubectl config set-context default \
  --cluster=k8s-lab \
  --user=system:kube-proxy \
  --kubeconfig=/etc/kubernetes/kubeconfig-kube-proxy.yaml

kubectl config use-context default \
  --kubeconfig=/etc/kubernetes/kubeconfig-kube-proxy.yaml
```

**Saída esperada:**
```
Cluster "k8s-lab" set.
User "system:kube-proxy" set.
Context "default" created.
Switched to context "default".
```

**Explicação dos comandos do kubeconfig:**

| Comando | Descrição |
|---------|-----------|
| `set-cluster` | Define o cluster alvo com o endereço do API server (control plane) e o certificado da CA para validar a conexão TLS. |
| `set-credentials` | Define as credenciais do kube-proxy usando certificado de cliente e chave privada. O CN do certificado deve ser `system:kube-proxy`. |
| `set-context` | Associa o cluster às credenciais em um contexto nomeado. |
| `use-context` | Define o contexto ativo que será usado por padrão. |

### 5. Verificar o Kubeconfig Gerado

Confirme que o kubeconfig foi criado corretamente:

```bash
# Verificar conteúdo do kubeconfig (sem exibir dados sensíveis)
kubectl config view --kubeconfig=/etc/kubernetes/kubeconfig-kube-proxy.yaml
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
    user: system:kube-proxy
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: system:kube-proxy
  user:
    client-certificate: /etc/kubernetes/pki/kube-proxy.pem
    client-key: /etc/kubernetes/pki/kube-proxy-key.pem
```

### 6. Criar o Diretório de Configuração

Crie o diretório onde o kube-proxy armazenará sua configuração:

```bash
# Criar diretório de configuração do kube-proxy
sudo mkdir -p /var/lib/kube-proxy
```

**Saída esperada:** Nenhuma saída indica sucesso.

### 7. Criar o Arquivo de Configuração do kube-proxy

Crie o arquivo de configuração do kube-proxy no formato KubeProxyConfiguration. Este formato é preferido sobre flags de linha de comando por ser mais legível e versionável:

```bash
# Criar arquivo de configuração do kube-proxy
cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/kubeconfig-kube-proxy.yaml
mode: "iptables"
clusterCIDR: "10.244.0.0/16"
iptables:
  masqueradeAll: false
  masqueradeBit: 14
  minSyncPeriod: 0s
  syncPeriod: 30s
conntrack:
  maxPerCore: 32768
  min: 131072
  tcpCloseWaitTimeout: 1h0m0s
  tcpEstablishedTimeout: 24h0m0s
EOF
```

**Saída esperada:** O conteúdo do arquivo de configuração será exibido no terminal (comportamento do `tee`).

### 8. Explicação dos Parâmetros de Configuração

Cada parâmetro do kube-proxy tem um propósito específico. Entender cada um é fundamental para troubleshooting e otimização:

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `clientConnection.kubeconfig` | `/etc/kubernetes/kubeconfig-kube-proxy.yaml` | Caminho para o arquivo kubeconfig usado pelo kube-proxy para se conectar ao kube-apiserver. Contém credenciais de cliente (certificado + chave) e o endereço do API server. |
| `mode` | `"iptables"` | Modo de proxy utilizado. Define como as regras de rede são implementadas. Opções: `iptables` (padrão), `ipvs`, `userspace` (legado). No modo iptables, regras são programadas diretamente no netfilter do kernel. |
| `clusterCIDR` | `"10.244.0.0/16"` | Range de IPs usado para Pods no cluster (Pod CIDR). O kube-proxy usa esta informação para distinguir tráfego interno do cluster de tráfego externo, aplicando SNAT (masquerade) apenas quando necessário. |
| `iptables.masqueradeAll` | `false` | Se `true`, aplica masquerade (SNAT) em todo tráfego que passa pelo kube-proxy. Se `false` (padrão), aplica masquerade apenas em tráfego originado fora do cluster CIDR. |
| `iptables.masqueradeBit` | `14` | Bit usado na marca (fwmark) do pacote para indicar que precisa de masquerade. O valor 14 significa que o bit 14 do campo mark do pacote é usado para sinalização interna. |
| `iptables.minSyncPeriod` | `0s` | Intervalo mínimo entre sincronizações de regras iptables. `0s` significa que o kube-proxy sincroniza imediatamente quando detecta mudanças. Em clusters grandes, aumentar este valor reduz carga no sistema. |
| `iptables.syncPeriod` | `30s` | Intervalo máximo entre sincronizações completas de regras iptables. Mesmo sem mudanças detectadas, o kube-proxy reconcilia todas as regras a cada 30 segundos para garantir consistência. |
| `conntrack.maxPerCore` | `32768` | Número máximo de entradas na tabela conntrack por core de CPU. A tabela conntrack rastreia conexões ativas para NAT funcionar corretamente. |
| `conntrack.min` | `131072` | Número mínimo total de entradas na tabela conntrack, independente do número de cores. Garante capacidade mínima mesmo em instâncias com poucos cores (como t2.micro). |
| `conntrack.tcpCloseWaitTimeout` | `1h0m0s` | Tempo que uma conexão TCP em estado CLOSE_WAIT permanece na tabela conntrack antes de ser removida. |
| `conntrack.tcpEstablishedTimeout` | `24h0m0s` | Tempo que uma conexão TCP estabelecida (ESTABLISHED) permanece na tabela conntrack sem atividade antes de ser removida. |

### 9. Criar o Arquivo de Serviço systemd

Crie o unit file do systemd para gerenciar o kube-proxy como um serviço do sistema:

```bash
# Criar unit file do kube-proxy
cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

**Saída esperada:** O conteúdo do unit file será exibido no terminal (comportamento do `tee`).

**Explicação dos parâmetros do systemd e flags:**

| Parâmetro | Descrição |
|-----------|-----------|
| `--config` | Caminho para o arquivo de configuração KubeProxyConfiguration. Quando usado, substitui flags individuais de linha de comando. Todas as configurações são lidas deste arquivo. |
| `--proxy-mode` | Modo de proxy utilizado para implementar regras de rede. Opções: `iptables` (padrão, usa netfilter do kernel), `ipvs` (usa IP Virtual Server para melhor escalabilidade). No modo iptables, regras são programadas diretamente no netfilter. |
| `--cluster-cidr` | Range CIDR de IPs para pods no cluster (ex: `10.244.0.0/16`). O kube-proxy usa esta informação para distinguir tráfego interno do cluster de tráfego externo, aplicando masquerade (SNAT) apenas quando necessário. |
| `--conntrack-max-per-core` | Número máximo de entradas na tabela conntrack por core de CPU. O valor `0` desabilita o ajuste automático, mantendo o valor padrão do sistema. A tabela conntrack rastreia conexões ativas para NAT funcionar corretamente. |
| `--hostname-override` | Sobrescreve o hostname do nó usado pelo kube-proxy para identificar o nó no cluster. Deve corresponder ao nome do nó registrado no API server (mesmo valor usado pelo kubelet). |
| `--v=2` | Nível de verbosidade dos logs (0=mínimo, 5=máximo). Nível 2 mostra informações úteis de operação sem excesso de detalhes. |
| `After=network.target` | Garante que o serviço só inicia após a rede estar disponível. Essencial porque o kube-proxy precisa de conectividade com o API server. |
| `Restart=on-failure` | Reinicia automaticamente se o processo falhar (exit code ≠ 0). |
| `RestartSec=5` | Aguarda 5 segundos antes de reiniciar após falha. Evita loops de reinício rápido. |

### 10. Iniciar o Serviço kube-proxy

Recarregue a configuração do systemd e inicie o kube-proxy:

```bash
# Recarregar configuração do systemd
sudo systemctl daemon-reload

# Habilitar o kube-proxy para iniciar no boot
sudo systemctl enable kube-proxy

# Iniciar o serviço kube-proxy
sudo systemctl start kube-proxy
```

**Saída esperada:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/kube-proxy.service → /etc/systemd/system/kube-proxy.service.
```

Verifique que o serviço está rodando:

```bash
# Verificar status do serviço
sudo systemctl status kube-proxy
```

**Saída esperada:**
```
● kube-proxy.service - Kubernetes Kube Proxy
     Loaded: loaded (/etc/systemd/system/kube-proxy.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 5s ago
       Docs: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/
   Main PID: 3456 (kube-proxy)
      Tasks: 5 (limit: 1024)
     Memory: 15.0M
        CPU: 120ms
     CGroup: /system.slice/kube-proxy.service
             └─3456 /usr/local/bin/kube-proxy --config=/var/lib/kube-proxy/kube-proxy-config.yaml --v=2
```

**Linhas-chave para confirmar sucesso:**
- `Active: active (running)` — o serviço está rodando
- `enabled` — configurado para iniciar no boot

## Verificação

### 1. Verificar Logs do kube-proxy

Verifique os logs para confirmar que o kube-proxy iniciou corretamente e está conectado ao API server:

```bash
# Verificar logs recentes do kube-proxy
sudo journalctl -u kube-proxy --no-pager -l --since "2 minutes ago"
```

**Saída esperada (linhas-chave):**
```
kube-proxy: I0101 00:00:00.000000    3456 server_others.go:220] "Using iptables proxy"
kube-proxy: I0101 00:00:00.000000    3456 server.go:243] "kube-proxy running in dual-stack mode" ipFamily=IPv4
kube-proxy: I0101 00:00:00.000000    3456 server_others.go:269] "kube-proxy running in single-stack mode" ipFamily=IPv4
kube-proxy: I0101 00:00:00.000000    3456 conntrack.go:52] "Setting nf_conntrack_max" conntrackMax=131072
kube-proxy: I0101 00:00:00.000000    3456 config.go:188] "Starting service config controller"
kube-proxy: I0101 00:00:00.000000    3456 config.go:97] "Starting endpoint slice config controller"
```

**Linhas-chave:**
- `Using iptables proxy` — confirma que o modo iptables está ativo
- `Starting service config controller` — o kube-proxy está observando Services
- `Starting endpoint slice config controller` — o kube-proxy está observando EndpointSlices
- Ausência de linhas `E` (error) indica operação normal

### 2. Verificar Regras iptables Criadas

Após o kube-proxy iniciar, ele cria chains e regras iptables para os Services existentes. Verifique que as chains do kube-proxy foram criadas:

```bash
# Listar chains do kube-proxy na tabela nat
sudo iptables -t nat -L KUBE-SERVICES -n | head -20
```

**Saída esperada:**
```
Chain KUBE-SERVICES (2 references)
target     prot opt source               destination
KUBE-SVC-NPX46M4PTMTKRN6Y  tcp  --  0.0.0.0/0   10.96.0.1    /* default/kubernetes:https cluster IP */ tcp dpt:443
KUBE-SVC-ERIFXISQEP7F7OF4  tcp  --  0.0.0.0/0   10.96.0.10   /* kube-system/kube-dns:dns-tcp cluster IP */ tcp dpt:53
KUBE-NODEPORTS  all  --  0.0.0.0/0   0.0.0.0/0    /* kubernetes service nodeports */
```

**Explicação:**
- `KUBE-SERVICES` — chain principal que intercepta tráfego destinado a ClusterIPs
- `KUBE-SVC-*` — chains individuais para cada Service
- Os comentários indicam qual Service cada regra representa
- `10.96.0.1` é o ClusterIP do Service `kubernetes` (API server)

> **Nota**: Se o cluster ainda não tem Services além do `kubernetes`, apenas uma regra aparecerá. Mais regras serão criadas conforme Services forem adicionados.
