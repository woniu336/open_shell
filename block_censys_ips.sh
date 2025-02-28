#!/bin/bash
#
# Censys UFW Blocker
# 版本: 1.1.0
# 描述: 自动下载 Censys 扫描器 IP 列表并更新 UFW 防火墙规则
# 最后更新: $(date '+%Y-%m-%d')
#

# 设置错误处理
set -e
trap 'echo "错误发生在第 $LINENO 行"; exit 1' ERR

# 定义变量
CENSYS_IP_LIST_URL="https://support.censys.io/hc/en-us/article_attachments/34972050185876"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/censys_ufw_update.log"
IPv4_LIST="${SCRIPT_DIR}/censys_ipv4.txt"
IPv6_LIST="${SCRIPT_DIR}/censys_ipv6.txt"
TEMP_FILE="${SCRIPT_DIR}/censys_mixed_ips.txt"

# 预定义的风险 IP 地址
declare -a RISK_IPS=(
    "94.154.33.153"
    "185.220.101.29"
    "138.197.191.87"
    "152.42.217.201"
    "149.88.106.138"
    "179.43.191.19"
    "146.190.111.4"
    "185.220.101.190"
    "192.42.116.178"
)

# 预定义的 IDC 扫描范围
declare -a IDC_RANGES=(
    "20.171.206.0/24"
    "52.230.152.0/24"
    "52.233.106.0/24"
    "152.32.128.0/17"
    "103.218.243.0/24"
)

# 预定义的 Facebook IPv4 范围
declare -a FACEBOOK_IPV4=(
    "69.63.176.0/21"
    "69.63.184.0/21"
    "66.220.144.0/20"
    "69.63.176.0/20"
)

# 预定义的 Facebook IPv6 范围
declare -a FACEBOOK_IPV6=(
    "2620:0:1c00::/40"
    "2a03:2880::/32"
    "2a03:2880:fffe::/48"
    "2a03:2880:ffff::/48"
    "2620:0:1cff::/48"
)

# 预定义的 Semrush 范围
declare -a SEMRUSH_RANGES=(
    "85.208.96.0/24"
    "185.191.171.0/24"
)

# 日志函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查并获取 SSH 端口
get_ssh_ports() {
    local ports=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')
    if [ -z "$ports" ]; then
        echo "22"
    else
        echo "$ports"
    fi
}

# 添加或更新 UFW 规则函数
add_or_update_rule() {
    local ip="$1"
    local position="$2"
    
    if ufw status | grep -q "DENY.*$ip"; then
        local rule_num=$(ufw status numbered | grep "$ip" | awk '{print $1}' | tr -d '[]')
        if [ ! -z "$rule_num" ]; then
            log_message "更新规则: $ip"
            ufw --force delete $rule_num
        fi
    fi
    
    if [ ! -z "$position" ]; then
        ufw insert $position deny from "$ip" to any
    else
        ufw deny from "$ip" to any
    fi
}

# 主程序开始
log_message "开始更新 UFW 规则"

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    log_message "错误：此脚本需要 root 权限运行"
    exit 1
fi

# 检查并安装 UFW
if ! command -v ufw &> /dev/null; then
    log_message "UFW 未安装，正在安装..."
    apt update && apt install -y ufw
    if [ $? -ne 0 ]; then
        log_message "UFW 安装失败"
        exit 1
    fi
fi

# 允许 SSH 端口
SSH_PORTS=$(get_ssh_ports)
for port in $SSH_PORTS; do
    ufw allow "$port/tcp"
    log_message "已允许 SSH 端口: $port"
done

# 启用 UFW
ufw --force enable

# 添加预定义的风险 IP
log_message "添加预定义的风险 IP..."
for ip in "${RISK_IPS[@]}"; do
    add_or_update_rule "$ip" 1
done

# 添加预定义的 IDC 范围
log_message "添加预定义的 IDC 范围..."
for range in "${IDC_RANGES[@]}"; do
    add_or_update_rule "$range" 1
done

# 添加预定义的 Facebook IPv4
log_message "添加预定义的 Facebook IPv4 范围..."
for range in "${FACEBOOK_IPV4[@]}"; do
    add_or_update_rule "$range" 1
done

# 添加预定义的 Semrush 范围
log_message "添加预定义的 Semrush 范围..."
for range in "${SEMRUSH_RANGES[@]}"; do
    add_or_update_rule "$range" 1
done

# 下载和处理 Censys IP 列表
log_message "下载 Censys IP 列表..."
if ! curl -s -o "$TEMP_FILE" "$CENSYS_IP_LIST_URL"; then
    log_message "错误：下载 IP 列表失败"
    exit 1
fi

# 初始化 IP 列表文件
> "$IPv4_LIST"
> "$IPv6_LIST"

# 处理下载的 IP 列表
log_message "处理 IP 列表..."
while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r' | tr -d ' ')
    [[ -z "$line" || "$line" =~ ^AS[0-9]+ ]] && continue
    
    if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        echo "$line" >> "$IPv4_LIST"
    elif [[ "$line" =~ : ]]; then
        echo "$line" >> "$IPv6_LIST"
    fi
done < "$TEMP_FILE"

# 处理 IPv4 规则
log_message "添加 Censys IPv4 规则..."
while IFS= read -r subnet; do
    [[ "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]] && add_or_update_rule "$subnet" 1
done < "$IPv4_LIST"

# 查找 IPv6 规则插入位置
FIRST_V6_RULE=$(ufw status numbered | grep '(v6)' | head -n1 | awk -F'[][]' '{print $2}')
if [ -z "$FIRST_V6_RULE" ]; then
    FIRST_V6_RULE=$(ufw status numbered | grep -c '^\[')
    FIRST_V6_RULE=$((FIRST_V6_RULE + 1))
fi

# 添加预定义的 Facebook IPv6
log_message "添加预定义的 Facebook IPv6 范围..."
for range in "${FACEBOOK_IPV6[@]}"; do
    add_or_update_rule "$range" "$FIRST_V6_RULE"
    FIRST_V6_RULE=$((FIRST_V6_RULE + 1))
done

# 处理 IPv6 规则
log_message "添加 Censys IPv6 规则..."
while IFS= read -r subnet; do
    [[ "$subnet" =~ : ]] && add_or_update_rule "$subnet" "$FIRST_V6_RULE"
    FIRST_V6_RULE=$((FIRST_V6_RULE + 1))
done < "$IPv6_LIST"

# 重新加载 UFW
log_message "重新加载 UFW..."
ufw reload

# 统计和清理
IPv4_COUNT=$(wc -l < "$IPv4_LIST")
IPv6_COUNT=$(wc -l < "$IPv6_LIST")
log_message "规则更新完成！"
log_message "IPv4 规则数量: $IPv4_COUNT"
log_message "IPv6 规则数量: $IPv6_COUNT"

# 清理临时文件
rm -f "$TEMP_FILE"

exit 0 