#!/bin/bash

# 定义日志文件路径
SSL_LOG="/home/domain/logssl"
DOMAIN_LOG="/home/domain/warnfile"
SERVER_LOG="/home/domain/serverlog"

# 定义钉钉机器人 webhook
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=ace02fed431c60c0cd60b7026ee27a114ccf23a561612a9749f6efd1c600e292"

# 函数：读取SSL日志并生成报告
generate_ssl_report() {
    local content=""
    
    if [ -s "$SSL_LOG" ]; then
        while IFS= read -r line; do
            domain=$(echo "$line" | awk -F'告警域名：' '{print $2}' | awk '{print $1}')
            days=$(echo "$line" | awk -F'剩余：' '{print $2}')
            content+="  $domain (剩余 $days)\n"
        done < "$SSL_LOG"
    else
        content="  无SSL证书告警信息\n"
    fi
    
    echo -e "SSL证书监控:\n$content"
}

# 函数：读取域名日志并生成报告
generate_domain_report() {
    local content=""
    
    if [ -s "$DOMAIN_LOG" ]; then
        content=$(awk '
            /^域名:/ {domain=$2}
            /^到期日期:/ {date=$2}
            /^剩余天数:/ {days=$2" "$3; printf "  %s (到期: %s, %s)\n", domain, date, days}
        ' "$DOMAIN_LOG")
    else
        content="  无域名到期告警信息\n"
    fi
    
    echo -e "域名到期监控:\n$content"
}


# 生成报告
report="每日监控报告 $(date +"%Y-%m-%d")\n"
report+="================\n\n"
report+=$(generate_ssl_report)
report+="\n----------------\n\n"
report+=$(generate_domain_report)

# 如果所有日志都为空，添加一条信息
if [ ! -s "$SSL_LOG" ] && [ ! -s "$DOMAIN_LOG" ] && [ ! -s "$SERVER_LOG" ]; then
    report+="\n================"
    report+="\n  所有监控项目正常"
    report+="\n================"
fi

# 发送钉钉消息
curl "$DINGTALK_WEBHOOK" \
   -H 'Content-Type: application/json' \
   -d '{
    "msgtype": "text",
    "text": {
        "content": "'"${report}"'"
    }
}'

# 添加定时任务到 crontab
# (crontab -l ; echo "0 14 * * * cd /home/domain && ./daily_report.sh >/dev/null 2>&1") | crontab -