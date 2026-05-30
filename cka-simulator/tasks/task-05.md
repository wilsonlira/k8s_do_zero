# Tarefa 05 — Scaling e Rollback de Deployment

**Domínio:** Workloads & Scheduling
**Peso:** 5%
**Tempo recomendado:** 8 minutos

---

## Cenário

A equipe de desenvolvimento implantou uma aplicação web no namespace `production` usando um Deployment chamado `webapp`. Atualmente a aplicação está rodando com 2 réplicas usando a imagem `nginx:1.24`. Devido a um aumento de tráfego, é necessário escalar a aplicação. Além disso, uma atualização para a versão `nginx:1.25` precisa ser realizada, mas caso a nova versão apresente problemas, você deve ser capaz de reverter rapidamente.

---

## Requisitos

1. Crie o namespace `production` (caso não exista).

2. Crie um Deployment chamado `webapp` no namespace `production` com as seguintes especificações:
   - Imagem: `nginx:1.24`
   - Réplicas: 2
   - Labels no pod: `app=webapp`
   - Estratégia de atualização: `RollingUpdate` com `maxSurge=1` e `maxUnavailable=0`

3. Escale o Deployment `webapp` para **5 réplicas**.

4. Atualize a imagem do Deployment para `nginx:1.25` e registre a causa da mudança na anotação de revisão (use `--record` ou `kubectl annotate`).

5. Verifique que o rollout foi concluído com sucesso.

6. Realize um **rollback** para a revisão anterior (imagem `nginx:1.24`).

7. Confirme que todas as 5 réplicas estão rodando com a imagem `nginx:1.24` após o rollback.

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace production existe
kubectl get namespace production
# Esperado: STATUS = Active

# 2. Verificar que o Deployment existe com 5 réplicas prontas
kubectl get deployment webapp -n production
# Esperado: READY = 5/5

# 3. Verificar a imagem atual após rollback
kubectl get deployment webapp -n production -o jsonpath='{.spec.template.spec.containers[0].image}'
# Esperado: nginx:1.24

# 4. Verificar que todos os pods estão Running
kubectl get pods -n production -l app=webapp --no-headers | grep -c "Running"
# Esperado: 5

# 5. Verificar o histórico de revisões (deve ter pelo menos 2 revisões)
kubectl rollout history deployment/webapp -n production
# Esperado: pelo menos 2 revisões listadas

# 6. Verificar a estratégia de atualização
kubectl get deployment webapp -n production -o jsonpath='{.spec.strategy.type}'
# Esperado: RollingUpdate
```


---

## Critérios de Aprovação

- ✅ Namespace `production` criado
- ✅ Deployment `webapp` criado com estratégia RollingUpdate (maxSurge=1, maxUnavailable=0)
- ✅ Deployment escalado para 5 réplicas
- ✅ Imagem atualizada para `nginx:1.25` com registro de revisão
- ✅ Rollback executado com sucesso para `nginx:1.24`
- ✅ Todas as 5 réplicas rodando com a imagem correta após rollback
