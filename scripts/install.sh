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

# 检测安装环境
for command in nginx python3 curl ip ss logrotate cron; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "缺少命令：$command" >&2
        exit 1
    }
done

nginx -v
python3 --version
curl --version

echo "依赖安装完成，正在部署项目..."
