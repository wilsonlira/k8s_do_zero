# Guia do Exame Simulado CKA

## Visão Geral

Este simulador reproduz as condições do exame **Certified Kubernetes Administrator (CKA)** da Linux Foundation/CNCF. O objetivo é avaliar sua capacidade de administrar um cluster Kubernetes em cenários práticos reais.

O exame simulado é composto por tarefas práticas que devem ser executadas diretamente no cluster construído durante este laboratório.

---

## Informações do Exame

| Item | Valor |
|------|-------|
| **Duração total** | 2 horas (120 minutos) |
| **Número de tarefas** | 15–17 tarefas |
| **Nota de aprovação** | 66% |
| **Formato** | Prático — execução de comandos no cluster |
| **Ambiente** | Cluster Kubernetes construído neste laboratório |
| **Recursos permitidos** | Documentação oficial do Kubernetes (kubernetes.io/docs) |

---

## Distribuição por Domínio

O exame cobre 5 domínios do CKA com os seguintes pesos:

| Domínio | Peso | Tempo Sugerido | Nº Aprox. de Tarefas |
|---------|------|----------------|----------------------|
| **Cluster Architecture, Installation & Configuration** | 25% | ~30 min | 4 tarefas |
| **Workloads & Scheduling** | 15% | ~18 min | 2–3 tarefas |
| **Services & Networking** | 20% | ~24 min | 3 tarefas |
| **Storage** | 10% | ~12 min | 2 tarefas |
| **Troubleshooting** | 30% | ~36 min | 4–5 tarefas |

> **Nota:** A distribuição de tempo é uma sugestão. Gerencie seu tempo conforme sua familiaridade com cada domínio.

---

## Instruções para o Candidato

### Antes de Começar

1. **Verifique o cluster** — Confirme que todos os componentes estão funcionando:
   ```bash
   kubectl get nodes
   kubectl get componentstatuses
   kubectl cluster-info
   ```

2. **Configure o ambiente** — Certifique-se de que o `kubectl` está configurado e acessível:
   ```bash
   kubectl config current-context
   ```

3. **Prepare um cronômetro** — Inicie um timer de 2 horas antes de começar a primeira tarefa.

4. **Tenha a documentação acessível** — Abra https://kubernetes.io/docs em uma aba do navegador (único recurso permitido).

### Durante o Exame

- **Leia cada tarefa completamente** antes de começar a executar comandos.
- **Observe o tempo recomendado** por tarefa — se estiver travado por mais de 5 minutos além do tempo sugerido, passe para a próxima tarefa e volte depois.
- **Execute os comandos diretamente no cluster** — todas as tarefas exigem ações práticas.
- **Não consulte as soluções** durante o exame — use-as apenas para auto-avaliação após concluir.
- **Anote tarefas puladas** para retornar a elas se sobrar tempo.

### Após o Exame

1. Execute os **comandos de verificação** de cada tarefa para determinar se passou ou falhou.
2. Preencha o **checklist de pontuação** em `scoring.md`.
3. Calcule sua **nota final** usando a fórmula de ponderação por domínio.
4. Consulte as **soluções** em `solutions/` para entender abordagens alternativas e aprender com erros.

---

## Formato das Tarefas

Cada tarefa segue esta estrutura:

```
# Tarefa XX — [Título]

**Domínio:** [Nome do Domínio]
**Peso:** [X%]
**Tempo recomendado:** [X minutos]

## Cenário
[Descrição do contexto e situação]

## Requisitos
[Lista do que deve ser feito]

## Comandos de Verificação
[Comandos que o candidato executa para auto-avaliar]
```

---

## Regras e Restrições

1. **Tempo máximo**: 2 horas. Após esse período, pare de executar tarefas.
2. **Recursos permitidos**: Apenas a documentação oficial em https://kubernetes.io/docs.
3. **Sem soluções durante o exame**: Não consulte `solutions/` até terminar todas as tarefas.
4. **Execução prática**: Todas as respostas devem ser implementadas no cluster — não basta "saber" a resposta.
5. **Ambiente limpo**: Não modifique recursos que não fazem parte da tarefa atual, a menos que explicitamente solicitado.
6. **Uma tentativa**: Simule condições reais — não refaça tarefas após consultar a solução.

---

## Dicas de Preparação

### Atalhos Úteis

```bash
# Alias recomendados (configure antes do exame)
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias ka='kubectl apply -f'

# Autocompletar kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

### Estratégia de Tempo

1. **Primeira passada (90 min)**: Resolva todas as tarefas que conseguir, pulando as que travarem.
2. **Segunda passada (30 min)**: Retorne às tarefas puladas com o tempo restante.
3. **Priorize tarefas de alto peso**: Troubleshooting (30%) e Cluster Architecture (25%) somam mais da metade da nota.

### Tópicos Essenciais para Revisar

- Criação e gerenciamento de Deployments, Services, e ConfigMaps
- Troubleshooting de pods (logs, describe, events)
- Configuração de NetworkPolicies
- Gerenciamento de PersistentVolumes e PersistentVolumeClaims
- Backup e restore do etcd
- Certificados TLS e kubeconfig
- RBAC (Roles, ClusterRoles, Bindings)
- Upgrade de cluster

---

## Critério de Aprovação

- **Nota mínima para aprovação: 66%**
- A nota é calculada com base nos pesos de cada domínio (não é uma média simples de tarefas)
- Consulte `scoring.md` para o cálculo detalhado da pontuação

---

## Próximos Passos

1. Leia este guia completamente
2. Verifique que seu cluster está funcional
3. Inicie o cronômetro de 2 horas
4. Comece pela tarefa `tasks/task-01.md`
5. Após concluir, use `scoring.md` para calcular sua nota
