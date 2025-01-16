#!/bin/bash

# 颜色变量定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 清屏函数
clear_screen() {
    clear
}

# 显示横幅
show_banner() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}             服务器管理工具 v1.0              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
}

# 显示主菜单
show_menu() {
    echo -e "${YELLOW}请选择要执行的操作：${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} SSL证书申请"
    echo -e "${GREEN}2.${NC} Nginx管理"
    echo -e "${GREEN}3.${NC} 反向代理 ${YELLOW}★${NC}"
    echo -e "${GREEN}4.${NC} 流量监控"
    echo -e "${GREEN}5.${NC} Docker管理"
    echo -e "${GREEN}6.${NC} 快捷键设置"
    echo -e "${GREEN}7.${NC} 系统工具集 ${YELLOW}★${NC}"
    echo -e "${GREEN}0.${NC} 退出脚本"
    echo ""
    echo -e "${BLUE}=================================================${NC}"
}

# 显示Docker管理菜单
show_docker_menu() {
    clear_screen
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}             Docker 管理菜单              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 安装 Docker"
    echo -e "${GREEN}2.${NC} 卸载 Docker"
    echo -e "${GREEN}3.${NC} 启动 Docker"
    echo -e "${GREEN}4.${NC} 停止 Docker"
    echo -e "${GREEN}5.${NC} 重启 Docker"
    echo -e "${GREEN}6.${NC} 查看 Docker 状态"
    echo -e "${GREEN}0.${NC} 返回主菜单"
    echo ""
    echo -e "${BLUE}=================================================${NC}"
}

# Docker管理函数
docker_management() {
    while true; do
        show_docker_menu
        read -p "请输入选项 [0-6]: " docker_choice
        case $docker_choice in
            1)
                if command -v docker &>/dev/null; then
                    echo -e "${YELLOW}Docker 已经安装${NC}"
                else
                    echo -e "${YELLOW}正在安装 Docker...${NC}"
                    curl -fsSL https://get.docker.com | sh
                    systemctl start docker
                    systemctl enable docker
                    echo -e "${GREEN}Docker 安装完成！${NC}"
                fi
                ;;
            2)
                if ! command -v docker &>/dev/null; then
                    echo -e "${RED}Docker 未安装！${NC}"
                else
                    echo -e "${YELLOW}正在卸载 Docker...${NC}"
                    # 停止所有容器
                    docker ps -a -q | xargs -r docker rm -f
                    # 删除所有镜像
                    docker images -q | xargs -r docker rmi -f
                    # 清理所有未使用的网络
                    docker network prune -f
                    # 清理所有未使用的卷
                    docker volume prune -f
                    # 完全清理系统
                    docker system prune -af --volumes
                    
                    # 停止和禁用服务
                    systemctl stop docker
                    systemctl disable docker
                    systemctl stop docker.socket
                    systemctl disable docker.socket
                    
                    # 卸载 Docker 相关包
                    if command -v apt-get &>/dev/null; then
                        apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin
                        apt-get autoremove -y --purge
                    elif command -v yum &>/dev/null; then
                        yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin
                    fi
                    
                    # 删除所有 Docker 相关文件和目录
                    rm -rf /var/lib/docker
                    rm -rf /var/lib/containerd
                    rm -rf /etc/docker
                    rm -rf /etc/containerd
                    rm -f /etc/docker/daemon.json
                    rm -rf /var/run/docker.sock
                    rm -rf /usr/local/bin/docker-compose
                    
                    # 刷新 hash 表
                    hash -r
                    
                    echo -e "${GREEN}Docker 已完全卸载！${NC}"
                fi
                ;;
            3)
                if ! command -v docker &>/dev/null; then
                    echo -e "${RED}Docker 未安装！${NC}"
                else
                    systemctl start docker
                    echo -e "${GREEN}Docker 已启动！${NC}"
                fi
                ;;
            4)
                if ! command -v docker &>/dev/null; then
                    echo -e "${RED}Docker 未安装！${NC}"
                else
                    systemctl stop docker
                    echo -e "${GREEN}Docker 已停止！${NC}"
                fi
                ;;
            5)
                if ! command -v docker &>/dev/null; then
                    echo -e "${RED}Docker 未安装！${NC}"
                else
                    systemctl restart docker
                    echo -e "${GREEN}Docker 已重启！${NC}"
                fi
                ;;
            6)
                if ! command -v docker &>/dev/null; then
                    echo -e "${RED}Docker 未安装！${NC}"
                else
                    echo -e "${YELLOW}Docker 版本：${NC}"
                    docker --version
                    echo -e "${YELLOW}Docker 状态：${NC}"
                    systemctl status docker
                fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选项，请重新选择${NC}"
                ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 安装依赖
install_dependency() {
    if ! command -v docker &>/dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl start docker
        systemctl enable docker
    fi
}

# 申请证书
install_ssltls() {
    cd ~
    local file_path="/etc/letsencrypt/live/$yuming/fullchain.pem"
    
    # 使用 install_dependency 函数检查并安装 Docker
    install_dependency
    
    if [ ! -f "$file_path" ]; then
        local ipv4_pattern='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
        local ipv6_pattern='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
        if [[ ($yuming =~ $ipv4_pattern || $yuming =~ $ipv6_pattern) ]]; then
            mkdir -p /etc/letsencrypt/live/$yuming/
            openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -keyout /etc/letsencrypt/live/$yuming/privkey.pem -out /etc/letsencrypt/live/$yuming/fullchain.pem -days 5475 -subj "/C=US/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name"
        else
            # 检查 Nginx 是否已安装
            if ! command -v nginx &>/dev/null; then
                echo -e "${YELLOW}注意: Nginx 未安装，但不影响证书申请${NC}"
            # 如果 Nginx 已安装，检查是否在运行
            elif systemctl is-active nginx >/dev/null 2>&1; then
                echo -e "${YELLOW}检测到 Nginx 正在运行，需要临时停止以申请证书...${NC}"
                systemctl stop nginx
                local nginx_was_running=true
            fi
            
            # 申请证书
            docker run -it --rm -p 80:80 -v /etc/letsencrypt/:/etc/letsencrypt certbot/certbot certonly --standalone -d "$yuming" --email your@email.com --agree-tos --no-eff-email --force-renewal --key-type ecdsa
            
            # 如果之前 Nginx 在运行，重新启动它
            if [ "$nginx_was_running" = true ]; then
                echo -e "${YELLOW}重新启动 Nginx...${NC}"
                systemctl start nginx
                echo -e "${GREEN}Nginx 已重新启动${NC}"
            fi
        fi
    fi
}

# 显示证书信息
install_ssltls_text() {
    echo -e "${YELLOW}$yuming 公钥信息${NC}"
    cat /etc/letsencrypt/live/$yuming/fullchain.pem
    echo ""
    echo -e "${YELLOW}$yuming 私钥信息${NC}"
    cat /etc/letsencrypt/live/$yuming/privkey.pem
    echo ""
    echo -e "${YELLOW}证书存放路径${NC}"
    echo "公钥: /etc/letsencrypt/live/$yuming/fullchain.pem"
    echo "私钥: /etc/letsencrypt/live/$yuming/privkey.pem"
    echo ""
}

# 安装 crontab
install_crontab() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|kali)
                apt update
                apt install -y cron
                systemctl enable cron
                systemctl start cron
                ;;
            centos|rhel|almalinux|rocky|fedora)
                yum install -y cronie
                systemctl enable crond
                systemctl start crond
                ;;
            alpine)
                apk add --no-cache cronie
                rc-update add crond
                rc-service crond start
                ;;
            arch|manjaro)
                pacman -S --noconfirm cronie
                systemctl enable cronie
                systemctl start cronie
                ;;
            opensuse|suse|opensuse-tumbleweed)
                zypper install -y cron
                systemctl enable cron
                systemctl start cron
                ;;
            openwrt|lede)
                opkg update
                opkg install cron
                /etc/init.d/cron enable
                /etc/init.d/cron start
                ;;
            *)
                echo "不支持的发行版: $ID"
                return
                ;;
        esac
    else
        echo "无法确定操作系统。"
        return
    fi

    echo -e "${GREEN}crontab 已安装且 cron 服务正在运行。${NC}"
}

# 检查并安装 crontab
check_crontab_installed() {
    if command -v crontab >/dev/null 2>&1; then
        echo -e "${GREEN}crontab 已经安装${NC}"
        return
    else
        echo -e "${YELLOW}正在安装 crontab...${NC}"
        install_crontab
        return
    fi
}

# 设置证书自动续签
setup_cert_renewal() {
    cd ~
    curl -sS -O ${gh_proxy}https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/auto_cert_renewal.sh
    chmod +x auto_cert_renewal.sh

    check_crontab_installed
    local cron_job="5 3 * * * ~/auto_cert_renewal.sh"
    local existing_cron=$(crontab -l 2>/dev/null | grep -F "$cron_job")

    if [ -z "$existing_cron" ]; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        echo -e "${GREEN}证书自动续签任务已添加${NC}"
    else
        echo -e "${YELLOW}证书自动续签任务已存在${NC}"
    fi
}

# 申请证书主函数
add_ssl() {
    yuming="${1:-}"
    if [ -z "$yuming" ]; then
        add_yuming
    fi
    
    # 安装必要组件
    install_dependency
    setup_cert_renewal
    
    # 删除已存在的证书（如果有）
    docker run -it --rm -v /etc/letsencrypt/:/etc/letsencrypt certbot/certbot delete --cert-name "$yuming" -n 2>/dev/null
    
    # 申请新证书
    install_ssltls
    certs_status
    
    # 如果证书申请成功，复制到 Nginx 证书目录
    local cert_path="/etc/letsencrypt/live/$yuming"
    if [ -f "$cert_path/fullchain.pem" ] && [ -f "$cert_path/privkey.pem" ]; then
        echo -e "${YELLOW}正在复制证书到 Nginx 目录...${NC}"
        # 确保目标目录存在
        mkdir -p /etc/nginx/certs
        # 复制证书文件
        cp "$cert_path/fullchain.pem" "/etc/nginx/certs/${yuming}_cert.pem"
        cp "$cert_path/privkey.pem" "/etc/nginx/certs/${yuming}_key.pem"
        # 设置适当的权限
        chmod 644 "/etc/nginx/certs/${yuming}_cert.pem"
        chmod 600 "/etc/nginx/certs/${yuming}_key.pem"
        echo -e "${GREEN}证书已复制到 Nginx 目录${NC}"
    fi
    
    install_ssltls_text
    ssl_ps
    
    echo -e "${GREEN}证书申请完成，已设置自动续签！${NC}"
}

# 获取 IP 地址
ip_address() {
    ipv4_address=$(curl -s ipv4.ip.sb)
    ipv6_address=$(curl -s --max-time 1 ipv6.ip.sb)
}

# 提示用户输入域名
add_yuming() {
    ip_address
    echo -e "先将域名解析到本机IP: ${YELLOW}$ipv4_address  $ipv6_address${NC}"
    read -e -p "请输入你的IP或者解析过的域名: " yuming
}

# 检查证书状态
certs_status() {
    sleep 1
    local file_path="/etc/letsencrypt/live/$yuming/fullchain.pem"
    if [ -f "$file_path" ]; then
        echo -e "${GREEN}域名证书申请成功${NC}"
    else
        echo -e "${RED}注意: ${NC}检测到域名证书申请失败，请检测域名是否正确解析或更换域名重新尝试！"
    fi
}

# 显示已申请证书的到期情况
ssl_ps() {
    echo -e "${YELLOW}已申请的证书到期情况${NC}"
    echo "站点信息                      证书到期时间"
    echo "------------------------"
    for cert_dir in /etc/letsencrypt/live/*; do
        local cert_file="$cert_dir/fullchain.pem"
        if [ -f "$cert_file" ]; then
            local domain=$(basename "$cert_dir")
            local expire_date=$(openssl x509 -noout -enddate -in "$cert_file" | awk -F'=' '{print $2}')
            local formatted_date=$(date -d "$expire_date" '+%Y-%m-%d')
            printf "%-30s%s\n" "$domain" "$formatted_date"
        fi
    done
    echo ""
}

# SSL证书申请函数
ssl_cert_menu() {
    echo "开始SSL证书申请..."
    add_ssl
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# Nginx管理函数
nginx_management() {
    if [ ! -f "install_nginx.sh" ]; then
        echo -e "${YELLOW}正在下载 Nginx 安装脚本...${NC}"
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/install_nginx.sh
        chmod +x install_nginx.sh
    fi
    ./install_nginx.sh
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 显示反向代理菜单
show_proxy_menu() {
    clear_screen
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}             反向代理管理菜单              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 反代 Cloudflare"
    echo -e "${GREEN}2.${NC} 反代源站"
    echo -e "${GREEN}3.${NC} 删除反代"
    echo -e "${GREEN}0.${NC} 返回主菜单"
    echo ""
    echo -e "${BLUE}=================================================${NC}"
}

# 检查证书是否存在
check_cert_exists() {
    local domain=$1
    if [[ -f "/etc/nginx/certs/${domain}_cert.pem" && -f "/etc/nginx/certs/${domain}_key.pem" ]]; then
        return 0
    else
        return 1
    fi
}

# 配置反向代理
setup_proxy() {
    local proxy_type=$1
    local conf_url=""
    
    if [ "$proxy_type" = "cloudflare" ]; then
        conf_url="https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/cf.conf"
    else
        conf_url="https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/fast.conf"
    fi
    
    # 获取域名信息
    read -p "请输入主域名: " main_domain
    read -p "请输入源站域名: " backend_domain
    
    # 检查证书
    if ! check_cert_exists "$main_domain"; then
        echo -e "${RED}错误: 未找到域名 $main_domain 的证书！${NC}"
        echo -e "${YELLOW}请先返回主菜单申请SSL证书。${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return 1
    fi
    
    # 下载配置文件
    echo -e "${YELLOW}正在下载配置文件...${NC}"
    if ! curl -s -o "/etc/nginx/conf.d/$main_domain.conf" "$conf_url"; then
        echo -e "${RED}下载配置文件失败！${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return 1
    fi
    
    # 替换域名
    echo -e "${YELLOW}正在配置反向代理...${NC}"
    sed -i "s/fast.1111.com/$main_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
    sed -i "s/backend.222.com/$backend_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
    
    # 检查配置
    echo -e "${YELLOW}正在检查Nginx配置...${NC}"
    if nginx -t; then
        systemctl restart nginx
        echo -e "${GREEN}反向代理配置成功！${NC}"
        echo -e "${GREEN}已将 $main_domain 反向代理到 $backend_domain${NC}"
        read -n 1 -s -r -p "按任意键继续..."
    else
        echo -e "${RED}Nginx配置检查失败，请检查配置文件！${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return 1
    fi
}

# 列出并删除反向代理
list_and_delete_proxy() {
    clear_screen
    echo -e "${YELLOW}当前配置的反向代理：${NC}"
    echo "------------------------"
    
    # 列出所有反向代理配置（排除default.conf）
    local configs=($(ls /etc/nginx/conf.d/*.conf 2>/dev/null | grep -v 'default.conf'))
    if [ ${#configs[@]} -eq 0 ]; then
        echo -e "${YELLOW}没有找到反向代理配置${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    # 显示所有配置
    for i in "${!configs[@]}"; do
        local conf_name=$(basename "${configs[$i]}")
        echo -e "${GREEN}$((i+1)).${NC} $conf_name"
    done
    echo "------------------------"
    
    # 选择要删除的配置
    read -p "请输入要删除的配置编号（输入 0 取消）: " choice
    if [[ $choice == "0" ]]; then
        return
    fi
    
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -le ${#configs[@]} ]; then
        local selected_conf="${configs[$((choice-1))]}"
        if rm "$selected_conf"; then
            echo -e "${GREEN}配置文件已删除${NC}"
            # 重启 Nginx
            if nginx -t; then
                systemctl restart nginx
                echo -e "${GREEN}Nginx 已重新加载配置${NC}"
            else
                echo -e "${RED}Nginx 配置检查失败，请手动检查配置！${NC}"
            fi
        else
            echo -e "${RED}删除配置文件失败${NC}"
        fi
    else
        echo -e "${RED}无效的选择${NC}"
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}

# 反向代理函数
reverse_proxy() {
    while true; do
        show_proxy_menu
        read -p "请输入选项 [1-4]: " proxy_choice
        case $proxy_choice in
            1)
                setup_proxy "cloudflare"
                ;;
            2)
                setup_proxy "source"
                ;;
            3)
                list_and_delete_proxy
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选项，请重新选择${NC}"
                read -n 1 -s -r -p "按任意键继续..."
                ;;
        esac
    done
}

# 流量监控函数
traffic_monitor() {
    while true; do
        clear_screen
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}             流量监控管理菜单              ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 安装流量监控"
        echo -e "${GREEN}2.${NC} 查看监控状态"
        echo -e "${GREEN}3.${NC} 查看流量情况"
        echo -e "${GREEN}4.${NC} 编辑配置文件"
        echo -e "${GREEN}5.${NC} 重启监控服务"
        echo -e "${GREEN}6.${NC} 停止监控服务"
        echo -e "${GREEN}7.${NC} 卸载监控服务"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        echo -e "${BLUE}=================================================${NC}"

        read -p "请输入选项 [0-7]: " monitor_choice
        case $monitor_choice in
            1)
                if [ -d "/opt/NetMonitor" ] || [ -f "/etc/systemd/system/netmonitor.service" ]; then
                    echo -e "${YELLOW}检测到已安装 NetMonitor，请选择操作：${NC}"
                    echo -e "${GREEN}1.${NC} 删除并重新安装"
                    echo -e "${GREEN}2.${NC} 升级并保留配置文件"
                    echo -e "${GREEN}3.${NC} 退出安装"
                    read -p "请输入选项（1/2/3）：" reinstall_choice
                    case $reinstall_choice in
                        1)
                            systemctl stop netmonitor
                            systemctl disable netmonitor
                            rm -rf /opt/NetMonitor
                            rm -f /etc/systemd/system/netmonitor.service
                            ;;
                        2)
                            systemctl stop netmonitor
                            systemctl disable netmonitor
                            rm -f /opt/NetMonitor/netmonitor
                            ;;
                        3)
                            return
                            ;;
                        *)
                            echo -e "${RED}无效的选项${NC}"
                            return
                            ;;
                    esac
                fi

                # 继续安装流程
                wget -qO- https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/netmonitor.sh -O netmonitor.sh && chmod +x netmonitor.sh && ./netmonitor.sh
                ;;
            2)
                if ! systemctl is-active netmonitor >/dev/null 2>&1; then
                    echo -e "${RED}NetMonitor 服务未运行！${NC}"
                else
                    systemctl status netmonitor | cat
                fi
                ;;
            3)
                if [ -f "/opt/NetMonitor/config.json" ]; then
                    # 检查并安装依赖
                    if ! command -v bc &> /dev/null || ! command -v jq &> /dev/null; then
                        echo -e "${YELLOW}正在安装必要的依赖...${NC}"
                        if command -v apt-get &> /dev/null; then
                            apt-get update
                            apt-get install -y bc jq
                        elif command -v yum &> /dev/null; then
                            yum install -y bc jq
                        else
                            echo -e "${RED}无法安装依赖，请手动安装 bc 和 jq${NC}"
                            return
                        fi
                    fi

                    clear_screen
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${GREEN}             流量监控情况              ${NC}"
                    echo -e "${BLUE}=================================================${NC}"
                    echo ""
                    
                    # 读取JSON文件中的值
                    device=$(jq -r '.device' /opt/NetMonitor/config.json)
                    interface=$(jq -r '.interface' /opt/NetMonitor/config.json)
                    interval=$(jq -r '.interval' /opt/NetMonitor/config.json)
                    start_day=$(jq -r '.start_day' /opt/NetMonitor/config.json)
                    total_receive=$(jq -r '.statistics.total_receive' /opt/NetMonitor/config.json)
                    total_transmit=$(jq -r '.statistics.total_transmit' /opt/NetMonitor/config.json)
                    last_reset=$(jq -r '.statistics.last_reset' /opt/NetMonitor/config.json)
                    category=$(jq -r '.comparison.category' /opt/NetMonitor/config.json)
                    limit=$(jq -r '.comparison.limit' /opt/NetMonitor/config.json)
                    threshold=$(jq -r '.comparison.threshold' /opt/NetMonitor/config.json)
                    ratio=$(jq -r '.comparison.ratio' /opt/NetMonitor/config.json)

                    # 计算总流量（GB）
                    total_receive_gb=$(echo "scale=2; $total_receive/1024/1024/1024" | bc)
                    total_transmit_gb=$(echo "scale=2; $total_transmit/1024/1024/1024" | bc)
                    total_gb=$(echo "scale=2; $total_receive_gb + $total_transmit_gb" | bc)
                    
                    # 计算流量使用百分比
                    usage_percent=$(echo "scale=2; ($total_gb/$limit)*100" | bc)

                    echo -e "${YELLOW}基本信息：${NC}"
                    echo "• 设备名称：$device"
                    echo "• 监控网卡：$interface"
                    echo "• 检查间隔：${interval}秒"
                    echo "• 重置日期：每月${start_day}号"
                    echo "• 上次重置：$last_reset"
                    echo ""
                    echo -e "${YELLOW}流量统计：${NC}"
                    echo "• 接收流量：${total_receive_gb} GB"
                    echo "• 发送流量：${total_transmit_gb} GB"
                    echo "• 总流量：${total_gb} GB"
                    echo ""
                    echo -e "${YELLOW}流量限制：${NC}"
                    echo "• 统计方式：$category"
                    echo "• 月度限额：${limit} GB"
                    echo "• 已使用：${usage_percent}%"
                    echo "• 警告阈值：${threshold}（${limit}GB的${threshold}）"
                    echo "• 关机阈值：${ratio}（${limit}GB的${ratio}）"
                    echo ""
                    echo -e "${BLUE}=================================================${NC}"
                else
                    echo -e "${RED}配置文件不存在！${NC}"
                fi
                ;;
            4)
                if [ -f "/opt/NetMonitor/config.json" ]; then
                    echo -e "${YELLOW}提示：配置文件包含以下重要参数：${NC}"
                    echo -e "1. device: 设备名称"
                    echo -e "2. interface: 网卡名称（使用 ip a 查看）"
                    echo -e "3. start_day: 流量重置日期（1-31）"
                    echo -e "4. category: 统计类型（upload/download/upload+download）"
                    echo -e "5. limit: 月流量限制（GB）"
                    echo -e "6. threshold: 提醒阈值（如：0.85 表示 85%）"
                    echo -e "7. ratio: 自动关机阈值（如：0.95 表示 95%）"
                    echo -e "8. telegram 配置：bot token 和 chat id\n"
                    read -p "按任意键开始编辑配置文件..." -n 1 -r
                    nano /opt/NetMonitor/config.json
                    
                    # 检查配置文件格式是否正确
                    if jq empty /opt/NetMonitor/config.json >/dev/null 2>&1; then
                        echo -e "${GREEN}配置文件格式正确，正在重启服务...${NC}"
                        systemctl restart netmonitor
                        echo -e "${GREEN}服务已重启！${NC}"
                    else
                        echo -e "${RED}配置文件格式错误，请检查JSON格式！${NC}"
                    fi
                else
                    echo -e "${RED}配置文件不存在！${NC}"
                fi
                ;;
            5)
                if systemctl is-active netmonitor >/dev/null 2>&1; then
                    systemctl restart netmonitor
                    echo -e "${GREEN}NetMonitor 服务已重启！${NC}"
                else
                    echo -e "${RED}NetMonitor 服务未运行！${NC}"
                fi
                ;;
            6)
                if systemctl is-active netmonitor >/dev/null 2>&1; then
                    systemctl stop netmonitor
                    echo -e "${GREEN}NetMonitor 服务已停止！${NC}"
                else
                    echo -e "${RED}NetMonitor 服务未运行！${NC}"
                fi
                ;;
            7)
                read -p "确定要卸载 NetMonitor 吗？(y/n): " confirm
                if [ "$confirm" = "y" ]; then
                    systemctl stop netmonitor
                    systemctl disable netmonitor
                    rm -rf /opt/NetMonitor
                    rm -f /etc/systemd/system/netmonitor.service
                    echo -e "${GREEN}NetMonitor 已完全卸载！${NC}"
                fi
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效的选项，请重新选择${NC}"
                ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 设置快捷键函数
setup_shortcut() {
    clear_screen
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}             快捷键设置              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    
    while true; do
        read -e -p "请输入你的快捷按键（输入0退出）: " shortcut_key
        if [ "$shortcut_key" == "0" ]; then
            return
        fi
        
        # 检查是否为空
        if [ -z "$shortcut_key" ]; then
            echo -e "${RED}快捷键不能为空！${NC}"
            continue
        fi
        
        # 删除已存在的快捷方式
        sed -i '/alias .*='\''n'\''$/d' ~/.bashrc
        find /usr/local/bin/ -type l -exec bash -c 'test "$(readlink -f {})" = "/usr/local/bin/k" && rm -f {}' \;
        
        # 创建新的快捷方式
        if ln -s "$(realpath $0)" "/usr/local/bin/$shortcut_key" 2>/dev/null; then
            echo -e "${GREEN}快捷键已设置为: $shortcut_key${NC}"
            echo -e "${YELLOW}请重新打开终端或执行 'source ~/.bashrc' 使设置生效${NC}"
        else
            echo -e "${RED}快捷键设置失败，请检查权限或是否已被占用${NC}"
        fi
        
        read -n 1 -s -r -p "按任意键继续..."
        return
    done
}

# 系统工具集函数
system_tools() {
    if [ ! -f "xttool.sh" ]; then
        echo -e "${YELLOW}正在下载系统工具集脚本...${NC}"
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/xttool.sh
        chmod +x xttool.sh
    fi
    ./xttool.sh
}

# 主程序循环
while true; do
    clear_screen
    show_banner
    show_menu
    
    read -p "请输入选项 [0-7]: " choice
    
    case $choice in
        1)
            ssl_cert_menu
            ;;
        2)
            nginx_management
            ;;
        3)
            reverse_proxy
            ;;
        4)
            traffic_monitor
            ;;
        5)
            docker_management
            ;;
        6)
            setup_shortcut
            ;;
        7)
            system_tools
            ;;
        0)
            clear_screen
            echo -e "${GREEN}感谢使用，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择${NC}"
            read -n 1 -s -r -p "按任意键继续..."
            ;;
    esac
done 