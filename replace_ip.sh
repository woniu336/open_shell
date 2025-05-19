#!/bin/bash

# 替换HAProxy配置文件中的IP地址
# 用法: ./replace_ip.sh <新IP地址>

# 检查参数
if [ $# -ne 1 ]; then
    echo "错误: 请提供一个新的IP地址"
    echo "用法: $0 <新IP地址>"
    exit 1
fi

NEW_IP="$1"

# 验证输入的IP地址格式
if ! [[ $NEW_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误: 请输入有效的IP地址格式 (x.x.x.x)"
    exit 1
fi

CONFIG_FILE="/etc/haproxy/haproxy.cfg"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: HAProxy配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 创建备份
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "已创建配置文件备份: $BACKUP_FILE"

# 提取当前正在使用的IP地址
CURRENT_IP=$(grep -oE 'server[[:space:]]+server1_[[:digit:]]+[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' "$CONFIG_FILE" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

if [ -z "$CURRENT_IP" ]; then
    echo "错误: 在配置文件中未找到IP地址"
    exit 1
fi

echo "当前IP地址: $CURRENT_IP"
echo "新IP地址: $NEW_IP"

# 使用sed替换IP地址
sed -i "s/$CURRENT_IP/$NEW_IP/g" "$CONFIG_FILE"

# 验证替换是否成功
if grep -q "$NEW_IP" "$CONFIG_FILE"; then
    echo "成功: IP地址已更新为 $NEW_IP"
    
    # 重启HAProxy服务
    echo "正在重启HAProxy服务..."
    if systemctl restart haproxy; then
        echo "HAProxy服务已成功重启"
    else
        echo "警告: HAProxy服务重启失败，请手动检查并重启"
        echo "可以使用命令: sudo systemctl restart haproxy"
    fi
else
    echo "错误: IP地址替换失败"
    echo "正在从备份恢复..."
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    exit 1
fi

exit 0