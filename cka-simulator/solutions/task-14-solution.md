# Solução — Tarefa 14: Troubleshooting de Node NotReady

**Domínio:** Troubleshooting
**Tempo estimado:** 7 minutos

---

## Passo 1: Identificar o nó com problema

```bash
kubectl get nodes
```

**Saída esperada:**
```
NAME                STATUS     ROLES           AGE   VERSION
k8s-control-plane   Ready      control-plane   10d   v1.29.0
k8s-worker-01       NotReady   <none>          10d   v1.29.0
```

**Por que:** O primeiro passo é identificar **qual** nó está com problema. O status `NotReady` indica que o kubelet desse nó parou de enviar heartbeats ao API server. O node controller marca o nó como NotReady após ~40 segundos sem heartbeat.

---

## Passo 2: Obter detalhes do nó

```bash
kubectl describe node k8s-worker-01 | grep -A 5 "Conditions:"
```

**Saída esperada:**
```
Conditions:
  Type                 Status    LastHeartbeatTime                 Reason                       Message
  ----                 ------    -----------------                 ------                       -------
  Ready                Unknown   2024-01-15T10:25:00Z              NodeStatusUnknown            Kubelet stopped posting node status.
  MemoryPressure       Unknown   2024-01-15T10:25:00Z              NodeStatusUnknown            Kubelet stopped posting node status.
  DiskPressure         Unknown   2024-01-15T10:25:00Z              NodeStatusUnknown            Kubelet stopped posting node status.
```

**Por que:** As condições do nó mostram `Unknown` com a mensagem "Kubelet stopped posting node status". Isso confirma que o problema é no kubelet (não em rede, disco ou memória). O `LastHeartbeatTime` mostra quando o último heartbeat foi recebido.

---

## Passo 3: Acessar o worker node via SSH

```bash
ssh ubuntu@<WORKER_NODE_IP>
```

**Saída esperada:**
```
Welcome to Ubuntu 22.04 LTS
ubuntu@k8s-worker-01:~$
```

**Por que:** Como o kubelet está parado, precisamos acessar o nó diretamente para diagnosticar e corrigir. O SSH é a forma padrão de acesso remoto a nós do cluster.

---

## Passo 4: Verificar o status do kubelet

```bash
systemctl status kubelet
```

**Saída esperada:**
```
● kubelet.service - Kubernetes Kubelet
     Loaded: loaded (/etc/systemd/system/kubelet.service; enabled; vendor preset: enabled)
     Active: inactive (dead) since Mon 2024-01-15 10:25:00 UTC; 5min ago
   Main PID: 1234 (code=exited, status=0/SUCCESS)
```

**Por que:** O status `inactive (dead)` confirma que o kubelet foi parado (não crashou — `status=0/SUCCESS` indica parada limpa). Se fosse um crash, veríamos `status=1/FAILURE` ou similar.

---

## Passo 5: Verificar logs do kubelet para confirmar a causa

```bash
journalctl -u kubelet --no-pager -n 20
```

**Saída esperada:**
```
Jan 15 10:25:00 k8s-worker-01 systemd[1]: Stopping Kubernetes Kubelet...
Jan 15 10:25:00 k8s-worker-01 systemd[1]: kubelet.service: Deactivated successfully.
Jan 15 10:25:00 k8s-worker-01 systemd[1]: Stopped Kubernetes Kubelet.
```

**Por que:** Os logs confirmam que o kubelet foi parado pelo systemd (não por erro de configuração ou crash). Não há mensagens de erro — apenas a sequência normal de parada. Isso indica que alguém executou `systemctl stop kubelet` manualmente.

---

## Passo 6: Reiniciar o kubelet

```bash
sudo systemctl start kubelet
```

**Por que:** Como o kubelet foi parado manualmente (sem erro de configuração), basta reiniciá-lo. Se houvesse um erro de configuração, precisaríamos corrigir antes de reiniciar.

---

## Passo 7: Verificar que o kubelet está ativo

```bash
systemctl is-active kubelet
```

**Saída esperada:**
```
active
```

```bash
systemctl status kubelet
```

**Saída esperada:**
```
● kubelet.service - Kubernetes Kubelet
     Loaded: loaded (/etc/systemd/system/kubelet.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-15 10:30:00 UTC; 5s ago
   Main PID: 5678
```

**Por que:** Confirmamos que o kubelet está rodando novamente. O status `active (running)` e um novo PID indicam que o processo foi iniciado com sucesso.

---

## Passo 8: Verificar que não há erros nos logs

```bash
journalctl -u kubelet --no-pager -n 10 --priority=err
```

**Saída esperada:**
```
(vazio — nenhuma linha de erro)
```

**Por que:** Verificamos que não há erros após o restart. Se houvesse problemas de certificado, conectividade ou configuração, veríamos mensagens de erro aqui.

---

## Passo 9: Voltar ao control plane e verificar o status do nó

```bash
# Sair do SSH do worker
exit

# Verificar o status do nó (pode levar 30-40 segundos)
kubectl get nodes
```

**Saída esperada:**
```
NAME                STATUS   ROLES           AGE   VERSION
k8s-control-plane   Ready    control-plane   10d   v1.29.0
k8s-worker-01       Ready    <none>          10d   v1.29.0
```

**Por que:** Após reiniciar o kubelet, ele envia um heartbeat ao API server. O node controller atualiza o status para `Ready` após receber o heartbeat. Isso pode levar até 40 segundos (intervalo padrão de node status update é 10s, mas o controller tem um período de graça).

---

## Passo 10: Verificar que os pods do sistema estão rodando no nó

```bash
kubectl get pods -n kube-system --field-selector spec.nodeName=k8s-worker-01
```

**Saída esperada:**
```
NAME                    READY   STATUS    RESTARTS   AGE
kube-proxy-abc12        1/1     Running   1          10d
```

**Por que:** Confirmamos que os pods de sistema (como kube-proxy) estão rodando no nó restaurado. O restart count pode ter incrementado se o pod foi afetado pela parada do kubelet.

---

## Resumo do Processo de Troubleshooting de Node

| Passo | Ação | Ferramenta |
|-------|------|-----------|
| 1 | Identificar nó com problema | `kubectl get nodes` |
| 2 | Ver condições detalhadas | `kubectl describe node` |
| 3 | Acessar o nó | SSH |
| 4 | Verificar kubelet | `systemctl status kubelet` |
| 5 | Analisar logs | `journalctl -u kubelet` |
| 6 | Corrigir (reiniciar/reconfigurar) | `systemctl start kubelet` |
| 7 | Confirmar recuperação | `kubectl get nodes` |

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| Node heartbeat | Kubelet envia status ao API server periodicamente (~10s) |
| NotReady | Node controller marca nó após ~40s sem heartbeat |
| `systemctl` | Gerenciador de serviços do Linux (start, stop, status, restart) |
| `journalctl` | Ferramenta para ler logs do systemd |
| Node conditions | Ready, MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable |
| `--priority=err` | Filtra logs por severidade (err = apenas erros) |
