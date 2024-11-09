#!/bin/bash

# 基础配置
MONITOR_DIR="检测目录"
LOG_FILE="/var/log/php_block.log"
# 安全存储目录，按日期归类
QUARANTINE_DIR="/root/php_quarantine/$(date +%Y-%m-%d)"
# 钉钉配置
DINGDING_TOKEN="钉钉token"
DINGDING_URL="https://oapi.dingtalk.com/robot/send?access_token=$DINGDING_TOKEN"

# 确保隔离目录存在
mkdir -p "$QUARANTINE_DIR"
chmod 700 "$QUARANTINE_DIR"

# 发送钉钉通知函数
send_dingding_msg() {
    local message="$1"
    local server_name=$(hostname)
    local server_ip=$(curl -s ifconfig.me)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 构建钉钉消息
    local msg_content="### ⚠️ 服务器安全警告！\n\n"
    msg_content+="**服务器信息：**\n"
    msg_content+="- 主机名：${server_name}\n"
    msg_content+="- IP地址：${server_ip}\n"
    msg_content+="- 告警时间：${timestamp}\n\n"
    msg_content+="**详细信息：**\n${message}\n\n"
    msg_content+="请及时检查服务器安全状况！"
    
    # 发送请求到钉钉
    curl -s -H "Content-Type: application/json" \
         -X POST \
         -d "{
             \"msgtype\": \"markdown\",
             \"markdown\": {
                 \"title\": \"服务器安全警告\",
                 \"text\": \"$msg_content\"
             }
         }" \
         "$DINGDING_URL"
}

echo "开始监控目录: $MONITOR_DIR"
echo "日志文件位置: $LOG_FILE"
echo "可疑文件隔离目录: $QUARANTINE_DIR"

# 确保监控目录存在
if [ ! -d "$MONITOR_DIR" ]; then
    error_msg="监控目录 $MONITOR_DIR 不存在！"
    echo "错误: $error_msg"
    send_dingding_msg "$error_msg"
    exit 1
fi

# 记录脚本启动信息
startup_msg="PHP文件监控服务已启动\n- 监控目录: $MONITOR_DIR\n- 隔离目录: $QUARANTINE_DIR"
send_dingding_msg "$startup_msg"

# 定义通知控制变量
last_notification_time=0
NOTIFICATION_INTERVAL=300  # 5分钟通知间隔

# 主循环
while true; do
    current_time=$(date +%s)
    
    # 查找所有php文件
    find "$MONITOR_DIR" -type f -name "*.php" -mmin -1 | while read file; do
        # 生成隔离文件名（包含时间戳和原始路径信息）
        filename=$(basename "$file")
        quarantine_filename="$(date +%H-%M-%S)_${filename}"
        quarantine_path="$QUARANTINE_DIR/$quarantine_filename"
        
        # 获取文件信息
        OWNER=$(stat -c '%U' "$file")
        FILE_SIZE=$(stat -c '%s' "$file")
        FILE_PERM=$(stat -c '%a' "$file")
        
        # 移动文件到隔离目录
        mv "$file" "$quarantine_path"
        chmod 400 "$quarantine_path"  # 设置为只读
        
        # 记录日志
        log_message="检测到PHP文件并已隔离\n文件: $file\n隔离位置: $quarantine_path"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $log_message" >> "$LOG_FILE"
        
        # 检查是否需要发送通知
        if [ $((current_time - last_notification_time)) -ge $NOTIFICATION_INTERVAL ]; then
            # 构建通知消息
            detailed_msg="检测到可疑PHP文件！\n"
            detailed_msg+="**原始信息：**\n"
            detailed_msg+="- 原始路径：\`$file\`\n"
            detailed_msg+="- 文件所有者：\`$OWNER\`\n"
            detailed_msg+="- 文件大小：\`$FILE_SIZE bytes\`\n"
            detailed_msg+="- 文件权限：\`$FILE_PERM\`\n\n"
            detailed_msg+="**安全处理：**\n"
            detailed_msg+="- 隔离位置：\`$quarantine_path\`\n"
            detailed_msg+="- 文件已设置为只读权限"
            
            # 发送钉钉通知
            send_dingding_msg "$detailed_msg"
            
            # 更新最后通知时间
            last_notification_time=$current_time
        fi
    done
    
    # 休眠5秒
    sleep 5
done