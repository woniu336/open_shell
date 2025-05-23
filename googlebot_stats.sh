#!/bin/bash

echo "=== Googlebot 阻止统计 ==="
echo "生成时间: $(date)"
echo

# 1. 查看iptables规则统计
echo "1. IPv4 规则匹配统计:"
iptables -L INPUT -v -n | grep -E "(66\.249\.|64\.233\.|72\.14\.|74\.125\.|209\.85\.|216\.239\.)" | while read line; do
    packets=$(echo $line | awk '{print $1}')
    bytes=$(echo $line | awk '{print $2}')
    source=$(echo $line | awk '{print $4}')
    echo "  来源: $source - 匹配包数: $packets, 字节数: $bytes"
done

echo
echo "2. IPv6 规则匹配统计:"
ip6tables -L INPUT -v -n 2>/dev/null | grep "2001:4860" | while read line; do
    packets=$(echo $line | awk '{print $1}')
    bytes=$(echo $line | awk '{print $2}')
    source=$(echo $line | awk '{print $4}')
    echo "  来源: $source - 匹配包数: $packets, 字节数: $bytes"
done

echo
echo "3. 总计统计:"
total_ipv4=$(iptables -L INPUT -v -n | grep -E "(66\.249\.|64\.233\.|72\.14\.|74\.125\.|209\.85\.|216\.239\.)" | awk '{sum+=$1} END {print sum+0}')
total_ipv6=$(ip6tables -L INPUT -v -n 2>/dev/null | grep "2001:4860" | awk '{sum+=$1} END {print sum+0}')
echo "  IPv4被阻止包总数: $total_ipv4"
echo "  IPv6被阻止包总数: $total_ipv6"
echo "  总被阻止包数: $((total_ipv4 + total_ipv6))"

echo
echo "4. 最近的日志记录 (如果启用了日志):"
if [ -f /var/log/kern.log ]; then
    echo "最近10条Googlebot阻止记录:"
    grep "BLOCKED_GOOGLEBOT" /var/log/kern.log | tail -10
else
    echo "未找到kern.log文件或未启用日志记录"
fi

echo
echo "5. 当前活跃的Googlebot规则数量:"
ipv4_rules_count=$(iptables -L INPUT -n | grep -c -E "(66\.249\.|64\.233\.|72\.14\.|74\.125\.|209\.85\.|216\.239\.)")
ipv6_rules_count=$(ip6tables -L INPUT -n 2>/dev/null | grep -c "2001:4860")
echo "  IPv4规则数: $ipv4_rules_count"
echo "  IPv6规则数: $ipv6_rules_count"

echo
echo "=== 统计完成 ==="