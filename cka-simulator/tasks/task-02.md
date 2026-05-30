# Tarefa 02 — Gerenciamento de Certificados TLS

**Domínio:** Cluster Architecture, Installation & Configuration
**Peso:** 6.25%
**Tempo recomendado:** 10 minutos

---

## Cenário

Durante uma auditoria de segurança, foi identificado que o certificado do kube-apiserver expirará em 7 dias. Você precisa verificar a validade dos certificados do cluster, gerar um novo certificado para o kube-apiserver com os Subject Alternative Names (SANs) corretos, e aplicar a renovação sem causar downtime prolongado.

O cluster utiliza a seguinte estrutura de PKI:
- **CA do cluster:** /etc/kubernetes/pki/ca.pem e /etc/kubernetes/pki/ca-key.pem
- **Certificado do apiserver:** /etc/kubernetes/pki/apiserver.pem
- **Chave do apiserver:** /etc/kubernetes/pki/apiserver-key.pem
- **IP do control plane:** 10.0.1.10
- **Nome do nó:** k8s-control-plane
- **Service CIDR primeiro IP:** 10.96.0.1

---

## Requisitos

1. Verifique a data de expiração do certificado atual do kube-apiserver usando `openssl`
2. Gere um novo certificado para o kube-apiserver com as seguintes especificações:
   - **CN (Common Name):** kube-apiserver
   - **O (Organization):** Kubernetes
   - **SANs:** kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local, 10.96.0.1, 10.0.1.10, 127.0.0.1, k8s-control-plane
   - **Validade:** 365 dias
   - **Assinado pela CA do cluster**
3. Substitua o certificado antigo pelo novo nos caminhos corretos
4. Reinicie o kube-apiserver para aplicar o novo certificado
5. Verifique que o API server está acessível com o novo certificado

> **Importante:** Mantenha um backup do certificado antigo antes de substituí-lo.

---

## Comandos de Verificação

Execute os seguintes comandos para validar se a tarefa foi concluída corretamente:

```bash
# 1. Verificar que o novo certificado tem validade de ~365 dias
openssl x509 -in /etc/kubernetes/pki/apiserver.pem -noout -dates
# Esperado: "notAfter" com data ~1 ano no futuro

# 2. Verificar o CN do certificado
openssl x509 -in /etc/kubernetes/pki/apiserver.pem -noout -subject
# Esperado: subject contendo "CN = kube-apiserver"

# 3. Verificar os SANs do certificado
openssl x509 -in /etc/kubernetes/pki/apiserver.pem -noout -text | grep -A1 "Subject Alternative Name"
# Esperado: DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc,
#           DNS:kubernetes.default.svc.cluster.local, DNS:k8s-control-plane,
#           IP:10.96.0.1, IP:10.0.1.10, IP:127.0.0.1

# 4. Verificar que o certificado foi assinado pela CA do cluster
openssl verify -CAfile /etc/kubernetes/pki/ca.pem /etc/kubernetes/pki/apiserver.pem
# Esperado: "/etc/kubernetes/pki/apiserver.pem: OK"

# 5. Verificar que o API server está respondendo
kubectl cluster-info
# Esperado: "Kubernetes control plane is running at https://..."

# 6. Verificar que o backup do certificado antigo existe
ls -la /etc/kubernetes/pki/apiserver.pem.bak
# Esperado: arquivo de backup presente
```

---

## Critérios de Aprovação

- ✅ Expiração do certificado antigo verificada corretamente
- ✅ Novo certificado gerado com CN, O e SANs corretos
- ✅ Certificado assinado pela CA do cluster
- ✅ Validade de 365 dias configurada
- ✅ Backup do certificado antigo mantido
- ✅ API server acessível após a renovação
