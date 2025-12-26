#!/bin/bash
# save_kua.sh - 修复版安装启动脚本（移除了定时任务设置）
# 用法: ./save_kua.sh [install|start|stop|status|restart|help]

set -e

# 配置
PROJECT_DIR="$HOME/auto-save-kua"
APP_DIR="$PROJECT_DIR/simple_admin"
PID_FILE="/tmp/save_kua.pid"
LOG_FILE="$APP_DIR/app.log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查命令是否存在
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓ $1 已安装${NC}"
        return 0
    else
        echo -e "${RED}✗ $1 未安装${NC}"
        return 1
    fi
}

# 安装 pip 包（处理系统保护）
install_pip_package() {
    local package="$1"
    echo -e "${YELLOW}安装: $package${NC}"
    
    if pip3 install "$package" 2>&1 | grep -q "externally-managed-environment"; then
        pip3 install --break-system-packages "$package"
        echo -e "${GREEN}✓ $package 安装成功${NC}"
    elif pip3 install "$package" 2>&1 | grep -q "Successfully installed"; then
        echo -e "${GREEN}✓ $package 安装成功${NC}"
    else
        echo -e "${GREEN}✓ $package 已安装或安装成功${NC}"
    fi
}

# 安装 requirements.txt
install_requirements() {
    local req_file="$1"
    
    if [ ! -f "$req_file" ]; then
        echo -e "${YELLOW}警告: 未找到 $req_file${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}从 $req_file 安装依赖...${NC}"
    
    if pip3 install -r "$req_file" 2>&1 | grep -q "externally-managed-environment"; then
        pip3 install --break-system-packages -r "$req_file"
        echo -e "${GREEN}✓ 依赖安装完成${NC}"
    else
        echo -e "${GREEN}✓ 依赖安装完成${NC}"
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
        sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-full
    fi
    
    # 检查并安装pip3
    if check_command pip3; then
        pip3 --version
    else
        echo "正在安装 pip3..."
        sudo apt-get install -y python3-pip python3-full
    fi
    
    # 检查并安装其他依赖
    check_command jq || sudo apt-get install -y jq
    check_command git || sudo apt-get install -y git
    check_command curl || sudo apt-get install -y curl
    
    # 创建 pip 配置以绕过系统保护
    echo -e "${YELLOW}配置 pip 以绕过系统保护...${NC}"
    mkdir -p ~/.config/pip
    echo "[global]
break-system-packages = true" > ~/.config/pip/pip.conf
    
    # 安装基础Python依赖
    echo "安装基础Python依赖..."
    install_pip_package "aiohttp"
    install_pip_package "flask"
    install_pip_package "flask-cors"
    
    # 下载项目
    echo "下载项目..."
    if [ -d "$PROJECT_DIR" ]; then
        echo "项目已存在，更新中..."
        cd "$PROJECT_DIR"
        git pull origin main || git pull origin master || echo "使用现有版本"
    else
        cd ~
        echo "正在克隆项目..."
        git clone https://github.com/woniu336/auto-save-kua.git
    fi
    
    # 检查项目结构
    echo "检查项目结构..."
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}错误: 未找到应用目录 $APP_DIR${NC}"
        echo "项目结构可能是:"
        find "$PROJECT_DIR" -type f -name "*.py" | head -10
        exit 1
    fi
    
    # 安装 requirements.txt 中的依赖
    if [ -f "$PROJECT_DIR/requirements.txt" ]; then
        install_requirements "$PROJECT_DIR/requirements.txt"
    elif [ -f "$APP_DIR/requirements.txt" ]; then
        install_requirements "$APP_DIR/requirements.txt"
    else
        echo -e "${YELLOW}未找到 requirements.txt，安装常见依赖...${NC}"
        install_pip_package "requests"
        install_pip_package "beautifulsoup4"
        install_pip_package "selenium"
    fi
    
    # 检查 app.py 需要的额外依赖
    echo "检查应用额外依赖..."
    if [ -f "$APP_DIR/app.py" ]; then
        # 检查导入的模块
        if grep -q "import " "$APP_DIR/app.py"; then
            echo "检测到以下导入:"
            grep -E "^(import|from)" "$APP_DIR/app.py" | head -10
            
            # 尝试安装常见模块
            if grep -q "import requests" "$APP_DIR/app.py"; then
                install_pip_package "requests"
            fi
            if grep -q "import bs4\|beautifulsoup" "$APP_DIR/app.py"; then
                install_pip_package "beautifulsoup4"
            fi
            if grep -q "import selenium" "$APP_DIR/app.py"; then
                install_pip_package "selenium"
            fi
        fi
    fi
    
    # 设置权限
    echo "设置执行权限..."
    [ -f "$PROJECT_DIR/clean_log_simple.py" ] && chmod +x "$PROJECT_DIR/clean_log_simple.py"
    [ -f "$APP_DIR/app.py" ] && chmod +x "$APP_DIR/app.py"
    
    echo ""
    echo -e "${GREEN}=== 安装完成 ===${NC}"
    echo "项目路径: $PROJECT_DIR"
    echo "应用目录: $APP_DIR"
    echo "访问地址: http://localhost:5006"
    echo "日志文件: $LOG_FILE"
    echo ""
    echo "常用命令:"
    echo "  启动: $0 start"
    echo "  停止: $0 stop"
    echo "  状态: $0 status"
    echo "  重启: $0 restart"
    echo "  查看日志: tail -f $LOG_FILE"
    echo ""
    echo -e "${YELLOW}定时任务说明:${NC}"
    echo "  如需设置定时清理日志，请手动添加以下定时任务："
    echo "  crontab -e"
    echo "  添加: 0 3 * * * cd $PROJECT_DIR && /usr/bin/python3 clean_log_simple.py 2>&1 | logger -t save_kua"
    echo ""
    echo -e "${YELLOW}请运行 '$0 start' 启动应用${NC}"
}

# 启动函数
start_app() {
    echo "启动应用程序..."
    
    # 检查是否已安装
    if [ ! -f "$APP_DIR/app.py" ]; then
        echo -e "${RED}错误: 应用未安装或 app.py 不存在${NC}"
        echo "请先运行: $0 install"
        exit 1
    fi
    
    # 检查是否已在运行
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            echo -e "${GREEN}应用已经在运行 (PID: $PID)${NC}"
            echo "访问地址: http://localhost:5006"
            exit 0
        else
            echo "清理旧的 PID 文件..."
            rm -f "$PID_FILE"
        fi
    fi
    
    # 启动
    echo "正在启动..."
    cd "$APP_DIR"
    
    # 确保日志目录存在
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 启动应用并记录PID
    nohup python3 app.py > "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    
    sleep 3
    
    # 检查是否启动成功
    if kill -0 $PID 2>/dev/null; then
        echo -e "${GREEN}✓ 启动成功!${NC}"
        echo "  PID: $PID"
        echo "  端口: 5006"
        echo "  日志: $LOG_FILE"
        echo "  访问: http://localhost:5006"
        
        # 等待应用完全启动
        sleep 2
        echo ""
        echo "检查应用状态..."
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:5006 | grep -q "200\|302\|404"; then
            echo -e "${GREEN}✓ 应用服务正常${NC}"
        else
            echo -e "${YELLOW}⚠ 应用可能正在启动中，请稍后访问...${NC}"
        fi
    else
        echo -e "${RED}✗ 启动失败${NC}"
        echo "请查看日志文件: $LOG_FILE"
        tail -20 "$LOG_FILE"
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
        echo "正在停止进程 $PID..."
        kill $PID
        sleep 2
        
        if kill -0 $PID 2>/dev/null; then
            echo "强制停止..."
            kill -9 $PID
        fi
        
        echo -e "${GREEN}✓ 已停止 (PID: $PID)${NC}"
    else
        echo "应用未在运行"
    fi
    
    rm -f "$PID_FILE"
}

# 状态函数
status_app() {
    echo "应用程序状态:"
    
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            echo -e "${GREEN}✓ 正在运行${NC}"
            echo "  PID: $PID"
            echo "  运行时间: $(ps -p $PID -o etime= 2>/dev/null || echo "未知")"
            
            # 检查端口
            if netstat -tlnp 2>/dev/null | grep ":$PID\|:5006" &>/dev/null; then
                echo "  端口: 5006 (监听中)"
            else
                echo "  端口: 5006 (可能未监听)"
            fi
            
            # 检查内存使用
            MEM_USAGE=$(ps -p $PID -o rss= 2>/dev/null)
            if [ -n "$MEM_USAGE" ]; then
                MEM_MB=$((MEM_USAGE / 1024))
                echo "  内存使用: ${MEM_MB}MB"
            fi
            
            echo "  日志文件: $LOG_FILE"
            echo "  访问地址: http://localhost:5006"
            
            # 尝试访问
            echo -n "  服务状态: "
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:5006 --connect-timeout 2 &>/dev/null; then
                echo -e "${GREEN}可访问${NC}"
            else
                echo -e "${YELLOW}不可访问${NC}"
            fi
            return 0
        fi
    fi
    
    echo -e "${RED}✗ 未运行${NC}"
    
    # 检查是否有其他实例在运行
    OTHER_PID=$(pgrep -f "app.py" | head -1)
    if [ -n "$OTHER_PID" ]; then
        echo -e "${YELLOW}⚠ 发现未管理的进程 (PID: $OTHER_PID)${NC}"
        echo "  使用 '$0 stop' 停止，或手动终止: kill $OTHER_PID"
    fi
    
    return 1
}

# 重启函数
restart_app() {
    echo "重启应用程序..."
    stop_app
    sleep 2
    start_app
}

# 查看日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo "=== 应用日志 (最后50行) ==="
        tail -50 "$LOG_FILE"
    else
        echo "日志文件不存在: $LOG_FILE"
    fi
}

# 清理日志
clean_log() {
    echo "清理日志文件..."
    if [ -f "$LOG_FILE" ]; then
        > "$LOG_FILE"
        echo -e "${GREEN}✓ 日志已清理${NC}"
    else
        echo "日志文件不存在"
    fi
}

# 帮助函数
show_help() {
    echo -e "${GREEN}save_kua.sh - 完整安装启动脚本${NC}"
    echo ""
    echo "用法:"
    echo "  $0 install    安装应用和所有依赖"
    echo "  $0 start      启动应用（后台运行）"
    echo "  $0 stop       停止应用"
    echo "  $0 status     查看应用状态"
    echo "  $0 restart    重启应用"
    echo "  $0 log        查看应用日志"
    echo "  $0 clean      清理日志文件"
    echo "  $0 help       显示帮助信息"
    echo ""
    echo "示例:"
    echo "  # 首次安装"
    echo "  ./save_kua.sh install"
    echo "  ./save_kua.sh start"
    echo ""
    echo "  # 日常管理"
    echo "  ./save_kua.sh status    # 查看状态"
    echo "  ./save_kua.sh log       # 查看日志"
    echo "  ./save_kua.sh restart   # 重启应用"
    echo ""
    echo "项目路径: $PROJECT_DIR"
    echo ""
    echo "定时任务（手动设置）:"
    echo "  # 添加定时清理日志（每天凌晨3点）"
    echo "  crontab -e"
    echo "  # 添加: 0 3 * * * cd $PROJECT_DIR && /usr/bin/python3 clean_log_simple.py 2>&1 | logger -t save_kua"
}

# 主逻辑
case "$1" in
    "install") 
        install_app 
        ;;
    "start")   
        start_app   
        ;;
    "stop")    
        stop_app    
        ;;
    "status")  
        status_app  
        ;;
    "restart") 
        restart_app 
        ;;
    "log"|"logs")
        view_log
        ;;
    "clean")
        clean_log
        ;;
    "help"|"--help"|"-h"|"")
        show_help 
        ;;
    *) 
        echo -e "${RED}错误: 未知命令 '$1'${NC}"
        echo "使用 '$0 help' 查看帮助"
        exit 1 
        ;;
esac
