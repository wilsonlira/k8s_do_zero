# Tarefa 13 — Debugging de Pod em CrashLoopBackOff

**Domínio:** Troubleshooting
**Peso:** 6%
**Tempo recomendado:** 8 minutos

---

## Cenário

A equipe de desenvolvimento reportou que a aplicação `web-app` no namespace `production` está indisponível. Ao verificar, você identifica que o pod está em estado **CrashLoopBackOff**. Sua tarefa é diagnosticar a causa raiz e corrigir o problema para que o pod volte ao estado Running.

O pod foi criado com a seguinte configuração, mas contém um erro que impede sua execução:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-app
  namespace: production
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    command: ["/bin/sh", "-c", "cat /etc/config/app.conf && nginx -g 'daemon off;'"]
    ports:
    - containerPort: 80
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
  volumes:
  - name: config-volume
    configMap:
      name: app-config
```

O pod referencia um ConfigMap `app-config` que não existe, causando falha na montagem do volume e consequente crash do container.

---

## Requisitos

1. Crie o namespace `production` (se não existir).

2. Aplique o manifesto do pod acima (ele entrará em CrashLoopBackOff ou ficará em estado de erro).

3. Diagnostique a causa raiz do crash usando comandos de troubleshooting:
   - Verifique os eventos do pod com `kubectl describe pod`
   - Verifique os logs do container com `kubectl logs`

4. Corrija o problema criando o ConfigMap `app-config` no namespace `production` com a chave `app.conf` contendo o valor `server_name=web-app;`

5. Delete e recrie o pod (ou aguarde o restart) para que ele monte o ConfigMap corretamente.

6. Verifique que o pod está em estado **Running** e respondendo na porta 80.

---

## Comandos de Verificação

Execute os seguintes comandos para validar sua solução:

```bash
# 1. Verificar que o namespace production existe
kubectl get namespace production
# Esperado: production   Active   <age>

# 2. Verificar que o ConfigMap app-config existe
kubectl get configmap app-config -n production
# Esperado: app-config   1   <age>

# 3. Verificar que o ConfigMap contém a chave app.conf
kubectl get configmap app-config -n production -o jsonpath='{.data.app\.conf}'
# Esperado: server_name=web-app;

# 4. Verificar que o pod está Running
kubectl get pod web-app -n production -o jsonpath='{.status.phase}'
# Esperado: Running

# 5. Verificar que o container está Ready
kubectl get pod web-app -n production -o jsonpath='{.status.containerStatuses[0].ready}'
# Esperado: true

# 6. Verificar que o nginx responde na porta 80
kubectl exec web-app -n production -- curl -s -o /dev/null -w "%{http_code}" http://localhost:80
# Esperado: 200
```

---

## Dicas

- Use `kubectl describe pod` para verificar eventos — procure por mensagens sobre ConfigMap não encontrado.
- Use `kubectl logs` para inspecionar logs do container (pode mostrar erro de arquivo não encontrado).
- Lembre-se que um pod com volume de ConfigMap não inicia se o ConfigMap não existir.
- Após criar o ConfigMap, pode ser necessário deletar e recriar o pod para que o volume seja montado.
