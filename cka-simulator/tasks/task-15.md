# Tarefa 15 — Troubleshooting de Conectividade de Rede entre Pods

**Domínio:** Troubleshooting
**Peso:** 6%
**Tempo recomendado:** 8 minutos

---

## Cenário

A equipe de desenvolvimento reportou que um pod `frontend` não consegue se comunicar com o serviço `backend-svc` no namespace `app-network`. O Service existe e o pod backend está Running, mas as requisições do frontend para `http://backend-svc:8080` estão falhando.

Ao investigar, você descobre que o Service foi criado com um **selector incorreto** que não corresponde aos labels dos pods backend, resultando em zero endpoints.

---

## Requisitos

1. Crie o namespace `app-network` (se não existir).

2. Crie o Deployment `backend` com as seguintes especificações:
   - Imagem: `nginx:1.25`
   - Réplicas: 1
   - Label do pod: `app: backend`
   - Porta do container: 80

3. Crie o Service `backend-svc` com um **selector incorreto** (simulando o erro):
   - Tipo: ClusterIP
   - Port: 8080
   - TargetPort: 80
   - Selector: `app: backend-wrong` (INCORRETO — não corresponde ao label do pod)

4. Crie o pod `frontend` com a imagem `busybox:1.36` executando `sleep 3600`.

5. Diagnostique o problema:
   - Verifique que o Service não tem endpoints (`kubectl get endpoints backend-svc`)
   - Compare o selector do Service com os labels dos pods backend

6. Corrija o Service alterando o selector para `app: backend`.

7. Verifique que a comunicação entre frontend e backend funciona via `http://backend-svc:8080`.

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace app-network existe
kubectl get namespace app-network
# Esperado: app-network   Active   <age>

# 2. Verificar que o backend está Running
kubectl get pods -n app-network -l app=backend
# Esperado: 1 pod em estado Running

# 3. Verificar que o Service tem endpoints (NÃO deve estar vazio)
kubectl get endpoints backend-svc -n app-network
# Esperado: backend-svc   <IP>:80   <age>

# 4. Verificar o selector do Service
kubectl get svc backend-svc -n app-network -o jsonpath='{.spec.selector.app}'
# Esperado: backend

# 5. Verificar resolução DNS do serviço a partir do frontend
kubectl exec frontend -n app-network -- nslookup backend-svc.app-network.svc.cluster.local
# Esperado: resolução com IP do ClusterIP do serviço

# 6. Verificar conectividade HTTP do frontend para o backend
kubectl exec frontend -n app-network -- wget -qO- --timeout=5 http://backend-svc:8080
# Esperado: HTML da página padrão do nginx (contendo "Welcome to nginx")
```

---

## Dicas

- Use `kubectl get endpoints <service-name>` para verificar se o Service tem endpoints ativos.
- Se endpoints estiver vazio (`<none>`), o selector do Service não corresponde a nenhum pod.
- Use `kubectl get pods --show-labels` para ver os labels dos pods.
- Use `kubectl describe svc <service-name>` para ver o selector configurado.
- Corrija com `kubectl edit svc` ou `kubectl patch svc`.
