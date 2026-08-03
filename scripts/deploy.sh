#!/usr/bin/env bash


# systemd服务、nginx服务、虚拟环境运行脚本


set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/config/nginx/sites.conf"


# ============================================================ #
NGINX_CONF="/etc/nginx/sites-available/ops-demo"
NGINX_LINK="/etc/nginx/sites-enabled/ops-demo"
LOGROTATE_CONF="/etc/logrotate.d/ops-demo"
# ============================================================ #

# EUID 表示当前用户的有效用户UID，0表示root用户
if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 sudo 执行此脚本。" >&2
    exit 1
fi

for command in cp install mkdir nginx python3 systemctl useradd; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "缺少命令：$command" >&2
        exit 1
    }
done

# 检测项目根目录和requirements.txt文件是否存在
[[ -d "$REPO_ROOT" ]] || {
    echo "缺少项目根目录：$REPO_ROOT" >&2
    exit 1
}
[[ -f "$REPO_ROOT/requirements.txt" ]] || {
    echo "缺少 requirements.txt：$REPO_ROOT/requirements.txt" >&2
    exit 1
}

if ! getent passwd "$RUN_USER" >/dev/null; then
    useradd --system --user-group --home-dir "$PROJECT_ROOT" \
        --shell /usr/sbin/nologin "$RUN_USER"
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

# 检测venv虚拟环境是否存在，不存在就创建
if [[ ! -x "$VENV_PATH/bin/python" ]]; then
    echo "创建虚拟环境：$VENV_PATH"
    "$PYTHON_BIN" -m venv "$VENV_PATH"
fi
# 更新配置环境
"$VENV_PATH/bin/python" -m pip install --upgrade pip
"$VENV_PATH/bin/pip" install -r "$PROJECT_ROOT/requirements.txt" \
    "gunicorn==$GUNICORN_VERSION"
chown -R "$RUN_USER:$RUN_GROUP" "$VENV_PATH"

# 编写service脚本代码
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

install -m 0644 "$REPO_ROOT/config/logrotate/ops-demo" "$LOGROTATE_CONF"
ln -sfn "$NGINX_CONF" "$NGINX_LINK"

nginx -t
systemctl daemon-reload

for site in "${SITES[@]}"; do
    IFS='|' read -r SERVICE_NAME APP_PATH APP_PORT UPSTREAM_WEIGHT <<< "$site"
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
done

systemctl enable nginx
systemctl restart nginx

"$PROJECT_ROOT/scripts/health-check.sh"
