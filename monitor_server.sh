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

# 配置状态文件路径，用于记录服务器之前的状态
STATUS_FILE="/home/domain/serverstatus"

# 清空日志文件
> "$LOG_FILE"

# 如果状态文件不存在，创建它
if [[ ! -f "$STATUS_FILE" ]]; then
    touch "$STATUS_FILE"
fi

# 发送钉钉消息的函数
send_dingtalk_message() {
    local message="$1"
    curl "$DINGTALK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$message\"}}"
}

# 记录消息到日志文件的函数
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# 检查服务器状态并发送相应消息的函数
check_and_notify() {
    local server="$1"
    local port="$2"
    local label="$3"
    local status="$4"
    local previous_status

    # 读取服务器之前的状态
    previous_status=$(grep "^$server|" "$STATUS_FILE" | cut -d'|' -f2)

    if [[ "$status" != "OK" ]]; then
        # 服务器异常
        if [[ "$previous_status" != "$status" ]]; then
            # 状态发生变化，发送告警
            message="服务器 $label ($server) $status"
            send_dingtalk_message "$message"
            log_message "$message"
        fi
    elif [[ "$previous_status" != "OK" && -n "$previous_status" ]]; then
        # 服务器恢复正常，且之前状态不正常
        message="服务器 $label ($server) 已恢复正常运行"
        send_dingtalk_message "$message"
        log_message "$message"
    fi

    # 更新状态文件
    sed -i "/^$server|/d" "$STATUS_FILE"
    echo "$server|$status" >> "$STATUS_FILE"
}

# 遍历每个目标服务器进行监控
for TARGET_SERVER in "${!TARGET_SERVERS[@]}"; do
    IFS='|' read -r TARGET_PORT SERVER_LABEL <<< "${TARGET_SERVERS[$TARGET_SERVER]}"
    TARGET_URL="http://$TARGET_SERVER:$TARGET_PORT/"

    # 使用ping命令检查目标服务器是否可达
    if ! ping -c 1 "$TARGET_SERVER" &> /dev/null; then
        check_and_notify "$TARGET_SERVER" "$TARGET_PORT" "$SERVER_LABEL" "运行异常，无法ping通"
    else
        # 使用nc命令检查目标端口是否开放
        if ! nc -z -w 2 "$TARGET_SERVER" "$TARGET_PORT" &> /dev/null; then
            check_and_notify "$TARGET_SERVER" "$TARGET_PORT" "$SERVER_LABEL" "端口 $TARGET_PORT 未开放"
        else
            # 使用curl命令检查HTTP服务是否正常响应
            http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_URL")
            if [[ "$http_code" != "200" && "$http_code" != "302" && "$http_code" != "404" ]]; then
                check_and_notify "$TARGET_SERVER" "$TARGET_PORT" "$SERVER_LABEL" "HTTP服务未正常响应，HTTP状态码: $http_code"
            else
                check_and_notify "$TARGET_SERVER" "$TARGET_PORT" "$SERVER_LABEL" "OK"
            fi
        fi
    fi
done

# 脚本执行完毕后自动退出
exit 0