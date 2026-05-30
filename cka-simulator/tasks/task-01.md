# Tarefa 01 — Backup e Restore do etcd

**Domínio:** Cluster Architecture, Installation & Configuration
**Peso:** 6.25%
**Tempo recomendado:** 10 minutos

---

## Cenário

Você é o administrador de um cluster Kubernetes em produção. A equipe de operações solicitou que você realize um backup do etcd antes de uma janela de manutenção programada. Além disso, você deve demonstrar que é capaz de restaurar o cluster a partir de um snapshot caso algo dê errado durante a manutenção.

O etcd está rodando no nó control plane com os seguintes parâmetros:
- **Endpoint:** https://127.0.0.1:2379
- **Certificado CA:** /etc/etcd/ca.pem
- **Certificado cliente:** /etc/etcd/etcd.pem
- **Chave cliente:** /etc/etcd/etcd-key.pem
- **Diretório de dados:** /var/lib/etcd

---

## Requisitos

1. Crie um snapshot (backup) do etcd e salve-o em `/opt/etcd-backup/snapshot-$(date +%Y%m%d).db`
2. Verifique a integridade do snapshot criado usando `etcdctl snapshot status`
3. Restaure o snapshot para um novo diretório de dados em `/var/lib/etcd-restored`
4. Atualize a configuração do etcd para usar o novo diretório de dados restaurado
5. Reinicie o serviço etcd e verifique que o cluster está saudável

> **Importante:** Todos os comandos devem ser executados no nó control plane. Use as flags de TLS apropriadas em todos os comandos `etcdctl`.

---

## Comandos de Verificação

Execute os seguintes comandos para validar se a tarefa foi concluída corretamente:

```bash
# 1. Verificar que o arquivo de snapshot existe
ls -la /opt/etcd-backup/snapshot-*.db
# Esperado: arquivo .db com tamanho > 0

# 2. Verificar integridade do snapshot
ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup/snapshot-*.db --write-out=table
# Esperado: tabela com hash, revision, total keys, total size (sem erros)

# 3. Verificar que o diretório restaurado existe
ls -la /var/lib/etcd-restored/member/
# Esperado: diretórios snap/ e wal/ presentes

# 4. Verificar saúde do etcd após restore
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem
# Esperado: "127.0.0.1:2379 is healthy"

# 5. Verificar que o API server está respondendo
kubectl get nodes
# Esperado: nós listados com status Ready
```

---

## Critérios de Aprovação

- ✅ Snapshot criado com sucesso em `/opt/etcd-backup/`
- ✅ Snapshot verificado sem erros de integridade
- ✅ Restore executado para `/var/lib/etcd-restored`
- ✅ Serviço etcd reiniciado e saudável
- ✅ Cluster Kubernetes funcional após o restore
