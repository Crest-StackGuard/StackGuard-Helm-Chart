# Stackguard Helm Chart

Chart source for Stackguard. **Install guide:** [`../README.md`](../README.md)

**Published:** `oci://public.ecr.aws/stackguard-io/stackguard:0.1.0`  
**Artifact Hub:** [artifacthub.io/packages/helm/stackguard/stackguard](https://artifacthub.io/packages/helm/stackguard/stackguard)

## Quick install

```bash
cp values.local.yaml.example values.local.yaml
# edit secrets in values.local.yaml

helm install stackguard oci://public.ecr.aws/stackguard-io/stackguard \
  --version 0.1.0 \
  -f values.local.yaml \
  -f values-eks.yaml
```

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
