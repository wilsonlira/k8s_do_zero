#!/bin/bash
# =============================================================================
# Property 3: Documentação de Parâmetros de Configuração
# =============================================================================
# Validates: Requirements 2.4, 3.3, 4.4, 5.4, 6.3, 7.3, 8.3, 10.3, 11.3
#
# Este script faz referência cruzada entre os arquivos de configuração em
# configs/ e a documentação nos módulos (docs/), verificando que cada
# parâmetro/flag tem uma explicação na documentação correspondente.
#
# Mapeamento de configs para módulos:
#   configs/containerd/config.toml        → docs/03-container-runtime/README.md
#   configs/systemd/etcd.service          → docs/04-etcd/README.md
#   configs/systemd/kube-apiserver.service → docs/05-kube-apiserver/README.md
#   configs/systemd/kube-controller-manager.service → docs/06-kube-controller-manager/README.md
#   configs/systemd/kube-scheduler.service → docs/07-kube-scheduler/README.md
#   configs/systemd/kubelet.service       → docs/08-kubelet/README.md
#   configs/systemd/kube-proxy.service    → docs/09-kube-proxy/README.md
#   configs/coredns/coredns.yaml          → docs/11-coredns/README.md
#   configs/kubernetes/kubeconfig-admin.yaml → docs/12-kubectl-kubeconfig/README.md
# =============================================================================

set -euo pipefail

# Determinar raiz do projeto (script está em scripts/validation/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONFIGS_DIR="$PROJECT_ROOT/configs"
DOCS_DIR="$PROJECT_ROOT/docs"

# Cores para saída
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # Sem cor

# Contadores globais
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
COMPONENTS_CHECKED=0
COMPONENTS_PASSED=0
COMPONENTS_FAILED=0

# =============================================================================
# Funções Auxiliares
# =============================================================================

pass() {
  local check="$1"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "  ${GREEN}✅ PASS${NC} $check"
}

fail() {
  local check="$1"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "  ${RED}❌ FAIL${NC} $check"
}


# Extrai flags de um arquivo de serviço systemd (linhas com --)
# Retorna apenas o nome do flag (sem -- e sem valor)
# Foca apenas nas linhas do ExecStart (entre ExecStart= e a próxima diretiva)
extract_systemd_flags() {
  local service_file="$1"
  # Extrai o bloco ExecStart (linhas continuadas com \)
  # e depois extrai os flags --nome-do-flag
  sed -n '/^ExecStart=/,/^[A-Z]/p' "$service_file" | \
    grep -oP '(?<=\s)--[a-z][a-z0-9-]*' 2>/dev/null | \
    sed 's/^--//' | \
    sort -u
}

# Extrai flags mencionados na seção "Key configuration flags" dos comentários
# Estes são parâmetros importantes que podem estar em um config file separado
extract_key_config_flags() {
  local service_file="$1"
  # Busca linhas com --flag-name na seção de comentários do header
  grep -P '^\s*#\s+--[a-z]' "$service_file" 2>/dev/null | \
    grep -oP '(?<=--)[a-z][a-z0-9-]*' | \
    sort -u
}

# Extrai parâmetros-chave de um arquivo TOML (containerd config)
# Retorna nomes de seções e parâmetros importantes
extract_toml_params() {
  local toml_file="$1"
  # Extrai parâmetros de configuração (chave = valor)
  grep -P '^\s+\w+\s*=' "$toml_file" 2>/dev/null | \
    sed 's/^\s*//; s/\s*=.*//' | sort -u
}

# Extrai plugins do Corefile no coredns.yaml
extract_corefile_plugins() {
  local yaml_file="$1"
  # Extrai nomes de plugins do Corefile (linhas que começam com nome de plugin)
  grep -P '^\s{8}[a-z]+' "$yaml_file" 2>/dev/null | \
    sed 's/^\s*//; s/\s.*//' | \
    grep -v '^#' | \
    grep -vP '^\d' | \
    sort -u
}

# Extrai seções de kubeconfig (clusters, users, contexts, current-context)
extract_kubeconfig_sections() {
  local yaml_file="$1"
  # Extrai campos de nível superior do kubeconfig
  grep -P '^(clusters|users|contexts|current-context|apiVersion|kind):' "$yaml_file" 2>/dev/null | \
    sed 's/:.*//' | sort -u
}

# Verifica se um parâmetro/flag é mencionado na documentação
# Busca pelo nome do flag (com ou sem --) no README
# Also checks camelCase equivalent (e.g., cluster-dns → clusterDNS, clusterDns)
param_documented() {
  local doc_file="$1"
  local param="$2"

  # Direct search (kebab-case or exact match)
  if grep -qi "$param" "$doc_file" 2>/dev/null; then
    return 0
  fi

  # Convert kebab-case to camelCase and search
  # e.g., "cluster-dns" → "clusterDns" or "clusterDNS"
  local camel_case
  camel_case=$(echo "$param" | sed -r 's/-(.)/\U\1/g')
  if grep -qi "$camel_case" "$doc_file" 2>/dev/null; then
    return 0
  fi

  # Try with common abbreviation patterns (DNS, IP, TLS, CIDR)
  # e.g., "tls-cert-file" → "tlsCertFile"
  local camel_upper
  camel_upper=$(echo "$param" | sed -r 's/-(.)/\U\1/g' | sed 's/Dns/DNS/g; s/Ip/IP/g; s/Tls/TLS/g; s/Cidr/CIDR/g; s/Url/URL/g')
  if grep -qi "$camel_upper" "$doc_file" 2>/dev/null; then
    return 0
  fi

  # Search with underscores (for TOML params like bin_dir)
  local underscore_form
  underscore_form=$(echo "$param" | tr '-' '_')
  if grep -qi "$underscore_form" "$doc_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

# =============================================================================
# Verificação Pré-execução
# =============================================================================

echo "============================================================"
echo "Property 3: Documentação de Parâmetros de Configuração"
echo "Validates: Requirements 2.4, 3.3, 4.4, 5.4, 6.3, 7.3, 8.3, 10.3, 11.3"
echo "============================================================"
echo ""

if [ ! -d "$CONFIGS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de configurações não encontrado: $CONFIGS_DIR${NC}"
  exit 1
fi

if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}ERRO: Diretório de documentação não encontrado: $DOCS_DIR${NC}"
  exit 1
fi

# =============================================================================
# Definição de mapeamentos: config_file → doc_file → componente
# =============================================================================

# Arrays paralelos para mapeamento
declare -a CONFIG_FILES
declare -a DOC_FILES
declare -a COMPONENT_NAMES

# containerd config → container-runtime module (Req 2.4)
CONFIG_FILES+=("$CONFIGS_DIR/containerd/config.toml")
DOC_FILES+=("$DOCS_DIR/03-container-runtime/README.md")
COMPONENT_NAMES+=("containerd (Req 2.4)")

# etcd service → etcd module (Req 3.3)
CONFIG_FILES+=("$CONFIGS_DIR/systemd/etcd.service")
DOC_FILES+=("$DOCS_DIR/04-etcd/README.md")
COMPONENT_NAMES+=("etcd (Req 3.3)")

# kube-apiserver service → apiserver module (Req 4.4)
CONFIG_FILES+=("$CONFIGS_DIR/systemd/kube-apiserver.service")
DOC_FILES+=("$DOCS_DIR/05-kube-apiserver/README.md")
COMPONENT_NAMES+=("kube-apiserver (Req 4.4)")

# kube-controller-manager service → controller-manager module (Req 5.4)
CONFIG_FILES+=("$CONFIGS_DIR/systemd/kube-controller-manager.service")
DOC_FILES+=("$DOCS_DIR/06-kube-controller-manager/README.md")
COMPONENT_NAMES+=("kube-controller-manager (Req 5.4)")

# kube-scheduler service → scheduler module (Req 6.3)
CONFIG_FILES+=("$CONFIGS_DIR/systemd/kube-scheduler.service")
DOC_FILES+=("$DOCS_DIR/07-kube-scheduler/README.md")
COMPONENT_NAMES+=("kube-scheduler (Req 6.3)")

# kubelet service → kubelet module (Req 7.3)
CONFIG_FILES+=("$CONFIGS_DIR/systemd/kubelet.service")
DOC_FILES+=("$DOCS_DIR/08-kubelet/README.md")
COMPONENT_NAMES+=("kubelet (Req 7.3)")
# Note: kubelet uses --config for most params; we check ExecStart flags
# plus key params documented in the service file header

# kube-proxy service → kube-proxy module (Req 8.3)
CONFIG_FILES+=("$CONFIGS_DIR/systemd/kube-proxy.service")
DOC_FILES+=("$DOCS_DIR/09-kube-proxy/README.md")
COMPONENT_NAMES+=("kube-proxy (Req 8.3)")

# coredns config → coredns module (Req 10.3)
CONFIG_FILES+=("$CONFIGS_DIR/coredns/coredns.yaml")
DOC_FILES+=("$DOCS_DIR/11-coredns/README.md")
COMPONENT_NAMES+=("CoreDNS (Req 10.3)")

# kubeconfig-admin → kubectl module (Req 11.3)
CONFIG_FILES+=("$CONFIGS_DIR/kubernetes/kubeconfig-admin.yaml")
DOC_FILES+=("$DOCS_DIR/12-kubectl-kubeconfig/README.md")
COMPONENT_NAMES+=("kubeconfig/kubectl (Req 11.3)")


# =============================================================================
# Validação de Cada Componente
# =============================================================================

for i in "${!CONFIG_FILES[@]}"; do
  config_file="${CONFIG_FILES[$i]}"
  doc_file="${DOC_FILES[$i]}"
  component="${COMPONENT_NAMES[$i]}"

  COMPONENTS_CHECKED=$((COMPONENTS_CHECKED + 1))
  COMPONENT_HAS_ERROR=0

  echo -e "${YELLOW}--- Componente: $component ---${NC}"

  # Verificar se o arquivo de configuração existe
  if [ ! -f "$config_file" ]; then
    fail "[$component] Arquivo de configuração não encontrado: $(basename "$config_file")"
    COMPONENT_HAS_ERROR=1
    COMPONENTS_FAILED=$((COMPONENTS_FAILED + 1))
    echo ""
    continue
  fi

  # Verificar se o arquivo de documentação existe
  if [ ! -f "$doc_file" ]; then
    fail "[$component] Documentação não encontrada: $(basename "$(dirname "$doc_file")")/README.md"
    COMPONENT_HAS_ERROR=1
    COMPONENTS_FAILED=$((COMPONENTS_FAILED + 1))
    echo ""
    continue
  fi

  # -------------------------------------------------------------------------
  # Extrair parâmetros baseado no tipo de arquivo
  # -------------------------------------------------------------------------
  PARAMS=()
  config_basename=$(basename "$config_file")

  case "$config_basename" in
    *.service)
      # Extrair flags do ExecStart do systemd service file
      while IFS= read -r flag; do
        [ -n "$flag" ] && PARAMS+=("$flag")
      done < <(extract_systemd_flags "$config_file")
      # Também extrair flags-chave documentados nos comentários do header
      # (para componentes que usam --config com arquivo separado)
      while IFS= read -r flag; do
        [ -n "$flag" ] && PARAMS+=("$flag")
      done < <(extract_key_config_flags "$config_file")
      # Remover duplicatas
      if [ ${#PARAMS[@]} -gt 0 ]; then
        PARAMS=($(printf '%s\n' "${PARAMS[@]}" | sort -u))
      fi
      ;;
    config.toml)
      # Extrair parâmetros-chave do containerd config
      # Focar nos parâmetros mais importantes para Kubernetes
      PARAMS=("SystemdCgroup" "sandbox_image" "bin_dir" "conf_dir" "address" "runtime_type" "default_runtime_name")
      ;;
    coredns.yaml)
      # Extrair plugins do Corefile
      PARAMS=("kubernetes" "forward" "cache" "errors" "health" "ready" "loop" "reload" "loadbalance" "prometheus")
      ;;
    kubeconfig-admin.yaml)
      # Verificar seções do kubeconfig
      PARAMS=("clusters" "users" "contexts" "current-context" "certificate-authority" "client-certificate" "client-key" "server")
      ;;
    *)
      echo -e "  ${YELLOW}⚠️  Tipo de arquivo não reconhecido: $config_basename${NC}"
      continue
      ;;
  esac

  # -------------------------------------------------------------------------
  # Verificar se cada parâmetro está documentado
  # -------------------------------------------------------------------------
  if [ ${#PARAMS[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}⚠️  Nenhum parâmetro extraído de $config_basename${NC}"
    continue
  fi

  UNDOCUMENTED=()

  for param in "${PARAMS[@]}"; do
    if param_documented "$doc_file" "$param"; then
      pass "[$component] Parâmetro '$param' documentado"
    else
      fail "[$component] Parâmetro '$param' NÃO documentado em $(basename "$(dirname "$doc_file")")/README.md"
      UNDOCUMENTED+=("$param")
      COMPONENT_HAS_ERROR=1
    fi
  done

  # Resumo do componente
  total_params=${#PARAMS[@]}
  documented_params=$((total_params - ${#UNDOCUMENTED[@]}))
  echo -e "  Parâmetros: $documented_params/$total_params documentados"

  if [ ${#UNDOCUMENTED[@]} -gt 0 ]; then
    echo -e "  ${RED}Não documentados: ${UNDOCUMENTED[*]}${NC}"
  fi

  # Atualizar contadores de componentes
  if [ "$COMPONENT_HAS_ERROR" -eq 0 ]; then
    COMPONENTS_PASSED=$((COMPONENTS_PASSED + 1))
  else
    COMPONENTS_FAILED=$((COMPONENTS_FAILED + 1))
  fi

  echo ""
done

# =============================================================================
# Resumo
# =============================================================================

echo "============================================================"
echo "RESUMO"
echo "============================================================"
echo "Componentes verificados:   $COMPONENTS_CHECKED"
echo -e "Componentes aprovados:     ${GREEN}$COMPONENTS_PASSED${NC}"
echo -e "Componentes reprovados:    ${RED}$COMPONENTS_FAILED${NC}"
echo ""
echo "Total de verificações:     $TOTAL_CHECKS"
echo -e "Aprovadas:                 ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Reprovadas:                ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "${GREEN}✅ TODAS AS VERIFICAÇÕES PASSARAM — Todos os parâmetros de configuração estão documentados.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED_CHECKS VERIFICAÇÃO(ÕES) FALHARAM — Parâmetros de configuração sem documentação encontrados.${NC}"
  exit 1
fi
