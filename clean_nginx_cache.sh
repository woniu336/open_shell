#!/bin/bash

# 定义路径和日志文件
CACHE_DIR="/usr/local/nginx/cache/proxy"
LOG_FILE="/var/log/nginx_cache_clean.log"

# 检查目录是否存在
if [ ! -d "$CACHE_DIR" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Error: Directory $CACHE_DIR does not exist!" >> "$LOG_FILE"
    exit 1
fi

# 删除文件并记录日志
echo "===== Start cleaning Nginx cache at $(date) =====" >> "$LOG_FILE"
find "$CACHE_DIR" -type f -exec rm -v {} \; 2>&1 | tee -a "$LOG_FILE"

# 清理空目录（可选）
find "$CACHE_DIR" -type d -empty -delete 2>&1 | tee -a "$LOG_FILE"

echo "===== Cleanup completed at $(date) =====" >> "$LOG_FILE"