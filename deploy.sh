#!/bin/bash

set -euo pipefail

INGRESS_DOMAIN="$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')"

echo "Ingress domain: ${INGRESS_DOMAIN}"

echo "Deploying ArgoCD operator..."

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "Waiting for ArgoCD openshift-gitops to become Available..."

until [ "$(oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.status.phase}' 2>/dev/null)" = "Available" ]; do
  sleep 10
done

echo "ArgoCD openshift-gitops is Available."

oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{
    "spec": {
      "controller": {
        "appSync": "5s"
      },
      "extraConfig": {
        "timeout.reconciliation.jitter": "0s"
      }
    }
  }'

echo "Granting cluster-admin to the ArgoCD application controller service account..."

oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-gitops-argocd-application-controller-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
EOF

oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-ai-ref
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/dsferreira54/openshift-ai-ref
    targetRevision: main
    path: gitops
    helm:
      parameters:
        - name: ingressDomain
          value: "${INGRESS_DOMAIN}"
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ApplyOutOfSyncOnly=true
EOF

ARGOCD_ADMIN_PASSWORD="$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d)"

echo ""
echo "Argo CD admin credentials:"
echo "  Username: admin"
if [ -n "$ARGOCD_ADMIN_PASSWORD" ]; then
  echo "  Password: ${ARGOCD_ADMIN_PASSWORD}"
else
  echo "  Error: unable to retrieve Argo CD admin password from secret openshift-gitops-cluster."
fi
ARGOCD_URL="$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null)"
if [ -n "$ARGOCD_URL" ]; then
  echo "  URL: https://${ARGOCD_URL}"
fi
