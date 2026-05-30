# Solução — Tarefa 11: Criar PersistentVolume e PersistentVolumeClaim

**Domínio:** Storage
**Tempo estimado:** 8 minutos

---

## Passo 1: Criar o namespace storage-lab

```bash
kubectl create namespace storage-lab
```

**Saída esperada:**
```
namespace/storage-lab created
```

---

## Passo 2: Criar o PersistentVolume

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-dados
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/dados
    type: DirectoryOrCreate
EOF
```

**Saída esperada:**
```
persistentvolume/pv-dados created
```

**Por que:** O PersistentVolume (PV) representa um pedaço de armazenamento no cluster. Detalhes:
- **`capacity: 1Gi`** — tamanho total disponível
- **`ReadWriteOnce`** — pode ser montado por um único nó em modo leitura/escrita
- **`Retain`** — quando o PVC é deletado, os dados no PV são preservados (não são apagados automaticamente). Isso é importante para dados de banco de dados
- **`storageClassName: manual`** — agrupa PVs e PVCs. O binding só ocorre entre PV e PVC com a mesma storageClassName
- **`hostPath`** — usa um diretório no nó host (adequado para labs, não para produção)
- **`DirectoryOrCreate`** — cria o diretório se não existir

**Nota:** PVs são recursos de cluster (sem namespace).

---

## Passo 3: Criar o PersistentVolumeClaim

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-dados
  namespace: storage-lab
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
  storageClassName: manual
EOF
```

**Saída esperada:**
```
persistentvolumeclaim/pvc-dados created
```

**Por que:** O PVC é uma "requisição" de armazenamento feita por um usuário/aplicação. O Kubernetes automaticamente faz o binding entre PVC e PV quando:
1. A `storageClassName` é igual (`manual`)
2. O `accessMode` é compatível (`ReadWriteOnce`)
3. A capacidade do PV é >= a solicitada pelo PVC (1Gi >= 500Mi)

O PVC solicita 500Mi mas o PV tem 1Gi — o binding ocorre e o PVC recebe acesso ao PV inteiro.

---

## Passo 4: Verificar o binding PV ↔ PVC

```bash
kubectl get pv pv-dados
```

**Saída esperada:**
```
NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   AGE
pv-dados   1Gi        RWO            Retain           Bound    storage-lab/pvc-dados   manual         30s
```

```bash
kubectl get pvc pvc-dados -n storage-lab
```

**Saída esperada:**
```
NAME        STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-dados   Bound    pv-dados   1Gi        RWO            manual         30s
```

**Por que:** O status `Bound` confirma que o PVC foi vinculado ao PV. A coluna CLAIM no PV mostra `storage-lab/pvc-dados`, confirmando a associação bidirecional.

---

## Passo 5: Criar o Pod que usa o PVC

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-banco
  namespace: storage-lab
spec:
  containers:
  - name: banco
    image: busybox
    command: ["sh", "-c", "echo 'dados persistentes' > /dados/teste.txt && sleep 3600"]
    volumeMounts:
    - name: volume-dados
      mountPath: /dados
  volumes:
  - name: volume-dados
    persistentVolumeClaim:
      claimName: pvc-dados
EOF
```

**Saída esperada:**
```
pod/pod-banco created
```

**Por que:** O Pod referencia o PVC pelo nome (`claimName: pvc-dados`). O Kubernetes monta o volume no caminho `/dados` dentro do container. O comando escreve um arquivo de teste para verificar que a persistência funciona.

Fluxo: Pod → PVC (`pvc-dados`) → PV (`pv-dados`) → hostPath (`/mnt/dados`)

---

## Passo 6: Verificar que o Pod está Running

```bash
kubectl get pod pod-banco -n storage-lab
```

**Saída esperada:**
```
NAME        READY   STATUS    RESTARTS   AGE
pod-banco   1/1     Running   0          30s
```

---

## Passo 7: Verificar o conteúdo do arquivo no volume

```bash
kubectl exec pod-banco -n storage-lab -- cat /dados/teste.txt
```

**Saída esperada:**
```
dados persistentes
```

**Por que:** Confirmamos que o container conseguiu escrever no volume montado. Se o pod for deletado e recriado com o mesmo PVC, os dados persistem — essa é a essência do armazenamento persistente.

---

## Passo 8: Verificar a montagem do volume

```bash
kubectl describe pod pod-banco -n storage-lab | grep -A 5 "Volumes:"
```

**Saída esperada:**
```
Volumes:
  volume-dados:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  pvc-dados
    ReadOnly:   false
```

**Por que:** O `describe` confirma que o volume está montado corretamente e que o PVC está sendo usado como fonte de dados.

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| PersistentVolume (PV) | Recurso de cluster que representa armazenamento físico |
| PersistentVolumeClaim (PVC) | Requisição de armazenamento feita por um pod/usuário |
| Binding | Associação automática entre PVC e PV compatível |
| storageClassName | Agrupa PVs e PVCs — binding só ocorre com mesma classe |
| Retain | Dados preservados após deleção do PVC (requer limpeza manual) |
| Delete | Dados apagados automaticamente quando PVC é deletado |
| Recycle | (Deprecated) Limpa dados e disponibiliza PV novamente |
| hostPath | Armazenamento local no nó — não recomendado para produção |
