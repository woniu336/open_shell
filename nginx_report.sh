#!/bin/bash

# ============================================================================
# Nginx 日志分析报告脚本 - 简化版
# ============================================================================

# 默认配置
LOG="${1:-/opt/om/nginx/logs/access.log}"
CONF_DIR="/opt/om/nginx/conf"
DAYS="${2:-1}"  # 分析最近N天，默认1天
TEMP_DIR="/tmp/nginx_analysis_$"

# ============================================================================
# 错误处理和前置检查
# ============================================================================
set -euo pipefail

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

check_prerequisites() {
    if [[ ! -f "$LOG" ]]; then
        echo "错误: 日志文件不存在: $LOG" >&2
        exit 1
    fi
    
    if [[ ! -r "$LOG" ]]; then
        echo "错误: 无权限读取日志文件: $LOG" >&2
        exit 1
    fi
    
    mkdir -p "$TEMP_DIR"
}

# ============================================================================
# 时间范围过滤
# ============================================================================
filter_by_date() {
    if [[ "$DAYS" -eq 1 ]]; then
        cat "$LOG"
    else
        local cutoff_date=$(date -d "$DAYS days ago" +%d/%b/%Y)
        awk -v cutoff="$cutoff_date" '$4 >= "["cutoff' "$LOG"
    fi
}

# ============================================================================
# 输出格式化函数
# ============================================================================
print_header() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Nginx 日志分析报告 - $(date '+%Y-%m-%d %H:%M:%S')         ║"
    echo "║         分析范围: 最近 $DAYS 天                                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_section() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# 一次性数据提取 - 优化性能
# ============================================================================
extract_all_data() {
    echo "正在分析日志文件..." >&2
    
    filter_by_date | awk -v temp="$TEMP_DIR" '
    BEGIN {
        status_file = temp "/status.txt"
        bot_file = temp "/bots.txt"
        error_502_file = temp "/error_502.txt"
        error_5xx_file = temp "/error_5xx.txt"
        upstream_file = temp "/upstream.txt"
        ip_file = temp "/ip.txt"
        hour_403_file = temp "/hour_403.txt"
        hour_502_file = temp "/hour_502.txt"
    }
    {
        # 提取基本字段
        ip = $1
        timestamp = $4
        method = $6
        url = $7
        status = $9
        
        # 提取时间（小时）
        split(timestamp, time_parts, ":")
        hour = time_parts[2]
        
        # 提取 request_time
        req_time = 0
        if (match($0, /request_time=[0-9.]+/)) {
            req_time_str = substr($0, RSTART, RLENGTH)
            sub(/request_time=/, "", req_time_str)
            req_time = req_time_str
        }
        
        # 提取 upstream
        upstream = "-"
        if (match($0, /upstream: [^ ]+/)) {
            upstream_str = substr($0, RSTART, RLENGTH)
            sub(/upstream: /, "", upstream_str)
            upstream = upstream_str
        }
        
        # 状态码统计
        print status > status_file
        
        # IP 统计
        print ip > ip_file
        
        # 403 Bot 统计 - 直接在整行中查找
        if (status == 403) {
            if (match($0, /ClaudeBot|Claude-User|Claude-SearchBot|OAI-SearchBot|ChatGPT-User|GPTBot|Amazonbot|facebookexternalhit|facebookcatalog|meta-webindexer|meta-externalads|meta-externalagent|meta-externalfetcher/)) {
                bot_name = substr($0, RSTART, RLENGTH)
                print bot_name > bot_file
                print ip "\t" bot_name > temp "/bot_ip.txt"
            }
            print hour > hour_403_file
        }
        
        # 502 错误分析
        if (status == 502) {
            print upstream "\t" req_time "\t" url "\t" timestamp "\t" method > error_502_file
            print hour > hour_502_file
        }
        
        # 其他 5xx 错误（排除 502）
        if (status ~ /^5[0-9][0-9]$/ && status != 502) {
            print status > error_5xx_file
        }
        
        # Upstream 统计
        print upstream "\t" status > upstream_file
    }
    '
}

# ============================================================================
# 1. 基础统计
# ============================================================================
show_basic_stats() {
    print_section "📊 基础统计"
    
    local total=$(wc -l < "$TEMP_DIR/status.txt")
    echo "  总请求数: $total"
    echo ""
    
    echo "  状态码分布:"
    sort "$TEMP_DIR/status.txt" | uniq -c | sort -rn | head -10 | while read count code; do
        printf "    %-4s : %8s 次 (%.2f%%)\n" "$code" "$count" $(awk "BEGIN {printf \"%.2f\", ($count/$total)*100}")
    done
    echo ""
}

# ============================================================================
# 2. AI Bot 拦截统计
# ============================================================================
show_bot_stats() {
    print_section "🤖 AI Bot 拦截统计"
    
    if [[ -s "$TEMP_DIR/bots.txt" ]]; then
        sort "$TEMP_DIR/bots.txt" | uniq -c | sort -rn | while read count bot; do
            printf "  %-30s : %8s 次\n" "$bot" "$count"
        done
        echo ""
        
        echo "  Bot 访问来源 IP (Top 10):"
        if [[ -s "$TEMP_DIR/bot_ip.txt" ]]; then
            cut -f1 "$TEMP_DIR/bot_ip.txt" | sort | uniq -c | sort -rn | head -10 | while read count ip; do
                printf "    %-18s : %6s 次\n" "$ip" "$count"
            done
        fi
    else
        echo "  ✓ 未发现AI Bot访问"
    fi
    echo ""
    
    if [[ -s "$TEMP_DIR/hour_403.txt" ]]; then
        echo "  403拦截时段分布:"
        sort "$TEMP_DIR/hour_403.txt" | uniq -c | sort -k2 -n | while read count hour; do
            # 移除前导零避免八进制问题
            hour_num=$((10#$hour))
            printf "    %02d:00 : %6s 次\n" "$hour_num" "$count"
        done
        echo ""
    fi
}

# ============================================================================
# 3. 502 错误分析
# ============================================================================
show_502_errors() {
    print_section "⚠️  502 错误分析"
    
    local error_502_count=0
    [[ -f "$TEMP_DIR/error_502.txt" ]] && error_502_count=$(wc -l < "$TEMP_DIR/error_502.txt")
    
    echo "  502错误总数: $error_502_count"
    echo ""
    
    if [[ "$error_502_count" -gt 0 ]]; then
        echo "  后端节点分布:"
        cut -f1 "$TEMP_DIR/error_502.txt" | sort | uniq -c | sort -rn | while read count backend; do
            printf "    %-25s : %6s 次\n" "$backend" "$count"
        done
        echo ""
        
        echo "  502时段分布:"
        sort "$TEMP_DIR/hour_502.txt" | uniq -c | sort -k2 -n | while read count hour; do
            hour_num=$((10#$hour))
            printf "    %02d:00 : %4s 次\n" "$hour_num" "$count"
        done
        echo ""
        
        echo "  高频502 URL (Top 10):"
        cut -f3 "$TEMP_DIR/error_502.txt" | sort | uniq -c | sort -rn | head -10 | while read count url; do
            printf "    %4s 次 : %s\n" "$count" "$url"
        done
        echo ""
        
        echo "  最近5条502错误:"
        tail -5 "$TEMP_DIR/error_502.txt" | while IFS=$'\t' read upstream req_time url timestamp method; do
            printf "    [%s] %s %s -> %s (%.3fs)\n" "$timestamp" "$method" "$url" "$upstream" "$req_time"
        done
    else
        echo "  ✓ 无502错误"
    fi
    echo ""
}

# ============================================================================
# 4. 其他5xx错误
# ============================================================================
show_other_5xx_errors() {
    print_section "🔴 其他 5xx 错误"
    
    if [[ -s "$TEMP_DIR/error_5xx.txt" ]]; then
        sort "$TEMP_DIR/error_5xx.txt" | uniq -c | sort -rn | while read count code; do
            printf "  %s : %s 次\n" "$code" "$count"
        done
    else
        echo "  ✓ 无其他5xx错误"
    fi
    echo ""
}



# ============================================================================
# 6. Top IP 访问统计
# ============================================================================
show_top_ips() {
    print_section "🌐 Top 10 访问IP"
    
    sort "$TEMP_DIR/ip.txt" | uniq -c | sort -rn | head -10 | while read count ip; do
        printf "  %-18s : %8s 次\n" "$ip" "$count"
    done
    echo ""
}

# ============================================================================
# 主函数
# ============================================================================
main() {
    check_prerequisites
    
    print_header
    
    # 提取所有数据（一次性扫描）
    extract_all_data
    
    # 生成各部分报告
    show_basic_stats
    show_bot_stats
    show_502_errors
    show_other_5xx_errors
    show_top_ips
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "报告生成完成 - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 显示使用帮助
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    cat << EOF
用法: $0 [日志文件路径] [天数]

参数:
  日志文件路径    Nginx 访问日志路径 (默认: /opt/om/nginx/logs/access.log)
  天数           分析最近N天的日志 (默认: 1)

示例:
  $0                                          # 使用默认配置
  $0 /var/log/nginx/access.log               # 指定日志文件
  $0 /var/log/nginx/access.log 7             # 分析最近7天
  $0 /var/log/nginx/access.log 1 > report.txt  # 保存报告
EOF
    exit 0
fi

main "$@"
