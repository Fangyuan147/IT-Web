#!/usr/bin/env bash


# nginx功能检测脚本


set -Eeuo pipefail

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config/nginx/sites.conf"

echo "project root: ${ROOT}"

#检测命令状态
for command in curl grep nginx ss systemctl; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "FAIL: 缺少命令：$command" >&2
        exit 1
    }
done

python3 --version
nginx -v 2>&1
nginx -t

# 检测nginx配置文件是否存在
for site in "${SITES[@]}"; do
    IFS='|' read -r SERVICE_NAME APP_PATH APP_PORT UPSTREAM_WEIGHT <<< "$site"
    # 服务状态检测
    systemctl is-active --quiet "$SERVICE_NAME" || {
        echo "FAIL: 服务未运行：$SERVICE_NAME" >&2
        exit 1
    }
    # 服务开机自启检测
    systemctl is-enabled --quiet "$SERVICE_NAME" || {
        echo "FAIL: 服务未启用开机自启：$SERVICE_NAME" >&2
        exit 1
    }
    # 端口监听检测
    if ! ss -lnt | grep -Eq "127\.0\.0\.1:${APP_PORT}[[:space:]]"; then
        echo "FAIL: 端口未按预期监听：127.0.0.1:${APP_PORT}" >&2
        exit 1
    fi
    curl --fail --silent --show-error --connect-timeout 3 --max-time 5 \
        "http://127.0.0.1:${APP_PORT}/health" >/dev/null
    echo "PASS: backend ${SERVICE_NAME} ${APP_PORT}"
done

# 检测nginx服务运行和开机自启运行
systemctl is-active --quiet nginx || {
    echo "FAIL: nginx 未运行" >&2
    exit 1
}
systemctl is-enabled --quiet nginx || {
    echo "FAIL: nginx 未启用开机自启" >&2
    exit 1
}

curl --fail --silent --show-error --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${NGINX_PORT}/health" >/dev/null
echo "PASS: nginx 功能全部齐全"
