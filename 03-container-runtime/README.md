# Módulo 03 — Container Runtime (containerd)

## Objetivo

Instalar e configurar o container runtime (containerd) em todos os nós do cluster. Ao final deste módulo, você terá:

- Compreensão do papel do container runtime na arquitetura Kubernetes
- Entendimento da interface CRI (Container Runtime Interface) e como o kubelet delega operações
- Módulos de kernel e parâmetros de rede configurados corretamente
- containerd versão 1.7.13 instalado e configurado com SystemdCgroup
- Capacidade de verificar o funcionamento do runtime com pull de imagens

## Teoria

### O Papel do Container Runtime no Kubernetes

O **container runtime** é o componente responsável por executar containers no nível do sistema operacional. No Kubernetes, ele é a camada mais baixa da stack — é quem realmente cria, inicia, para e remove containers.

```
┌─────────────────────────────────────────────────────────────┐
│                      Kubernetes Node                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐         CRI (gRPC)         ┌──────────────┐  │
│  │  kubelet │ ◄─────────────────────────► │  containerd  │  │
│  └──────────┘                             └──────┬───────┘  │
│                                                  │          │
│                                           ┌──────▼───────┐  │
│                                           │    runc      │  │
│                                           │  (OCI spec)  │  │
│                                           └──────┬───────┘  │
│                                                  │          │
│                                           ┌──────▼───────┐  │
│                                           │   Container  │  │
│                                           │   (processo) │  │
│                                           └──────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Fluxo de operação:**

1. O **kubelet** recebe uma especificação de Pod do kube-apiserver
2. O kubelet traduz a spec do Pod em chamadas CRI (gRPC) para o container runtime
3. O **containerd** recebe as chamadas e gerencia o ciclo de vida do container
4. O containerd delega a criação real do container para o **runc** (runtime OCI de baixo nível)
5. O **runc** cria o container usando namespaces e cgroups do kernel Linux

### CRI — Container Runtime Interface

O **CRI (Container Runtime Interface)** é uma API padrão definida pelo Kubernetes que permite ao kubelet se comunicar com qualquer container runtime compatível. Antes do CRI, o Kubernetes tinha código específico para cada runtime (Docker, rkt) embutido no kubelet, o que tornava a manutenção difícil.

**Benefícios do CRI:**

| Aspecto | Sem CRI (legado) | Com CRI |
|---------|-------------------|---------|
| Acoplamento | kubelet acoplado ao runtime | kubelet desacoplado via API |
| Novos runtimes | Requer mudança no código do kubelet | Basta implementar a API CRI |
| Manutenção | Complexa (código monolítico) | Simples (interface padronizada) |
| Runtimes suportados | Apenas os embutidos | Qualquer runtime compatível |

**Runtimes compatíveis com CRI:**

- **containerd** — runtime de produção, usado neste lab (leve, estável, amplamente adotado)
- **CRI-O** — runtime otimizado para Kubernetes (usado pelo OpenShift)
- **Docker** (via cri-dockerd) — adaptador para usar Docker com CRI (legado, não recomendado)

### Como o kubelet Delega Operações via CRI

O kubelet não executa containers diretamente. Ele delega todas as operações de ciclo de vida para o container runtime através de chamadas gRPC na interface CRI:

| Operação kubelet | Chamada CRI | O que acontece |
|------------------|-------------|----------------|
| Criar Pod | `RunPodSandbox` | Cria o namespace de rede e o sandbox (pause container) |
| Criar Container | `CreateContainer` | Prepara o filesystem e configuração do container |
| Iniciar Container | `StartContainer` | Executa o processo principal do container |
| Parar Container | `StopContainer` | Envia SIGTERM, aguarda graceful shutdown |
| Remover Container | `RemoveContainer` | Remove o container e limpa recursos |
| Remover Pod | `RemovePodSandbox` | Remove o sandbox e namespace de rede |
| Pull de Imagem | `PullImage` | Baixa a imagem do registry |
| Status | `ContainerStatus` | Retorna estado atual do container |

O kubelet se conecta ao containerd via **socket Unix** em `/run/containerd/containerd.sock`. Esta é a configuração que faremos neste módulo.

### Módulos de Kernel Necessários

O container runtime e a rede do Kubernetes dependem de funcionalidades específicas do kernel Linux que precisam ser habilitadas:

| Módulo | Propósito |
|--------|-----------|
| **overlay** | Filesystem overlay (OverlayFS) usado pelo containerd para montar camadas de imagens de container de forma eficiente. Permite que múltiplos containers compartilhem camadas base sem duplicar dados. |
| **br_netfilter** | Permite que o tráfego de rede que passa por bridges Linux seja processado pelo iptables/netfilter. Essencial para que as regras de rede do Kubernetes (Services, NetworkPolicies) funcionem corretamente com tráfego entre containers. |

### Parâmetros sysctl Necessários

| Parâmetro | Valor | Propósito |
|-----------|-------|-----------|
| `net.bridge.bridge-nf-call-iptables` | 1 | Faz com que pacotes que atravessam bridges sejam processados pelo iptables. Sem isso, o kube-proxy não consegue aplicar regras de NAT para Services. |
| `net.bridge.bridge-nf-call-ip6tables` | 1 | Mesmo que acima, mas para tráfego IPv6. |
| `net.ipv4.ip_forward` | 1 | Habilita o encaminhamento de pacotes IP entre interfaces de rede. Necessário para que o nó possa rotear tráfego entre pods em diferentes nós. |

### containerd — Visão Geral

O **containerd** é um container runtime de nível industrial, originalmente desenvolvido pela Docker Inc. e agora mantido pela CNCF (Cloud Native Computing Foundation). Ele é:

- **Leve** — faz apenas o necessário (gerenciar containers), sem extras
- **Estável** — usado em produção por grandes empresas
- **Compatível com CRI** — suporta nativamente a interface CRI do Kubernetes
- **Padrão da indústria** — runtime padrão em EKS, GKE, AKS e kubeadm

### Configuração do containerd para Kubernetes

O containerd usa um arquivo de configuração TOML (`/etc/containerd/config.toml`) que define seu comportamento. Os parâmetros mais importantes para Kubernetes são:

| Parâmetro | Valor | Explicação |
|-----------|-------|------------|
| `SystemdCgroup = true` | `true` | Configura o containerd para usar o driver de cgroup **systemd** em vez do driver **cgroupfs**. O Kubernetes requer que o kubelet e o container runtime usem o mesmo driver de cgroup. Como o systemd é o init system padrão no Ubuntu, ambos devem usar systemd. Se houver inconsistência, os pods podem ficar instáveis ou falhar ao iniciar. |
| `sandbox_image` | `registry.k8s.io/pause:3.9` | Define a imagem do container "pause" usado como sandbox para cada Pod. O pause container mantém os namespaces de rede e IPC do Pod ativos enquanto os containers de aplicação podem ser reiniciados. Cada Pod tem exatamente um pause container. |
| `default_runtime_name` | `runc` | Define o runtime OCI padrão usado pelo containerd quando nenhum runtime específico é solicitado. O runc é a implementação de referência da especificação OCI. |
| `runtime_type` | `io.containerd.runc.v2` | Tipo do shim de runtime usado para executar containers. O shim v2 é a versão recomendada que gerencia o ciclo de vida do container e se comunica com o containerd via ttrpc. |
| `bin_dir` | `/opt/cni/bin` | Diretório onde os binários dos plugins CNI estão instalados. O containerd usa estes binários para configurar a rede dos containers (bridge, loopback, calico, etc.). |
| `conf_dir` | `/etc/cni/net.d` | Diretório contendo os arquivos de configuração CNI (*.conflist). O containerd lê estes arquivos para determinar como configurar a rede de cada Pod. |
| `[plugins."io.containerd.grpc.v1.cri"]` | — | Seção que configura o plugin CRI do containerd. Este plugin é o que permite ao kubelet se comunicar com o containerd via interface CRI. |
| `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]` | — | Configura o runc como runtime OCI padrão. O runc é responsável por criar os containers usando primitivas do kernel (namespaces, cgroups). |
| `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]` | — | Opções específicas do runc, incluindo o driver de cgroup. |

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/) — instâncias EC2 provisionadas e acessíveis via SSH
- [Módulo 02 — Certificados TLS](../02-tls-certificates/) — certificados gerados e distribuídos

**Importante:** Os comandos deste módulo devem ser executados em **AMBOS os nós** (control plane e worker node). O container runtime é necessário em todos os nós que executam containers.

Você precisará:

- Acesso SSH configurado para ambos os nós
- IP público do Control Plane (`CONTROL_PLANE_PUBLIC_IP`)
- IP público do Worker Node (`WORKER_NODE_PUBLIC_IP`)

## Comandos Passo a Passo

> **Nota**: Execute todos os comandos abaixo em **AMBOS os nós** (control plane e worker). Conecte-se via SSH em cada nó e execute os mesmos comandos.

### 1. Conectar ao Nó via SSH

Conecte-se ao nó onde deseja instalar o containerd. Repita todo o processo para cada nó.

```bash
# Conectar ao control plane
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${CONTROL_PLANE_PUBLIC_IP}

# OU conectar ao worker node
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@${WORKER_NODE_PUBLIC_IP}
```

**Saída esperada:**
```
Welcome to Ubuntu 22.04.3 LTS (GNU/Linux 5.15.0-1051-aws x86_64)
...
ubuntu@k8s-control-plane:~$
```

### 2. Carregar Módulos de Kernel

Os módulos `overlay` e `br_netfilter` precisam ser carregados no kernel para que o containerd e a rede do Kubernetes funcionem corretamente.

#### 2.1 Criar arquivo de configuração para carregamento persistente

Este arquivo garante que os módulos sejam carregados automaticamente após cada reinicialização do sistema:

```bash
# Criar arquivo de configuração para módulos do kernel
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
```

**Saída esperada:**
```
overlay
br_netfilter
```

**Explicação:** O diretório `/etc/modules-load.d/` contém arquivos que listam módulos de kernel a serem carregados automaticamente durante o boot pelo systemd. Sem este arquivo, os módulos seriam perdidos após reinicialização.

#### 2.2 Carregar os módulos imediatamente

Carregue os módulos no kernel em execução sem precisar reiniciar:

```bash
# Carregar módulo overlay (filesystem para containers)
sudo modprobe overlay

# Carregar módulo br_netfilter (bridge + netfilter)
sudo modprobe br_netfilter
```

**Saída esperada:** Nenhuma saída indica sucesso.

**Explicação:**
- `modprobe overlay` — carrega o módulo OverlayFS que permite ao containerd montar camadas de imagens de forma eficiente
- `modprobe br_netfilter` — carrega o módulo que conecta bridges de rede ao netfilter/iptables

#### 2.3 Verificar que os módulos foram carregados

Confirme que ambos os módulos estão ativos no kernel:

```bash
# Verificar módulos carregados
lsmod | grep -E "overlay|br_netfilter"
```

**Saída esperada:**
```
br_netfilter           32768  0
bridge                307200  1 br_netfilter
overlay               151552  0
```

**Linhas-chave:** Ambos `br_netfilter` e `overlay` devem aparecer na lista. Se algum estiver ausente, o `modprobe` falhou.

### 3. Configurar Parâmetros sysctl de Rede

Os parâmetros sysctl configuram o comportamento de rede do kernel. Estes são obrigatórios para que o Kubernetes gerencie tráfego de rede corretamente.

#### 3.1 Criar arquivo de configuração sysctl

```bash
# Criar configuração de rede para Kubernetes
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
```

**Saída esperada:**
```
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
```

**Explicação dos parâmetros:**
- `net.bridge.bridge-nf-call-iptables = 1` — pacotes que passam por bridges Linux são processados pelo iptables. O kube-proxy depende disso para implementar Services (DNAT/SNAT)
- `net.bridge.bridge-nf-call-ip6tables = 1` — mesmo comportamento para IPv6
- `net.ipv4.ip_forward = 1` — permite que o nó encaminhe pacotes entre interfaces de rede. Sem isso, pods em nós diferentes não conseguem se comunicar

#### 3.2 Aplicar os parâmetros imediatamente

Aplique as configurações sem reiniciar o sistema:

```bash
# Aplicar parâmetros sysctl
sudo sysctl --system
```

**Saída esperada (linhas relevantes):**
```
* Applying /etc/sysctl.d/99-kubernetes-cri.conf ...
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

**Linhas-chave:** Os três parâmetros devem aparecer com valor `= 1`. Se algum mostrar `= 0`, verifique se o módulo `br_netfilter` está carregado.

#### 3.3 Verificar que os parâmetros estão ativos

```bash
# Verificar cada parâmetro individualmente
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
sysctl net.ipv4.ip_forward
```

**Saída esperada:**
```
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

### 4. Instalar containerd

Vamos instalar o containerd versão **1.7.13** a partir do repositório oficial do Docker. Esta versão é estável e compatível com Kubernetes 1.29.

#### 4.1 Instalar dependências

Instale os pacotes necessários para adicionar repositórios HTTPS:

```bash
# Atualizar lista de pacotes e instalar dependências
sudo apt-get update
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release
```

**Saída esperada (últimas linhas):**
```
Setting up apt-transport-https ...
Setting up ca-certificates ...
...
Processing triggers for ca-certificates ...
```

**Explicação:** Estes pacotes permitem que o apt baixe pacotes de repositórios HTTPS e verifique assinaturas GPG.

#### 4.2 Adicionar chave GPG do repositório Docker

A chave GPG garante que os pacotes baixados são autênticos e não foram adulterados:

```bash
# Criar diretório para keyrings
sudo install -m 0755 -d /etc/apt/keyrings

# Baixar e instalar a chave GPG do Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Definir permissões de leitura
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

**Saída esperada:** Nenhuma saída indica sucesso.

#### 4.3 Adicionar repositório Docker

Adicione o repositório oficial do Docker como fonte de pacotes:

```bash
# Adicionar repositório Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

**Saída esperada:** Nenhuma saída indica sucesso.

**Explicação:**
- `arch=$(dpkg --print-architecture)` — detecta a arquitetura do sistema (amd64)
- `signed-by=/etc/apt/keyrings/docker.gpg` — usa a chave GPG para verificar pacotes
- `$(lsb_release -cs)` — detecta o codinome da versão Ubuntu (jammy para 22.04)
- `stable` — usa o canal estável do repositório

#### 4.4 Instalar containerd versão específica

Instale a versão exata do containerd definida no `variables.env` (1.7.13):

```bash
# Atualizar lista de pacotes com o novo repositório
sudo apt-get update

# Instalar containerd na versão específica
sudo apt-get install -y containerd.io=1.7.13-1
```

**Saída esperada:**
```
Reading package lists... Done
...
Setting up containerd.io (1.7.13-1) ...
Created symlink /etc/systemd/system/multi-user.target.wants/containerd.service → /lib/systemd/system/containerd.service.
```

**Linhas-chave:** A mensagem `Setting up containerd.io (1.7.13-1)` confirma a instalação da versão correta. O symlink indica que o serviço será iniciado automaticamente no boot.

> **Nota:** Fixamos a versão `1.7.13-1` para garantir reprodutibilidade. Em produção, mantenha o containerd atualizado com patches de segurança.

#### 4.5 Impedir atualização automática do containerd

Para evitar que atualizações do sistema alterem a versão do containerd:

```bash
# Fixar versão do containerd (impedir upgrade automático)
sudo apt-mark hold containerd.io
```

**Saída esperada:**
```
containerd.io set on hold.
```

### 5. Gerar e Configurar o config.toml do containerd

O containerd precisa de um arquivo de configuração que habilite o plugin CRI e configure o driver de cgroup correto para Kubernetes.

#### 5.1 Gerar configuração padrão

Gere o arquivo de configuração padrão do containerd como ponto de partida:

```bash
# Criar diretório de configuração
sudo mkdir -p /etc/containerd

# Gerar configuração padrão
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
```

**Saída esperada:** Nenhuma saída indica sucesso. O arquivo `/etc/containerd/config.toml` será criado com a configuração padrão.

**Explicação:** O comando `containerd config default` gera uma configuração completa com todos os valores padrão. Vamos modificar apenas os parâmetros necessários para Kubernetes.

#### 5.2 Configurar SystemdCgroup

O parâmetro mais crítico é o `SystemdCgroup`. Ele deve ser `true` para que o containerd use o driver de cgroup systemd, compatível com o kubelet:

```bash
# Habilitar SystemdCgroup no containerd
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
```

**Saída esperada:** Nenhuma saída indica sucesso.

**Por que isso é necessário:**

O Linux usa **cgroups** (control groups) para limitar e contabilizar recursos (CPU, memória) de processos. Existem dois drivers para gerenciar cgroups:

- **cgroupfs** — o containerd gerencia cgroups diretamente via filesystem
- **systemd** — o systemd gerencia cgroups (recomendado quando systemd é o init system)

Se o kubelet usa systemd (padrão no Ubuntu) e o containerd usa cgroupfs, haverá **dois gerenciadores de cgroup competindo**, causando instabilidade. Ambos devem usar o mesmo driver.

#### 5.3 Configurar imagem do sandbox (pause container)

Configure a imagem do pause container para a versão compatível com Kubernetes 1.29:

```bash
# Configurar sandbox image
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.9"|g' /etc/containerd/config.toml
```

**Saída esperada:** Nenhuma saída indica sucesso.

**O que é o pause container:**

Cada Pod no Kubernetes tem um container especial chamado "pause" (ou "sandbox") que:

1. É o primeiro container criado no Pod
2. Mantém os namespaces de rede e IPC do Pod ativos
3. Serve como "pai" dos outros containers no Pod
4. Se um container de aplicação reinicia, o namespace de rede (IP do Pod) permanece estável graças ao pause container

#### 5.4 Verificar as alterações no config.toml

Confirme que as configurações foram aplicadas corretamente:

```bash
# Verificar SystemdCgroup
grep "SystemdCgroup" /etc/containerd/config.toml
```

**Saída esperada:**
```
            SystemdCgroup = true
```

```bash
# Verificar sandbox_image
grep "sandbox_image" /etc/containerd/config.toml
```

**Saída esperada:**
```
    sandbox_image = "registry.k8s.io/pause:3.9"
```

### 6. Reiniciar e Habilitar o Serviço containerd

Após alterar a configuração, reinicie o serviço para aplicar as mudanças:

```bash
# Reiniciar containerd para aplicar nova configuração
sudo systemctl restart containerd

# Habilitar containerd para iniciar automaticamente no boot
sudo systemctl enable containerd
```

**Saída esperada:**
```
Synchronizing state of containerd.service with SysV service script with /lib/systemd/systemd-sysv-install.
Executing: /lib/systemd/systemd-sysv-install enable containerd
```

**Explicação:**
- `systemctl restart containerd` — para e reinicia o serviço, carregando a nova configuração
- `systemctl enable containerd` — cria um symlink para que o serviço inicie automaticamente no boot

## Verificação

Após completar a instalação em cada nó, execute os seguintes comandos para confirmar que tudo está funcionando corretamente.

### Verificação 1: Serviço containerd ativo

Verifique que o serviço containerd está rodando sem erros:

```bash
# Verificar status do serviço
sudo systemctl status containerd
```

**Saída esperada:**
```
● containerd.service - containerd container runtime
     Loaded: loaded (/lib/systemd/system/containerd.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-01 00:00:00 UTC; 1min ago
       Docs: https://containerd.io
   Main PID: 1234 (containerd)
      Tasks: 8
     Memory: 12.5M
        CPU: 250ms
     CGroup: /system.slice/containerd.service
             └─1234 /usr/bin/containerd
```

**Linhas-chave:**
- `Active: active (running)` — serviço está rodando
- `enabled` — configurado para iniciar no boot
- Sem mensagens de erro nos logs

### Verificação 2: Socket do containerd acessível

O kubelet se conecta ao containerd via socket Unix. Verifique que o socket existe e está acessível:

```bash
# Verificar que o socket existe
ls -la /run/containerd/containerd.sock
```

**Saída esperada:**
```
srw-rw---- 1 root root 0 Jan  1 00:00 /run/containerd/containerd.sock
```

**Linhas-chave:** O arquivo deve existir com tipo `s` (socket) no início das permissões. Se não existir, o containerd não iniciou corretamente.

### Verificação 3: Versão do containerd

Confirme que a versão instalada é a esperada (1.7.13):

```bash
# Verificar versão
containerd --version
```

**Saída esperada:**
```
containerd containerd.io 1.7.13 ...
```

**Linha-chave:** A versão deve ser `1.7.13`.

### Verificação 4: Pull de imagem de teste

Teste a capacidade do containerd de baixar imagens de um registry. Usamos o `ctr` (CLI do containerd) para isso:

```bash
# Fazer pull de uma imagem de teste
sudo ctr images pull docker.io/library/hello-world:latest
```

**Saída esperada:**
```
docker.io/library/hello-world:latest:                                             resolved       |++++++++++++++++++++++++++++++++++++++|
index-sha256:...                                                                  done           |++++++++++++++++++++++++++++++++++++++|
manifest-sha256:...                                                               done           |++++++++++++++++++++++++++++++++++++++|
layer-sha256:...                                                                  done           |++++++++++++++++++++++++++++++++++++++|
config-sha256:...                                                                 done           |++++++++++++++++++++++++++++++++++++++|
elapsed: 2.1s                                                                     total:  2.5 KB (1.2 KB/s)
unpacking linux/amd64 sha256:...
done: 312.1ms
```

**Linhas-chave:** A mensagem `done` no final indica que a imagem foi baixada e descompactada com sucesso.

### Verificação 5: Listar imagens baixadas

Confirme que a imagem está armazenada localmente:

```bash
# Listar imagens
sudo ctr images list
```

**Saída esperada:**
```
REF                                TYPE                                                      DIGEST                                                                  SIZE      PLATFORMS   LABELS
docker.io/library/hello-world:latest application/vnd.docker.distribution.manifest.list.v2+json sha256:...  2.5 KiB   linux/amd64 -
```

### Verificação 6: Testar execução de container (opcional)

Execute um container de teste para validar o ciclo completo:

```bash
# Executar container de teste
sudo ctr run --rm docker.io/library/hello-world:latest test-hello
```

**Saída esperada:**
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
...
```

**Linha-chave:** A mensagem `Hello from Docker!` confirma que o containerd consegue criar e executar containers com sucesso.

### Verificação 7: Confirmar configuração CRI

Verifique que o plugin CRI está habilitado na configuração:

```bash
# Verificar que o CRI plugin não está desabilitado
grep -A 2 'disabled_plugins' /etc/containerd/config.toml
```

**Saída esperada:**
```
disabled_plugins = []
```

**Linha-chave:** A lista `disabled_plugins` deve estar vazia `[]`. Se contiver `"cri"`, o kubelet não conseguirá se comunicar com o containerd.

### Verificação 8: Limpar imagem de teste

Após confirmar o funcionamento, remova a imagem de teste para liberar espaço:

```bash
# Remover imagem de teste
sudo ctr images remove docker.io/library/hello-world:latest
```

**Saída esperada:**
```
docker.io/library/hello-world:latest
```

## Troubleshooting

### Problema 1: Serviço containerd não inicia (status failed)

**Sintoma:**
```bash
sudo systemctl status containerd
```
```
● containerd.service - containerd container runtime
     Active: failed (Result: exit-code) since ...
```

**Causa provável 1: Arquivo config.toml com sintaxe inválida**

Se o `sed` corrompeu o arquivo de configuração ou há erro de sintaxe TOML:

**Resolução:**
```bash
# Verificar logs detalhados
sudo journalctl -u containerd -n 50 --no-pager

# Regenerar configuração padrão
sudo rm /etc/containerd/config.toml
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Reaplicar configurações do Kubernetes
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.9"|g' /etc/containerd/config.toml

# Reiniciar serviço
sudo systemctl restart containerd
```

**Causa provável 2: Versão incompatível ou pacote corrompido**

Se a instalação do pacote falhou parcialmente:

**Resolução:**
```bash
# Remover e reinstalar containerd
sudo apt-get remove -y containerd.io
sudo apt-get install -y containerd.io=1.7.13-1

# Regenerar configuração
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.9"|g' /etc/containerd/config.toml

# Reiniciar
sudo systemctl daemon-reload
sudo systemctl restart containerd
```

### Problema 2: Módulos de kernel não carregam

**Sintoma:**
```bash
lsmod | grep overlay
# (sem saída)
```

**Causa provável 1: Módulo não disponível no kernel**

Em algumas AMIs mínimas, os módulos podem não estar incluídos.

**Resolução:**
```bash
# Verificar se o módulo existe no sistema
find /lib/modules/$(uname -r) -name "overlay*"
find /lib/modules/$(uname -r) -name "br_netfilter*"

# Se não encontrar, instalar módulos extras do kernel
sudo apt-get install -y linux-modules-extra-$(uname -r)

# Tentar carregar novamente
sudo modprobe overlay
sudo modprobe br_netfilter
```

**Causa provável 2: Permissões insuficientes**

O `modprobe` requer privilégios root.

**Resolução:**
```bash
# Executar com sudo
sudo modprobe overlay
sudo modprobe br_netfilter

# Verificar
lsmod | grep -E "overlay|br_netfilter"
```

### Problema 3: Parâmetros sysctl não aplicam (valor permanece 0)

**Sintoma:**
```bash
sysctl net.bridge.bridge-nf-call-iptables
```
```
net.bridge.bridge-nf-call-iptables = 0
```

**Causa provável 1: Módulo br_netfilter não carregado**

Os parâmetros `net.bridge.*` só existem quando o módulo `br_netfilter` está carregado.

**Resolução:**
```bash
# Carregar o módulo primeiro
sudo modprobe br_netfilter

# Reaplicar sysctl
sudo sysctl --system

# Verificar
sysctl net.bridge.bridge-nf-call-iptables
```

**Causa provável 2: Outro arquivo sysctl sobrescrevendo o valor**

Pode haver outro arquivo em `/etc/sysctl.d/` com prioridade maior.

**Resolução:**
```bash
# Listar todos os arquivos sysctl (ordem de aplicação)
ls -la /etc/sysctl.d/

# Verificar se algum outro arquivo define o mesmo parâmetro
grep -r "bridge-nf-call" /etc/sysctl.d/ /etc/sysctl.conf

# Se necessário, renomear nosso arquivo para ter prioridade máxima
sudo mv /etc/sysctl.d/99-kubernetes-cri.conf /etc/sysctl.d/zz-kubernetes-cri.conf
sudo sysctl --system
```

### Problema 4: Socket do containerd não encontrado

**Sintoma:**
```bash
ls /run/containerd/containerd.sock
```
```
ls: cannot access '/run/containerd/containerd.sock': No such file or directory
```

**Causa provável 1: Serviço containerd não está rodando**

O socket só existe enquanto o containerd está ativo.

**Resolução:**
```bash
# Verificar status do serviço
sudo systemctl status containerd

# Se não estiver rodando, iniciar
sudo systemctl start containerd

# Verificar socket novamente
ls -la /run/containerd/containerd.sock
```

**Causa provável 2: Caminho do socket alterado na configuração**

Se o config.toml foi modificado incorretamente, o socket pode estar em outro caminho.

**Resolução:**
```bash
# Verificar onde o socket está configurado
grep -i "address" /etc/containerd/config.toml | head -5

# Verificar se existe em outro local
find /run -name "containerd.sock" 2>/dev/null

# Se necessário, regenerar configuração padrão
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.9"|g' /etc/containerd/config.toml
sudo systemctl restart containerd
```

### Problema 5: Pull de imagem falha (timeout ou erro de rede)

**Sintoma:**
```bash
sudo ctr images pull docker.io/library/hello-world:latest
```
```
ctr: failed to resolve reference "docker.io/library/hello-world:latest": failed to do request: ... i/o timeout
```

**Causa provável 1: Instância sem acesso à internet**

A instância EC2 pode não ter rota para a internet (internet gateway ou NAT gateway ausente).

**Resolução:**
```bash
# Testar conectividade com a internet
curl -I https://registry-1.docker.io/v2/ 2>&1 | head -5

# Se falhar, verificar rota padrão
ip route show default

# Verificar DNS
cat /etc/resolv.conf
nslookup registry-1.docker.io
```

Se não houver rota padrão, revise a configuração de VPC no [Módulo 01](../01-aws-infrastructure/).

**Causa provável 2: Security group bloqueando tráfego de saída**

O security group pode não permitir tráfego de saída (egress) para a internet.

**Resolução:**
```bash
# Verificar regras de saída do security group via AWS CLI (na máquina local)
aws ec2 describe-security-groups \
  --group-ids <SECURITY_GROUP_ID> \
  --query 'SecurityGroups[0].IpPermissionsEgress'

# Deve ter uma regra permitindo todo tráfego de saída (0.0.0.0/0)
```

### Problema 6: Erro de cgroup driver incompatível (após instalar kubelet)

**Sintoma (nos logs do kubelet):**
```
"Failed to run kubelet" err="failed to run Kubelet: misconfiguration: kubelet cgroup driver: \"systemd\" is different from docker cgroup driver: \"cgroupfs\""
```

**Causa provável: SystemdCgroup não configurado como true**

O containerd está usando cgroupfs enquanto o kubelet espera systemd.

**Resolução:**
```bash
# Verificar configuração atual
grep "SystemdCgroup" /etc/containerd/config.toml

# Se estiver false, corrigir
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Reiniciar containerd
sudo systemctl restart containerd

# Reiniciar kubelet (se já estiver instalado)
sudo systemctl restart kubelet
```

### Problema 7: Permissão negada ao acessar o socket

**Sintoma:**
```bash
ctr images list
```
```
ctr: failed to dial "/run/containerd/containerd.sock": ... permission denied
```

**Causa provável: Comando executado sem sudo**

O socket do containerd tem permissões restritas (`srw-rw----` com owner root).

**Resolução:**
```bash
# Usar sudo para comandos ctr
sudo ctr images list

# Ou adicionar o usuário ao grupo root (não recomendado em produção)
# O kubelet roda como root, então não terá este problema
```

### Resumo de Verificação Rápida

Execute este bloco de comandos para uma verificação completa e rápida:

```bash
echo "=== Verificação do Container Runtime ==="
echo ""
echo "1. Módulos de kernel:"
lsmod | grep -E "overlay|br_netfilter" && echo "   ✓ OK" || echo "   ✗ FALHA"
echo ""
echo "2. Parâmetros sysctl:"
[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" = "1" ] && echo "   ✓ bridge-nf-call-iptables = 1" || echo "   ✗ bridge-nf-call-iptables != 1"
[ "$(sysctl -n net.ipv4.ip_forward)" = "1" ] && echo "   ✓ ip_forward = 1" || echo "   ✗ ip_forward != 1"
echo ""
echo "3. Serviço containerd:"
systemctl is-active containerd && echo "   ✓ Serviço ativo" || echo "   ✗ Serviço inativo"
echo ""
echo "4. Socket containerd:"
[ -S /run/containerd/containerd.sock ] && echo "   ✓ Socket existe" || echo "   ✗ Socket não encontrado"
echo ""
echo "5. Versão containerd:"
containerd --version
echo ""
echo "6. Configuração CRI:"
grep "SystemdCgroup = true" /etc/containerd/config.toml > /dev/null && echo "   ✓ SystemdCgroup = true" || echo "   ✗ SystemdCgroup não configurado"
echo ""
echo "=== Verificação completa ==="
```

**Saída esperada:**
```
=== Verificação do Container Runtime ===

1. Módulos de kernel:
br_netfilter           32768  0
overlay               151552  0
   ✓ OK

2. Parâmetros sysctl:
   ✓ bridge-nf-call-iptables = 1
   ✓ ip_forward = 1

3. Serviço containerd:
active
   ✓ Serviço ativo

4. Socket containerd:
   ✓ Socket existe

5. Versão containerd:
containerd containerd.io 1.7.13 ...

6. Configuração CRI:
   ✓ SystemdCgroup = true

=== Verificação completa ===
```

Todos os itens devem mostrar `✓`. Se algum mostrar `✗`, consulte a seção de Troubleshooting correspondente acima.
