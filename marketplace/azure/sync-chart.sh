#!/usr/bin/env bash
# Syncs the marketplace CNAB chart from the canonical chart in helm/stackguard.
# Only templates/ and Chart.yaml are copied; values.yaml is marketplace-specific
# and is maintained by hand.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${here}/../../helm/stackguard"
dst="${here}/stackguard"

if [[ ! -d "${src}" ]]; then
  echo "source chart not found: ${src}" >&2
  exit 1
fi

rm -rf "${dst}/templates"
mkdir -p "${dst}/templates"
cp "${src}/Chart.yaml" "${dst}/Chart.yaml"
cp -R "${src}/templates/." "${dst}/templates/"

# The cluster extension owns the namespace; the bundle must not create it.
rm -f "${dst}/templates/namespace.yaml"

echo "synced chart from ${src} -> ${dst}"
