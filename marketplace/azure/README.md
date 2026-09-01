# Stackguard — Azure Marketplace CNAB bundle

Artifacts required to publish Stackguard as a **Kubernetes application** container
offer on the Azure Marketplace, packaged as a Cloud Native Application Bundle (CNAB).

```
marketplace/azure/
├── manifest.yaml            # CNAB package manifest consumed by the cpa tool
├── mainTemplate.json        # ARM template: optional AKS cluster + cluster extension
├── createUIDefinition.json  # Azure portal create experience
├── stackguard/              # Helm chart shipped inside the bundle
├── sync-chart.sh            # Refreshes stackguard/ from helm/stackguard
└── build-bundle.sh          # Runs cpa verify / buildbundle in Docker
```

## How this differs from `helm/stackguard`

The bundled chart shares its templates with the public chart; only `values.yaml`
differs. `sync-chart.sh` copies `Chart.yaml` and `templates/` from
`helm/stackguard` and drops `namespace.yaml`, because the AKS cluster extension
creates and owns the release namespace.

Marketplace-specific behaviour in the shared templates:

- Images resolve from `global.azure.images.<component>` when present, which is the
  block the packaging tool rewrites to point at the Microsoft-owned ACR. Without
  that block the chart falls back to the normal `images.*` values.
- Pod specs carry the `azure-extensions-usage-release-identifier` label, required
  for per-core/per-node/per-pod billing models. The label is only emitted when
  `global.azure` is set, so the public chart is unaffected.
- Resources default to `.Release.Namespace` when `namespace` is empty.

## Parameter flow

`createUIDefinition.json` → `mainTemplate.json` parameters → extension
`configurationSettings` / `configurationProtectedSettings` → Helm values.

| Portal input | Helm value |
| --- | --- |
| Storage class | `global.storageClass` |
| Service exposure | `dashboard/server/ai.service.type` |
| Dashboard / API / AI URL | `urls.*` |
| Stackguard secret (protected) | `secrets.stackguardSecret` |
| PostgreSQL password (protected) | `secrets.postgres.password` |

## Before you build

1. Create an ACR in the same Entra tenant as your Partner Center account and set
   `registryServer` in `manifest.yaml`.
2. Grant the marketplace first-party app `32597670-3e15-4def-8851-614ff48c1efa`
   the `acrpull` role on that registry and register the
   `Microsoft.PartnerCenterIngestion` provider on the subscription.
3. Confirm the image tags in `stackguard/values.yaml` are pinned to an immutable,
   vulnerability-scanned release rather than `latest`.
4. Bump `version` in `manifest.yaml` for every submission — CNAB tags are immutable
   once attached to an offer.

## Build and publish

```bash
./sync-chart.sh          # only if the source chart changed
helm lint ./stackguard
./build-bundle.sh <your-registry-name>
```

`build-bundle.sh` mounts this directory into `mcr.microsoft.com/container-package-app`
and runs `cpa verify` followed by `cpa buildbundle`. The tool requires Docker and
a linux/amd64 host. Once the bundle is pushed, reference the CNAB from your
Partner Center Kubernetes application offer.

## Limitations to keep in mind

- Marketplace supports linux/amd64 images only.
- One offer targets either managed AKS or Arc-enabled Kubernetes, not both.
- All images end up in a **public** Microsoft ACR regardless of plan visibility.
- No images or charts may be downloaded at deployment time; everything must be in
  the bundle.
