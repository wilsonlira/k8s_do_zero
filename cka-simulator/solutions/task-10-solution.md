# Solução — Tarefa 10: Configurar Ingress com Roteamento por Path e Troubleshooting DNS

**Domínio:** Services & Networking
**Tempo estimado:** 8 minutos

---

## Passo 1: Criar o namespace ingress-demo

```bash
kubectl create namespace ingress-demo
```

**Saída esperada:**
```
namespace/ingress-demo created
```

---

## Passo 2: Criar o Deployment app-v1

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v1
  namespace: ingress-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-v1
  template:
    metadata:
      labels:
        app: app-v1
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:0.2.3
        args:
        - "-text=stable-v1"
        ports:
        - containerPort: 5678
EOF
```

**Saída esperada:**
```
deployment.apps/app-v1 created
```

**Por que:** O `http-echo` é uma imagem leve que responde com o texto configurado em `-text`. Isso permite verificar facilmente qual backend está respondendo. A porta 5678 é a porta padrão do http-echo.

---

## Passo 3: Criar o Deployment app-v2

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v2
  namespace: ingress-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-v2
  template:
    metadata:
      labels:
        app: app-v2
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:0.2.3
        args:
        - "-text=canary-v2"
        ports:
        - containerPort: 5678
EOF
```

**Saída esperada:**
```
deployment.apps/app-v2 created
```

**Por que:** A segunda versão (canary) responde com texto diferente, permitindo validar que o roteamento por path está direcionando para o backend correto.

---

## Passo 4: Criar os Services

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app-v1-svc
  namespace: ingress-demo
spec:
  type: ClusterIP
  selector:
    app: app-v1
  ports:
  - port: 80
    targetPort: 5678
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: app-v2-svc
  namespace: ingress-demo
spec:
  type: ClusterIP
  selector:
    app: app-v2
  ports:
  - port: 80
    targetPort: 5678
    protocol: TCP
EOF
```

**Saída esperada:**
```
service/app-v1-svc created
service/app-v2-svc created
```

**Por que:** Os Services abstraem os pods e fornecem um endpoint estável para o Ingress. Note que a porta do Service é 80 (padrão HTTP) mas o targetPort é 5678 (porta do container). O Ingress aponta para o Service, não diretamente para os pods.

---

## Passo 5: Criar o recurso Ingress

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: ingress-demo
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /stable
        pathType: Prefix
        backend:
          service:
            name: app-v1-svc
            port:
              number: 80
      - path: /canary
        pathType: Prefix
        backend:
          service:
            name: app-v2-svc
            port:
              number: 80
EOF
```

**Saída esperada:**
```
ingress.networking.k8s.io/app-ingress created
```

**Por que:** O Ingress define regras de roteamento HTTP no nível de aplicação (Layer 7):
- **`ingressClassName: nginx`** — indica qual Ingress Controller deve processar este recurso
- **`pathType: Prefix`** — `/stable` corresponde a `/stable`, `/stable/`, `/stable/anything`
- **Roteamento por path** — um único ponto de entrada (IP do Ingress Controller) roteia para diferentes backends baseado no path da URL

Isso é mais eficiente que criar um NodePort por serviço e permite roteamento inteligente.

---

## Passo 6: Verificar os Deployments e Services

```bash
kubectl get deployments -n ingress-demo
```

**Saída esperada:**
```
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
app-v1   2/2     2            2           1m
app-v2   2/2     2            2           1m
```

```bash
kubectl get endpoints -n ingress-demo
```

**Saída esperada:**
```
NAME         ENDPOINTS                            AGE
app-v1-svc   10.244.1.5:5678,10.244.2.3:5678     1m
app-v2-svc   10.244.1.6:5678,10.244.2.4:5678     1m
```

**Por que:** Confirmamos que os Services têm endpoints (pods saudáveis). Se endpoints estiver vazio, o Ingress retornaria 503 (Service Unavailable).

---

## Passo 7: Verificar o roteamento via Ingress

```bash
# Obter o IP do Ingress Controller
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

# Testar rota /stable
curl http://$INGRESS_IP/stable
```

**Saída esperada:**
```
stable-v1
```

```bash
# Testar rota /canary
curl http://$INGRESS_IP/canary
```

**Saída esperada:**
```
canary-v2
```

**Por que:** Cada path retorna a resposta do backend correto, confirmando que o roteamento está funcionando. O Ingress Controller (NGINX) recebe a requisição, analisa o path, e encaminha para o Service correspondente.

---

## Passo 8: Verificar resolução DNS interna

```bash
kubectl run dns-check --image=busybox:1.36 --rm -it --restart=Never -n ingress-demo -- nslookup app-v1-svc.ingress-demo.svc.cluster.local
```

**Saída esperada:**
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      app-v1-svc.ingress-demo.svc.cluster.local
Address 1: 10.96.x.x app-v1-svc.ingress-demo.svc.cluster.local
```

```bash
kubectl run dns-check2 --image=busybox:1.36 --rm -it --restart=Never -n ingress-demo -- nslookup app-v2-svc.ingress-demo.svc.cluster.local
```

**Saída esperada:**
```
Name:      app-v2-svc.ingress-demo.svc.cluster.local
Address 1: 10.96.y.y app-v2-svc.ingress-demo.svc.cluster.local
```

**Por que:** A resolução DNS confirma que o CoreDNS está funcionando e que os Services são descobríveis por nome. Se o DNS falhar, verificamos o CoreDNS:

```bash
# Troubleshooting DNS — verificar pods do CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

**Saída esperada:**
```
NAME                       READY   STATUS    RESTARTS   AGE
coredns-abc12-def34        1/1     Running   0          10d
coredns-abc12-ghi56        1/1     Running   0          10d
```

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| Ingress | Recurso que define regras de roteamento HTTP/HTTPS (Layer 7) |
| Ingress Controller | Componente que implementa as regras do Ingress (ex: NGINX) |
| ingressClassName | Identifica qual controller processa o Ingress |
| pathType: Prefix | Corresponde ao path e qualquer sub-path |
| pathType: Exact | Corresponde apenas ao path exato |
| Roteamento por path | Um IP, múltiplos backends baseado no URL path |
| Roteamento por host | Múltiplos domínios no mesmo IP (virtual hosting) |
