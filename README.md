# StackGuard on Kubernetes (AKS / EKS / GKE)

Deploy StackGuard on managed Kubernetes. Same app manifests for all clouds — only the Terraform layer changes.

**Prefer Helm?** See [`helm/README.md`](helm/README.md) for `helm install` from public ECR (recommended for new deployments).

**India regions (default):** AKS `centralindia` · EKS `ap-south-1` · GKE `asia-south1`

---

## What you get

| Service                         | Port | Public?            |
| ------------------------------- | ---- | ------------------ |
| Server API                      | 8080 | Yes (LoadBalancer) |
| Dashboard                       | 4000 | Yes (LoadBalancer) |
| Postgres                        | 5432 | No (internal only) |
| Valkey (Redis-compatible cache) | 6379 | No (internal only) |

- Server + dashboard images: `public.ecr.aws/stackguard-io/server:v1.1.1` and `.../dashboard:v1.1.1`
- Postgres 17 and **official Valkey** [`valkey/valkey:8`](https://hub.docker.com/r/valkey/valkey) (in-cluster by default)
- **Optional managed data plane:** use managed Postgres + a managed Redis-compatible cache (for example Azure Database for PostgreSQL + Azure Cache for Redis) instead of the in-cluster containers — see [Managed Postgres and cache](#managed-postgres-and-cache)
- No license key. After start, open the site, enter name and email, wait for approval, then sign in with the emailed password.
- Cloud account vs local is detected by the application from instance metadata (AWS account ID, Azure subscription ID, GCP project ID). Do not pass CSP or cloud id env vars.
- **Monolithic:** exactly **1** pod each for server, dashboard, Postgres, and Valkey — never scale out pods
- No HPA, no VPA, no pod autoscaling. Prefer node autoscaling off (`vmEnableAutoScale=false`). Scale **vertically** only: raise CPU/RAM + node VM size
- Default **one node**: **8 vCPU, 16 GiB RAM** (EKS `c6i.2xlarge`, AKS `Standard_F8s_v2`, GKE `e2-custom-8-16384`)
- Default **pod requests**: server **2 CPU / 4 GiB**, dashboard **1 CPU / 2 GiB**, Postgres **2 CPU / 4 GiB**, Valkey **1 CPU / 2 GiB** (fits that node with kube-system headroom)
- Ubuntu only on the StackGuard node (AKS `Ubuntu2204`, GKE `UBUNTU_CONTAINERD`, EKS Canonical Ubuntu AMI — never Amazon Linux / Azure Linux / COS)
- 10 GiB persistent disk per service (app disk is user-overridable)
- Azure Marketplace (Helm + optional AKS create): [`marketplace/azure/README.md`](marketplace/azure/README.md)

---

## Managed Postgres and cache

You do **not** have to run Postgres or Valkey as containers in the cluster.

Prefer cloud-managed services when you can:

| Need     | Example (Azure)                          | What you set                                                                   |
| -------- | ---------------------------------------- | ------------------------------------------------------------------------------ |
| Database | Azure Database for PostgreSQL            | `STACKGUARD_DATABASE_URL` / Helm `secrets.databaseUrl`                         |
| Cache    | Azure Cache for Redis (Redis-compatible) | `STACKGUARD_REDIS_URL` / Helm `secrets.redisUrl` (`rediss://…` when TLS is on) |

**Helm:** disable the bundled pods and point at the managed endpoints:

```yaml
postgres:
  enabled: false
valkey:
  enabled: false
secrets:
  databaseUrl: postgresql://user:pass@my-pg.postgres.database.azure.com:5432/stackguard?sslmode=require
  redisUrl: rediss://:accesskey@my-cache.redis.cache.windows.net:6380/0
```

**Raw manifests:** set the same URLs in `stackguard.env` and skip applying `manifests/postgres/` and `manifests/valkey/` (or delete those resources after apply).

Keep **bundled** Postgres + Valkey enabled when you want a self-contained install with no external managed services.

---

## Folder structure

```text
k8/
├── helm/                    # Helm install (recommended) → helm/README.md
├── infrastructure/          # Pick ONE: aks / eks / gke → terraform/
└── kubernetes/
    ├── scripts/apply.sh     # Raw manifest deploy (alternative to Helm)
    ├── values/
    │   ├── base.env.example # Copy this → stackguard.env
    │   └── overlays/        # Copy aks/eks/gke example → cloud.env
    └── manifests/           # Do not edit unless you know why
```

**Never commit:** `stackguard.env`, `cloud.env`, `terraform.tfvars` (gitignored)

---

## Step 1 — Install tools

You need: **Terraform**, **kubectl**, **envsubst** (`brew install gettext`), and your cloud CLI (`az` / `aws` / `gcloud`).

Log in to your cloud account before continuing.

---

## Step 2 — Create config files

```bash
cd k8/kubernetes

cp values/base.env.example values/stackguard.env
cp values/overlays/aks.env.example values/cloud.env    # use eks or gke if not AKS

chmod +x scripts/*.sh
```

Edit `values/stackguard.env`:

```bash
# 1) Generate a 32-character secret (required — exactly 32 chars)
openssl rand -hex 16
# Put output in STACKGUARD_SECRET=

# 2) Generate a Postgres password
openssl rand -hex 16
# Put output in POSTGRES_PASSWORD=

# 3) Database URL — password MUST match POSTGRES_PASSWORD, MUST end with ?sslmode=disable
STACKGUARD_DATABASE_URL=postgresql://stackguard:<POSTGRES_PASSWORD>@stackguard-postgres:5432/stackguard?sslmode=disable

# 4) Valkey password — MUST match VALKEY_PASSWORD in STACKGUARD_REDIS_URL
VALKEY_PASSWORD=<same-as-above-or-another>
STACKGUARD_REDIS_URL=redis://stackguard:<VALKEY_PASSWORD>@stackguard-valkey:6379/0
```

Leave `STACKGUARD_API_URL=http://localhost:8080` for now — you fix it in Step 5.

---

## Step 3 — Create the cluster (pick your cloud)

### AKS

```bash
cd ../../infrastructure/aks/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

az aks get-credentials \
  --resource-group rg-stackguard-prod \
  --name aks-stackguard-prod \
  --overwrite-existing
```

### EKS

```bash
cd ../../infrastructure/eks/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

aws eks update-kubeconfig --region ap-south-1 --name eks-stackguard-prod
```

Terraform sets IMDS hop limit **2**, installs EBS CSI + `gp3`, and uses a **Canonical Ubuntu EKS AMI** (`node_ami_id` or SSM lookup — never Amazon Linux). Node autoscaling stays off (`min=max=desired=1`).

### GKE

```bash
cd ../../infrastructure/gke/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

gcloud container clusters get-credentials gke-stackguard-prod \
  --region asia-south1 --project <your-project-id>
```

Terraform sets node `workload_metadata_config.mode = GCE_METADATA` so pods can read the GCP project ID.

Confirm the cluster works:

```bash
kubectl get nodes
```

---

## Step 4 — Deploy StackGuard

```bash
cd ../../../kubernetes

./scripts/apply.sh values/stackguard.env values/cloud.env
```

Wait until both pods are Running:

```bash
kubectl get pods -n stackguard -w
```

You want:

```text
stackguard-server-...     1/1   Running
stackguard-dashboard-...  1/1   Running
stackguard-postgres-0     1/1   Running
stackguard-valkey-0       1/1   Running
```

Press `Ctrl+C` to stop watching.

---

## Step 5 — Get the public IP and fix the URL

```bash
kubectl get svc -n stackguard stackguard-server stackguard-dashboard
```

Copy both **EXTERNAL-IP** values. Edit `values/stackguard.env`:

```bash
STACKGUARD_API_URL=http://<server-ip>:8080
STACKGUARD_DASHBOARD_URL=http://<dashboard-ip>:4000
```

Apply again and restart:

```bash
./scripts/apply.sh values/stackguard.env values/cloud.env

kubectl rollout restart deployment -n stackguard stackguard-server stackguard-dashboard
```

Open the UI: **http://\<dashboard-ip\>:4000**

Enter your full name and email to ask for approval. After an admin approves, refresh and sign in with the password from the email. Then set a new password and accept the terms if asked.

---

## Step 6 — Check status

```bash
kubectl get pods -n stackguard
kubectl get svc -n stackguard
kubectl get pvc -n stackguard
```

---

## Step 7 — Check logs

**Application**

```bash
kubectl logs -n stackguard -l app=stackguard-server --tail=100
kubectl logs -n stackguard -l app=stackguard-server -f
```

**Postgres**

```bash
kubectl logs -n stackguard stackguard-postgres-0 --tail=100
kubectl logs -n stackguard stackguard-postgres-0 -f
```

**Valkey (cache)**

```bash
kubectl logs -n stackguard stackguard-valkey-0 --tail=100
kubectl logs -n stackguard stackguard-valkey-0 -f
```

**After a crash**

```bash
kubectl logs -n stackguard -l app=stackguard-server --previous
kubectl describe pod -n stackguard -l app=stackguard-server
```

---

## Common problems

| Problem                                           | Fix                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `STACKGUARD_SECRET must be exactly 32 characters` | Run `openssl rand -hex 16`, put result in `STACKGUARD_SECRET`                                                                                                                                                                                                                                                                                                                                                                                              |
| `SSL is not enabled on the server`                | Add `?sslmode=disable` to end of `STACKGUARD_DATABASE_URL`                                                                                                                                                                                                                                                                                                                                                                                                 |
| Postgres crash — `lost+found`                     | Already fixed in template. Reset: `kubectl delete statefulset -n stackguard stackguard-postgres` then `kubectl delete pvc -n stackguard postgres-data-stackguard-postgres-0` then re-run `apply.sh`                                                                                                                                                                                                                                                        |
| AKS quota error `standardDSv3Family`              | Azure Portal → Subscriptions → Usage + quotas → Central India → increase **Standard DSv3 Family vCPUs** to at least 16                                                                                                                                                                                                                                                                                                                                     |
| Pod stuck `Pending`                               | Single node ran out of CPU during restart. Run `kubectl get pods -n stackguard` and delete the old/terminating pod                                                                                                                                                                                                                                                                                                                                         |
| LoadBalancer `<pending>`                          | Wait 2–5 min. Check Azure/AWS/GCP LB quota                                                                                                                                                                                                                                                                                                                                                                                                                 |
| App detects as `local` / missing cloud ID         | Pods must reach instance metadata. **EKS:** IMDS hop limit **2** (Terraform launch template). Live fix: `aws ec2 modify-instance-metadata-options --instance-id <id> --http-put-response-hop-limit 2 --http-tokens required` then restart app. **AKS:** do not block `169.254.169.254`. **GKE:** node metadata mode `GCE_METADATA`. Confirm: `kubectl logs -n stackguard -l app=stackguard-server \| grep -E 'AWS detected\|Azure detected\|GCP detected'` |
| Config change not picked up                       | Re-run `./scripts/apply.sh` then `kubectl rollout restart deployment -n stackguard stackguard-server`                                                                                                                                                                                                                                                                                                                                                      |
| Site asks for approval again                      | Approval is tied to the cloud account the app detects, or to the email on a local install                                                                                                                                                                                                                                                                                                                                                                  |

---

## Change CPU / RAM / storage

Edit `kubernetes/values/stackguard.env`, then:

```bash
./scripts/apply.sh values/stackguard.env values/cloud.env
kubectl rollout restart deployment -n stackguard stackguard-server
```

To scale the node VM, edit `terraform.tfvars` and run `terraform apply`.

---

## Delete everything

```bash
# Remove StackGuard
kubectl delete namespace stackguard

# Remove cluster
cd infrastructure/<aks|eks|gke>/terraform
terraform destroy
```

---

## Default sizing

| Service   | CPU | RAM   | Disk   |
| --------- | --- | ----- | ------ |
| Server    | 2   | 4 GiB | 10 GiB |
| Dashboard | 1   | 2 GiB | —      |
| Postgres  | 2   | 4 GiB | 10 GiB |
| Valkey    | 1   | 2 GiB | 2 GiB  |

| Cloud | Node VM                              |
| ----- | ------------------------------------ |
| AKS   | `Standard_F8s_v2` (8 vCPU, 16 GiB)   |
| EKS   | `c6i.2xlarge` (8 vCPU, 16 GiB)       |
| GKE   | `e2-custom-8-16384` (8 vCPU, 16 GiB) |

| Cloud | Storage class (`cloud.env`) |
| ----- | --------------------------- |
| AKS   | `managed-csi`               |
| EKS   | `gp3`                       |
| GKE   | `standard-rwo`              |
