# Tarefa 17 — Troubleshooting de Falha em Deployment de Aplicação

**Domínio:** Troubleshooting
**Peso:** 6%
**Tempo recomendado:** 6 minutos

---

## Cenário

A equipe de DevOps criou um Deployment para a aplicação `api-server` no namespace `staging`, mas os pods não estão ficando Ready. O Deployment foi criado com 3 réplicas, porém todas estão reiniciando continuamente porque as **probes de saúde estão configuradas incorretamente**.

O manifesto aplicado foi:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: staging
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: api
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

O problema: o nginx escuta na porta **80** e serve conteúdo no path **/** — mas as probes estão configuradas para verificar a porta **8080** e o path **/healthz**, que não existem.

---

## Requisitos

1. Crie o namespace `staging` (se não existir).

2. Aplique o manifesto do Deployment acima.

3. Diagnostique por que os pods não estão ficando Ready:
   - Verifique o estado dos pods com `kubectl get pods`
   - Verifique eventos com `kubectl describe pod`
   - Identifique que as probes estão falhando (porta e path incorretos)

4. Corrija o Deployment alterando as probes:
   - **readinessProbe**: httpGet path `/` na porta `80`
   - **livenessProbe**: httpGet path `/` na porta `80`

5. Verifique que todas as 3 réplicas estão em estado Running e Ready após a correção.

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace staging existe
kubectl get namespace staging
# Esperado: staging   Active   <age>

# 2. Verificar que o Deployment existe com 3 réplicas desejadas
kubectl get deployment api-server -n staging -o jsonpath='{.spec.replicas}'
# Esperado: 3

# 3. Verificar que todas as réplicas estão disponíveis
kubectl get deployment api-server -n staging -o jsonpath='{.status.availableReplicas}'
# Esperado: 3

# 4. Verificar que todos os pods estão Running e Ready (1/1)
kubectl get pods -n staging -l app=api-server --no-headers | grep -c "1/1.*Running"
# Esperado: 3

# 5. Verificar que a readinessProbe está na porta 80
kubectl get deployment api-server -n staging -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}'
# Esperado: 80

# 6. Verificar que a readinessProbe usa o path /
kubectl get deployment api-server -n staging -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}'
# Esperado: /
```

---

## Dicas

- Use `kubectl describe pod <pod-name>` para ver eventos de probe failure.
- Eventos como "Readiness probe failed: connection refused" indicam porta incorreta.
- Eventos como "Readiness probe failed: HTTP probe failed with statuscode: 404" indicam path incorreto.
- Use `kubectl edit deployment` ou `kubectl set` para corrigir as probes.
- Após editar o Deployment, novos pods serão criados automaticamente com a configuração corrigida.
- O nginx padrão escuta na porta 80 e responde com 200 no path `/`.
