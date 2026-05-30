# Solução — Tarefa 06: Criação e Gerenciamento de DaemonSet

**Domínio:** Workloads & Scheduling
**Tempo estimado:** 7 minutos

---

## Passo 1: Criar o namespace monitoring

```bash
kubectl create namespace monitoring
```

**Saída esperada:**
```
namespace/monitoring created
```

**Por que:** Isolamos os recursos de monitoramento em um namespace dedicado, seguindo a boa prática de separação de responsabilidades.

---

## Passo 2: Criar o DaemonSet node-monitor

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-monitor
      type: daemon
  template:
    metadata:
      labels:
        app: node-monitor
        type: daemon
    spec:
      containers:
      - name: monitor
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo \$(date) - Node monitoring active; sleep 30; done"]
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "100m"
            memory: "128Mi"
        volumeMounts:
        - name: host-logs
          mountPath: /host-logs
          readOnly: true
      volumes:
      - name: host-logs
        hostPath:
          path: /var/log
          type: Directory
EOF
```

**Saída esperada:**
```
daemonset.apps/node-monitor created
```

**Por que:** O DaemonSet garante que exatamente **um pod** rode em cada nó elegível do cluster. Diferente de um Deployment (que distribui N réplicas), o DaemonSet escala automaticamente com o cluster — quando um novo nó é adicionado, um pod é criado nele automaticamente.

Detalhes da configuração:
- **`busybox:1.36`** — imagem leve para o agente de monitoramento
- **`resources`** — requests definem o mínimo garantido; limits definem o máximo permitido. Isso evita que o agente consuma recursos excessivos do nó
- **`hostPath /var/log`** — monta o diretório de logs do host no container, permitindo que o agente leia logs do sistema operacional
- **`readOnly: true`** — o agente só precisa ler logs, não escrever. Isso segue o princípio do menor privilégio

---

## Passo 3: Verificar que o DaemonSet está rodando

```bash
kubectl get daemonset node-monitor -n monitoring
```

**Saída esperada:**
```
NAME           DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
node-monitor   2         2         2       2            2           <none>          30s
```

**Por que:** O campo DESIRED mostra quantos nós são elegíveis (sem taints que impeçam o scheduling). CURRENT = READY = DESIRED confirma que todos os pods foram criados e estão saudáveis.

---

## Passo 4: Verificar os pods em cada nó

```bash
kubectl get pods -n monitoring -l app=node-monitor -o wide
```

**Saída esperada:**
```
NAME                 READY   STATUS    RESTARTS   AGE   IP           NODE
node-monitor-abc12   1/1     Running   0          45s   10.244.1.5   k8s-control-plane
node-monitor-def34   1/1     Running   0          45s   10.244.2.3   k8s-worker-01
```

**Por que:** O `-o wide` mostra em qual nó cada pod está rodando. Devemos ver um pod por nó elegível. Se o control plane tiver taints (como `node-role.kubernetes.io/control-plane:NoSchedule`), o pod não será agendado lá a menos que adicionemos uma toleration.

---

## Passo 5: Verificar os resource limits

```bash
kubectl get daemonset node-monitor -n monitoring -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

**Saída esperada:**
```json
{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
```

**Por que:** Confirmamos que os limites de recursos estão configurados corretamente. Sem limits, um agente com bug poderia consumir toda a CPU/memória do nó, afetando outros workloads.

---

## Passo 6: Verificar o volume hostPath

```bash
kubectl get daemonset node-monitor -n monitoring -o jsonpath='{.spec.template.spec.volumes[0].hostPath.path}'
```

**Saída esperada:**
```
/var/log
```

```bash
# Verificar que o volume está montado como readOnly
kubectl get daemonset node-monitor -n monitoring -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[0].readOnly}'
```

**Saída esperada:**
```
true
```

**Por que:** Confirmamos que o diretório correto do host está montado e que a montagem é somente leitura, conforme os requisitos de segurança.

---

## Passo 7: Verificar os logs do agente

```bash
kubectl logs -n monitoring -l app=node-monitor --tail=3
```

**Saída esperada:**
```
Mon Jan 15 10:30:00 UTC 2024 - Node monitoring active
Mon Jan 15 10:30:30 UTC 2024 - Node monitoring active
Mon Jan 15 10:31:00 UTC 2024 - Node monitoring active
```

**Por que:** Verificamos que o agente está executando corretamente, imprimindo a mensagem de monitoramento a cada 30 segundos.

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| DaemonSet | Garante 1 pod por nó elegível — escala automaticamente com o cluster |
| hostPath | Monta um diretório do nó host dentro do container |
| readOnly | Restringe o acesso ao volume para somente leitura |
| Resource requests | Mínimo de recursos garantidos pelo scheduler |
| Resource limits | Máximo de recursos que o container pode usar |
| Labels | Metadados usados para seleção e filtragem de recursos |
