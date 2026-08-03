#!/usr/bin/env bash


# backup.sh 的别名脚本，方便用户执行备份操作



set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/backup.sh" "$@"
