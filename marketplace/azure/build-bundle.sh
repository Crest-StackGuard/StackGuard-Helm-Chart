#!/usr/bin/env bash
# Builds and pushes the Stackguard CNAB bundle using the Microsoft container
# packaging tool. Requires Docker and a linux/amd64 host.
#
#   ./build-bundle.sh <acr-name> [--force]
set -euo pipefail

registry_name="${1:-}"
if [[ -z "${registry_name}" ]]; then
  echo "usage: $0 <acr-name> [--force]" >&2
  exit 1
fi
shift

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image="mcr.microsoft.com/container-package-app:latest"

docker pull "${image}"

docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${here}:/data" \
  --entrypoint /bin/bash \
  "${image}" -c "
    set -euo pipefail
    az login
    az acr login -n '${registry_name}'
    cd /data
    cpa verify
    cpa buildbundle $*
  "
