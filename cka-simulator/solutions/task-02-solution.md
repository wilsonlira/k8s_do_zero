# Solução — Tarefa 02: Gerenciamento de Certificados TLS

**Domínio:** Cluster Architecture, Installation & Configuration
**Tempo estimado:** 10 minutos

---

## Passo 1: Verificar a data de expiração do certificado atual

```bash
openssl x509 -in /etc/kubernetes/pki/apiserver.pem -noout -dates
```

**Saída esperada:**
```
notBefore=Jan 10 00:00:00 2024 GMT
notAfter=Jan 17 00:00:00 2024 GMT
```

**Por que:** Antes de renovar, precisamos confirmar que o certificado realmente está próximo da expiração. O campo `notAfter` mostra a data limite — após essa data, o certificado é rejeitado por qualquer cliente TLS, causando falha na comunicação com o API server.

---

## Passo 2: Fazer backup do certificado antigo

```bash
sudo cp /etc/kubernetes/pki/apiserver.pem /etc/kubernetes/pki/apiserver.pem.bak
sudo cp /etc/kubernetes/pki/apiserver-key.pem /etc/kubernetes/pki/apiserver-key.pem.bak
```

**Por que:** Manter um backup permite reverter rapidamente caso o novo certificado tenha algum problema (SANs incorretos, CA errada, etc.). Em produção, essa é uma prática essencial antes de qualquer alteração em certificados.

---

## Passo 3: Criar o arquivo de configuração do CSR (Certificate Signing Request)

```bash
cat > /tmp/apiserver-csr.conf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = kube-apiserver
O = Kubernetes

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = k8s-control-plane
IP.1 = 10.96.0.1
IP.2 = 10.0.1.10
IP.3 = 127.0.0.1
EOF
```

**Por que:** O arquivo de configuração define todos os atributos do certificado. Os SANs (Subject Alternative Names) são críticos — o kube-apiserver é acessado por diferentes nomes e IPs:
- `kubernetes*` — nomes DNS usados internamente pelos componentes do cluster
- `10.96.0.1` — primeiro IP do Service CIDR (o Service "kubernetes" no namespace default)
- `10.0.1.10` — IP real do nó control plane
- `127.0.0.1` — acesso local (localhost)
- `k8s-control-plane` — hostname do nó

---

## Passo 4: Gerar nova chave privada e CSR

```bash
openssl genrsa -out /etc/kubernetes/pki/apiserver-key.pem 2048

openssl req -new \
  -key /etc/kubernetes/pki/apiserver-key.pem \
  -out /tmp/apiserver.csr \
  -config /tmp/apiserver-csr.conf
```

**Saída esperada:**
```
Generating RSA private key, 2048 bit long modulus
..........+++
.....+++
e is 65537 (0x10001)
```

**Por que:** Geramos uma nova chave RSA de 2048 bits (mínimo recomendado para segurança) e um CSR que contém as informações do certificado (CN, O, SANs). O CSR será assinado pela CA do cluster no próximo passo.

---

## Passo 5: Assinar o certificado com a CA do cluster

```bash
openssl x509 -req \
  -in /tmp/apiserver.csr \
  -CA /etc/kubernetes/pki/ca.pem \
  -CAkey /etc/kubernetes/pki/ca-key.pem \
  -CAcreateserial \
  -out /etc/kubernetes/pki/apiserver.pem \
  -days 365 \
  -extensions v3_req \
  -extfile /tmp/apiserver-csr.conf
```

**Saída esperada:**
```
Signature ok
subject=/CN=kube-apiserver/O=Kubernetes
Getting CA Private Key
```

**Por que:** A assinatura pela CA do cluster é o que torna o certificado confiável. Todos os componentes do Kubernetes confiam na CA — se o certificado não for assinado por ela, as conexões TLS serão rejeitadas. A flag `-days 365` define a validade de 1 ano.

---

## Passo 6: Verificar o novo certificado

```bash
# Verificar CN e Organization
openssl x509 -in /etc/kubernetes/pki/apiserver.pem -noout -subject
```

**Saída esperada:**
```
subject= /CN=kube-apiserver/O=Kubernetes
```

```bash
# Verificar SANs
openssl x509 -in /etc/kubernetes/pki/apiserver.pem -noout -text | grep -A1 "Subject Alternative Name"
```

**Saída esperada:**
```
            X509v3 Subject Alternative Name:
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:k8s-control-plane, IP Address:10.96.0.1, IP Address:10.0.1.10, IP Address:127.0.0.1
```

```bash
# Verificar validade
openssl x509 -in /etc/kubernetes/pki/apiserver.pem -noout -dates
```

**Saída esperada:**
```
notBefore=Jan 15 10:00:00 2024 GMT
notAfter=Jan 15 10:00:00 2025 GMT
```

```bash
# Verificar que foi assinado pela CA correta
openssl verify -CAfile /etc/kubernetes/pki/ca.pem /etc/kubernetes/pki/apiserver.pem
```

**Saída esperada:**
```
/etc/kubernetes/pki/apiserver.pem: OK
```

**Por que:** Verificamos cada aspecto do certificado antes de reiniciar o API server. Um certificado com SANs faltando causaria erros de TLS para componentes que acessam o apiserver por aquele nome/IP específico.

---

## Passo 7: Reiniciar o kube-apiserver

```bash
sudo systemctl restart kube-apiserver
```

**Por que:** O kube-apiserver carrega os certificados TLS na inicialização. Para usar o novo certificado, o serviço precisa ser reiniciado. Durante o restart (alguns segundos), o cluster fica temporariamente indisponível.

---

## Passo 8: Verificar que o API server está acessível

```bash
kubectl cluster-info
```

**Saída esperada:**
```
Kubernetes control plane is running at https://10.0.1.10:6443
CoreDNS is running at https://10.0.1.10:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

**Por que:** Se o `kubectl cluster-info` retorna com sucesso, significa que o novo certificado está sendo aceito pelo cliente (kubectl valida o certificado contra a CA). Isso confirma que a renovação foi bem-sucedida.

---

## Passo 9: Limpar arquivos temporários

```bash
rm -f /tmp/apiserver-csr.conf /tmp/apiserver.csr
```

**Por que:** Boa prática de segurança — o CSR e o arquivo de configuração não são mais necessários e não devem ficar no sistema.

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| CN (Common Name) | Identifica o "dono" do certificado — para o apiserver é `kube-apiserver` |
| O (Organization) | Grupo ao qual o certificado pertence — usado pelo RBAC do Kubernetes |
| SANs | Nomes/IPs alternativos pelos quais o servidor pode ser acessado |
| CA (Certificate Authority) | Entidade raiz de confiança que assina certificados |
| `-days 365` | Validade do certificado em dias |
| `openssl verify` | Valida a cadeia de confiança (certificado → CA) |
