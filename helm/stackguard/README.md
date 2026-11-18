# StackGuard Helm Chart

Chart source for StackGuard. **Install guide:** [`../README.md`](../README.md)

**Published:** `oci://public.ecr.aws/stackguard-io/stackguard:0.2.2`  
**Artifact Hub:** [artifacthub.io/packages/helm/stackguard/stackguard](https://artifacthub.io/packages/helm/stackguard/stackguard)

## Quick install

```bash
cp values.local.yaml.example values.local.yaml
# edit secrets in values.local.yaml

helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.2.2 \
  -f values.local.yaml \
  -f values-eks.yaml
```

**Hard limits (monolithic):** exactly **1** pod each for server, dashboard, Postgres, and Valkey. No HPA/VPA / horizontal autoscaling — scale vertically only. Images are **linux/amd64 (x86_64) only**.

## What this chart deploys

- `stackguard-server` — API on port 8080 (`public.ecr.aws/stackguard-io/server:v1.1.1`)
- `stackguard-dashboard` — UI on port 4000 (`public.ecr.aws/stackguard-io/dashboard:v1.1.1`)
- `stackguard-postgres` — Postgres 17
- `stackguard-valkey` — official [`valkey/valkey:8`](https://hub.docker.com/r/valkey/valkey) (Redis-compatible cache for sessions/SSO/rate limits)
- Optional: disable Postgres/Valkey and use managed Postgres + managed Redis-compatible cache via `secrets.databaseUrl` / `secrets.redisUrl`

No license key env vars. After start, open the site and enter name and email for approval.

## Publish a new chart version

```bash
helm package .
helm lint .

aws ecr-public get-login-password --profile sgl --region us-east-1 | \
  helm registry login --username AWS --password-stdin public.ecr.aws

helm push stackguard-<version>.tgz oci://public.ecr.aws/stackguard-io
```

Push updated Artifact Hub metadata after changing `artifacthub-repo.yml`:

```bash
oras push public.ecr.aws/stackguard-io/stackguard:artifacthub.io \
  --config /tmp/ah-config.json:application/vnd.cncf.artifacthub.config.v1+yaml \
  artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml
```

(`printf '{}' > /tmp/ah-config.json` once if the file does not exist.)
