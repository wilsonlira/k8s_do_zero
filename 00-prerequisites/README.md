# Módulo 00 — Pré-requisitos

## Objetivo

Preparar o ambiente local com todas as ferramentas e configurações necessárias para construir o cluster Kubernetes na AWS. Ao final deste módulo, você terá:

- Uma conta AWS configurada com as permissões adequadas
- AWS CLI instalado e autenticado
- Ferramentas de criptografia (openssl, cfssl) para geração de certificados TLS
- Cliente SSH para acesso remoto às instâncias EC2
- Conhecimento dos custos e limites do AWS Free Tier

## Teoria

### Por que esses pré-requisitos são necessários?

Construir um cluster Kubernetes do zero ("the hard way") exige interação direta com a infraestrutura de nuvem e geração manual de certificados TLS para comunicação segura entre componentes. Diferente de ferramentas como `kubeadm` ou `kops` que automatizam esses passos, neste lab cada etapa é executada manualmente para fins educacionais.

**AWS CLI** é a interface de linha de comando que permite criar e gerenciar recursos na AWS (VPC, EC2, Security Groups) de forma programática e reproduzível.

**Certificados TLS** são fundamentais no Kubernetes — cada componente (etcd, kube-apiserver, kubelet, etc.) se autentica mutuamente usando certificados. As ferramentas `openssl` e `cfssl` são usadas para gerar a Autoridade Certificadora (CA) e os certificados individuais.

**SSH** é o protocolo usado para acessar remotamente as instâncias EC2 onde os componentes do Kubernetes serão instalados.

### Modelo de Custos — AWS Free Tier

O AWS Free Tier oferece 12 meses de uso gratuito para contas novas, incluindo:

| Recurso | Limite Gratuito |
|---------|----------------|
| EC2 (t2.micro) | 750 horas/mês |
| EBS (gp2/gp3) | 30 GB/mês |
| Data Transfer (saída) | 100 GB/mês |
| VPC, Subnets, Security Groups | Sem custo |

> **Importante**: O Free Tier é válido apenas para contas criadas há menos de 12 meses. Após esse período, todos os recursos passam a ser cobrados.

## Pré-requisitos

Este é o primeiro módulo do lab. Não há módulos anteriores necessários.

Você precisa de:

- Um computador com acesso à internet
- Sistema operacional Linux, macOS ou Windows (com WSL2 recomendado)
- Permissão para instalar software no sistema

## Comandos Passo a Passo

### 1. Configurar Conta AWS

Antes de instalar qualquer ferramenta, você precisa de uma conta AWS com as permissões corretas.

#### 1.1 Criar conta AWS (se ainda não tiver)

Acesse [https://aws.amazon.com/free](https://aws.amazon.com/free) e crie uma conta. Você precisará de:
- Email válido
- Cartão de crédito (para verificação, não será cobrado dentro do Free Tier)
- Número de telefone para verificação

#### 1.2 Criar usuário IAM com permissões necessárias

O comando abaixo cria um usuário IAM dedicado para o lab. Não use o usuário root da conta AWS para operações do dia a dia.

```bash
# Criar usuário IAM para o lab
aws iam create-user --user-name k8s-lab-user
```

**Saída esperada:**
```json
{
    "User": {
        "Path": "/",
        "UserName": "k8s-lab-user",
        "UserId": "AIDAEXAMPLE123456789",
        "Arn": "arn:aws:iam::123456789012:user/k8s-lab-user",
        "CreateDate": "2024-01-01T00:00:00Z"
    }
}
```

#### 1.3 Anexar políticas IAM necessárias

O usuário precisa de permissões para gerenciar EC2, VPC e IAM. As políticas abaixo concedem acesso suficiente para o lab:

```bash
# Permissão para gerenciar instâncias EC2 e networking
aws iam attach-user-policy \
  --user-name k8s-lab-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

```bash
# Permissão para gerenciar VPC e componentes de rede
aws iam attach-user-policy \
  --user-name k8s-lab-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
```

**Saída esperada:** Nenhuma saída indica sucesso (exit code 0).

> **Nota de segurança**: Em ambientes de produção, use políticas com privilégio mínimo. Para este lab educacional, as políticas FullAccess simplificam o processo. Após concluir o lab, remova o usuário e suas permissões.

#### 1.4 Criar credenciais de acesso programático

```bash
# Gerar Access Key para uso com AWS CLI
aws iam create-access-key --user-name k8s-lab-user
```

**Saída esperada:**
```json
{
    "AccessKey": {
        "UserName": "k8s-lab-user",
        "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
        "Status": "Active",
        "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "CreateDate": "2024-01-01T00:00:00Z"
    }
}
```

> **Importante**: Anote o `AccessKeyId` e `SecretAccessKey`. O SecretAccessKey é exibido apenas uma vez.

---

### 2. Instalar AWS CLI v2

O AWS CLI é a ferramenta principal para interagir com a AWS via linha de comando. Todos os scripts deste lab utilizam o AWS CLI para provisionar infraestrutura.

#### Linux (x86_64)

```bash
# Baixar o instalador do AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Descompactar o instalador
unzip awscliv2.zip

# Executar a instalação (requer sudo)
sudo ./aws/install
```

**Saída esperada:**
```
You can now run: /usr/local/bin/aws --version
```

#### macOS

```bash
# Baixar o instalador do AWS CLI v2 para macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

# Instalar o pacote
sudo installer -pkg AWSCLIV2.pkg -target /
```

**Saída esperada:**
```
installer: Package name is AWS Command Line Interface
installer: Installing at base path /
```

#### Windows (via WSL2 — recomendado)

Se estiver usando Windows, recomendamos instalar o WSL2 e seguir as instruções de Linux acima. Alternativamente:

```powershell
# Baixar e executar o instalador MSI
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

#### Configurar credenciais AWS

Após instalar o AWS CLI, configure as credenciais do usuário IAM criado anteriormente:

```bash
# Configurar AWS CLI com as credenciais
aws configure
```

O comando solicitará as seguintes informações:
```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

---

### 3. Instalar OpenSSL

O OpenSSL é usado para gerar e inspecionar certificados TLS. A maioria dos sistemas Linux e macOS já possui o OpenSSL instalado.

#### Linux (Debian/Ubuntu)

```bash
# Instalar OpenSSL (geralmente já está instalado)
sudo apt-get update && sudo apt-get install -y openssl
```

**Saída esperada:**
```
openssl is already the newest version (3.0.x-xubuntuX).
```

#### macOS

```bash
# Instalar via Homebrew (versão mais recente)
brew install openssl
```

**Saída esperada:**
```
==> Pouring openssl@3--3.x.x.arm64_sonoma.bottle.tar.gz
🍺  /opt/homebrew/Cellar/openssl@3/3.x.x: xxx files, xxMB
```

---

### 4. Instalar CFSSL e CFSSLJSON

O CFSSL (CloudFlare's SSL toolkit) é uma ferramenta para geração de certificados TLS que simplifica a criação de CAs e certificados com configuração JSON. Será usado no módulo de certificados TLS para gerar todos os certificados do cluster.

#### Linux (x86_64)

```bash
# Baixar cfssl
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64 \
  -o /usr/local/bin/cfssl

# Baixar cfssljson (converte saída JSON do cfssl em arquivos de certificado)
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64 \
  -o /usr/local/bin/cfssljson

# Tornar executáveis
chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
```

**Saída esperada:** Nenhuma saída indica sucesso. Os binários estarão disponíveis em `/usr/local/bin/`.

#### macOS

```bash
# Instalar via Homebrew
brew install cfssl
```

**Saída esperada:**
```
==> Pouring cfssl--1.6.x.arm64_sonoma.bottle.tar.gz
🍺  /opt/homebrew/Cellar/cfssl/1.6.x: x files, xxMB
```

---

### 5. Verificar Cliente SSH

O SSH é necessário para acessar remotamente as instâncias EC2 onde os componentes do Kubernetes serão instalados. O OpenSSH client geralmente já está instalado em sistemas Linux e macOS.

#### Linux/macOS

```bash
# Verificar se o cliente SSH está disponível
which ssh
```

**Saída esperada:**
```
/usr/bin/ssh
```

#### Instalar se necessário (Debian/Ubuntu)

```bash
# Instalar cliente OpenSSH
sudo apt-get install -y openssh-client
```

**Saída esperada:**
```
openssh-client is already the newest version (1:9.x...).
```

---

### 6. Instalar kubectl (opcional neste momento)

O kubectl será instalado e configurado em detalhes no [Módulo 12 — kubectl & kubeconfig](../12-kubectl-kubeconfig/). Porém, se desejar instalá-lo antecipadamente:

```bash
# Baixar kubectl na versão compatível com o cluster
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"

# Tornar executável e mover para o PATH
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Saída esperada:** Nenhuma saída indica sucesso.

## Verificação

Execute os comandos abaixo para confirmar que todas as ferramentas estão instaladas corretamente.

### Verificar AWS CLI

```bash
aws --version
```

**Saída esperada** (a versão exata pode variar):
```
aws-cli/2.15.x Python/3.11.x Linux/6.x.x-xxx source/x86_64.ubuntu.22
```

A linha-chave é `aws-cli/2.x.x` — confirma que a versão 2 está instalada.

### Verificar autenticação AWS

```bash
aws sts get-caller-identity
```

**Saída esperada:**
```json
{
    "UserId": "AIDAEXAMPLE123456789",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/k8s-lab-user"
}
```

A linha-chave é o campo `"Arn"` — confirma que as credenciais estão configuradas e válidas.

### Verificar região configurada

```bash
aws configure get region
```

**Saída esperada:**
```
us-east-1
```

### Verificar OpenSSL

```bash
openssl version
```

**Saída esperada:**
```
OpenSSL 3.0.x xx Xxx xxxx (Library: OpenSSL 3.0.x xx Xxx xxxx)
```

A linha-chave é `OpenSSL 3.x.x` ou `OpenSSL 1.1.x` — ambas versões são compatíveis com o lab.

### Verificar CFSSL

```bash
cfssl version
```

**Saída esperada:**
```
Version: 1.6.4
Runtime: go1.21.x
```

### Verificar CFSSLJSON

```bash
cfssljson --version
```

**Saída esperada:**
```
Version: 1.6.4
Runtime: go1.21.x
```

### Verificar SSH

```bash
ssh -V
```

**Saída esperada:**
```
OpenSSH_9.x...
```

A linha-chave é `OpenSSH_` seguido de um número de versão — confirma que o cliente SSH está disponível.

### Verificar kubectl (se instalado)

```bash
kubectl version --client
```

**Saída esperada:**
```
Client Version: v1.29.0
Kustomize Version: v5.x.x
```

### Script de verificação completa

Execute o script abaixo para verificar todos os pré-requisitos de uma vez:

```bash
#!/bin/bash
echo "=== Verificação de Pré-requisitos do Lab Kubernetes ==="
echo ""

# Verificar AWS CLI
echo -n "[1/6] AWS CLI v2........... "
if aws --version 2>/dev/null | grep -q "aws-cli/2"; then
    echo "✅ OK ($(aws --version 2>&1 | cut -d' ' -f1))"
else
    echo "❌ NÃO ENCONTRADO"
fi

# Verificar autenticação AWS
echo -n "[2/6] AWS Credentials...... "
if aws sts get-caller-identity &>/dev/null; then
    echo "✅ OK ($(aws sts get-caller-identity --query 'Arn' --output text))"
else
    echo "❌ NÃO CONFIGURADO"
fi

# Verificar OpenSSL
echo -n "[3/6] OpenSSL.............. "
if openssl version &>/dev/null; then
    echo "✅ OK ($(openssl version | cut -d' ' -f2))"
else
    echo "❌ NÃO ENCONTRADO"
fi

# Verificar CFSSL
echo -n "[4/6] CFSSL................ "
if cfssl version &>/dev/null; then
    echo "✅ OK ($(cfssl version | grep Version | cut -d: -f2 | tr -d ' '))"
else
    echo "❌ NÃO ENCONTRADO"
fi

# Verificar CFSSLJSON
echo -n "[5/6] CFSSLJSON............ "
if cfssljson --version &>/dev/null; then
    echo "✅ OK"
else
    echo "❌ NÃO ENCONTRADO"
fi

# Verificar SSH
echo -n "[6/6] SSH Client........... "
if ssh -V 2>&1 | grep -q "OpenSSH"; then
    echo "✅ OK ($(ssh -V 2>&1 | cut -d' ' -f1))"
else
    echo "❌ NÃO ENCONTRADO"
fi

echo ""
echo "=== Verificação concluída ==="
```

**Saída esperada (todos os pré-requisitos instalados):**
```
=== Verificação de Pré-requisitos do Lab Kubernetes ===

[1/6] AWS CLI v2........... ✅ OK (aws-cli/2.15.0)
[2/6] AWS Credentials...... ✅ OK (arn:aws:iam::123456789012:user/k8s-lab-user)
[3/6] OpenSSL.............. ✅ OK (3.0.2)
[4/6] CFSSL................ ✅ OK (1.6.4)
[5/6] CFSSLJSON............ ✅ OK
[6/6] SSH Client........... ✅ OK (OpenSSH_9.6p1)

=== Verificação concluída ===
```

## Troubleshooting

### Problema: AWS CLI não encontrado após instalação

**Sintoma:**
```
bash: aws: command not found
```

**Causa provável:** O binário do AWS CLI não está no PATH do sistema. Isso ocorre quando a instalação foi feita em um diretório não padrão ou o shell não foi reiniciado.

**Resolução:**
```bash
# Verificar onde o AWS CLI foi instalado
find / -name "aws" -type f 2>/dev/null

# Adicionar ao PATH (ajuste o caminho conforme necessário)
export PATH="/usr/local/bin:$PATH"

# Para tornar permanente, adicione ao ~/.bashrc ou ~/.zshrc
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

### Problema: Credenciais AWS inválidas ou expiradas

**Sintoma:**
```
An error occurred (InvalidClientTokenId) when calling the GetCallerIdentity operation:
The security token included in the request is invalid.
```

**Causa provável:** As credenciais configuradas estão incorretas, expiradas, ou o Access Key foi desativado.

**Resolução:**
```bash
# Verificar as credenciais configuradas
aws configure list

# Reconfigurar com credenciais válidas
aws configure

# Se usando SSO, renovar a sessão
aws sso login
```

---

### Problema: Permissão negada ao instalar ferramentas

**Sintoma:**
```
Permission denied: /usr/local/bin/cfssl
```

**Causa provável:** O comando de instalação precisa de privilégios de administrador (sudo) para escrever em `/usr/local/bin/`.

**Resolução:**
```bash
# Usar sudo para mover binários para diretórios do sistema
sudo mv cfssl /usr/local/bin/
sudo chmod +x /usr/local/bin/cfssl

# Alternativa: instalar em diretório do usuário
mkdir -p ~/bin
mv cfssl ~/bin/
export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
```

---

### Problema: CFSSL não encontrado após download

**Sintoma:**
```
bash: cfssl: command not found
```

**Causa provável:** O binário foi baixado mas não foi movido para um diretório no PATH, ou não recebeu permissão de execução.

**Resolução:**
```bash
# Verificar se o arquivo foi baixado
ls -la /usr/local/bin/cfssl

# Garantir permissão de execução
sudo chmod +x /usr/local/bin/cfssl
sudo chmod +x /usr/local/bin/cfssljson

# Verificar se /usr/local/bin está no PATH
echo $PATH | grep -q "/usr/local/bin" && echo "OK" || echo "Adicione /usr/local/bin ao PATH"
```

---

### Problema: SSH connection refused ao conectar em instância EC2

**Sintoma:**
```
ssh: connect to host <IP> port 22: Connection refused
```

**Causa provável:** A instância EC2 ainda não terminou de inicializar, o security group não permite tráfego na porta 22, ou o serviço SSH não está rodando na instância.

**Resolução:**
```bash
# Verificar se a instância está no estado "running"
aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --query 'Reservations[].Instances[].State.Name' \
  --output text

# Verificar regras do security group (porta 22 deve estar aberta)
aws ec2 describe-security-groups \
  --group-ids <SG_ID> \
  --query 'SecurityGroups[].IpPermissions[?FromPort==`22`]'

# Aguardar a instância ficar disponível e tentar novamente
aws ec2 wait instance-status-ok --instance-ids <INSTANCE_ID>
ssh -i ~/.ssh/k8s-lab-key.pem ubuntu@<IP>
```

---

### Problema: Região AWS incorreta configurada

**Sintoma:**
```
An error occurred (AuthFailure) when calling the DescribeInstances operation:
AWS was not able to validate the provided access credentials
```

Ou recursos criados não aparecem no console AWS.

**Causa provável:** A região configurada no AWS CLI não corresponde à região onde os recursos foram criados.

**Resolução:**
```bash
# Verificar região atual
aws configure get region

# Corrigir para a região do lab
aws configure set region us-east-1

# Verificar novamente
aws configure get region
```

---

## Próximo Módulo

Após confirmar que todos os pré-requisitos estão instalados e funcionando, prossiga para:

➡️ [Módulo 01 — Infraestrutura AWS](../01-aws-infrastructure/)
