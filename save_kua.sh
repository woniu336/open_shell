#!/bin/bash
# save_kua.sh - 简洁版安装启动脚本
# 用法: ./save_kua.sh [install|start|stop|status|restart|help]

set -e

# 配置
PROJECT_DIR="$HOME/auto-save-kua"
APP_DIR="$PROJECT_DIR/simple_admin"
PID_FILE="/tmp/save_kua.pid"
LOG_FILE="$APP_DIR/app.log"

# 检查命令是否存在
check_command() {
    if command -v "$1" &> /dev/null; then
        echo "✓ $1 已安装"
        return 0
    else
        echo "✗ $1 未安装"
        return 1
    fi
}

# 安装函数
install_app() {
    echo "=== 开始安装 auto-save-kua ==="
    
    # 检查并安装python3
    if check_command python3; then
        python3 --version
    else
        echo "正在安装 python3..."
        sudo apt-get update && sudo apt-get install -y python3 python3-pip
    fi
    
    # 检查并安装pip3
    if check_command pip3; then
        pip3 --version
    else
        echo "正在安装 pip3..."
        sudo apt-get install -y python3-pip
    fi
    
    # 检查并安装其他依赖
    check_command jq || sudo apt-get install -y jq
    check_command git || sudo apt-get install -y git
    
    # 安装Python依赖
    echo "安装Python依赖..."
    pip3 install aiohttp flask
    
    # 下载项目
    echo "下载项目..."
    if [ -d "$PROJECT_DIR" ]; then
        cd "$PROJECT_DIR"
        git pull || echo "使用现有版本"
    else
        cd ~
        git clone https://github.com/woniu336/auto-save-kua.git
    fi
    
    # 设置权限
    [ -f "$PROJECT_DIR/clean_log_simple.py" ] && chmod +x "$PROJECT_DIR/clean_log_simple.py"
    
    # 设置定时任务
    echo "设置定时任务..."
    CRON_JOB="0 3 * * * cd $PROJECT_DIR && /usr/bin/python3 clean_log_simple.py"
    (crontab -l 2>/dev/null | grep -v "clean_log_simple.py"; echo "$CRON_JOB") | crontab -
    
    echo ""
    echo "=== 安装完成 ==="
    echo "项目路径: $PROJECT_DIR"
    echo "访问地址: http://localhost:5006"
    echo ""
    echo "启动命令: $0 start"
    echo "停止命令: $0 stop"
}

# 启动函数
start_app() {
    echo "启动应用程序..."
    
    # 检查是否已安装
    if [ ! -f "$APP_DIR/app.py" ]; then
        echo "错误: 应用未安装，请先运行: $0 install"
        exit 1
    fi
    
    # 检查是否已在运行
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            echo "应用已经在运行 (PID: $PID)"
            exit 0
        fi
    fi
    
    # 启动
    cd "$APP_DIR"
    python3 app.py > "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    
    sleep 2
    if kill -0 $PID 2>/dev/null; then
        echo "✓ 启动成功! (PID: $PID)"
        echo "日志文件: $LOG_FILE"
        echo "本地访问: http://localhost:5006"
    else
        echo "✗ 启动失败，请检查日志"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# 停止函数
stop_app() {
    echo "停止应用程序..."
    
    if [ ! -f "$PID_FILE" ]; then
        echo "应用未在运行"
        return 0
    fi
    
    PID=$(cat "$PID_FILE")
    
    if kill -0 $PID 2>/dev/null; then
        kill $PID 2>/dev/null && echo "✓ 已停止 (PID: $PID)" || echo "停止失败"
    else
        echo "应用未在运行"
    fi
    
    rm -f "$PID_FILE"
}

# 状态函数
status_app() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            echo "✓ 应用正在运行"
            echo "  PID: $PID"
            echo "  端口: 5006"
            echo "  日志: $LOG_FILE"
            echo "  地址: http://localhost:5006"
            return 0
        fi
    fi
    echo "✗ 应用未在运行"
    return 1
}

# 重启函数
restart_app() {
    stop_app
    sleep 1
    start_app
}

# 帮助函数
show_help() {
    echo "save_kua.sh - 简洁安装启动脚本"
    echo ""
    echo "用法:"
    echo "  $0 install    安装应用和依赖"
    echo "  $0 start      启动应用"
    echo "  $0 stop       停止应用"
    echo "  $0 status     查看状态"
    echo "  $0 restart    重启应用"
    echo "  $0 help       显示帮助"
    echo ""
    echo "示例:"
    echo "  # 首次安装并启动"
    echo "  ./save_kua.sh install"
    echo "  ./save_kua.sh start"
    echo ""
    echo "  # 日常使用"
    echo "  ./save_kua.sh start"
    echo "  ./save_kua.sh stop"
}

# 主逻辑
case "$1" in
    "install") install_app ;;
    "start")   start_app   ;;
    "stop")    stop_app    ;;
    "status")  status_app  ;;
    "restart") restart_app ;;
    "help"|"--help"|"-h"|"") show_help ;;
    *) echo "错误: 未知命令 '$1'，使用 '$0 help' 查看帮助" && exit 1 ;;
esac
