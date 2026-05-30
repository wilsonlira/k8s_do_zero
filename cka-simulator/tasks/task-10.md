# Tarefa 10 — Configurar Ingress com Roteamento por Path e Troubleshooting DNS

**Domínio:** Services & Networking
**Peso:** 20%
**Tempo recomendado:** 8 minutos

---

## Cenário

A equipe de plataforma precisa expor duas aplicações internas através de um único ponto de entrada HTTP usando o NGINX Ingress Controller já instalado no cluster. As aplicações são:

- **app-v1**: Serve a versão estável da aplicação (path `/stable`)
- **app-v2**: Serve a versão canary da aplicação (path `/canary`)

Além disso, a equipe reportou que a resolução DNS interna do cluster não está funcionando para um Service recém-criado. Você deve diagnosticar e garantir que o DNS resolve corretamente.

---

## Requisitos

1. Crie o namespace `ingress-demo` (se não existir)
2. No namespace `ingress-demo`, crie o Deployment `app-v1`:
   - Imagem: `hashicorp/http-echo:0.2.3`
   - Réplicas: 2
   - Label: `app=app-v1`
   - Args: `-text=stable-v1`
   - Container port: 5678
3. No namespace `ingress-demo`, crie o Deployment `app-v2`:
   - Imagem: `hashicorp/http-echo:0.2.3`
   - Réplicas: 2
   - Label: `app=app-v2`
   - Args: `-text=canary-v2`
   - Container port: 5678
4. Crie um Service ClusterIP chamado `app-v1-svc` no namespace `ingress-demo`:
   - Selector: `app=app-v1`
   - Port: 80 (targetPort: 5678)
5. Crie um Service ClusterIP chamado `app-v2-svc` no namespace `ingress-demo`:
   - Selector: `app=app-v2`
   - Port: 80 (targetPort: 5678)
6. Crie um recurso **Ingress** chamado `app-ingress` no namespace `ingress-demo`:
   - IngressClassName: `nginx`
   - Regra de roteamento por path:
     - Path `/stable` → Service `app-v1-svc` porta 80 (pathType: Prefix)
     - Path `/canary` → Service `app-v2-svc` porta 80 (pathType: Prefix)
7. Verifique que a resolução DNS funciona para ambos os Services dentro do cluster

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace existe
kubectl get namespace ingress-demo
# Esperado: STATUS = Active

# 2. Verificar Deployments rodando
kubectl get deployments -n ingress-demo
# Esperado: app-v1 READY=2/2, app-v2 READY=2/2

# 3. Verificar Services com endpoints
kubectl get svc -n ingress-demo
# Esperado: app-v1-svc e app-v2-svc listados, TYPE=ClusterIP

kubectl get endpoints app-v1-svc -n ingress-demo
# Esperado: 2 IPs listados

kubectl get endpoints app-v2-svc -n ingress-demo
# Esperado: 2 IPs listados

# 4. Verificar recurso Ingress
kubectl get ingress app-ingress -n ingress-demo
# Esperado: Ingress listado com CLASS=nginx

kubectl describe ingress app-ingress -n ingress-demo
# Esperado: Rules mostrando /stable → app-v1-svc:80, /canary → app-v2-svc:80

# 5. Verificar roteamento via Ingress (usar IP do Ingress Controller)
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

curl http://$INGRESS_IP/stable
# Esperado: "stable-v1"

curl http://$INGRESS_IP/canary
# Esperado: "canary-v2"

# 6. Verificar resolução DNS interna
kubectl run dns-check --image=busybox:1.36 --rm -it --restart=Never -n ingress-demo -- nslookup app-v1-svc.ingress-demo.svc.cluster.local
# Esperado: Resolve para o ClusterIP do app-v1-svc

kubectl run dns-check2 --image=busybox:1.36 --rm -it --restart=Never -n ingress-demo -- nslookup app-v2-svc.ingress-demo.svc.cluster.local
# Esperado: Resolve para o ClusterIP do app-v2-svc

# 7. Verificar que CoreDNS está funcionando
kubectl get pods -n kube-system -l k8s-app=kube-dns
# Esperado: Pods do CoreDNS em STATUS=Running
```

---

## Critérios de Aprovação

- ✅ Namespace `ingress-demo` existe
- ✅ Deployments `app-v1` e `app-v2` com 2 réplicas cada em estado Ready
- ✅ Services `app-v1-svc` e `app-v2-svc` com endpoints corretos
- ✅ Ingress `app-ingress` configurado com IngressClassName `nginx`
- ✅ Path `/stable` roteia para `app-v1-svc` retornando "stable-v1"
- ✅ Path `/canary` roteia para `app-v2-svc` retornando "canary-v2"
- ✅ DNS interno resolve ambos os Services corretamente
- ✅ CoreDNS pods estão rodando no namespace `kube-system`
