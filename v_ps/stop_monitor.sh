#!/bin/bash

PID_FILE="monitor.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null 2>&1; then
        echo "停止监控程序 (PID: $PID)..."
        kill $PID
        rm "$PID_FILE"
        echo "监控程序已停止"
    else
        echo "监控程序未在运行"
        rm "$PID_FILE"
    fi
else
    echo "PID文件不存在，监控程序可能未在运行"
fi