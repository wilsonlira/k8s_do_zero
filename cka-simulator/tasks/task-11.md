# Tarefa 11 — Criar PersistentVolume e PersistentVolumeClaim

**Domínio:** Storage
**Peso:** 5%
**Tempo recomendado:** 8 minutos

---

## Cenário

A equipe de desenvolvimento precisa de armazenamento persistente para uma aplicação de banco de dados que será implantada no cluster. O administrador do cluster deve provisionar um PersistentVolume (PV) utilizando armazenamento local no nó worker e criar um PersistentVolumeClaim (PVC) que será utilizado por um Pod para montar o volume.

O namespace `storage-lab` já deve ser criado para esta tarefa.

---

## Requisitos

1. Crie o namespace `storage-lab` (se não existir).

2. Crie um **PersistentVolume** com as seguintes especificações:
   - Nome: `pv-dados`
   - Capacidade: `1Gi`
   - Modo de acesso: `ReadWriteOnce`
   - Tipo: `hostPath`
   - Caminho no host: `/mnt/dados`
   - StorageClassName: `manual`
   - Política de retenção (persistentVolumeReclaimPolicy): `Retain`

3. Crie um **PersistentVolumeClaim** com as seguintes especificações:
   - Nome: `pvc-dados`
   - Namespace: `storage-lab`
   - Modo de acesso: `ReadWriteOnce`
   - Capacidade solicitada: `500Mi`
   - StorageClassName: `manual`

4. Crie um **Pod** com as seguintes especificações:
   - Nome: `pod-banco`
   - Namespace: `storage-lab`
   - Imagem: `busybox`
   - Comando: `["sh", "-c", "echo 'dados persistentes' > /dados/teste.txt && sleep 3600"]`
   - Monte o PVC `pvc-dados` no caminho `/dados` dentro do container

5. Verifique que:
   - O PV está no estado `Bound`
   - O PVC está no estado `Bound` e vinculado ao PV `pv-dados`
   - O Pod está no estado `Running`
   - O arquivo `/dados/teste.txt` existe dentro do container com o conteúdo correto

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace existe
kubectl get namespace storage-lab
# Esperado: storage-lab   Active   <age>

# 2. Verificar que o PV existe e está Bound
kubectl get pv pv-dados
# Esperado: pv-dados   1Gi   RWO   Retain   Bound   storage-lab/pvc-dados   manual   <age>

# 3. Verificar que o PVC existe e está Bound
kubectl get pvc pvc-dados -n storage-lab
# Esperado: pvc-dados   Bound   pv-dados   1Gi   RWO   manual   <age>

# 4. Verificar que o Pod está Running
kubectl get pod pod-banco -n storage-lab
# Esperado: pod-banco   1/1   Running   0   <age>

# 5. Verificar o conteúdo do arquivo no volume
kubectl exec pod-banco -n storage-lab -- cat /dados/teste.txt
# Esperado: dados persistentes

# 6. Verificar que o volume está montado corretamente
kubectl describe pod pod-banco -n storage-lab | grep -A 2 "Mounts:"
# Esperado: /dados from volume-dados (rw)
```

---

## Dicas

- Use `kubectl explain persistentvolume.spec` para consultar os campos disponíveis.
- Use `kubectl explain persistentvolumeclaim.spec` para consultar os campos do PVC.
- Lembre-se que PersistentVolumes são recursos de cluster (não pertencem a um namespace), mas PersistentVolumeClaims são recursos com namespace.
- O `storageClassName` deve ser idêntico no PV e no PVC para que o binding ocorra.
