# Tarefa 04 — Configuração de RBAC

**Domínio:** Cluster Architecture, Installation & Configuration
**Peso:** 6.25%
**Tempo recomendado:** 7 minutos

---

## Cenário

Um novo desenvolvedor chamado **João** foi adicionado à equipe e precisa de acesso ao cluster Kubernetes. A política de segurança da empresa exige que:

- Desenvolvedores só podem gerenciar recursos no namespace `development`
- Desenvolvedores podem criar, listar, atualizar e deletar Pods, Deployments e Services
- Desenvolvedores **não** podem acessar Secrets, ConfigMaps com dados sensíveis, ou recursos em outros namespaces
- O acesso deve ser configurado via RBAC usando certificado de cliente

O namespace `development` já existe no cluster.

---

## Requisitos

1. Crie uma chave privada e um CSR (Certificate Signing Request) para o usuário "joao" com:
   - **CN (Common Name):** joao
   - **O (Organization):** developers
2. Assine o certificado usando a CA do cluster (`/etc/kubernetes/pki/ca.pem` e `/etc/kubernetes/pki/ca-key.pem`) com validade de 365 dias
3. Crie um Role no namespace `development` chamado `developer-role` com as seguintes permissões:
   - **Recursos:** pods, deployments, services
   - **Verbos:** get, list, watch, create, update, delete
4. Crie um RoleBinding chamado `joao-developer-binding` que vincule o Role `developer-role` ao usuário "joao" no namespace `development`
5. Configure um contexto no kubeconfig para o usuário "joao" apontando para o namespace `development`
6. Verifique que o usuário "joao" pode listar pods no namespace `development` mas **não** pode listar pods no namespace `default`

> **Importante:** Use `kubectl auth can-i` para verificar as permissões sem precisar trocar de contexto.

---

## Comandos de Verificação

Execute os seguintes comandos para validar se a tarefa foi concluída corretamente:

```bash
# 1. Verificar que o Role existe no namespace development
kubectl get role developer-role -n development
# Esperado: Role "developer-role" listado

# 2. Verificar as permissões do Role
kubectl describe role developer-role -n development
# Esperado: Resources: pods, deployments.apps, services
#           Verbs: get, list, watch, create, update, delete

# 3. Verificar que o RoleBinding existe
kubectl get rolebinding joao-developer-binding -n development
# Esperado: RoleBinding "joao-developer-binding" listado

# 4. Verificar que o RoleBinding referencia o usuário correto
kubectl describe rolebinding joao-developer-binding -n development
# Esperado: Subject: User "joao", Role: "developer-role"

# 5. Verificar que "joao" pode listar pods no namespace development
kubectl auth can-i list pods -n development --as=joao
# Esperado: "yes"

# 6. Verificar que "joao" pode criar deployments no namespace development
kubectl auth can-i create deployments -n development --as=joao
# Esperado: "yes"

# 7. Verificar que "joao" NÃO pode listar pods no namespace default
kubectl auth can-i list pods -n default --as=joao
# Esperado: "no"

# 8. Verificar que "joao" NÃO pode acessar secrets no namespace development
kubectl auth can-i get secrets -n development --as=joao
# Esperado: "no"
```

---

## Critérios de Aprovação

- ✅ Certificado do usuário "joao" gerado e assinado pela CA do cluster
- ✅ Role `developer-role` criado com permissões corretas (pods, deployments, services)
- ✅ RoleBinding `joao-developer-binding` vinculando o usuário ao Role
- ✅ Usuário pode gerenciar recursos no namespace `development`
- ✅ Usuário **não** pode acessar recursos em outros namespaces
- ✅ Usuário **não** pode acessar Secrets
