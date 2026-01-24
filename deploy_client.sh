#!/bin/bash
# deploy_client.sh - 客户端（站点服务器）Rsyslog 日志转发部署脚本
# 用法：./deploy_client.sh <日志中心IP> [all | "site1 site2"]

set -euo pipefail

#========================================
# 基本配置
#========================================
LOG_CENTER="${1:-}"
SITES="${2:-all}"
RELP_PORT="2514"

SERVER_NAME=$(hostname -s)
SERVER_IP=$(hostname -I | awk '{print $1}')
BACKUP_DIR="/root/rsyslog_backup_$(date +%Y%m%d_%H%M%S)"

#========================================
# 颜色 & 日志函数（日志统一走 stderr）
#========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

#========================================
# 参数检查
#========================================
if [ -z "$LOG_CENTER" ]; then
    log_error "缺少日志中心 IP"
    echo "用法: $0 <日志中心IP> [all | \"site1 site2\"]" >&2
    exit 1
fi

log_info "日志中心地址: ${LOG_CENTER}:${RELP_PORT}"
log_info "本机标识: ${SERVER_NAME} (${SERVER_IP})"

#========================================
# 1. 安装软件包
#========================================
install_packages() {
    log_info "安装 rsyslog 及 RELP 模块..."

    apt-get update -qq
    apt-get install -y rsyslog rsyslog-relp >/dev/null

    if [ ! -f /usr/lib/x86_64-linux-gnu/rsyslog/omrelp.so ]; then
        log_error "RELP 模块 omrelp.so 不存在，安装失败"
        exit 1
    fi

    log_info "软件包安装完成"
}

#========================================
# 2. 备份配置
#========================================
backup_configs() {
    log_info "备份现有配置到 ${BACKUP_DIR}"
    mkdir -p "$BACKUP_DIR"

    [ -f /etc/rsyslog.conf ] && cp /etc/rsyslog.conf "$BACKUP_DIR/"
    [ -d /etc/rsyslog.d ] && cp -r /etc/rsyslog.d "$BACKUP_DIR/"
    [ -f /etc/nginx/nginx.conf ] && cp /etc/nginx/nginx.conf "$BACKUP_DIR/"
    [ -d /etc/nginx/sites-available ] && cp -r /etc/nginx/sites-available "$BACKUP_DIR/"

    log_info "配置备份完成"
}

#========================================
# 3. 自动检测站点（stdout 只输出结果）
#========================================
detect_sites() {
    (
        if [ -d /etc/nginx/sites-available ]; then
            for conf in /etc/nginx/sites-available/*; do
                [ -f "$conf" ] || continue

                grep -h "server_name" "$conf" 2>/dev/null \
                | grep -v "#" \
                | sed 's/server_name//g; s/;//g' \
                | tr -s ' ' '\n' \
                | grep -vE '^(_|\*|localhost|default_server)$' \
                | cut -d'.' -f1 \
                | tr -cd '[:alnum:]_\n-' \
                | grep -v '^www$'
            done
        fi
    ) | sort -u | xargs
}

#========================================
# 4. 配置 rsyslog
#========================================
configure_rsyslog() {
    log_info "生成 rsyslog 转发配置..."

    rm -f /etc/rsyslog.d/9*-nginx-*.conf

    cat > /etc/rsyslog.d/99-nginx-forward.conf <<EOF
module(load="omrelp")
module(load="imudp")
input(type="imudp" address="127.0.0.1" port="514")

# [FIX] 移除了 NginxLogFormat 模板，直接使用默认转发格式
# 这样可以保留 syslogtag，确保服务端规则能够正确匹配

if (\$syslogtag contains "_access") or (\$syslogtag contains "_error") then {
  action(
    type="omrelp"
    target="${LOG_CENTER}"
    port="${RELP_PORT}"
    # 注意：这里不再使用 template="NginxLogFormat"
    # 服务端会通过 fromhost-ip 和 syslogtag 自动格式化日志
    queue.type="LinkedList"
    queue.size="50000"
    queue.filename="nginx_fwd"
    queue.saveonshutdown="on"
    action.resumeRetryCount="-1"
  )
  stop
}

if (\$syslogtag contains "_access") then {
  action(type="omfile" file="/var/log/nginx/rsyslog_access.log")
}

if (\$syslogtag contains "_error") then {
  action(type="omfile" file="/var/log/nginx/rsyslog_error.log")
}
EOF

    log_info "rsyslog 配置完成"
}


#========================================
# 5. Nginx 配置提示
#========================================
print_nginx_hint() {
    log_info "请在 Nginx server 块（或 http 块）中添加以下内容："
    echo ""
    echo "    # 1. 定义通用日志格式"
    echo "    log_format syslog_combined"
    echo "        '\$remote_addr - \$remote_user [\$time_local] '"
    echo "        '\"\$request\" \$status \$body_bytes_sent '"
    echo "        '\"\$http_referer\" \"\$http_user_agent\"';"
    echo ""
    echo "    # 2. 站点日志配置"
    for s in $SITES; do
        echo "    # 站点: $s"
        echo "    access_log syslog:server=127.0.0.1:514,facility=local7,tag=${s}_access,severity=info syslog_combined;"
        echo "    error_log  syslog:server=127.0.0.1:514,facility=local7,tag=${s}_error,severity=error;"
        echo ""
    done
}

#========================================
# 6. 重启并校验服务
#========================================
restart_services() {
    log_info "验证 rsyslog 配置..."
    if ! rsyslogd -N1 >/tmp/rsyslog_check.log 2>&1; then
        log_error "rsyslog 配置错误："
        cat /tmp/rsyslog_check.log >&2
        exit 1
    fi

    systemctl restart rsyslog
    systemctl enable rsyslog >/dev/null

    log_info "rsyslog 已启动"
}

#========================================
# 7. 验证部署
#========================================
verify() {
    log_info "部署验证"

    systemctl is-active --quiet rsyslog \
        && echo "✔ rsyslog 运行中" \
        || echo "✘ rsyslog 未运行"

    logger -p local7.info -t "test_access" "deploy_test_$(date +%H%M%S)"
    sleep 1

    if grep -q deploy_test /var/log/nginx/rsyslog_access.log 2>/dev/null; then
        echo "✔ 本地日志写入正常"
    else
        echo "⚠ 本地日志未命中测试记录"
    fi
}

#========================================
# 主流程
#========================================
main() {
    echo ""
    echo "========================================="
    echo " 客户端 Rsyslog 日志转发部署"
    echo "========================================="
    echo ""

    [ "$(id -u)" -eq 0 ] || { log_error "请使用 root 运行"; exit 1; }

    install_packages
    backup_configs

    if [ "$SITES" = "all" ]; then
        log_info "自动检测 Nginx 站点..."
        SITES=$(detect_sites)
    fi

    log_info "检测到 $(echo "$SITES" | wc -w) 个站点："
    for s in $SITES; do echo "  - $s"; done >&2

    configure_rsyslog
    restart_services
    print_nginx_hint
    verify

    log_info "部署完成，请添加 Nginx 日志配置并 reload nginx"
}

main
