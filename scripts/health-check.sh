#!/usr/bin/env bash


# nginx服务状态和健康检测脚本


set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # 记录当前脚本所在目录
source "$SCRIPT_DIR/../config/nginx/sites.conf"


# 检测nginx运行状态
systemctl is-active --quiet nginx || {
    echo "FAIL: nginx 未运行" >&2
    exit 1
}

for site in "${SITES[@]}"; do
    IFS='|' read -r SERVICE_NAME APP_PATH APP_PORT UPSTREAM_WEIGHT <<< "$site"
    # 逐一检测服务运行状态
    systemctl is-active --quiet "$SERVICE_NAME" || {
        echo "FAIL: $SERVICE_NAME 未运行" >&2
        exit 1
    }
    # 逐一检测服务健康状态
    if ! curl --fail --silent --show-error \
        --connect-timeout 3 --max-time 5 \
        "http://127.0.0.1:${APP_PORT}/health" >/dev/null 2>&1; then
        echo "FAIL: $SERVICE_NAME 健康检查失败，端口：$APP_PORT" >&2
        exit 1
    fi
    # 运行通过
    echo "PASS: $SERVICE_NAME :$APP_PORT"
done

# 检测nginx端口状态 80端口
if ! curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${NGINX_PORT}/health" >/dev/null 2>&1; then
    echo "FAIL: Nginx 统一入口健康检查失败，端口：$NGINX_PORT" >&2
    exit 1
fi

echo "PASS: Nginx 全部端口成功运行"
