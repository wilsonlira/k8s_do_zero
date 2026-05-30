# Tarefa 16 — Troubleshooting de Componente do Control Plane (kube-scheduler)

**Domínio:** Troubleshooting
**Peso:** 6%
**Tempo recomendado:** 7 minutos

---

## Cenário

Após uma manutenção no control plane node, o cluster está apresentando comportamento anormal: novos pods não estão sendo agendados em nenhum node. Pods existentes continuam rodando, mas qualquer novo Deployment ou Pod fica em estado **Pending** indefinidamente.

Ao investigar, você descobre que o serviço `kube-scheduler` foi parado durante a manutenção e não foi reiniciado:

```bash
# Comando que foi executado durante a manutenção (simulação):
sudo systemctl stop kube-scheduler
```

---

## Requisitos

1. Verifique o status de saúde dos componentes do control plane:
   - kube-apiserver (porta 6443)
   - kube-controller-manager (porta 10257)
   - kube-scheduler (porta 10259)
   - etcd (porta 2379)

2. Identifique que o `kube-scheduler` não está funcionando verificando:
   - O endpoint de health retorna erro
   - O serviço systemd está inativo

3. Inspecione os logs do kube-scheduler para confirmar que foi parado (não há erro de configuração).

4. Reinicie o serviço do kube-scheduler:
   ```bash
   sudo systemctl start kube-scheduler
   ```

5. Verifique que o scheduler está saudável consultando seu endpoint de health.

6. Confirme que novos pods estão sendo agendados corretamente criando um pod de teste.

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar health do kube-scheduler (executar no control plane node)
curl -sk https://localhost:10259/healthz
# Esperado: ok

# 2. Verificar que o serviço kube-scheduler está ativo
systemctl is-active kube-scheduler
# Esperado: active

# 3. Verificar que não há erros recentes no scheduler
journalctl -u kube-scheduler --no-pager -n 5 --priority=err
# Esperado: nenhuma linha de erro (ou vazio)

# 4. Criar pod de teste e verificar que é agendado
kubectl run scheduler-test --image=nginx:1.25 --restart=Never
kubectl wait --for=condition=Ready pod/scheduler-test --timeout=30s
# Esperado: pod/scheduler-test condition met

# 5. Verificar que o pod de teste está Running em um node
kubectl get pod scheduler-test -o jsonpath='{.spec.nodeName}'
# Esperado: nome de um worker node (não vazio)

# 6. Limpar pod de teste
kubectl delete pod scheduler-test --grace-period=0 --force
```

---

## Dicas

- Use `curl -sk https://localhost:<porta>/healthz` para verificar health de cada componente.
- Portas padrão: apiserver=6443, controller-manager=10257, scheduler=10259, etcd=2379.
- Um pod em Pending com evento "0/X nodes are available" pode indicar scheduler inativo.
- Use `kubectl describe pod <pod-name>` para ver eventos — se não houver evento de scheduling, o scheduler não está processando.
- Use `systemctl status kube-scheduler` para ver estado e últimas linhas de log.
