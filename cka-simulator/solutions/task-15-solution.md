# Solução — Tarefa 15: Troubleshooting de Conectividade de Rede entre Pods

**Domínio:** Troubleshooting
**Tempo estimado:** 8 minutos

---

## Passo 1: Criar o namespace app-network

```bash
kubectl create namespace app-network
```

**Saída esperada:**
```
namespace/app-network created
```

---

## Passo 2: Criar o Deployment backend

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: app-network
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF
```

**Saída esperada:**
```
deployment.apps/backend created
```

---

## Passo 3: Criar o Service com selector INCORRETO (simulando o erro)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: app-network
spec:
  type: ClusterIP
  selector:
    app: backend-wrong
  ports:
  - port: 8080
    targetPort: 80
    protocol: TCP
EOF
```

**Saída esperada:**
```
service/backend-svc created
```

**Por que:** Criamos o Service com o selector `app: backend-wrong` propositalmente. O pod tem label `app: backend`, então o selector não corresponde e o Service não terá endpoints.

---

## Passo 4: Criar o pod frontend

```bash
kubectl run frontend \
  --image=busybox:1.36 \
  --namespace=app-network \
  --command -- sleep 3600
```

**Saída esperada:**
```
pod/frontend created
```

---

## Passo 5: Diagnosticar — Verificar endpoints do Service

```bash
kubectl get endpoints backend-svc -n app-network
```

**Saída esperada:**
```
NAME          ENDPOINTS   AGE
backend-svc   <none>      30s
```

**Por que:** `<none>` nos endpoints é o sinal claro do problema. Um Service sem endpoints não pode rotear tráfego para nenhum pod. Isso significa que o selector do Service não corresponde a nenhum pod existente.

---

## Passo 6: Diagnosticar — Comparar selector do Service com labels dos pods

```bash
# Ver o selector do Service
kubectl get svc backend-svc -n app-network -o jsonpath='{.spec.selector}'
```

**Saída esperada:**
```json
{"app":"backend-wrong"}
```

```bash
# Ver as labels dos pods backend
kubectl get pods -n app-network --show-labels
```

**Saída esperada:**
```
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
backend-abc12-def34        1/1     Running   0          1m    app=backend,pod-template-hash=abc12
frontend                   1/1     Running   0          30s   run=frontend
```

**Por que:** A comparação revela o problema:
- Service selector: `app=backend-wrong`
- Pod label: `app=backend`

O selector não corresponde ao label do pod — por isso não há endpoints. Este é um erro comum em ambientes reais (typo no selector, label alterada após criação do Service, etc.).

---

## Passo 7: Diagnosticar — Testar conectividade (confirmar falha)

```bash
kubectl exec frontend -n app-network -- wget -qO- --timeout=3 http://backend-svc:8080
```

**Saída esperada:**
```
wget: download timed out
command terminated with exit code 1
```

**Por que:** A requisição falha com timeout porque o Service não tem endpoints para rotear o tráfego. O DNS resolve o nome do Service para o ClusterIP, mas o kube-proxy não tem regras de encaminhamento (pois não há endpoints).

---

## Passo 8: Corrigir — Atualizar o selector do Service

```bash
kubectl patch svc backend-svc -n app-network -p '{"spec":{"selector":{"app":"backend"}}}'
```

**Saída esperada:**
```
service/backend-svc patched
```

**Por que:** O `kubectl patch` permite alterar campos específicos do recurso sem recriar. Corrigimos o selector de `backend-wrong` para `backend`, que corresponde à label dos pods. O Kubernetes imediatamente recalcula os endpoints.

---

## Passo 9: Verificar que os endpoints foram populados

```bash
kubectl get endpoints backend-svc -n app-network
```

**Saída esperada:**
```
NAME          ENDPOINTS        AGE
backend-svc   10.244.2.5:80    2m
```

**Por que:** Agora o Service tem endpoints — o IP do pod backend aparece na lista. O kube-proxy atualiza as regras de iptables/IPVS automaticamente para rotear tráfego para esse endpoint.

---

## Passo 10: Verificar conectividade do frontend para o backend

```bash
# Verificar resolução DNS
kubectl exec frontend -n app-network -- nslookup backend-svc.app-network.svc.cluster.local
```

**Saída esperada:**
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      backend-svc.app-network.svc.cluster.local
Address 1: 10.96.x.x backend-svc.app-network.svc.cluster.local
```

```bash
# Verificar conectividade HTTP
kubectl exec frontend -n app-network -- wget -qO- --timeout=5 http://backend-svc:8080
```

**Saída esperada:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
</html>
```

**Por que:** A requisição agora funciona:
1. DNS resolve `backend-svc` para o ClusterIP
2. kube-proxy roteia o tráfego do ClusterIP para o endpoint (pod backend)
3. O nginx responde com a página padrão

A porta 8080 do Service é mapeada para a porta 80 do container (targetPort).

---

## Resumo do Processo de Troubleshooting de Rede

| Sintoma | Causa provável | Diagnóstico |
|---------|---------------|-------------|
| Timeout ao acessar Service | Endpoints vazios | `kubectl get endpoints` |
| Endpoints vazios | Selector não corresponde | Comparar selector vs labels |
| DNS não resolve | CoreDNS com problema | `kubectl get pods -n kube-system` |
| Connection refused | Pod não está escutando na porta | `kubectl exec -- netstat -tlnp` |

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| Endpoints | Lista de IPs dos pods que correspondem ao selector do Service |
| Selector | Label query que o Service usa para encontrar pods |
| `kubectl patch` | Altera campos específicos de um recurso sem recriar |
| `kubectl edit` | Abre o recurso em editor de texto para edição |
| ClusterIP | IP virtual do Service — kube-proxy roteia para endpoints |
| targetPort | Porta real no container (pode ser diferente da porta do Service) |
