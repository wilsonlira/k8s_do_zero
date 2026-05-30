# Tarefa 09 — Configurar NetworkPolicy para Isolamento de Tráfego

**Domínio:** Services & Networking
**Peso:** 20%
**Tempo recomendado:** 10 minutos

---

## Cenário

Sua empresa possui um cluster Kubernetes com múltiplas aplicações em diferentes namespaces. A equipe de segurança exige que o banco de dados no namespace `database` seja acessível **apenas** pelos pods da aplicação backend no namespace `backend`, e que todo outro tráfego de ingress seja bloqueado.

Atualmente, qualquer pod no cluster consegue se comunicar com o banco de dados, o que representa um risco de segurança. Você deve implementar NetworkPolicies para restringir o acesso.

---

## Requisitos

1. Crie o namespace `database` com o label `purpose=database`
2. Crie o namespace `backend` com o label `purpose=backend`
3. No namespace `database`, crie um Deployment chamado `mysql`:
   - Imagem: `mysql:8.0`
   - Réplicas: 1
   - Label: `app=mysql`
   - Container port: 3306
   - Variável de ambiente: `MYSQL_ROOT_PASSWORD=secret123`
4. Crie um Service ClusterIP chamado `mysql-svc` no namespace `database`:
   - Selector: `app=mysql`
   - Port: 3306
5. No namespace `backend`, crie um pod chamado `api-server`:
   - Imagem: `busybox:1.36`
   - Label: `app=api-server`
   - Comando: `sleep 3600`
6. Crie uma **NetworkPolicy** chamada `db-allow-backend-only` no namespace `database` que:
   - Aplique-se aos pods com label `app=mysql`
   - Permita tráfego de **ingress** apenas de pods no namespace com label `purpose=backend`
   - Permita tráfego apenas na porta TCP 3306
   - Bloqueie todo outro tráfego de ingress (deny-all implícito)

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar namespaces com labels corretos
kubectl get namespace database --show-labels
# Esperado: Labels incluem purpose=database

kubectl get namespace backend --show-labels
# Esperado: Labels incluem purpose=backend

# 2. Verificar que o MySQL está rodando
kubectl get pods -n database -l app=mysql
# Esperado: STATUS = Running

# 3. Verificar que o Service existe
kubectl get svc mysql-svc -n database
# Esperado: TYPE = ClusterIP, PORT(S) = 3306/TCP

# 4. Verificar que a NetworkPolicy existe
kubectl get networkpolicy db-allow-backend-only -n database
# Esperado: NetworkPolicy listada

kubectl describe networkpolicy db-allow-backend-only -n database
# Esperado: 
#   PodSelector: app=mysql
#   Allowing ingress traffic: From NamespaceSelector: purpose=backend
#   To Port: 3306/TCP

# 5. Verificar que o pod do backend CONSEGUE acessar o MySQL (porta 3306)
kubectl exec api-server -n backend -- nc -zv -w3 mysql-svc.database.svc.cluster.local 3306
# Esperado: Conexão bem-sucedida (open)

# 6. Verificar que um pod de OUTRO namespace NÃO consegue acessar o MySQL
kubectl run test-blocked --image=busybox:1.36 --rm -it --restart=Never -n default -- nc -zv -w3 mysql-svc.database.svc.cluster.local 3306
# Esperado: Conexão falha (timeout ou refused)
```

---

## Critérios de Aprovação

- ✅ Namespace `database` existe com label `purpose=database`
- ✅ Namespace `backend` existe com label `purpose=backend`
- ✅ Deployment `mysql` rodando no namespace `database`
- ✅ Service `mysql-svc` criado corretamente
- ✅ NetworkPolicy `db-allow-backend-only` aplicada aos pods `app=mysql`
- ✅ Pod no namespace `backend` consegue conectar na porta 3306
- ✅ Pod em outro namespace (ex: `default`) NÃO consegue conectar na porta 3306
