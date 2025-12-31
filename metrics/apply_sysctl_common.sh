#!/usr/bin/env bash
set -euo pipefail

# 一键启用“统一系统参数”（用于 A/B 公平对比：ApexMQTT vs EMQX）
# 说明：
# - 本脚本只做“命令行即时生效”的 sysctl 设置（不修改 /etc/sysctl.conf）。
# - 需要 sudo 权限。
# - 目标是减少因为系统默认参数差异导致的性能/稳定性偏差。

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "请使用 sudo 运行：sudo $0" >&2
  exit 1
fi

echo "[1/3] 提升文件描述符/文件表上限（即时生效）"
sysctl -w fs.nr_open=2000000
sysctl -w fs.file-max=2000000

echo "[2/3] 提升连接队列/积压队列深度"
sysctl -w net.core.netdev_max_backlog=65536
sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535

echo "[3/3] TCP 缓冲区与端口相关（与复现指南保持一致）"
sysctl -w net.core.wmem_max=16777216
sysctl -w net.core.rmem_max=16777216
sysctl -w net.ipv4.tcp_wmem="4096 4096 16777216"
sysctl -w net.ipv4.tcp_rmem="4096 4096 16777216"
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.ip_local_port_range="1024 65535"

echo "完成。建议同时在当前 shell 执行：ulimit -n 1048576"


