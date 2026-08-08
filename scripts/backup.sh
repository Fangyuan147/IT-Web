#!/usr/bin/env bash


# 自动备份脚本


set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/nginx/sites.conf"

if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 sudo 执行此脚本。" >&2
    exit 1
fi

# 判断是否定义了安装根目录，如果没有定义则使用默认的项目根目录
# 判断定义的备份目录是否存在，如果不存在则使用默认备份目录
INSTALL_ROOT="${INSTALL_ROOT:-$PROJECT_ROOT}"
DEST="${BACKUP_DIR:-$BACKUP_ROOT}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
DATE="$(date '+%F_%H-%M-%S')"
BACKUP="${DEST}/ops-demo_${DATE}.tar.gz"
[[ -d "${INSTALL_ROOT}/apps" ]] || {
    echo "缺少应用目录：${INSTALL_ROOT}/apps" >&2
    exit 1
}
mkdir -p "${DEST}"

SYSTEM_ITEMS=()
# 备份脚本
for item in \
    etc/systemd/system/ops-demo.service \
    etc/systemd/system/ops-demo1.service \
    etc/systemd/system/ops-demo2.service \
    etc/nginx/sites-available/ops-demo \
    etc/nginx/sites-enabled/ops-demo \
    etc/logrotate.d/ops-demo \
    etc/cron.d/ops-demo-backup; do
    if [[ -e "/$item" || -L "/$item" ]]; then
        SYSTEM_ITEMS+=("$item")  # 分别判断是否存在，存在则添加到数组中
    fi
done

# 压缩备份，准备备份文件，排除虚拟环境、缓存文件和环境变量文件
tar \
    --exclude='*/venv' \
    --exclude='*/__pycache__' \
    --exclude='*.pyc' \
    --exclude='.env' \
    --exclude='.env.*' \
    -czf "$BACKUP" \
    -C "$INSTALL_ROOT" apps config scripts requirements.txt \
    -C / "${SYSTEM_ITEMS[@]}"

# 查找并删除超过保留天数的备份文件
find "$DEST" -type f -name 'ops-demo_*.tar.gz' \
    -mtime "+$RETENTION_DAYS" -delete

printf '%s backup=%s\n' "$(date '+%F %T')" "$BACKUP"
