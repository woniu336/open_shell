#!/bin/bash

# 启动监控
start() {
    echo "开始监控..."
    nohup python3 -u buyvm.py > monitor.log 2>&1 &
    echo $! > monitor.pid
    echo "监控进程已启动，PID: $(cat monitor.pid)"
    echo "使用 'tail -f monitor.log' 查看实时日志"
}

# 停止监控
stop() {
    if [ -f monitor.pid ]; then
        pid=$(cat monitor.pid)
        echo "正在停止监控进程 (PID: $pid)..."
        kill $pid
        rm monitor.pid
        echo "监控已停止"
    else
        echo "没有找到正在运行的监控进程"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 1
        start
        ;;
    *)
        echo "用法: $0 {start|stop|restart}"
        exit 1
        ;;
esac 