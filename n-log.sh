#!/bin/bash
# nginx_log_analyzer.sh

LOG_FILE="/home/web/log/nginx/access.log"

echo "=== Nginx访问日志分析 ==="
echo "1. 总请求数: $(wc -l < $LOG_FILE)"
echo "2. 状态码统计:"
awk '{print $9}' $LOG_FILE | sort | uniq -c | sort -rn
echo "3. 最频繁访问IP:"
awk '{print $1}' $LOG_FILE | sort | uniq -c | sort -rn | head -10
echo "4. 最热门URL:"
awk '{print $7}' $LOG_FILE | sort | uniq -c | sort -rn | head -10
echo "5. 流量统计:"
awk '{sum+=$10} END {
    print "总流量: " sum/1024/1024 " MB";
    print "平均响应大小: " sum/NR/1024 " KB"
}' $LOG_FILE
