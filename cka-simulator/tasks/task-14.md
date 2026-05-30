# Tarefa 14 — Troubleshooting de Node NotReady

**Domínio:** Troubleshooting
**Peso:** 6%
**Tempo recomendado:** 7 minutos

---

## Cenário

O monitoramento alertou que um worker node do cluster está reportando status **NotReady**. Ao investigar, você descobre que o serviço `kubelet` no worker node parou de funcionar. Sua tarefa é diagnosticar o problema no node e restaurá-lo ao estado Ready.

Neste cenário, o kubelet foi parado manualmente para simular uma falha:

```bash
# Comando executado no worker node para simular a falha:
sudo systemctl stop kubelet
```

---

## Requisitos

1. Identifique qual(is) node(s) estão em estado NotReady usando `kubectl get nodes`.

2. Acesse o worker node via SSH e verifique o status do serviço kubelet com `systemctl`.

3. Inspecione os logs do kubelet para identificar a causa da falha usando `journalctl`.

4. Reinicie o serviço kubelet:
   ```bash
   sudo systemctl start kubelet
   ```

5. Verifique que o serviço kubelet está ativo e sem erros.

6. Confirme que o node voltou ao estado **Ready** no cluster (pode levar até 40 segundos).

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que todos os nodes estão Ready
kubectl get nodes
# Esperado: todos os nodes com STATUS = Ready

# 2. Verificar status do kubelet no worker node (executar via SSH no worker)
systemctl is-active kubelet
# Esperado: active

# 3. Verificar que o kubelet não tem erros recentes
journalctl -u kubelet --no-pager -n 5 --priority=err
# Esperado: nenhuma linha de erro recente (ou vazio)

# 4. Verificar condição Ready do node
kubectl get node <worker-node-name> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Esperado: True

# 5. Verificar que pods do sistema estão rodando no node
kubectl get pods -n kube-system --field-selector spec.nodeName=<worker-node-name>
# Esperado: pods kube-proxy (e outros) em estado Running
```

---

## Dicas

- Use `kubectl get nodes` para identificar rapidamente nodes com problemas.
- Use `kubectl describe node <node-name>` para ver condições detalhadas e eventos.
- No worker node, `systemctl status kubelet` mostra o estado atual e últimas linhas de log.
- Use `journalctl -u kubelet --no-pager -n 50` para ver logs recentes do kubelet.
- Após reiniciar o kubelet, o node pode levar 30-40 segundos para reportar Ready.
