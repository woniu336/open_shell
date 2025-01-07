#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 安装目录
INSTALL_DIR="/root/data/docker_data/speedtest-ex"
CONFIG_DIR="$INSTALL_DIR/speedtest-ex/config"

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 检查并安装Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        
        echo -e "${YELLOW}正在安装 Docker Compose...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        
        echo -e "${GREEN}Docker 和 Docker Compose 安装完成${NC}"
    fi
}

# 安装 SpeedTest-EX
install_speedtest() {
    echo -e "${YELLOW}开始安装 SpeedTest-EX...${NC}"
    
    # 创建必要的目录
    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR || exit
    
    # 创建 docker-compose.yml
    cat > docker-compose.yml << 'EOF'
services:
  speedtest-ex:
    image: 'wjqserver/speedtest-ex:latest'
    restart: always
    volumes:
      - './speedtest-ex/config:/data/speedtest-ex/config'
      - './speedtest-ex/log:/data/speedtest-ex/log'
      - './speedtest-ex/db:/data/speedtest-ex/db'
    ports:
      - '8989:8989'
EOF

    # 创建配置目录和配置文件
    mkdir -p $CONFIG_DIR
    
    # 创建默认配置文件
    cat > $CONFIG_DIR/config.toml << 'EOF'
[server]
host = "0.0.0.0"
port = 8989
basePath = ""

[log]
logFilePath = "/data/speedtest-ex/log/speedtest-ex.log"
maxLogSize = 5

[ipinfo]
model = "ipinfo"
ipinfo_url = ""
ipinfo_api_key = ""

[database]
model = "bolt"
path = "/data/speedtest-ex/db/speedtest.db"

[frontend]
chartlist = 100
EOF

    # 启动服务
    docker-compose up -d
    
    echo -e "${GREEN}SpeedTest-EX 安装完成！${NC}"
    echo -e "访问地址: http://$(curl -s ip.sb):8989"
}

# 修改配置文件
modify_config() {
    if [ ! -f "$CONFIG_DIR/config.toml" ]; then
        echo -e "${RED}配置文件不存在，请先安装 SpeedTest-EX${NC}"
        return
    fi

    echo -e "${YELLOW}当前配置文件内容：${NC}"
    cat "$CONFIG_DIR/config.toml"
    
    echo -e "\n${YELLOW}是否要修改配置文件？[y/N]${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        nano "$CONFIG_DIR/config.toml"
        
        echo -e "${YELLOW}正在重启服务以应用新配置...${NC}"
        cd $INSTALL_DIR || exit
        docker-compose restart
        echo -e "${GREEN}配置已更新${NC}"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${YELLOW}=== SpeedTest-EX 安装管理工具 ===${NC}"
    echo "1. 安装 SpeedTest-EX"
    echo "2. 修改配置文件"
    echo "3. 卸载 SpeedTest-EX"
    echo "4. 退出"
}

# 卸载 SpeedTest-EX
uninstall_speedtest() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}SpeedTest-EX 未安装${NC}"
        return
    fi

    echo -e "${YELLOW}正在卸载 SpeedTest-EX...${NC}"
    
    # 停止并删除容器
    cd "$INSTALL_DIR" || exit
    docker-compose down
    
    # 询问是否删除数据
    echo -e "\n${YELLOW}是否删除所有数据（包括配置文件和测速记录）？[y/N]${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}所有数据已删除${NC}"
    else
        echo -e "${GREEN}数据已保留在 $INSTALL_DIR${NC}"
    fi
    
    echo -e "${GREEN}SpeedTest-EX 已成功卸载${NC}"
}

# 主程序
main() {
    check_root
    install_docker
    
    while true; do
        show_menu
        read -p "请选择操作 [1-4]: " choice
        case $choice in
            1) install_speedtest ;;
            2) modify_config ;;
            3) uninstall_speedtest ;;
            4) 
                echo -e "${GREEN}感谢使用！${NC}"
                exit 0 
                ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        read -p "按回车键继续..."
    done
}

main 