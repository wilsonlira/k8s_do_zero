# Tarefa 07 — Node Affinity, Taints e Tolerations

**Domínio:** Workloads & Scheduling
**Peso:** 5%
**Tempo recomendado:** 8 minutos

---

## Cenário

O cluster possui nós com diferentes capacidades. A equipe de infraestrutura precisa garantir que determinados workloads sejam agendados apenas em nós específicos. Você deve usar **Node Affinity** para direcionar pods a nós com labels específicas, e **Taints/Tolerations** para restringir quais pods podem ser agendados em nós dedicados.

---

## Requisitos

1. Adicione a label `workload=critical` ao nó worker do cluster (use `kubectl get nodes` para identificar o nó worker).

2. Aplique um **taint** no nó worker:
   - Key: `dedicated`
   - Value: `critical-apps`
   - Effect: `NoSchedule`

3. Crie o namespace `scheduling-demo` (caso não exista).

4. Crie um Deployment chamado `critical-app` no namespace `scheduling-demo` com as seguintes especificações:
   - Imagem: `nginx:1.25`
   - Réplicas: 2
   - Labels no pod: `app=critical-app`
   - **Node Affinity** (requiredDuringSchedulingIgnoredDuringExecution): o pod DEVE ser agendado em nós com a label `workload=critical`
   - **Toleration**: tolerar o taint `dedicated=critical-apps:NoSchedule`

5. Crie um segundo Deployment chamado `regular-app` no namespace `scheduling-demo` com:
   - Imagem: `busybox:1.36`
   - Réplicas: 1
   - Comando: `sh -c "sleep 3600"`
   - Labels no pod: `app=regular-app`
   - **Sem** toleration para o taint `dedicated`
   - **Sem** node affinity

6. Verifique que:
   - Os pods de `critical-app` estão **Running** no nó com a label `workload=critical`
   - O pod de `regular-app` está em **Pending** (pois não tolera o taint do nó worker) — OU — se houver outros nós sem taint, pode estar Running em outro nó

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar a label no nó worker
kubectl get nodes --show-labels | grep "workload=critical"
# Esperado: o nó worker aparece com a label workload=critical

# 2. Verificar o taint no nó worker
kubectl describe node <WORKER_NODE_NAME> | grep -A 3 "Taints"
# Esperado: dedicated=critical-apps:NoSchedule

# 3. Verificar que o namespace scheduling-demo existe
kubectl get namespace scheduling-demo
# Esperado: STATUS = Active

# 4. Verificar que critical-app está Running com 2 réplicas
kubectl get deployment critical-app -n scheduling-demo
# Esperado: READY = 2/2

# 5. Verificar que os pods de critical-app estão no nó correto
kubectl get pods -n scheduling-demo -l app=critical-app -o wide
# Esperado: todos os pods no nó com label workload=critical

# 6. Verificar a node affinity do Deployment critical-app
kubectl get deployment critical-app -n scheduling-demo -o jsonpath='{.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key}'
# Esperado: workload

# 7. Verificar a toleration do Deployment critical-app
kubectl get deployment critical-app -n scheduling-demo -o jsonpath='{.spec.template.spec.tolerations[*].key}'
# Esperado: dedicated (entre as tolerations listadas)

# 8. Verificar o status do regular-app
kubectl get pods -n scheduling-demo -l app=regular-app
# Esperado: Pending (se o único nó worker tem taint) OU Running em outro nó sem taint
```


---

## Critérios de Aprovação

- ✅ Label `workload=critical` aplicada ao nó worker
- ✅ Taint `dedicated=critical-apps:NoSchedule` aplicado ao nó worker
- ✅ Namespace `scheduling-demo` criado
- ✅ Deployment `critical-app` com node affinity e toleration corretos
- ✅ Pods de `critical-app` rodando no nó com label `workload=critical`
- ✅ Deployment `regular-app` sem toleration (pod Pending ou em outro nó)
