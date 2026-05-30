# Módulo 13 — Ingress Controller

## Objetivo

Instalar e configurar um Ingress Controller no cluster Kubernetes, habilitando o roteamento de tráfego HTTP/HTTPS externo para serviços internos. Ao final deste módulo, você terá:

- Compreensão do papel de Ingress resources e Ingress Controllers no Kubernetes
- Clareza sobre as diferenças entre Ingress, NodePort e LoadBalancer
- NGINX Ingress Controller instalado e operacional
- Dois serviços backend implantados para demonstração
- Ingress com roteamento baseado em path (path-based routing)
- Ingress com roteamento baseado em host (host-based routing)
- TLS termination configurado com certificado auto-assinado
- Capacidade de diagnosticar problemas comuns de Ingress

## Teoria

### O que é um Ingress?

Um **Ingress** é um recurso da API do Kubernetes que define regras para rotear tráfego HTTP/HTTPS externo para Services dentro do cluster. Ele funciona como uma camada de abstração que descreve *como* o tráfego deve ser direcionado — mas não executa o roteamento por si só.

Para que as regras de Ingress sejam efetivadas, é necessário um **Ingress Controller** — um componente que monitora os recursos Ingress via API server e configura um proxy reverso (como NGINX, Traefik ou HAProxy) para implementar as regras definidas.

### Ingress vs NodePort vs LoadBalancer

O Kubernetes oferece diferentes formas de expor serviços para tráfego externo. Cada abordagem tem trade-offs:

| Característica | NodePort | LoadBalancer | Ingress |
|---|---|---|---|
| **Camada OSI** | L4 (TCP/UDP) | L4 (TCP/UDP) | L7 (HTTP/HTTPS) |
| **Porta** | Porta alta (30000-32767) em cada nó | Porta padrão (80/443) via cloud LB | Porta padrão (80/443) via controller |
| **Roteamento** | Por porta — 1 porta = 1 serviço | Por IP — 1 LB = 1 serviço | Por path/host — 1 endpoint = N serviços |
| **TLS** | Não gerencia | Depende do cloud provider | Termination no controller |
| **Custo (cloud)** | Sem custo extra | 1 Load Balancer por serviço ($$$) | 1 Load Balancer para todos os serviços |
| **Uso ideal** | Desenvolvimento, testes | Serviço único em produção | Múltiplos serviços HTTP em produção |

**Por que usar Ingress?**

- **Consolidação**: Um único ponto de entrada para múltiplos serviços, em vez de um LoadBalancer por serviço
- **Roteamento inteligente**: Direciona tráfego baseado em URL path (`/api`, `/web`) ou hostname (`api.example.com`, `web.example.com`)
- **TLS centralizado**: Gerencia certificados HTTPS em um único lugar
- **Economia**: Em cloud providers, evita o custo de múltiplos Load Balancers

### Arquitetura do Ingress Controller

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Tráfego Externo                             │
│                    (HTTP/HTTPS requests)                            │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    NGINX Ingress Controller                          │
│                    (Pod no cluster)                                  │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  nginx.conf (gerado automaticamente a partir dos Ingress)   │   │
│  │                                                             │   │
│  │  server {                                                   │   │
│  │    location /app1 → backend-app1:80                         │   │
│  │    location /app2 → backend-app2:80                         │   │
│  │  }                                                          │   │
│  │  server {                                                   │   │
│  │    server_name app1.example.com → backend-app1:80           │   │
│  │    server_name app2.example.com → backend-app2:80           │   │
│  │  }                                                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
     │ Service      │ │ Service      │ │ Service      │
     │ backend-app1 │ │ backend-app2 │ │ backend-app3 │
     └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
            ▼                ▼                ▼
     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
     │ Pod(s)       │ │ Pod(s)       │ │ Pod(s)       │
     │ app1         │ │ app2         │ │ app3         │
     └──────────────┘ └──────────────┘ └──────────────┘
```

**Fluxo de uma requisição HTTP:**

1. Cliente envia requisição HTTP para o IP/porta do Ingress Controller
2. O NGINX Ingress Controller inspeciona o `Host` header e o URL path
3. Baseado nas regras do Ingress resource, roteia para o Service backend correto
4. O Service encaminha para um dos Pods do backend
5. A resposta retorna pelo mesmo caminho

### NGINX Ingress Controller

O **NGINX Ingress Controller** é a implementação de referência mantida pelo projeto Kubernetes. Ele:

- Monitora recursos Ingress via kube-apiserver (watch)
- Gera e recarrega a configuração do NGINX automaticamente quando Ingress resources são criados, modificados ou removidos
- Suporta path-based routing, host-based routing, TLS termination, rate limiting, e mais
- É implantado como um Deployment (ou DaemonSet) dentro do cluster

Neste lab, usamos o NGINX Ingress Controller por ser a opção mais documentada, amplamente adotada, e alinhada com o conteúdo do exame CKA.

### Tipos de Roteamento

#### Path-Based Routing (Roteamento por caminho)

Direciona tráfego baseado no URL path da requisição:

```
http://ingress-ip/app1  →  Service app1
http://ingress-ip/app2  →  Service app2
```

#### Host-Based Routing (Roteamento por hostname)

Direciona tráfego baseado no header `Host` da requisição HTTP:

```
http://app1.example.com  →  Service app1
http://app2.example.com  →  Service app2
```

### TLS Termination

O Ingress Controller pode terminar conexões HTTPS, descriptografando o tráfego TLS antes de encaminhá-lo aos backends em HTTP. Isso centraliza o gerenciamento de certificados no Ingress, eliminando a necessidade de configurar TLS em cada serviço individualmente.

## Pré-requisitos

Antes de iniciar este módulo, você deve ter completado:

- [Módulo 11 — CoreDNS](../11-coredns/) — DNS funcional no cluster para resolução de Services
- [Módulo 10 — CNI Networking](../10-cni-networking/) — pod-to-pod networking operacional
- [Módulo 12 — kubectl & kubeconfig](../12-kubectl-kubeconfig/) — kubectl configurado para acessar o cluster

Componentes que devem estar operacionais:

- kube-apiserver acessível e respondendo
- Worker node(s) com status Ready
- CoreDNS resolvendo nomes de Services
- Plugin CNI funcional (Pods obtêm IPs e se comunicam)
- kubectl configurado e conectado ao cluster

## Comandos Passo a Passo

### 1. Implantar Serviços Backend

Antes de configurar o Ingress, precisamos de serviços backend para receber o tráfego roteado. Vamos criar dois aplicativos simples que retornam respostas distintas, permitindo verificar que o roteamento funciona corretamente.

#### 1.1 Criar o backend "app1"

Este Deployment usa uma imagem NGINX customizada que retorna uma página identificando o serviço como "App 1":

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
  namespace: default
  labels:
    app: app1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app1
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
        - name: app1
          image: hashicorp/http-echo:0.2.3
          args:
            - "-text=Hello from App 1"
            - "-listen=:8080"
          ports:
            - containerPort: 8080
EOF
```

**Saída esperada:**
```
deployment.apps/app1 created
```

A imagem `hashicorp/http-echo` é um servidor HTTP simples que retorna o texto configurado via flag `-text`. Usamos porta 8080 para evitar necessidade de privilégios root no container.

#### 1.2 Criar o Service para "app1"

O Service expõe o Deployment app1 internamente no cluster, permitindo que o Ingress Controller encaminhe tráfego para ele:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app1-service
  namespace: default
spec:
  selector:
    app: app1
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
EOF
```

**Saída esperada:**
```
service/app1-service created
```

O Service escuta na porta 80 e encaminha para a porta 8080 do container. Isso permite que o Ingress referencie a porta padrão HTTP (80).

#### 1.3 Criar o backend "app2"

O segundo backend retorna uma resposta diferente para que possamos verificar o roteamento:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app2
  namespace: default
  labels:
    app: app2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app2
  template:
    metadata:
      labels:
        app: app2
    spec:
      containers:
        - name: app2
          image: hashicorp/http-echo:0.2.3
          args:
            - "-text=Hello from App 2"
            - "-listen=:8080"
          ports:
            - containerPort: 8080
EOF
```

**Saída esperada:**
```
deployment.apps/app2 created
```

#### 1.4 Criar o Service para "app2"

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app2-service
  namespace: default
spec:
  selector:
    app: app2
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
EOF
```

**Saída esperada:**
```
service/app2-service created
```

#### 1.5 Verificar que os backends estão rodando

Antes de prosseguir, confirme que ambos os Deployments estão saudáveis:

```bash
# Verificar Pods dos backends
kubectl get pods -l 'app in (app1, app2)'
```

**Saída esperada:**
```
NAME                    READY   STATUS    RESTARTS   AGE
app1-xxxxxxxxx-xxxxx   1/1     Running   0          30s
app2-xxxxxxxxx-xxxxx   1/1     Running   0          25s
```

A linha-chave é `STATUS: Running` e `READY: 1/1` para ambos os Pods.

```bash
# Verificar Services
kubectl get svc app1-service app2-service
```

**Saída esperada:**
```
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
app1-service   ClusterIP   10.96.X.X      <none>        80/TCP    45s
app2-service   ClusterIP   10.96.X.X      <none>        80/TCP    40s
```

---

### 2. Instalar o NGINX Ingress Controller

O NGINX Ingress Controller é instalado usando o manifesto oficial do projeto Kubernetes. Este manifesto cria todos os recursos necessários: Namespace, ServiceAccount, RBAC, ConfigMaps, Deployment e Service.

#### 2.1 Aplicar o manifesto oficial do NGINX Ingress Controller

O manifesto oficial cria o namespace `ingress-nginx` e todos os componentes necessários:

```bash
# Instalar NGINX Ingress Controller usando manifesto oficial
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.6/deploy/static/provider/baremetal/deploy.yaml
```

**Saída esperada:**
```
namespace/ingress-nginx created
serviceaccount/ingress-nginx created
serviceaccount/ingress-nginx-admission created
role.rbac.authorization.k8s.io/ingress-nginx created
role.rbac.authorization.k8s.io/ingress-nginx-admission created
clusterrole.rbac.authorization.k8s.io/ingress-nginx created
clusterrole.rbac.authorization.k8s.io/ingress-nginx-admission created
rolebinding.rbac.authorization.k8s.io/ingress-nginx created
rolebinding.rbac.authorization.k8s.io/ingress-nginx-admission created
clusterrolebinding.rbac.authorization.k8s.io/ingress-nginx created
clusterrolebinding.rbac.authorization.k8s.io/ingress-nginx-admission created
configmap/ingress-nginx-controller created
service/ingress-nginx-controller created
service/ingress-nginx-controller-admission created
deployment.apps/ingress-nginx-controller created
job.batch/ingress-nginx-admission-create created
job.batch/ingress-nginx-admission-patch created
ingressclass.networking.k8s.io/nginx created
validatingwebhookconfiguration.admissionregistration.k8s.io/ingress-nginx-admission created
```

> **Nota**: Usamos o manifesto `provider/baremetal` porque nosso cluster é bare-metal (EC2 sem integração com cloud load balancer). Este manifesto configura o Ingress Controller com um Service do tipo NodePort em vez de LoadBalancer.

#### Componentes criados pelo manifesto

| Recurso | Função |
|---|---|
| `Namespace ingress-nginx` | Isola todos os recursos do Ingress Controller |
| `ServiceAccount` | Identidade para o controller acessar a API |
| `ClusterRole/ClusterRoleBinding` | Permissões RBAC para monitorar Ingress, Services, Endpoints, Secrets |
| `ConfigMap ingress-nginx-controller` | Configuração global do NGINX (timeouts, buffer sizes, etc.) |
| `Deployment ingress-nginx-controller` | O Pod do NGINX Ingress Controller |
| `Service ingress-nginx-controller` | Expõe o controller via NodePort (portas 80/443) |
| `IngressClass nginx` | Define a classe de Ingress padrão |
| `ValidatingWebhookConfiguration` | Valida recursos Ingress antes de serem criados |

#### 2.2 Aguardar o Ingress Controller ficar pronto

O controller pode levar alguns segundos para inicializar completamente:

```bash
# Aguardar o Pod do Ingress Controller ficar Ready
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

**Saída esperada:**
```
pod/ingress-nginx-controller-xxxxxxxxx-xxxxx condition met
```

#### 2.3 Verificar a instalação do Ingress Controller

```bash
# Verificar Pods no namespace ingress-nginx
kubectl get pods -n ingress-nginx
```

**Saída esperada:**
```
NAME                                        READY   STATUS      RESTARTS   AGE
ingress-nginx-admission-create-xxxxx        0/1     Completed   0          60s
ingress-nginx-admission-patch-xxxxx         0/1     Completed   0          60s
ingress-nginx-controller-xxxxxxxxx-xxxxx    1/1     Running     0          60s
```

A linha-chave é o Pod `ingress-nginx-controller` com `STATUS: Running` e `READY: 1/1`.

Os Pods `admission-create` e `admission-patch` são Jobs que configuram o webhook de validação e terminam após a execução (status `Completed`).

```bash
# Verificar o Service do Ingress Controller (NodePort)
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

**Saída esperada:**
```
NAME                       TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller   NodePort   10.96.X.X      <none>        80:3XXXX/TCP,443:3XXXX/TCP   90s
```

A linha-chave é `TYPE: NodePort` com portas mapeadas (ex: `80:31080/TCP,443:31443/TCP`). Anote as portas NodePort — elas serão usadas para acessar o Ingress externamente.

```bash
# Verificar a IngressClass criada
kubectl get ingressclass
```

**Saída esperada:**
```
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       2m
```

A IngressClass `nginx` é o que conecta recursos Ingress ao NGINX Ingress Controller.

---

### 3. Criar Ingress com Path-Based Routing

O path-based routing direciona requisições para diferentes backends baseado no caminho da URL. Neste exemplo, `/app1` vai para o serviço app1 e `/app2` vai para o serviço app2.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-based-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /app1
            pathType: Prefix
            backend:
              service:
                name: app1-service
                port:
                  number: 80
          - path: /app2
            pathType: Prefix
            backend:
              service:
                name: app2-service
                port:
                  number: 80
EOF
```

**Saída esperada:**
```
ingress.networking.k8s.io/path-based-ingress created
```

#### Explicação dos campos do Ingress

| Campo | Valor | Descrição |
|---|---|---|
| `ingressClassName` | `nginx` | Associa este Ingress ao NGINX Ingress Controller |
| `annotations.rewrite-target` | `/` | Reescreve o path antes de encaminhar ao backend (remove `/app1` ou `/app2`) |
| `rules[].http.paths[].path` | `/app1`, `/app2` | Paths que ativam cada regra de roteamento |
| `rules[].http.paths[].pathType` | `Prefix` | Match por prefixo — `/app1/anything` também é roteado |
| `backend.service.name` | `app1-service` | Nome do Service de destino |
| `backend.service.port.number` | `80` | Porta do Service de destino |

**Sobre `pathType`:**

| Tipo | Comportamento |
|---|---|
| `Prefix` | Match por prefixo — `/app1` casa com `/app1`, `/app1/`, `/app1/sub` |
| `Exact` | Match exato — `/app1` casa apenas com `/app1` |
| `ImplementationSpecific` | Comportamento definido pelo Ingress Controller |

**Sobre `rewrite-target`:**

A annotation `nginx.ingress.kubernetes.io/rewrite-target: /` é necessária porque o backend `http-echo` não conhece o path `/app1`. Sem o rewrite, a requisição chegaria ao backend como `GET /app1`, que poderia retornar 404. Com o rewrite, a requisição chega como `GET /`.

---

### 4. Criar Ingress com Host-Based Routing

O host-based routing direciona requisições baseado no header `Host` da requisição HTTP. Cada hostname é roteado para um backend diferente.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-based-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
    - host: app1.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1-service
                port:
                  number: 80
    - host: app2.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app2-service
                port:
                  number: 80
EOF
```

**Saída esperada:**
```
ingress.networking.k8s.io/host-based-ingress created
```

#### Explicação dos campos

| Campo | Valor | Descrição |
|---|---|---|
| `rules[].host` | `app1.example.com` | Hostname que ativa esta regra (comparado com o header `Host`) |
| `rules[].http.paths[].path` | `/` | Path raiz — todo tráfego para este host é roteado |

**Como funciona o host-based routing:**

1. O cliente envia uma requisição com `Host: app1.example.com`
2. O NGINX Ingress Controller compara o header `Host` com as regras definidas
3. A regra que casa com `app1.example.com` direciona para `app1-service`
4. Se nenhuma regra casar, o NGINX retorna 404

> **Nota**: Em um ambiente real, você configuraria registros DNS apontando `app1.example.com` e `app2.example.com` para o IP do Ingress Controller. No lab, usamos o header `Host` diretamente com `curl -H`.

---

### 5. Configurar TLS Termination

O Ingress Controller pode terminar conexões HTTPS usando um certificado TLS armazenado em um Secret do Kubernetes. O tráfego entre o cliente e o Ingress é criptografado (HTTPS), enquanto o tráfego entre o Ingress e os backends é HTTP (não criptografado).

#### 5.1 Gerar certificado auto-assinado

Para o lab, geramos um certificado auto-assinado. Em produção, use certificados de uma CA confiável (ex: Let's Encrypt).

```bash
# Gerar chave privada RSA de 2048 bits
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls-ingress.key \
  -out tls-ingress.crt \
  -subj "/CN=app1.example.com/O=k8s-lab" \
  -addext "subjectAltName=DNS:app1.example.com,DNS:app2.example.com"
```

**Saída esperada:**
```
...+..+.......+...+..+...
-----
```

O comando gera dois arquivos:
- `tls-ingress.key` — chave privada (nunca compartilhe)
- `tls-ingress.crt` — certificado público

**Parâmetros explicados:**

| Parâmetro | Valor | Descrição |
|---|---|---|
| `-x509` | — | Gera certificado auto-assinado (não um CSR) |
| `-nodes` | — | Não criptografa a chave privada com senha |
| `-days 365` | 365 | Validade do certificado em dias |
| `-newkey rsa:2048` | RSA 2048-bit | Algoritmo e tamanho da chave |
| `-keyout` | `tls-ingress.key` | Arquivo de saída da chave privada |
| `-out` | `tls-ingress.crt` | Arquivo de saída do certificado |
| `-subj` | `"/CN=app1.example.com/O=k8s-lab"` | Subject do certificado (Common Name e Organization) |
| `-addext` | `subjectAltName=DNS:...` | Nomes alternativos (SANs) — hostnames válidos para o certificado |

#### 5.2 Criar Secret TLS no Kubernetes

O certificado e a chave são armazenados em um Secret do tipo `kubernetes.io/tls`:

```bash
# Criar Secret TLS a partir dos arquivos gerados
kubectl create secret tls ingress-tls-secret \
  --cert=tls-ingress.crt \
  --key=tls-ingress.key \
  --namespace=default
```

**Saída esperada:**
```
secret/ingress-tls-secret created
```

Verifique o Secret criado:

```bash
kubectl get secret ingress-tls-secret
```

**Saída esperada:**
```
NAME                 TYPE                DATA   AGE
ingress-tls-secret   kubernetes.io/tls   2      10s
```

A linha-chave é `TYPE: kubernetes.io/tls` e `DATA: 2` — confirma que o Secret contém o certificado (`tls.crt`) e a chave (`tls.key`).

#### 5.3 Criar Ingress com TLS

Agora criamos um Ingress que usa o Secret TLS para habilitar HTTPS:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app1.example.com
        - app2.example.com
      secretName: ingress-tls-secret
  rules:
    - host: app1.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1-service
                port:
                  number: 80
    - host: app2.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app2-service
                port:
                  number: 80
EOF
```

**Saída esperada:**
```
ingress.networking.k8s.io/tls-ingress created
```

#### Explicação dos campos TLS

| Campo | Valor | Descrição |
|---|---|---|
| `tls[].hosts` | `app1.example.com`, `app2.example.com` | Hostnames para os quais o TLS é habilitado |
| `tls[].secretName` | `ingress-tls-secret` | Nome do Secret contendo o certificado e chave |
| `annotations.ssl-redirect` | `"true"` | Redireciona automaticamente HTTP → HTTPS (301) |

**Como funciona o TLS termination:**

1. Cliente inicia conexão HTTPS com o Ingress Controller
2. O Ingress Controller apresenta o certificado do Secret `ingress-tls-secret`
3. A conexão TLS é estabelecida entre cliente e Ingress Controller
4. O Ingress Controller descriptografa a requisição
5. A requisição é encaminhada ao backend em HTTP (sem criptografia interna)
6. A resposta do backend retorna ao Ingress Controller
7. O Ingress Controller criptografa a resposta e envia ao cliente

> **Nota de segurança**: Em produção, considere usar TLS end-to-end (mTLS) entre o Ingress e os backends para ambientes com requisitos de segurança elevados.

---

### 6. Verificar os Ingress Resources Criados

```bash
# Listar todos os Ingress resources
kubectl get ingress
```

**Saída esperada:**
```
NAME                 CLASS   HOSTS                              ADDRESS       PORTS     AGE
path-based-ingress   nginx   *                                  10.96.X.X     80        5m
host-based-ingress   nginx   app1.example.com,app2.example.com  10.96.X.X     80        3m
tls-ingress          nginx   app1.example.com,app2.example.com  10.96.X.X     80, 443   1m
```

```bash
# Detalhes do Ingress path-based
kubectl describe ingress path-based-ingress
```

**Saída esperada:**
```
Name:             path-based-ingress
Namespace:        default
Address:          10.96.X.X
Ingress Class:    nginx
Default backend:  <default>
Rules:
  Host        Path  Backends
  ----        ----  --------
  *
              /app1   app1-service:80 (10.244.X.X:8080)
              /app2   app2-service:80 (10.244.X.X:8080)
Annotations:  nginx.ingress.kubernetes.io/rewrite-target: /
Events:
  Type    Reason  Age   From                      Message
  ----    ------  ----  ----                      -------
  Normal  Sync    30s   nginx-ingress-controller  Scheduled for sync
```

A linha-chave é `Backends` mostrando os IPs dos Pods — confirma que o Ingress Controller resolveu os Services para endpoints reais.

---

## Verificação

### Obter a porta NodePort do Ingress Controller

Como estamos em um cluster bare-metal (sem cloud load balancer), o Ingress Controller é acessível via NodePort. Primeiro, identifique as portas:

```bash
# Obter as portas NodePort do Ingress Controller
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}'
```

**Saída esperada:**
```
31080
```

```bash
# Obter a porta HTTPS
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}'
```

**Saída esperada:**
```
31443
```

> **Nota**: As portas NodePort são atribuídas dinamicamente (range 30000-32767). Os valores acima são exemplos — use os valores reais retornados pelos comandos.

Defina variáveis para facilitar os testes (substitua pelos valores reais):

```bash
# Definir variáveis para os testes
# Use o IP público do worker node (de variables.env ou aws ec2 describe-instances)
NODE_IP="${WORKER_NODE_IP}"
HTTP_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo "Ingress HTTP:  http://${NODE_IP}:${HTTP_PORT}"
echo "Ingress HTTPS: https://${NODE_IP}:${HTTPS_PORT}"
```

**Saída esperada:**
```
Ingress HTTP:  http://<WORKER_IP>:31080
Ingress HTTPS: https://<WORKER_IP>:31443
```

---

### Teste 1: Path-Based Routing

Envie requisições HTTP para os paths `/app1` e `/app2` e verifique que cada um retorna a resposta do backend correto:

```bash
# Testar roteamento para /app1
curl http://${NODE_IP}:${HTTP_PORT}/app1
```

**Saída esperada:**
```
Hello from App 1
```

A resposta `Hello from App 1` confirma que o path `/app1` foi roteado corretamente para o `app1-service`.

```bash
# Testar roteamento para /app2
curl http://${NODE_IP}:${HTTP_PORT}/app2
```

**Saída esperada:**
```
Hello from App 2
```

A resposta `Hello from App 2` confirma que o path `/app2` foi roteado corretamente para o `app2-service`.

```bash
# Testar path inexistente (deve retornar 404)
curl -s -o /dev/null -w "%{http_code}" http://${NODE_IP}:${HTTP_PORT}/inexistente
```

**Saída esperada:**
```
404
```

O código 404 confirma que paths não configurados não são roteados para nenhum backend.

---

### Teste 2: Host-Based Routing

Envie requisições com diferentes headers `Host` para verificar o roteamento por hostname:

```bash
# Testar roteamento para app1.example.com
curl -H "Host: app1.example.com" http://${NODE_IP}:${HTTP_PORT}/
```

**Saída esperada:**
```
Hello from App 1
```

A resposta confirma que requisições com `Host: app1.example.com` são roteadas para `app1-service`.

```bash
# Testar roteamento para app2.example.com
curl -H "Host: app2.example.com" http://${NODE_IP}:${HTTP_PORT}/
```

**Saída esperada:**
```
Hello from App 2
```

A resposta confirma que requisições com `Host: app2.example.com` são roteadas para `app2-service`.

```bash
# Testar host não configurado (deve retornar 404)
curl -s -o /dev/null -w "%{http_code}" -H "Host: unknown.example.com" http://${NODE_IP}:${HTTP_PORT}/
```

**Saída esperada:**
```
404
```

---

### Teste 3: TLS Termination (HTTPS)

Teste o acesso HTTPS usando o certificado auto-assinado. A flag `-k` ignora a validação do certificado (necessário para certificados auto-assinados):

```bash
# Testar HTTPS para app1.example.com
curl -k -H "Host: app1.example.com" https://${NODE_IP}:${HTTPS_PORT}/
```

**Saída esperada:**
```
Hello from App 1
```

```bash
# Testar HTTPS para app2.example.com
curl -k -H "Host: app2.example.com" https://${NODE_IP}:${HTTPS_PORT}/
```

**Saída esperada:**
```
Hello from App 2
```

Verifique o certificado apresentado pelo Ingress Controller:

```bash
# Inspecionar o certificado TLS apresentado
openssl s_client -connect ${NODE_IP}:${HTTPS_PORT} -servername app1.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

**Saída esperada:**
```
subject=CN = app1.example.com, O = k8s-lab
issuer=CN = app1.example.com, O = k8s-lab
notBefore=Jan  1 00:00:00 2024 GMT
notAfter=Jan  1 00:00:00 2025 GMT
```

A linha-chave é `subject=CN = app1.example.com` — confirma que o Ingress Controller está usando o certificado correto.

#### Testar redirecionamento HTTP → HTTPS

A annotation `ssl-redirect: "true"` faz o Ingress redirecionar requisições HTTP para HTTPS:

```bash
# Testar redirecionamento (deve retornar 308 Permanent Redirect)
curl -s -o /dev/null -w "%{http_code}" -H "Host: app1.example.com" http://${NODE_IP}:${HTTP_PORT}/
```

**Saída esperada:**
```
308
```

> **Nota**: O código 308 indica redirecionamento permanente para HTTPS. O `tls-ingress` tem precedência sobre o `host-based-ingress` para os mesmos hosts quando ambos existem. Se quiser testar o host-based routing sem TLS, delete o `tls-ingress` primeiro: `kubectl delete ingress tls-ingress`.

---

### Teste 4: Verificação completa com script

Execute o script abaixo para validar todos os cenários de uma vez:

```bash
#!/bin/bash
echo "=== Verificação do Ingress Controller ==="
echo ""

# Obter variáveis
NODE_IP="${WORKER_NODE_IP}"
HTTP_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo "Node IP: ${NODE_IP}"
echo "HTTP Port: ${HTTP_PORT}"
echo "HTTPS Port: ${HTTPS_PORT}"
echo ""

# Teste 1: Path-based routing
echo -n "[1/6] Path /app1........... "
RESP=$(curl -s http://${NODE_IP}:${HTTP_PORT}/app1)
if echo "$RESP" | grep -q "App 1"; then
    echo "✅ OK ($RESP)"
else
    echo "❌ FALHOU (resposta: $RESP)"
fi

echo -n "[2/6] Path /app2........... "
RESP=$(curl -s http://${NODE_IP}:${HTTP_PORT}/app2)
if echo "$RESP" | grep -q "App 2"; then
    echo "✅ OK ($RESP)"
else
    echo "❌ FALHOU (resposta: $RESP)"
fi

# Teste 2: Host-based routing
echo -n "[3/6] Host app1............ "
RESP=$(curl -s -H "Host: app1.example.com" http://${NODE_IP}:${HTTP_PORT}/)
if echo "$RESP" | grep -q "App 1"; then
    echo "✅ OK ($RESP)"
else
    echo "❌ FALHOU (resposta: $RESP)"
fi

echo -n "[4/6] Host app2............ "
RESP=$(curl -s -H "Host: app2.example.com" http://${NODE_IP}:${HTTP_PORT}/)
if echo "$RESP" | grep -q "App 2"; then
    echo "✅ OK ($RESP)"
else
    echo "❌ FALHOU (resposta: $RESP)"
fi

# Teste 3: TLS
echo -n "[5/6] HTTPS app1........... "
RESP=$(curl -sk -H "Host: app1.example.com" https://${NODE_IP}:${HTTPS_PORT}/)
if echo "$RESP" | grep -q "App 1"; then
    echo "✅ OK ($RESP)"
else
    echo "❌ FALHOU (resposta: $RESP)"
fi

echo -n "[6/6] HTTPS app2........... "
RESP=$(curl -sk -H "Host: app2.example.com" https://${NODE_IP}:${HTTPS_PORT}/)
if echo "$RESP" | grep -q "App 2"; then
    echo "✅ OK ($RESP)"
else
    echo "❌ FALHOU (resposta: $RESP)"
fi

echo ""
echo "=== Verificação concluída ==="
```

**Saída esperada (todos os testes passando):**
```
=== Verificação do Ingress Controller ===

Node IP: <WORKER_IP>
HTTP Port: 31080
HTTPS Port: 31443

[1/6] Path /app1........... ✅ OK (Hello from App 1)
[2/6] Path /app2........... ✅ OK (Hello from App 2)
[3/6] Host app1............ ✅ OK (Hello from App 1)
[4/6] Host app2............ ✅ OK (Hello from App 2)
[5/6] HTTPS app1........... ✅ OK (Hello from App 1)
[6/6] HTTPS app2........... ✅ OK (Hello from App 2)

=== Verificação concluída ===
```

## Troubleshooting

### Problema: Ingress Controller Pod não inicia (CrashLoopBackOff)

**Sintoma:**
```
NAME                                        READY   STATUS             RESTARTS   AGE
ingress-nginx-controller-xxxxxxxxx-xxxxx    0/1     CrashLoopBackOff   3          2m
```

**Causa provável:** O Ingress Controller não consegue se conectar ao kube-apiserver, ou há conflito de portas no nó.

**Resolução:**
```bash
# Verificar logs do Pod para identificar o erro
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# Verificar eventos do Pod
kubectl describe pod -n ingress-nginx -l app.kubernetes.io/component=controller

# Verificar se as portas 80/443 não estão em uso no nó
ssh ubuntu@${WORKER_NODE_IP} "sudo ss -tlnp | grep -E ':80|:443'"

# Se houver conflito de porta, o manifesto baremetal usa NodePort (30000+)
# Verifique se o range NodePort está aberto no security group
aws ec2 describe-security-groups --group-ids <SG_ID> \
  --query 'SecurityGroups[].IpPermissions[?FromPort==`30000`]'
```

---

### Problema: Requisição ao Ingress retorna 404

**Sintoma:**
```bash
curl http://${NODE_IP}:${HTTP_PORT}/app1
# Retorna: <html><body><h1>404 Not Found</h1></body></html>
```

**Causa provável:** O Ingress resource não foi processado pelo controller, o path não corresponde à regra configurada, ou o backend Service não tem endpoints.

**Resolução:**
```bash
# Verificar se o Ingress foi aceito pelo controller (deve ter ADDRESS preenchido)
kubectl get ingress path-based-ingress

# Se ADDRESS estiver vazio, verificar IngressClass
kubectl get ingress path-based-ingress -o jsonpath='{.spec.ingressClassName}'
# Deve retornar: nginx

# Verificar se o Service backend tem endpoints
kubectl get endpoints app1-service
# Deve mostrar IPs de Pods — se vazio, o Service não encontra Pods

# Verificar labels dos Pods vs selector do Service
kubectl get pods -l app=app1 --show-labels
kubectl get svc app1-service -o jsonpath='{.spec.selector}'

# Verificar logs do Ingress Controller para erros de configuração
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller | grep -i error
```

---

### Problema: Ingress retorna 503 Service Temporarily Unavailable

**Sintoma:**
```bash
curl http://${NODE_IP}:${HTTP_PORT}/app1
# Retorna: <html><body><h1>503 Service Temporarily Unavailable</h1></body></html>
```

**Causa provável:** O backend Service existe mas não tem endpoints disponíveis (Pods não estão Running ou labels não correspondem ao selector do Service).

**Resolução:**
```bash
# Verificar se o Service tem endpoints
kubectl get endpoints app1-service
# Se ENDPOINTS estiver <none>, o Service não encontra Pods

# Verificar status dos Pods do backend
kubectl get pods -l app=app1
# Pods devem estar Running e Ready

# Se Pods estão em CrashLoopBackOff, verificar logs
kubectl logs -l app=app1

# Verificar se o selector do Service corresponde às labels dos Pods
kubectl get svc app1-service -o yaml | grep -A5 selector
kubectl get pods -l app=app1 --show-labels

# Recriar o Deployment se necessário
kubectl rollout restart deployment app1
```

---

### Problema: TLS não funciona — conexão recusada na porta HTTPS

**Sintoma:**
```bash
curl -k https://${NODE_IP}:${HTTPS_PORT}/
# curl: (7) Failed to connect to <IP> port 31443: Connection refused
```

**Causa provável:** A porta HTTPS NodePort não está aberta no security group da AWS, ou o Ingress Controller não está escutando na porta 443.

**Resolução:**
```bash
# Verificar se o Service tem a porta HTTPS configurada
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Deve mostrar 443:3XXXX/TCP

# Verificar se a porta NodePort está aberta no security group
aws ec2 describe-security-groups --group-ids <SG_ID> \
  --query 'SecurityGroups[].IpPermissions[?FromPort<=`31443` && ToPort>=`31443`]'

# Se a porta não estiver aberta, adicionar regra
aws ec2 authorize-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp \
  --port 30000-32767 \
  --cidr 0.0.0.0/0

# Verificar se o Ingress Controller está escutando em HTTPS
kubectl exec -n ingress-nginx -it $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o name) -- ss -tlnp | grep 443
```

---

### Problema: Certificado TLS incorreto apresentado (Fake Certificate)

**Sintoma:**
```bash
openssl s_client -connect ${NODE_IP}:${HTTPS_PORT} -servername app1.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject
# subject=O = Acme Co, CN = Kubernetes Ingress Controller Fake Certificate
```

**Causa provável:** O Ingress Controller não encontrou o Secret TLS referenciado no Ingress resource. Isso ocorre quando o Secret não existe, está em outro namespace, ou o nome está incorreto.

**Resolução:**
```bash
# Verificar se o Secret existe no namespace correto
kubectl get secret ingress-tls-secret -n default
# Deve retornar o Secret com TYPE kubernetes.io/tls

# Verificar se o Ingress referencia o Secret correto
kubectl get ingress tls-ingress -o jsonpath='{.spec.tls[0].secretName}'
# Deve retornar: ingress-tls-secret

# Verificar se o Secret contém dados válidos
kubectl get secret ingress-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject
# Deve mostrar: subject=CN = app1.example.com, O = k8s-lab

# Se o Secret estiver incorreto, recriar
kubectl delete secret ingress-tls-secret
kubectl create secret tls ingress-tls-secret --cert=tls-ingress.crt --key=tls-ingress.key

# Verificar logs do controller para erros de Secret
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller | grep -i "secret\|tls\|cert"
```

---

### Problema: Backend service não existe ou é inalcançável

**Sintoma:**
```
kubectl describe ingress path-based-ingress
# Events:
#   Warning  BackendNotFound  ingress-nginx-controller  service "app1-service" not found
```

Ou no log do controller:
```
upstream not found: default-app1-service-80
```

**Causa provável:** O Ingress resource referencia um Service que não existe no namespace especificado, ou o Service foi deletado após a criação do Ingress.

**Resolução:**
```bash
# Verificar se o Service existe
kubectl get svc app1-service
# Se retornar "not found", o Service precisa ser criado

# Verificar o namespace — o Service deve estar no mesmo namespace do Ingress
kubectl get ingress path-based-ingress -o jsonpath='{.metadata.namespace}'
kubectl get svc -n default app1-service

# Verificar se o Service tem a porta correta
kubectl get svc app1-service -o jsonpath='{.spec.ports[0].port}'
# Deve corresponder ao port.number no Ingress (80)

# Recriar o Service se necessário
kubectl expose deployment app1 --name=app1-service --port=80 --target-port=8080

# Verificar eventos do Ingress após correção
kubectl describe ingress path-based-ingress | grep -A5 Events
```

---

### Problema: Webhook de validação bloqueia criação de Ingress

**Sintoma:**
```
Error from server (InternalError): error when creating "ingress.yaml":
Internal error occurred: failed calling webhook "validate.nginx.ingress.kubernetes.io":
Post "https://ingress-nginx-controller-admission.ingress-nginx.svc:443/networking/v1/ingresses":
dial tcp 10.96.X.X:443: connect: connection refused
```

**Causa provável:** O webhook de validação do Ingress Controller não está acessível. Isso pode ocorrer se o Pod do controller não estiver rodando ou se o Service de admission não tiver endpoints.

**Resolução:**
```bash
# Verificar se o Pod do controller está Running
kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller

# Verificar se o Service de admission tem endpoints
kubectl get endpoints -n ingress-nginx ingress-nginx-controller-admission

# Se o controller não estiver rodando, verificar eventos
kubectl describe deployment -n ingress-nginx ingress-nginx-controller

# Solução temporária: deletar o webhook (permite criar Ingress sem validação)
kubectl delete validatingwebhookconfiguration ingress-nginx-admission

# Após o controller voltar a funcionar, reaplicar o manifesto para recriar o webhook
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.6/deploy/static/provider/baremetal/deploy.yaml
```

---

## Limpeza (Opcional)

Se desejar remover todos os recursos criados neste módulo:

```bash
# Remover Ingress resources
kubectl delete ingress path-based-ingress host-based-ingress tls-ingress

# Remover Secret TLS
kubectl delete secret ingress-tls-secret

# Remover backends
kubectl delete deployment app1 app2
kubectl delete service app1-service app2-service

# Remover NGINX Ingress Controller
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.6/deploy/static/provider/baremetal/deploy.yaml

# Remover arquivos de certificado locais
rm -f tls-ingress.key tls-ingress.crt
```

---

## Próximo Módulo

Após confirmar que o Ingress Controller está operacional e roteando tráfego corretamente, prossiga para:

➡️ [Módulo 14 — Validação do Cluster](../14-cluster-validation/)
