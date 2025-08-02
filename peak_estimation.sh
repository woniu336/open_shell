#!/bin/bash
# peak_estimation.sh

echo "=== 高峰期需求估算 ==="

# 当前最高连接数
CURRENT_MAX=$(netstat -tn | grep -v 15.24.6.161 | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -1 | awk '{print $1}')
echo "当前最高连接数: $CURRENT_MAX"

# 估算高峰期可能的连接数
ESTIMATED_PEAK_2X=$((CURRENT_MAX * 2))
ESTIMATED_PEAK_3X=$((CURRENT_MAX * 3))
ESTIMATED_PEAK_5X=$((CURRENT_MAX * 5))

echo "高峰期估算:"
echo "  2倍流量: ${ESTIMATED_PEAK_2X}个连接"
echo "  3倍流量: ${ESTIMATED_PEAK_3X}个连接" 
echo "  5倍流量: ${ESTIMATED_PEAK_5X}个连接"

echo -e "\n建议的限制设置:"
echo "  保守设置: $((ESTIMATED_PEAK_2X + 50))个并发限制"
echo "  宽松设置: $((ESTIMATED_PEAK_3X + 50))个并发限制"
echo "  很宽松设置: $((ESTIMATED_PEAK_5X + 50))个并发限制"
