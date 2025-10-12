#!/bin/bash
# 一键修改 HAProxy 后端 IP 并重启服务
# 适用于 Debian 系统

CONFIG="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/etc/haproxy"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== HAProxy 后端 IP 修改脚本 ==="
echo "1) 修改 server1"
echo "2) 修改 server1-backup"
read -p "请选择要修改的后端 [1/2]: " CHOICE

if [[ "$CHOICE" == "1" ]]; then
    TARGET="server1"
elif [[ "$CHOICE" == "2" ]]; then
    TARGET="server1-backup"
else
    echo "❌ 无效选择，退出。"
    exit 1
fi

read -p "请输入新的 IP 地址: " NEW_IP
if [[ ! "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ IP 地址格式无效，退出。"
    exit 1
fi

# 备份原文件
cp "$CONFIG" "$BACKUP_DIR/haproxy.cfg.bak.$TIMESTAMP"
echo "✅ 已备份到: $BACKUP_DIR/haproxy.cfg.bak.$TIMESTAMP"

# 替换 IP
sed -i -E "s/(server[[:space:]]+$TARGET[[:space:]]+)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)/\1$NEW_IP\2/" "$CONFIG"

echo "🔍 校验新配置中..."
if haproxy -c -f "$CONFIG" >/dev/null 2>&1; then
    echo "✅ 配置校验通过，正在重启 HAProxy..."
    systemctl restart haproxy
    systemctl is-active --quiet haproxy && echo "🚀 HAProxy 已成功重启。" || echo "⚠️ 重启失败，请检查。"
else
    echo "❌ 配置校验失败，正在恢复原配置..."
    mv "$BACKUP_DIR/haproxy.cfg.bak.$TIMESTAMP" "$CONFIG"
    echo "已恢复原配置。"
    exit 1
fi
