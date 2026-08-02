#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/ops-demo}"
SERVICE_USER="${SERVICE_USER:-opsdemo}"
SERVICE_GROUP="${SERVICE_GROUP:-opsdemo}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "run this script as root, for example: sudo ./scripts/deploy.sh" >&2
    exit 1
fi

if ! getent group "${SERVICE_GROUP}" >/dev/null; then groupadd --system "${SERVICE_GROUP}"; fi
if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
    useradd --system --gid "${SERVICE_GROUP}" --home-dir "${INSTALL_ROOT}" --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

install -d -o "${SERVICE_USER}" -g "${SERVICE_GROUP}" -m 0750 \
    "${INSTALL_ROOT}" "${INSTALL_ROOT}/apps" /var/log/ops-demo /var/backups/ops-demo

if [[ "${PROJECT_ROOT}" != "${INSTALL_ROOT}" ]]; then
    cp -a "${PROJECT_ROOT}/apps/." "${INSTALL_ROOT}/apps/"
    cp -a "${PROJECT_ROOT}/config" "${INSTALL_ROOT}/"
    cp -a "${PROJECT_ROOT}/scripts" "${INSTALL_ROOT}/"
    cp -a "${PROJECT_ROOT}/requirements.txt" "${INSTALL_ROOT}/"
fi

if [[ ! -x "${INSTALL_ROOT}/venv/bin/python" ]]; then python3 -m venv "${INSTALL_ROOT}/venv"; fi
"${INSTALL_ROOT}/venv/bin/pip" install --upgrade pip
"${INSTALL_ROOT}/venv/bin/pip" install -r "${INSTALL_ROOT}/requirements.txt"
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_ROOT}" /var/log/ops-demo /var/backups/ops-demo

install -m 0644 "${PROJECT_ROOT}/config/systemd/ops-demo.service" /etc/systemd/system/
install -m 0644 "${PROJECT_ROOT}/config/systemd/ops-demo1.service" /etc/systemd/system/
install -m 0644 "${PROJECT_ROOT}/config/systemd/ops-demo2.service" /etc/systemd/system/
install -m 0644 "${PROJECT_ROOT}/config/logrotate/ops-demo" /etc/logrotate.d/ops-demo
systemctl daemon-reload
systemctl enable ops-demo ops-demo1 ops-demo2
systemctl restart ops-demo ops-demo1 ops-demo2

if command -v nginx >/dev/null; then
    install -m 0644 "${PROJECT_ROOT}/config/nginx/ops-demo.conf" /etc/nginx/sites-available/ops-demo.conf
    ln -sfn /etc/nginx/sites-available/ops-demo.conf /etc/nginx/sites-enabled/ops-demo.conf
    nginx -t
    systemctl enable nginx
    systemctl reload nginx || systemctl start nginx
fi

echo "deployment completed: ${INSTALL_ROOT}"
