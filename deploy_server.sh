#!/bin/bash
# deploy_server_optimized.sh - 日志中心服务端部署脚本（精简优化版）

set -euo pipefail

#========================================
# 配置区域
#========================================
LOG_DIR="${1:-/data/nginx_logs}"
RELP_PORT="2514"
TCP_PORT="10514"
UDP_PORT="514"
CENTER_IP=$(hostname -I | awk '{print $1}')
BACKUP_DIR="/root/rsyslog_backup_$(date +%Y%m%d_%H%M%S)"

#========================================
# 颜色输出
#========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

#========================================
# 1. 安装软件
#========================================
install_packages() {
    log_step "安装必要软件包..."

    apt-get update -qq
    apt-get install -y rsyslog rsyslog-relp logrotate tree curl

    if ! command -v ufw &>/dev/null; then
        apt-get install -y ufw
    fi

    # [FIX] 功能级检测 RELP
    if ! ls /usr/lib/*/rsyslog/imrelp.so >/dev/null 2>&1; then
        log_error "rsyslog 未安装 imrelp 模块（RELP 不可用）"
        exit 1
    fi

    log_info "软件包安装完成"
}

#========================================
# 2. 创建目录 (仅保留 active 和 errors)
#========================================
create_directories() {
    log_step "创建优化的目录结构..."

    # 1. 实时日志：按客户端IP分类
    mkdir -p "${LOG_DIR}/active"
    
    # 2. 错误日志：单独存储，方便排查
    mkdir -p "${LOG_DIR}/errors"

    # 3. 系统运行日志目录
    mkdir -p /var/log/rsyslog_center

    # 设置权限
    chown -R syslog:adm "${LOG_DIR}" 2>/dev/null || chown -R root:root "${LOG_DIR}"
    chmod -R 755 "${LOG_DIR}"

    tree -L 1 "${LOG_DIR}"
}

#========================================
# 3. 备份配置
#========================================
backup_configs() {
    log_step "备份 rsyslog 配置..."
    mkdir -p "$BACKUP_DIR"
    [ -f /etc/rsyslog.conf ] && cp /etc/rsyslog.conf "$BACKUP_DIR/"
    [ -d /etc/rsyslog.d ] && cp -r /etc/rsyslog.d "$BACKUP_DIR/"
    log_info "配置已备份至: $BACKUP_DIR"
}

#========================================
# 4. rsyslog 配置 (精简版，只写一份文件)
#========================================
configure_rsyslog() {
    log_step "生成 rsyslog 配置..."

    rm -f /etc/rsyslog.d/10-log-center.conf

    cat > /etc/rsyslog.d/10-log-center.conf << RSYSLOG_EOF
# 日志中心配置（精简优化版）
# Server: ${CENTER_IP}

module(load="imrelp")
module(load="imtcp")
module(load="imudp")

# 开启监听
input(type="imrelp" port="${RELP_PORT}" ruleset="nginx_logs")
input(type="imtcp"  port="${TCP_PORT}" ruleset="nginx_logs")
input(type="imudp"  port="${UDP_PORT}" ruleset="nginx_logs")

# 模板：Active 日志路径 (按 IP 分目录)
template(name="ActivePath" type="string"
 string="${LOG_DIR}/active/%fromhost-ip%/%syslogtag:R,ERE,1,DFLT:([a-zA-Z0-9_-]+)_access--end%.log")

# 模板：Error 日志路径 (按 IP 分目录)
template(name="ErrorPath" type="string"
 string="${LOG_DIR}/errors/%fromhost-ip%/%syslogtag:R,ERE,1,DFLT:([a-zA-Z0-9_-]+)_error--end%.log")

# 模板：日志格式 (去除开头多余空格)
template(name="LogFmt" type="list") {
    property(name="msg" droplastlf="on" position.from="2")
    constant(value="\n")
}

ruleset(name="nginx_logs") {

    # 处理 Access 日志
    if (\$syslogtag contains '_access') then {
        action(type="omfile" dynaFile="ActivePath" template="LogFmt"
               dirCreateMode="0755" fileCreateMode="0640"
               asyncWriting="on")
        stop    # 阻止继续向下匹配
    }

    # 处理 Error 日志
    if (\$syslogtag contains '_error') then {
        action(type="omfile" dynaFile="ErrorPath" template="LogFmt"
               dirCreateMode="0755" fileCreateMode="0640"
               asyncWriting="on")
        stop
    }
}
RSYSLOG_EOF

    log_info "rsyslog 配置生成完毕"
}

#========================================
# 5. logrotate (仅对 active 和 errors 生效)
#========================================
configure_logrotate() {
    log_step "配置 logrotate..."

    cat > /etc/logrotate.d/nginx-log-center << ROTATE_EOF
# Active 日志轮转 (保留7天)
${LOG_DIR}/active/*/*.log {
    daily
    rotate 7
    copytruncate
    compress
    delaycompress
    missingok
    notifempty
    create 0640 syslog adm
}

# Error 日志轮转 (保留14天，因为错误日志通常更重要，需要更久追溯)
${LOG_DIR}/errors/*/*.log {
    daily
    rotate 14
    copytruncate
    compress
    delaycompress
    missingok
    notifempty
}
ROTATE_EOF
}

#========================================
# 6. 防火墙
#========================================
configure_firewall() {
    log_step "配置防火墙..."

    if ! command -v ufw &>/dev/null; then
        log_warn "ufw 不存在，跳过防火墙配置"
        return
    fi

    ufw allow ${RELP_PORT}/tcp comment 'rsyslog RELP' >/dev/null
    ufw allow ${TCP_PORT}/tcp comment 'rsyslog TCP'  >/dev/null
    ufw allow ${UDP_PORT}/udp comment 'rsyslog UDP'  >/dev/null

    if ufw status | grep -q inactive; then
        log_warn "ufw 未启用，仅添加规则（未强制 enable）"
    fi
}

#========================================
# 7. 清理脚本 (清理压缩包)
#========================================
create_cleanup_script() {
    # 由于 archive 目录已删除，这里主要用于清理 logrotate 生成的旧压缩包
    # logrotate 自身会控制数量，但为了保险，清理 30 天以前的旧 .gz 文件
    cat > /usr/local/bin/log_center_cleanup.sh << EOF
#!/bin/bash
# 清理超过 30 天的已压缩日志 (logrotate 应该已经删除了，但这作为双重保险)
LOG_DIR="${LOG_DIR}"
find "\$LOG_DIR/active" -name "*.gz" -mtime +30 -delete 2>/dev/null
find "\$LOG_DIR/errors" -name "*.gz" -mtime +30 -delete 2>/dev/null
find "\$LOG_DIR" -type d -empty -delete 2>/dev/null
EOF
    chmod +x /usr/local/bin/log_center_cleanup.sh
}

#========================================
# 8. cron
#========================================
configure_cron() {
    cat > /etc/cron.d/log-center << EOF
0 3 * * * root /usr/local/bin/log_center_cleanup.sh >> /var/log/rsyslog_center/cleanup.log 2>&1
EOF
}

#========================================
# 9. 重启验证
#========================================
restart_services() {
    log_step "重启 rsyslog 服务..."
    rsyslogd -N1
    systemctl restart rsyslog
    systemctl enable rsyslog
    log_info "服务状态: $(systemctl is-active rsyslog)"
}

#========================================
# 主流程
#========================================
main() {
    [ "$(id -u)" -eq 0 ] || { log_error "请使用 root 用户运行此脚本"; exit 1; }

    log_info "开始部署日志中心 (优化版)..."
    log_info "日志存储根目录: ${LOG_DIR}"

    install_packages
    create_directories
    backup_configs
    configure_rsyslog
    configure_logrotate
    configure_firewall
    create_cleanup_script
    configure_cron
    restart_services

    echo ""
    log_info "日志中心部署完成 ✅"
    log_info "-------------------------------------------"
    log_info "目录结构:"
    log_info "  实时日志: ${LOG_DIR}/active/{IP}/"
    log_info "  错误日志: ${LOG_DIR}/errors/{IP}/"
    log_info "-------------------------------------------"
    log_info "测试命令:"
    log_info "  logger -t site1_access 'hello world'"
    log_info "  tail -f ${LOG_DIR}/active/127.0.0.1/site1_access.log"
    log_info "-------------------------------------------"
}

main
