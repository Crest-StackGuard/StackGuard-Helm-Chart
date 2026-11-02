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

**Hard limits:** exactly **1** `stackguard-application` pod (no replicas knob, no HPA/VPA). Ubuntu nodes only (`stackguard.io/os=ubuntu`). Scale by raising CPU/RAM/disk + node VM size.

## What this chart deploys

- `stackguard-application` — API + UI on port 8080 (`public.ecr.aws/stackguard-io/stackguard-application`)
- `stackguard-postgres` — Postgres 17

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
