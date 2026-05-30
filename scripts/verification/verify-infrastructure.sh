#!/bin/bash
# =============================================================================
# Verificação de Infraestrutura AWS
# =============================================================================
# Este script verifica o estado da infraestrutura provisionada para o lab:
#   - Instâncias EC2 estão no estado "running"
#   - Security groups possuem as regras corretas para o Kubernetes
#   - Recursos estão em conformidade com o AWS Free Tier
#
# Executa verificações não-destrutivas usando AWS CLI para confirmar que
# a infraestrutura está pronta para a instalação dos componentes do cluster.
#
# Requirements: 1.5 (verificar elegibilidade Free Tier)
#               12.1 (verificar componentes do control plane reportando status)
# =============================================================================

set -euo pipefail

# Carrega variáveis centralizadas do projeto
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../variables.env"

# -----------------------------------------------------------------------------
# Variáveis de controle
# -----------------------------------------------------------------------------
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# -----------------------------------------------------------------------------
# Funções auxiliares
# -----------------------------------------------------------------------------

# Registra um check que passou
check_pass() {
    local msg="$1"
    echo "  ✓ ${msg}"
    ((TOTAL_CHECKS++))
    ((PASSED_CHECKS++))
}

# Registra um check que falhou
check_fail() {
    local msg="$1"
    echo "  ✗ ${msg}"
    ((TOTAL_CHECKS++))
    ((FAILED_CHECKS++))
}

# Registra um aviso (não é falha, mas requer atenção)
check_warn() {
    local msg="$1"
    echo "  ⚠ ${msg}"
    ((WARNINGS++))
}

# Verifica se o AWS CLI está configurado e acessível
verify_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "ERRO: AWS CLI não encontrado. Instale antes de continuar."
        echo "  → https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi

    if ! aws sts get-caller-identity --region "${AWS_REGION}" &> /dev/null; then
        echo "ERRO: AWS CLI não está autenticado ou sem permissões."
        echo "  → Execute: aws configure"
        echo "  → Ou verifique suas credenciais em ~/.aws/credentials"
        exit 1
    fi
}

# =============================================================================
# INÍCIO DA VERIFICAÇÃO
# =============================================================================

echo "============================================="
echo " Verificação de Infraestrutura AWS"
echo " Região: ${AWS_REGION}"
echo " Projeto: ${CLUSTER_NAME}"
echo "============================================="
echo ""

# Verifica pré-requisitos
echo "Verificando pré-requisitos..."
verify_aws_cli
echo "  ✓ AWS CLI configurado e autenticado"
echo ""

# -----------------------------------------------------------------------------
# Seção 1: Verificar Instâncias EC2
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [1/4] Verificando Instâncias EC2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Busca instâncias do projeto pelo tag Project
INSTANCES_JSON=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" \
              "Name=instance-state-name,Values=running,stopped,pending" \
    --region "${AWS_REGION}" \
    --query 'Reservations[].Instances[]' \
    --output json 2>/dev/null || echo "[]")

INSTANCE_COUNT=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "${INSTANCE_COUNT}" -eq 0 ]; then
    check_fail "Nenhuma instância encontrada com tag Project='${CLUSTER_NAME}'"
    echo "    → Execute scripts/infrastructure/create-instances.sh para provisionar"
else
    echo "  Instâncias encontradas: ${INSTANCE_COUNT}"
    echo ""

    # Verifica cada instância
    for i in $(seq 0 $((INSTANCE_COUNT - 1))); do
        INST_ID=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[${i}]['InstanceId'])")
        INST_STATE=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[${i}]['State']['Name'])")
        INST_TYPE=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[${i}]['InstanceType'])")
        INST_NAME=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); tags=d[${i}].get('Tags',[]); print(next((t['Value'] for t in tags if t['Key']=='Name'),'sem-nome'))")
        INST_ROLE=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); tags=d[${i}].get('Tags',[]); print(next((t['Value'] for t in tags if t['Key']=='Role'),'desconhecido'))")

        echo "  ┌── ${INST_NAME} (${INST_ROLE})"

        # Verifica estado da instância
        if [ "${INST_STATE}" = "running" ]; then
            check_pass "Estado: running"
        elif [ "${INST_STATE}" = "stopped" ]; then
            check_fail "Estado: stopped — instância precisa estar running"
            echo "      → Execute: aws ec2 start-instances --instance-ids ${INST_ID} --region ${AWS_REGION}"
        else
            check_fail "Estado: ${INST_STATE} — estado inesperado"
        fi

        # Verifica tipo da instância (Free Tier)
        if [ "${INST_TYPE}" = "t2.micro" ] || [ "${INST_TYPE}" = "t3.micro" ]; then
            check_pass "Tipo: ${INST_TYPE} — elegível ao Free Tier"
        else
            check_fail "Tipo: ${INST_TYPE} — NÃO elegível ao Free Tier"
            echo "      → Tipos elegíveis: t2.micro, t3.micro"
        fi

        echo "  └──"
        echo ""
    done

    # Verifica se temos pelo menos 1 control-plane e 1 worker
    CP_COUNT=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d if any(t.get('Value')=='control-plane' for t in i.get('Tags',[]))))")
    WORKER_COUNT=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d if any(t.get('Value')=='worker' for t in i.get('Tags',[]))))")

    if [ "${CP_COUNT}" -ge 1 ]; then
        check_pass "Control Plane: ${CP_COUNT} instância(s) encontrada(s)"
    else
        check_fail "Control Plane: nenhuma instância com Role=control-plane"
    fi

    if [ "${WORKER_COUNT}" -ge 1 ]; then
        check_pass "Worker Node: ${WORKER_COUNT} instância(s) encontrada(s)"
    else
        check_fail "Worker Node: nenhuma instância com Role=worker"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 2: Verificar Security Groups
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [2/4] Verificando Security Groups"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Busca security groups do projeto
SG_JSON=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --output json 2>/dev/null || echo '{"SecurityGroups":[]}')

SG_COUNT=$(echo "${SG_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('SecurityGroups',[])))")

if [ "${SG_COUNT}" -eq 0 ]; then
    check_fail "Nenhum security group encontrado com tag Project='${CLUSTER_NAME}'"
    echo "    → Execute scripts/infrastructure/create-security-groups.sh"
else
    # Portas obrigatórias para o Control Plane
    CP_REQUIRED_PORTS=("22" "6443" "2379" "10250" "10259" "10257")
    CP_PORT_NAMES=("SSH" "kube-apiserver" "etcd" "kubelet" "kube-scheduler" "kube-controller-manager")

    # Portas obrigatórias para o Worker Node
    WORKER_REQUIRED_PORTS=("22" "10250" "30000")
    WORKER_PORT_NAMES=("SSH" "kubelet" "NodePort (30000-32767)")

    # Verifica Control Plane SG
    CP_SG=$(echo "${SG_JSON}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for sg in data.get('SecurityGroups', []):
    if 'control-plane' in sg.get('GroupName', ''):
        print(json.dumps(sg))
        break
" 2>/dev/null || echo "")

    if [ -n "${CP_SG}" ]; then
        echo "  Control Plane Security Group:"
        CP_SG_NAME=$(echo "${CP_SG}" | python3 -c "import sys,json; print(json.load(sys.stdin)['GroupName'])")
        echo "    Nome: ${CP_SG_NAME}"

        for idx in "${!CP_REQUIRED_PORTS[@]}"; do
            PORT="${CP_REQUIRED_PORTS[$idx]}"
            PORT_NAME="${CP_PORT_NAMES[$idx]}"

            PORT_FOUND=$(echo "${CP_SG}" | python3 -c "
import sys, json
sg = json.load(sys.stdin)
port = int(${PORT})
found = False
for rule in sg.get('IpPermissions', []):
    from_port = rule.get('FromPort', 0)
    to_port = rule.get('ToPort', 0)
    # Verifica se a porta está no range da regra
    if from_port <= port <= to_port:
        found = True
        break
    # Verifica regras sem restrição de porta (protocol -1)
    if rule.get('IpProtocol', '') == '-1':
        found = True
        break
print('yes' if found else 'no')
" 2>/dev/null || echo "no")

            if [ "${PORT_FOUND}" = "yes" ]; then
                check_pass "Porta ${PORT} (${PORT_NAME}) — aberta"
            else
                check_fail "Porta ${PORT} (${PORT_NAME}) — NÃO encontrada"
                echo "      → Adicione regra de ingress para porta ${PORT}/tcp"
            fi
        done
        echo ""
    else
        check_fail "Security Group do Control Plane não encontrado"
        echo "    → Esperado: ${CLUSTER_NAME}-control-plane-sg"
    fi

    # Verifica Worker Node SG
    WORKER_SG=$(echo "${SG_JSON}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for sg in data.get('SecurityGroups', []):
    if 'worker' in sg.get('GroupName', ''):
        print(json.dumps(sg))
        break
" 2>/dev/null || echo "")

    if [ -n "${WORKER_SG}" ]; then
        echo "  Worker Node Security Group:"
        WORKER_SG_NAME=$(echo "${WORKER_SG}" | python3 -c "import sys,json; print(json.load(sys.stdin)['GroupName'])")
        echo "    Nome: ${WORKER_SG_NAME}"

        for idx in "${!WORKER_REQUIRED_PORTS[@]}"; do
            PORT="${WORKER_REQUIRED_PORTS[$idx]}"
            PORT_NAME="${WORKER_PORT_NAMES[$idx]}"

            PORT_FOUND=$(echo "${WORKER_SG}" | python3 -c "
import sys, json
sg = json.load(sys.stdin)
port = int(${PORT})
found = False
for rule in sg.get('IpPermissions', []):
    from_port = rule.get('FromPort', 0)
    to_port = rule.get('ToPort', 0)
    if from_port <= port <= to_port:
        found = True
        break
    if rule.get('IpProtocol', '') == '-1':
        found = True
        break
print('yes' if found else 'no')
" 2>/dev/null || echo "no")

            if [ "${PORT_FOUND}" = "yes" ]; then
                check_pass "Porta ${PORT} (${PORT_NAME}) — aberta"
            else
                check_fail "Porta ${PORT} (${PORT_NAME}) — NÃO encontrada"
                echo "      → Adicione regra de ingress para porta ${PORT}/tcp"
            fi
        done
        echo ""
    else
        check_fail "Security Group do Worker Node não encontrado"
        echo "    → Esperado: ${CLUSTER_NAME}-worker-sg"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 3: Verificar Conformidade com Free Tier
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [3/4] Verificando Conformidade com Free Tier"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verifica volumes EBS
VOLUMES_JSON=$(aws ec2 describe-volumes \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --output json 2>/dev/null || echo '{"Volumes":[]}')

# Se não encontrou volumes por tag, busca pelos volumes das instâncias do projeto
VOL_COUNT=$(echo "${VOLUMES_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('Volumes',[])))")

if [ "${VOL_COUNT}" -eq 0 ] && [ "${INSTANCE_COUNT:-0}" -gt 0 ]; then
    # Busca IDs das instâncias para encontrar volumes anexados
    INST_IDS=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(i['InstanceId'] for i in d))")
    if [ -n "${INST_IDS}" ]; then
        VOLUMES_JSON=$(aws ec2 describe-volumes \
            --filters "Name=attachment.instance-id,Values=${INST_IDS}" \
            --region "${AWS_REGION}" \
            --output json 2>/dev/null || echo '{"Volumes":[]}')
        VOL_COUNT=$(echo "${VOLUMES_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('Volumes',[])))")
    fi
fi

if [ "${VOL_COUNT}" -eq 0 ]; then
    echo "  ℹ Nenhum volume EBS encontrado para o projeto"
else
    TOTAL_EBS=$(echo "${VOLUMES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(v['Size'] for v in d.get('Volumes',[])))")
    EBS_TYPES=$(echo "${VOLUMES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(set(v['VolumeType'] for v in d.get('Volumes',[]))))")

    echo "  Armazenamento EBS total: ${TOTAL_EBS} GB (limite Free Tier: 30 GB)"
    echo "  Tipos de volume: ${EBS_TYPES}"

    # Verifica limite de 30 GB
    if [ "${TOTAL_EBS}" -le 30 ]; then
        check_pass "EBS total (${TOTAL_EBS} GB) dentro do limite Free Tier (30 GB)"
    else
        check_fail "EBS total (${TOTAL_EBS} GB) EXCEDE o limite Free Tier (30 GB)"
        echo "    → Reduza os tamanhos dos volumes em variables.env"
        echo "    → Custo estimado adicional: ~\$0.08/GB/mês para gp3"
    fi

    # Verifica tipos de volume (devem ser gp2 ou gp3)
    ALL_GP=$(echo "${VOLUMES_JSON}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
all_gp = all(v['VolumeType'] in ('gp2', 'gp3') for v in d.get('Volumes', []))
print('yes' if all_gp else 'no')
")
    if [ "${ALL_GP}" = "yes" ]; then
        check_pass "Todos os volumes são gp2/gp3 — elegíveis ao Free Tier"
    else
        check_fail "Volumes com tipo não-elegível ao Free Tier detectados"
        echo "    → Use apenas gp2 ou gp3"
    fi
fi

# Verifica horas de instância estimadas
if [ "${INSTANCE_COUNT:-0}" -gt 0 ]; then
    RUNNING_COUNT=$(echo "${INSTANCES_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d if i['State']['Name']=='running'))")
    MONTHLY_HOURS=$((RUNNING_COUNT * 24 * 30))

    echo ""
    echo "  Instâncias running: ${RUNNING_COUNT}"
    echo "  Horas mensais estimadas: ${MONTHLY_HOURS} / 750 (limite Free Tier)"

    if [ "${MONTHLY_HOURS}" -le 750 ]; then
        check_pass "Horas mensais (${MONTHLY_HOURS}h) dentro do limite Free Tier (750h)"
    else
        check_warn "Horas mensais (${MONTHLY_HOURS}h) EXCEDEM o limite Free Tier (750h)"
        echo "    → Pare instâncias quando não estiver estudando"
        echo "    → aws ec2 stop-instances --instance-ids <ids> --region ${AWS_REGION}"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Seção 4: Verificar VPC e Networking
# -----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " [4/4] Verificando VPC e Networking"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Busca VPC do projeto
VPC_JSON=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --output json 2>/dev/null || echo '{"Vpcs":[]}')

VPC_COUNT=$(echo "${VPC_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('Vpcs',[])))")

if [ "${VPC_COUNT}" -eq 0 ]; then
    check_fail "VPC não encontrada com tag Project='${CLUSTER_NAME}'"
    echo "    → Execute scripts/infrastructure/create-vpc.sh"
else
    VPC_ID_FOUND=$(echo "${VPC_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Vpcs'][0]['VpcId'])")
    VPC_CIDR_FOUND=$(echo "${VPC_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Vpcs'][0]['CidrBlock'])")
    VPC_STATE=$(echo "${VPC_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Vpcs'][0]['State'])")

    if [ "${VPC_STATE}" = "available" ]; then
        check_pass "VPC ${VPC_ID_FOUND} — estado: available"
    else
        check_fail "VPC ${VPC_ID_FOUND} — estado: ${VPC_STATE} (esperado: available)"
    fi

    if [ "${VPC_CIDR_FOUND}" = "${VPC_CIDR}" ]; then
        check_pass "VPC CIDR: ${VPC_CIDR_FOUND} — conforme configuração"
    else
        check_warn "VPC CIDR: ${VPC_CIDR_FOUND} — diferente do configurado (${VPC_CIDR})"
    fi

    # Verifica subnet
    SUBNET_JSON=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID_FOUND}" "Name=tag:Project,Values=${CLUSTER_NAME}" \
        --region "${AWS_REGION}" \
        --output json 2>/dev/null || echo '{"Subnets":[]}')

    SUBNET_COUNT=$(echo "${SUBNET_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('Subnets',[])))")

    if [ "${SUBNET_COUNT}" -ge 1 ]; then
        check_pass "Subnet encontrada na VPC (${SUBNET_COUNT} subnet(s))"
    else
        check_fail "Nenhuma subnet encontrada na VPC com tag do projeto"
    fi

    # Verifica Internet Gateway
    IGW_JSON=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=${VPC_ID_FOUND}" \
        --region "${AWS_REGION}" \
        --output json 2>/dev/null || echo '{"InternetGateways":[]}')

    IGW_COUNT=$(echo "${IGW_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('InternetGateways',[])))")

    if [ "${IGW_COUNT}" -ge 1 ]; then
        check_pass "Internet Gateway anexado à VPC"
    else
        check_fail "Nenhum Internet Gateway encontrado na VPC"
        echo "    → Necessário para acesso SSH e download de pacotes"
    fi
fi

echo ""

# =============================================================================
# RESUMO FINAL
# =============================================================================
echo "============================================="
echo " Resumo da Verificação de Infraestrutura"
echo "============================================="
echo ""
echo "  Total de verificações: ${TOTAL_CHECKS}"
echo "  Aprovadas:  ${PASSED_CHECKS}"
echo "  Reprovadas: ${FAILED_CHECKS}"
echo "  Avisos:     ${WARNINGS}"
echo ""

if [ "${FAILED_CHECKS}" -eq 0 ] && [ "${WARNINGS}" -eq 0 ]; then
    echo "  ✓ RESULTADO: Infraestrutura OK — pronta para instalação do cluster"
    echo ""
    exit 0
elif [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo "  ⚠ RESULTADO: Infraestrutura funcional, mas com avisos"
    echo "    Revise os avisos acima para otimizar custos."
    echo ""
    exit 0
else
    echo "  ✗ RESULTADO: Infraestrutura com problemas"
    echo "    Corrija os itens reprovados antes de prosseguir."
    echo ""
    echo "  Próximos passos:"
    echo "    1. Corrija os erros listados acima"
    echo "    2. Execute este script novamente para revalidar"
    echo "    3. Prossiga com a instalação dos componentes do cluster"
    echo ""
    exit 1
fi
