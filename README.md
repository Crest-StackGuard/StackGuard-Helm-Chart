# Stackguard on Kubernetes (AKS / EKS / GKE)

Deploy Stackguard on managed Kubernetes. Same app manifests for all clouds — only the Terraform layer changes.

**Prefer Helm?** See [`helm/README.md`](helm/README.md) for `helm install` from public ECR (recommended for new deployments).

**India regions (default):** AKS `centralindia` · EKS `ap-south-1` · GKE `asia-south1`

---

## What you get

| Service | Port | Public? |
|---------|------|---------|
| Dashboard | 4000 | Yes (LoadBalancer) |
| Server (API) | 8080 | Yes (LoadBalancer) |
| AI | 8000 | Yes (LoadBalancer) |
| Postgres | 5432 | No (internal only) |

- 1 pod per service (no horizontal scaling)
- 10 GiB persistent disk per service
- Vertical scaling only (change CPU/RAM in config files)

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
```

Leave the three `localhost` URLs for now — you fix them in Step 6.

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

### GKE

```bash
cd ../../infrastructure/gke/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

gcloud container clusters get-credentials gke-stackguard-prod \
  --region asia-south1 --project <your-project-id>
```

Confirm the cluster works:

```bash
kubectl get nodes
```

---

## Step 4 — Deploy Stackguard

```bash
cd ../../../kubernetes

./scripts/apply.sh values/stackguard.env values/cloud.env
```

Wait until all 4 pods are Running:

```bash
kubectl get pods -n stackguard -w
```

You want:

```text
stackguard-dashboard-...   1/1   Running
stackguard-ai-...          1/1   Running
stackguard-server-...      1/1   Running
stackguard-postgres-0      1/1   Running
```

Press `Ctrl+C` to stop watching.

---

## Step 5 — Get public IPs and fix URLs

```bash
kubectl get svc -n stackguard
```

Copy the **EXTERNAL-IP** for dashboard, server, and ai. Edit `values/stackguard.env`:

```bash
STACKGUARD_DASHBOARD_URL=http://<dashboard-ip>:4000
STACKGUARD_API_URL=http://<server-ip>:8080
STACKGUARD_AI_URL=http://<ai-ip>:8000
```

Apply again and restart apps:

```bash
./scripts/apply.sh values/stackguard.env values/cloud.env

kubectl rollout restart deployment -n stackguard \
  stackguard-dashboard stackguard-ai stackguard-server
```

Open in browser: **http://\<dashboard-ip\>:4000**

---

## Step 6 — Check status

```bash
# Everything running?
kubectl get pods -n stackguard
kubectl get svc -n stackguard
kubectl get pvc -n stackguard
```

---

## Step 7 — Check logs

**Dashboard**

```bash
kubectl logs -n stackguard -l app=stackguard-dashboard --tail=100
kubectl logs -n stackguard -l app=stackguard-dashboard -f
```

**AI**

```bash
kubectl logs -n stackguard -l app=stackguard-ai --tail=100
kubectl logs -n stackguard -l app=stackguard-ai -f
```

**Server**

```bash
kubectl logs -n stackguard -l app=stackguard-server --tail=100
kubectl logs -n stackguard -l app=stackguard-server -f
```

**Postgres**

```bash
kubectl logs -n stackguard stackguard-postgres-0 --tail=100
kubectl logs -n stackguard stackguard-postgres-0 -f
```

**After a crash** (see what happened before restart):

```bash
kubectl logs -n stackguard -l app=stackguard-server --previous
kubectl logs -n stackguard -l app=stackguard-ai --previous
kubectl logs -n stackguard stackguard-postgres-0 --previous
```

**Why is a pod failing?**

```bash
kubectl describe pod -n stackguard -l app=stackguard-server
kubectl describe pod -n stackguard -l app=stackguard-ai
kubectl describe pod -n stackguard -l app=stackguard-dashboard
kubectl describe pod -n stackguard stackguard-postgres-0
```

**All pods at once**

```bash
for p in $(kubectl get pods -n stackguard -o name); do
  echo "=== $p ==="
  kubectl logs -n stackguard "$p" --tail=30
done
```

---

## Common problems

| Problem | Fix |
|---------|-----|
| `STACKGUARD_SECRET must be exactly 32 characters` | Run `openssl rand -hex 16`, put result in `STACKGUARD_SECRET` |
| `SSL is not enabled on the server` | Add `?sslmode=disable` to end of `STACKGUARD_DATABASE_URL` |
| Postgres crash — `lost+found` | Already fixed in template. Reset: `kubectl delete statefulset -n stackguard stackguard-postgres` then `kubectl delete pvc -n stackguard postgres-data-stackguard-postgres-0` then re-run `apply.sh` |
| AKS quota error `standardDSv3Family` | Azure Portal → Subscriptions → Usage + quotas → Central India → increase **Standard DSv3 Family vCPUs** to at least 16 |
| Pod stuck `Pending` | Single node ran out of CPU during restart. Run `kubectl get pods -n stackguard` and delete the old/terminating pod |
| LoadBalancer `<pending>` | Wait 2–5 min. Check Azure/AWS/GCP LB quota |
| Config change not picked up | Re-run `./scripts/apply.sh` then `kubectl rollout restart deployment -n stackguard <name>` |

---

## Change CPU / RAM / storage

Edit `kubernetes/values/stackguard.env`, then:

```bash
./scripts/apply.sh values/stackguard.env values/cloud.env
kubectl rollout restart deployment -n stackguard stackguard-dashboard stackguard-ai stackguard-server
```

To scale the node VM, edit `terraform.tfvars` and run `terraform apply`.

---

## Delete everything

```bash
# Remove Stackguard
kubectl delete namespace stackguard

# Remove cluster
cd infrastructure/<aks|eks|gke>/terraform
terraform destroy
```

---

## Default sizing

| Service | CPU | RAM | Disk |
|---------|-----|-----|------|
| Dashboard | 2 | 4 GiB | 10 GiB |
| AI | 2 | 4 GiB | 10 GiB |
| Server | 4 | 8 GiB | 10 GiB |
| Postgres | 2 | 4 GiB | 10 GiB |

| Cloud | Node VM |
|-------|---------|
| AKS | `Standard_D16s_v3` (16 vCPU) |
| EKS | `m6i.4xlarge` |
| GKE | `n2-standard-16` |

| Cloud | Storage class (`cloud.env`) |
|-------|----------------------------|
| AKS | `managed-csi` |
| EKS | `gp3` |
| GKE | `standard-rwo` |
