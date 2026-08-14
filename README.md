# OpenShift AI Reference — Model Serving with Token-Based Rate Limiting

This repository demonstrates how to deploy **OpenShift AI** with a language model served on CPU, exposed through **Red Hat Connectivity Link** with **per-user token counting and rate limiting**.

Everything is managed via GitOps (ArgoCD + Helm).

## Architecture

```
Client (HTTPS)
    │
    ▼
OpenShift Route (edge TLS)
    │
    ▼
Istio Gateway (RHCL/Kuadrant)
    ├── AuthPolicy      → API key validation (Authorino)
    ├── TokenRateLimitPolicy → per-user token counting (Limitador)
    │
    ▼
HTTPRoute → qwen-05b-predictor (vLLM on CPU)
    │
    ▼
Qwen 2.5 0.5B Instruct (OpenAI-compatible API)
```

## What's Deployed

| Component | Description |
|---|---|
| **OpenShift AI (RHOAI 3.4)** | AI platform with KServe in RawDeployment mode |
| **Qwen 2.5 0.5B Instruct** | Lightweight LLM running on CPU via vLLM |
| **Red Hat Connectivity Link** | API gateway with Authorino (auth) + Limitador (rate limiting) |
| **TokenRateLimitPolicy** | Automatic token counting from OpenAI `usage.total_tokens` response field |

## Prerequisites

- OpenShift 4.19+ cluster with `oc` CLI connected as `cluster-admin`
- No GPU required — the model runs on CPU
- Public GitHub repository (no ArgoCD authentication needed)

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/dsferreira54/openshift-ai-ref.git
cd openshift-ai-ref

# 2. Connect to your OpenShift cluster
oc login --server=https://api.your-cluster.example.com:6443

# 3. Run the deploy script (installs ArgoCD + creates Application)
bash deploy.sh

# 4. The RHOAI operator needs to be bootstrapped manually
#    (ArgoCD can't validate CRDs before the operator installs them)
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: openshift-operators
spec:
  channel: "stable-3.x"
  installPlanApproval: Automatic
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# 5. Wait for RHOAI CRDs to become available (~2 minutes)
until oc get crd datascienceclusters.datasciencecluster.opendatahub.io 2>/dev/null; do
  sleep 10
done

# 6. ArgoCD will automatically sync all remaining resources
#    Monitor progress in ArgoCD UI or:
oc get application openshift-ai-ref -n openshift-gitops -w
```

## Validating the Deployment

### 1. Check all components are running

```bash
# OpenShift AI operator
oc get csv -n openshift-operators | grep rhods

# Model serving
oc get inferenceservice -n ai-model-serving
oc get pods -n ai-model-serving

# Connectivity Link
oc get kuadrant -n kuadrant-system
oc get authpolicy,tokenratelimitpolicy -n ai-model-serving
```

### 2. Test API authentication

```bash
EP="https://ai-gateway.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"

# No key → 401
curl -sk "$EP/v1/models" -w "HTTP %{http_code}\n"

# Valid key → 200
curl -sk "$EP/v1/models" \
  -H "Authorization: Bearer sk-free-demo-key-openshift-ai-ref"
```

### 3. Test inference with token counting

```bash
curl -sk "$EP/v1/chat/completions" \
  -H "Authorization: Bearer sk-free-demo-key-openshift-ai-ref" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen-05b","max_tokens":50,"messages":[{"role":"user","content":"What is OpenShift?"}]}'
```

The response includes `usage.total_tokens` which the `TokenRateLimitPolicy` uses to count tokens against the user's budget.

### 4. Test rate limiting

With the default configuration:
- **Free tier**: 5,000 tokens per 24h
- **Pro tier**: 50,000 tokens per 24h

When the limit is exceeded, the gateway returns **HTTP 429 Too Many Requests**.

## Demo API Keys

| User | API Key | Tier | Token Limit |
|---|---|---|---|
| free-user-1 | `sk-free-demo-key-openshift-ai-ref` | free | 5,000 tokens/day |
| pro-user-1 | `sk-pro-demo-key-openshift-ai-ref` | pro | 50,000 tokens/day |

> **Note**: These are demo keys committed to a public repository. In production, use `oc create secret` to create keys out-of-band and never commit real secrets to Git.

## Configuration

All configuration is in `gitops/values.yaml`:

| Parameter | Description | Default |
|---|---|---|
| `openShiftAI.operator.channel` | RHOAI operator channel | `stable-3.x` |
| `modelServing.model.storageUri` | HuggingFace model URI | `hf://Qwen/Qwen2.5-0.5B-Instruct` |
| `modelServing.resources.*` | CPU/memory for model pod | 4-8 CPU, 8-16Gi |
| `connectivityLink.tokenLimits.free.*` | Free tier token budget | 5,000/24h |
| `connectivityLink.tokenLimits.pro.*` | Pro tier token budget | 50,000/24h |

## Repository Structure

```
openshift-ai-ref/
├── AGENTS.md                              # Agent guidelines and project rules
├── deploy.sh                              # Bootstrap script (ArgoCD + Application)
├── README.md                              # This file
├── .gitignore
└── gitops/
    ├── Chart.yaml
    ├── values.yaml                        # All configurable parameters
    ├── .helmignore
    └── templates/
        ├── 1-openshift-ai/
        │   ├── 0-operator.yaml            # RHOAI Subscription
        │   ├── 1-dsci.yaml                # DSCInitialization
        │   └── 2-dsc.yaml                 # DataScienceCluster
        ├── 2-model-serving/
        │   ├── 0-namespace.yaml           # ai-model-serving namespace
        │   ├── 1-serving-runtime.yaml     # vLLM CPU ServingRuntime
        │   └── 2-inference-service.yaml   # InferenceService (RawDeployment)
        └── 3-connectivity-link/
            ├── 0-namespace.yaml           # kuadrant-system namespace
            ├── 1-operator.yaml            # RHCL Subscription + OperatorGroup
            ├── 2-kuadrant.yaml            # Kuadrant CR + GatewayClass
            ├── 3-gateway.yaml             # Gateway API Gateway
            ├── 3a-gateway-route.yaml      # OpenShift Route for Gateway
            ├── 4-httproute.yaml           # HTTPRoute to model service
            ├── 5-auth-policy.yaml         # API key authentication
            ├── 6-token-rate-limit.yaml    # TokenRateLimitPolicy
            └── 7-api-keys.yaml            # Demo API key Secrets
```

## Technical Decisions

- **RawDeployment mode**: Avoids dependency on OpenShift Serverless and Service Mesh for KServe. The model runs as a standard Kubernetes Deployment.
- **vLLM CPU image**: Uses the official `registry.redhat.io/rhaii/vllm-cpu-rhel9` image from RHOAI 3.4. CPU inference is slower but works without GPU nodes.
- **GatewayClass `openshift-default`**: Uses the native OpenShift Gateway API controller (`openshift.io/gateway-controller/v1`), available on OCP 4.19+. RHCL provides the Istio data plane internally.
- **TokenRateLimitPolicy**: Automatically extracts `usage.total_tokens` from OpenAI-compatible responses. Zero configuration needed for token extraction — it works out of the box with vLLM.

## Known Limitations

- **CPU inference is slow** (~10-15 seconds per request). This is expected for a 0.5B model on CPU. Use GPU for production workloads.
- **Bootstrap requires manual operator installation**: The RHOAI operator Subscription must be applied before ArgoCD can sync CRD-dependent resources.
- **Demo API keys are in Git**: Real deployments should create API key secrets out-of-band using `oc create secret`.
