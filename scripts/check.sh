#!/usr/bin/env bash


# nginx  服务检测


set -Eeuo pipefail

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config/nginx/sites.conf"
source "$ROOT/config/prometheus/prometheus.conf"

echo "project root: ${ROOT}"

#检测命令状态
for command in curl grep nginx ss systemctl promtool; do
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

if curl --fail --silent --show-error -G \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready" >/dev/null; then
    echo "PASS: Prometheus 已就绪"
else
    echo "FAIL: Prometheus 未就绪" >&2
    exit 1
fi

#
RESULT="$(
    curl --fail --silent --show-error -G \
        --connect-timeout 3 --max-time 5 \
        "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/query" \
        --data-urlencode 'query=probe_success{job="ops-demo-http"}'
)" || {
    echo "FAIL: Prometheus 查询失败" >&2
    exit 1
}

if ! printf '%s' "$RESULT" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)

if payload.get("status") != "success":
    raise SystemExit("Prometheus 返回状态不是 success")

results = payload.get("data", {}).get("result", [])

if len(results) != 4:
    raise SystemExit(f"期望 4 个 HTTP 探测结果，实际得到 {len(results)} 个")

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
#

if curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${PROMETHEUS_NODE_PORT}/metrics" >/dev/null; then
    echo "Prometheus Node Exporter UP"
else
    echo "Prometheus Node Exporter DOWN" >&2
    exit 1
fi

if curl --fail "http://127.0.0.1:${PROMETHEUS_BLACKBOX_PORT}/metrics"; then
    echo "Prometheus Blackbox Exporter UP"
else
    echo "Prometheus Blackbox Exporter DOWN" >&2
    exit 1
fi

if curl --fail "http://127.0.0.1:${GRAFANA_PORT}/api/health";then
    echo "Grafana 服务运行正常"
else
    echo "Grafana 服务运行异常"
    exit 1
fi

# 检测prometheus服务运行和开机自启运行
systemctl is-active --quiet prometheus || {
    echo "FAIL: prometheus 未运行" >&2
    exit 1
}

systemctl is-enabled --quiet prometheus || {
    echo "FAIL: prometheus 未启用开机自启" >&2
    exit 1
}


# 检测 Prometheus Node Exporter 服务运行和开机自启运行
systemctl is-active --quiet prometheus-node-exporter || {
    echo "FAIL: prometheus-node-exporter 未启用开机自启" >&2
    exit 1
}

systemctl is-enabled --quiet prometheus-node-exporter || {
    echo "FAIL: prometheus-node-exporter 未启用开机自启" >&2
    exit 1
}


# 检测 Prometheus Blackbox Exporter 服务运行和开机自启运行
systemctl is-active --quiet prometheus-blackbox-exporter || {
    echo "FAIL: prometheus-blackbox-exporter 未运行" >&2
    exit 1
}

systemctl is-enabled --quiet prometheus-blackbox-exporter || {
    echo "FAIL: prometheus-blackbox-exporter 未启用开机自启" >&2
    exit 1
}


# 检测 Grafana 服务运行和开机自启运行
systemctl is-active --quiet grafana-server || {
    echo "FAIL: grafana-server 未运行" >&2
    exit 1
}

systemctl is-enabled --quiet grafana-server || {
    echo "FAIL: grafana-server 未启用开机自启" >&2
    exit 1
}


# 检测nginx服务运行和开机自启运行
systemctl is-active --quiet nginx || {
    echo "FAIL: nginx 未运行" >&2
    exit 1
}

systemctl is-enabled --quiet nginx || {
    echo "FAIL: nginx 未启用开机自启" >&2
    exit 1
}


# 检测cron服务运行和开机自启运行
systemctl is-active --quiet cron || {
    echo "FAIL: cron 未运行" >&2
    exit 1
}

systemctl is-enabled --quiet cron || {
    echo "FAIL: cron 未启用开机自启" >&2
    exit 1
}


if ! curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${NGINX_PORT}/health" >/dev/null; then
    echo "FAIL: Nginx 健康检查失败" >&2
    exit 1
fi
