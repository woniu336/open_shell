#!/bin/bash
#================================================================
# 域名到期监控脚本 - 发送钉钉消息通知
# 原作者: 路飞博客
# 博客: https://blog.talimus.eu.org
# 优化版本: v0.5
# 更新日期: 2025/11/22
# 修复: 告警逻辑和调试输出
#================================================================

set -euo pipefail

# 全局变量
declare -a DOMAINS

#----------------------------------------------------------------
# 配置项
#----------------------------------------------------------------
WORK_DIR="/home/domain"
WARN_FILE="${WORK_DIR}/warnfile"
LOG_FILE="/tmp/testdomain.log"
PYTHON_SCRIPT="${WORK_DIR}/warnsrc.py"
DOMAIN_CONFIG="${WORK_DIR}/domains.txt"

# 告警阈值（天）
WARN_DAYS=30

# 重试配置
MAX_RETRIES=3
RETRY_DELAY=3
WHOIS_DELAY=5

# 调试模式（设置为1启用详细输出）
DEBUG=1

#----------------------------------------------------------------
# 函数定义
#----------------------------------------------------------------

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

log_debug() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" >&2
    fi
}

check_dependencies() {
    local deps=("whois" "bc" "python3")
    local missing=()
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "缺少依赖: ${missing[*]}, 尝试安装..."
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq
            for pkg in "${missing[@]}"; do
                sudo apt-get install -y "$pkg" || log_error "安装 $pkg 失败"
            done
        elif command -v yum &> /dev/null; then
            for pkg in "${missing[@]}"; do
                sudo yum install -y "$pkg" || log_error "安装 $pkg 失败"
            done
        else
            log_error "未检测到支持的包管理器(apt/yum)"
            return 1
        fi
    fi
    
    log_info "所有依赖检查完成"
}

init_files() {
    mkdir -p "$WORK_DIR" 2>/dev/null || true
    
    if [ ! -w "$WORK_DIR" ]; then
        log_error "工作目录 $WORK_DIR 不可写"
        exit 1
    fi
    
    if [ ! -f "$DOMAIN_CONFIG" ]; then
        log_error "域名配置文件不存在: $DOMAIN_CONFIG"
        log_info "请创建配置文件，每行一个域名"
        exit 1
    fi
    
    if [ ! -r "$DOMAIN_CONFIG" ]; then
        log_error "域名配置文件不可读: $DOMAIN_CONFIG"
        exit 1
    fi
    
    > "$WARN_FILE"
    > "$LOG_FILE"
    
    if [ ! -f "$PYTHON_SCRIPT" ]; then
        log_warn "Python脚本 $PYTHON_SCRIPT 不存在，告警将只输出到文件"
    fi
}

extract_expiry_date() {
    local domain="$1"
    local whois_output="$2"
    local expiry_date=""
    
    # 格式1: Expiry Date: 2025-12-31T23:59:59Z
    expiry_date=$(echo "$whois_output" | grep -iE 'Expiry Date|Registry Expiry Date' | head -1 | awk '{print $NF}' | cut -d 'T' -f 1)
    
    # 格式2: Expiration Time: 2025-12-31
    if [ -z "$expiry_date" ]; then
        expiry_date=$(echo "$whois_output" | grep -i 'Expiration Time' | head -1 | awk '{print $NF}')
    fi
    
    # 格式3: Expiration Date: 31-Dec-2025
    if [ -z "$expiry_date" ]; then
        expiry_date=$(echo "$whois_output" | grep -i 'Expiration Date' | head -1 | awk '{print $NF}')
        if [ -n "$expiry_date" ]; then
            expiry_date=$(date -d "$expiry_date" +%Y-%m-%d 2>/dev/null || echo "")
        fi
    fi
    
    # 格式4: paid-till: 2025-12-31
    if [ -z "$expiry_date" ]; then
        expiry_date=$(echo "$whois_output" | grep -i 'paid-till' | head -1 | awk '{print $NF}' | cut -d 'T' -f 1)
    fi
    
    echo "$expiry_date"
}

get_domain_expiry() {
    local domain="$1"
    local retry=0
    local expiry_date=""
    local whois_output=""
    
    while [ $retry -lt $MAX_RETRIES ]; do
        log_info "查询域名 $domain (尝试 $((retry+1))/$MAX_RETRIES)"
        
        whois_output=$(whois "$domain" 2>/dev/null || echo "")
        
        if [ -z "$whois_output" ]; then
            log_warn "域名 $domain whois查询返回空结果"
            retry=$((retry + 1))
            [ $retry -lt $MAX_RETRIES ] && sleep $RETRY_DELAY
            continue
        fi
        
        expiry_date=$(extract_expiry_date "$domain" "$whois_output")
        
        if [ -n "$expiry_date" ]; then
            log_info "域名 $domain 过期日期: $expiry_date"
            echo "$expiry_date"
            return 0
        fi
        
        retry=$((retry + 1))
        [ $retry -lt $MAX_RETRIES ] && sleep $RETRY_DELAY
    done
    
    log_error "无法获取域名 $domain 的过期日期"
    return 1
}

calculate_days_remaining() {
    local expiry_date="$1"
    local expiry_timestamp
    local today_timestamp
    local days_remaining
    
    expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || echo "")
    
    if [ -z "$expiry_timestamp" ]; then
        log_error "无法解析日期: $expiry_date"
        return 1
    fi
    
    today_timestamp=$(date +%s)
    days_remaining=$(( (expiry_timestamp - today_timestamp) / 86400 ))
    
    echo "$days_remaining"
}

generate_warning() {
    local domain="$1"
    local expiry_date="$2"
    local days_remaining="$3"
    
    cat >> "$WARN_FILE" << EOF
========================================
域名到期提醒
========================================
域名: ${domain}
到期日期: ${expiry_date}
剩余天数: ${days_remaining} 天
状态: $([ $days_remaining -le 7 ] && echo "紧急" || echo "警告")
告警阈值: ${WARN_DAYS} 天
========================================

EOF
}

log_domain_info() {
    local domain="$1"
    local expiry_date="$2"
    local days_remaining="$3"
    
    cat >> "$LOG_FILE" << EOF
域名: ${domain}
到期日期: ${expiry_date}
剩余天数: ${days_remaining} 天
告警阈值: ${WARN_DAYS} 天
是否告警: $([ $days_remaining -lt $WARN_DAYS ] && echo "是" || echo "否")
查询时间: $(date '+%Y-%m-%d %H:%M:%S')
----------------------------------------

EOF
}

read_domains() {
    local -a domains=()
    
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | xargs)
        
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        domains+=("$line")
    done < "$DOMAIN_CONFIG"
    
    if [ ${#domains[@]} -eq 0 ]; then
        log_error "配置文件中没有找到有效的域名"
        exit 1
    fi
    
    log_info "从配置文件读取到 ${#domains[@]} 个域名"
    
    DOMAINS=("${domains[@]}")
}

process_domain() {
    local domain="$1"
    local expiry_date
    local days_remaining
    
    if ! expiry_date=$(get_domain_expiry "$domain"); then
        cat >> "$WARN_FILE" << EOF
========================================
域名查询失败
========================================
域名: ${domain}
错误: 无法获取过期日期
建议: 请检查域名是否正确或网络连接
========================================

EOF
        return 1
    fi
    
    if ! days_remaining=$(calculate_days_remaining "$expiry_date"); then
        log_error "域名 $domain 日期计算失败"
        return 1
    fi
    
    log_info "域名 $domain 剩余 $days_remaining 天"
    
    # 添加调试输出
    log_debug "比较: $days_remaining < $WARN_DAYS"
    
    log_domain_info "$domain" "$expiry_date" "$days_remaining"
    
    # 关键修复：使用 -lt 进行数值比较
    if [ "$days_remaining" -lt "$WARN_DAYS" ]; then
        log_warn "域名 $domain 即将过期 ($days_remaining 天 < $WARN_DAYS 天阈值)"
        generate_warning "$domain" "$expiry_date" "$days_remaining"
        return 0
    else
        log_info "域名 $domain 未达到告警阈值 ($days_remaining 天 >= $WARN_DAYS 天)"
    fi
    
    return 0
}

send_alert() {
    if [ ! -s "$WARN_FILE" ]; then
        log_info "没有需要告警的域名"
        return 0
    fi
    
    log_info "发现需要告警的域名，告警文件大小: $(wc -c < "$WARN_FILE") 字节"
    
    if [ ! -f "$PYTHON_SCRIPT" ]; then
        log_warn "Python告警脚本不存在，仅输出告警内容："
        echo "========== 告警内容 =========="
        cat "$WARN_FILE"
        echo "=============================="
        return 0
    fi
    
    log_info "发送告警通知..."
    if python3 "$PYTHON_SCRIPT" "$WARN_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "告警发送成功"
    else
        log_error "告警发送失败，错误码: $?"
        log_error "告警内容："
        cat "$WARN_FILE"
        return 1
    fi
}

#----------------------------------------------------------------
# 主程序
#----------------------------------------------------------------
main() {
    log_info "============ 域名监控脚本启动 ============"
    log_info "告警阈值设置: $WARN_DAYS 天"
    
    check_dependencies
    init_files
    read_domains
    
    local total=${#DOMAINS[@]}
    local success=0
    local failed=0
    
    for domain in "${DOMAINS[@]}"; do
        if process_domain "$domain"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
        
        sleep "$WHOIS_DELAY"
    done
    
    log_info "处理完成: 总数=$total, 成功=$success, 失败=$failed"
    
    # 显示告警文件状态
    if [ -s "$WARN_FILE" ]; then
        log_info "告警文件包含 $(grep -c "域名到期提醒" "$WARN_FILE" || echo 0) 条告警"
    fi
    
    send_alert
    
    log_info "============ 域名监控脚本结束 ============"
    
    [ $failed -eq 0 ] && return 0 || return 1
}

main "$@"
