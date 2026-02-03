# Cluster Autoscaler with Spot Placement Scores

This directory contains everything needed to deploy an AKS cluster with Cluster Autoscaler optimized using Azure Spot Placement Scores.

## Prerequisites

- Azure CLI installed and authenticated
- Terraform installed
- `jq`, `kubectl`, and `kubelogin` installed

## Files

| File                   | Description                                                  |
|------------------------|--------------------------------------------------------------|
| `main.tf`              | Terraform configuration for AKS cluster with spot node pools |
| `variables.tf`         | Terraform variable definitions                               |
| `dev.tfvars`           | Example variable values                                      |
| `demo-deployment.yaml` | Sample workload for testing autoscaling                      |

## Quick Start

```bash
# ============================================================
# 1. DEPLOY INFRASTRUCTURE
# ============================================================
cp dev.tfvars.example dev.tfvars
# Edit dev.tfvars with your subscription_id, resource_group_name, etc.
terraform init
terraform apply -var-file=dev.tfvars

# ============================================================
# 2. CONFIGURE VARIABLES
# ============================================================
RESOURCE_GROUP="your-resource-group"      # Update with your values
CLUSTER_NAME="your-cluster-name"          # Update with your values
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
REGIONS='["westus3"]'
VM_SIZES='[{"sku":"Standard_D4as_v4"},{"sku":"Standard_D8as_v4"},{"sku":"Standard_D4as_v5"},{"sku":"Standard_D8as_v5"}]'
VM_COUNT=10

# ============================================================
# 3. QUERY SPOT PLACEMENT SCORES
# ============================================================
az compute-recommender spot-placement-score \
    --location westus3 \
    --subscription "$SUBSCRIPTION_ID" \
    --availability-zones true \
    --desired-locations "$REGIONS" \
    --desired-count "$VM_COUNT" \
    --desired-sizes "$VM_SIZES" \
    --output json | tee spot-placement-scores.json

cat spot-placement-scores.json | jq '.placementScores | group_by(.score) | map({score: .[0].score, skus: [.[].sku] | unique})'

# ============================================================
# 4. GENERATE PRIORITY EXPANDER CONFIGMAP
# ============================================================
# Extract SKUs and convert to regex patterns (Standard_D4as_v5 → d4asv5)
HIGH_PATTERNS=$(cat spot-placement-scores.json | jq -r '[.placementScores[] | select(.score == "High") | .sku | gsub("_"; "") | gsub("Standard"; "") | ascii_downcase | "    - .*" + . + ".*"] | unique | join("\n")')
MEDIUM_PATTERNS=$(cat spot-placement-scores.json | jq -r '[.placementScores[] | select(.score == "Medium") | .sku | gsub("_"; "") | gsub("Standard"; "") | ascii_downcase | "    - .*" + . + ".*"] | unique | join("\n")')

cat > cluster-autoscaler-priority-expander.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |-
    10:
    - .*default.*
    20:
$MEDIUM_PATTERNS
    30:
$HIGH_PATTERNS
EOF

cat cluster-autoscaler-priority-expander.yaml

# ============================================================
# 5. APPLY TO CLUSTER
# ============================================================
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl apply -f cluster-autoscaler-priority-expander.yaml

# ============================================================
# 6. TEST AUTOSCALING
# ============================================================
kubectl apply -f demo-deployment.yaml
kubectl scale deployment scaling-demo --replicas=20
kubectl get nodes -w
```

## Priority Levels

| Priority | Description                       |
|----------|-----------------------------------|
| 30       | High-score spot pools (preferred) |
| 20       | Medium-score spot pools           |
| 10       | On-demand pools (fallback)        |

The Cluster Autoscaler will prefer higher priority pools when scaling up.

## Cleanup

```bash
terraform destroy -var-file=dev.tfvars
```

## More Information

See the main [README.md](../README.md) for full documentation.
