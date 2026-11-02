# StackGuard on Kubernetes (AKS / EKS / GKE)

Deploy StackGuard on managed Kubernetes. Same app manifests for all clouds — only the Terraform layer changes.

**Prefer Helm?** See [`helm/README.md`](helm/README.md) for `helm install` from public ECR (recommended for new deployments).

**India regions (default):** AKS `centralindia` · EKS `ap-south-1` · GKE `asia-south1`

---

## What you get

| Service | Port | Public? |
|---------|------|---------|
| Application (API + UI) | 8080 | Yes (LoadBalancer) |
| Postgres | 5432 | No (internal only) |

- One application image: `public.ecr.aws/stackguard-io/stackguard-application`
- Postgres 17
- No license key. After start, open the site, enter name and email, wait for approval, then sign in with the emailed password.
- Cloud account vs local is detected by the application from instance metadata (AWS account ID, Azure subscription ID, GCP project ID). Do not pass CSP or cloud id env vars.
- Always **exactly 1** `stackguard-application` pod (never scale out the golang server)
- No HPA, no VPA, no node/cluster autoscaling (`vmEnableAutoScale=false`). Vertical only: raise CPU/RAM + node VM size
- Ubuntu only on the StackGuard node (AKS `Ubuntu2204`, GKE `UBUNTU_CONTAINERD`, EKS Canonical Ubuntu AMI — never Amazon Linux / Azure Linux / COS)
- 10 GiB persistent disk per service (app disk is user-overridable)
- Azure Marketplace (Helm + optional AKS create): [`marketplace/azure/README.md`](marketplace/azure/README.md)

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

Leave `STACKGUARD_APPLICATION_URL=http://localhost:8080` for now — you fix it in Step 5.

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
stackguard-application-...   1/1   Running
stackguard-postgres-0        1/1   Running
```

Press `Ctrl+C` to stop watching.

---

## Step 5 — Get the public IP and fix the URL

```bash
kubectl get svc -n stackguard stackguard-application
```

Copy the **EXTERNAL-IP**. Edit `values/stackguard.env`:

```bash
STACKGUARD_APPLICATION_URL=http://<application-ip>:8080
```

Apply again and restart:

```bash
./scripts/apply.sh values/stackguard.env values/cloud.env

kubectl rollout restart deployment -n stackguard stackguard-application
```

Open in the browser: **http://\<application-ip\>:8080**

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
kubectl logs -n stackguard -l app=stackguard-application --tail=100
kubectl logs -n stackguard -l app=stackguard-application -f
```

**Postgres**

```bash
kubectl logs -n stackguard stackguard-postgres-0 --tail=100
kubectl logs -n stackguard stackguard-postgres-0 -f
```

**After a crash**

```bash
kubectl logs -n stackguard -l app=stackguard-application --previous
kubectl describe pod -n stackguard -l app=stackguard-application
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
| App detects as `local` / missing cloud ID | Pods must reach instance metadata. **EKS:** IMDS hop limit **2** (Terraform launch template). Live fix: `aws ec2 modify-instance-metadata-options --instance-id <id> --http-put-response-hop-limit 2 --http-tokens required` then restart app. **AKS:** do not block `169.254.169.254`. **GKE:** node metadata mode `GCE_METADATA`. Confirm: `kubectl logs -n stackguard -l app=stackguard-application \| grep -E 'AWS detected\|Azure detected\|GCP detected'` |
| Config change not picked up | Re-run `./scripts/apply.sh` then `kubectl rollout restart deployment -n stackguard stackguard-application` |
| Site asks for approval again | Approval is tied to the cloud account the app detects, or to the email on a local install |

---

## Change CPU / RAM / storage

Edit `kubernetes/values/stackguard.env`, then:

```bash
./scripts/apply.sh values/stackguard.env values/cloud.env
kubectl rollout restart deployment -n stackguard stackguard-application
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

| Service | CPU | RAM | Disk |
|---------|-----|-----|------|
| Application | 4 | 8 GiB | 10 GiB |
| Postgres | 4 | 8 GiB | 10 GiB |

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
