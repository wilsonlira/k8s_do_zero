# Tarefa 08 — Criar e Expor Services (ClusterIP e NodePort)

**Domínio:** Services & Networking
**Peso:** 20%
**Tempo recomendado:** 8 minutos

---

## Cenário

A equipe de desenvolvimento implantou uma aplicação web no namespace `webapp`. O Deployment `frontend` já está rodando com 3 réplicas usando a imagem `nginx:1.25` na porta 80. Porém, a aplicação ainda não está acessível — nem internamente pelo cluster, nem externamente.

Você precisa criar os Services necessários para que:
1. Outros pods dentro do cluster possam acessar o frontend via DNS interno
2. Usuários externos possam acessar a aplicação via NodePort

---

## Requisitos

1. Crie o namespace `webapp` (se não existir)
2. Crie o Deployment `frontend` no namespace `webapp`:
   - Imagem: `nginx:1.25`
   - Réplicas: 3
   - Label: `app=frontend`
   - Container port: 80
3. Crie um Service do tipo **ClusterIP** chamado `frontend-svc` no namespace `webapp`:
   - Selector: `app=frontend`
   - Port: 80 (targetPort: 80)
4. Crie um Service do tipo **NodePort** chamado `frontend-nodeport` no namespace `webapp`:
   - Selector: `app=frontend`
   - Port: 80 (targetPort: 80)
   - NodePort: 30080
5. Verifique que o Service ClusterIP resolve via DNS interno do cluster

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace existe
kubectl get namespace webapp
# Esperado: STATUS = Active

# 2. Verificar que o Deployment está rodando com 3 réplicas
kubectl get deployment frontend -n webapp
# Esperado: READY = 3/3

# 3. Verificar que o Service ClusterIP existe e tem endpoints
kubectl get svc frontend-svc -n webapp
# Esperado: TYPE = ClusterIP, PORT(S) = 80/TCP

kubectl get endpoints frontend-svc -n webapp
# Esperado: Deve listar 3 IPs (um por pod)

# 4. Verificar que o Service NodePort existe na porta correta
kubectl get svc frontend-nodeport -n webapp
# Esperado: TYPE = NodePort, PORT(S) = 80:30080/TCP

# 5. Verificar resolução DNS interna (executar de dentro de um pod)
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -n webapp -- nslookup frontend-svc.webapp.svc.cluster.local
# Esperado: Deve resolver para o ClusterIP do service frontend-svc

# 6. Verificar acesso via NodePort (executar do nó worker)
curl http://<WORKER_NODE_IP>:30080
# Esperado: Página padrão do nginx (HTML com "Welcome to nginx!")
```

---

## Critérios de Aprovação

- ✅ Namespace `webapp` existe
- ✅ Deployment `frontend` com 3 réplicas em estado Ready
- ✅ Service `frontend-svc` do tipo ClusterIP com 3 endpoints
- ✅ Service `frontend-nodeport` do tipo NodePort na porta 30080
- ✅ DNS interno resolve `frontend-svc.webapp.svc.cluster.local`
- ✅ Acesso externo via NodePort retorna resposta do nginx
