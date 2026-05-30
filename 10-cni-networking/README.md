# Módulo 10 — CNI Networking (Calico)

## Objetivo

Instalar e configurar um plugin CNI (Container Network Interface) para habilitar a comunicação pod-to-pod entre nós do cluster. Ao final deste módulo, você terá:

- Compreensão da especificação CNI e suas responsabilidades
- Conhecimento das diferenças entre Flannel e Calico
- Calico instalado e configurado com o pod CIDR `10.244.0.0/16`
- Comunicação pod-to-pod funcional entre Worker Nodes
- Entendimento dos modelos de rede overlay vs routed

## Teoria

### O que é CNI (Container Network Interface)?

CNI é uma especificação que define como plugins de rede devem configurar a conectividade de rede para containers. No contexto do Kubernetes, o CNI é responsável por:

1. **Atribuição de endereços IP** — cada pod recebe um IP único dentro do cluster
2. **Configuração de rotas** — garantir que pacotes entre pods sejam roteados corretamente
3. **Gerenciamento de network namespaces** — isolar a rede de cada pod em seu próprio namespace

Quando o kubelet cria um pod, ele invoca o plugin CNI configurado para:
- Criar uma interface de rede virtual (veth pair) no network namespace do pod
- Atribuir um endereço IP do range configurado (pod CIDR)
- Configurar rotas para que o pod possa se comunicar com outros pods no cluster
- Configurar regras de firewall/iptables conforme necessário

### Como o CNI se integra ao Kubernetes?

```
┌─────────────────────────────────────────────────────────────┐
│                      kubelet                                  │
│                                                              │
│  1. Recebe ordem do API Server para criar pod               │
│  2. Solicita ao container runtime (containerd) criar o pod  │
│  3. Invoca o plugin CNI para configurar a rede do pod       │
│                                                              │
│         ┌──────────────┐                                     │
│         │  CNI Plugin  │                                     │
│         │  (Calico)    │                                     │
│         └──────┬───────┘                                     │
│                │                                             │
│    ┌───────────┼───────────┐                                 │
│    │           │           │                                 │
│    ▼           ▼           ▼                                 │
│ Criar      Atribuir    Configurar                           │
│ veth pair  IP do CIDR  rotas                                │
└─────────────────────────────────────────────────────────────┘
```

O fluxo completo é:

1. O kube-scheduler atribui o pod a um nó
2. O kubelet no nó recebe a especificação do pod via API Server
3. O kubelet instrui o containerd a criar o container (sandbox)
4. O containerd cria o network namespace para o pod
5. O kubelet invoca o plugin CNI passando o network namespace
6. O plugin CNI configura a interface de rede, atribui IP e configura rotas
7. O pod está pronto para comunicação de rede

### Modelo de Rede do Kubernetes

O Kubernetes impõe três requisitos fundamentais de rede:

1. **Pod-to-Pod**: Todos os pods podem se comunicar entre si sem NAT
2. **Node-to-Pod**: Todos os nós podem se comunicar com todos os pods sem NAT
3. **Pod IP consistente**: O IP que um pod vê para si mesmo é o mesmo IP que outros pods veem

Esses requisitos criam uma rede "flat" onde cada pod tem um IP roteável dentro do cluster. O plugin CNI é responsável por implementar essa rede.

### Overlay vs Routed Networking

Existem dois modelos principais de implementação de rede para clusters Kubernetes:

#### Overlay Network (Rede Sobreposta)

- Encapsula pacotes de pod dentro de pacotes UDP/VXLAN entre nós
- Os nós da rede subjacente não precisam conhecer os IPs dos pods
- **Vantagem**: Funciona em qualquer infraestrutura sem configuração de rede especial
- **Desvantagem**: Overhead de encapsulamento (cabeçalhos extras, latência adicional)
- **Exemplo**: Flannel com backend VXLAN

```
Pod A (10.244.0.5) → [Encapsulamento VXLAN] → Rede do Host → [Desencapsulamento] → Pod B (10.244.1.3)
```

#### Routed Network (Rede Roteada)

- Usa rotas IP nativas (BGP ou rotas estáticas) para direcionar tráfego entre nós
- Os roteadores da rede conhecem os ranges de IP dos pods em cada nó
- **Vantagem**: Sem overhead de encapsulamento, melhor performance
- **Desvantagem**: Requer suporte da infraestrutura de rede (BGP ou configuração de rotas)
- **Exemplo**: Calico com BGP peering

```
Pod A (10.244.0.5) → [Rota BGP direta] → Rede do Host → [Rota BGP] → Pod B (10.244.1.3)
```

#### Calico: Suporte a Ambos os Modelos

O Calico é flexível e suporta ambos os modelos:
- **Modo BGP (padrão)**: Rede roteada sem encapsulamento — melhor performance
- **Modo VXLAN**: Overlay network — compatível com ambientes que não suportam BGP
- **Modo IPIP**: Encapsulamento IP-in-IP — meio-termo entre BGP puro e VXLAN

Neste lab, usaremos o **modo VXLAN** do Calico, pois a AWS VPC não suporta BGP nativamente entre instâncias EC2 sem configuração adicional.

### Comparação: Flannel vs Calico

| Característica | Flannel | Calico |
|---|---|---|
| **Modelo de rede** | Overlay (VXLAN) | Routed (BGP) ou Overlay (VXLAN/IPIP) |
| **Complexidade** | Simples — fácil de instalar e operar | Moderada — mais componentes e configurações |
| **Network Policies** | ❌ Não suporta nativamente | ✅ Suporte completo a NetworkPolicy |
| **Performance** | Boa (overhead de VXLAN) | Excelente (BGP) / Boa (VXLAN) |
| **Escalabilidade** | Boa para clusters pequenos/médios | Excelente para clusters grandes |
| **Observabilidade** | Básica | Avançada (métricas, logs, flow logs) |
| **Segurança** | Básica | Avançada (policies, encryption) |
| **Casos de uso** | Labs simples, ambientes de teste | Produção, ambientes com requisitos de segurança |
| **Manutenção** | Mínima | Moderada |
| **Documentação** | Boa | Excelente e extensa |

### Por que Calico neste Lab?

Escolhemos o **Calico** para este lab pelos seguintes motivos:

1. **Mais recursos para aprendizado** — Network Policies, múltiplos modos de rede, e configurações avançadas proporcionam mais oportunidades de aprendizado
2. **Relevância para o CKA** — O exame CKA cobra conhecimento de Network Policies, que o Calico implementa nativamente
3. **Uso em produção** — Calico é amplamente usado em ambientes de produção, tornando o conhecimento diretamente aplicável
4. **Flexibilidade** — Suporta tanto overlay quanto routed networking, permitindo explorar ambos os modelos
5. **Observabilidade** — Ferramentas de diagnóstico integradas (calicoctl) facilitam o troubleshooting

### Arquitetura do Calico

O Calico é composto por vários componentes:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Cluster Kubernetes                         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              calico-kube-controllers (Deployment)         │    │
│  │  - Sincroniza políticas de rede com o datastore          │    │
│  │  - Gerencia IPAM (IP Address Management)                 │    │
│  │  - Limpa recursos órfãos                                 │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌──────────────────────┐    ┌──────────────────────┐          │
│  │   Worker Node 1       │    │   Worker Node 2       │          │
│  │                       │    │                       │          │
│  │  ┌─────────────────┐ │    │  ┌─────────────────┐ │          │
│  │  │ calico-node     │ │    │  │ calico-node     │ │          │
│  │  │ (DaemonSet)     │ │    │  │ (DaemonSet)     │ │          │
│  │  │                 │ │    │  │                 │ │          │
│  │  │ - Felix (agent) │ │    │  │ - Felix (agent) │ │          │
│  │  │ - BIRD (BGP)    │ │    │  │ - BIRD (BGP)    │ │          │
│  │  │ - confd         │ │    │  │ - confd         │ │          │
│  │  └─────────────────┘ │    │  └─────────────────┘ │          │
│  │                       │    │                       │          │
│  │  Pod CIDR:           │    │  Pod CIDR:           │          │
│  │  10.244.0.0/24       │    │  10.244.1.0/24       │          │
│  └──────────────────────┘    └──────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

**Componentes principais:**

- **Felix** — agente que roda em cada nó, responsável por programar rotas e regras de iptables/eBPF
- **BIRD** — daemon BGP que distribui informações de roteamento entre nós (usado no modo BGP)
- **confd** — monitora o datastore do Calico e gera configurações para BIRD
- **calico-kube-controllers** — sincroniza estado entre Kubernetes API e o datastore do Calico
- **CNI plugin binary** — binário invocado pelo kubelet para configurar a rede de cada pod

### Como o Calico Atribui IPs aos Pods

O Calico usa um sistema de IPAM (IP Address Management) para atribuir IPs:

1. O pod CIDR total (`10.244.0.0/16`) é dividido em blocos menores (por padrão, /26 = 64 IPs)
2. Cada nó recebe um ou mais blocos de IPs
3. Quando um pod é criado em um nó, o Calico atribui o próximo IP disponível do bloco daquele nó
4. Se o bloco de um nó se esgota, um novo bloco é alocado automaticamente

```
Pod CIDR: 10.244.0.0/16 (65.536 IPs disponíveis)
│
├── Node 1: Bloco 10.244.0.0/26 (64 IPs: 10.244.0.1 - 10.244.0.62)
│   ├── Pod A: 10.244.0.5
│   ├── Pod B: 10.244.0.6
│   └── Pod C: 10.244.0.7
│
└── Node 2: Bloco 10.244.0.64/26 (64 IPs: 10.244.0.65 - 10.244.0.126)
    ├── Pod D: 10.244.0.65
    └── Pod E: 10.244.0.66
```

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 03 — Container Runtime](../03-container-runtime/) — containerd instalado e funcionando em todos os nós
- [Módulo 08 — kubelet](../08-kubelet/) — kubelet instalado e registrado no cluster

Você também precisa de:

- Cluster com kube-apiserver, kube-controller-manager e kube-scheduler funcionando
- kubectl configurado e com acesso ao cluster
- Conectividade SSH para todos os nós do cluster

## Comandos Passo a Passo

### 1. Instalar Binários CNI nos Worker Nodes

Antes de instalar o Calico, precisamos garantir que os binários CNI base estejam presentes em cada nó. Esses binários fornecem funcionalidades básicas que o Calico utiliza (loopback, portmap, etc.).

Execute os comandos abaixo em **cada Worker Node** via SSH:

```bash
# Definir a versão dos plugins CNI
CNI_PLUGINS_VERSION="1.4.0"

# Criar diretório para os binários CNI
sudo mkdir -p /opt/cni/bin

# Baixar os plugins CNI
curl -L "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-v${CNI_PLUGINS_VERSION}.tgz" \
  -o /tmp/cni-plugins.tgz

# Extrair os binários para o diretório padrão
sudo tar -xzf /tmp/cni-plugins.tgz -C /opt/cni/bin/

# Limpar arquivo temporário
rm -f /tmp/cni-plugins.tgz
```

**Saída esperada:**
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 43.2M  100 43.2M    0     0  15.2M      0  0:00:02  0:00:02 --:--:-- 15.2M
```

Verifique que os binários foram instalados corretamente:

```bash
# Listar binários CNI instalados
ls /opt/cni/bin/
```

**Saída esperada:**
```
bandwidth  bridge  dhcp  dummy  firewall  host-device  host-local  ipvlan
loopback  macvlan  portmap  ptp  sbr  static  tap  tuning  vlan  vrf
```

Os binários-chave são:
- `bridge` — cria uma bridge de rede no nó
- `host-local` — IPAM plugin que atribui IPs de um range local
- `loopback` — configura a interface loopback no namespace do pod
- `portmap` — mapeia portas do host para o container

### 2. Criar Diretório de Configuração CNI

O kubelet procura configurações CNI no diretório `/etc/cni/net.d/`. O Calico criará automaticamente sua configuração neste diretório após a instalação, mas precisamos garantir que o diretório existe.

Execute em **cada Worker Node**:

```bash
# Criar diretório de configuração CNI
sudo mkdir -p /etc/cni/net.d
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

### 3. Instalar o Calico via Manifesto

O Calico é instalado no cluster como um conjunto de recursos Kubernetes (DaemonSet, Deployment, ServiceAccount, etc.). O manifesto oficial configura todos os componentes necessários.

Execute no **nó local** (onde kubectl está configurado):

```bash
# Baixar o manifesto do Calico (versão 3.27)
curl -L https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml \
  -o calico.yaml
```

**Saída esperada:**
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  238k  100  238k    0     0   512k      0 --:--:-- --:--:-- --:--:--  512k
```

### 4. Configurar o Pod CIDR no Manifesto

Antes de aplicar o manifesto, precisamos configurar o pod CIDR para corresponder ao valor definido no nosso cluster (`10.244.0.0/16`). O Calico usa a variável de ambiente `CALICO_IPV4POOL_CIDR` para definir o range de IPs dos pods.

Edite o arquivo `calico.yaml` para configurar o CIDR:

```bash
# Descomentar e configurar o CALICO_IPV4POOL_CIDR no manifesto
# Procure a seção do container calico-node e ajuste a variável de ambiente
sed -i 's/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/' calico.yaml
sed -i 's/#   value: "192.168.0.0\/16"/  value: "10.244.0.0\/16"/' calico.yaml
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

Alternativamente, edite manualmente o arquivo e localize a seção:

```yaml
# No container calico-node, seção env:
- name: CALICO_IPV4POOL_CIDR
  value: "10.244.0.0/16"
```

### 5. Configurar o Modo de Encapsulamento (VXLAN)

Para ambientes AWS onde BGP não é suportado nativamente entre instâncias, configuramos o Calico para usar encapsulamento VXLAN:

```bash
# Configurar encapsulamento VXLAN (cross-subnet para otimizar tráfego local)
sed -i 's/value: "Always"/value: "CrossSubnet"/' calico.yaml

# Configurar o backend de encapsulamento para VXLAN
sed -i 's/# - name: CALICO_IPV4POOL_VXLAN/- name: CALICO_IPV4POOL_VXLAN/' calico.yaml
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

> **Nota**: O modo `CrossSubnet` usa encapsulamento VXLAN apenas para tráfego entre nós em subnets diferentes. Tráfego entre pods no mesmo nó não é encapsulado, otimizando a performance.

### 6. Aplicar o Manifesto do Calico

Agora aplicamos o manifesto configurado no cluster:

```bash
# Aplicar o manifesto do Calico no cluster
kubectl apply -f calico.yaml
```

**Saída esperada:**
```
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgpfilters.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgppeers.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/blockaffinities.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/caliconodestatuses.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/clusterinformations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/felixconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworksets.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/hostendpoints.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamblocks.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamconfigs.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamhandles.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ippools.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipreservations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networksets.crd.projectcalico.org created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
daemonset.apps/calico-node created
deployment.apps/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
serviceaccount/calico-node created
```

As linhas-chave são a criação do `daemonset.apps/calico-node` (roda em cada nó) e `deployment.apps/calico-kube-controllers` (controlador central).

### 7. Aguardar os Pods do Calico Ficarem Prontos

Após aplicar o manifesto, aguarde todos os pods do Calico atingirem o estado Running:

```bash
# Monitorar o status dos pods do Calico
kubectl get pods -n kube-system -l k8s-app=calico-node --watch
```

**Saída esperada (após ~60 segundos):**
```
NAME                READY   STATUS    RESTARTS   AGE
calico-node-abc12   1/1     Running   0          45s
calico-node-def34   1/1     Running   0          45s
```

Pressione `Ctrl+C` para sair do watch. Verifique também o controller:

```bash
# Verificar o calico-kube-controllers
kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers
```

**Saída esperada:**
```
NAME                                       READY   STATUS    RESTARTS   AGE
calico-kube-controllers-7c968b5878-x9z2k   1/1     Running   0          60s
```

### 8. Verificar a Configuração CNI nos Nós

Após a instalação, o Calico cria automaticamente a configuração CNI em cada nó. Verifique via SSH em um Worker Node:

```bash
# Verificar que o Calico criou a configuração CNI
cat /etc/cni/net.d/10-calico.conflist
```

**Saída esperada:**
```json
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "datastore_type": "kubernetes",
      "mtu": 0,
      "nodename_file_optional": false,
      "log_level": "Info",
      "log_file_path": "/var/log/calico/cni/cni.log",
      "ipam": {
        "type": "calico-ipam",
        "assign_ipv4": "true",
        "assign_ipv6": "false"
      },
      "container_settings": {
        "allow_ip_forwarding": false
      },
      "policy": {
        "type": "k8s"
      },
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
      }
    },
    {
      "type": "portmap",
      "snat": true,
      "capabilities": {"portMappings": true}
    },
    {
      "type": "bandwidth",
      "capabilities": {"bandwidth": true}
    }
  ]
}
```

**Parâmetros importantes da configuração:**

| Parâmetro | Valor | Descrição |
|---|---|---|
| `type` | `calico` | Plugin CNI principal do Calico |
| `datastore_type` | `kubernetes` | Usa a API do Kubernetes como datastore (ao invés de etcd direto) |
| `ipam.type` | `calico-ipam` | Usa o IPAM do Calico para atribuição de IPs |
| `ipam.assign_ipv4` | `true` | Atribui endereços IPv4 aos pods |
| `policy.type` | `k8s` | Usa NetworkPolicy do Kubernetes para políticas de rede |
| `kubernetes.kubeconfig` | `/etc/cni/net.d/calico-kubeconfig` | Kubeconfig para o plugin se comunicar com a API |
| `portmap` (plugin) | — | Habilita mapeamento de portas (hostPort) |
| `bandwidth` (plugin) | — | Habilita limitação de bandwidth por pod |

### 9. Verificar o IPPool Configurado

O Calico cria um recurso IPPool que define o range de IPs disponíveis para pods:

```bash
# Verificar o IPPool criado pelo Calico
kubectl get ippools -o yaml
```

**Saída esperada:**
```yaml
apiVersion: v1
items:
- apiVersion: crd.projectcalico.org/v1
  kind: IPPool
  metadata:
    name: default-ipv4-ippool
  spec:
    blockSize: 26
    cidr: 10.244.0.0/16
    encapsulation: VXLANCrossSubnet
    natOutgoing: true
    nodeSelector: all()
kind: List
```

**Parâmetros do IPPool:**

| Parâmetro | Valor | Descrição |
|---|---|---|
| `cidr` | `10.244.0.0/16` | Range total de IPs para pods (65.536 endereços) |
| `blockSize` | `26` | Cada nó recebe blocos /26 (64 IPs por bloco) |
| `encapsulation` | `VXLANCrossSubnet` | Usa VXLAN apenas entre subnets diferentes |
| `natOutgoing` | `true` | Aplica SNAT para tráfego de pods saindo do cluster |
| `nodeSelector` | `all()` | Todos os nós participam deste pool |

### 10. Verificar que os Nós Estão Ready

Com o CNI instalado, os nós que estavam em estado `NotReady` (por falta de plugin de rede) devem transicionar para `Ready`:

```bash
# Verificar status dos nós
kubectl get nodes
```

**Saída esperada:**
```
NAME               STATUS   ROLES    AGE   VERSION
k8s-control-plane  Ready    <none>   1h    v1.29.0
k8s-worker-01      Ready    <none>   45m   v1.29.0
```

A linha-chave é `STATUS: Ready` — indica que o kubelet detectou o plugin CNI e o nó está pronto para receber pods.

## Verificação

### Teste 1: Verificar Pods do Calico

```bash
# Todos os pods do Calico devem estar Running
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers
```

**Saída esperada:**
```
NAME                READY   STATUS    RESTARTS   AGE
calico-node-abc12   1/1     Running   0          5m
calico-node-def34   1/1     Running   0          5m

NAME                                       READY   STATUS    RESTARTS   AGE
calico-kube-controllers-7c968b5878-x9z2k   1/1     Running   0          5m
```

### Teste 2: Verificar Comunicação Pod-to-Pod entre Nós

Este é o teste mais importante — confirma que a rede CNI está funcionando corretamente entre nós diferentes.

#### 2.1 Criar pods de teste em nós diferentes

```bash
# Criar pod de teste no primeiro nó
kubectl run test-pod-1 \
  --image=busybox \
  --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-worker-01"}}}' \
  -- sleep 3600
```

**Saída esperada:**
```
pod/test-pod-1 created
```

```bash
# Criar pod de teste no segundo nó (control plane, se permitir scheduling)
kubectl run test-pod-2 \
  --image=busybox \
  --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-control-plane"}}}' \
  -- sleep 3600
```

**Saída esperada:**
```
pod/test-pod-2 created
```

> **Nota**: Se o control plane tiver taints que impedem scheduling, remova temporariamente com:
> `kubectl taint nodes k8s-control-plane node-role.kubernetes.io/control-plane:NoSchedule-`

#### 2.2 Verificar que os pods receberam IPs do CIDR configurado

```bash
# Verificar IPs atribuídos aos pods de teste
kubectl get pods -o wide
```

**Saída esperada:**
```
NAME         READY   STATUS    RESTARTS   AGE   IP            NODE
test-pod-1   1/1     Running   0          30s   10.244.0.5    k8s-worker-01
test-pod-2   1/1     Running   0          25s   10.244.0.65   k8s-control-plane
```

As linhas-chave são os IPs na coluna `IP` — devem estar dentro do range `10.244.0.0/16`.

#### 2.3 Testar conectividade entre os pods

```bash
# Do test-pod-1, fazer ping no test-pod-2
kubectl exec test-pod-1 -- ping -c 3 10.244.0.65
```

**Saída esperada:**
```
PING 10.244.0.65 (10.244.0.65): 56 data bytes
64 bytes from 10.244.0.65: seq=0 ttl=62 time=0.845 ms
64 bytes from 10.244.0.65: seq=1 ttl=62 time=0.621 ms
64 bytes from 10.244.0.65: seq=2 ttl=62 time=0.587 ms

--- 10.244.0.65 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.587/0.684/0.845 ms
```

A linha-chave é `0% packet loss` — confirma que a comunicação pod-to-pod entre nós está funcionando.

```bash
# Do test-pod-2, fazer ping no test-pod-1
kubectl exec test-pod-2 -- ping -c 3 10.244.0.5
```

**Saída esperada:**
```
PING 10.244.0.5 (10.244.0.5): 56 data bytes
64 bytes from 10.244.0.5: seq=0 ttl=62 time=0.912 ms
64 bytes from 10.244.0.5: seq=1 ttl=62 time=0.654 ms
64 bytes from 10.244.0.5: seq=2 ttl=62 time=0.598 ms

--- 10.244.0.5 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.598/0.721/0.912 ms
```

