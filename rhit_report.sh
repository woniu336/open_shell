#!/bin/bash
# 用法: ./rhit_report.sh /path/to/access-rhit.log

LOG_FILE="$1"
if [ -z "$LOG_FILE" ]; then
    echo "❌ 请提供日志文件路径，例如: ./rhit_report.sh /path/to/access-rhit.log"
    exit 1
fi

REPORT="rhit_report_$(date +%F_%H%M).txt"

{
    echo "📊 rhit 报告"
    echo "日志文件: $LOG_FILE"
    echo "生成时间: $(date)"
    echo "----------------------------------------"

    echo -e "\n=== 状态码统计 ==="
    rhit -f status "$LOG_FILE" | awk 'NR<=20'

    echo -e "\n=== 最常见 IP ==="
    rhit -f i "$LOG_FILE" | awk 'NR<=20'

    echo -e "\n=== 访问最多的路径 ==="
    rhit -f p "$LOG_FILE" | awk 'NR<=20'

    echo -e "\n=== 来源统计 ==="
    rhit -f r "$LOG_FILE" | awk 'NR<=20'

    echo -e "\n=== 请求方法统计 ==="
    rhit -f m "$LOG_FILE" | awk 'NR<=20'

    echo -e "\n=== 每日请求数 ==="
    rhit -f d "$LOG_FILE" | awk 'NR<=20'

    echo -e "\n=== 每小时请求数 ==="
    rhit -f t "$LOG_FILE" | awk 'NR<=20'
	
    echo -e "\n=== 查看最消耗带宽的 IP ==="
    rhit -k bytes -f i "$LOG_FILE" | awk 'NR<=20'
	
    echo -e "\n=== 查看消耗流量最大的页面 ==="
    rhit -k bytes -f p "$LOG_FILE" | awk 'NR<=20'

} > "$REPORT"

echo "✅ 报告已生成: $REPORT"
