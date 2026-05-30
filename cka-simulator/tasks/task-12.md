# Tarefa 12 — Configurar StorageClass e Provisionamento Dinâmico

**Domínio:** Storage
**Peso:** 5%
**Tempo recomendado:** 7 minutos

---

## Cenário

A equipe de plataforma deseja simplificar o provisionamento de volumes para os desenvolvedores. Em vez de criar PersistentVolumes manualmente, o cluster deve suportar **provisionamento dinâmico** através de uma StorageClass. Sua tarefa é criar uma StorageClass, um PVC que utilize essa StorageClass, e um Pod que monte o volume provisionado dinamicamente.

Além disso, você deve demonstrar que entende como configurar diferentes políticas de retenção e modos de montagem de volumes em Pods.

---

## Requisitos

1. Crie o namespace `dynamic-storage` (se não existir).

2. Crie uma **StorageClass** com as seguintes especificações:
   - Nome: `sc-rapida`
   - Provisioner: `kubernetes.io/no-provisioner`
   - Volume Binding Mode: `WaitForFirstConsumer`
   - Reclaim Policy: `Delete`

3. Crie um **PersistentVolume** para ser utilizado com a StorageClass:
   - Nome: `pv-dinamico`
   - Capacidade: `2Gi`
   - Modo de acesso: `ReadWriteOnce`
   - Tipo: `hostPath`
   - Caminho no host: `/mnt/dinamico`
   - StorageClassName: `sc-rapida`
   - Node Affinity: configure para o nó worker do cluster (use o nome real do nó)

4. Crie um **PersistentVolumeClaim** com as seguintes especificações:
   - Nome: `pvc-app`
   - Namespace: `dynamic-storage`
   - Modo de acesso: `ReadWriteOnce`
   - Capacidade solicitada: `1Gi`
   - StorageClassName: `sc-rapida`

5. Crie um **Pod** com as seguintes especificações:
   - Nome: `pod-app`
   - Namespace: `dynamic-storage`
   - Imagem: `nginx:alpine`
   - Monte o PVC `pvc-app` no caminho `/usr/share/nginx/html`
   - O volume deve ser montado como **somente leitura** (`readOnly: true`) no container

6. Crie um segundo **Pod** no mesmo namespace:
   - Nome: `pod-writer`
   - Namespace: `dynamic-storage`
   - Imagem: `busybox`
   - Comando: `["sh", "-c", "echo '<h1>Kubernetes Storage</h1>' > /dados/index.html && sleep 3600"]`
   - Monte o **mesmo PVC** `pvc-app` no caminho `/dados` com permissão de **leitura e escrita**

7. Verifique que:
   - A StorageClass foi criada corretamente
   - O PV e PVC estão no estado `Bound`
   - Ambos os Pods estão `Running`
   - O conteúdo escrito pelo `pod-writer` é acessível pelo `pod-app`

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace existe
kubectl get namespace dynamic-storage
# Esperado: dynamic-storage   Active   <age>

# 2. Verificar a StorageClass
kubectl get storageclass sc-rapida
# Esperado: sc-rapida   kubernetes.io/no-provisioner   Delete   WaitForFirstConsumer   false   <age>

# 3. Verificar que o PV existe com a StorageClass correta
kubectl get pv pv-dinamico
# Esperado: pv-dinamico   2Gi   RWO   Delete   Bound   dynamic-storage/pvc-app   sc-rapida   <age>

# 4. Verificar que o PVC está Bound
kubectl get pvc pvc-app -n dynamic-storage
# Esperado: pvc-app   Bound   pv-dinamico   2Gi   RWO   sc-rapida   <age>

# 5. Verificar que ambos os Pods estão Running
kubectl get pods -n dynamic-storage
# Esperado:
# pod-app      1/1   Running   0   <age>
# pod-writer   1/1   Running   0   <age>

# 6. Verificar que o pod-app monta o volume como readOnly
kubectl describe pod pod-app -n dynamic-storage | grep -A 2 "Mounts:"
# Esperado: /usr/share/nginx/html from volume-app (ro)

# 7. Verificar que o conteúdo escrito pelo pod-writer é acessível
kubectl exec pod-app -n dynamic-storage -- cat /usr/share/nginx/html/index.html
# Esperado: <h1>Kubernetes Storage</h1>

# 8. Verificar o Volume Binding Mode da StorageClass
kubectl describe storageclass sc-rapida | grep VolumeBindingMode
# Esperado: VolumeBindingMode: WaitForFirstConsumer
```

---

## Dicas

- Use `kubectl explain storageclass` para consultar os campos disponíveis.
- O provisioner `kubernetes.io/no-provisioner` indica que o provisionamento é manual (o PV deve existir previamente), mas o binding é controlado pela StorageClass.
- `WaitForFirstConsumer` atrasa o binding do PV até que um Pod que use o PVC seja agendado — isso garante que o PV esteja no mesmo nó que o Pod.
- Para montar um volume como somente leitura, use `readOnly: true` na seção `volumeMounts` do container.
- Dois Pods podem compartilhar o mesmo PVC se o modo de acesso permitir (neste caso, ambos estão no mesmo nó com `ReadWriteOnce`).
