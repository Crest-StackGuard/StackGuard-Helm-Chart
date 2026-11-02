# Azure Marketplace (Helm + AKS Terraform only)

We maintain **Helm** + **AKS Terraform** knobs. Partner Center / CreateUIDefinition wiring is out of scope here — map the Marketplace UI to the values below.

## Both offers

| Offer | What runs | UI asks |
|-------|-----------|---------|
| **A** Helm on existing AKS | `helm install` + `values-aks.yaml` | App **CPU**, **RAM**, **disk** |
| **B** Create AKS + Helm | AKS Terraform (Ubuntu, autoscale off) then same Helm | Same + **node VM size** |

## Map UI → code

| UI field | Offer | Where |
|----------|-------|--------|
| App CPU | A, B | Helm `application.resources.requests.cpu` + `limits.cpu` |
| App RAM | A, B | Helm `application.resources.requests.memory` + `limits.memory` |
| App disk | A, B | Helm `application.persistence.size` |
| Node VM size | **B only** | AKS Terraform `node_vm_size` |

Example Helm overrides: [`../../helm/stackguard/values.marketplace.yaml.example`](../../helm/stackguard/values.marketplace.yaml.example)

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version <chart-version> \
  -f values-aks.yaml \
  -f values.marketplace.yaml \
  -f values.local.yaml   # secrets
```

## Fixed (not in UI)

| Rule | Enforcement |
|------|-------------|
| 1 app pod only | Helm `replicas: 1` (setting `application.replicas` fails) |
| Autoscale off | AKS `enable_auto_scaling=false` (`vmEnableAutoScale=false`) |
| Ubuntu only | AKS `os_sku=Ubuntu2204` + Helm `nodeSelector: stackguard.io/os=ubuntu` |
| **Subscription ID** | **IMDS only** (`169.254.169.254` + `Metadata: true`) — never Helm / Marketplace |

Confirm after install:

```bash
kubectl logs -n stackguard -l app=stackguard-application --tail=50 | grep -E 'Azure detected|provider='
# expect: Azure detected - ID: <subscriptionId>
```
