#!/usr/bin/env bash

set -Eeuo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/ops-demo}"
DEST="${BACKUP_DIR:-/var/backups/ops-demo}"
DATE="$(date '+%F_%H-%M-%S')"
BACKUP="${DEST}/ops-demo_${DATE}.tar.gz"

[[ -d "${INSTALL_ROOT}/apps" ]] || { echo "missing ${INSTALL_ROOT}/apps" >&2; exit 1; }
mkdir -p "${DEST}"

tar --exclude='*/venv' --exclude='*/__pycache__' --exclude='*.pyc' \
    --exclude='.env' --exclude='.env.*' \
    -czf "${BACKUP}" -C "${INSTALL_ROOT}" apps config scripts requirements.txt

find "${DEST}" -type f -name 'ops-demo_*.tar.gz' -mtime +7 -delete
printf '%s backup=%s\n' "$(date '+%F %T')" "${BACKUP}"
