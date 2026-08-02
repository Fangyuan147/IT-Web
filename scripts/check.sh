#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
echo "project root: ${ROOT}"

command -v python3 >/dev/null && python3 --version
command -v nginx >/dev/null && nginx -v 2>&1 || true

for port in 8000 8001 8002; do
    curl --fail --silent --show-error --max-time 5 "http://127.0.0.1:${port}/health" >/dev/null
    echo "backend ${port}: healthy"
done

curl --fail --silent --show-error --max-time 5 http://localhost/health >/dev/null
echo "nginx localhost: healthy"

if command -v systemctl >/dev/null; then
    systemctl is-active --quiet nginx && echo "nginx service: active"
    systemctl is-active --quiet ops-demo && echo "ops-demo service: active"
    systemctl is-active --quiet ops-demo1 && echo "ops-demo1 service: active"
    systemctl is-active --quiet ops-demo2 && echo "ops-demo2 service: active"
fi
