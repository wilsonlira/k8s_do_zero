# Solução — Tarefa 04: Configuração de RBAC

**Domínio:** Cluster Architecture, Installation & Configuration
**Tempo estimado:** 7 minutos

---

## Passo 1: Gerar a chave privada para o usuário "joao"

```bash
openssl genrsa -out /tmp/joao.key 2048
```

**Saída esperada:**
```
Generating RSA private key, 2048 bit long modulus
..........+++
.....+++
e is 65537 (0x10001)
```

**Por que:** Cada usuário no Kubernetes autenticado por certificado precisa de um par de chaves (privada + pública). A chave privada é usada para assinar requisições — ela nunca deve ser compartilhada.

---

## Passo 2: Criar o CSR (Certificate Signing Request)

```bash
openssl req -new \
  -key /tmp/joao.key \
  -out /tmp/joao.csr \
  -subj "/CN=joao/O=developers"
```

**Por que:** O CSR contém as informações que serão incluídas no certificado:
- **CN (Common Name) = joao** — o Kubernetes usa o CN como nome do usuário para RBAC
- **O (Organization) = developers** — o Kubernetes usa o O como grupo do usuário

Isso significa que qualquer RoleBinding para o usuário "joao" ou para o grupo "developers" se aplicará a este certificado.

---

## Passo 3: Assinar o certificado com a CA do cluster

```bash
openssl x509 -req \
  -in /tmp/joao.csr \
  -CA /etc/kubernetes/pki/ca.pem \
  -CAkey /etc/kubernetes/pki/ca-key.pem \
  -CAcreateserial \
  -out /tmp/joao.pem \
  -days 365
```

**Saída esperada:**
```
Signature ok
subject=/CN=joao/O=developers
Getting CA Private Key
```

**Por que:** O certificado precisa ser assinado pela mesma CA que o kube-apiserver confia. Quando o usuário se conecta, o apiserver valida o certificado contra a CA e extrai o CN e O para identificar o usuário e seus grupos.

---

## Passo 4: Criar o Role no namespace development

```bash
kubectl create role developer-role \
  --namespace=development \
  --verb=get,list,watch,create,update,delete \
  --resource=pods,deployments,services
```

**Saída esperada:**
```
role.rbac.authorization.k8s.io/developer-role created
```

**Por que:** O Role define **o que** pode ser feito. Neste caso, permitimos operações CRUD completas (get, list, watch, create, update, delete) nos recursos pods, deployments e services. O Role é namespaced — só se aplica ao namespace `development`.

---

## Passo 5: Criar o RoleBinding

```bash
kubectl create rolebinding joao-developer-binding \
  --namespace=development \
  --role=developer-role \
  --user=joao
```

**Saída esperada:**
```
rolebinding.rbac.authorization.k8s.io/joao-developer-binding created
```

**Por que:** O RoleBinding conecta **quem** (usuário joao) ao **o que** (Role developer-role) em **onde** (namespace development). Sem o RoleBinding, o Role existe mas não se aplica a ninguém.

---

## Passo 6: Configurar o contexto no kubeconfig para o usuário joao

```bash
# Adicionar as credenciais do usuário
kubectl config set-credentials joao \
  --client-certificate=/tmp/joao.pem \
  --client-key=/tmp/joao.key

# Criar o contexto
kubectl config set-context joao-context \
  --cluster=$(kubectl config view -o jsonpath='{.clusters[0].name}') \
  --namespace=development \
  --user=joao
```

**Saída esperada:**
```
User "joao" set.
Context "joao-context" created.
```

**Por que:** O contexto no kubeconfig permite alternar facilmente entre usuários com `kubectl config use-context joao-context`. Ele associa o cluster, o namespace padrão e as credenciais do usuário em uma configuração nomeada.

---

## Passo 7: Verificar as permissões do usuário

```bash
# Verificar que joao pode listar pods no namespace development
kubectl auth can-i list pods -n development --as=joao
```

**Saída esperada:**
```
yes
```

```bash
# Verificar que joao pode criar deployments no namespace development
kubectl auth can-i create deployments -n development --as=joao
```

**Saída esperada:**
```
yes
```

```bash
# Verificar que joao NÃO pode listar pods no namespace default
kubectl auth can-i list pods -n default --as=joao
```

**Saída esperada:**
```
no
```

```bash
# Verificar que joao NÃO pode acessar secrets
kubectl auth can-i get secrets -n development --as=joao
```

**Saída esperada:**
```
no
```

**Por que:** O `kubectl auth can-i --as=<user>` permite testar permissões sem precisar trocar de contexto. Isso é essencial para validar que o RBAC está configurado corretamente — tanto as permissões concedidas quanto as negadas (princípio do menor privilégio).

---

## Resumo dos Conceitos

| Conceito | Explicação |
|----------|-----------|
| Role | Define permissões (verbos + recursos) dentro de um namespace |
| RoleBinding | Vincula um Role a um usuário/grupo/serviceaccount |
| ClusterRole | Como Role, mas aplica-se a todo o cluster |
| CN no certificado | Kubernetes usa como nome do usuário |
| O no certificado | Kubernetes usa como grupo do usuário |
| `--as=<user>` | Impersonação para testar permissões de outro usuário |
| Princípio do menor privilégio | Conceder apenas as permissões estritamente necessárias |
