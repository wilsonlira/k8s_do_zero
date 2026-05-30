# Solução — Tarefa 07: Node Affinity, Taints e Tolerations

**Domínio:** Workloads & Scheduling
**Tempo estimado:** 8 minutos

---

## Passo 1: Identificar o nó worker

```bash
kubectl get nodes
```

**Saída esperada:**
```
NAME                STATUS   ROLES           AGE   VERSION
k8s-control-plane   Ready    control-plane   10d   v1.29.0
k8s-worker-01       Ready    <none>          10d   v1.29.0
```

**Por que:** Precisamos identificar o nome exato do nó worker para aplicar a label e o taint. O nó sem role `control-plane` é o worker.

---

## Passo 2: Adicionar a label ao nó worker

```bash
kubectl label node k8s-worker-01 workload=critical
```

**Saída esperada:**
```
node/k8s-worker-01 labeled
```

**Por que:** Labels em nós são usadas pelo Node Affinity para direcionar pods a nós específicos. A label `workload=critical` marca este nó como destinado a workloads críticos.

---

## Passo 3: Aplicar o taint no nó worker

```bash
kubectl taint nodes k8s-worker-01 dedicated=critical-apps:NoSchedule
```

**Saída esperada:**
```
node/k8s-worker-01 tainted
```

**Por que:** O taint `dedicated=critical-apps:NoSchedule` impede que pods **sem** a toleration correspondente sejam agendados neste nó. Isso cria uma "barreira" — apenas pods que explicitamente toleram este taint podem rodar aqui. É como uma placa de "acesso restrito".

---

## Passo 4: Criar o namespace scheduling-demo

```bash
kubectl create namespace scheduling-demo
```

**Saída esperada:**
```
namespace/scheduling-demo created
```

---

## Passo 5: Criar o Deployment critical-app com Node Affinity e Toleration

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: critical-app
  namespace: scheduling-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: critical-app
  template:
    metadata:
      labels:
        app: critical-app
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: workload
                operator: In
                values:
                - critical
      tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "critical-apps"
        effect: "NoSchedule"
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF
```

**Saída esperada:**
```
deployment.apps/critical-app created
```

**Por que:** Este Deployment combina dois mecanismos de scheduling:
1. **Node Affinity (`required`)** — o pod DEVE ser agendado em nós com `workload=critical`. Se nenhum nó tiver essa label, o pod fica Pending.
2. **Toleration** — o pod "tolera" o taint `dedicated=critical-apps:NoSchedule`, permitindo que seja agendado no nó com esse taint.

A combinação garante que: (a) o pod vai para o nó correto, e (b) o pod é permitido nesse nó apesar do taint.

---

## Passo 6: Criar o Deployment regular-app (sem toleration)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: regular-app
  namespace: scheduling-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: regular-app
  template:
    metadata:
      labels:
        app: regular-app
    spec:
      containers:
      - name: busybox
        image: busybox:1.36
        command: ["sh", "-c", "sleep 3600"]
EOF
```

**Saída esperada:**
```
deployment.apps/regular-app created
```

**Por que:** Este Deployment **não** tem toleration para o taint `dedicated=critical-apps:NoSchedule`. Se o único nó worker disponível tem esse taint, o pod ficará em estado Pending — demonstrando que o taint está funcionando como barreira.

---

## Passo 7: Verificar o scheduling dos pods

```bash
# Verificar critical-app (deve estar Running no nó worker)
kubectl get pods -n scheduling-demo -l app=critical-app -o wide
```

**Saída esperada:**
```
NAME                           READY   STATUS    RESTARTS   AGE   IP           NODE
critical-app-abc12-xyz34       1/1     Running   0          30s   10.244.2.5   k8s-worker-01
critical-app-abc12-xyz56       1/1     Running   0          30s   10.244.2.6   k8s-worker-01
```

```bash
# Verificar regular-app (deve estar Pending se não há outro nó sem taint)
kubectl get pods -n scheduling-demo -l app=regular-app
```

**Saída esperada:**
```
NAME                          READY   STATUS    RESTARTS   AGE
regular-app-def45-abc78       0/1     Pending   0          30s
```

```bash
# Ver o motivo do Pending
kubectl describe pod -n scheduling-demo -l app=regular-app | grep -A 3 "Events:"
```

**Saída esperada:**
```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  30s   default-scheduler  0/2 nodes are available: 1 node(s) had untolerated taint {dedicated: critical-apps}, 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }
```

**Por que:** O scheduler não consegue agendar o `regular-app` porque:
- O nó worker tem o taint `dedicated=critical-apps:NoSchedule` (e o pod não tolera)
- O nó control-plane tem o taint `node-role.kubernetes.io/control-plane:NoSchedule` (padrão)

Isso demonstra que taints efetivamente isolam nós para workloads específicos.

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| Node Affinity | Direciona pods para nós com labels específicas (atração) |
| `required` vs `preferred` | Required = obrigatório (Pending se não atender); Preferred = preferência (best-effort) |
| Taint | Marca um nó para repelir pods que não toleram o taint (repulsão) |
| Toleration | Permite que um pod seja agendado em nós com taints específicos |
| NoSchedule | Efeito que impede scheduling de novos pods (pods existentes não são afetados) |
| NoExecute | Efeito mais forte — remove pods existentes que não toleram |
