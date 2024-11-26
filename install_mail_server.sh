#!/bin/bash

# 颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 请使用root用户运行此脚本${NC}"
        exit 1
    fi
}

# 在initial_check函数前添加检查docker函数
check_docker() {
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        echo "正在安装 Docker..."
        curl -fsSL https://get.docker.com | sh
    fi
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo "正在安装 Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

# 添加main_menu_action函数处理菜单选择
main_menu_action() {
    local choice=$1
    case $choice in
        1)
            read -p "请输入邮箱域名 (例如: mail.example.com): " domain
            create_docker_compose "$domain"           
            echo "正在启动服务..."
            docker-compose up -d
            
            show_dns_info "$domain"
            echo -e "\n${GREEN}安装完成！${NC}"
            echo "首次配置页面: https://${domain}"
            echo "管理后台: https://${domain}/admin"
            echo "默认管理员账号: admin@${domain#mail.}"
            ;;
        2)
            if [ -d "/root/data/docker_data/posteio" ]; then
                cd /root/data/docker_data/posteio
                echo "正在更新服务..."
                docker-compose pull
                docker-compose up -d
                echo -e "${GREEN}更新完成！${NC}"
            else
                echo -e "${RED}未找到安装目录！${NC}"
            fi
            ;;
        3)
            if [ -d "/root/data/docker_data/posteio" ]; then
                cd /root/data/docker_data/posteio
                echo "正在卸载服务..."
                docker-compose down
                docker rmi -f analogic/poste.io
                cd /root/data/docker_data
                rm -rf posteio
                echo -e "${GREEN}已完全卸载服务、数据和镜像！${NC}"
            else
                echo -e "${RED}未找到安装目录！${NC}"
            fi
            ;;
    esac
    
    echo -e "\n按回车键继续..."
    read
    initial_check
}

# 修改initial_check函数，添加docker检查
initial_check() {
    clear
    # 检查docker
    check_docker
    
    echo -e "\033[38;5;81m┌──────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[38;5;81m│\033[0m            \033[1;36m邮件服务器管理脚本\033[0m                 \033[38;5;81m│\033[0m"
    echo -e "\033[38;5;81m│\033[0m            \033[1;33mPoste.io 一键部署\033[0m                  \033[38;5;81m│\033[0m"
    echo -e "\033[38;5;81m└──────────────────────────────────────────────────┘\033[0m"
    echo ""
    
    # 系统检查部分
    echo -e "\033[1;36m系统检查\033[0m"
    echo -e "\033[38;5;81m────────────────────────\033[0m"
    
    # 检查telnet
    echo -n "✓ Telnet......... "
    if command -v telnet &> /dev/null; then
        echo -e "${GREEN}已安装${NC}"
    else
        echo -e "${RED}未安装${NC}"
        echo "正在安装telnet..."
        apt-get update && apt-get install -y telnet > /dev/null 2>&1
    fi

    # 检查邮件服务
    echo -n "✓ 邮局服务....... "
    if [ -d "/root/data/docker_data/posteio" ]; then
        echo -e "${GREEN}已安装${NC}"
    else
        echo -e "${RED}未安装${NC}"
    fi
        
    echo -e "\n\033[1;36m端口检测\033[0m"
    echo -e "\033[38;5;81m────────────────────────\033[0m"
    local port=25
    local timeout=3
    
    # 执行telnet检测并保存输出
    telnet_output=$(echo "quit" | timeout $timeout telnet smtp.qq.com $port 2>&1)
    echo "$telnet_output" | grep -E "Connected|Connection"
    
    if echo "$telnet_output" | grep -q 'Connected'; then
        echo -e "✓ 端口 25........ ${GREEN}当前可用${NC}"
    else
        echo -e "✗ 端口 25........ ${RED}当前不可用${NC}"
    fi
    
    echo -e "\n\033[1;36m操作选项\033[0m"
    echo -e "\033[38;5;81m────────────────────────\033[0m"
    echo -e "\033[1;32m1\033[0m. 安装服务器          \033[1;32m2\033[0m. 更新服务器"
    echo -e "\033[1;31m3\033[0m. 卸载服务器          \033[1;31m0\033[0m. 退出脚本"
    echo -e "\033[38;5;81m────────────────────────\033[0m"
    
    read -p "$(echo -e "\033[1;33m请输入选项 [0-3]: \033[0m")" choice
    
    case $choice in
        1|2|3)
            main_menu_action $choice
            ;;
        0)
            echo -e "\n${GREEN}感谢使用，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}无效选项，请重新选择${NC}"
            sleep 2
            initial_check
            ;;
    esac
}

# 创建docker-compose配置
create_docker_compose() {
    local domain=$1
    # 从域名中提取根域名
    local root_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
    local admin_email="admin@${root_domain}"
    
    mkdir -p /root/data/docker_data/posteio
    cd /root/data/docker_data/posteio
    
    cat > docker-compose.yml << EOF
services:
  mailserver:
    image: analogic/poste.io
    hostname: ${domain}
    ports:
      - "25:25"
      - "110:110"
      - "143:143"
      - "587:587"
      - "993:993"
      - "995:995"
      - "4190:4190"
      - "465:465"
      - "8808:80"      
      - "8843:443"    
    environment:
      - LETSENCRYPT_EMAIL=${admin_email}
      - LETSENCRYPT_HOST=${domain}
      - VIRTUAL_HOST=${domain}
      - DISABLE_CLAMAV=TRUE    
      - DISABLE_RSPAMD=TRUE    
      - TZ=Asia/Shanghai
      - HTTPS=OFF               
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./mail-data:/data
EOF
}

# 显示DNS配置信息
show_dns_info() {
    local domain=$1
    local ip=$(curl -s ifconfig.me)
    local root_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
    
    echo -e "\n${GREEN}请配置以下DNS记录：${NC}"
    echo "------------------------"
    echo "A           mail            ${ip}"
    echo "CNAME       imap            ${domain}"
    echo "CNAME       pop             ${domain}"
    echo "CNAME       smtp            ${domain}"
    echo "MX          @               ${domain}"
    echo "TXT         @               v=spf1 mx ~all"
    echo "TXT         _dmarc          v=DMARC1; p=none; rua=mailto:mail@${root_domain}"
    echo "------------------------"
}

# 修改主程序入口
check_root
initial_check