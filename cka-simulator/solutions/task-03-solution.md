# Solução — Tarefa 03: Upgrade de Componentes do Cluster

**Domínio:** Cluster Architecture, Installation & Configuration
**Tempo estimado:** 8 minutos

---

## Passo 1: Verificar a versão atual dos componentes

```bash
kube-apiserver --version
kube-controller-manager --version
kube-scheduler --version
```

**Saída esperada:**
```
Kubernetes v1.29.0
Kubernetes v1.29.0
Kubernetes v1.29.0
```

**Por que:** Antes de qualquer upgrade, documentamos a versão atual para confirmar o ponto de partida e ter referência para rollback se necessário. Isso também valida que os binários estão acessíveis no PATH.

---

## Passo 2: Verificar que os novos binários estão disponíveis

```bash
ls -la /opt/kubernetes/v1.29.1/
/opt/kubernetes/v1.29.1/kube-apiserver --version
```

**Saída esperada:**
```
-rwxr-xr-x 1 root root 130M Jan 15 10:00 kube-apiserver
-rwxr-xr-x 1 root root  65M Jan 15 10:00 kube-controller-manager
-rwxr-xr-x 1 root root  55M Jan 15 10:00 kube-scheduler
Kubernetes v1.29.1
```

**Por que:** Confirmamos que os binários da nova versão existem e são executáveis antes de iniciar o processo de upgrade. Isso evita iniciar um drain e descobrir depois que os binários não estão disponíveis.

---

## Passo 3: Drenar o nó control plane

```bash
kubectl drain k8s-control-plane --ignore-daemonsets --delete-emptydir-data
```

**Saída esperada:**
```
node/k8s-control-plane cordoned
evicting pod kube-system/coredns-...
pod/coredns-... evicted
node/k8s-control-plane drained
```

**Por que:** O `drain` faz duas coisas: (1) marca o nó como `SchedulingDisabled` (cordon) para que novos pods não sejam agendados nele, e (2) remove pods existentes de forma graceful. A flag `--ignore-daemonsets` é necessária porque DaemonSets não podem ser evicted (eles devem rodar em todos os nós). A flag `--delete-emptydir-data` permite evictar pods que usam volumes emptyDir.

---

## Passo 4: Atualizar os binários do control plane

```bash
sudo cp /opt/kubernetes/v1.29.1/kube-apiserver /usr/local/bin/kube-apiserver
sudo cp /opt/kubernetes/v1.29.1/kube-controller-manager /usr/local/bin/kube-controller-manager
sudo cp /opt/kubernetes/v1.29.1/kube-scheduler /usr/local/bin/kube-scheduler
```

**Por que:** Substituímos os binários antigos pelos novos. Usamos `cp` (e não `mv`) para manter os originais em `/opt/kubernetes/v1.29.1/` como referência. Os serviços ainda estão rodando com os binários antigos em memória — a atualização só terá efeito após o restart.

---

## Passo 5: Reiniciar os serviços atualizados

```bash
sudo systemctl restart kube-apiserver
sudo systemctl restart kube-controller-manager
sudo systemctl restart kube-scheduler
```

**Por que:** Cada serviço precisa ser reiniciado para carregar o novo binário. A ordem importa: o apiserver primeiro (pois os outros dependem dele), depois controller-manager e scheduler. O restart do apiserver causa uma breve indisponibilidade da API (poucos segundos).

---

## Passo 6: Verificar que os serviços estão ativos

```bash
sudo systemctl is-active kube-apiserver
sudo systemctl is-active kube-controller-manager
sudo systemctl is-active kube-scheduler
```

**Saída esperada:**
```
active
active
active
```

**Por que:** Confirmamos que todos os serviços iniciaram com sucesso após o restart. Se algum retornar `failed` ou `inactive`, precisamos investigar os logs com `journalctl -u <serviço>`.

---

## Passo 7: Fazer uncordon do nó control plane

```bash
kubectl uncordon k8s-control-plane
```

**Saída esperada:**
```
node/k8s-control-plane uncordoned
```

**Por que:** O `uncordon` remove a marca `SchedulingDisabled` do nó, permitindo que novos pods sejam agendados nele novamente. Sem esse passo, o nó continuaria rejeitando novos workloads.

---

## Passo 8: Verificar as novas versões

```bash
kube-apiserver --version
kube-controller-manager --version
kube-scheduler --version
```

**Saída esperada:**
```
Kubernetes v1.29.1
Kubernetes v1.29.1
Kubernetes v1.29.1
```

**Por que:** Confirmação final de que todos os componentes estão rodando na versão alvo.

---

## Passo 9: Verificar o estado do cluster

```bash
kubectl get nodes
```

**Saída esperada:**
```
NAME                STATUS   ROLES           AGE   VERSION
k8s-control-plane   Ready    control-plane   10d   v1.29.1
k8s-worker-01       Ready    <none>          10d   v1.29.0
```

```bash
kubectl get componentstatuses
```

**Saída esperada:**
```
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health":"true"}
```

```bash
kubectl version --short
```

**Saída esperada:**
```
Client Version: v1.29.0
Server Version: v1.29.1
```

**Por que:** Verificamos que o nó está Ready (sem SchedulingDisabled), que todos os componentes reportam status Healthy, e que a versão do servidor (apiserver) é a nova versão. O worker node ainda mostra v1.29.0 pois não foi atualizado nesta tarefa.

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| `drain` | Remove pods e impede scheduling no nó durante manutenção |
| `cordon/uncordon` | Controla se o nó aceita novos pods |
| Patch upgrade | Atualização de versão menor (1.29.0 → 1.29.1) — menor risco |
| `--ignore-daemonsets` | DaemonSets não são evicted pois devem rodar em todos os nós |
| Ordem de restart | apiserver → controller-manager → scheduler (dependências) |
