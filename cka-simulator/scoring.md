# Sistema de Pontuação — Simulado CKA

## Visão Geral

A pontuação do exame simulado é baseada em um sistema de **checklist por tarefa**, onde cada tarefa define comandos de verificação específicos e seus resultados esperados. O candidato executa os comandos de verificação e determina se passou ou falhou em cada tarefa.

A nota final é calculada como uma **porcentagem ponderada por domínio**, refletindo a distribuição de pesos do exame CKA real.

---

## Pesos por Domínio

| # | Domínio | Peso | Tarefas |
|---|---------|------|---------|
| 1 | **Cluster Architecture, Installation & Configuration** | 25% | Tasks 01–04 |
| 2 | **Workloads & Scheduling** | 15% | Tasks 05–07 |
| 3 | **Services & Networking** | 20% | Tasks 08–10 |
| 4 | **Storage** | 10% | Tasks 11–12 |
| 5 | **Troubleshooting** | 30% | Tasks 13–17 |
| | **TOTAL** | **100%** | |

---

## Mecanismo de Pontuação por Checklist

### Como Funciona

Para cada tarefa, existe um conjunto de **comandos de verificação** que validam se a tarefa foi concluída corretamente. O candidato deve:

1. Executar cada comando de verificação listado na tarefa
2. Comparar a saída com o resultado esperado
3. Marcar a tarefa como **PASS** (✅) ou **FAIL** (❌)

### Critérios de Avaliação por Tarefa

Uma tarefa é considerada **PASS** quando:
- **Todos** os comandos de verificação retornam o resultado esperado
- Os recursos criados estão no estado correto (Running, Ready, etc.)
- As configurações aplicadas estão ativas e funcionais

Uma tarefa é considerada **FAIL** quando:
- **Qualquer** comando de verificação retorna resultado diferente do esperado
- Recursos não foram criados ou estão em estado incorreto
- A tarefa não foi completada dentro do tempo total do exame

---

## Checklist de Pontuação

Preencha esta tabela após concluir o exame:

### Domínio 1: Cluster Architecture, Installation & Configuration (25%)

| Tarefa | Descrição | Tempo Rec. | Resultado |
|--------|-----------|------------|-----------|
| Task 01 | Backup e Restore do etcd | 10 min | ⬜ PASS / ⬜ FAIL |
| Task 02 | Gerenciamento de Certificados TLS | 10 min | ⬜ PASS / ⬜ FAIL |
| Task 03 | Upgrade de Componentes do Cluster | 8 min | ⬜ PASS / ⬜ FAIL |
| Task 04 | Configuração de RBAC | 7 min | ⬜ PASS / ⬜ FAIL |

**Tarefas aprovadas neste domínio:** ___/4

### Domínio 2: Workloads & Scheduling (15%)

| Tarefa | Descrição | Tempo Rec. | Resultado |
|--------|-----------|------------|-----------|
| Task 05 | Scaling e Rollback de Deployment | 8 min | ⬜ PASS / ⬜ FAIL |
| Task 06 | Criação e Gerenciamento de DaemonSet | 7 min | ⬜ PASS / ⬜ FAIL |
| Task 07 | Node Affinity, Taints e Tolerations | 8 min | ⬜ PASS / ⬜ FAIL |

**Tarefas aprovadas neste domínio:** ___/3

### Domínio 3: Services & Networking (20%)

| Tarefa | Descrição | Tempo Rec. | Resultado |
|--------|-----------|------------|-----------|
| Task 08 | Criar e Expor Services (ClusterIP e NodePort) | 8 min | ⬜ PASS / ⬜ FAIL |
| Task 09 | Configurar NetworkPolicy para Isolamento de Tráfego | 10 min | ⬜ PASS / ⬜ FAIL |
| Task 10 | Configurar Ingress com Roteamento por Path e Troubleshooting DNS | 8 min | ⬜ PASS / ⬜ FAIL |

**Tarefas aprovadas neste domínio:** ___/3

### Domínio 4: Storage (10%)

| Tarefa | Descrição | Tempo Rec. | Resultado |
|--------|-----------|------------|-----------|
| Task 11 | | 8 min | ⬜ PASS / ⬜ FAIL |
| Task 12 | | 7 min | ⬜ PASS / ⬜ FAIL |

**Tarefas aprovadas neste domínio:** ___/2

### Domínio 5: Troubleshooting (30%)

| Tarefa | Descrição | Tempo Rec. | Resultado |
|--------|-----------|------------|-----------|
| Task 13 | Debugging de Pod em CrashLoopBackOff | 8 min | ⬜ PASS / ⬜ FAIL |
| Task 14 | Troubleshooting de Node NotReady | 7 min | ⬜ PASS / ⬜ FAIL |
| Task 15 | Troubleshooting de Conectividade de Rede entre Pods | 8 min | ⬜ PASS / ⬜ FAIL |
| Task 16 | Troubleshooting de Componente do Control Plane (kube-scheduler) | 7 min | ⬜ PASS / ⬜ FAIL |
| Task 17 | Troubleshooting de Falha em Deployment de Aplicação | 6 min | ⬜ PASS / ⬜ FAIL |

**Tarefas aprovadas neste domínio:** ___/5

---

## Cálculo da Nota Final

### Fórmula

A nota final é calculada pela média ponderada das taxas de aprovação por domínio:

```
Nota Final = Σ (Taxa de Aprovação do Domínio × Peso do Domínio)
```

Onde:

```
Taxa de Aprovação do Domínio = (Tarefas PASS no Domínio) / (Total de Tarefas no Domínio)
```

### Exemplo de Cálculo

Suponha os seguintes resultados:

| Domínio | Tarefas PASS | Total | Taxa | Peso | Contribuição |
|---------|-------------|-------|------|------|--------------|
| Cluster Architecture | 3 | 4 | 75% | 25% | 18,75% |
| Workloads & Scheduling | 2 | 3 | 67% | 15% | 10,00% |
| Services & Networking | 2 | 3 | 67% | 20% | 13,33% |
| Storage | 1 | 2 | 50% | 10% | 5,00% |
| Troubleshooting | 4 | 5 | 80% | 30% | 24,00% |

**Nota Final = 18,75 + 10,00 + 13,33 + 5,00 + 24,00 = 71,08%**

### Fórmula Detalhada

```
Nota = (PASS_arch/4 × 25) + (PASS_work/3 × 15) + (PASS_net/3 × 20) + (PASS_stor/2 × 10) + (PASS_trouble/5 × 30)
```

Onde:
- `PASS_arch` = número de tarefas aprovadas em Cluster Architecture (0–4)
- `PASS_work` = número de tarefas aprovadas em Workloads & Scheduling (0–3)
- `PASS_net` = número de tarefas aprovadas em Services & Networking (0–3)
- `PASS_stor` = número de tarefas aprovadas em Storage (0–2)
- `PASS_trouble` = número de tarefas aprovadas em Troubleshooting (0–5)

---

## Resultado Final

Preencha após calcular sua nota:

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   NOTA FINAL: _______ %                        │
│                                                 │
│   RESULTADO:  ⬜ APROVADO (≥ 66%)              │
│               ⬜ REPROVADO (< 66%)             │
│                                                 │
│   Nota mínima para aprovação: 66%              │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## Análise por Domínio

Após calcular sua nota, identifique seus pontos fortes e fracos:

| Domínio | Sua Taxa | Meta (66%) | Status |
|---------|----------|------------|--------|
| Cluster Architecture | ___% | 66% | ⬜ Acima / ⬜ Abaixo |
| Workloads & Scheduling | ___% | 66% | ⬜ Acima / ⬜ Abaixo |
| Services & Networking | ___% | 66% | ⬜ Acima / ⬜ Abaixo |
| Storage | ___% | 66% | ⬜ Acima / ⬜ Abaixo |
| Troubleshooting | ___% | 66% | ⬜ Acima / ⬜ Abaixo |

### Plano de Estudo Recomendado

- **Domínios abaixo de 66%**: Revise os módulos correspondentes e refaça as tarefas após estudar as soluções.
- **Domínios entre 66% e 80%**: Pratique cenários adicionais para consolidar o conhecimento.
- **Domínios acima de 80%**: Bom domínio — mantenha a prática para não perder fluência.

### Mapeamento Domínio → Módulos de Estudo

| Domínio | Módulos para Revisão |
|---------|---------------------|
| Cluster Architecture | 02-tls-certificates, 04-etcd, 05-kube-apiserver, 14-cluster-validation |
| Workloads & Scheduling | 07-kube-scheduler, 08-kubelet, 03-container-runtime |
| Services & Networking | 09-kube-proxy, 10-cni-networking, 11-coredns, 13-ingress-controller |
| Storage | 04-etcd (backup/restore), 08-kubelet (volumes) |
| Troubleshooting | Todos os módulos (seções de Troubleshooting) |

---

## Notas Importantes

1. **Honestidade na auto-avaliação**: O sistema de checklist depende da sua honestidade ao comparar resultados. Não marque PASS se o resultado não corresponder exatamente ao esperado.

2. **Parcialidade não conta**: Uma tarefa é PASS ou FAIL — não existe pontuação parcial. Se 3 de 4 verificações passam mas 1 falha, a tarefa é FAIL.

3. **Refaça o simulado**: Após estudar as soluções e revisar os módulos, espere alguns dias e refaça o exame para medir sua evolução.

4. **Condições reais**: Para uma simulação mais realista, não pause o cronômetro e não consulte materiais além da documentação oficial do Kubernetes.
