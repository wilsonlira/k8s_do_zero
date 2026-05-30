# Solução — Tarefa 01: Backup e Restore do etcd

**Domínio:** Cluster Architecture, Installation & Configuration
**Tempo estimado:** 10 minutos

---

## Passo 1: Criar o diretório de backup

```bash
sudo mkdir -p /opt/etcd-backup
```

**Por que:** O diretório de destino precisa existir antes de salvar o snapshot. Usamos `sudo` pois `/opt` geralmente requer permissões de root.

---

## Passo 2: Criar o snapshot (backup) do etcd

```bash
ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-backup/snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem
```

**Saída esperada:**
```
Snapshot saved at /opt/etcd-backup/snapshot-20240115.db
```

**Por que:** O comando `snapshot save` cria uma cópia consistente de todos os dados do etcd. As flags TLS são obrigatórias porque o etcd está configurado com mTLS (mutual TLS) — sem elas, a conexão é recusada. A variável `ETCDCTL_API=3` garante que estamos usando a API v3 do etcdctl.

---

## Passo 3: Verificar a integridade do snapshot

```bash
ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup/snapshot-$(date +%Y%m%d).db --write-out=table
```

**Saída esperada:**
```
+----------+----------+------------+------------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+----------+----------+------------+------------+
| 3e4fca8d |    15847 |       1024 |     2.1 MB |
+----------+----------+------------+------------+
```

**Por que:** A verificação de integridade confirma que o snapshot não está corrompido. O hash é calculado sobre os dados e qualquer corrupção resultaria em erro. Sem essa verificação, você poderia ter um backup inutilizável.

---

## Passo 4: Restaurar o snapshot para um novo diretório

```bash
ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-backup/snapshot-$(date +%Y%m%d).db \
  --data-dir=/var/lib/etcd-restored
```

**Saída esperada:**
```
2024-01-15 10:30:00.123456 I | mvcc: restore compact to 15847
2024-01-15 10:30:00.135789 I | etcdserver/membership: added member ...
```

**Por que:** O `snapshot restore` recria a estrutura de dados do etcd (diretórios `member/snap` e `member/wal`) a partir do snapshot. Usamos um diretório diferente (`/var/lib/etcd-restored`) para não sobrescrever os dados atuais até confirmarmos que o restore está correto.

---

## Passo 5: Atualizar a configuração do etcd para usar o novo diretório

```bash
sudo sed -i 's|--data-dir=/var/lib/etcd|--data-dir=/var/lib/etcd-restored|' /etc/systemd/system/etcd.service
```

**Por que:** O etcd precisa ser apontado para o novo diretório de dados restaurado. O arquivo de unit do systemd contém a flag `--data-dir` que define onde o etcd lê/escreve seus dados. Alterando esse valor, o etcd usará os dados restaurados no próximo início.

---

## Passo 6: Recarregar a configuração do systemd e reiniciar o etcd

```bash
sudo systemctl daemon-reload
sudo systemctl restart etcd
```

**Por que:** O `daemon-reload` é necessário sempre que um arquivo de unit do systemd é modificado — sem ele, o systemd usa a versão em cache. O `restart` para e inicia o etcd com a nova configuração, carregando os dados do diretório restaurado.

---

## Passo 7: Verificar a saúde do etcd após o restore

```bash
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem
```

**Saída esperada:**
```
https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 2.345ms
```

**Por que:** Este comando confirma que o etcd está aceitando conexões e processando operações de escrita (o "committed proposal" indica que o Raft consensus está funcionando). Se o restore tivesse falhado, veríamos um erro de conexão ou timeout.

---

## Passo 8: Verificar que o cluster Kubernetes está funcional

```bash
kubectl get nodes
```

**Saída esperada:**
```
NAME                STATUS   ROLES           AGE   VERSION
k8s-control-plane   Ready    control-plane   10d   v1.29.0
k8s-worker-01       Ready    <none>          10d   v1.29.0
```

**Por que:** O kube-apiserver depende do etcd para ler o estado do cluster. Se `kubectl get nodes` retorna os nós com status Ready, significa que toda a cadeia está funcionando: kubectl → apiserver → etcd (restaurado).

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| `ETCDCTL_API=3` | Define a versão da API do etcdctl (v3 é obrigatória para snapshots) |
| Flags TLS | Autenticação mútua entre cliente (etcdctl) e servidor (etcd) |
| `snapshot save` | Cria backup atômico e consistente dos dados |
| `snapshot restore` | Recria estrutura de dados a partir do backup |
| `--data-dir` | Define o diretório onde o etcd armazena seus dados persistentes |
| `daemon-reload` | Atualiza o systemd após modificar arquivos de unit |
