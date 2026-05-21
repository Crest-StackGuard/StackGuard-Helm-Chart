#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
VALUES_DIR="${ROOT_DIR}/values"

BASE_ENV="${1:-${VALUES_DIR}/stackguard.env}"
CLOUD_OVERLAY="${2:-}"

if [[ ! -f "${BASE_ENV}" ]]; then
  echo "Base values file not found: ${BASE_ENV}"
  echo "Setup:"
  echo "  cp values/base.env.example values/stackguard.env"
  echo "  ./scripts/apply.sh values/stackguard.env values/overlays/<aks|eks|gke>.env"
  exit 1
fi

load_env() {
  set -a
  # shellcheck disable=SC1090
  source "$1"
  set +a
}

load_env "${BASE_ENV}"

if [[ -n "${CLOUD_OVERLAY}" ]]; then
  if [[ ! -f "${CLOUD_OVERLAY}" ]]; then
    echo "Cloud overlay not found: ${CLOUD_OVERLAY}"
    exit 1
  fi
  load_env "${CLOUD_OVERLAY}"
fi

if [[ -z "${STACKGUARD_STORAGE_CLASS:-}" ]]; then
  echo "STACKGUARD_STORAGE_CLASS is missing."
  echo "Apply with a cloud overlay, for example:"
  echo "  ./scripts/apply.sh values/stackguard.env values/overlays/aks.env"
  exit 1
fi

render_apply() {
  envsubst < "$1" | kubectl apply -f -
}

render_apply "${MANIFESTS_DIR}/namespace/namespace.yaml"
render_apply "${MANIFESTS_DIR}/config/secret.yaml"
render_apply "${MANIFESTS_DIR}/config/configmap.yaml"
render_apply "${MANIFESTS_DIR}/network/networkpolicy.yaml"
render_apply "${MANIFESTS_DIR}/dashboard/pvc.yaml"
render_apply "${MANIFESTS_DIR}/ai/pvc.yaml"
render_apply "${MANIFESTS_DIR}/server/pvc.yaml"
render_apply "${MANIFESTS_DIR}/postgres/service.yaml"
render_apply "${MANIFESTS_DIR}/postgres/statefulset.yaml"
render_apply "${MANIFESTS_DIR}/dashboard/deployment.yaml"
render_apply "${MANIFESTS_DIR}/dashboard/service.yaml"
render_apply "${MANIFESTS_DIR}/ai/deployment.yaml"
render_apply "${MANIFESTS_DIR}/ai/service.yaml"
render_apply "${MANIFESTS_DIR}/server/deployment.yaml"
render_apply "${MANIFESTS_DIR}/server/service.yaml"

echo "Stackguard deployed (1 pod per service, horizontal scaling disabled)."
echo "Vertical scaling: update CPU/memory/storage in ${BASE_ENV} and re-run this script."
