#!/bin/bash
# cleanup_rsyslog_client.sh
# 清理 deploy_client.sh 产生的所有配置和痕迹

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

[ "$(id -u)" -eq 0 ] || { err "请使用 root 运行"; exit 1; }

echo ""
echo "========================================="
echo " 清理 Rsyslog / Nginx 日志转发客户端"
echo "========================================="
echo ""

#----------------------------------------
# 1. 清理 rsyslog 配置
#----------------------------------------
log "清理 rsyslog 转发配置..."

CONF_FILES=(
  /etc/rsyslog.d/99-nginx-forward.conf
  /etc/rsyslog.d/98-nginx-forward.conf
)

for f in "${CONF_FILES[@]}"; do
  if [ -f "$f" ]; then
    rm -f "$f"
    log "已删除 $f"
  fi
done

# 清理 rsyslog 队列文件
log "清理 rsyslog 磁盘队列..."
rm -f /var/lib/rsyslog/nginx_fwd* 2>/dev/null || true

#----------------------------------------
# 2. 清理本地测试日志
#----------------------------------------
log "清理本地 rsyslog 调试日志..."
rm -f /var/log/nginx/rsyslog_access.log
rm -f /var/log/nginx/rsyslog_error.log

#----------------------------------------
# 3. 清理 nginx syslog 相关文件
#----------------------------------------
log "清理 Nginx syslog 配置..."

rm -f /etc/nginx/conf.d/syslog-logging.conf
rm -f /etc/nginx/conf.d/site-*-logging.conf
rm -f /etc/nginx/conf.d/README-syslog.conf

#----------------------------------------
# 4. 重启 rsyslog
#----------------------------------------
log "重启 rsyslog..."
systemctl restart rsyslog

#----------------------------------------
# 5. 校验
#----------------------------------------
log "验证 rsyslog 状态..."
if systemctl is-active --quiet rsyslog; then
    log "rsyslog 正常运行"
else
    err "rsyslog 未运行，请手动检查"
fi

echo ""
warn "⚠ 注意：请手动从 Nginx server 块中删除以下内容（如果已添加）："
echo "  access_log syslog:server=127.0.0.1:514 ..."
echo "  error_log  syslog:server=127.0.0.1:514 ..."
echo ""

log "清理完成"
