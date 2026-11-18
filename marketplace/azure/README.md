# Azure Marketplace (Helm + AKS Terraform only)

We maintain **Helm** + **AKS Terraform** knobs. Partner Center / CreateUIDefinition wiring is out of scope here — map the Marketplace UI to the values below.

## Both offers

| Offer                      | What runs                                            | UI asks                        |
| -------------------------- | ---------------------------------------------------- | ------------------------------ |
| **A** Helm on existing AKS | `helm install` + `values-aks.yaml`                   | App **CPU**, **RAM**, **disk** |
| **B** Create AKS + Helm    | AKS Terraform (Ubuntu, autoscale off) then same Helm | Same + **node VM size**        |

Default chart ships **server**, **dashboard**, **Postgres**, and official **Valkey** (`valkey/valkey`). Marketplace UI collects `app-stackguardSecret`, `app-postgresPassword`, and `app-valkeyPassword`.

To use **managed** Azure Database for PostgreSQL + **Azure Cache for Redis** (Redis-compatible) instead of in-cluster Postgres/Valkey, set `postgres.enabled: false`, `valkey.enabled: false`, and supply `secrets.databaseUrl` + `secrets.redisUrl` (see [`../../helm/README.md`](../../helm/README.md#managed-postgres-and-cache)).

## Map UI → code

| UI field     | Offer      | Where                                                          |
| ------------ | ---------- | -------------------------------------------------------------- |
| App CPU      | A, B       | Helm `application.resources.requests.cpu` + `limits.cpu`       |
| App RAM      | A, B       | Helm `application.resources.requests.memory` + `limits.memory` |
| App disk     | A, B       | Helm `application.persistence.size`                            |
| Node VM size | **B only** | AKS Terraform `node_vm_size`                                   |

Example Helm overrides: [`../../helm/stackguard/values.marketplace.yaml.example`](../../helm/stackguard/values.marketplace.yaml.example)

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version <chart-version> \
  -f values-aks.yaml \
  -f values.marketplace.yaml \
  -f values.local.yaml   # secrets
```

## Fixed (not in UI)

| Rule                    | Enforcement                                                                     |
| ----------------------- | ------------------------------------------------------------------------------- |
| Monolithic (1 pod each) | Server, dashboard, Postgres, Valkey hard-locked to **1** replica (no HPA/VPA)   |
| Autoscale off           | AKS node autoscaler default off; app pods never scale out                       |
| Ubuntu only             | AKS `os_sku=Ubuntu2204` + Helm `nodeSelector: stackguard.io/os=ubuntu`          |
| **Subscription ID**     | **IMDS only** (`169.254.169.254` + `Metadata: true`) — never Helm / Marketplace |

Confirm after install:

```bash
kubectl logs -n stackguard -l app=stackguard-server --tail=50 | grep -E 'Azure detected|provider='
# expect: Azure detected - ID: <subscriptionId>
```
