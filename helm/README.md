# Stackguard on Kubernetes (Helm)

Deploy Stackguard with a single Helm release on any Kubernetes cluster (AKS, EKS, GKE, or on-prem).

**Chart:** `oci://public.ecr.aws/stackguard-io/stackguard` · **Artifact Hub:** [stackguard/stackguard](https://artifacthub.io/packages/helm/stackguard/stackguard)

**India regions (if using Terraform):** AKS `centralindia` · EKS `ap-south-1` · GKE `asia-south1`

---

## What you get

| Service | Port | Public? |
|---------|------|---------|
| Dashboard | 4000 | Yes (LoadBalancer) |
| Server (API) | 8080 | Yes (LoadBalancer) |
| AI | 8000 | Yes (LoadBalancer) |
| Postgres | 5432 | No (internal only) |

- 1 pod per service (no horizontal scaling)
- 10 GiB persistent disk per workload
- Container images pulled from public ECR (no credentials needed)

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

**Never commit:** `values.local.yaml` (gitignored)

For cluster provisioning (Terraform), see [`../infrastructure/`](../infrastructure/) and [`../README.md`](../README.md).

For raw manifests without Helm, see [`../kubernetes/`](../kubernetes/).

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| **Helm** | 3.8+ | OCI chart install |
| **kubectl** | any recent | Cluster access |
| **Kubernetes cluster** | 1.24+ | With LoadBalancer support and a default or named storage class |

**Minimum node capacity:** 16 vCPU / 32 GiB RAM total across the cluster (see [Default sizing](#default-sizing)).

Optional (only if creating a new cluster):

- **Terraform** + cloud CLI (`az` / `aws` / `gcloud`) — see [`../README.md`](../README.md) Step 3

---

## End-to-end setup

```text
┌─────────────────────────────────────────────────────────────┐
│  1. Cluster ready (existing or Terraform)                   │
│  2. Prepare values.local.yaml (secrets + storage class)     │
│  3. helm install from public ECR                          │
│  4. Wait for LoadBalancer IPs                               │
│  5. helm upgrade with public URLs                           │
│  6. Open dashboard                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Step 1 — Cluster access

### Option A — Use an existing cluster

```bash
kubectl get nodes
kubectl get storageclass
```

Note your storage class name. You need one that supports `ReadWriteOnce` PVCs.

### Option B — Create a cluster with Terraform

Follow [`../README.md`](../README.md) Steps 1–3 for AKS, EKS, or GKE, then return here.

```bash
# Example (EKS)
cd ../infrastructure/eks/terraform
terraform init && terraform apply
aws eks update-kubeconfig --region ap-south-1 --name eks-stackguard-prod
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
```

Edit `values.local.yaml`:

```yaml
secrets:
  stackguardSecret: "<output-of-first-openssl-command>"
  postgres:
    password: "<output-of-second-openssl-command>"
```

The chart auto-builds `STACKGUARD_DATABASE_URL` from the postgres settings. If you set it manually, it **must** end with `?sslmode=disable`:

```text
postgresql://stackguard:<password>@stackguard-postgres:5432/stackguard?sslmode=disable
```

---

## Step 3 — Install Stackguard

Pick the cloud overlay for your storage class, or set `global.storageClass` yourself.

### EKS

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.1.0 \
  -f values.local.yaml \
  -f values-eks.yaml
```

### AKS

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.1.0 \
  -f values.local.yaml \
  -f values-aks.yaml
```

### GKE

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.1.0 \
  -f values.local.yaml \
  -f values-gke.yaml
```

### Without a values file (inline secrets)

```bash
helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.1.0 \
  --set global.storageClass=gp3 \
  --set secrets.stackguardSecret="$(openssl rand -hex 16)" \
  --set secrets.postgres.password="$(openssl rand -hex 16)"
```

No Helm registry login is required — chart and app images are on **public ECR**.

---

## Step 4 — Wait for pods

```bash
kubectl get pods -n stackguard -w
```

Expected:

```text
stackguard-dashboard-...   1/1   Running
stackguard-ai-...          1/1   Running
stackguard-server-...      1/1   Running
stackguard-postgres-0      1/1   Running
```

Press `Ctrl+C` to stop watching.

---

## Step 5 — Get LoadBalancer IPs and set URLs

```bash
kubectl get svc -n stackguard
```

Copy the **EXTERNAL-IP** (or hostname) for dashboard, server, and ai. Update `values.local.yaml`:

```yaml
urls:
  dashboard: http://<dashboard-ip>:4000
  api: http://<server-ip>:8080
  ai: http://<ai-ip>:8000
```

Upgrade the release and restart apps:

```bash
helm upgrade stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.1.0 \
  -f values.local.yaml \
  -f values-eks.yaml

kubectl rollout restart deployment -n stackguard \
  stackguard-dashboard stackguard-ai stackguard-server
```

Open in browser: **http://\<dashboard-ip\>:4000**

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
kubectl logs -n stackguard -l app=stackguard-dashboard --tail=100
kubectl logs -n stackguard -l app=stackguard-server --tail=100
kubectl logs -n stackguard -l app=stackguard-ai --tail=100
kubectl logs -n stackguard stackguard-postgres-0 --tail=100
```

### After a crash

```bash
kubectl logs -n stackguard -l app=stackguard-server --previous
kubectl describe pod -n stackguard -l app=stackguard-server
```

---

## Change CPU / RAM / storage

Edit `values.local.yaml` (or `values.yaml` defaults), then upgrade:

```yaml
server:
  resources:
    requests:
      cpu: "4"
      memory: 8Gi
    limits:
      cpu: "4"
      memory: 8Gi
  persistence:
    size: 20Gi
```

```bash
helm upgrade stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.1.0 \
  -f values.local.yaml \
  -f values-eks.yaml

kubectl rollout restart deployment -n stackguard \
  stackguard-dashboard stackguard-ai stackguard-server
```

To resize cluster nodes, update Terraform in [`../infrastructure/`](../infrastructure/) and run `terraform apply`.

---

## Upgrade to a new chart version

```bash
helm upgrade stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version <new-version> \
  -f values.local.yaml \
  -f values-eks.yaml
```

Pin image tags in `values.local.yaml` for reproducible deploys:

```yaml
images:
  dashboard:
    tag: "1.0.0"
  server:
    tag: "1.0.0"
  ai:
    tag: "1.0.0"
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

| Service | CPU | RAM | Disk |
|---------|-----|-----|------|
| Dashboard | 2 | 4 GiB | 10 GiB |
| AI | 2 | 4 GiB | 10 GiB |
| Server | 4 | 8 GiB | 10 GiB |
| Postgres | 2 | 4 GiB | 10 GiB |

**Total:** 10 vCPU requests, 20 GiB RAM requests (limits match requests).

| Cloud | Recommended node VM | Storage class |
|-------|---------------------|---------------|
| AKS | `Standard_D16s_v3` (16 vCPU) | `managed-csi` |
| EKS | `m6i.4xlarge` | `gp3` |
| GKE | `n2-standard-16` | `standard-rwo` |

---

## Common problems

| Problem | Fix |
|---------|-----|
| `global.storageClass is required` | Pass `-f values-eks.yaml` (or aks/gke), or `--set global.storageClass=gp3` |
| `secrets.stackguardSecret is required` | Set in `values.local.yaml` — exactly 32 chars (`openssl rand -hex 16`) |
| `SSL is not enabled on the server` | Database URL must end with `?sslmode=disable` |
| Pod stuck `Pending` | Insufficient CPU on node — check `kubectl describe pod`, free resources or add nodes |
| LoadBalancer `<pending>` | Wait 2–5 min; check cloud LB quota |
| Config change not picked up | `helm upgrade ...` then `kubectl rollout restart deployment ...` |
| Postgres crash — `lost+found` | Delete StatefulSet + postgres PVC, then `helm upgrade` again |
| Image pull errors | Images are public — check network/egress to `public.ecr.aws` |

---

## Key Helm values reference

| Value | Description |
|-------|-------------|
| `global.storageClass` | **Required.** PVC storage class for your cloud |
| `secrets.stackguardSecret` | **Required.** 32-character app secret |
| `secrets.postgres.password` | **Required.** Postgres password |
| `urls.dashboard/api/ai` | Public URLs — set after LoadBalancers are ready |
| `images.*.tag` | Pin image versions (default: `latest`) |
| `dashboard/server/ai.service.type` | Default `LoadBalancer` |
| `vpa.enabled` | Vertical Pod Autoscaler (default `false`) |
| `networkPolicy.enabled` | Permissive network policy (default `true`) |

Full defaults: [`stackguard/values.yaml`](stackguard/values.yaml)

---

## Images and chart sources

| Artifact | URI |
|----------|-----|
| Helm chart | `oci://public.ecr.aws/stackguard-io/stackguard` |
| Dashboard | `public.ecr.aws/stackguard-io/dashboard` |
| Server | `public.ecr.aws/stackguard-io/server` |
| AI | `public.ecr.aws/stackguard-io/ai` |
| Postgres | `postgres:16` (Docker Hub) |

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

| Path | Use when |
|------|----------|
| **`k8/helm/`** (this guide) | Standard install — `helm install` / `helm upgrade` on any cluster |
| **`k8/kubernetes/`** | Raw manifests + `envsubst` + `apply.sh` |
| **`k8/infrastructure/`** | Terraform to create AKS / EKS / GKE clusters |

All three deploy the same Stackguard stack. **Use Helm for new deployments** unless you have a reason to use raw manifests.
