#!/usr/bin/env bash


# systemd服务、nginx服务、虚拟环境运行脚本


set -Eeuo pipefail

# BASH_SOURCE[0] 表示当前脚本的位置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"     #根目录ops-demo
source "$REPO_ROOT/config/nginx/sites.conf"
source "$REPO_ROOT/config/prometheus/prometheus.conf"


# ============================================================ #
CRON_CONF="/etc/cron.d/ops-demo-backup"
NGINX_CONF="/etc/nginx/sites-available/ops-demo"
NGINX_LINK="/etc/nginx/sites-enabled/ops-demo"
LOGROTATE_CONF="/etc/logrotate.d/ops-demo"
# ============================================================ #

# EUID 表示当前用户的有效用户UID，0表示root用户
# 检测当前用户权限
if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 sudo 执行此脚本。" >&2
    exit 1
fi

# 检测项目根目录和requirements.txt文件是否存在
[[ -d "$REPO_ROOT" ]] || {
    echo "缺少项目根目录：$REPO_ROOT" >&2
    exit 1
}
[[ -f "$REPO_ROOT/requirements.txt" ]] || {
    echo "缺少 requirements.txt：$REPO_ROOT/requirements.txt" >&2
    exit 1
}

# 创建运行用户和组
if ! getent passwd "$RUN_USER" >/dev/null; then
    useradd --system --user-group --home-dir "$PROJECT_ROOT" \
        --shell /usr/sbin/nologin "$RUN_USER"           # --shell 禁止用户登录终端
fi

RUN_GROUP="$(id -gn "$RUN_USER")"

echo "安装项目到：$PROJECT_ROOT"
mkdir -p "$PROJECT_ROOT" "$LOG_ROOT" "$BACKUP_ROOT"

# 当脚本从项目副本运行时，复制应用、配置、脚本和依赖清单。
# 如果项目本身就在 /opt/ops-demo，则跳过自我复制。
if [[ "$REPO_ROOT" != "$PROJECT_ROOT" ]]; then
    cp -a "$REPO_ROOT/apps" "$PROJECT_ROOT/"
    cp -a "$REPO_ROOT/config" "$PROJECT_ROOT/"
    cp -a "$REPO_ROOT/scripts" "$PROJECT_ROOT/"
    cp -a "$REPO_ROOT/requirements.txt" "$PROJECT_ROOT/"
fi

chmod +x "$PROJECT_ROOT/scripts"/*.sh
chown -R "$RUN_USER:$RUN_GROUP" "$PROJECT_ROOT/apps" "$LOG_ROOT"


# 检测python环境是否可执行
if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "Python 不存在或不可执行：$PYTHON_BIN" >&2
    exit 1
fi

# 检测venv虚拟环境中python是否可执行，如果不能则创建虚拟环境和下载python环境
if [[ ! -x "$VENV_PATH/bin/python" ]]; then
    echo "创建虚拟环境：$VENV_PATH"
    "$PYTHON_BIN" -m venv "$VENV_PATH"
fi
# 升级pip和安装依赖包
"$VENV_PATH/bin/python" -m pip install --upgrade pip
"$VENV_PATH/bin/pip" install -r "$PROJECT_ROOT/requirements.txt"
chown -R "$RUN_USER:$RUN_GROUP" "$VENV_PATH"

# 编写systemd脚本代码
for site in "${SITES[@]}"; do
    IFS='|' read -r SERVICE_NAME APP_PATH APP_PORT UPSTREAM_WEIGHT <<< "$site"

    echo "配置服务：$SERVICE_NAME，端口：$APP_PORT，应用路径：$APP_PATH"
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=$SERVICE_NAME Flask application
After=network.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_GROUP
WorkingDirectory=$APP_PATH
ExecStart=$VENV_PATH/bin/gunicorn --workers 2 --chdir $APP_PATH \
  --bind 127.0.0.1:$APP_PORT \
  --access-logfile $LOG_ROOT/${SERVICE_NAME}-access.log \
  --error-logfile $LOG_ROOT/${SERVICE_NAME}-error.log app:app
Restart=on-failure
RestartSec=5
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true

[Install]
WantedBy=multi-user.target
EOF
done


# 编写ngnix脚本代码
{
    echo "upstream ops_demo_backend {"
    for site in "${SITES[@]}"; do
        IFS='|' read -r SERVICE_NAME APP_PATH APP_PORT UPSTREAM_WEIGHT <<< "$site"
        echo "    server 127.0.0.1:${APP_PORT} weight=${UPSTREAM_WEIGHT};"
    done
    cat <<EOF
}

server {
    listen $NGINX_PORT;
    listen [::]:$NGINX_PORT;
    server_name localhost;

    access_log /var/log/nginx/ops-demo-access.log;
    error_log /var/log/nginx/ops-demo-error.log;

    location / {
        proxy_pass http://ops_demo_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
EOF
} > "$NGINX_CONF"

# 安装cron定时任务配置文件
install -m 0644 "$REPO_ROOT/config/cron/ops-demo-backup" "$CRON_CONF"
# 安装logrotate配置文件
install -m 0644 "$REPO_ROOT/config/logrotate/ops-demo" "$LOGROTATE_CONF"
ln -sfn "$NGINX_CONF" "$NGINX_LINK"

# 检测脚本生成服务情况
nginx -t
systemctl daemon-reload

# Web 运行服务
for site in "${SITES[@]}"; do
    IFS='|' read -r SERVICE_NAME APP_PATH APP_PORT UPSTREAM_WEIGHT <<< "$site"
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
done

# 创建prometheus和grafana文件目录并配置权限
install -d -m 0755 /etc/prometheus/rules
install -d -m 0755 /etc/grafana/provisioning/datasources
install -d -m 0755 /etc/grafana/dashboards/ops-demo
install -d -m 0755 /etc/grafana/provisioning/dashboards

# install -m 把脚本的文件内容复制到系统文件中
install -m 0644 \
    "$REPO_ROOT/config/prometheus/prometheus.yml" \
    "$PROMETHEUS_CONFIG_FILE"
install -m 0644 \
    "$REPO_ROOT/config/prometheus/blackbox.yml" \
    "$PROMETHEUS_BLACKBOX_CONFIG_FILE"
install -m 0644 \
    "$REPO_ROOT/config/prometheus/alertmanager.yml" \
    "$PROMETHEUS_ALERTMANAGER_FILE"
install -m 0644 \
    "$REPO_ROOT/config/prometheus/rules/ops-demo.yml" \
    "$PROMETHEUS_RULES_FILE"
install -m 0644 \
    "$REPO_ROOT/config/grafana/provisioning/prometheus.yml" \
    "$GRAFANA_PROMETHEUS_FILE"
install -m 0644 \
    "$REPO_ROOT/config/grafana/dashboards/ops-demo-overview.json" \
    "$GRAFANA_DASHBOARD_JSON_FILE"
install -m 0644 \
    "$REPO_ROOT/config/grafana/provisioning/dashboards/ops-demo.yml" \
    "$GRAFANA_DASHBOARD_OPS_DEMO_FILE"

# 检测 Prometheus 配置
if ! promtool check config "$PROMETHEUS_CONFIG_FILE"; then
    echo "Prometheus 配置错误"
    exit 1
fi

# 检测Prometheus rule配置
if ! promtool check rules "$PROMETHEUS_RULES_FILE"; then
    echo "Prometheus 规则错误"
    exit 1
fi

# 检测 Prometheus Blackbox 配置
if ! prometheus-blackbox-exporter \
    --config.file="$PROMETHEUS_BLACKBOX_CONFIG_FILE" \
    --config.check; then
    echo "Blackbox 配置错误"
    exit 1
fi

# 检测Prometheus alertmanager 配置
if ! amtool check-config "$PROMETHEUS_ALERTMANAGER_FILE";then
    echo "alertmanager 配置错误"
    exit 1
fi
# 查看防火墙配置
ufw status verbose

# 启动prometheus 服务
systemctl enable --now prometheus
systemctl enable --now prometheus-node-exporter
systemctl enable --now prometheus-blackbox-exporter
systemctl enable --now prometheus-alertmanager
systemctl restart prometheus
systemctl restart prometheus-node-exporter
systemctl restart prometheus-blackbox-exporter
systemctl restart prometheus-alertmanager

# 启动 cron 服务
systemctl enable cron
systemctl restart cron

# 启动 Nginx 服务
systemctl enable nginx
systemctl restart nginx

# 启动 Grafana 服务
systemctl enable grafana-server
systemctl restart grafana-server

# 等待Grafana服务启动，否则会导致部署失败
echo "等待 Grafana 启动..."

for attempt in {1..30}; do
    if curl --fail --silent --show-error \
        "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
        >/dev/null 2>&1; then
        echo "PASS: Grafana 已就绪"
        break
    fi

    if [[ "$attempt" -eq 30 ]]; then
        echo "FAIL: Grafana 在 30 秒内未就绪" >&2
        systemctl status grafana-server --no-pager >&2
        journalctl -u grafana-server -n 50 --no-pager >&2
        exit 1
    fi

    sleep 1
done

echo "项目部署完成"

echo "正在检测服务运行状态和健康状况..."
# 运行结束后，检测服务运行状况
bash $SCRIPT_DIR/check.sh
