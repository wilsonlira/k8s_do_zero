# Solução — Tarefa 16: Troubleshooting de Componente do Control Plane (kube-scheduler)

**Domínio:** Troubleshooting
**Tempo estimado:** 7 minutos

---

## Passo 1: Verificar a saúde dos componentes do control plane

```bash
# Verificar kube-apiserver
curl -sk https://localhost:6443/healthz
```

**Saída esperada:**
```
ok
```

```bash
# Verificar kube-controller-manager
curl -sk https://localhost:10257/healthz
```

**Saída esperada:**
```
ok
```

```bash
# Verificar kube-scheduler
curl -sk https://localhost:10259/healthz
```

**Saída esperada:**
```
curl: (7) Failed to connect to localhost port 10259: Connection refused
```

```bash
# Verificar etcd
curl -sk --cacert /etc/etcd/ca.pem --cert /etc/etcd/etcd.pem --key /etc/etcd/etcd-key.pem https://localhost:2379/health
```

**Saída esperada:**
```json
{"health":"true"}
```

**Por que:** Verificamos cada componente individualmente para identificar qual está com problema. O apiserver, controller-manager e etcd respondem "ok"/"true", mas o scheduler retorna "Connection refused" — indicando que o processo não está escutando na porta 10259 (ou seja, não está rodando).

---

## Passo 2: Confirmar o sintoma — Pod em Pending

```bash
kubectl run test-pending --image=nginx:1.25 --restart=Never
kubectl get pod test-pending
```

**Saída esperada:**
```
NAME           READY   STATUS    RESTARTS   AGE
test-pending   0/1     Pending   0          10s
```

```bash
kubectl describe pod test-pending | grep -A 3 "Events:"
```

**Saída esperada:**
```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  10s   default-scheduler  0/2 nodes are available: ...
```

**Ou sem nenhum evento de scheduling (se o scheduler não está processando).**

**Por que:** Um pod em Pending sem evento de scheduling (ou com FailedScheduling) é o sintoma clássico de scheduler inativo. O apiserver aceita a criação do pod, mas nenhum componente está atribuindo o pod a um nó.

---

## Passo 3: Verificar o status do serviço kube-scheduler

```bash
systemctl status kube-scheduler
```

**Saída esperada:**
```
● kube-scheduler.service - Kubernetes Scheduler
     Loaded: loaded (/etc/systemd/system/kube-scheduler.service; enabled; vendor preset: enabled)
     Active: inactive (dead) since Mon 2024-01-15 10:00:00 UTC; 30min ago
   Main PID: 1234 (code=exited, status=0/SUCCESS)
```

**Por que:** O status `inactive (dead)` com `status=0/SUCCESS` confirma que o scheduler foi parado manualmente (não crashou). Se fosse um crash, veríamos um exit code diferente de 0.

---

## Passo 4: Verificar logs do scheduler

```bash
journalctl -u kube-scheduler --no-pager -n 15
```

**Saída esperada:**
```
Jan 15 10:00:00 k8s-control-plane systemd[1]: Stopping Kubernetes Scheduler...
Jan 15 10:00:00 k8s-control-plane systemd[1]: kube-scheduler.service: Deactivated successfully.
Jan 15 10:00:00 k8s-control-plane systemd[1]: Stopped Kubernetes Scheduler.
```

**Por que:** Os logs confirmam que foi uma parada limpa (não há erros de configuração ou certificado). Isso significa que basta reiniciar o serviço — não há necessidade de corrigir configuração.

---

## Passo 5: Reiniciar o kube-scheduler

```bash
sudo systemctl start kube-scheduler
```

**Por que:** Como não há erro de configuração, reiniciar o serviço é suficiente para restaurar a funcionalidade. O scheduler se reconecta ao apiserver e começa a processar pods pendentes.

---

## Passo 6: Verificar que o scheduler está saudável

```bash
systemctl is-active kube-scheduler
```

**Saída esperada:**
```
active
```

```bash
curl -sk https://localhost:10259/healthz
```

**Saída esperada:**
```
ok
```

**Por que:** Confirmamos que o serviço está ativo E que o endpoint de health responde. Ambas as verificações são importantes — o serviço pode estar "active" mas com erro interno (nesse caso o healthz retornaria erro).

---

## Passo 7: Verificar que não há erros nos logs

```bash
journalctl -u kube-scheduler --no-pager -n 5 --priority=err
```

**Saída esperada:**
```
(vazio — nenhum erro)
```

**Por que:** Confirmamos que o scheduler iniciou sem erros. Erros comuns após restart incluem: certificado inválido, kubeconfig incorreto, ou apiserver inacessível.

---

## Passo 8: Verificar que pods pendentes são agendados

```bash
# Verificar o pod de teste criado anteriormente
kubectl get pod test-pending
```

**Saída esperada:**
```
NAME           READY   STATUS    RESTARTS   AGE
test-pending   1/1     Running   0          2m
```

**Por que:** O scheduler processa automaticamente todos os pods pendentes assim que inicia. O pod `test-pending` que estava em Pending agora deve estar Running — o scheduler atribuiu um nó e o kubelet iniciou o container.

---

## Passo 9: Criar um novo pod de teste para confirmar

```bash
kubectl run scheduler-test --image=nginx:1.25 --restart=Never
kubectl wait --for=condition=Ready pod/scheduler-test --timeout=30s
```

**Saída esperada:**
```
pod/scheduler-test created
pod/scheduler-test condition met
```

```bash
kubectl get pod scheduler-test -o jsonpath='{.spec.nodeName}'
```

**Saída esperada:**
```
k8s-worker-01
```

**Por que:** Um novo pod criado após o restart do scheduler deve ser agendado imediatamente. O `kubectl wait` confirma que o pod atingiu o estado Ready dentro de 30 segundos. O `nodeName` mostra em qual nó o scheduler colocou o pod.

---

## Passo 10: Limpar pods de teste

```bash
kubectl delete pod test-pending scheduler-test --grace-period=0 --force
```

**Saída esperada:**
```
pod "test-pending" force deleted
pod "scheduler-test" force deleted
```

**Por que:** Limpamos os pods de teste para não deixar recursos desnecessários no cluster.

---

## Resumo do Processo de Troubleshooting do Control Plane

| Componente | Porta Health | Sintoma quando inativo |
|-----------|-------------|----------------------|
| kube-apiserver | 6443 | kubectl não funciona, nenhuma operação possível |
| kube-controller-manager | 10257 | Deployments não escalam, ReplicaSets não reconciliam |
| kube-scheduler | 10259 | Novos pods ficam em Pending indefinidamente |
| etcd | 2379 | Nenhuma leitura/escrita de estado funciona |

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| kube-scheduler | Atribui pods a nós baseado em recursos, affinity, taints |
| Pending | Pod aceito pelo apiserver mas sem nó atribuído |
| Health endpoint | `/healthz` retorna "ok" se o componente está funcional |
| `curl -sk` | `-s` silencioso, `-k` ignora validação de certificado TLS |
| Reconciliação | Após restart, o scheduler processa todos os pods pendentes |
