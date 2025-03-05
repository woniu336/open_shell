#!/bin/bash

# 配置参数
CONN_THRESHOLD=200    # 降低阈值到200
TIME_WINDOW=60       # 监控时间窗口(秒)
LOG_FILE="/var/log/ip_monitor.log"
WHITELIST=("127.0.0.1" "192.168.1." "172.19.0.") # 白名单IP/IP段
LOCK_FILE="/var/run/ip_monitor.lock"  # 添加锁文件

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用root权限运行此脚本"
    exit 1
fi

# 检查脚本是否已经在运行
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE")
    if ps -p "$pid" > /dev/null 2>&1; then
        echo "脚本已经在运行中 (PID: $pid)"
        exit 1
    else
        # 如果进程不存在，删除过期的锁文件
        rm -f "$LOCK_FILE"
    fi
fi

# 创建锁文件
echo $$ > "$LOCK_FILE"

# 清理函数
cleanup() {
    echo "正在停止监控..."
    rm -f "$LOCK_FILE"
    exit 0
}

# 注册清理函数
trap cleanup SIGINT SIGTERM

# 记录日志函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

# 检查IP是否在白名单中
is_whitelisted() {
    local ip=$1
    for white_ip in "${WHITELIST[@]}"; do
        if [[ $ip == $white_ip* ]]; then
            return 0
        fi
    done
    return 1
}

# 检查IP是否已被封禁
is_blocked() {
    local ip=$1
    ufw status | grep -q "$ip"
    return $?
}

# 封禁IP
block_ip() {
    local ip=$1
    if ! is_blocked "$ip"; then
        ufw insert 1 deny from "$ip" to any
        log_message "已封禁IP: $ip (优先级: 1)"
    fi
}

# 添加启动提示
echo "开始监控网络连接..."
echo "日志文件位置: $LOG_FILE"
echo "连接数阈值: $CONN_THRESHOLD"
echo "检查间隔: $TIME_WINDOW 秒"
echo "----------------------------------------"

# 主循环
while true; do
    # 显示当前时间
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 正在检查连接..."
    
    # 获取当前所有TCP连接的IP地址及其连接数 (改进过滤条件)
    ip_counts=$(netstat -apn | grep 'tcp' | awk '{print $5}' | grep -v "::" | cut -d: -f1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort | uniq -c)
    
    # 显示当前连接统计
    echo "当前活动连接:"
    echo "$ip_counts"
    echo "----------------------------------------"
    
    echo "$ip_counts" | while read count ip; do
        # 检查是否超过阈值且不在白名单中
        if [ "$count" -gt "$CONN_THRESHOLD" ] && ! is_whitelisted "$ip"; then
            # 获取IP段 (取前三段)
            ip_range=$(echo "$ip" | cut -d. -f1-3).0/24
            
            log_message "检测到可疑IP: $ip (连接数: $count)"
            block_ip "$ip_range"
        fi
    done
    
    sleep "$TIME_WINDOW"
done 