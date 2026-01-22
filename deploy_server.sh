#!/bin/bash
# deploy_server.sh - 日志中心服务端部署脚本（修正版）

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
# 2. 创建目录
#========================================
create_directories() {
    log_step "创建目录结构..."

    mkdir -p "${LOG_DIR}"/{active,fixed,archive,errors,temp}
    mkdir -p /var/log/rsyslog_center

    chown -R syslog:adm "${LOG_DIR}" 2>/dev/null || chown -R root:root "${LOG_DIR}"
    chmod 755 "${LOG_DIR}"

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
}

#========================================
# 4. rsyslog 配置
#========================================
configure_rsyslog() {
    log_step "生成 rsyslog 配置..."

    rm -f /etc/rsyslog.d/10-log-center.conf

    cat > /etc/rsyslog.d/10-log-center.conf << RSYSLOG_EOF
# 日志中心配置（自动生成）
# Server: ${CENTER_IP}

module(load="imrelp")
module(load="imtcp")
module(load="imudp")

input(type="imrelp" port="${RELP_PORT}" ruleset="nginx_logs")
input(type="imtcp"  port="${TCP_PORT}" ruleset="nginx_logs")
input(type="imudp"  port="${UDP_PORT}" ruleset="nginx_logs")

template(name="ActivePath" type="string"
 string="${LOG_DIR}/active/%syslogtag:R,ERE,1,DFLT:([a-zA-Z0-9_-]+)_access--end%_%fromhost-ip%.log")

template(name="ErrorPath" type="string"
 string="${LOG_DIR}/errors/%syslogtag:R,ERE,1,DFLT:([a-zA-Z0-9_-]+)_error--end%_%fromhost-ip%.log")

template(name="FixedPath" type="string"
 string="${LOG_DIR}/fixed/%syslogtag:R,ERE,1,DFLT:([a-zA-Z0-9_-]+)_(access|error)--end%.log")

template(name="ArchivePath" type="string"
 string="${LOG_DIR}/archive/%\$year%/%\$month%/%\$day%/%syslogtag%_%fromhost-ip%.log")

template(name="LogFmt" type="list") {
    property(name="timereported" dateFormat="rfc3339")
    constant(value=" ")
    property(name="fromhost-ip")
    constant(value=" ")
    property(name="syslogtag")
    constant(value=" ")
    property(name="msg" droplastlf="on")
    constant(value="\n")
}

ruleset(name="nginx_logs") {

    if (\$syslogtag contains '_access') then {
        action(type="omfile" dynaFile="ActivePath" template="LogFmt"
               dirCreateMode="0755" fileCreateMode="0640"
               asyncWriting="on")
        action(type="omfile" dynaFile="FixedPath" template="LogFmt"
               asyncWriting="on")
        action(type="omfile" dynaFile="ArchivePath" template="LogFmt"
               asyncWriting="on")
        stop    # [FIX] 防止重复匹配
    }

    if (\$syslogtag contains '_error') then {
        action(type="omfile" dynaFile="ErrorPath" template="LogFmt"
               dirCreateMode="0755" fileCreateMode="0640"
               asyncWriting="on")
        action(type="omfile" dynaFile="FixedPath" template="LogFmt"
               asyncWriting="on")
        stop    # [FIX]
    }
}
RSYSLOG_EOF
}

#========================================
# 5. logrotate
#========================================
configure_logrotate() {
    log_step "配置 logrotate..."

    cat > /etc/logrotate.d/nginx-log-center << ROTATE_EOF
${LOG_DIR}/active/*.log {
    daily
    rotate 7
    copytruncate
    compress
    delaycompress
    missingok
    notifempty
    create 0640 syslog adm
}

${LOG_DIR}/fixed/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}

${LOG_DIR}/errors/*.log {
    daily
    rotate 14
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
        log_warn "ufw 不存在，跳过"
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
# 7. 清理脚本（只管 archive）
#========================================
create_cleanup_script() {
    cat > /usr/local/bin/log_center_cleanup.sh << EOF
#!/bin/bash
LOG_DIR="${LOG_DIR}"
find "\$LOG_DIR/archive" -name "*.gz" -mtime +90 -delete 2>/dev/null
find "\$LOG_DIR/archive" -type d -empty -delete 2>/dev/null
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
    rsyslogd -N1
    systemctl restart rsyslog
    systemctl enable rsyslog
}

#========================================
# 主流程
#========================================
main() {
    [ "$(id -u)" -eq 0 ] || { log_error "请用 root"; exit 1; }

    install_packages
    create_directories
    backup_configs
    configure_rsyslog
    configure_logrotate
    configure_firewall
    create_cleanup_script
    configure_cron
    restart_services

    log_info "日志中心部署完成 ✅"
    log_info "测试：logger -t site1_access 'hello log center'"
    log_info "监听日志中 (Real-time): tail -f ${LOG_DIR}/active/*.log"
}

main
