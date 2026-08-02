#!/usr/bin/env bash

set -Eeuo pipefail

URL="${HEALTH_URL:-http://localhost/health}"
LOG="${HEALTH_LOG:-/var/log/ops-demo/health-check.log}"
mkdir -p "$(dirname -- "${LOG}")"

if curl --fail --silent --show-error --max-time 5 "${URL}" >/dev/null; then
    printf '%s status=healthy url=%s\n' "$(date '+%F %T')" "${URL}" >>"${LOG}"
    exit 0
fi

printf '%s status=unhealthy action=restart url=%s\n' "$(date '+%F %T')" "${URL}" >>"${LOG}"
if [[ "${EUID}" -ne 0 ]]; then
    echo "health check failed; automatic recovery requires root privileges" >&2
    exit 1
fi

systemctl restart ops-demo ops-demo1 ops-demo2
systemctl reload nginx 2>/dev/null || true
