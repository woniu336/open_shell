#!/bin/bash
# monitor_without_logs.sh

echo "=== HAProxy限流监控 (无日志版本) $(date) ==="

FORWARDING_IP="8.8.8.8"

# 当前连接分析
echo "当前连接统计 (排除转发IP):"
CONNECTIONS=$(netstat -tn | grep -v $FORWARDING_IP | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr)

# 检查高连接数IP
HIGH_CONN=$(echo "$CONNECTIONS" | awk '
$1 >= 80 { print "🚨 ALERT: " $2 " - " $1 " connections (接近100限制)" }
$1 >= 60 { print "⚠️  WARNING: " $2 " - " $1 " connections (需要关注)" }
$1 >= 40 { print "ℹ️  INFO: " $2 " - " $1 " connections (正常范围上限)" }
')

if [ -n "$HIGH_CONN" ]; then
    echo "$HIGH_CONN"
else
    echo "✅ 所有IP连接数都在安全范围内"
fi

# 显示前10名连接数
echo -e "\n📊 连接数排行榜 (前10名):"
echo "$CONNECTIONS" | head -10 | awk '{printf "%2d. %15s - %3d connections\n", NR, $2, $1}'

# HAProxy进程和配置状态
echo -e "\n🔧 HAProxy状态:"
if pgrep haproxy > /dev/null; then
    HAPROXY_PID=$(pgrep haproxy | head -1)
    echo "✅ HAProxy运行中 (PID: $HAPROXY_PID)"
    
    # 检查HAProxy进程的连接数
    HAPROXY_CONNS=$(lsof -p $HAPROXY_PID 2>/dev/null | grep ESTABLISHED | wc -l)
    echo "HAProxy进程连接数: $HAPROXY_CONNS"
else
    echo "❌ HAProxy未运行"
fi

# Stick-table检查
if command -v socat >/dev/null 2>&1 && [ -S /var/run/haproxy.sock ]; then
    echo -e "\n📈 Stick-table统计:"
    TABLE_INFO=$(echo "show table tcp_front_443" | socat stdio /var/run/haproxy.sock 2>/dev/null)
    if [ -n "$TABLE_INFO" ]; then
        TABLE_SIZE=$(echo "$TABLE_INFO" | head -1)
        ENTRY_COUNT=$(echo "$TABLE_INFO" | grep -v "^#" | wc -l)
        echo "Stick-table: $ENTRY_COUNT 条记录"
        echo "$TABLE_SIZE"
        
        # 显示stick-table中的高连接数IP
        echo -e "\nStick-table中连接数>=30的IP:"
        echo "$TABLE_INFO" | grep -v $FORWARDING_IP | awk 'NF>=3 && $3>=30 {printf "  %15s - %3d connections\n", $1, $3}' | head -5
    else
        echo "无法获取stick-table信息"
    fi
else
    echo -e "\n❌ socat不可用或HAProxy socket未配置"
fi

# 总体统计
TOTAL_ESTABLISHED=$(netstat -tn | grep ESTABLISHED | wc -l)
UNIQUE_IPS_ALL=$(netstat -tn | awk '{print $5}' | cut -d: -f1 | sort | uniq | wc -l)
UNIQUE_IPS_EXCL=$(netstat -tn | grep -v $FORWARDING_IP | awk '{print $5}' | cut -d: -f1 | sort | uniq | wc -l)

echo -e "\n📊 总体统计:"
echo "总ESTABLISHED连接: $TOTAL_ESTABLISHED"
echo "所有唯一IP数量: $UNIQUE_IPS_ALL"
echo "非转发IP数量: $UNIQUE_IPS_EXCL"
echo "转发IP连接数: $(netstat -tn | grep $FORWARDING_IP | wc -l)"

# 系统负载
echo -e "\n💻 系统状态:"
echo "负载: $(uptime | awk -F'load average:' '{print $2}')"
echo "内存使用: $(free -h | grep Mem | awk '{print $3"/"$2}')"

echo -e "\n================================"
