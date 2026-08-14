# AGENTS.md

## 1. Objetivo deste repositório

Este repositório mantém uma referência funcional de **OpenShift AI** executada em Red Hat OpenShift com implantação via GitOps (Argo CD + Helm).

O objetivo final é demonstrar, de forma reproduzível, como expor modelos de IA com **contagem e controle de tokens por usuário** utilizando **Red Hat Connectivity Link (RHCL)**.

A cadeia de valor completa é:

1. **OpenShift AI** — plataforma de IA sobre OpenShift.
2. **Modelo de linguagem** — um modelo leve do catálogo Red Hat, servido em CPU.
3. **Model as a Service (MaaS)** — exposição do modelo via inferência servida (KServe / vLLM).
4. **Connectivity Link** — gateway de API que expõe o modelo externamente com políticas de rate limiting e contagem de tokens por consumidor.

---

## 2. Estrutura autoritativa do repositório

A estrutura abaixo é autoritativa e não deve ser reorganizada sem solicitação explícita:

```text
openshift-ai-ref/
├── AGENTS.md
├── deploy.sh
├── .gitignore
├── README.md
└── gitops/
    ├── Chart.yaml
    ├── .helmignore
    ├── values.yaml
    └── templates/
        ├── 1-openshift-ai/
        │   ├── 0-operator.yaml
        │   ├── 1-dsci.yaml
        │   └── 2-dsc.yaml
        ├── 2-model-serving/
        │   ├── 0-namespace.yaml
        │   ├── 1-serving-runtime.yaml
        │   └── 2-inference-service.yaml
        └── 3-connectivity-link/
            ├── 0-namespace.yaml
            ├── 1-operator.yaml
            ├── 2-kuadrant.yaml
            ├── 3-gateway.yaml
            ├── 3a-gateway-route.yaml
            ├── 4-httproute.yaml
            ├── 5-auth-policy.yaml
            ├── 6-token-rate-limit.yaml
            └── 7-api-keys.yaml
```

Responsabilidades:

- `gitops/` — Helm Chart e manifestos declarativos do ambiente. Fonte de verdade para o Argo CD.
- `deploy.sh` — bootstrap do OpenShift GitOps (Argo CD) e criação da Application apontando para este repositório.
- `README.md` — guia de uso, validação e operação do projeto.
- `AGENTS.md` — regras, contexto e orientações para agentes de IA que trabalham neste repositório.

---

## 3. Fases do projeto

### Fase 1 — Estrutura básica e GitOps (concluída)

- [x] Criar a estrutura do repositório inspirada no padrão `rhbk-demo`.
- [x] Criar `deploy.sh` para instalar o Argo CD e apontar para este repositório.
- [x] Validar que o Argo CD sincroniza com o repositório.

### Fase 2 — OpenShift AI (concluída)

- [x] Instalar o operador OpenShift AI via manifestos no Helm chart (`stable-3.x`).
- [x] Criar o `DSCInitialization` com Service Mesh desabilitado (RawDeployment mode).
- [x] Criar o `DataScienceCluster` com KServe em modo RawDeployment, componentes mínimos.
- [x] Validar que o OpenShift AI está operacional.

### Fase 3 — Modelo em CPU (concluída)

- [x] Modelo selecionado: `Qwen/Qwen2.5-0.5B-Instruct` (0.5B parâmetros, público, compatível com CPU).
- [x] Runtime: `vllm-cpu-runtime` com imagem oficial `registry.redhat.io/rhaii/vllm-cpu-rhel9` (RHOAI 3.4).
- [x] `InferenceService` em modo RawDeployment com `storageUri: hf://Qwen/Qwen2.5-0.5B-Instruct`.
- [x] Validar que o modelo responde a requisições de inferência (API OpenAI-compatible).

### Fase 4 — Model as a Service (MaaS) (concluída)

- [x] Modelo exposto via Gateway API (Istio/RHCL) + OpenShift Route.
- [x] Endpoint externo: `https://ai-gateway.<ingressDomain>/v1/chat/completions`.
- [x] Validar endpoint de inferência acessível externamente.

### Fase 5 — Connectivity Link com contagem de tokens (concluída)

- [x] Instalar o Red Hat Connectivity Link (`rhcl-operator`, canal `stable`).
- [x] Criar `Kuadrant` CR e `GatewayClass` (`openshift-default`, controlador nativo OCP).
- [x] Configurar `Gateway` + `HTTPRoute` para o endpoint de inferência.
- [x] Implementar `AuthPolicy` com autenticação por API key (Secrets do Kubernetes).
- [x] Implementar `TokenRateLimitPolicy` com contagem automática de tokens (`usage.total_tokens`).
- [x] Criar consumidores: free (5.000 tokens/dia) e pro (50.000 tokens/dia).
- [x] Validar que a contagem de tokens funciona: requests dentro do limite retornam 200, acima retornam 429.

---

## 4. Princípios de conteúdo e reutilização

Todo conteúdo deve ser genérico e reaproveitável.

Não citar:

- Clientes reais.
- Instituições reais.
- Informações comerciais sensíveis.
- Dados pessoais reais.

Toda informação de negócio deve ser fictícia ou genérica.

---

## 5. Ambiente de trabalho

### Cluster OpenShift

- Cluster de **laboratório** — pode ser quebrado sem penalização.
- Sem GPU — modelos devem rodar em **CPU**.
- Acesso como `admin` via `oc` CLI.
- Se o cluster ficar inacessível, informar o operador para que suba um novo.

### Repositório GitHub

- Repositório público: `https://github.com/dsferreira54/openshift-ai-ref`
- Branch principal: `main`
- Credenciais do GitHub configuradas via credential helper (push automático).
- Commits e pushes são permitidos a qualquer momento.

### Argo CD

- Fonte de verdade para o estado do cluster.
- O `deploy.sh` instala o operador OpenShift GitOps e cria a Application.
- A Application aponta para o diretório `gitops/` deste repositório.
- O sync é automático com `prune: true` e `selfHeal: true`.

---

## 6. Regras de trabalho com GitOps

### Regra de ouro

> **Toda alteração no cluster deve estar refletida no repositório Git.**

O Argo CD é a fonte de verdade. Alterações manuais via `oc` são permitidas temporariamente para diagnóstico ou prototipação rápida, mas **devem ser transcritas para o Helm chart antes de considerar o trabalho concluído**.

### Fluxo permitido

1. Prototipar com `oc apply` diretamente no cluster (se necessário para agilidade).
2. Validar que funciona.
3. Transcrever para template Helm em `gitops/templates/`.
4. Commit e push.
5. Verificar sincronização no Argo CD.

### Argo CD pode ser pausado

- É permitido pausar o sync automático do Argo CD durante testes manuais.
- Reativar o sync após transcrever as alterações para o repositório.

---

## 7. Política de commits

### Regras

- Fazer commits incrementais e lógicos — nem muito grandes, nem triviais.
- Cada commit deve representar uma unidade coerente de trabalho.
- Mensagens de commit devem ser claras e descritivas.
- Commits e pushes podem ser feitos a qualquer momento.
- Não acumular muitas alterações em um único commit.
- Não fazer commit para alterar uma única linha, a menos que seja realmente necessário.

### Exemplos de bons commits

```text
feat: add initial project structure with Helm chart and deploy script
feat: add OpenShift AI operator subscription
fix: correct namespace reference in DataScienceCluster
docs: update README with deployment instructions
```

---

## 8. Documentação

- O `README.md` deve ser mantido atualizado com instruções de uso e estado atual do projeto.
- Linguagem clara e acessível.
- Documentar pré-requisitos, como executar o deploy, e como validar.

---

## 9. GitOps, Helm e OpenShift

Regras operacionais permanentes:

- O estado final deve estar descrito em `gitops/`.
- Não considerar alterações manuais no cluster como estado final.
- Toda correção manual para diagnóstico deve ser reproduzida no Helm chart.
- Argo CD deve permanecer como fonte de verdade de implantação.
- Templates Helm devem ser legíveis e sem complexidade desnecessária.
- Priorizar manifestos mínimos e funcionais.

Validação esperada:

- Chart renderiza sem erro (`helm template`).
- Argo CD sincroniza sem erros.
- Recursos ficam disponíveis no OpenShift.

---

## 10. Segurança e dados

Obrigatório:

- Usar apenas dados fictícios.
- Proteger segredos.
- Não comitar segredos reais.
- Não expor tokens ou credenciais em código ou documentação.

---

## 11. Forma de trabalho do agente

Antes de implementar:

1. Ler este `AGENTS.md`.
2. Examinar estado atual dos arquivos.
3. Relacionar a mudança a uma fase ou requisito do projeto.
4. Escolher a solução mais simples.
5. Evitar mudanças não solicitadas.

Durante:

1. Fazer mudanças incrementais.
2. Validar cada etapa (no cluster e/ou com `helm template`).
3. Não esconder falhas.
4. Registrar decisões relevantes.
5. Não introduzir dependências sem justificativa.
6. Não alterar estrutura sem autorização.

Depois:

1. Executar testes/validações aplicáveis.
2. Revisar o diff.
3. Verificar que não há segredos expostos.
4. Confirmar estado do Argo CD.
5. Informar limitações e riscos.

---

## 12. Formato de resposta esperado do agente

Ao concluir uma atividade, reportar:

### Objetivo

Problema resolvido.

### Alterações

Arquivos criados/modificados.

### Validação

Comandos e testes executados.

### Resultado

O que está funcionando.

### Limitações

O que não foi coberto.

### Riscos

Pontos de atenção.

### Próxima ação recomendada

Próximo passo lógico.

Regra:

- Não afirmar que funciona sem validação.

---

## 13. Restrições finais

Não fazer:

- Alterar `deploy.sh` sem solicitação explícita.
- Reorganizar estrutura do repositório sem solicitação explícita.
- Implementar complexidade fora do escopo da fase atual.
- Expor segredos, tokens ou credenciais.
- Usar dados reais.
- Tratar a demonstração como arquitetura final de produção.

---

## 14. Critérios de sucesso (visão final)

Ao final de todas as fases, uma pessoa deve conseguir:

1. Executar `deploy.sh` em um cluster OpenShift conectado via `oc`.
2. O Argo CD instala e sincroniza automaticamente todos os recursos.
3. O OpenShift AI fica operacional.
4. Um modelo leve (CPU) responde a requisições de inferência.
5. O Connectivity Link expõe o modelo com gateway de API.
6. Consumidores possuem limites de tokens configurados.
7. A contagem de tokens é aplicada e verificável.
8. Todo o estado está declarado no repositório Git.
