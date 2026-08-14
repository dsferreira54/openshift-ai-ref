# OpenShift AI Reference

Referência funcional de **OpenShift AI** sobre Red Hat OpenShift, com exposição de modelos de IA via **Red Hat Connectivity Link** e contagem de tokens por consumidor.

## Visão geral

Este projeto demonstra uma stack completa para servir modelos de IA com governança de uso:

| Camada | Tecnologia | Função |
|--------|-----------|--------|
| Plataforma de IA | OpenShift AI | Gerenciamento e serving de modelos |
| Modelo | Catálogo Red Hat (CPU) | Modelo leve para inferência sem GPU |
| Serving | KServe / vLLM | Model as a Service (MaaS) |
| Gateway | Connectivity Link (Kuadrant) | Rate limiting e contagem de tokens |
| GitOps | Argo CD + Helm | Implantação declarativa |

## Pré-requisitos

- Cluster Red Hat OpenShift (4.14+)
- CLI `oc` autenticado como administrador
- Acesso à internet (para pull de imagens e operadores)

> **Nota:** GPU não é necessária. O modelo selecionado roda em CPU.

## Deploy

1. Conecte-se ao cluster OpenShift:

```bash
oc login <cluster-api-url>
```

2. Execute o script de bootstrap:

```bash
./deploy.sh
```

O script irá:

- Instalar o operador OpenShift GitOps (Argo CD).
- Conceder permissões de cluster-admin ao controller do Argo CD.
- Criar uma Application apontando para o diretório `gitops/` deste repositório.
- Exibir as credenciais e URL do Argo CD.

3. Acompanhe a sincronização no Argo CD.

## Estrutura do repositório

```text
openshift-ai-ref/
├── AGENTS.md            # Orientações para agentes de IA
├── deploy.sh            # Bootstrap do Argo CD e Application
├── gitops/              # Helm chart (fonte de verdade)
│   ├── Chart.yaml
│   ├── .helmignore
│   ├── values.yaml
│   └── templates/
├── .gitignore
└── README.md
```

## Estado atual

- [x] Estrutura básica do repositório
- [x] Script `deploy.sh` para bootstrap do Argo CD
- [x] Helm chart base (vazio, pronto para receber templates)
- [ ] Operador OpenShift AI
- [ ] Modelo em CPU (inferência)
- [ ] Model as a Service (MaaS)
- [ ] Connectivity Link com contagem de tokens
