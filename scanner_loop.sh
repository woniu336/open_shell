#!/bin/bash

SCAN_SCRIPT="/root/php-malware-scanner.sh"

# 检查脚本文件是否存在
if [ ! -f "$SCAN_SCRIPT" ]; then
    echo "错误：扫描脚本 $SCAN_SCRIPT 不存在"
    exit 1
fi

# 检查脚本是否有执行权限
if [ ! -x "$SCAN_SCRIPT" ]; then
    echo "为脚本添加执行权限"
    chmod +x "$SCAN_SCRIPT"
fi

echo "开始循环执行扫描脚本..."

while true; do
    # 执行扫描脚本
    "$SCAN_SCRIPT"
    
    # 等待5秒
    sleep 5
done