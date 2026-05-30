# Solução — Tarefa 12: Configurar StorageClass e Provisionamento Dinâmico

**Domínio:** Storage
**Tempo estimado:** 7 minutos

---

## Passo 1: Criar o namespace dynamic-storage

```bash
kubectl create namespace dynamic-storage
```

**Saída esperada:**
```
namespace/dynamic-storage created
```

---

## Passo 2: Criar a StorageClass

```bash
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: sc-rapida
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
```

**Saída esperada:**
```
storageclass.storage.k8s.io/sc-rapida created
```

**Por que:** A StorageClass define **como** volumes são provisionados:
- **`provisioner: kubernetes.io/no-provisioner`** — indica provisionamento manual (o admin cria os PVs). Em cloud, usaríamos `kubernetes.io/aws-ebs` ou `ebs.csi.aws.com`
- **`volumeBindingMode: WaitForFirstConsumer`** — atrasa o binding do PV até que um Pod que use o PVC seja agendado. Isso garante que o PV esteja no mesmo nó que o Pod (importante para hostPath e armazenamento local)
- **`reclaimPolicy: Delete`** — quando o PVC é deletado, o PV também é removido

---

## Passo 3: Identificar o nó worker

```bash
WORKER_NODE=$(kubectl get nodes --no-headers | grep -v control-plane | awk '{print $1}')
echo "Worker node: $WORKER_NODE"
```

**Saída esperada:**
```
Worker node: k8s-worker-01
```

**Por que:** Precisamos do nome exato do nó para configurar a Node Affinity no PV, garantindo que o volume hostPath esteja no mesmo nó onde os pods serão agendados.

---

## Passo 4: Criar o PersistentVolume com Node Affinity

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-dinamico
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: sc-rapida
  hostPath:
    path: /mnt/dinamico
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - k8s-worker-01
EOF
```

**Saída esperada:**
```
persistentvolume/pv-dinamico created
```

**Por que:** A Node Affinity no PV garante que ele só pode ser usado por pods agendados no nó `k8s-worker-01`. Isso é obrigatório para armazenamento local — o diretório `/mnt/dinamico` só existe nesse nó específico. Combinado com `WaitForFirstConsumer`, o scheduler sabe que o pod deve ir para esse nó.

---

## Passo 5: Criar o PersistentVolumeClaim

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-app
  namespace: dynamic-storage
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: sc-rapida
EOF
```

**Saída esperada:**
```
persistentvolumeclaim/pvc-app created
```

**Por que:** O PVC solicita 1Gi com a StorageClass `sc-rapida`. Como o `volumeBindingMode` é `WaitForFirstConsumer`, o PVC ficará em estado `Pending` até que um Pod que o use seja criado e agendado.

---

## Passo 6: Criar o Pod pod-writer (leitura e escrita)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-writer
  namespace: dynamic-storage
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo '<h1>Kubernetes Storage</h1>' > /dados/index.html && sleep 3600"]
    volumeMounts:
    - name: volume-app
      mountPath: /dados
  volumes:
  - name: volume-app
    persistentVolumeClaim:
      claimName: pvc-app
EOF
```

**Saída esperada:**
```
pod/pod-writer created
```

**Por que:** O pod-writer monta o PVC com permissão de leitura e escrita (padrão) e escreve um arquivo HTML. Este pod dispara o binding do PVC (pois é o "first consumer"), fazendo o PV ser vinculado.

---

## Passo 7: Criar o Pod pod-app (somente leitura)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-app
  namespace: dynamic-storage
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    volumeMounts:
    - name: volume-app
      mountPath: /usr/share/nginx/html
      readOnly: true
  volumes:
  - name: volume-app
    persistentVolumeClaim:
      claimName: pvc-app
EOF
```

**Saída esperada:**
```
pod/pod-app created
```

**Por que:** O pod-app monta o **mesmo PVC** mas com `readOnly: true`. Isso significa que o nginx pode servir os arquivos escritos pelo pod-writer, mas não pode modificá-los. Dois pods podem compartilhar o mesmo PVC com `ReadWriteOnce` desde que estejam no mesmo nó.

---

## Passo 8: Verificar o estado dos recursos

```bash
# Verificar StorageClass
kubectl get storageclass sc-rapida
```

**Saída esperada:**
```
NAME        PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
sc-rapida   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer   false                  1m
```

```bash
# Verificar PV e PVC
kubectl get pv pv-dinamico
kubectl get pvc pvc-app -n dynamic-storage
```

**Saída esperada:**
```
NAME          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                      STORAGECLASS   AGE
pv-dinamico   2Gi        RWO            Delete           Bound    dynamic-storage/pvc-app    sc-rapida      1m

NAME      STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-app   Bound    pv-dinamico   2Gi        RWO            sc-rapida      1m
```

```bash
# Verificar Pods
kubectl get pods -n dynamic-storage
```

**Saída esperada:**
```
NAME         READY   STATUS    RESTARTS   AGE
pod-app      1/1     Running   0          30s
pod-writer   1/1     Running   0          45s
```

---

## Passo 9: Verificar que o conteúdo é compartilhado

```bash
kubectl exec pod-app -n dynamic-storage -- cat /usr/share/nginx/html/index.html
```

**Saída esperada:**
```
<h1>Kubernetes Storage</h1>
```

**Por que:** O arquivo escrito pelo `pod-writer` em `/dados/index.html` é visível pelo `pod-app` em `/usr/share/nginx/html/index.html` — ambos apontam para o mesmo volume físico (`/mnt/dinamico` no nó). Isso demonstra compartilhamento de dados entre pods via PVC.

---

## Passo 10: Verificar montagem readOnly

```bash
kubectl describe pod pod-app -n dynamic-storage | grep -A 2 "Mounts:"
```

**Saída esperada:**
```
    Mounts:
      /usr/share/nginx/html from volume-app (ro)
```

**Por que:** O `(ro)` confirma que o volume está montado como somente leitura no pod-app. Se tentássemos escrever, receberíamos um erro "Read-only file system".

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| StorageClass | Define como volumes são provisionados e suas propriedades |
| WaitForFirstConsumer | Atrasa binding até um Pod ser agendado (garante localidade) |
| Immediate | Binding ocorre assim que o PVC é criado |
| Node Affinity no PV | Restringe em quais nós o PV pode ser usado |
| readOnly mount | Container pode ler mas não escrever no volume |
| Compartilhamento de PVC | Múltiplos pods no mesmo nó podem usar o mesmo PVC (RWO) |
| no-provisioner | Provisionamento manual — admin cria PVs explicitamente |
