#!/bin/bash

# 定义本地和远程目录
LOCAL_DIR="/home/backup/"
REMOTE_DIR="r2:web/backup"

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