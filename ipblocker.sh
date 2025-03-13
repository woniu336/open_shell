#!/bin/bash
set -e

# 唯一标识符 (防止与其他规则冲突)
PREFIX="IPBLOCKER"
IPSET_NAME="${PREFIX}_BANNED_IPS"
IPTABLES_CHAIN="${PREFIX}_BANNED_CHAIN"
CONFIG_DIR="/etc/${PREFIX}"
LOG_FILE="/var/log/${PREFIX}.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志记录函数
log() {
  local level=$1
  local message=$2
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${NC}"
  logger -t "${PREFIX}" "[${level}] ${message}"
}

# 检查 root 权限
check_root() {
  if [ "$EUID" -ne 0 ]; then
    log "ERROR" "请使用 root 权限运行此脚本"
    exit 1
  fi
}

# 检查依赖工具
check_requirements() {
  local missing_tools=()
  for tool in ipset iptables wget awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done

  if [ ${#missing_tools[@]} -ne 0 ]; then
    log "ERROR" "缺少必要的工具: ${missing_tools[*]}"
    echo "安装命令:"
    echo "Debian/Ubuntu: apt-get install iptables ipset wget"
    echo "CentOS/RHEL: yum install iptables ipset wget"
    exit 1
  fi
}

# 初始化防火墙规则
init_firewall() {
  log "INFO" "正在初始化防火墙规则..."

  # 清理旧规则 (仅处理本脚本创建的)
  cleanup_rules silent

  # 创建 ipset
  if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
    ipset create "$IPSET_NAME" hash:ip hashsize 65536 maxelem 1000000
  fi

  # 创建 iptables 链
  if ! iptables -nL "$IPTABLES_CHAIN" >/dev/null 2>&1; then
    iptables -N "$IPTABLES_CHAIN"
    iptables -I INPUT -j "$IPTABLES_CHAIN"
    iptables -I FORWARD -j "$IPTABLES_CHAIN"
    iptables -A "$IPTABLES_CHAIN" -m set --match-set "$IPSET_NAME" src -j DROP
  fi

  log "INFO" "防火墙规则初始化完成"
}

# 更新 IP 黑名单
update_blacklist() {
  log "INFO" "开始更新 IP 黑名单..."
  mkdir -p "$CONFIG_DIR"
  
  local tmp_file="${CONFIG_DIR}/abuseipdb.tmp"
  local target_file="${CONFIG_DIR}/abuseipdb.list"

  if ! wget -q -O "$tmp_file" https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-1d.ipv4; then
    log "ERROR" "黑名单下载失败"
    return 1
  fi

  if [ ! -s "$tmp_file" ]; then
    log "ERROR" "下载文件为空"
    rm -f "$tmp_file"
    return 1
  fi

  # 验证文件格式
  if ! grep -Pq '^\d+\.\d+\.\d+\.\d+$' "$tmp_file"; then
    log "ERROR" "文件格式验证失败"
    return 1
  fi

  # 原子操作替换文件
  mv "$tmp_file" "$target_file"

  # 创建临时 ipset
  ipset create "${IPSET_NAME}_tmp" hash:ip hashsize 65536 maxelem 1000000

  # 填充数据
  while read -r ip; do
    ipset add "${IPSET_NAME}_tmp" "$ip" 2>/dev/null || log "WARN" "无效IP: $ip"
  done < <(grep -v '^#' "$target_file")

  # 原子替换
  ipset swap "${IPSET_NAME}_tmp" "$IPSET_NAME"
  ipset destroy "${IPSET_NAME}_tmp"

  log "INFO" "黑名单更新完成，当前记录数: $(ipset list "$IPSET_NAME" | grep '^Number' | awk '{print $2}')"
}

# 清理规则 (仅处理本脚本创建的)
cleanup_rules() {
  local silent=${1:-}
  [ -z "$silent" ] && log "INFO" "正在清理防火墙规则..."

  # 删除 iptables 规则
  iptables -D INPUT -j "$IPTABLES_CHAIN" 2>/dev/null || true
  iptables -D FORWARD -j "$IPTABLES_CHAIN" 2>/dev/null || true
  iptables -F "$IPTABLES_CHAIN" 2>/dev/null || true
  iptables -X "$IPTABLES_CHAIN" 2>/dev/null || true

  # 删除 ipset
  ipset destroy "$IPSET_NAME" 2>/dev/null || true
  ipset destroy "${IPSET_NAME}_tmp" 2>/dev/null || true

  [ -z "$silent" ] && log "INFO" "防火墙规则清理完成"
}

# 定时任务脚本
setup_cron() {
  log "INFO" "正在配置定时任务..."
  mkdir -p /etc/cron.d

  # 创建每日更新脚本
  cat > /etc/cron.d/${PREFIX}_daily <<EOF
#!/bin/bash
${0} update >/dev/null 2>&1
EOF

  # 创建启动加载脚本
  cat > /etc/cron.d/${PREFIX}_boot <<EOF
#!/bin/bash
${0} init >/dev/null 2>&1
EOF

  # 设置定时任务
  echo "0 5 * * * root /bin/bash /etc/cron.d/${PREFIX}_daily" > /etc/cron.d/${PREFIX}
  echo "@reboot root /bin/bash /etc/cron.d/${PREFIX}_boot" >> /etc/cron.d/${PREFIX}

  systemctl restart cron 2>/dev/null || systemctl restart crond
  log "INFO" "定时任务配置完成"
}

# 显示状态
show_status() {
  echo -e "\n${YELLOW}=== 防火墙状态 ==="
  echo -e "${GREEN}[IPSet]${NC}"
  ipset list "$IPSET_NAME" 2>/dev/null || echo "未找到黑名单集合"
  
  echo -e "\n${GREEN}[IPTables]${NC}"
  iptables -nL "$IPTABLES_CHAIN" 2>/dev/null || echo "未找到防火墙链"
  
  echo -e "\n${GREEN}[定时任务]${NC}"
  ls /etc/cron.d/${PREFIX}* 2>/dev/null || echo "未配置定时任务"
}

# 帮助信息
show_help() {
  echo -e "${YELLOW}使用方法: $0 [命令]"
  echo "命令列表:"
  echo "  init     初始化防火墙规则"
  echo "  update   更新黑名单"
  echo "  cron     配置定时任务"
  echo "  clean    清理所有规则"
  echo "  status   显示当前状态"
  echo "  help     显示帮助信息"
}

# 主程序
main() {
  check_root
  check_requirements

  case $1 in
    init)    init_firewall ;;
    update)  update_blacklist ;;
    cron)    setup_cron ;;
    clean)   cleanup_rules ;;
    status)  show_status ;;
    help)    show_help ;;
    *)       show_help; exit 1 ;;
  esac
}

main "$@"