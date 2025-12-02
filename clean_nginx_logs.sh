#!/bin/bash

LOG_DIR="/home/web/log/nginx"
KEEP=3

cd "$LOG_DIR" || exit

# 清理 access 日志压缩包，只留最新 3 个
ls -1t access.log-*.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

# 清理 error 日志压缩包，只留最新 3 个
ls -1t error.log-*.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
