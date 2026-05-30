# Solução — Tarefa 09: Configurar NetworkPolicy para Isolamento de Tráfego

**Domínio:** Services & Networking
**Tempo estimado:** 10 minutos

---

## Passo 1: Criar os namespaces com labels

```bash
kubectl create namespace database
kubectl label namespace database purpose=database

kubectl create namespace backend
kubectl label namespace backend purpose=backend
```

**Saída esperada:**
```
namespace/database created
namespace/database labeled
namespace/backend created
namespace/backend labeled
```

**Por que:** As labels nos namespaces são essenciais para a NetworkPolicy. O `namespaceSelector` na policy usa essas labels para identificar de quais namespaces o tráfego é permitido. Sem a label `purpose=backend` no namespace backend, a policy não reconheceria o tráfego como autorizado.

---

## Passo 2: Criar o Deployment MySQL no namespace database

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "secret123"
EOF
```

**Saída esperada:**
```
deployment.apps/mysql created
```

**Por que:** O MySQL é o recurso que queremos proteger. A label `app=mysql` será usada pela NetworkPolicy para identificar quais pods a regra se aplica (podSelector).

---

## Passo 3: Criar o Service para o MySQL

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: mysql-svc
  namespace: database
spec:
  type: ClusterIP
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
    protocol: TCP
EOF
```

**Saída esperada:**
```
service/mysql-svc created
```

**Por que:** O Service permite que outros pods acessem o MySQL via DNS (`mysql-svc.database.svc.cluster.local`) em vez de usar o IP do pod diretamente. A NetworkPolicy controla o tráfego no nível de rede (IP/porta), mas o Service facilita a descoberta.

---

## Passo 4: Criar o pod api-server no namespace backend

```bash
kubectl run api-server \
  --image=busybox:1.36 \
  --namespace=backend \
  --labels="app=api-server" \
  --command -- sleep 3600
```

**Saída esperada:**
```
pod/api-server created
```

**Por que:** Este pod simula a aplicação backend que precisa acessar o banco de dados. Ele está no namespace `backend` (que tem a label `purpose=backend`), então a NetworkPolicy deve permitir seu tráfego.

---

## Passo 5: Criar a NetworkPolicy

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-backend-only
  namespace: database
spec:
  podSelector:
    matchLabels:
      app: mysql
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: backend
    ports:
    - protocol: TCP
      port: 3306
EOF
```

**Saída esperada:**
```
networkpolicy.networking.k8s.io/db-allow-backend-only created
```

**Por que:** A NetworkPolicy implementa o princípio de "deny by default, allow explicitly":

1. **`podSelector: app=mysql`** — a policy se aplica aos pods do MySQL
2. **`policyTypes: [Ingress]`** — controla tráfego de entrada (quem pode conectar no MySQL)
3. **`ingress.from.namespaceSelector: purpose=backend`** — permite tráfego apenas de pods em namespaces com label `purpose=backend`
4. **`ports: TCP/3306`** — restringe a permissão apenas à porta do MySQL

O efeito implícito: qualquer tráfego de ingress que **não** corresponda às regras é **bloqueado**. Pods de outros namespaces (como `default`) não conseguirão conectar.

---

## Passo 6: Verificar que o backend consegue acessar o MySQL

```bash
kubectl exec api-server -n backend -- nc -zv -w3 mysql-svc.database.svc.cluster.local 3306
```

**Saída esperada:**
```
mysql-svc.database.svc.cluster.local (10.96.x.x:3306) open
```

**Por que:** O pod `api-server` está no namespace `backend` (label `purpose=backend`), então a NetworkPolicy permite seu tráfego na porta 3306. A conexão é bem-sucedida.

---

## Passo 7: Verificar que outros namespaces são bloqueados

```bash
kubectl run test-blocked --image=busybox:1.36 --rm -it --restart=Never -n default -- nc -zv -w3 mysql-svc.database.svc.cluster.local 3306
```

**Saída esperada:**
```
nc: mysql-svc.database.svc.cluster.local (10.96.x.x:3306): Connection timed out
pod "test-blocked" deleted
```

**Por que:** O pod no namespace `default` não tem a label `purpose=backend`, então a NetworkPolicy bloqueia o tráfego. O timeout confirma que a política está funcionando — o pacote é descartado silenciosamente (não há resposta de "connection refused", apenas timeout).

---

## Passo 8: Verificar a NetworkPolicy

```bash
kubectl describe networkpolicy db-allow-backend-only -n database
```

**Saída esperada:**
```
Name:         db-allow-backend-only
Namespace:    database
Created on:   2024-01-15 10:30:00
Labels:       <none>
Annotations:  <none>
Spec:
  PodSelector:     app=mysql
  Allowing ingress traffic:
    To Port: 3306/TCP
    From:
      NamespaceSelector: purpose=backend
  Not affecting egress traffic
  Policy Types: Ingress
```

**Por que:** O `describe` mostra uma visão legível da policy, confirmando que está configurada conforme os requisitos.

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| NetworkPolicy | Regras de firewall no nível de pod/namespace |
| podSelector | Define quais pods a policy protege |
| namespaceSelector | Permite tráfego de pods em namespaces com labels específicas |
| Deny by default | Quando uma policy existe, todo tráfego não explicitamente permitido é bloqueado |
| Ingress | Tráfego de entrada (quem pode conectar no pod) |
| Egress | Tráfego de saída (para onde o pod pode conectar) |
| CNI plugin | A NetworkPolicy só funciona se o CNI plugin suportar (Calico, Cilium — sim; Flannel — não) |
