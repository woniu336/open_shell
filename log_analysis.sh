#!/bin/bash

LOG_DIR="/data/wwwlogs"  # 更新为新的日志目录

# 人类可读的流量格式化函数
format_size() {
    local size=$(printf "%.0f" "$1")
    if (( size < 1024 )); then
        echo "${size} B"
    elif (( size < 1048576 )); then
        echo "$(( size / 1024 )) KB"
    elif (( size < 1073741824 )); then
        echo "$(( size / 1048576 )) MB"
    else
        echo "$(( size / 1073741824 )) GB"
    fi
}

# 列出所有网站并统计汇总数据
list_sites() {
    local total_requests=0
    local total_traffic=0
    declare -A site_requests
    declare -A site_traffic

    echo "📌 站点列表:"
    for log_path in "$LOG_DIR"/*.access.log; do
        [[ -f "$log_path" ]] || continue  # 确保是文件
        site_name=$(basename "$log_path" .access.log)  # 获取站点名称

        echo "检查站点: $site_name, 日志路径: $log_path"  # 调试输出

        # 统计该站点请求数 & 总流量
        requests=$(wc -l < "$log_path")
        traffic=$(awk '{size=$10} size ~ /^[0-9]+$/ {sum += size} END {printf "%.0f", sum}' "$log_path")
        traffic=${traffic:-0}

        site_requests["$site_name"]=$requests
        site_traffic["$site_name"]=$traffic
        total_requests=$((total_requests + requests))
        total_traffic=$((total_traffic + traffic))

        echo "  ✅ $site_name - 请求数: $requests, 流量: $(format_size "$traffic")"
    done

    # 汇总数据
    echo -e "\n📊 **站点总览**"
    echo "  🌐 站点总数: ${#site_requests[@]}"
    echo "  📥 总请求数: $total_requests"
    echo "  📊 总流量: $(format_size "$total_traffic")"

    # 按请求数 & 流量 排序站点
    echo -e "\n📈 **Top 5 站点 (按请求数)**"
    for site in "${!site_requests[@]}"; do
        echo "${site_requests[$site]} $site"
    done | sort -nr | head -n 5 | awk '{printf "  %-15s 请求数: %s\n", $2, $1}'

    echo -e "\n💾 **Top 5 站点 (按流量)**"
    for site in "${!site_traffic[@]}"; do
        echo "${site_traffic[$site]} $site"
    done | sort -nr | head -n 5 | while read -r size site; do
        echo "  $site 流量: $(format_size "$size")"
    done
}

# 筛选 IP 日志
extract_ip_logs() {
    local ip="$1"
    local output_file="$2"
    local found=0

    echo "📂 正在搜索与 IP $ip 相关的日志..."
    > "$output_file"  # 清空输出文件

    for site in "$LOG_DIR"/*; do
        [[ -d "$site" ]] || continue
        log_path="$site.access.log"  # 更新日志路径格式

        if [[ -f "$log_path" ]]; then
            # 检测日志文件类型
            if file "$log_path" | grep -q "gzip compressed data"; then
                zgrep -a -F "$ip" "$log_path" >> "$output_file"
            else
                grep -a -F "$ip" "$log_path" >> "$output_file"
            fi
            found=1
        fi
    done

    if [[ $found -eq 1 ]]; then
        echo "✅ 日志已保存到: $output_file"
    else
        echo "❌ 没有找到与 $ip 相关的日志！"
    fi
}

# 解析命令行参数
if [[ $# -eq 2 && "$1" == "-n" ]]; then
    SITE="$2"
    LOG_PATH="$LOG_DIR/$SITE.access.log"  # 更新日志路径格式

    if [[ ! -f "$LOG_PATH" ]]; then
        echo "错误: 访问日志 $LOG_PATH 不存在！"
        exit 1
    fi

    echo "日志文件: $LOG_PATH"

    # 统计请求最多的 10 个 IP
    echo -e "\n📊 请求数最多的 IP:"
    awk '{print $1}' "$LOG_PATH" | sort | uniq -c | sort -nr | head -n 10 | awk '{printf "  %-15s 请求数: %s\n", $2, $1}'

    # 统计流量最多的 10 个 IP
    echo -e "\n📊 消耗带宽最多的 IP:"
    awk '{ip=$1; size=$10} size ~ /^[0-9]+$/ {traffic[ip] += size} END {for (ip in traffic) printf "%.0f %s\n", traffic[ip], ip}' "$LOG_PATH" \
        | sort -nr | head -n 10 | while read -r size ip; do
        echo "  $ip 流量: $(format_size "$size")"
    done

elif [[ $# -eq 1 && "$1" == "-v" ]]; then
    list_sites

elif [[ $# -eq 3 && "$1" == "-i" ]]; then
    extract_ip_logs "$2" "$3"

else
    echo "用法:"
    echo "  $0 -n <site>         # 查看指定站点的流量信息"
    echo "  $0 -v                # 列出所有站点并显示汇总数据"
    echo "  $0 -i <IP> <文件>    # 筛选出指定 IP 的日志并保存"
    exit 1
fi 