# Kubernetes Lab — Construindo um Cluster do Zero na AWS Free Tier

Projeto educacional para ensinar Kubernetes do zero, utilizando a AWS Free Tier. O objetivo é construir um cluster Kubernetes funcional componente a componente, explicando o papel de cada um, com instruções passo a passo e comando a comando.

Ao final, um teste prático simulando o exame CKA (Certified Kubernetes Administrator) é aplicado para validar o aprendizado.

## Arquitetura do Cluster

```
┌─────────────────────────────────────────────────────────────────┐
│                     Control Plane (t2.micro)                     │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐    │
│  │   etcd   │  │ kube-apiserver│  │ kube-controller-manager│    │
│  └──────────┘  └──────────────┘  └────────────────────────┘    │
│                                   ┌────────────────┐            │
│                                   │ kube-scheduler │            │
│                                   └────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ API (port 6443)
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      Worker Node (t2.micro)                      │
│  ┌──────────┐  ┌────────────┐  ┌───────────┐  ┌───────────┐   │
│  │ kubelet  │  │ kube-proxy │  │ containerd│  │ CNI Plugin│   │
│  └──────────┘  └────────────┘  └───────────┘  └───────────┘   │
│                                                                  │
│  ┌──────────────────┐  ┌────────────────────────┐              │
│  │   CoreDNS Pod    │  │  Ingress Controller Pod │              │
│  └──────────────────┘  └────────────────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

## Pré-requisitos

Antes de iniciar o lab, você precisa ter:

- **Conta AWS** com acesso ao Free Tier (conta criada há menos de 12 meses)
- **AWS CLI v2** instalado e configurado com credenciais válidas
- **SSH client** (OpenSSH ou PuTTY)
- **openssl** para geração e inspeção de certificados
- **kubectl** (será instalado durante o lab, mas pode ser pré-instalado)
- **Conhecimento básico** de Linux, redes TCP/IP e linha de comando

## Estrutura do Projeto

```
lab_k8s/
├── README.md                    # Este arquivo
├── variables.env                # Configuração centralizada do lab
├── docs/                        # Módulos educacionais
│   ├── 00-prerequisites/        # Pré-requisitos e ferramentas
│   ├── 01-aws-infrastructure/   # Provisionamento AWS
│   ├── 02-tls-certificates/     # Certificados TLS (PKI)
│   ├── 03-container-runtime/    # Container runtime (containerd)
│   ├── 04-etcd/                 # Banco de dados do cluster
│   ├── 05-kube-apiserver/       # API Server
│   ├── 06-kube-controller-manager/ # Controller Manager
│   ├── 07-kube-scheduler/       # Scheduler
│   ├── 08-kubelet/              # Agente do nó worker
│   ├── 09-kube-proxy/           # Proxy de rede
│   ├── 10-cni-networking/       # Plugin CNI (rede pod-to-pod)
│   ├── 11-coredns/              # DNS do cluster
│   ├── 12-kubectl-kubeconfig/   # CLI e configuração de acesso
│   ├── 13-ingress-controller/   # Ingress Controller (NGINX)
│   └── 14-cluster-validation/   # Validação final do cluster
├── scripts/
│   ├── infrastructure/          # Scripts de provisionamento AWS
│   ├── certificates/            # Scripts de geração de certificados
│   ├── verification/            # Scripts de verificação
│   └── cleanup/                 # Scripts de limpeza de recursos
├── configs/
│   ├── pki/                     # Certificados e chaves TLS
│   ├── systemd/                 # Unit files dos serviços
│   ├── kubernetes/              # Kubeconfig files
│   ├── containerd/              # Configuração do containerd
│   ├── cni/                     # Manifesto do plugin CNI
│   └── coredns/                 # Manifesto do CoreDNS
└── cka-simulator/
    ├── exam-guide.md            # Guia do exame simulado
    ├── scoring.md               # Mecanismo de pontuação
    ├── tasks/                   # Tarefas do simulado CKA
    └── solutions/               # Soluções das tarefas
```

## Guia de Navegação — Ordem dos Módulos

Os módulos devem ser seguidos na ordem abaixo. Cada módulo lista seus pré-requisitos explicitamente.

| # | Módulo | Descrição |
|---|--------|-----------|
| 00 | [Pré-requisitos](docs/00-prerequisites/) | Ferramentas e configuração inicial |
| 01 | [Infraestrutura AWS](docs/01-aws-infrastructure/) | VPC, subnets, security groups, EC2 |
| 02 | [Certificados TLS](docs/02-tls-certificates/) | PKI, CA, certificados de componentes |
| 03 | [Container Runtime](docs/03-container-runtime/) | containerd e CRI |
| 04 | [etcd](docs/04-etcd/) | Banco de dados distribuído do cluster |
| 05 | [kube-apiserver](docs/05-kube-apiserver/) | API Server do control plane |
| 06 | [kube-controller-manager](docs/06-kube-controller-manager/) | Controladores de reconciliação |
| 07 | [kube-scheduler](docs/07-kube-scheduler/) | Agendamento de pods nos nós |
| 08 | [kubelet](docs/08-kubelet/) | Agente do nó worker |
| 09 | [kube-proxy](docs/09-kube-proxy/) | Regras de rede para serviços |
| 10 | [CNI Networking](docs/10-cni-networking/) | Rede pod-to-pod entre nós |
| 11 | [CoreDNS](docs/11-coredns/) | Service discovery via DNS |
| 12 | [kubectl & kubeconfig](docs/12-kubectl-kubeconfig/) | CLI e acesso ao cluster |
| 13 | [Ingress Controller](docs/13-ingress-controller/) | Roteamento HTTP/HTTPS externo |
| 14 | [Validação do Cluster](docs/14-cluster-validation/) | Verificação completa do cluster |

Após completar todos os módulos, realize o [Simulador CKA](cka-simulator/) para testar seus conhecimentos.

## Configuração Rápida

1. Clone este repositório
2. Revise e ajuste os parâmetros em `variables.env` conforme necessário
3. Siga os módulos na ordem indicada, começando pelo módulo 00

```bash
# Carregar variáveis de configuração
source variables.env

# Verificar configuração AWS
aws sts get-caller-identity
```

## Custos Estimados

Este lab foi projetado para operar **inteiramente dentro do AWS Free Tier**:

| Recurso | Configuração | Free Tier |
|---------|-------------|-----------|
| EC2 | 2x t2.micro | 750 horas/mês |
| EBS | 2x 15GB gp3 | 30 GB/mês |
| VPC | 1 VPC + subnets | Sem custo |
| Data Transfer | Mínimo | 100 GB/mês saída |

> **Atenção**: O Free Tier é válido por 12 meses após a criação da conta AWS. Sempre execute os scripts de cleanup após terminar o lab para evitar cobranças.

## Limpeza de Recursos

Após concluir o lab, remova todos os recursos AWS:

```bash
source variables.env
bash scripts/cleanup/cleanup.sh
```

## Licença

Este projeto é disponibilizado para fins educacionais.
