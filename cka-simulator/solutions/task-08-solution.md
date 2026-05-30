# Solução — Tarefa 08: Criar e Expor Services (ClusterIP e NodePort)

**Domínio:** Services & Networking
**Tempo estimado:** 8 minutos

---

## Passo 1: Criar o namespace webapp

```bash
kubectl create namespace webapp
```

**Saída esperada:**
```
namespace/webapp created
```

**Por que:** Isolamos a aplicação web em seu próprio namespace para organização e controle de acesso.

---

## Passo 2: Criar o Deployment frontend

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: webapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
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
deployment.apps/frontend created
```

**Por que:** O Deployment cria 3 réplicas do nginx para alta disponibilidade. A label `app=frontend` será usada pelos Services como selector para identificar quais pods recebem tráfego.

---

## Passo 3: Verificar que os pods estão rodando

```bash
kubectl get pods -n webapp -l app=frontend
```

**Saída esperada:**
```
NAME                        READY   STATUS    RESTARTS   AGE
frontend-abc12-def34        1/1     Running   0          30s
frontend-abc12-ghi56        1/1     Running   0          30s
frontend-abc12-jkl78        1/1     Running   0          30s
```

**Por que:** Confirmamos que os 3 pods estão Running antes de criar os Services. Um Service sem pods saudáveis não teria endpoints.

---

## Passo 4: Criar o Service ClusterIP

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  namespace: webapp
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
EOF
```

**Saída esperada:**
```
service/frontend-svc created
```

**Por que:** O Service ClusterIP cria um IP virtual interno ao cluster que distribui tráfego entre os 3 pods. Outros pods podem acessar o frontend usando o nome DNS `frontend-svc.webapp.svc.cluster.local` ou simplesmente `frontend-svc` (dentro do mesmo namespace). O ClusterIP **não** é acessível de fora do cluster.

---

## Passo 5: Criar o Service NodePort

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: frontend-nodeport
  namespace: webapp
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
    protocol: TCP
EOF
```

**Saída esperada:**
```
service/frontend-nodeport created
```

**Por que:** O Service NodePort expõe a aplicação em uma porta fixa (30080) em **todos os nós** do cluster. Qualquer requisição para `<IP-do-nó>:30080` é roteada para um dos pods do frontend. Isso permite acesso externo sem necessidade de um LoadBalancer.

---

## Passo 6: Verificar os Services e endpoints

```bash
kubectl get svc -n webapp
```

**Saída esperada:**
```
NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
frontend-svc        ClusterIP   10.96.45.123    <none>        80/TCP         30s
frontend-nodeport   NodePort    10.96.78.456    <none>        80:30080/TCP   15s
```

```bash
kubectl get endpoints frontend-svc -n webapp
```

**Saída esperada:**
```
NAME           ENDPOINTS                                      AGE
frontend-svc   10.244.1.5:80,10.244.1.6:80,10.244.2.3:80     30s
```

**Por que:** Os endpoints mostram os IPs dos pods que o Service está balanceando. Devemos ver 3 IPs (um por pod). Se os endpoints estiverem vazios, o selector do Service não corresponde às labels dos pods.

---

## Passo 7: Verificar resolução DNS interna

```bash
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -n webapp -- nslookup frontend-svc.webapp.svc.cluster.local
```

**Saída esperada:**
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      frontend-svc.webapp.svc.cluster.local
Address 1: 10.96.45.123 frontend-svc.webapp.svc.cluster.local
```

**Por que:** O CoreDNS resolve o nome do Service para seu ClusterIP. Isso permite que aplicações se comuniquem usando nomes DNS em vez de IPs hardcoded — essencial para ambientes dinâmicos onde IPs mudam.

---

## Passo 8: Verificar acesso via NodePort

```bash
# Obter o IP do nó worker
WORKER_IP=$(kubectl get node k8s-worker-01 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

# Testar acesso via NodePort
curl http://$WORKER_IP:30080
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

**Por que:** O acesso via NodePort confirma que o tráfego externo está sendo roteado corretamente: requisição na porta 30080 do nó → kube-proxy → pod do nginx na porta 80. Isso simula como um usuário externo acessaria a aplicação.

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| ClusterIP | IP virtual interno — acessível apenas dentro do cluster |
| NodePort | Expõe o Service em uma porta fixa (30000-32767) em todos os nós |
| Selector | Conecta o Service aos pods com labels correspondentes |
| Endpoints | Lista de IPs dos pods que o Service está balanceando |
| DNS interno | CoreDNS resolve `<svc>.<ns>.svc.cluster.local` para o ClusterIP |
| targetPort | Porta no container que recebe o tráfego |
| port | Porta exposta pelo Service |
| nodePort | Porta exposta em cada nó do cluster |
