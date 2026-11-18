# StackGuard on Kubernetes (Helm)

Deploy StackGuard with a single Helm release on any Kubernetes cluster (AKS, EKS, GKE, or on-prem).

**Chart:** `oci://public.ecr.aws/stackguard-io/stackguard` · **Artifact Hub:** [stackguard/stackguard](https://artifacthub.io/packages/helm/stackguard/stackguard)

**India regions (if using Terraform):** AKS `centralindia` · EKS `ap-south-1` · GKE `asia-south1`

---

## What you get

| Service                         | Port | Public?            |
| ------------------------------- | ---- | ------------------ |
| Server API                      | 8080 | Yes (LoadBalancer) |
| Dashboard                       | 4000 | Yes (LoadBalancer) |
| Postgres                        | 5432 | No (internal only) |
| Valkey (Redis-compatible cache) | 6379 | No (internal only) |

- Server + dashboard images from public ECR (`v1.1.1`)
- Postgres 17 and **official Valkey** [`valkey/valkey:8`](https://hub.docker.com/r/valkey/valkey)
- Optional: disable in-cluster Postgres/Valkey and use **managed** Postgres + a **managed Redis-compatible cache** (for example Azure Database for PostgreSQL + Azure Cache for Redis) — see [Managed Postgres and cache](#managed-postgres-and-cache)
- No license key. Open the site → enter name and email → admin approves → sign in with the emailed password
- Cloud vs local is detected by the application from instance metadata (AWS account ID, Azure subscription ID, GCP project ID). Do not pass CSP or cloud id through Helm
- **Monolithic:** exactly **1** pod each for server, dashboard, Postgres, and Valkey. Setting `*.replicas` ≠ 1 fails the chart. Never run 2+ of any workload.
- No HPA, no VPA, no pod autoscaling. Prefer node autoscaling off. Scale **vertically** only (pod CPU/RAM + node VM size)
- Ubuntu only for the StackGuard node (`values-*-*.yaml` sets `application.nodeSelector.stackguard.io/os=ubuntu`)
- 10 GiB persistent disk per workload (override `application.persistence.size`)
- Azure Marketplace: see [`../marketplace/azure/README.md`](../marketplace/azure/README.md)

---

## Folder structure

```text
k8/helm/
├── README.md                 # This file — full install guide
└── stackguard/               # Helm chart source
    ├── Chart.yaml
    ├── values.yaml           # Defaults (committed)
    ├── values.local.yaml.example
    ├── values-aks.yaml       # storageClass: managed-csi
    ├── values-eks.yaml       # storageClass: gp3
    ├── values-gke.yaml       # storageClass: standard-rwo
    └── templates/
```

---

## Step 1 — Cluster access

You need a running Kubernetes cluster and `kubectl` / `helm` installed.

Optional: create AKS / EKS / GKE with Terraform under [`../infrastructure/`](../infrastructure/).

```bash
kubectl get nodes
```

---

## Step 2 — Prepare secrets and values

```bash
cd k8/helm/stackguard

cp values.local.yaml.example values.local.yaml
```

Generate secrets:

```bash
# STACKGUARD_SECRET — must be EXACTLY 32 characters
openssl rand -hex 16

# Postgres password
openssl rand -hex 16

# Valkey password
openssl rand -hex 16
```

Edit `values.local.yaml`:

```yaml
secrets:
  stackguardSecret: "<output-of-first-openssl-command>"
  postgres:
    password: "<output-of-second-openssl-command>"
  valkey:
    password: "<output-of-third-openssl-command>"
```

The chart auto-builds `STACKGUARD_DATABASE_URL` and `STACKGUARD_REDIS_URL` from the bundled Postgres/Valkey settings. If you set database URL manually for the in-cluster Postgres, it **must** end with `?sslmode=disable`:

```text
postgresql://stackguard:<password>@stackguard-postgres:5432/stackguard?sslmode=disable
```

### Managed Postgres and cache

To use **managed Postgres** and a **managed Redis-compatible cache** (for example Azure Database for PostgreSQL + Azure Cache for Redis) instead of the in-cluster containers:

```yaml
postgres:
  enabled: false
valkey:
  enabled: false
secrets:
  databaseUrl: postgresql://user:pass@my-pg.postgres.database.azure.com:5432/stackguard?sslmode=require
  redisUrl: rediss://:accesskey@my-cache.redis.cache.windows.net:6380/0
```

Leave `postgres.enabled` / `valkey.enabled` at `true` (default) for the bundled containers.

---

## Step 3 — Install StackGuard

Pick the cloud overlay for your storage class, or set `global.storageClass` yourself.

### EKS

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.2.2 \
  -f values.local.yaml \
  -f values-eks.yaml
```

### AKS

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.2.2 \
  -f values.local.yaml \
  -f values-aks.yaml
```

### GKE

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.2.2 \
  -f values.local.yaml \
  -f values-gke.yaml
```

### Without a values file (inline secrets)

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.2.2 \
  --set global.storageClass=gp3 \
  --set secrets.stackguardSecret="$(openssl rand -hex 16)" \
  --set secrets.postgres.password="$(openssl rand -hex 16)" \
  --set secrets.valkey.password="$(openssl rand -hex 16)"
```

No Helm registry login is required — chart and app images are on **public ECR**.

---

## Step 4 — Wait for pods

```bash
kubectl get pods -n stackguard -w
```

Expected:

```text
stackguard-server-...     1/1   Running
stackguard-dashboard-...  1/1   Running
stackguard-postgres-0     1/1   Running
stackguard-valkey-0       1/1   Running
```

Press `Ctrl+C` to stop watching.

---

## Step 5 — Get the LoadBalancer IP and set the URL

```bash
kubectl get svc -n stackguard stackguard-server
```

Copy the **EXTERNAL-IP** (or hostname). Update `values.local.yaml`:

```yaml
urls:
  application: http://<application-ip>:8080
```

Upgrade the release and restart:

```bash
helm upgrade stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.2.2 \
  -f values.local.yaml \
  -f values-eks.yaml

kubectl rollout restart deployment -n stackguard stackguard-server
```

Confirm the app detected the cloud tenant (no env vars needed):

```bash
kubectl logs -n stackguard -l app=stackguard-server --tail=50 | grep -E 'AWS detected|Azure detected|GCP detected|provider='
```

Open in the browser: **http://\<application-ip\>:8080**

Enter name and email for approval. After approval, refresh and sign in with the emailed password.

---

## Step 6 — Verify

```bash
kubectl get pods -n stackguard
kubectl get svc -n stackguard
kubectl get pvc -n stackguard
helm status stackguard -n stackguard
```

### Logs

```bash
kubectl logs -n stackguard -l app=stackguard-server --tail=100
kubectl logs -n stackguard stackguard-postgres-0 --tail=100
```

### After a crash

```bash
kubectl logs -n stackguard -l app=stackguard-server --previous
kubectl describe pod -n stackguard -l app=stackguard-server
```

---

## Scale (machine size only — never more pods)

StackGuard is **monolithic**: server and dashboard are hard-locked to **1 replica each** (same for Postgres and Valkey). Do **not** add HPA/VPA or raise `replicas`. Raise resources, then enlarge the node:

```yaml
server:
  resources:
    requests: { cpu: "4", memory: 8Gi }
    limits: { cpu: "4", memory: 8Gi }
dashboard:
  resources:
    requests: { cpu: "2", memory: 4Gi }
    limits: { cpu: "2", memory: 4Gi }
```

```bash
helm upgrade stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.2.2 \
  -f values.local.yaml \
  -f values-eks.yaml

kubectl rollout restart deployment -n stackguard stackguard-server
```

Then increase the node VM in Terraform under [`../infrastructure/`](../infrastructure/) and run `terraform apply`.

---

## Upgrade to a new chart version

```bash
helm upgrade stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version <new-version> \
  -f values.local.yaml \
  -f values-eks.yaml
```

Pin the application tag for reproducible deploys:

```yaml
images:
  application:
    tag: "2.0.0"
```

---

## Uninstall

```bash
helm uninstall stackguard
kubectl delete namespace stackguard
```

PVCs inside the namespace are removed with the namespace. If you installed into an existing namespace with `createNamespace: false`, delete PVCs manually:

```bash
kubectl delete pvc -n stackguard --all
```

---

## Default sizing

Fits one **8 vCPU / 16 GiB** node with headroom for kube-system:

| Service   | CPU | RAM   | Disk   |
| --------- | --- | ----- | ------ |
| Server    | 2   | 4 GiB | 10 GiB |
| Dashboard | 1   | 2 GiB | —      |
| Postgres  | 2   | 4 GiB | 10 GiB |
| Valkey    | 1   | 2 GiB | 2 GiB  |

| Cloud | Recommended node VM                  | Storage class  |
| ----- | ------------------------------------ | -------------- |
| AKS   | `Standard_F8s_v2` (8 vCPU, 16 GiB)   | `managed-csi`  |
| EKS   | `c6i.2xlarge` (8 vCPU, 16 GiB)       | `gp3`          |
| GKE   | `e2-custom-8-16384` (8 vCPU, 16 GiB) | `standard-rwo` |

---

## Cloud detection (account / subscription / project ID)

StackGuard reads cloud identity from the node metadata service — **never** from Helm values:

| Cloud       | ID field        | Metadata endpoint                                      |
| ----------- | --------------- | ------------------------------------------------------ |
| AWS (EKS)   | Account ID      | `169.254.169.254` IMDSv2                               |
| Azure (AKS) | Subscription ID | `169.254.169.254` + `Metadata: true`                   |
| GCP (GKE)   | Project ID      | `metadata.google.internal` + `Metadata-Flavor: Google` |

Infrastructure requirements (covered by [`../infrastructure/`](../infrastructure/) Terraform):

- **EKS:** IMDS hop limit **2** (launch template). Allow egress to `169.254.169.254/32`.
- **AKS:** IMDS is available to pods by default. Do not block `169.254.169.254/32`.
- **GKE:** Node `workload_metadata_config.mode = GCE_METADATA`. Do not block metadata traffic.

## Common problems

| Problem                                | Fix                                                                                                                                                                                                                                              |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `global.storageClass is required`      | Pass `-f values-eks.yaml` (or aks/gke), or `--set global.storageClass=gp3`                                                                                                                                                                       |
| `secrets.stackguardSecret is required` | Set in `values.local.yaml` — exactly 32 chars (`openssl rand -hex 16`)                                                                                                                                                                           |
| `SSL is not enabled on the server`     | Database URL must end with `?sslmode=disable`                                                                                                                                                                                                    |
| Pod stuck `Pending`                    | Insufficient CPU on node — check `kubectl describe pod`, free resources or add nodes                                                                                                                                                             |
| LoadBalancer `<pending>`               | Wait 2–5 min; check cloud LB quota                                                                                                                                                                                                               |
| Config change not picked up            | `helm upgrade ...` then `kubectl rollout restart deployment/stackguard-server`                                                                                                                                                                   |
| Postgres crash — `lost+found`          | Delete StatefulSet + postgres PVC, then `helm upgrade` again                                                                                                                                                                                     |
| Image pull errors                      | Images are public — check network/egress to `public.ecr.aws`                                                                                                                                                                                     |
| Detects as `local` / missing cloud ID  | See **Cloud detection** above. On a live EKS node: `aws ec2 modify-instance-metadata-options --instance-id <id> --http-put-response-hop-limit 2 --http-tokens required`, then restart the app pod. Confirm NetworkPolicy allows metadata egress. |

---

## Key Helm values reference

| Value                         | Description                                                      |
| ----------------------------- | ---------------------------------------------------------------- |
| `global.storageClass`         | **Required.** PVC storage class for your cloud                   |
| `secrets.stackguardSecret`    | **Required.** 32-character app secret                            |
| `secrets.postgres.password`   | **Required** when using bundled Postgres                         |
| `secrets.valkey.password`     | **Required** when using bundled Valkey                           |
| `secrets.databaseUrl`         | Managed / external Postgres URL (set `postgres.enabled: false`)  |
| `secrets.redisUrl`            | Managed Redis-compatible cache URL (set `valkey.enabled: false`) |
| `urls.api` / `urls.dashboard` | Public URLs — set after LoadBalancers are ready                  |
| `images.server.tag`           | Server image tag (default: `v1.1.1`)                             |
| `images.dashboard.tag`        | Dashboard image tag (default: `v1.1.1`)                          |
| `images.valkey`               | Official Valkey image (`valkey/valkey:8`)                        |
| `postgres.enabled`            | Bundled Postgres (default `true`)                                |
| `valkey.enabled`              | Bundled Valkey (default `true`)                                  |
| `server.service.type`         | Default `LoadBalancer`                                           |
| `server.resources`            | CPU/RAM for the server pod                                       |
| `valkey.resources`            | CPU/RAM for the Valkey cache pod                                 |
| `networkPolicy.enabled`       | Permissive network policy (default `true`)                       |

Replicas are hardcoded to `1`. Setting `server.replicas` / `dashboard.replicas` (or postgres/valkey) to anything else **fails** the chart. `vpa.enabled` must stay `false`.

Full defaults: [`stackguard/values.yaml`](stackguard/values.yaml)

---

## Images and chart sources

| Artifact   | URI                                             |
| ---------- | ----------------------------------------------- |
| Helm chart | `oci://public.ecr.aws/stackguard-io/stackguard` |
| Server     | `public.ecr.aws/stackguard-io/server:v1.1.1`    |
| Dashboard  | `public.ecr.aws/stackguard-io/dashboard:v1.1.1` |
| Postgres   | `postgres:17` (Docker Hub)                      |
| Valkey     | `valkey/valkey:8` (official, Docker Hub)        |

---

## Local chart development

Install from the chart source instead of OCI:

```bash
cd stackguard
helm lint .
helm install stackguard . -f values.local.yaml -f values-eks.yaml
```

Publish a new version: see [`stackguard/README.md`](stackguard/README.md).

---

## Helm vs raw manifests

| Path                        | Use when                                                          |
| --------------------------- | ----------------------------------------------------------------- |
| **`k8/helm/`** (this guide) | Standard install — `helm install` / `helm upgrade` on any cluster |
| **`k8/kubernetes/`**        | Raw manifests + `envsubst` + `apply.sh`                           |
| **`k8/infrastructure/`**    | Terraform to create AKS / EKS / GKE clusters                      |

All three deploy the same StackGuard stack. **Use Helm for new deployments** unless you have a reason to use raw manifests.
