# Tarefa 03 — Upgrade de Componentes do Cluster

**Domínio:** Cluster Architecture, Installation & Configuration
**Peso:** 6.25%
**Tempo recomendado:** 8 minutos

---

## Cenário

Sua equipe decidiu atualizar o cluster Kubernetes da versão 1.29.0 para a versão 1.29.1 (patch upgrade). Você deve realizar o upgrade do nó control plane seguindo as melhores práticas: primeiro drenar o nó, atualizar os componentes, e depois retornar o nó ao serviço.

O cluster possui:
- **1 nó control plane:** k8s-control-plane
- **1 nó worker:** k8s-worker-01
- **Versão atual:** 1.29.0
- **Versão alvo:** 1.29.1
- **Binários disponíveis em:** /opt/kubernetes/v1.29.1/

---

## Requisitos

1. Verifique a versão atual de todos os componentes do control plane (kube-apiserver, kube-controller-manager, kube-scheduler)
2. Faça o drain do nó control plane para evitar scheduling de novos pods durante o upgrade
3. Atualize os binários do kube-apiserver, kube-controller-manager e kube-scheduler para a versão 1.29.1:
   - Copie os novos binários de `/opt/kubernetes/v1.29.1/` para `/usr/local/bin/`
4. Reinicie os serviços atualizados (kube-apiserver, kube-controller-manager, kube-scheduler)
5. Faça o uncordon do nó control plane para permitir scheduling novamente
6. Verifique que todos os componentes estão rodando na nova versão

> **Importante:** O upgrade deve ser feito componente a componente no control plane. Não atualize o worker node nesta tarefa.

---

## Comandos de Verificação

Execute os seguintes comandos para validar se a tarefa foi concluída corretamente:

```bash
# 1. Verificar versão do kube-apiserver
kube-apiserver --version
# Esperado: "Kubernetes v1.29.1"

# 2. Verificar versão do kube-controller-manager
kube-controller-manager --version
# Esperado: "Kubernetes v1.29.1"

# 3. Verificar versão do kube-scheduler
kube-scheduler --version
# Esperado: "Kubernetes v1.29.1"

# 4. Verificar que o nó control plane está com status Ready e SchedulingEnabled
kubectl get nodes
# Esperado: k8s-control-plane com status "Ready" (sem SchedulingDisabled)

# 5. Verificar saúde dos componentes
kubectl get componentstatuses
# Esperado: scheduler, controller-manager, etcd-0 todos com status "Healthy"

# 6. Verificar que o API server está respondendo na nova versão
kubectl version --short
# Esperado: Server Version: v1.29.1
```

---

## Critérios de Aprovação

- ✅ Versão anterior verificada antes do upgrade
- ✅ Nó control plane drenado corretamente
- ✅ Binários atualizados para v1.29.1
- ✅ Serviços reiniciados com sucesso
- ✅ Nó retornado ao serviço (uncordon)
- ✅ Todos os componentes reportando versão 1.29.1
