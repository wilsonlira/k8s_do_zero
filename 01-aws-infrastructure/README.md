# Módulo 01 — Infraestrutura AWS

## Objetivo

Provisionar toda a infraestrutura de rede e computação na AWS necessária para hospedar o cluster Kubernetes. Ao final deste módulo, você terá:

- Uma VPC isolada com subnet pública e conectividade à internet
- Security groups configurados com todas as portas necessárias para os componentes do Kubernetes
- Um par de chaves SSH para acesso remoto às instâncias
- 2 instâncias EC2 (t2.micro) — 1 control plane e 1 worker node
- Volumes EBS dentro do limite de 30 GB do Free Tier
- Conhecimento de cada recurso AWS criado e seu papel na arquitetura

## Teoria

### Arquitetura de Rede para Kubernetes na AWS

Um cluster Kubernetes precisa de uma rede que permita comunicação livre entre seus nós (control plane e workers). Na AWS, isso é implementado usando:

**VPC (Virtual Private Cloud)** — Uma rede virtual isolada dentro da AWS. Funciona como seu próprio data center na nuvem, com controle total sobre endereçamento IP, subnets e regras de tráfego.

**Subnet** — Uma subdivisão da VPC onde as instâncias EC2 são lançadas. Usamos uma subnet pública (com acesso à internet) para que as instâncias possam baixar pacotes e ser acessadas via SSH.

**Internet Gateway (IGW)** — Componente que conecta a VPC à internet. Sem ele, as instâncias não conseguem se comunicar com o mundo externo.

**Route Table** — Tabela de roteamento que define para onde o tráfego de rede é direcionado. Configuramos uma rota padrão (0.0.0.0/0) apontando para o IGW.

**Security Groups** — Firewalls virtuais que controlam o tráfego de entrada e saída das instâncias. Cada componente do Kubernetes precisa de portas específicas abertas.

### Portas Necessárias para o Kubernetes

O Kubernetes utiliza diversas portas para comunicação entre componentes:

| Porta | Protocolo | Componente | Descrição |
|-------|-----------|------------|-----------|
| 6443 | TCP | kube-apiserver | API do Kubernetes (ponto de entrada principal) |
| 2379-2380 | TCP | etcd | Comunicação cliente e peer do etcd |
| 10250 | TCP | kubelet | API do agente de nó |
| 10259 | TCP | kube-scheduler | Endpoint de health/métricas do scheduler |
| 10257 | TCP | kube-controller-manager | Endpoint de health/métricas do controller-manager |
| 30000-32767 | TCP | NodePort Services | Serviços expostos externamente |
| 22 | TCP | SSH | Acesso remoto para administração |

### Instâncias EC2 e Free Tier

O AWS Free Tier oferece 750 horas/mês de instâncias t2.micro (ou t3.micro em algumas regiões). Com 2 instâncias rodando 24/7, o consumo é de ~1.440 horas/mês — o que **excede** o limite gratuito.

**Estratégia para minimizar custos:**
- Pare as instâncias quando não estiver estudando (`aws ec2 stop-instances`)
- Com 2 instâncias, cada uma pode rodar ~12,5 horas/dia dentro do Free Tier
- Termine as instâncias ao concluir o lab (`aws ec2 terminate-instances`)

### Volumes EBS (Elastic Block Store)

Cada instância EC2 precisa de um volume de disco (EBS) para o sistema operacional e dados. O Free Tier inclui 30 GB de armazenamento gp2/gp3 total.

**Configuração deste lab:**
- Control Plane: 15 GB gp3
- Worker Node: 15 GB gp3
- **Total: 30 GB** (exatamente no limite do Free Tier)

> ⚠️ **Aviso de Custo**: Se você criar volumes adicionais ou aumentar os tamanhos, será cobrado ~$0,08/GB/mês para gp3.

### Diagrama da Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                     │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Subnet Pública (10.0.1.0/24)              │  │
│  │                                                        │  │
│  │  ┌──────────────────┐    ┌──────────────────┐         │  │
│  │  │  Control Plane   │    │   Worker Node    │         │  │
│  │  │   (t2.micro)     │    │   (t2.micro)     │         │  │
│  │  │                  │    │                  │         │  │
│  │  │ Portas:          │    │ Portas:          │         │  │
│  │  │ 22, 6443, 2379-  │    │ 22, 10250,       │         │  │
│  │  │ 2380, 10250,     │    │ 30000-32767      │         │  │
│  │  │ 10259, 10257     │    │                  │         │  │
│  │  │ EBS: 15GB gp3    │    │ EBS: 15GB gp3    │         │  │
│  │  └──────────────────┘    └──────────────────┘         │  │
│  │                                                        │  │
│  └────────────────────────────────────────────────────────┘  │
│                              │                               │
│                    ┌─────────┴─────────┐                     │
│                    │  Route Table       │                     │
│                    │  0.0.0.0/0 → IGW  │                     │
│                    └─────────┬─────────┘                     │
│                              │                               │
└──────────────────────────────┼───────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │  Internet Gateway   │
                    └──────────┬──────────┘
                               │
                          ┌────┴────┐
                          │ Internet │
                          └─────────┘
```

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 00 — Pré-requisitos](../00-prerequisites/) — AWS CLI instalado e configurado, credenciais válidas

Variáveis de ambiente necessárias (definidas em `variables.env`):

| Variável | Valor | Descrição |
|----------|-------|-----------|
| `AWS_REGION` | us-east-1 | Região AWS onde os recursos serão criados |
| `INSTANCE_TYPE` | t2.micro | Tipo de instância EC2 (Free Tier) |
| `AMI_ID` | ami-0c7217cdde317cfec | Ubuntu 22.04 LTS para us-east-1 |
| `KEY_NAME` | k8s-lab-key | Nome do par de chaves SSH |
| `VPC_CIDR` | 10.0.0.0/16 | Bloco CIDR da VPC |
| `SUBNET_CIDR` | 10.0.1.0/24 | Bloco CIDR da subnet |
| `CLUSTER_NAME` | k8s-lab | Nome do projeto (usado em tags) |

## Comandos Passo a Passo

Você pode executar os comandos manualmente (recomendado para aprendizado) ou usar os scripts automatizados disponíveis em `scripts/infrastructure/`.

> **Dica**: Para a primeira execução, siga os comandos manuais para entender cada etapa. Nas execuções seguintes, use os scripts para agilizar.

### Usando os Scripts Automatizados

Os scripts devem ser executados na seguinte ordem:

```bash
# 1. Carregar variáveis de configuração
source variables.env

# 2. Criar VPC, subnet, internet gateway e route table
bash scripts/infrastructure/create-vpc.sh

# 3. Exportar IDs dos recursos criados (exibidos na saída do script)
export VPC_ID="vpc-xxxxxxxxx"
export SUBNET_ID="subnet-xxxxxxxxx"

# 4. Criar security groups
bash scripts/infrastructure/create-security-groups.sh

# 5. Exportar IDs dos security groups
export CP_SG_ID="sg-xxxxxxxxx"
export WORKER_SG_ID="sg-xxxxxxxxx"

# 6. Criar par de chaves SSH
bash scripts/infrastructure/create-keypair.sh

# 7. Criar instâncias EC2
bash scripts/infrastructure/create-instances.sh

# 8. Verificar conformidade com Free Tier
bash scripts/infrastructure/verify-free-tier.sh
```

**Saída esperada** (ao final de todos os scripts):
```
=============================================
 EC2 Instances Created Successfully
=============================================

Instance Details:
  Control Plane: i-0abc123... (Public: 54.x.x.x, Private: 10.0.1.x)
  Worker Node:   i-0def456... (Public: 3.x.x.x, Private: 10.0.1.x)
```

---

### Comandos Manuais — Passo 1: Criar VPC

A VPC é a base de toda a infraestrutura de rede. Ela fornece um ambiente de rede isolado onde nosso cluster Kubernetes vai operar.

```bash
# Criar a VPC com bloco CIDR 10.0.0.0/16
# --cidr-block: Define o range de IPs disponíveis (65.536 endereços)
# --tag-specifications: Adiciona tags para identificação e organização
aws ec2 create-vpc \
    --cidr-block "10.0.0.0/16" \
    --region "us-east-1" \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=k8s-lab-vpc},{Key=Project,Value=k8s-lab}]' \
    --query 'Vpc.VpcId' \
    --output text
```

**Saída esperada:**
```
vpc-0a1b2c3d4e5f67890
```

A linha retornada é o ID da VPC criada. Salve este valor para uso nos próximos comandos.

```bash
# Salvar o ID da VPC em uma variável
export VPC_ID="vpc-0a1b2c3d4e5f67890"  # Use o ID retornado acima
```

Agora habilitamos DNS hostnames na VPC. Isso permite que as instâncias recebam nomes DNS públicos, necessários para acesso SSH e para que os componentes do Kubernetes se encontrem por hostname.

```bash
# Habilitar DNS hostnames na VPC
# Sem isso, instâncias não recebem nomes DNS públicos
aws ec2 modify-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --enable-dns-hostnames '{"Value": true}' \
    --region "us-east-1"
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

```bash
# Habilitar suporte a DNS (geralmente já habilitado por padrão)
aws ec2 modify-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --enable-dns-support '{"Value": true}' \
    --region "us-east-1"
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

---

### Comandos Manuais — Passo 2: Criar Subnet

A subnet é onde as instâncias EC2 serão lançadas. Usamos uma subnet pública em uma única Availability Zone (suficiente para um lab).

```bash
# Criar subnet pública dentro da VPC
# --cidr-block 10.0.1.0/24: Fornece 256 endereços IP (mais que suficiente)
# --availability-zone: Especifica a AZ (us-east-1a)
aws ec2 create-subnet \
    --vpc-id "${VPC_ID}" \
    --cidr-block "10.0.1.0/24" \
    --region "us-east-1" \
    --availability-zone "us-east-1a" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=k8s-lab-subnet},{Key=Project,Value=k8s-lab}]' \
    --query 'Subnet.SubnetId' \
    --output text
```

**Saída esperada:**
```
subnet-0a1b2c3d4e5f67890
```

```bash
# Salvar o ID da subnet
export SUBNET_ID="subnet-0a1b2c3d4e5f67890"  # Use o ID retornado acima
```

Habilitamos a atribuição automática de IP público para que as instâncias lançadas nesta subnet recebam um IP público automaticamente (necessário para acesso SSH e download de pacotes).

```bash
# Habilitar auto-assign de IP público na subnet
# Instâncias lançadas aqui receberão automaticamente um IP público
aws ec2 modify-subnet-attribute \
    --subnet-id "${SUBNET_ID}" \
    --map-public-ip-on-launch \
    --region "us-east-1"
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

---

### Comandos Manuais — Passo 3: Criar Internet Gateway

O Internet Gateway permite que as instâncias na VPC se comuniquem com a internet. Sem ele, não é possível baixar pacotes nem acessar as instâncias via SSH de fora da AWS.

```bash
# Criar Internet Gateway
# O IGW é um componente gerenciado pela AWS (altamente disponível e escalável)
aws ec2 create-internet-gateway \
    --region "us-east-1" \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=k8s-lab-igw},{Key=Project,Value=k8s-lab}]' \
    --query 'InternetGateway.InternetGatewayId' \
    --output text
```

**Saída esperada:**
```
igw-0a1b2c3d4e5f67890
```

```bash
# Salvar o ID do Internet Gateway
export IGW_ID="igw-0a1b2c3d4e5f67890"  # Use o ID retornado acima
```

Agora anexamos o IGW à VPC. Um IGW precisa estar "attached" a uma VPC para funcionar.

```bash
# Anexar Internet Gateway à VPC
# Isso habilita a conectividade internet para a VPC
aws ec2 attach-internet-gateway \
    --internet-gateway-id "${IGW_ID}" \
    --vpc-id "${VPC_ID}" \
    --region "us-east-1"
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

---

### Comandos Manuais — Passo 4: Criar Route Table

A Route Table define as regras de roteamento para o tráfego de rede. Precisamos de uma rota padrão que direcione todo o tráfego externo (0.0.0.0/0) para o Internet Gateway.

```bash
# Criar Route Table customizada
# A VPC já tem uma route table principal, mas criamos uma dedicada para controle explícito
aws ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --region "us-east-1" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=k8s-lab-rtb},{Key=Project,Value=k8s-lab}]' \
    --query 'RouteTable.RouteTableId' \
    --output text
```

**Saída esperada:**
```
rtb-0a1b2c3d4e5f67890
```

```bash
# Salvar o ID da Route Table
export RTB_ID="rtb-0a1b2c3d4e5f67890"  # Use o ID retornado acima
```

Adicionamos a rota padrão apontando para o Internet Gateway. O destino `0.0.0.0/0` significa "qualquer tráfego que não corresponda a uma rota mais específica".

```bash
# Adicionar rota padrão para o Internet Gateway
# 0.0.0.0/0 = todo tráfego externo vai para o IGW
aws ec2 create-route \
    --route-table-id "${RTB_ID}" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "${IGW_ID}" \
    --region "us-east-1"
```

**Saída esperada:**
```json
{
    "Return": true
}
```

A linha-chave é `"Return": true` — confirma que a rota foi criada com sucesso.

Associamos a Route Table à subnet para que as instâncias nela usem nossas rotas customizadas.

```bash
# Associar Route Table à Subnet
# Sem essa associação, a subnet usa a route table principal da VPC (sem rota para internet)
aws ec2 associate-route-table \
    --route-table-id "${RTB_ID}" \
    --subnet-id "${SUBNET_ID}" \
    --region "us-east-1" \
    --query 'AssociationId' \
    --output text
```

**Saída esperada:**
```
rtbassoc-0a1b2c3d4e5f67890
```

---

### Comandos Manuais — Passo 5: Criar Security Groups

Security Groups funcionam como firewalls virtuais. Criamos dois: um para o control plane e outro para os worker nodes, cada um com as portas específicas dos componentes que executam.

#### 5.1 Security Group do Control Plane

```bash
# Criar Security Group para o nó Control Plane
# --description: Descrição legível do propósito do SG
aws ec2 create-security-group \
    --group-name "k8s-lab-control-plane-sg" \
    --description "Security group for Kubernetes control plane node" \
    --vpc-id "${VPC_ID}" \
    --region "us-east-1" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=k8s-lab-control-plane-sg},{Key=Project,Value=k8s-lab}]' \
    --query 'GroupId' \
    --output text
```

**Saída esperada:**
```
sg-0a1b2c3d4e5f67890
```

```bash
# Salvar o ID do Security Group do Control Plane
export CP_SG_ID="sg-0a1b2c3d4e5f67890"  # Use o ID retornado acima
```

Agora adicionamos as regras de entrada (inbound rules) para cada componente do control plane:

```bash
# Porta 22 (SSH) — acesso remoto para administração
# --cidr 0.0.0.0/0: Permite SSH de qualquer IP (para lab; em produção, restrinja)
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr "0.0.0.0/0" \
    --region "us-east-1"
```

**Saída esperada:**
```json
{
    "Return": true,
    "SecurityGroupRules": [...]
}
```

```bash
# Porta 6443 (kube-apiserver) — ponto de entrada principal da API do Kubernetes
# Aberta para 0.0.0.0/0 para permitir acesso do kubectl local
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 6443 \
    --cidr "0.0.0.0/0" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Portas 2379-2380 (etcd) — comunicação cliente e peer do banco de dados do cluster
# --cidr 10.0.0.0/16: Restrito à VPC (apenas nós internos precisam acessar)
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 2379-2380 \
    --cidr "10.0.0.0/16" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Porta 10250 (kubelet) — API do agente de nó, usada pelo apiserver para logs/exec
# Restrito à VPC
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 10250 \
    --cidr "10.0.0.0/16" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Porta 10259 (kube-scheduler) — endpoint de health check e métricas
# Restrito à VPC
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 10259 \
    --cidr "10.0.0.0/16" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Porta 10257 (kube-controller-manager) — endpoint de health check e métricas
# Restrito à VPC
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 10257 \
    --cidr "10.0.0.0/16" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

#### 5.2 Security Group do Worker Node

```bash
# Criar Security Group para os Worker Nodes
aws ec2 create-security-group \
    --group-name "k8s-lab-worker-sg" \
    --description "Security group for Kubernetes worker nodes" \
    --vpc-id "${VPC_ID}" \
    --region "us-east-1" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=k8s-lab-worker-sg},{Key=Project,Value=k8s-lab}]' \
    --query 'GroupId' \
    --output text
```

**Saída esperada:**
```
sg-0b2c3d4e5f6789012
```

```bash
# Salvar o ID do Security Group do Worker
export WORKER_SG_ID="sg-0b2c3d4e5f6789012"  # Use o ID retornado acima
```

```bash
# Porta 22 (SSH) — acesso remoto
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr "0.0.0.0/0" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Porta 10250 (kubelet) — API do agente de nó no worker
# Restrito à VPC (o apiserver no control plane precisa acessar)
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol tcp \
    --port 10250 \
    --cidr "10.0.0.0/16" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Portas 30000-32767 (NodePort) — serviços Kubernetes expostos externamente
# Aberto para 0.0.0.0/0 para permitir acesso externo aos serviços
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol tcp \
    --port 30000-32767 \
    --cidr "0.0.0.0/0" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

#### 5.3 Comunicação Inter-Nós

Os nós do Kubernetes precisam se comunicar livremente entre si para pod networking, DNS e comunicação entre componentes. Permitimos todo tráfego entre os dois security groups.

```bash
# Permitir todo tráfego do Control Plane para o Worker
# --protocol -1: Todos os protocolos
# --source-group: Tráfego originado do SG especificado
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol -1 \
    --source-group "${CP_SG_ID}" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Permitir todo tráfego do Worker para o Control Plane
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol -1 \
    --source-group "${WORKER_SG_ID}" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Permitir tráfego dentro do próprio SG do Control Plane (para cenários multi-master)
aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol -1 \
    --source-group "${CP_SG_ID}" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

```bash
# Permitir tráfego dentro do próprio SG do Worker (para comunicação entre workers)
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol -1 \
    --source-group "${WORKER_SG_ID}" \
    --region "us-east-1"
```

**Saída esperada:** JSON com `"Return": true`.

---

### Comandos Manuais — Passo 6: Criar Par de Chaves SSH

O par de chaves SSH é necessário para acessar as instâncias EC2 remotamente. A AWS gera o par e retorna a chave privada apenas uma vez — ela não pode ser recuperada depois.

```bash
# Criar diretório para armazenar a chave privada
mkdir -p keys/
```

**Saída esperada:** Nenhuma saída indica sucesso.

```bash
# Criar par de chaves SSH na AWS
# --key-type rsa: Algoritmo RSA (compatível com todos os clientes SSH)
# --key-format pem: Formato PEM (padrão para OpenSSH)
# A chave privada é retornada via --query e salva no arquivo local
aws ec2 create-key-pair \
    --key-name "k8s-lab-key" \
    --key-type rsa \
    --key-format pem \
    --region "us-east-1" \
    --tag-specifications 'ResourceType=key-pair,Tags=[{Key=Name,Value=k8s-lab-key},{Key=Project,Value=k8s-lab}]' \
    --query 'KeyMaterial' \
    --output text > keys/k8s-lab-key.pem
```

**Saída esperada:** Nenhuma saída no terminal (a chave é redirecionada para o arquivo).

```bash
# Definir permissões restritivas na chave privada
# O SSH exige que a chave não seja acessível por outros usuários (modo 400)
chmod 400 keys/k8s-lab-key.pem
```

**Saída esperada:** Nenhuma saída indica sucesso.

```bash
# Verificar que a chave foi salva corretamente
ls -la keys/k8s-lab-key.pem
```

**Saída esperada:**
```
-r--------  1 user user  1674 Jan  1 00:00 keys/k8s-lab-key.pem
```

A linha-chave é `-r--------` — confirma que apenas o proprietário tem permissão de leitura.

> ⚠️ **Importante**: Se você perder este arquivo, não poderá acessar as instâncias. Será necessário criar um novo par de chaves e recriar as instâncias.

---

### Comandos Manuais — Passo 7: Criar Instâncias EC2

Agora criamos as instâncias EC2 que hospedarão os componentes do Kubernetes. Usamos t2.micro (Free Tier) com Ubuntu 22.04 LTS.

#### 7.1 Instância do Control Plane

O nó control plane executa os componentes de gerenciamento do cluster: etcd, kube-apiserver, kube-scheduler e kube-controller-manager.

```bash
# Criar instância EC2 para o Control Plane
# --image-id: AMI do Ubuntu 22.04 LTS (específica para us-east-1)
# --instance-type t2.micro: Free Tier eligible (1 vCPU, 1 GB RAM)
# --key-name: Par de chaves para acesso SSH
# --subnet-id: Subnet onde a instância será lançada
# --security-group-ids: Firewall com portas do control plane
# --block-device-mappings: Volume EBS de 15 GB gp3
aws ec2 run-instances \
    --image-id "ami-0c7217cdde317cfec" \
    --instance-type "t2.micro" \
    --key-name "k8s-lab-key" \
    --subnet-id "${SUBNET_ID}" \
    --security-group-ids "${CP_SG_ID}" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":15,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=k8s-control-plane},{Key=Project,Value=k8s-lab},{Key=Role,Value=control-plane}]' \
    --region "us-east-1" \
    --query 'Instances[0].InstanceId' \
    --output text
```

**Saída esperada:**
```
i-0a1b2c3d4e5f67890
```

```bash
# Salvar o ID da instância
export CP_INSTANCE_ID="i-0a1b2c3d4e5f67890"  # Use o ID retornado acima
```

> ⚠️ **Aviso Free Tier — Instância t2.micro**:
> - **Elegível**: Sim (750 horas/mês nos primeiros 12 meses da conta)
> - **Limitação**: 1 vCPU e 1 GB de RAM. Suficiente para um lab, mas pode ficar lento com muitos pods
> - **Custo se não elegível**: ~$0,0116/hora (~$8,50/mês) em us-east-1

> ⚠️ **Aviso Free Tier — Volume EBS 15 GB gp3**:
> - **Elegível**: Sim (30 GB total de gp2/gp3 incluídos no Free Tier)
> - **Custo se exceder**: ~$0,08/GB/mês para gp3

#### 7.2 Instância do Worker Node

O worker node executa os workloads (pods). Ele roda kubelet, kube-proxy, o container runtime (containerd) e o plugin CNI.

```bash
# Criar instância EC2 para o Worker Node
# Mesma configuração do control plane, mas com o security group do worker
aws ec2 run-instances \
    --image-id "ami-0c7217cdde317cfec" \
    --instance-type "t2.micro" \
    --key-name "k8s-lab-key" \
    --subnet-id "${SUBNET_ID}" \
    --security-group-ids "${WORKER_SG_ID}" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":15,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=k8s-worker-01},{Key=Project,Value=k8s-lab},{Key=Role,Value=worker}]' \
    --region "us-east-1" \
    --query 'Instances[0].InstanceId' \
    --output text
```

**Saída esperada:**
```
i-0b2c3d4e5f6789012
```

```bash
# Salvar o ID da instância
export WORKER_INSTANCE_ID="i-0b2c3d4e5f6789012"  # Use o ID retornado acima
```

#### 7.3 Aguardar Instâncias Ficarem Prontas

Após o lançamento, as instâncias levam alguns segundos para atingir o estado "running".

```bash
# Aguardar ambas as instâncias atingirem o estado "running"
# Este comando bloqueia até que as instâncias estejam prontas
aws ec2 wait instance-running \
    --instance-ids "${CP_INSTANCE_ID}" "${WORKER_INSTANCE_ID}" \
    --region "us-east-1"
```

**Saída esperada:** Nenhuma saída indica sucesso (as instâncias estão running).

#### 7.4 Obter Endereços IP

```bash
# Obter IP público e privado do Control Plane
aws ec2 describe-instances \
    --instance-ids "${CP_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' \
    --output text
```

**Saída esperada:**
```
54.123.45.67    10.0.1.10
```

A primeira coluna é o IP público (para SSH externo) e a segunda é o IP privado (para comunicação interna do cluster).

```bash
# Obter IP público e privado do Worker Node
aws ec2 describe-instances \
    --instance-ids "${WORKER_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' \
    --output text
```

**Saída esperada:**
```
3.234.56.78    10.0.1.20
```

```bash
# Salvar os IPs para uso nos próximos módulos
export CP_PUBLIC_IP="54.123.45.67"      # Use o IP retornado acima
export CP_PRIVATE_IP="10.0.1.10"        # Use o IP retornado acima
export WORKER_PUBLIC_IP="3.234.56.78"   # Use o IP retornado acima
export WORKER_PRIVATE_IP="10.0.1.20"    # Use o IP retornado acima
```

---

### Comandos Manuais — Passo 8: Verificar Conformidade com Free Tier

Após criar todos os recursos, é importante verificar que tudo está dentro dos limites do Free Tier.

```bash
# Verificar tipos de instância (devem ser t2.micro ou t3.micro)
aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=k8s-lab" "Name=instance-state-name,Values=running" \
    --region "us-east-1" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceType]' \
    --output table
```

**Saída esperada:**
```
-------------------------------------------
|           DescribeInstances             |
+-----------------+-----------------------+
|  k8s-control-plane |  t2.micro          |
|  k8s-worker-01     |  t2.micro          |
+-----------------+-----------------------+
```

A linha-chave é `t2.micro` para ambas as instâncias — confirma elegibilidade ao Free Tier.

```bash
# Verificar tamanho total dos volumes EBS (deve ser ≤ 30 GB)
aws ec2 describe-volumes \
    --filters "Name=attachment.instance-id,Values=${CP_INSTANCE_ID},${WORKER_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'Volumes[].[VolumeId,Size,VolumeType]' \
    --output table
```

**Saída esperada:**
```
-------------------------------------------------
|              DescribeVolumes                   |
+------------------------+------+---------------+
|  vol-0a1b2c3d4e5f67890 |  15  |  gp3          |
|  vol-0b2c3d4e5f6789012 |  15  |  gp3          |
+------------------------+------+---------------+
```

A soma da coluna de tamanho deve ser ≤ 30 GB.

```bash
# Verificar horas estimadas de uso mensal
# 2 instâncias × 24h × 30 dias = 1440 horas (excede 750h do Free Tier)
echo "Instâncias rodando 24/7: 2 × 24 × 30 = 1440 horas/mês"
echo "Limite Free Tier: 750 horas/mês"
echo "Recomendação: Pare as instâncias quando não estiver usando"
echo ""
echo "Para parar: aws ec2 stop-instances --instance-ids ${CP_INSTANCE_ID} ${WORKER_INSTANCE_ID}"
echo "Para iniciar: aws ec2 start-instances --instance-ids ${CP_INSTANCE_ID} ${WORKER_INSTANCE_ID}"
```

> ⚠️ **Resumo de Custos — Free Tier (conta com menos de 12 meses)**:
>
> | Recurso | Uso Neste Lab | Limite Free Tier | Status |
> |---------|---------------|------------------|--------|
> | EC2 t2.micro | 2 instâncias | 750 h/mês | ⚠️ Excede se 24/7 |
> | EBS gp3 | 30 GB total | 30 GB/mês | ✅ No limite |
> | VPC/Subnet/IGW | 1 de cada | Sem custo | ✅ Gratuito |
> | Security Groups | 2 | Sem custo | ✅ Gratuito |
> | IP Público | 2 (auto-assign) | Gratuito com instância running | ✅ Gratuito |
> | Data Transfer | Mínimo | 100 GB/mês | ✅ Dentro do limite |
>
> **Custo estimado se conta NÃO for Free Tier**: ~$17/mês (2× t2.micro 24/7 + 30GB EBS)
>
> **Dica para economizar**: Pare as instâncias quando não estiver estudando. Com ~12h/dia de uso, você fica dentro do Free Tier.

---

### Comandos Manuais — Passo 9: Testar Acesso SSH

Confirme que você consegue acessar ambas as instâncias via SSH.

```bash
# Conectar ao Control Plane via SSH
# -i: Especifica a chave privada
# ubuntu@: Usuário padrão da AMI Ubuntu
ssh -i keys/k8s-lab-key.pem ubuntu@${CP_PUBLIC_IP}
```

**Saída esperada:**
```
Welcome to Ubuntu 22.04.x LTS (GNU/Linux 5.15.x-xxx-generic x86_64)
...
ubuntu@ip-10-0-1-10:~$
```

A linha-chave é o prompt `ubuntu@ip-10-0-1-x:~$` — confirma acesso SSH bem-sucedido.

```bash
# Conectar ao Worker Node via SSH (em outro terminal)
ssh -i keys/k8s-lab-key.pem ubuntu@${WORKER_PUBLIC_IP}
```

**Saída esperada:**
```
Welcome to Ubuntu 22.04.x LTS (GNU/Linux 5.15.x-xxx-generic x86_64)
...
ubuntu@ip-10-0-1-20:~$
```

---

## Verificação

Execute os comandos abaixo para confirmar que toda a infraestrutura foi criada corretamente.

### Verificar VPC

```bash
aws ec2 describe-vpcs \
    --vpc-ids "${VPC_ID}" \
    --region "us-east-1" \
    --query 'Vpcs[0].[VpcId,CidrBlock,State]' \
    --output text
```

**Saída esperada:**
```
vpc-0a1b2c3d4e5f67890    10.0.0.0/16    available
```

A linha-chave é `available` — confirma que a VPC está ativa.

### Verificar Subnet

```bash
aws ec2 describe-subnets \
    --subnet-ids "${SUBNET_ID}" \
    --region "us-east-1" \
    --query 'Subnets[0].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
    --output text
```

**Saída esperada:**
```
subnet-0a1b2c3d4e5f67890    10.0.1.0/24    us-east-1a    True
```

A linha-chave é `True` no final — confirma que IPs públicos são atribuídos automaticamente.

### Verificar Internet Gateway

```bash
aws ec2 describe-internet-gateways \
    --internet-gateway-ids "${IGW_ID}" \
    --region "us-east-1" \
    --query 'InternetGateways[0].[InternetGatewayId,Attachments[0].State]' \
    --output text
```

**Saída esperada:**
```
igw-0a1b2c3d4e5f67890    available
```

A linha-chave é `available` — confirma que o IGW está anexado à VPC.

### Verificar Security Groups

```bash
# Listar regras do Security Group do Control Plane
aws ec2 describe-security-groups \
    --group-ids "${CP_SG_ID}" \
    --region "us-east-1" \
    --query 'SecurityGroups[0].IpPermissions[].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,Source:IpRanges[0].CidrIp||UserIdGroupPairs[0].GroupId}' \
    --output table
```

**Saída esperada:**
```
------------------------------------------------------
|            DescribeSecurityGroups                   |
+----------+----------+--------+--------------------+
| FromPort | Protocol | Source | ToPort             |
+----------+----------+--------+--------------------+
|  22      |  tcp     | 0.0.0.0/0 |  22             |
|  6443    |  tcp     | 0.0.0.0/0 |  6443           |
|  2379    |  tcp     | 10.0.0.0/16 |  2380         |
|  10250   |  tcp     | 10.0.0.0/16 |  10250        |
|  10259   |  tcp     | 10.0.0.0/16 |  10259        |
|  10257   |  tcp     | 10.0.0.0/16 |  10257        |
+----------+----------+--------+--------------------+
```

### Verificar Instâncias EC2

```bash
aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=k8s-lab" "Name=instance-state-name,Values=running" \
    --region "us-east-1" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress]' \
    --output table
```

**Saída esperada:**
```
---------------------------------------------------------------------------
|                          DescribeInstances                               |
+--------------------+---------------------+----------+---------+----------+
| k8s-control-plane  | i-0a1b2c3d4e5f67890 | t2.micro | running | 54.x.x.x |
| k8s-worker-01      | i-0b2c3d4e5f6789012 | t2.micro | running | 3.x.x.x  |
+--------------------+---------------------+----------+---------+----------+
```

A linha-chave é `running` para ambas as instâncias.

### Verificar Conectividade SSH

```bash
# Testar SSH no Control Plane (sem abrir sessão interativa)
ssh -i keys/k8s-lab-key.pem -o ConnectTimeout=5 ubuntu@${CP_PUBLIC_IP} "hostname && echo 'SSH OK'"
```

**Saída esperada:**
```
ip-10-0-1-10
SSH OK
```

```bash
# Testar SSH no Worker Node
ssh -i keys/k8s-lab-key.pem -o ConnectTimeout=5 ubuntu@${WORKER_PUBLIC_IP} "hostname && echo 'SSH OK'"
```

**Saída esperada:**
```
ip-10-0-1-20
SSH OK
```

### Verificar Comunicação Inter-Nós

Dentro do Control Plane, verifique que ele consegue alcançar o Worker Node pela rede interna:

```bash
# A partir do Control Plane, pingar o Worker Node pelo IP privado
ssh -i keys/k8s-lab-key.pem ubuntu@${CP_PUBLIC_IP} "ping -c 3 ${WORKER_PRIVATE_IP}"
```

**Saída esperada:**
```
PING 10.0.1.20 (10.0.1.20) 56(84) bytes of data.
64 bytes from 10.0.1.20: icmp_seq=1 ttl=64 time=0.5 ms
64 bytes from 10.0.1.20: icmp_seq=2 ttl=64 time=0.4 ms
64 bytes from 10.0.1.20: icmp_seq=3 ttl=64 time=0.4 ms

--- 10.0.1.20 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

A linha-chave é `0% packet loss` — confirma comunicação de rede entre os nós.

### Verificar Volumes EBS

```bash
# Verificar que o total de EBS está dentro do Free Tier (≤ 30 GB)
TOTAL_EBS=$(aws ec2 describe-volumes \
    --filters "Name=attachment.instance-id,Values=${CP_INSTANCE_ID},${WORKER_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'sum(Volumes[].Size)' \
    --output text)
echo "Total EBS: ${TOTAL_EBS} GB (limite Free Tier: 30 GB)"
```

**Saída esperada:**
```
Total EBS: 30 GB (limite Free Tier: 30 GB)
```

### Script de Verificação Completa

Use o script automatizado para verificar toda a infraestrutura de uma vez:

```bash
bash scripts/infrastructure/verify-free-tier.sh
```

**Saída esperada:**
```
=============================================
 Free Tier Verification Summary
=============================================

  ✓ All resources are within AWS Free Tier limits

Free Tier Checklist:
  [✓] Instance type: t2.micro (need t2.micro or t3.micro)
  [✓] EBS storage: 30 GB (limit: 30 GB)
  [⚠] Instance hours: ~1440/month (limit: 750)
  [✓] Elastic IPs: 0 unassociated (should be 0)
```

---

## Troubleshooting

### Problema: Falha ao criar VPC — limite de VPCs atingido

**Sintoma:**
```
An error occurred (VpcLimitExceeded) when calling the CreateVpc operation:
The maximum number of VPCs has been reached.
```

**Causa provável:** Cada região AWS tem um limite padrão de 5 VPCs. Se você já tem 5 VPCs na região us-east-1, não é possível criar mais.

**Resolução:**
```bash
# Listar VPCs existentes na região
aws ec2 describe-vpcs \
    --region "us-east-1" \
    --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' \
    --output table

# Opção 1: Deletar uma VPC não utilizada
aws ec2 delete-vpc --vpc-id vpc-xxxxxxxx --region "us-east-1"

# Opção 2: Usar outra região (altere AWS_REGION em variables.env)
# Nota: Será necessário atualizar o AMI_ID para a nova região

# Opção 3: Solicitar aumento de limite via AWS Support Console
```

---

### Problema: Falha ao criar instância — limite de instâncias atingido

**Sintoma:**
```
An error occurred (InstanceLimitExceeded) when calling the RunInstances operation:
You have requested more vCPU capacity than your current vCPU limit allows.
```

**Causa provável:** Contas AWS novas têm limites de vCPU por região. O limite padrão para instâncias On-Demand é geralmente 5 vCPUs para contas novas.

**Resolução:**
```bash
# Verificar limite atual de vCPUs
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-1216C47A \
    --region "us-east-1" \
    --query 'Quota.Value'

# Verificar instâncias em execução
aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --region "us-east-1" \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType]' \
    --output table

# Opção 1: Terminar instâncias não utilizadas
aws ec2 terminate-instances --instance-ids i-xxxxxxxx --region "us-east-1"

# Opção 2: Solicitar aumento de quota via AWS Console
# Service Quotas → EC2 → Running On-Demand Standard instances
```

---

### Problema: SSH connection timed out

**Sintoma:**
```
ssh: connect to host 54.x.x.x port 22: Connection timed out
```

**Causa provável:** O security group não permite tráfego na porta 22, a instância não tem IP público, ou a instância ainda está inicializando.

**Resolução:**
```bash
# 1. Verificar se a instância está no estado "running"
aws ec2 describe-instances \
    --instance-ids "${CP_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text
# Esperado: "running"

# 2. Verificar se a instância tem IP público
aws ec2 describe-instances \
    --instance-ids "${CP_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text
# Se retornar "None", a subnet não está atribuindo IPs públicos

# 3. Verificar regras do security group (porta 22)
aws ec2 describe-security-groups \
    --group-ids "${CP_SG_ID}" \
    --region "us-east-1" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'

# 4. Aguardar a instância passar nos status checks
aws ec2 wait instance-status-ok \
    --instance-ids "${CP_INSTANCE_ID}" \
    --region "us-east-1"
# Após este comando completar, tente SSH novamente
```

---

### Problema: SSH permission denied (publickey)

**Sintoma:**
```
Permission denied (publickey).
```

**Causa provável:** A chave privada está incorreta, tem permissões erradas, ou o nome de usuário está errado.

**Resolução:**
```bash
# 1. Verificar permissões da chave (deve ser 400)
ls -la keys/k8s-lab-key.pem
# Se não for -r--------, corrigir:
chmod 400 keys/k8s-lab-key.pem

# 2. Verificar que está usando o usuário correto
# Para Ubuntu AMI, o usuário é "ubuntu" (não "ec2-user" ou "root")
ssh -i keys/k8s-lab-key.pem ubuntu@${CP_PUBLIC_IP}

# 3. Verificar que a chave corresponde ao key pair da instância
aws ec2 describe-instances \
    --instance-ids "${CP_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'Reservations[0].Instances[0].KeyName' \
    --output text
# Deve retornar "k8s-lab-key"

# 4. Se a chave foi perdida, será necessário recriar:
#    - Terminar a instância
#    - Deletar o key pair antigo
#    - Criar novo key pair
#    - Recriar a instância com o novo key pair
```

---

### Problema: Security group rule already exists

**Sintoma:**
```
An error occurred (InvalidPermission.Duplicate) when calling the
AuthorizeSecurityGroupIngress operation: the specified rule already exists
```

**Causa provável:** A regra de security group já foi adicionada anteriormente (possivelmente de uma execução anterior do script).

**Resolução:**
```bash
# Listar regras existentes do security group
aws ec2 describe-security-groups \
    --group-ids "${CP_SG_ID}" \
    --region "us-east-1" \
    --query 'SecurityGroups[0].IpPermissions[]' \
    --output json

# Se a regra já existe, não é necessário adicioná-la novamente
# O erro pode ser ignorado com segurança — a regra já está ativa

# Para remover uma regra e recriá-la (se necessário):
aws ec2 revoke-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol tcp \
    --port 6443 \
    --cidr "0.0.0.0/0" \
    --region "us-east-1"
```

---

### Problema: Key pair already exists

**Sintoma:**
```
An error occurred (InvalidKeyPair.Duplicate) when calling the CreateKeyPair
operation: The keypair 'k8s-lab-key' already exists.
```

**Causa provável:** Um key pair com o mesmo nome já existe na região. Isso pode acontecer se o script foi executado anteriormente.

**Resolução:**
```bash
# Verificar se o key pair existe
aws ec2 describe-key-pairs \
    --key-names "k8s-lab-key" \
    --region "us-east-1"

# Opção 1: Usar o key pair existente (se você tem a chave privada)
# Verifique se o arquivo keys/k8s-lab-key.pem existe e está correto

# Opção 2: Deletar e recriar (se a chave privada foi perdida)
aws ec2 delete-key-pair \
    --key-name "k8s-lab-key" \
    --region "us-east-1"
# Depois execute o script create-keypair.sh novamente
```

---

### Problema: AMI não encontrada

**Sintoma:**
```
An error occurred (InvalidAMIID.NotFound) when calling the RunInstances
operation: The image id 'ami-0c7217cdde317cfec' does not exist
```

**Causa provável:** O AMI ID é específico por região. Se você mudou a região, o AMI ID do Ubuntu 22.04 será diferente.

**Resolução:**
```bash
# Buscar o AMI mais recente do Ubuntu 22.04 LTS na sua região
aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
              "Name=state,Values=available" \
    --region "us-east-1" \
    --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name]' \
    --output text

# Atualizar o AMI_ID em variables.env com o ID retornado
# Exemplo: ami-0abcdef1234567890
```

---

### Problema: Instância não recebe IP público

**Sintoma:** O campo `PublicIpAddress` retorna `None` ao descrever a instância.

**Causa provável:** A subnet não está configurada para atribuir IPs públicos automaticamente, ou a instância foi lançada sem a opção de IP público.

**Resolução:**
```bash
# Verificar configuração da subnet
aws ec2 describe-subnets \
    --subnet-ids "${SUBNET_ID}" \
    --region "us-east-1" \
    --query 'Subnets[0].MapPublicIpOnLaunch'
# Deve retornar "true"

# Se retornar "false", habilitar:
aws ec2 modify-subnet-attribute \
    --subnet-id "${SUBNET_ID}" \
    --map-public-ip-on-launch \
    --region "us-east-1"

# Para instâncias já criadas sem IP público, associar um Elastic IP:
ALLOC_ID=$(aws ec2 allocate-address --domain vpc --region "us-east-1" --query 'AllocationId' --output text)
aws ec2 associate-address \
    --instance-id "${CP_INSTANCE_ID}" \
    --allocation-id "${ALLOC_ID}" \
    --region "us-east-1"

# Nota: Elastic IPs são gratuitos quando associados a uma instância running
```

---

### Problema: Comunicação entre nós falha (ping timeout)

**Sintoma:**
```
PING 10.0.1.20 (10.0.1.20) 56(84) bytes of data.
--- 10.0.1.20 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss
```

**Causa provável:** As regras de inter-node communication nos security groups não foram configuradas, ou as instâncias estão em subnets/VPCs diferentes.

**Resolução:**
```bash
# 1. Verificar que ambas as instâncias estão na mesma subnet
aws ec2 describe-instances \
    --instance-ids "${CP_INSTANCE_ID}" "${WORKER_INSTANCE_ID}" \
    --region "us-east-1" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],SubnetId,VpcId]' \
    --output table

# 2. Verificar regras de inter-node nos security groups
aws ec2 describe-security-groups \
    --group-ids "${CP_SG_ID}" \
    --region "us-east-1" \
    --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`-1`]'

# 3. Se as regras inter-node não existem, adicioná-las:
aws ec2 authorize-security-group-ingress \
    --group-id "${WORKER_SG_ID}" \
    --protocol -1 \
    --source-group "${CP_SG_ID}" \
    --region "us-east-1"

aws ec2 authorize-security-group-ingress \
    --group-id "${CP_SG_ID}" \
    --protocol -1 \
    --source-group "${WORKER_SG_ID}" \
    --region "us-east-1"
```

---

## Limpeza de Recursos

Quando terminar de usar o lab, remova todos os recursos para evitar cobranças:

```bash
# Usar o script de limpeza automatizado
bash scripts/cleanup/cleanup.sh

# Ou manualmente, na ordem inversa:
# 1. Terminar instâncias
aws ec2 terminate-instances \
    --instance-ids "${CP_INSTANCE_ID}" "${WORKER_INSTANCE_ID}" \
    --region "us-east-1"

# 2. Aguardar terminação
aws ec2 wait instance-terminated \
    --instance-ids "${CP_INSTANCE_ID}" "${WORKER_INSTANCE_ID}" \
    --region "us-east-1"

# 3. Deletar key pair
aws ec2 delete-key-pair --key-name "k8s-lab-key" --region "us-east-1"

# 4. Deletar security groups
aws ec2 delete-security-group --group-id "${CP_SG_ID}" --region "us-east-1"
aws ec2 delete-security-group --group-id "${WORKER_SG_ID}" --region "us-east-1"

# 5. Desassociar e deletar route table
aws ec2 delete-route-table --route-table-id "${RTB_ID}" --region "us-east-1"

# 6. Desanexar e deletar internet gateway
aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" --region "us-east-1"
aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" --region "us-east-1"

# 7. Deletar subnet
aws ec2 delete-subnet --subnet-id "${SUBNET_ID}" --region "us-east-1"

# 8. Deletar VPC
aws ec2 delete-vpc --vpc-id "${VPC_ID}" --region "us-east-1"
```

---

## Próximo Módulo

Após confirmar que a infraestrutura está funcionando e você consegue acessar ambas as instâncias via SSH, prossiga para:

➡️ [Módulo 02 — Certificados TLS](../02-tls-certificates/)
