# Solução — Tarefa 13: Debugging de Pod em CrashLoopBackOff

**Domínio:** Troubleshooting
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

---

## Passo 2: Aplicar o manifesto do pod com erro

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: web-app
  namespace: production
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    command: ["/bin/sh", "-c", "cat /etc/config/app.conf && nginx -g 'daemon off;'"]
    ports:
    - containerPort: 80
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
  volumes:
  - name: config-volume
    configMap:
      name: app-config
EOF
```

**Saída esperada:**
```
pod/web-app created
```

**Por que:** Aplicamos o manifesto "quebrado" para simular o cenário de troubleshooting. O pod referencia um ConfigMap `app-config` que não existe.

---

## Passo 3: Diagnosticar — Verificar o estado do pod

```bash
kubectl get pod web-app -n production
```

**Saída esperada:**
```
NAME      READY   STATUS                       RESTARTS   AGE
web-app   0/1     CreateContainerConfigError   0          10s
```

**Por que:** O status `CreateContainerConfigError` (ou `ContainerCreating` seguido de erro) indica que o container não conseguiu ser criado. Isso é diferente de `CrashLoopBackOff` (que indica que o container inicia e morre). O erro ocorre antes mesmo do container iniciar porque o volume não pode ser montado.

---

## Passo 4: Diagnosticar — Verificar eventos do pod

```bash
kubectl describe pod web-app -n production | grep -A 10 "Events:"
```

**Saída esperada:**
```
Events:
  Type     Reason       Age   From               Message
  ----     ------       ----  ----               -------
  Normal   Scheduled    30s   default-scheduler  Successfully assigned production/web-app to k8s-worker-01
  Warning  FailedMount  15s   kubelet            MountVolume.SetUp failed for volume "config-volume" : configmap "app-config" not found
```

**Por que:** Os eventos revelam a causa raiz: `configmap "app-config" not found`. O kubelet não consegue montar o volume porque o ConfigMap referenciado não existe no namespace `production`. Este é o passo mais importante do troubleshooting — os eventos do pod quase sempre indicam a causa do problema.

---

## Passo 5: Diagnosticar — Verificar logs (opcional)

```bash
kubectl logs web-app -n production
```

**Saída esperada:**
```
Error from server (BadRequest): container "nginx" in pod "web-app" is waiting to start: CreateContainerConfigError
```

**Por que:** Como o container nunca iniciou, não há logs de aplicação. O erro confirma que o problema é na configuração do container (volume), não na aplicação em si.

---

## Passo 6: Corrigir — Criar o ConfigMap app-config

```bash
kubectl create configmap app-config \
  --namespace=production \
  --from-literal=app.conf="server_name=web-app;"
```

**Saída esperada:**
```
configmap/app-config created
```

**Por que:** Criamos o ConfigMap que o pod espera. A chave `app.conf` será montada como arquivo em `/etc/config/app.conf` dentro do container. O valor `server_name=web-app;` é o conteúdo que o comando `cat` no container irá ler.

---

## Passo 7: Deletar e recriar o pod

```bash
kubectl delete pod web-app -n production
```

**Saída esperada:**
```
pod "web-app" deleted
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: web-app
  namespace: production
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    command: ["/bin/sh", "-c", "cat /etc/config/app.conf && nginx -g 'daemon off;'"]
    ports:
    - containerPort: 80
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
  volumes:
  - name: config-volume
    configMap:
      name: app-config
EOF
```

**Saída esperada:**
```
pod/web-app created
```

**Por que:** Pods com volumes de ConfigMap que não existiam na criação precisam ser recriados. O kubelet não re-tenta montar volumes automaticamente após a criação do ConfigMap — é necessário deletar e recriar o pod.

---

## Passo 8: Verificar que o pod está Running

```bash
kubectl get pod web-app -n production
```

**Saída esperada:**
```
NAME      READY   STATUS    RESTARTS   AGE
web-app   1/1     Running   0          15s
```

---

## Passo 9: Verificar que o nginx está respondendo

```bash
kubectl exec web-app -n production -- curl -s -o /dev/null -w "%{http_code}" http://localhost:80
```

**Saída esperada:**
```
200
```

**Por que:** O HTTP 200 confirma que o nginx está servindo requisições corretamente. O container iniciou com sucesso: primeiro leu o arquivo de configuração (`cat /etc/config/app.conf`) e depois iniciou o nginx.

---

## Passo 10: Verificar o conteúdo do ConfigMap montado

```bash
kubectl exec web-app -n production -- cat /etc/config/app.conf
```

**Saída esperada:**
```
server_name=web-app;
```

**Por que:** Confirmamos que o ConfigMap foi montado corretamente como arquivo no caminho esperado.

---

## Resumo do Processo de Troubleshooting

| Passo | Comando | O que procurar |
|-------|---------|----------------|
| 1 | `kubectl get pod` | Status anormal (CrashLoopBackOff, Error, CreateContainerConfigError) |
| 2 | `kubectl describe pod` | Eventos com Warning (FailedMount, FailedScheduling, etc.) |
| 3 | `kubectl logs` | Erros de aplicação (se o container chegou a iniciar) |
| 4 | Identificar causa raiz | ConfigMap/Secret não existe, imagem não encontrada, etc. |
| 5 | Corrigir | Criar recurso faltante, corrigir configuração |
| 6 | Recriar pod | Delete + apply (ou aguardar restart se for Deployment) |

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| CrashLoopBackOff | Container inicia e morre repetidamente (erro de aplicação) |
| CreateContainerConfigError | Container não consegue ser criado (volume/secret/configmap faltando) |
| ConfigMap como volume | Cada chave do ConfigMap vira um arquivo no mountPath |
| `kubectl describe` | Mostra eventos — primeira ferramenta de troubleshooting |
| `kubectl logs` | Mostra stdout/stderr do container (só funciona se container iniciou) |
