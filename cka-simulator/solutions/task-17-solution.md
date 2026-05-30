# Solução — Tarefa 17: Troubleshooting de Falha em Deployment de Aplicação

**Domínio:** Troubleshooting
**Tempo estimado:** 6 minutos

---

## Passo 1: Criar o namespace staging

```bash
kubectl create namespace staging
```

**Saída esperada:**
```
namespace/staging created
```

---

## Passo 2: Aplicar o manifesto do Deployment com probes incorretas

```bash
cat <<EOF | kubectl apply -f -
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
EOF
```

**Saída esperada:**
```
deployment.apps/api-server created
```

**Por que:** Aplicamos o manifesto "quebrado" para simular o cenário. O nginx escuta na porta 80 e serve conteúdo no path `/`, mas as probes estão configuradas para porta 8080 e path `/healthz` — ambos incorretos.

---

## Passo 3: Diagnosticar — Verificar o estado dos pods

```bash
kubectl get pods -n staging -l app=api-server
```

**Saída esperada:**
```
NAME                          READY   STATUS    RESTARTS      AGE
api-server-abc12-def34        0/1     Running   2 (5s ago)    45s
api-server-abc12-ghi56        0/1     Running   1 (10s ago)   45s
api-server-abc12-jkl78        0/1     Running   2 (3s ago)    45s
```

**Por que:** Os pods estão `Running` mas `0/1` Ready — isso indica que a **readinessProbe** está falhando (o pod não é considerado pronto para receber tráfego). Os RESTARTS crescentes indicam que a **livenessProbe** também está falhando, causando reinicializações do container.

---

## Passo 4: Diagnosticar — Verificar eventos do pod

```bash
kubectl describe pod -n staging -l app=api-server | grep -A 10 "Events:" | head -20
```

**Saída esperada:**
```
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  60s                default-scheduler  Successfully assigned staging/api-server-abc12-def34 to k8s-worker-01
  Normal   Pulled     60s                kubelet            Container image "nginx:1.25" already present on machine
  Normal   Created    60s                kubelet            Created container api
  Normal   Started    60s                kubelet            Started container api
  Warning  Unhealthy  45s (x3 over 55s)  kubelet            Readiness probe failed: Get "http://10.244.2.5:8080/healthz": dial tcp 10.244.2.5:8080: connect: connection refused
  Warning  Unhealthy  30s (x2 over 40s)  kubelet            Liveness probe failed: Get "http://10.244.2.5:8080/healthz": dial tcp 10.244.2.5:8080: connect: connection refused
  Normal   Killing    30s                kubelet            Container api failed liveness probe, will be restarted
```

**Por que:** Os eventos revelam a causa raiz:
- **"connection refused"** na porta 8080 — o nginx não escuta nessa porta (escuta na 80)
- Se a porta estivesse correta mas o path errado, veríamos "HTTP probe failed with statuscode: 404"

O diagnóstico é claro: as probes estão apontando para porta e path incorretos.

---

## Passo 5: Diagnosticar — Confirmar a porta do nginx

```bash
# Verificar em qual porta o nginx está escutando (dentro do container)
kubectl exec -n staging $(kubectl get pods -n staging -l app=api-server -o jsonpath='{.items[0].metadata.name}') -- ss -tlnp 2>/dev/null || \
kubectl exec -n staging $(kubectl get pods -n staging -l app=api-server -o jsonpath='{.items[0].metadata.name}') -- cat /etc/nginx/conf.d/default.conf
```

**Saída esperada:**
```
server {
    listen       80;
    server_name  localhost;
    ...
}
```

**Por que:** Confirmamos que o nginx escuta na porta 80 (não 8080). O path padrão `/` retorna a página de boas-vindas com HTTP 200, enquanto `/healthz` retornaria 404.

---

## Passo 6: Corrigir — Atualizar as probes do Deployment

```bash
kubectl patch deployment api-server -n staging --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port", "value": 80},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 80},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/path", "value": "/"}
]'
```

**Saída esperada:**
```
deployment.apps/api-server patched
```

**Por que:** Corrigimos ambas as probes:
- **readinessProbe**: path `/` na porta `80` — verifica se o nginx está pronto para receber tráfego
- **livenessProbe**: path `/` na porta `80` — verifica se o nginx está vivo (reinicia se falhar)

O `kubectl patch` com `--type='json'` permite alterações cirúrgicas em campos específicos. Após o patch, o Deployment cria novos pods com a configuração corrigida (rolling update).

---

## Passo 7: Aguardar o rollout da correção

```bash
kubectl rollout status deployment/api-server -n staging
```

**Saída esperada:**
```
Waiting for deployment "api-server" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "api-server" rollout to finish: 2 of 3 updated replicas are available...
deployment "api-server" successfully rolled out
```

**Por que:** O Deployment cria novos pods com as probes corrigidas e remove os antigos gradualmente. O `rollout status` acompanha o progresso até que todas as 3 réplicas estejam disponíveis.

---

## Passo 8: Verificar que todos os pods estão Ready

```bash
kubectl get pods -n staging -l app=api-server
```

**Saída esperada:**
```
NAME                          READY   STATUS    RESTARTS   AGE
api-server-xyz12-abc34        1/1     Running   0          30s
api-server-xyz12-def56        1/1     Running   0          25s
api-server-xyz12-ghi78        1/1     Running   0          20s
```

**Por que:** Todos os pods mostram `1/1` Ready e `0` Restarts — as probes estão passando corretamente. Os novos pods (note os nomes diferentes) substituíram os antigos com probes incorretas.

---

## Passo 9: Verificar a configuração corrigida

```bash
# Verificar readinessProbe
kubectl get deployment api-server -n staging -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet}'
```

**Saída esperada:**
```json
{"path":"/","port":80}
```

```bash
# Verificar livenessProbe
kubectl get deployment api-server -n staging -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet}'
```

**Saída esperada:**
```json
{"path":"/","port":80}
```

```bash
# Verificar réplicas disponíveis
kubectl get deployment api-server -n staging -o jsonpath='{.status.availableReplicas}'
```

**Saída esperada:**
```
3
```

**Por que:** Confirmação final de que as probes estão configuradas corretamente e todas as réplicas estão disponíveis.

---

## Resumo do Processo de Troubleshooting de Probes

| Mensagem de erro | Causa | Solução |
|-----------------|-------|---------|
| "connection refused" | Porta incorreta na probe | Corrigir para a porta do container |
| "HTTP probe failed with statuscode: 404" | Path incorreto na probe | Corrigir para um path que retorne 200 |
| "HTTP probe failed with statuscode: 500" | Aplicação com erro interno | Investigar logs da aplicação |
| "dial tcp: i/o timeout" | Container não está respondendo | Verificar se o processo está rodando |

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| readinessProbe | Determina se o pod está pronto para receber tráfego (afeta endpoints do Service) |
| livenessProbe | Determina se o container está vivo (reinicia se falhar) |
| startupProbe | Protege containers lentos para iniciar (desabilita liveness/readiness até passar) |
| initialDelaySeconds | Tempo de espera antes da primeira verificação |
| periodSeconds | Intervalo entre verificações |
| failureThreshold | Número de falhas consecutivas antes de agir (padrão: 3) |
| `kubectl patch --type=json` | Alteração cirúrgica usando JSON Patch (RFC 6902) |
