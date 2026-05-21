#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
VALUES_DIR="${ROOT_DIR}/values"

BASE_ENV="${1:-${VALUES_DIR}/stackguard.env}"
CLOUD_OVERLAY="${2:-}"

if [[ ! -f "${BASE_ENV}" ]]; then
  echo "Base values file not found: ${BASE_ENV}"
  exit 1
fi

load_env() {
  set -a
  # shellcheck disable=SC1090
  source "$1"
  set +a
}

load_env "${BASE_ENV}"
if [[ -n "${CLOUD_OVERLAY}" && -f "${CLOUD_OVERLAY}" ]]; then
  load_env "${CLOUD_OVERLAY}"
fi

envsubst < "${MANIFESTS_DIR}/autoscaling/vpa.yaml" | kubectl apply -f -
echo "VPA resources applied with updateMode=${VPA_UPDATE_MODE:-Off}."
