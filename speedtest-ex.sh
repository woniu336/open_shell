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
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}Docker 安装完成${NC}"
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker Compose...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        
        # 等待安装完成并验证
        for i in {1..5}; do
            if command -v docker-compose &> /dev/null; then
                echo -e "${GREEN}Docker Compose 安装完成${NC}"
                break
            fi
            if [ $i -eq 5 ]; then
                echo -e "${RED}Docker Compose 安装失败，请手动安装后重试${NC}"
                exit 1
            fi
            echo -e "${YELLOW}等待 Docker Compose 安装完成...${NC}"
            sleep 2
        done
    fi

    # 验证Docker服务状态
    if ! systemctl is-active docker >/dev/null 2>&1; then
        echo -e "${YELLOW}正在启动 Docker 服务...${NC}"
        systemctl start docker
    fi
}

# 安装 SpeedTest-EX
install_speedtest() {
    echo -e "${YELLOW}开始安装 SpeedTest-EX...${NC}"
    
    # 验证Docker和Docker Compose是否可用
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}Docker 或 Docker Compose 未正确安装，请检查安装状态${NC}"
        return 1
    fi
    
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

[auth]
enable = false
username = "admin"
password = "password"
secret = "please_change_this_secret_key"
EOF

    # 启动服务
    docker-compose up -d
    
    # 获取IPv4地址
    SERVER_IP=$(curl -s4 ip.sb || curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
    
    echo -e "${GREEN}SpeedTest-EX 安装完成！${NC}"
    echo -e "访问地址: http://${SERVER_IP}:8989"
    
    # 添加交互式鉴权配置
    echo -e "\n${YELLOW}安全配置${NC}"
    echo -e "建议配置鉴权功能以保护服务器资源"
    echo -e "${YELLOW}是否现在配置鉴权？[y/n]${NC}"
    read -r configure_auth
    
    if [[ "$configure_auth" =~ ^[Yy]$ ]] || [[ -z "$configure_auth" ]]; then
        # 设置启用鉴权
        sed -i 's/enable = false/enable = true/' "$CONFIG_DIR/config.toml"
        
        # 设置用户名
        echo -e "\n${YELLOW}请设置管理员用户名 (默认: admin):${NC}"
        read -r new_username
        if [ ! -z "$new_username" ]; then
            sed -i "s|username = \"admin\"|username = \"$new_username\"|" "$CONFIG_DIR/config.toml"
        fi
        
        # 设置密码
        echo -e "\n${YELLOW}请设置管理员密码 (默认: password):${NC}"
        read -r new_password
        if [ ! -z "$new_password" ]; then
            sed -i "s|password = \"password\"|password = \"$new_password\"|" "$CONFIG_DIR/config.toml"
        fi
        
        # 生成随机密钥
        random_secret=$(openssl rand -base64 32)
        sed -i "s|secret = \"please_change_this_secret_key\"|secret = \"$random_secret\"|" "$CONFIG_DIR/config.toml"
        
        echo -e "\n${YELLOW}正在重启服务以应用新配置...${NC}"
        docker-compose restart
        
        echo -e "\n${GREEN}鉴权配置完成！${NC}"
        echo -e "用户名: ${new_username:-admin}"
        echo -e "密码: ${new_password:-password}"
        echo -e "密钥已自动生成"
    else
        echo -e "\n${YELLOW}您选择了不配置鉴权，您可以之后使用选项 2 来修改配置${NC}"
    fi
}

# 修改配置文件
modify_config() {
    if [ ! -f "$CONFIG_DIR/config.toml" ]; then
        echo -e "${RED}配置文件不存在，请先安装 SpeedTest-EX${NC}"
        return
    fi

    echo -e "${YELLOW}当前配置文件内容：${NC}"
    cat "$CONFIG_DIR/config.toml"
    
    echo -e "\n${YELLOW}配置说明：${NC}"
    echo -e "1. [auth] 部分用于配置鉴权功能："
    echo -e "   - enable: 是否启用鉴权"
    echo -e "   - username: 登录用户名"
    echo -e "   - password: 登录密码"
    echo -e "   - secret: 用于加密session的密钥，建议使用随机字符串"
    
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
    docker-compose down --rmi all
    
    # 清理相关的Docker镜像
    echo -e "${YELLOW}正在清理Docker镜像...${NC}"
    docker image rm wjqserver/speedtest-ex:latest >/dev/null 2>&1 || true
    
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