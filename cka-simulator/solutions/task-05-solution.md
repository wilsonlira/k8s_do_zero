# Solução — Tarefa 05: Scaling e Rollback de Deployment

**Domínio:** Workloads & Scheduling
**Tempo estimado:** 8 minutos

---

## Passo 1: Criar o namespace production

```bash
kubectl create namespace production
```

**Saída esperada:**
```
namespace/production created
```

**Por que:** O namespace isola recursos logicamente. Criar o namespace primeiro garante que os recursos subsequentes tenham um local definido.

---

## Passo 2: Criar o Deployment webapp

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: production
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: nginx
        image: nginx:1.24
        ports:
        - containerPort: 80
EOF
```

**Saída esperada:**
```
deployment.apps/webapp created
```

**Por que:** Criamos o Deployment com a estratégia `RollingUpdate` configurada com `maxSurge=1` (permite criar 1 pod extra durante update) e `maxUnavailable=0` (nunca reduz a capacidade durante update). Isso garante zero downtime durante atualizações — sempre haverá pelo menos 2 pods disponíveis.

---

## Passo 3: Verificar que o Deployment está pronto

```bash
kubectl get deployment webapp -n production
```

**Saída esperada:**
```
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
webapp   2/2     2            2           30s
```

**Por que:** Confirmamos que as 2 réplicas iniciais estão rodando antes de prosseguir com o scaling.

---

## Passo 4: Escalar o Deployment para 5 réplicas

```bash
kubectl scale deployment webapp -n production --replicas=5
```

**Saída esperada:**
```
deployment.apps/webapp scaled
```

**Por que:** O `scale` altera o número desejado de réplicas. O controller-manager detecta a diferença entre o estado desejado (5) e o atual (2) e cria 3 novos pods. Isso simula o aumento de capacidade para lidar com mais tráfego.

---

## Passo 5: Verificar o scaling

```bash
kubectl get deployment webapp -n production
```

**Saída esperada:**
```
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
webapp   5/5     5            5           1m
```

**Por que:** Confirmamos que todas as 5 réplicas estão prontas antes de iniciar a atualização de imagem.

---

## Passo 6: Atualizar a imagem para nginx:1.25

```bash
kubectl set image deployment/webapp nginx=nginx:1.25 -n production
kubectl annotate deployment/webapp -n production kubernetes.io/change-cause="Atualização para nginx:1.25"
```

**Saída esperada:**
```
deployment.apps/webapp image updated
deployment.apps/webapp annotated
```

**Por que:** O `set image` altera a imagem do container, disparando um rollout. A anotação `kubernetes.io/change-cause` registra o motivo da mudança no histórico de revisões — isso é útil para auditoria e para saber qual revisão reverter em caso de problemas.

---

## Passo 7: Verificar o status do rollout

```bash
kubectl rollout status deployment/webapp -n production
```

**Saída esperada:**
```
Waiting for deployment "webapp" rollout to finish: 3 of 5 updated replicas are available...
Waiting for deployment "webapp" rollout to finish: 4 of 5 updated replicas are available...
deployment "webapp" successfully rolled out
```

**Por que:** O `rollout status` acompanha o progresso da atualização em tempo real. Com `maxUnavailable=0`, o Kubernetes cria pods novos antes de remover os antigos, garantindo que a capacidade nunca cai abaixo de 5.

---

## Passo 8: Verificar o histórico de revisões

```bash
kubectl rollout history deployment/webapp -n production
```

**Saída esperada:**
```
deployment.apps/webapp
REVISION  CHANGE-CAUSE
1         <none>
2         Atualização para nginx:1.25
```

**Por que:** O histórico mostra todas as revisões do Deployment. A revisão 1 é a criação original (nginx:1.24) e a revisão 2 é a atualização (nginx:1.25). Isso permite reverter para qualquer revisão anterior.

---

## Passo 9: Realizar rollback para a revisão anterior

```bash
kubectl rollout undo deployment/webapp -n production
```

**Saída esperada:**
```
deployment.apps/webapp rolled back
```

**Por que:** O `rollout undo` reverte o Deployment para a revisão anterior (neste caso, nginx:1.24). Isso é equivalente a `--to-revision=1`. O Kubernetes aplica a mesma estratégia de RollingUpdate para o rollback, garantindo zero downtime.

---

## Passo 10: Verificar o rollback

```bash
# Verificar a imagem atual
kubectl get deployment webapp -n production -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Saída esperada:**
```
nginx:1.24
```

```bash
# Verificar que todas as réplicas estão Running
kubectl get pods -n production -l app=webapp --no-headers | grep -c "Running"
```

**Saída esperada:**
```
5
```

```bash
# Verificar o Deployment completo
kubectl get deployment webapp -n production
```

**Saída esperada:**
```
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
webapp   5/5     5            5           3m
```

**Por que:** Confirmamos que o rollback foi bem-sucedido: a imagem voltou para nginx:1.24 e todas as 5 réplicas estão rodando. O número de réplicas é mantido durante o rollback (não volta para 2).

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| RollingUpdate | Estratégia que atualiza pods gradualmente sem downtime |
| maxSurge | Número máximo de pods extras durante update |
| maxUnavailable | Número máximo de pods indisponíveis durante update |
| `rollout undo` | Reverte para a revisão anterior do Deployment |
| `change-cause` | Anotação que documenta o motivo de cada revisão |
| Revisão | Snapshot da configuração do Deployment em um ponto no tempo |
