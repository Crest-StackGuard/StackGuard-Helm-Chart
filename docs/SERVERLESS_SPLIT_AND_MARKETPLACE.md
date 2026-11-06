# StackGuard: Splitting the Server Image for Serverless AKS, and the Azure Marketplace Target Architecture

**Date:** 2026-11-02
**Branch:** `remove-ai-server-v1.0.1`
**Inputs:** Helm chart in this repo; image metadata and app layers pulled from `public.ecr.aws/stackguard-io/server:v1.0.1` and `dashboard:v1.0.0` (linux/amd64); Microsoft Learn docs listed under Sources.
**Related:** [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) (findings C1–C6, H1–H5 referenced below)

---

## 1. Summary

- **The "Docker inside" is in the server image, and it is the Docker CLI, not a Docker daemon.** The server image installs `docker-ce-cli` and puts its `scanner` user in a `docker` group. Its bundled ops scripts expect a host Docker socket (`/var/run/docker.sock`). That is a leftover from the Docker Compose deployment model.
- **On AKS that socket does not exist** (nodes run containerd and the chart mounts no socket). So every Docker-dependent feature is **already non-functional** on Kubernetes today: in-app update, backup, restore and DB prune. This needs confirming with the app team, but no code path in the chart can make it work.
- **The server image is really five workloads in one container:** the API, a secret-scanner engine started as a subprocess, a headless-Chromium PDF renderer, an in-process cron scheduler, and Docker-based ops scripts. That bundling, together with the local `/scans` volume, is what blocks horizontal scaling and serverless execution.
- **Recommended split:** `api` (stateless Deployment), `scanner` (Kubernetes Job per scan, started by KEDA), `renderer` (headless-Chrome Service), `scheduler` (single replica or CronJobs), and ops as Helm hooks or CronJobs. The dashboard is already separate and stays as it is.
- **"True AKS serverless" today** means AKS with node auto-provisioning (Karpenter) plus KEDA, with scanner jobs scaling to zero. **Virtual Nodes v2 (ACI)** is still **preview with no SLA**. It still needs a VM node pool, and it does not support the Cilium or NPM network policy engines. Treat it as an opt-in burst target, not the foundation.
- **Marketplace:** the existing Kubernetes-app (CNAB) offer can only deploy an AKS cluster and the extension. It **cannot** provision managed Postgres, Key Vault or Storage. For an enterprise-grade listing, wrap it: an **Azure Application (Managed Application)** offer that creates AKS + PostgreSQL Flexible Server + Key Vault + Storage, then installs the same chart as the extension.

---

## 2. What is inside the images (evidence)

### 2.1 Server image `stackguard-io/server:v1.0.1` (473 MB compressed)

| Layer content | Evidence | Role |
|---|---|---|
| Debian bookworm + `docker-ce-cli`, `chromium`, `git`, `openssh-client`, `jq`, `bc` | apt layer, 317 MB | Tooling for the roles below |
| `/app/main` (Go, 227 MB uncompressed) | links `k8s.io/client-go`, `chromedp`, `robfig/cron`; string `failed to execute StackGuard binary ./StackGuard (cwd=%s)`; env `STACKGUARD_CHROME_PATH` | API server, scheduler, PDF rendering; starts the scanner as a subprocess |
| `/app/StackGuard` (Go, 169 MB) | ~36k `trufflehog` symbols; links `github.com/docker/docker/client` (`ContainerCreate`, `ContainerExec*`), `unix:///var/run/docker.sock` | Secret-scanner engine (TruffleHog-based). Its Docker client is the TruffleHog "docker" source for scanning images through a local daemon |
| `/app/scripts/*.sh` | `update-server.sh`, `update-dashboard.sh`, `update-ai.sh`, `update-application.sh` run `docker pull/run/stop/rm` against containers named `stackguard-scanner` on network `stackguard_network`, and mount `/var/run/docker.sock`. `backup.sh`, `restore-db.sh` and `prune-db-for-update.sh` run `docker run postgres:17` / `busybox` against a Docker volume | Compose-era self-update and DB ops |
| `RUN useradd scanner && groupadd docker && usermod -aG docker scanner`; dirs `/scans`, `/app/storage_scans`, `/app/report_pdfs` | build history | Runs non-root (good); local file state (blocks scaling) |

Interpretation:

- `main` itself does not appear to call the update or backup scripts by name (no matching strings). They are likely invoked through a shell or from the dashboard's "update" flow. **Confirm with the app team** which UI actions trigger them.
- The `docker.sock` strings inside `main` are **detection rules** (it flags pods that mount the socket), not runtime use.

### 2.2 Dashboard image `stackguard-io/dashboard:v1.0.0` (121 MB)

Alpine + Node 22, non-root `appuser`, `node server.cjs` on :4000, plus an env-injection entrypoint. No Docker usage. This is already a clean single-purpose unit.

---

## 3. Why the current shape cannot go serverless

| Blocker | Cause | Effect on AKS / serverless |
|---|---|---|
| Docker CLI + socket-based scripts | Compose deployment model | Fails on containerd; mounting a host socket would be a privilege-escalation path, and serverless (ACI) never offers one |
| Scanner as a local subprocess | `exec ./StackGuard` in the API container | A scan consumes the API pod's CPU and memory (hence the 4 CPU / 8 GiB request); it cannot scale independently or run to zero |
| Chromium inside the API | `chromedp` + local `chromium` | ~300 MB image weight and memory spikes in the API pod |
| In-process cron (`robfig/cron`) | Scheduler inside the API | With more than one replica, every replica fires every job (duplicate scans and alerts) |
| Local file state | RWO PVC at `/scans`; dirs `storage_scans`, `report_pdfs` | Pins the API to one node; blocks replicas (review finding C2) |

---

## 4. Target split

```
                    Ingress / App Gateway for Containers (TLS, WAF)
                         │                         │
                ┌────────▼───────┐        ┌────────▼────────┐
                │ dashboard (×N) │──API──▶│ api (×N, HPA)   │  stateless; no docker, no chromium,
                └────────────────┘        │ image ~60 MB    │  no scanner binary
                                          └──┬──────┬───┬───┘
                    enqueue scan (DB queue)  │      │   │ CDP over ws://
                         ┌───────────────────┘      │   └──────────────▶ renderer (headless Chrome Svc)
                         ▼                          │
                 KEDA ScaledJob ── spawns ──▶ scanner Job pods (StackGuard engine)
                 (scales 0..N)                 run-to-completion; spot / NAP / virtual nodes
                         │                          │
                         └──────────┬───────────────┘
                                    ▼
                  PostgreSQL (Flexible Server, HA, TLS)   +   Blob Storage (scan artifacts, PDFs)

   scheduler (1 replica, or K8s CronJobs)  ──enqueues──▶ same queue
   ops: Helm pre-upgrade hook (migrate/prune), CronJob pg_dump or managed PITR
```

### 4.1 Units and what each needs

| Unit | Image | K8s kind | Scale | App change needed |
|---|---|---|---|---|
| `dashboard` | existing | Deployment + HPA | 2..N | None (state in `/data` must move to the API or DB to drop its PVC; confirm what it stores) |
| `api` | new slim image: distroless/debian-slim + `main` | Deployment + HPA + PDB | 2..N | Replace `exec ./StackGuard` with "enqueue job"; write artifacts to Blob, not `/scans`; remote Chrome; scheduler behind a flag |
| `scanner` | new image: `StackGuard` + `git` + `openssh-client` + CA certs | Job (via KEDA `ScaledJob`) | 0..N | Small entrypoint: claim job → run engine → write results to DB/Blob → exit. Image scanning must use **registry (remote) mode**, not a local daemon (verify TruffleHog's docker source supports this in the version vendored) |
| `renderer` | `chromedp/headless-shell` (or equivalent) | Deployment + Service | 1..N | `chromedp.NewRemoteAllocator(ctx, "ws://renderer:9222")` instead of a local exec allocator |
| `scheduler` | same as `api` with `--role=scheduler` | Deployment, replicas=1 (or Lease-based leader election) | 1 | Move the `robfig/cron` loop behind a role flag. Alternatively, map each schedule to a `CronJob` that enqueues |
| ops | `postgres:17` client image | Helm hook Job / CronJob | — | Replace the `update-*.sh` scripts with `helm upgrade` / extension auto-upgrade; replace `backup.sh` with Flexible Server PITR or a `pg_dump` CronJob to Blob; `prune-db-for-update.sh` becomes a `pre-upgrade` hook |

**Queue choice.** Start with a Postgres-table queue (`SELECT … FOR UPDATE SKIP LOCKED`) and the KEDA `postgresql` scaler. That adds zero new infrastructure and works inside the Marketplace CNAB constraints. Move to Azure Service Bus or Storage Queues (KEDA `azure-servicebus` / `azure-queue` scalers, workload identity) in the managed-app tier.

**Security gains.** No Docker CLI or group, no Chromium in the API, smaller attack surface, and each unit can run `readOnlyRootFilesystem` with its own ServiceAccount. This fixes review findings H1 and H2 per unit. Scanner pods get only the egress they need.

### 4.2 Compute options for "serverless"

| Option | Status | Fit for StackGuard |
|---|---|---|
| **AKS + node auto-provisioning (Karpenter) / AKS Automatic + KEDA** | Production | **Recommended.** API, dashboard and renderer run on a small always-on pool; scanner Jobs land on auto-provisioned (optionally spot) nodes that scale back down when idle |
| **AKS Virtual Nodes v2 (ACI)** | **Preview, no SLA** | Good later for bursty scanner Jobs. Constraints: still needs ≥1 VM node pool of 4 vCPU / 16 GiB, and each virtual node reserves ~3 vCPU / 12 GiB on it; no DaemonSets; Azure Files is the only PV type; no Cilium/NPM network policy (Calico or none); no CNI Overlay or BYO VNet; no API-server authorized IP ranges. Make it an opt-in `nodeSelector`/toleration on the scanner Job only |
| AKS Virtual Nodes v1 (add-on) | Superseded by v2 | Avoid: no PVCs, no init containers, no network policies, no managed identity |
| Azure Container Apps (+ Container Apps Jobs) | Production | Simplest truly serverless runtime (scale to zero, event-driven jobs). It is not AKS, though, and it cannot be sold through the Kubernetes-app Container offer. It would only be reachable through a Managed Application offer |

---

## 5. Azure Marketplace: best deployment architecture

### 5.1 Constraints of the current Kubernetes-app (CNAB) offer

From Microsoft's technical-assets doc:

- The ARM template may contain **only** `Microsoft.ContainerService/managedClusters` and `Microsoft.KubernetesConfiguration/extensions`. No Postgres, Key Vault, Storage, Service Bus or App Gateway.
- **All images must be in the bundle**, with nothing pulled at runtime. This means:
  - Every split image (scanner, renderer, ops client) must be listed under `global.azure.images.*`.
  - The current `update-*.sh` (`docker pull …:latest` from ECR) and `backup.sh` (`postgres:17`, `busybox`) patterns are non-compliant on principle.
- Linux/amd64 only; target either AKS or Arc per offer; images are republished to a **public** Microsoft ACR.
- Billing labels (`azure-extensions-usage-release-identifier`) go on every pod template, **including Job templates** for scanners. Per-core billing on bursty scan Jobs should be validated against how Microsoft meters short-lived pods and pods on virtual nodes (not documented; ask Partner Center support).

### 5.2 Recommended offer structure: two tiers, one chart

| Tier | Offer type | Provisions | Audience |
|---|---|---|---|
| **Standard** (exists) | Container offer, Kubernetes app (CNAB) | AKS (new or existing) + StackGuard extension; in-cluster Postgres (prefer CloudNativePG over the single StatefulSet); Azure Files / disk | Evaluations, SMB, customers with their own AKS |
| **Enterprise** (new) | **Azure Application: Managed Application** wrapping the Kubernetes app | New AKS (NAP + KEDA add-on, workload identity, Azure CNI), **PostgreSQL Flexible Server** (zone-redundant HA, PITR, private endpoint, TLS), **Key Vault** (Secrets Store CSI), **Storage account** (Blob for scans/PDFs), **App Gateway for Containers** or ingress with TLS/WAF, Log Analytics + Managed Prometheus, user-assigned identities; then the StackGuard extension | Regulated or enterprise customers |

Notes:

- A managed app that references a Kubernetes app **must create a new AKS cluster**; it cannot install into an existing one. Keep the Standard tier for "bring your own cluster".
- Keep **one source chart**. The enterprise tier only flips values: `postgres.enabled=false`, `externalDatabase`, `storage.type=blob`, `secrets.provider=keyvault`, `queue.type=servicebus`. This also retires the `sync-chart.sh` copy (review finding M1) once the bundle is built from `helm/stackguard` in CI.
- Enable extension **auto-upgrade for minor versions**. That is the Marketplace-native replacement for the in-app `update-*.sh` flow.
- SaaS (StackGuard-hosted, multi-tenant) is the most "serverless" option for the buyer. However, a security scanner that needs credentials to customer clouds, repos and clusters is usually easier to sell customer-hosted. Revisit it only if multi-tenancy becomes a product goal.

---

## 6. Roadmap

| Phase | Work | Owner | Unblocks |
|---|---|---|---|
| 0 | Confirm which features use the Docker scripts; hide or disable in-app update/backup on K8s; add a `STACKGUARD_RUNTIME=kubernetes` flag | App | Honest behaviour on AKS today |
| 1 | Chart: add `renderer` Deployment; app: remote Chrome allocator; drop Chromium from the API image | App + chart | ~300 MB smaller API image |
| 2 | App: DB job queue + scanner entrypoint; chart: `scanner` ScaledJob (KEDA postgres scaler), `scheduler` single replica | App + chart | Scans scale independently / to zero |
| 3 | App: artifacts to Blob (or an S3-compatible abstraction); API stateless; chart: HPA, PDB, replicas ≥ 2, drop `/scans` PVC | App + chart | HA (review findings C1, C2) |
| 4 | Ops: Helm hooks for migrations/prune; CronJob or managed backups; delete the Docker scripts and `docker-ce-cli` | App + chart | Marketplace compliance; no Docker anywhere |
| 5 | Marketplace: Enterprise Managed Application (Bicep → ARM) with Flexible Server, Key Vault, Storage, AGC; CI builds the CNAB from the single chart | Platform | Enterprise listing |
| 6 | Optional: Virtual Nodes v2 toleration on scanner Jobs once GA | Chart | Pure pay-per-second scan bursts |

---

## 7. Open questions for the StackGuard app team

1. Which UI or API actions run `scripts/update-*.sh`, `backup.sh` and `restore-db.sh`?
2. What does the dashboard persist in `/data`?
3. Is `/scans` scratch space or the system of record? Is `storage_scans` a DB table, a directory, or both?
4. Does the scanner need Docker-daemon image scanning, or is registry-based scanning enough?
5. How long do scans run, and how large are they? This sets the Job `activeDeadlineSeconds`, resources, and whether ACI limits fit.

---

## 8. Monthly cost comparison (Central India, pay-as-you-go list prices)

Prices come from the Azure Retail Prices API (`prices.azure.com`, USD, pulled 2026-11-02). Each month is 730 hours.

**Excluded, and roughly equal across all three options:**
- Log Analytics ingestion ($3.22/GB)
- Internet egress
- Defender for Cloud
- Marketplace software fees

**Assumed, not pulled:** the Standard Load Balancer price ($0.025/h for the first 5 rules), because the API returned no Load Balancer rows for this region.

### Unit prices used

| Item | Price |
|---|---|
| D16s_v3 node (current Terraform default) | $0.840/h |
| D4s_v5 node / D8s_v5 node / D8s_v5 **spot** | $0.202/h / $0.404/h / $0.0747/h |
| AKS Standard tier (uptime SLA) | $0.10/h (Free tier = $0) |
| PG Flexible General Purpose D2ds_v5 (2 vCore, 8 GiB) | $0.251/h |
| PG Flexible Burstable B2ms | $0.196/h |
| PG Flexible storage | $0.131/GB-month (backup storage free up to 100% of provisioned) |
| Premium SSD P10 (128 GiB OS disk) / Standard SSD E3 (10 Gi PVC) | $19.71 / $1.32 per month |
| Standard public IP | $0.005/h |
| Blob Hot LRS | $0.02/GB-month |

### Scenarios

| Line item | **A. Current** (1 × D16s_v3, in-cluster PG) | **B. Split, lean** (same availability as today) | **C. Split, enterprise HA** |
|---|---|---|---|
| AKS control plane | Free: $0 | Free: $0 | Standard (SLA): $73 |
| Always-on nodes + OS disks | 1 × D16s_v3 + P10: $633 | 1 × D4s_v5 + P10: $167 | 2 × D4s_v5 (2 zones) + P10: $334 |
| Scanner compute | inside the node above | D8s_v5 spot, ~4 h/day: $9 | D8s_v5 spot, ~4 h/day: $9 |
| PostgreSQL | inside the node + 10 Gi PVC | Flexible D2ds_v5 + 128 GiB: $200 | Flexible D2ds_v5 **zone-redundant HA** + 128 GiB: $400 |
| App PVCs / Blob + Key Vault | 3 × E3: $4 | Blob 100 GB + KV: $4 | Blob 100 GB + KV: $4 |
| Load Balancer + public IPs | LB + 3 IPs: $29 | LB + 2 IPs (one ingress): $26 | LB + 2 IPs: $26 |
| **Total / month** | **≈ $666** | **≈ $406 (−39%)** | **≈ $846 (+27%)** |

### What drives the difference

- **Today you pay for peak capacity 24/7.** The D16s_v3 ($613/month) is sized to hold a 4-CPU scan workload all the time. In B and C, scanning moves to spot nodes that exist only while a scan runs. That is the whole reason B is cheaper even with managed Postgres added.
- **Managed Postgres is not a pure add-on.** In A, Postgres already takes 2 CPU / 4 GiB of the D16s_v3. B moves that cost into Flexible Server ($200) and adds backups and point-in-time restore (PITR), which A does not have.
- **C costs more and buys** an AKS uptime SLA, two zones for the app, and a zone-redundant database with automatic failover. A and B are single points of failure.

### Sensitivities

| Change | Effect |
|---|---|
| Scans run 24/7 on one on-demand D8s_v5 instead of ~4 h/day on spot | +$286/month to B and C |
| Spot capacity unavailable (scanner falls back to on-demand), ~4 h/day | +$40/month |
| PG Burstable B2ms + 32 GiB instead of D2ds_v5 + 128 GiB (dev/SMB) | B drops to ≈ $353 |
| 1-year reserved instances on always-on D4s_v5 ($1,092/yr each ≈ $91/month vs $147) | −$56 per node per month |
| App Gateway for Containers / WAF instead of in-cluster ingress | Adds AGC charges (not priced here) |
| Marketplace bundle default (`Standard_D4s_v5`, one node) for the **current** design | Cheaper ($167), but 8 vCPU of requests does not fit on 4 vCPU; pods stay `Pending` |

---

## Sources

- [AKS virtual nodes (v1)](https://learn.microsoft.com/en-us/azure/aks/virtual-nodes)
- [AKS Virtual Nodes v2 (preview)](https://learn.microsoft.com/en-us/azure/aks/virtual-nodes-v2)
- [Kubernetes app Container offer: technical assets](https://learn.microsoft.com/en-us/partner-center/marketplace-offers/azure-container-technical-assets-kubernetes)
- [Reference Kubernetes apps from an Azure Application (managed app)](https://learn.microsoft.com/en-us/partner-center/marketplace-offers/referencing-kubernetes-apps-azure-app)
- [Microsoft Q&A: publishing an AKS app with supporting resources](https://learn.microsoft.com/en-us/answers/questions/5823374/how-to-publish-the-aks-application-along-with-crea) (community answer, not product docs)
- [Marketplace blog: choosing your offer type](https://techcommunity.microsoft.com/blog/marketplace-blog/ai-apps-and-agents-choosing-your-marketplace-offer-type/4505694)
