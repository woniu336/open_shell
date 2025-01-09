#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：必须以root权限运行此脚本"
    exit 1
fi

# 添加确认提示
echo "警告：此操作将完全删除AMH面板及所有相关数据！"
read -p "确定要继续吗？(y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "操作已取消"
    exit 1
fi

# 1. 停止服务
echo "正在停止服务..."
if pidof php-fpm >/dev/null; then
    killall php-fpm 2>/dev/null
fi

# 检查amh命令是否存在
if command -v amh >/dev/null 2>&1; then
    amh nginx stop 2>/dev/null
    amh mysql stop 2>/dev/null
fi

# 2. 删除文件和目录
echo "正在删除文件和目录..."
directories=(
    "/root/amh"
    "/home/usrdata"
    "/home/wwwroot"
    "/usr/local/amh*"
    "/usr/local/libiconv*"
    "/usr/local/nginx*"
    "/usr/local/mysql*"
    "/usr/local/php*"
)

for dir in "${directories[@]}"; do
    if ls $dir >/dev/null 2>&1; then
        rm -rf $dir
    fi
done

# 3. 删除启动脚本和配置文件
files=(
    "/etc/init.d/amh-start"
    "/etc/amh-iptables"
    "/bin/amh"
    "/root/amh.sh"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
    fi
done

echo "AMH面板及相关组件已完全删除" 