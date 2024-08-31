#!/bin/bash

# 配置目标服务器的IP地址、端口和标签，使用关联数组
declare -A TARGET_SERVERS=(
    #["8.8.8.8"]="8080|标签"
    ["192.168.1.8"]="3000|web02"
)

# 配置钉钉机器人的Webhook URL
DINGTALK_WEBHOOK=""

# 配置日志文件路径
LOG_FILE="/home/domain/serverlog"

# 清空日志文件
> "$LOG_FILE"

# 发送钉钉告警消息的函数
send_dingtalk_alert() {
    local message="$1"
    curl "$DINGTALK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$message\"}}"
}

# 记录告警消息到日志文件的函数
log_alert() {
    local message="$1"
    echo "$message" >> "$LOG_FILE"
}

# 遍历每个目标服务器进行监控
for TARGET_SERVER in "${!TARGET_SERVERS[@]}"; do
    IFS='|' read -r TARGET_PORT SERVER_LABEL <<< "${TARGET_SERVERS[$TARGET_SERVER]}"
    TARGET_URL="http://$TARGET_SERVER:$TARGET_PORT/"

    # 使用ping命令检查目标服务器是否可达
    if ! ping -c 1 "$TARGET_SERVER" &> /dev/null; then
        # 如果ping失败，发送钉钉告警并记录日志
        alert_message="服务器 $SERVER_LABEL ($TARGET_SERVER) 运行异常，无法ping通！"
        send_dingtalk_alert "$alert_message"
        log_alert "$alert_message"
    else
        # 使用nc命令检查目标端口是否开放
        if ! nc -z -w 2 "$TARGET_SERVER" "$TARGET_PORT" &> /dev/null; then
            # 如果端口检查失败，发送钉钉告警并记录日志
            alert_message="服务器 $SERVER_LABEL ($TARGET_SERVER) 端口 $TARGET_PORT 未开放！"
            send_dingtalk_alert "$alert_message"
            log_alert "$alert_message"
        else
            # 使用curl命令检查HTTP服务是否正常响应
            http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_URL")
            if [[ "$http_code" != "200" && "$http_code" != "302" && "$http_code" != "404" ]]; then
                # 如果HTTP服务检查失败，发送钉钉告警并记录日志
                alert_message="服务器 $SERVER_LABEL ($TARGET_SERVER) 的HTTP服务未正常响应，HTTP状态码: $http_code！"
                send_dingtalk_alert "$alert_message"
                log_alert "$alert_message"
            fi
        fi
    fi
done

# 脚本执行完毕后自动退出
exit 0