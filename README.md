# Stackguard Multi-Cloud Template (AKS / EKS / GKE)

Client-ready template for deploying Stackguard on managed Kubernetes in **India regions**:

- **Shared Kubernetes layer** (same manifests on all clouds)
- **Cloud-specific infrastructure layer** (Terraform per provider)
- **One pod per service** (dashboard, ai, server, postgres)
- **Horizontal scaling disabled**, vertical scaling only
- **10 GiB persistent storage per workload**
- **Auto-restart** via liveness/readiness probes + `restartPolicy: Always`

## Default India Regions

| Cloud | Region | Location |
|-------|--------|----------|
| AKS   | `centralindia` | Central India (Pune) |
| EKS   | `ap-south-1` | Mumbai |
| GKE   | `asia-south1` | Mumbai |

## Default Workload Sizing

| Service | CPU | Memory | Storage |
|---------|-----|--------|---------|
| Dashboard (app) | 2 vCPU | 4 GiB | 10 GiB |
| AI | 2 vCPU | 4 GiB | 10 GiB |
| Server | 4 vCPU | 8 GiB | 10 GiB |
| Postgres | 2 vCPU | 4 GiB | 10 GiB |

Node size defaults to **16 vCPU / 64 GiB** to fit all workloads on a single node (horizontal scaling disabled).

## Repository Layout

```text
k8/
├── README.md
├── kubernetes/                         # Shared Kubernetes layer
│   ├── scripts/
│   │   ├── apply.sh
│   │   └── apply-vpa.sh
│   ├── values/
│   │   ├── base.env.example
│   │   └── overlays/
│   │       ├── aks.env.example
│   │       ├── eks.env.example
│   │       └── gke.env.example
│   └── manifests/
│       ├── namespace/
│       ├── config/
│       ├── network/
│       ├── dashboard/
│       ├── ai/
│       ├── server/
│       ├── postgres/
│       └── autoscaling/
└── infrastructure/
    ├── aks/terraform/
    ├── eks/terraform/
    └── gke/terraform/
```

## Quick Start

### Step 1: Provision cluster (choose one cloud)

#### Azure AKS (Central India)

```bash
cd infrastructure/aks/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan && terraform apply

az aks get-credentials \
  --resource-group <resource_group_name> \
  --name <aks_cluster_name> \
  --overwrite-existing
```

#### AWS EKS (Mumbai)

```bash
cd infrastructure/eks/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan && terraform apply

aws eks update-kubeconfig --region ap-south-1 --name <cluster_name>
```

#### Google GKE (Mumbai)

```bash
cd infrastructure/gke/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan && terraform apply

gcloud container clusters get-credentials <cluster_name> --region asia-south1 --project <project_id>
```

### Step 2: Configure shared Kubernetes values

```bash
cd ../../../kubernetes
cp values/base.env.example values/stackguard.env
cp values/overlays/aks.env.example values/cloud.env   # or eks.env / gke.env
# Edit values/stackguard.env (secrets, URLs)
chmod +x scripts/*.sh
```

### Step 3: Deploy Stackguard

```bash
./scripts/apply.sh values/stackguard.env values/cloud.env
```

Optional VPA (vertical scaling only):

```bash
./scripts/apply-vpa.sh values/stackguard.env values/cloud.env
```

## Inter-Service Communication

All services communicate inside the cluster via Kubernetes DNS:

| Service | DNS Name | Port |
|---------|----------|------|
| Dashboard | `stackguard-dashboard` | 4000 |
| AI | `stackguard-ai` | 8000 |
| Server | `stackguard-server` | 8080 |
| Postgres | `stackguard-postgres` | 5432 |

## Networking & Resilience

- **Ingress:** permissive NetworkPolicy (all inbound ports allowed; tighten later if needed)
- **Egress:** permissive NetworkPolicy (cluster + public internet)
- **EKS:** cluster security group allows all inbound/outbound by default
- **AKS:** outbound internet via load balancer; inbound via LoadBalancer services
- **Persistence:** PVC/StatefulSet volumes survive pod restarts
- **Auto-restart:** liveness/readiness probes restart unhealthy containers automatically

## Scaling Policy

- **Horizontal scaling:** disabled
  - Workloads pinned to `replicas: 1`
  - No HPA manifests
  - Node pool autoscaling disabled in all Terraform modules
  - `node_count` validated to `1`
- **Vertical scaling:** allowed
  - Update CPU/memory/storage in `kubernetes/values/stackguard.env`
  - Optionally enable VPA via `kubernetes/scripts/apply-vpa.sh`
  - Increase node size in cloud Terraform

## Cloud Storage Classes

| Cloud | Storage Class |
|-------|---------------|
| AKS   | `managed-csi` |
| EKS   | `gp3` |
| GKE   | `standard-rwo` |

## Notes

- Kubernetes manifests are cloud-agnostic and reusable across AKS/EKS/GKE.
- Re-running `./scripts/apply.sh` resets replica counts to `1`.
- NetworkPolicy requires a supporting CNI (Azure CNI, Calico on EKS, etc.).
