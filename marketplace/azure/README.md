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
| App CPU      | A, B       | Helm `server.resources.requests.cpu` + `limits.cpu`            |
| App RAM      | A, B       | Helm `server.resources.requests.memory` + `limits.memory`      |
| App disk     | A, B       | Helm `server.persistence.size`                                 |
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
| Ubuntu only             | AKS `os_sku=Ubuntu2204`; Helm `*.nodeSelector` optional (off by default)        |
| **Subscription ID**     | **IMDS only** (`169.254.169.254` + `Metadata: true`) — never Helm / Marketplace |

Confirm after install:

```bash
kubectl logs -n stackguard -l app=stackguard-server --tail=50 | grep -E 'Azure detected|provider='
# expect: Azure detected - ID: <subscriptionId>
```

## Build and publish the CNAB bundle

The bundle chart in `stackguard/` shares its templates with `helm/stackguard`; only `values.yaml` differs (images under `global.azure.images`, empty namespace).

1. Make template changes in `helm/stackguard`, then copy them across: `./sync-chart.sh`.
2. Lint: `helm lint ./stackguard`.
3. Bump `version` in `manifest.yaml` for every submission. CNAB tags are immutable once attached to an offer.
4. Build and push with the packaging tool (needs Docker on a linux/amd64 host): `./build-bundle.sh <acr-name>`. It runs `cpa verify` and `cpa buildbundle` in `mcr.microsoft.com/container-package-app`.
5. Reference the new bundle version from the Partner Center offer.

Every pod carries the `azure-extensions-usage-release-identifier` billing label when `global.azure` is set. All images, including Postgres and Valkey, are listed under `global.azure.images` so the packaging tool can copy them into the Microsoft registry; nothing is pulled from elsewhere at install time.
