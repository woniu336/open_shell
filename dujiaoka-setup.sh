#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 函数定义
install_docker() {
    echo -e "${YELLOW}正在检查 Docker 安装状态...${NC}"
    if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
        echo -e "${GREEN}Docker 和 Docker Compose 已经安装${NC}"
    else
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        sudo systemctl enable docker
        echo -e "${GREEN}Docker 安装完成${NC}"
    fi
    read -p "按回车键继续..."
}

check_docker() {
    echo -e "${YELLOW}检查 Docker 安装状态...${NC}"
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        echo -e "${GREEN}Docker 版本: ${docker_version}${NC}"
    else
        echo -e "${RED}Docker 未安装${NC}"
    fi
    
    if command -v docker-compose &> /dev/null; then
        compose_version=$(docker-compose --version | awk '{print $4}' | tr -d ',')
        echo -e "${GREEN}Docker Compose 版本: ${compose_version}${NC}"
    else
        echo -e "${RED}Docker Compose 未安装${NC}"
    fi
    read -p "按回车键继续..."
}

install_dujiaoka() {
    echo -e "${YELLOW}正在安装独角数卡...${NC}"
    
    # 下载安装脚本
    if curl -sS -o duka.sh https://raw.githubusercontent.com/woniu336/open_shell/main/duka.sh; then
        chmod +x duka.sh
        echo -e "${GREEN}安装脚本下载成功${NC}"
    else
        echo -e "${RED}安装脚本下载失败，请检查网络连接后重试${NC}"
        read -p "按回车键返回主菜单..."
        return
    fi
    
    # 运行安装脚本
    echo -e "${YELLOW}正在执行安装脚本，这可能需要几分钟...${NC}"
    if ./duka.sh; then
        echo -e "${GREEN}独角数卡安装脚本执行完成${NC}"
        echo -e "${YELLOW}请注意查看上方输出中的数据库密码，您将在后续配置中需要它。${NC}"
    else
        echo -e "${RED}独角数卡安装脚本执行失败${NC}"
        echo -e "${YELLOW}请检查错误信息，解决问题后重试${NC}"
    fi
    
    read -p "按回车键继续..."
}

configure_dujiaoka() {
    clear
    echo -e "${GREEN}请按照以下步骤进行网页配置：${NC}"
    echo -e ""
    echo -e "1. 打开浏览器，访问 ${CYAN}http://你的服务器IP:3080${NC}"
    echo -e "2. 在配置页面中，按如下设置：\n"
    
    echo -e "   ${PURPLE}● 数据库设置：${NC}"
    echo -e "     - 数据库地址: ${CYAN}db${NC}"
    echo -e "     - 数据库用户名: ${CYAN}dujiaoka${NC}"
    echo -e "     - 数据库密码: ${CYAN}[使用终端显示的密码]${NC}"
    
    echo -e "\n   ${PURPLE}● Redis设置：${NC}"
    echo -e "     - Redis地址: ${CYAN}redis${NC}"
    
    echo -e "\n   ${PURPLE}● 网站设置：${NC}"
    echo -e "     - 网站名称: ${CYAN}[填写你的网站名称]${NC}"
    echo -e "     - 网站URL: ${CYAN}[填写完整域名，如 http://shop.example.com]${NC}"
    
    echo -e "\n${GREEN}提示：后台地址/admin  默认用户名和密码：admin${NC}"
    echo -e ""
    read -p "$(echo -e ${YELLOW}"配置完成后，按回车键继续..."${NC})"
}

disable_install() {
    echo -e "${YELLOW}禁用安装...${NC}"
    cd /root/dujiao
    sed -i 's/INSTALL=true/INSTALL=false/' docker-compose.yaml
    docker-compose down && docker-compose up -d
    echo -e "${GREEN}安装已禁用${NC}"
    read -p "按回车键继续..."
}

enable_https() {
    echo -e "${YELLOW}启用 HTTPS...${NC}"
    sed -i 's/ADMIN_HTTPS=false/ADMIN_HTTPS=true/' /root/dujiao/env.conf
    echo -e "${GREEN}HTTPS 已启用${NC}"
    echo -e "${YELLOW}请注意：你的域名启用了证书的情况下${NC}"
    read -p "按回车键继续..."
}

disable_debug() {
    echo -e "${YELLOW}禁用调试模式...${NC}"
    sed -i 's/APP_DEBUG=true/APP_DEBUG=false/' /root/dujiao/env.conf
    echo -e "${GREEN}调试模式已禁用${NC}"
    read -p "按回车键继续..."
}

# 完全删除独角数卡函数
remove_dujiaoka() {
    echo -e "${YELLOW}正在删除独角数卡，这需要你喝一杯水的时间...${NC}"
    
    # 停止并删除容器
    docker stop faka faka-data faka-redis
    docker rm faka faka-data faka-redis
    
    # 删除指定的镜像
    docker rmi ghcr.io/apocalypsor/dujiaoka:latest redis:alpine mariadb:focal
    
    # 删除正确的网络名称
    docker network rm dujiao_default
    
    # 删除相关文件和目录
    rm -rf /root/dujiao
    
    echo -e "${GREEN}独角数卡已完全删除${NC}"
    read -p "按回车键继续..."
}

# 主菜单
show_menu() {
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}    独角数卡安装和管理脚本${NC}"
    echo -e "${CYAN}    Blog: woniu336.github.io${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo "1. 安装 Docker"
    echo "2. 查看 Docker 版本"
    echo "3. 安装独角数卡"
    echo "4. 配置独角数卡"
    echo "5. 禁用安装"
    echo "6. 启用 HTTPS"
    echo "7. 禁用调试模式"
    echo "8. 完全删除独角数卡"
    echo "0. 退出"
    echo -e "${GREEN}===================================${NC}"
}

# 主循环
while true; do
    clear
    show_menu
    read -p "请选择操作 (0-8): " choice
    clear
    
    case $choice in
        1) install_docker ;;
        2) check_docker ;;
        3) install_dujiaoka ;;
        4) configure_dujiaoka ;;
        5) disable_install ;;
        6) enable_https ;;
        7) disable_debug ;;
        8) remove_dujiaoka ;;
        0) echo "退出脚本"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重新输入${NC}"; read -p "按回车键继续..." ;;
    esac
done