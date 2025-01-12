#!/bin/bash

# 定义本地和远程目录
LOCAL_DIR="/home/backup/"
REMOTE_DIR="r2:存储桶名/目录"

# 执行 AMH 备份命令
echo "开始执行 AMH 备份..."
amh amdata backup n y y n n n n

# 等待备份命令完成
echo "等待备份完成..."
sleep 60  # 给系统一些时间来完成备份操作

# 检查最新的备份文件是否已生成
latest_backup=$(find "$LOCAL_DIR" -type f -name "*.tar.gz.amh" -mmin -5)
while [ -z "$latest_backup" ]; do
    echo "正在等待备份文件生成..."
    sleep 5
    latest_backup=$(find "$LOCAL_DIR" -type f -name "*.tar.gz.amh" -mmin -5)
done

echo "AMH 备份已完成，开始同步到远程存储..."

# 同步新文件，跳过已存在的文件
echo "开始同步新文件..."
rclone copy "$LOCAL_DIR" "$REMOTE_DIR" --ignore-existing -u -v -P --transfers=6 --ignore-errors --buffer-size=64M --check-first --checkers=10 --drive-acknowledge-abuse

# 删除本地超过10个的旧文件
echo "清理本地旧文件..."
cd "$LOCAL_DIR" || exit
# 按修改时间排序，保留最新的10个文件，删除其他文件
find . -type f -printf '%T+ %p\n' | sort -r | awk 'NR>10 {print $2}' | xargs rm -f

# 删除远程超过10个的旧文件
echo "清理远程旧文件..."
# 获取远程文件列表，按文件名排序（因为文件名包含时间戳）
REMOTE_FILES=$(rclone lsf "$REMOTE_DIR" --files-only | sort | head -n -10)

if [ -z "$REMOTE_FILES" ]; then
    echo "远程目录为空，无需清理。"
else
    echo "$REMOTE_FILES" | while IFS= read -r file; do
        echo "正在删除远程文件: $file"
        rclone deletefile "$REMOTE_DIR/$file" --verbose
    done
fi

echo "备份和清理完成。"