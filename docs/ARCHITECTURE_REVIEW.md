# StackGuard Deployment Architecture Review

**Date:** 2026-10-31
**Branch reviewed:** `remove-ai-server-v1.0.1` (commit `6510128`)
**Scope:** Helm chart (`helm/stackguard`), Terraform (`infrastructure/{aks,eks,gke}`), raw manifests (`kubernetes/`), Azure Marketplace bundle (`marketplace/azure`)
**Question:** Is the current architecture suitable for an enterprise-level deployment?

---

## 1. Summary

**Not yet.** The project is a clean, well-organised **single-tenant, single-node** installation that works the same way on AKS, EKS and GKE. It is fine for evaluations, proofs of concept and small teams.

It is not ready for enterprise production, for two kinds of reason:

- **Fixable in the chart:** default secrets, an allow-all NetworkPolicy, no TLS or Ingress, no pod hardening, unencrypted in-cluster Postgres, and weak health checks.
- **Needs application changes:** the server and dashboard keep state on ReadWriteOnce volumes, and horizontal scaling is turned off on purpose. This rules out high availability (HA) until the application is changed.

| Area | Rating | Notes |
|---|---|---|
| Portability (multi-cloud) | Good | One chart with per-cloud values; Terraform for each cloud |
| Configuration & secrets handling | Fair | Secret/ConfigMap references, but insecure defaults and no external secret store |
| Availability / resilience | Poor | One replica of everything, on one node |
| Data durability | Poor | In-cluster Postgres with no backups, no PITR and no TLS |
| Network security | Poor | All traffic allowed; plain-HTTP public LoadBalancers |
| Workload hardening | Poor | No securityContext, PDB, ServiceAccount or RBAC |
| Observability | Poor | TCP probes only; no metrics or logging integration |
| Delivery / operations | Fair | Pinned image tags, Marketplace bundle; no CI and the chart exists in several copies |

---

## 2. Current Architecture

```
                Internet
                   │
     ┌─────────────┴─────────────┐
     │ LoadBalancer :4000 (HTTP) │ LoadBalancer :8080 (HTTP)
     ▼                           ▼
┌───────────┐   ┌──────────────────────┐
│ dashboard │──▶│ server               │
│ 1 replica │   │ 1 replica            │
│ PVC /data │   │ PVC /scans (RWO)     │
└───────────┘   └──────────┬───────────┘
                           │ sslmode=disable
                           ▼
                ┌──────────────────────┐
                │ postgres StatefulSet │
                │ 1 replica, RWO PVC   │
                └──────────────────────┘
     All of the above on a single node (node_count must equal 1)
```

Components (from `helm/stackguard/values.yaml`):

| Component | Kind | Replicas | Resources (req = limit) | Storage | Exposure |
|---|---|---|---|---|---|
| dashboard | Deployment | 1 | 2 CPU / 4 GiB | 10 Gi RWO at `/data` | LoadBalancer :4000 |
| server | Deployment | 1 | 4 CPU / 8 GiB | 10 Gi RWO at `/scans` | LoadBalancer :8080 |
| postgres 16.4 | StatefulSet | 1 | 2 CPU / 4 GiB | 10 Gi RWO | ClusterIP :5432 |

Total requests come to **8 vCPU / 16 GiB on one node**.

---

## 3. Strengths

- **One chart, three clouds.** Per-cloud values files (`values-aks.yaml`, `values-eks.yaml`, `values-gke.yaml`) and matching Terraform modules make installs repeatable.
- **Secrets are referenced, not inlined.** Pods read credentials through `secretKeyRef` and `configMapKeyRef`, and important values are enforced with Helm `required`.
- **Pinned image versions** (`server v1.0.1`, `dashboard v1.0.0`, `postgres 16.4`). There is no use of `latest`.
- **Guaranteed QoS.** Requests equal limits, so the scheduler places pods predictably.
- **External database already possible.** Setting `secrets.databaseUrl` (`templates/_helpers.tpl:80`) bypasses the bundled Postgres.
- **Marketplace-ready.** The CNAB bundle and `createUIDefinition.json` already exist for Azure.
- **Honest limits.** The Terraform `node_count == 1` check makes the single-node constraint explicit instead of letting it fail silently.

---

## 4. Findings

Severity: **Critical** = blocks an enterprise security or SRE sign-off; **High** = expected for production; **Medium** = operational maturity.

### 4.1 Critical

**C1. No high availability.**
Every workload runs as one replica. The server and Postgres are annotated `stackguard.io/horizontal-scaling: "disabled"`. All three Terraform modules reject `node_count != 1` (`infrastructure/*/terraform/variables.tf`). A single node failure, node upgrade or zone outage causes a full outage.

**C2. Stateful application pods.**
The server writes scans to a ReadWriteOnce PVC at `/scans`, and the dashboard writes to `/data`. An RWO volume can attach to only one node at a time, so adding replicas or spreading across zones is impossible without application changes. *This is the main limit on the architecture, and it cannot be fixed in the chart alone.*

**C3. Database durability and transport security.**
Postgres runs in the cluster as one StatefulSet pod. There are no backups, no point-in-time recovery (PITR), no replicas and no failover. The default connection string uses `sslmode=disable` (`templates/_helpers.tpl:84`). Losing that one disk loses all data.

**C4. Insecure default secrets.**
`values.yaml` ships `stackguardSecret: "0123456789abcdef0123456789abcdef"` and `password: replace-with-strong-password`. Both pass the `required` checks, so an install that forgets to override them deploys with known credentials.

**C5. The NetworkPolicy allows everything.**
`templates/networkpolicy.yaml` is enabled by default but contains `ingress: [{}]` and `egress: [{}]`, which allows all traffic. It looks like isolation but provides none. Postgres can be reached from any pod in the cluster.

**C6. Public plain-HTTP endpoints.**
The dashboard and server are each exposed as a public `LoadBalancer` with no TLS. There is no Ingress controller, cert-manager integration, WAF or IP allow-listing.

### 4.2 High

**H1. No pod security hardening.**
No `securityContext` is set (`runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, dropped capabilities, seccomp profile). Pods will be rejected on clusters that enforce the Pod Security Standards "restricted" profile.

**H2. No PodDisruptionBudgets, ServiceAccounts or RBAC.**
Pods run under the namespace's default ServiceAccount, with the token auto-mounted. With no PDBs, node drains during cluster upgrades evict pods without coordination.

**H3. Weak health checks.**
The server and dashboard use `tcpSocket` probes. These pass as soon as the port is open, even if the application cannot reach the database or is otherwise broken. There are no startup probes.

**H4. No external secret store integration.**
Secrets come only from Helm values. There is no support for External Secrets Operator, the Secrets Store CSI driver, Azure Key Vault, AWS Secrets Manager or GCP Secret Manager. Secrets end up in the Helm release history.

**H5. No observability.**
There are no metrics endpoints, ServiceMonitor or PodMonitor resources, dashboards, alerting rules or structured-logging guidance.

### 4.3 Medium

**M1. The chart exists in several copies.**
`helm/stackguard` and `marketplace/azure/stackguard` are kept in step by `sync-chart.sh`. `kubernetes/manifests/` is a third copy that still contains the removed AI service (`kubernetes/manifests/ai/`). Copies like this drift apart.

**M2. No CI pipeline in the repo.**
Nothing runs `helm lint`, `helm template` with kubeconform, chart-testing, policy checks (Kyverno, OPA/Conftest) or image vulnerability scanning before a release.

**M3. Terraform state and cluster posture.**
No remote state backend is configured. The single fixed-size node pool has no autoscaling and no zone spread. Private cluster or API endpoint restrictions should be reviewed for each cloud.

**M4. Upgrade and migration strategy.**
There are no documented database schema migration steps, rollback procedure or `helm upgrade` compatibility notes between chart versions.

**M5. Capacity headroom.**
With 8 vCPU / 16 GiB requested on one node, the node must be larger than that to leave room for system daemons. There is no spare capacity for surge pods during rolling updates.

---

## 5. Recommendations

### Phase 1: Chart hardening (no application changes; days)

| # | Action | Fixes |
|---|---|---|
| 1 | Remove default secret values; fail the install if they are empty or match the known placeholders; optionally generate them with `randAlphaNum` + `lookup` | C4 |
| 2 | Replace the allow-all policy with real NetworkPolicies: Postgres reachable only from the server; ingress only from the Ingress controller; egress limited to DNS, the database and required external endpoints | C5 |
| 3 | Add an optional Ingress with TLS (cert-manager annotations); make `ClusterIP` the default Service type | C6 |
| 4 | Add `securityContext` (non-root, read-only root filesystem, drop ALL capabilities, seccomp `RuntimeDefault`), a dedicated ServiceAccount with `automountServiceAccountToken: false`, and Pod Security Standards namespace labels | H1, H2 |
| 5 | Add PodDisruptionBudgets | H2 |
| 6 | Switch to HTTP readiness and liveness probes on a real health endpoint; add startup probes (needs a health route in the app if none exists) | H3 |
| 7 | Add `sslmode` as a value, defaulting to `require` when an external database is used | C3 (partial) |

### Phase 2: Production data and secrets (weeks)

| # | Action | Fixes |
|---|---|---|
| 8 | Make **managed Postgres** (RDS / Azure Database for PostgreSQL Flexible Server / Cloud SQL) the documented production path, with backups, PITR and high availability turned on. Keep the bundled StatefulSet for evaluations only, or replace it with CloudNativePG | C3 |
| 9 | Support External Secrets Operator or the Secrets Store CSI driver as a secret source | H4 |
| 10 | Add CI: `helm lint`, kubeconform, chart-testing, policy checks and Trivy image scans; produce the Marketplace chart from a single source instead of copying it | M1, M2 |
| 11 | Remove `kubernetes/manifests/ai/` or retire the raw manifests altogether | M1 |
| 12 | Add a Terraform remote state backend; review private cluster settings | M3 |
| 13 | Expose Prometheus metrics, ship a ServiceMonitor and basic alerts | H5 |

### Phase 3: High availability (application changes; one release cycle or more)

| # | Action | Fixes |
|---|---|---|
| 14 | Move server `/scans` and dashboard `/data` to object storage (S3 / Azure Blob / GCS), or to a ReadWriteMany volume as a stopgap | C2 |
| 15 | Make server and dashboard stateless and safe to run as multiple replicas (sessions, locking, scheduled jobs) | C1, C2 |
| 16 | Then add replicas ≥ 2, HorizontalPodAutoscaler, topology spread across zones, a multi-node autoscaling node pool, and lift the `node_count == 1` Terraform check | C1, M5 |

---

## 6. Target State

```
             Internet
                │
        ┌───────┴────────┐
        │ Ingress + TLS  │  (WAF / allow-list optional)
        └───┬────────┬───┘
            ▼        ▼
     dashboard ×N   server ×N      ← stateless, HPA, spread across zones, PDBs
            │        │
            │        ├──▶ Object storage (scans, artifacts)
            │        └──▶ Managed Postgres (HA, PITR, TLS)
            │
   Secrets: External Secrets / CSI  ·  Metrics: Prometheus  ·  Strict NetworkPolicies
```

---

## 7. Conclusion

- **After Phase 1 and Phase 2:** suitable for enterprise customers who accept a **single-instance** deployment with a managed, highly available database. This is a common and defensible tier for a security tool.
- **Only after Phase 3:** genuinely highly available, multi-zone and horizontally scalable. That requires application changes to remove local state from the server and dashboard; it is not a packaging problem.
