#!/bin/bash

# 设置日志文件目录
LOG_DIR="/home/usrdata/mysql-generic-5.7"
# 设置要保留的最新日志文件数量
KEEP_LOGS=5
# 日志文件前缀
LOG_PREFIX="mysql-bin"

# 检查目录是否存在
if [ ! -d "$LOG_DIR" ]; then
    echo "错误：目录 $LOG_DIR 不存在"
    exit 1
fi

# 切换到日志目录
cd "$LOG_DIR"

# 获取所有匹配的日志文件并按名称排序
log_files=($(ls ${LOG_PREFIX}.* 2>/dev/null | sort))
total_files=${#log_files[@]}

# 检查是否有日志文件
if [ $total_files -eq 0 ]; then
    echo "没有找到日志文件"
    exit 0
fi

# 计算需要删除的文件数量
files_to_delete=$((total_files - KEEP_LOGS))

if [ $files_to_delete -le 0 ]; then
    echo "当前日志文件数量（$total_files）小于或等于需要保留的数量（$KEEP_LOGS），不需要清理"
    exit 0
fi

# 删除旧的日志文件
echo "开始清理旧的日志文件..."
for ((i=0; i<files_to_delete; i++)); do
    file_to_remove=${log_files[i]}
    if rm "$file_to_remove"; then
        echo "已删除: $file_to_remove"
    else
        echo "删除失败: $file_to_remove"
    fi
done

echo "清理完成。保留了最新的 $KEEP_LOGS 个日志文件"