# Node Auto Provisioning with Spot Placement Scores

This directory contains everything needed to deploy an AKS cluster with Node Auto Provisioning (Karpenter) optimized using Azure Spot Placement Scores.

## Prerequisites

- Azure CLI installed and authenticated
- Terraform installed
- `jq`, `kubectl`, and `kubelogin` installed

## Files

| File                   | Description                                              |
|------------------------|----------------------------------------------------------|
| `main.tf`              | Terraform configuration for AKS cluster with NAP enabled |
| `variables.tf`         | Terraform variable definitions                           |
| `dev.tfvars`           | Example variable values                                  |
| `demo-deployment.yaml` | Sample workload for testing (uses Karpenter labels)      |

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
# 4. GENERATE KARPENTER NODEPOOL
# ============================================================
HIGH_SKUS=$(cat spot-placement-scores.json | jq -r '[.placementScores[] | select(.score == "High") | .sku] | unique | .[] | "        - " + .')

cat > node-pool.yaml << EOF
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-high-confidence
spec:
  disruption:
    budgets:
      - nodes: 30%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    spec:
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: default
      expireAfter: Never
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values:
        - amd64
      - key: kubernetes.io/os
        operator: In
        values:
        - linux
      - key: karpenter.sh/capacity-type
        operator: In
        values:
        - spot
      - key: karpenter.azure.com/sku-name
        operator: In
        values:
$HIGH_SKUS
EOF

cat node-pool.yaml

# ============================================================
# 5. APPLY TO CLUSTER
# ============================================================
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl apply -f node-pool.yaml

# ============================================================
# 6. TEST NODE PROVISIONING
# ============================================================
kubectl apply -f demo-deployment.yaml
kubectl scale deployment scaling-demo --replicas=20
kubectl get nodes -w
```

## Workload Requirements

Workloads must use Karpenter labels to be scheduled on spot nodes:

```yaml
nodeSelector:
  karpenter.sh/capacity-type: spot
tolerations:
- key: karpenter.sh/capacity-type
  operator: Equal
  value: spot
  effect: NoSchedule
```

## Cleanup

```bash
terraform destroy -var-file=dev.tfvars
```

## More Information

See the main [README.md](../README.md) for full documentation.
