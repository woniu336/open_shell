#!/bin/bash

SCRIPT_NAME="vps_stock_monitor.py"
LOG_FILE="monitor.log"
PID_FILE="monitor.pid"

# 检查是否已经运行
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null 2>&1; then
        echo "监控程序已在运行 (PID: $PID)"
        exit 1
    else
        echo "清理旧的PID文件..."
        rm "$PID_FILE"
    fi
fi

# 检查并安装依赖
if ! python3 -c "import requests" 2>/dev/null; then
    echo "安装 requests 模块..."
    python3 -m pip install requests >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "安装 requests 失败"
        exit 1
    fi
fi

# 检查脚本文件是否存在
if [ ! -f "$SCRIPT_NAME" ]; then
    echo "错误: $SCRIPT_NAME 不存在"
    exit 1
fi

# 启动Python脚本
echo "启动VPS监控脚本..."
nohup python3 $SCRIPT_NAME > $LOG_FILE 2>&1 &

# 检查是否成功启动
sleep 2
if ! ps -p $! > /dev/null 2>&1; then
    echo "启动失败，请检查日志文件"
    exit 1
fi

# 保存进程ID
echo $! > $PID_FILE

echo "监控程序已在后台运行"
echo "PID: $(cat $PID_FILE)"
echo "日志文件: $LOG_FILE"
echo "使用 'tail -f $LOG_FILE' 查看运行日志"