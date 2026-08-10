#!/usr/bin/env bash

# 项目运行前，该脚本负责检测运行环境和下载环境

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# EUID 表示当前用户的有效用户UID，0表示root用户
# 检测当前用户权限
if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 sudo 执行此脚本。" >&2
    exit 1
fi

# 检测必要命令是否存在
for command in apt-get systemctl grep useradd; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "缺少命令：$command" >&2
        exit 1
    }
done

apt-get update
apt-get install -y curl iproute2 logrotate cron
apt-get install -y nginx python3 python3-venv python3-pip
apt-get install -y prometheus prometheus-node-exporter prometheus-blackbox-exporter
apt-get install -y wget gnupg ca-certificates apt-transport-https
apt-get install -y ufw

# UFW部署只能在系统第一次部署
# 部署流程  apt-get update -> apt-get install -y ufw ->
# ufw allow OenSSH(放行SSH)
# ufw allow 80/tcp（放行Nginx）
# ufw allow 3000/tcp (其他电脑访问Grafana)
# ufw status numberd 确认规则无误
# ufw enable 启动

# 安装 Grafana
mkdir -p /etc/apt/keyrings
if ! command -v grafana-server >/dev/null 2>&1; then
    echo "正在安装 Grafana..."
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg >/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
    apt-get update
    apt-get install -y grafana
fi

# 检测安装环境
for command in nginx python3 curl ip ss logrotate cron ufw; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "缺少命令：$command" >&2
        exit 1
    }
done
for command in prometheus promtool prometheus-node-exporter blackbox_exporter grafana-server; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "缺少命令：$command" >&2
        exit 1
    }
done


# 检测安装版本
nginx -v
python3 --version
curl --version
prometheus --version
prometheus-node-exporter --version
blackbox_exporter --version
grafana-server --version


echo "依赖安装完成，正在部署项目..."
