#!/bin/bash

# 定义本地和远程目录
LOCAL_DIR="/home/backup/"
REMOTE_DIR="r2:web/amh-backup"

echo "开始查找最新的备份文件..."

# 获取最新的备份文件名
LATEST_BACKUP=$(rclone lsf "$REMOTE_DIR" --files-only | grep '\.tar\.gz\.amh$' | sort -r | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "错误：未找到任何备份文件"
    exit 1
fi

echo "找到最新备份文件: $LATEST_BACKUP"
echo "开始恢复备份文件..."

# 执行恢复操作
rclone copy "$REMOTE_DIR/$LATEST_BACKUP" "$LOCAL_DIR" \
    --ignore-existing -u -v -P \
    --transfers=6 \
    --ignore-errors \
    --buffer-size=64M \
    --check-first \
    --checkers=10 \
    --drive-acknowledge-abuse

if [ $? -eq 0 ]; then
    echo "备份文件已成功恢复到本地: $LOCAL_DIR$LATEST_BACKUP"
    
    echo "开始执行AMH还原操作..."
    # 执行AMH还原命令
    amh amdata revert "$LATEST_BACKUP"
    
    if [ $? -eq 0 ]; then
        echo "AMH还原操作完成"
        echo "整个恢复过程已成功完成！"
    else
        echo "AMH还原操作失败"
        exit 1
    fi
else
    echo "备份文件恢复过程中发生错误"
    exit 1
fi