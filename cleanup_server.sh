#!/bin/bash
# cleanup_server.sh - 清理日志中心服务端配置

set -euo pipefail

#========================================
# 配置区域（需与部署时一致）
#========================================
LOG_DIR="${1:-/data/nginx_logs}"
RELP_PORT="2514"
TCP_PORT="10514"
UDP_PORT="514"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

[ "$(id -u)" -eq 0 ] || { log_error "请使用 root 运行"; exit 1; }

log_info "开始清理服务端配置..."

# 1. 移除 rsyslog 配置
log_info "移除 rsyslog 配置文件..."
rm -f /etc/rsyslog.d/10-log-center.conf

# 2. 移除 logrotate 配置
log_info "移除 logrotate 配置文件..."
rm -f /etc/logrotate.d/nginx-log-center

# 3. 移除定时任务和清理脚本
log_info "移除定时任务和清理脚本..."
rm -f /etc/cron.d/log-center
rm -f /usr/local/bin/log_center_cleanup.sh
rm -f /var/log/rsyslog_center/cleanup.log

# 4. 清理防火墙规则 (UFW)
if command -v ufw &>/dev/null; then
    log_info "清理防火墙规则..."
    ufw delete allow ${RELP_PORT}/tcp || true
    ufw delete allow ${TCP_PORT}/tcp || true
    ufw delete allow ${UDP_PORT}/udp || true
fi

# 5. 重启 rsyslog
log_info "重启 rsyslog 服务..."
systemctl restart rsyslog

# 6. 询问是否删除日志目录
echo -e "${RED}[警告]${NC} 是否删除日志目录 ${LOG_DIR} 及其所有内容? (y/N)"
read -r CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    rm -rf "${LOG_DIR}"
    log_info "日志目录已删除"
else
    log_info "保留日志目录"
fi

log_info "服务端清理完成 ✅"
