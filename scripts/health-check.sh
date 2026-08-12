#!/usr/bin/env bash


# 各类服务状态和健康检测脚本


set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # 记录当前脚本所在目录
source "$SCRIPT_DIR/../config/nginx/sites.conf"
source "$SCRIPT_DIR/../config/prometheus/prometheus.conf"

# 检测nginx运行状态
systemctl is-active --quiet nginx || {
    echo "FAIL: nginx 未运行" >&2
    exit 1
}
# 检测cron运行状态
systemctl is-active --quiet cron || {
    echo "FAIL: cron 未运行" >&2
    exit 1
}

if ! curl --fail --silent --show-error -G \
    --connect-timeout 3 --max-time 5 \
    http://127.0.0.1:${PROMETHEUS_PORT}/-/ready; then
    echo "prometheus  未就绪" >&2
    exit 1
fi

RESULT="$(
    curl --fail --silent --show-error -G \
        --connect-timeout 3 --max-time 5 \
        "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/query" \
        --data-urlencode 'query=probe_success{job="ops-demo-http"}'
    )" || {
    echo "FAIL: Prometheus HTTP 探测查询失败" >&2
    exit 1
}

if ! printf '%s' "$RESULT" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)

if payload.get("status") != "success":
    raise SystemExit("Prometheus 返回状态不是 success")

results = payload.get("data", {}).get("result", [])

if len(results) != 3:
    raise SystemExit(f"期望 3 个 HTTP 探测结果，实际得到 {len(results)} 个")

if not all(
    isinstance(item.get("value"), list)
    and len(item["value"]) >= 2
    and item["value"][1] == "1"
    for item in results
):
    raise SystemExit("至少一个 HTTP 探测目标失败")
'; then
    echo "FAIL: HTTP 探测数据异常" >&2
    exit 1
fi

echo "PASS: 4 个 HTTP 探测目标均正常"

if ! curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${PROMETHEUS_NODE_PORT}/metrics" >/dev/null; then
    echo "Prometheus Node Exporter DOWN" >&2
    exit 1
fi

if ! curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${PROMETHEUS_BLACKBOX_PORT}/metrics"; then
    echo "Prometheus Blackbox Exporter DOWN" >&2
    exit 1
fi

if ! curl --fail "http://127.0.0.1:${GRAFANA_PORT}/api/health";then
    echo "Grafana 服务健康检查失败"
    exit 1
fi

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
