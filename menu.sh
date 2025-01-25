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
    echo -e "${GREEN}8.${NC} AMH面板管理"
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

# SSL证书申请函数
ssl_cert_menu() {
    while true; do
        clear_screen
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}             SSL证书管理菜单              ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 申请SSL证书"
        echo -e "${GREEN}2.${NC} 查看证书状态"
        echo -e "${GREEN}3.${NC} 手动续期证书"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        echo -e "${BLUE}=================================================${NC}"

        read -p "请输入选项 [0-3]: " ssl_choice
        case $ssl_choice in
            1)
                if [ -f "certbot-ssl.sh" ]; then
                    echo -e "${GREEN}certbot-ssl.sh 已存在，跳过下载...${NC}"
                    chmod +x certbot-ssl.sh
                else
                    echo -e "${YELLOW}开始下载SSL证书申请脚本...${NC}"
                    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/certbot-ssl.sh
                    chmod +x certbot-ssl.sh
                fi
                ./certbot-ssl.sh
                ;;
            2)
                if [ -d "/etc/letsencrypt/live/" ]; then
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
                else
                    echo -e "${RED}未找到任何SSL证书${NC}"
                fi
                ;;
            3)
                if [ -f "auto_cert_renewal.sh" ]; then
                    echo -e "${GREEN}auto_cert_renewal.sh 已存在，跳过下载...${NC}"
                    chmod +x auto_cert_renewal.sh
                else
                    echo -e "${YELLOW}开始下载证书续期脚本...${NC}"
                    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/auto_cert_renewal.sh
                    chmod +x auto_cert_renewal.sh
                fi
                ./auto_cert_renewal.sh
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
        # 显示源站类型子菜单
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}             选择源站类型              ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 单个源站"
        echo -e "${GREEN}2.${NC} 多个源站"
        echo ""
        echo -e "${BLUE}=================================================${NC}"
        
        read -p "请选择源站类型 [1-2]: " source_type
        case $source_type in
            1)
                conf_url="https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/one.conf"
                ;;
            2)
                conf_url="https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/fast.conf"
                ;;
            *)
                echo -e "${RED}无效的选择！${NC}"
                return 1
                ;;
        esac
    fi
    
    # 获取域名信息
    read -p "请输入主域名: " main_domain
    read -p "请输入源站域名: " backend_domain
    
    # 如果是单个源站，询问是否为https
    if [ "$proxy_type" = "source" ] && [ "$source_type" = "1" ]; then
        read -p "源站是否使用HTTPS? (y/n): " use_https
        local protocol="http"
        if [[ "$use_https" =~ ^[Yy]$ ]]; then
            protocol="https"
        fi
    fi
    
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
    
    if [ "$proxy_type" = "source" ]; then
        if [ "$source_type" = "1" ]; then
            # 单个源站：替换域名和协议
            sed -i "s/fast.1111.com/$main_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
            sed -i "s/backend.222.com/$backend_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
            sed -i "s|set \$upstream_endpoint https://|set \$upstream_endpoint $protocol://|g" "/etc/nginx/conf.d/$main_domain.conf"
        else
            # 多个源站：使用 upstream 方式
            read -p "请输入主源站IP: " primary_ip
            read -p "请输入备用源站IP: " backup_ip
            # 生成唯一的 upstream 名称
            local upstream_name=$(echo "${main_domain}" | sed 's/[^a-zA-Z0-9]/_/g')"_backend"
            # 替换默认的 upstream 块
            sed -i "/upstream.*{/,/}/c\upstream $upstream_name {\n    server $primary_ip:80 weight=1 max_fails=3 fail_timeout=10s;\n    server $backup_ip:80 weight=1 max_fails=3 fail_timeout=10s;\n    keepalive 32;\n}" "/etc/nginx/conf.d/$main_domain.conf"
            # 替换 proxy_pass
            sed -i "s|proxy_pass.*|proxy_pass http://$upstream_name;|" "/etc/nginx/conf.d/$main_domain.conf"
            # 替换域名
            sed -i "s/fast.1111.com/$main_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
            sed -i "s/backend.222.com/$backend_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
        fi
    else
        # Cloudflare 配置
        local upstream_name=$(echo "${main_domain}" | sed 's/[^a-zA-Z0-9]/_/g')"_backend"
        sed -i "s/cloudflare_backend/$upstream_name/g" "/etc/nginx/conf.d/$main_domain.conf"
        sed -i "s/fast.1111.com/$main_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
        sed -i "s/backend.222.com/$backend_domain/g" "/etc/nginx/conf.d/$main_domain.conf"
    fi
    
    # 检查配置
    echo -e "${YELLOW}正在检查Nginx配置...${NC}"
    if nginx -t; then
        # 清理 Nginx 缓存
        rm -rf /usr/local/nginx/cache/proxy/*
        systemctl restart nginx
        echo -e "${GREEN}反向代理配置成功！${NC}"
        if [ "$proxy_type" = "source" ]; then
            if [ "$source_type" = "1" ]; then
                echo -e "${GREEN}已将 $main_domain 反向代理到 $backend_domain${NC}"
            else
                echo -e "${GREEN}已将 $main_domain 反向代理到 $primary_ip 和 $backup_ip${NC}"
            fi
        else
            echo -e "${GREEN}已将 $main_domain 反向代理到 $backend_domain${NC}"
        fi
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
                # 清理 Nginx 缓存
                rm -rf /usr/local/nginx/cache/proxy/*
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

# AMH面板管理函数
amh_panel_management() {
    while true; do
        clear_screen
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}             AMH面板管理菜单              ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 安装AMH面板"
        echo -e "${GREEN}2.${NC} 编译Nginx模块"
        echo -e "${GREEN}3.${NC} 配置环境变量"
        echo -e "${GREEN}4.${NC} 查询Nginx模块"
        echo -e "${GREEN}5.${NC} 配置Nginx设置"
        echo -e "${GREEN}6.${NC} 禁止IP访问"
        echo -e "${GREEN}7.${NC} 卸载AMH面板"
        echo -e "${GREEN}8.${NC} 清理数据库日志"
        echo -e "${GREEN}9.${NC} 站点备份和还原"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        echo -e "${BLUE}=================================================${NC}"

        read -p "请输入选项 [0-9]: " amh_choice
        case $amh_choice in
            1)
                echo -e "${YELLOW}开始安装AMH面板...${NC}"
                wget https://dl.amh.sh/amh.sh && bash amh.sh nginx-generic-1.24,mysql-generic-5.7,php-generic-7.4
                ;;
            2)
                echo -e "${YELLOW}开始编译Nginx模块...${NC}"
                wget http://nginx.org/download/nginx-1.24.0.tar.gz
                tar -zxvf nginx-1.24.0.tar.gz
                cd nginx-1.24.0
                ./configure --prefix=/usr/local/nginx-generic-1.24 --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_gzip_static_module
                make && sudo make install
                amh nginx reload
                echo -e "${GREEN}Nginx模块编译完成！${NC}"
                ;;
            3)
                echo -e "${YELLOW}配置PATH环境变量...${NC}"
                if ! grep -q "export PATH=\$PATH:/usr/local/nginx-generic-1.24/sbin" ~/.bashrc; then
                    echo 'export PATH=$PATH:/usr/local/nginx-generic-1.24/sbin' >> ~/.bashrc
                    source ~/.bashrc
                    echo -e "${GREEN}环境变量配置完成！${NC}"
                else
                    echo -e "${YELLOW}环境变量已经配置过了${NC}"
                fi
                ;;
            4)
                echo -e "${YELLOW}查询Nginx模块状态...${NC}"
                echo -e "\n检查realip模块:"
                nginx -V 2>&1 | grep -i --color=auto "http_realip_module"
                echo -e "\n检查gzip_static模块:"
                nginx -V 2>&1 | grep -o http_gzip_static_module
                ;;
            5)
                echo -e "${YELLOW}配置Nginx设置...${NC}"
                # 检查cf.conf是否存在
                if [ -f "/usr/local/nginx-generic-1.24/conf/cf.conf" ]; then
                    echo -e "${YELLOW}检测到cf.conf已存在，将进行替换...${NC}"
                    rm -f /usr/local/nginx-generic-1.24/conf/cf.conf
                fi
                
                # 创建cf.conf
                cat > /usr/local/nginx-generic-1.24/conf/cf.conf << 'EOF'
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;
real_ip_header CF-Connecting-IP;
real_ip_recursive on;
EOF
                echo -e "${GREEN}cf.conf配置完成！${NC}"
                echo -e "${YELLOW}请手动修改nginx.conf文件...${NC}"
                read -n 1 -s -r -p "按任意键打开nginx.conf进行编辑..."
                nano /usr/local/nginx-generic-1.24/conf/nginx.conf
                
                amh nginx reload
                amh nginx restart
                echo -e "${GREEN}Nginx配置已更新！${NC}"
                ;;
            6)
                echo -e "${YELLOW}配置禁止IP访问...${NC}"
                curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/create_default_config.sh && chmod +x create_default_config.sh && ./create_default_config.sh
                ;;
            7)
                echo -e "${YELLOW}开始卸载AMH面板...${NC}"
                read -p "确定要卸载AMH面板吗？(y/n): " confirm
                if [ "$confirm" = "y" ]; then
                    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/uamh.sh && chmod +x uamh.sh && ./uamh.sh
                else
                    echo -e "${YELLOW}已取消卸载操作${NC}"
                fi
                ;;
            8)
                echo -e "${YELLOW}配置数据库日志清理...${NC}"
                # 获取用户输入的目录
                read -e -p "请输入脚本存放目录(例如/root/test): " script_dir
                if [ -z "$script_dir" ]; then
                    echo -e "${RED}目录不能为空！${NC}"
                    continue
                fi
                
                # 创建目录并设置为可执行目录
                mkdir -p "$script_dir"
                amh amcrontab set_sh "$script_dir"
                
                # 下载清理脚本
                cd "$script_dir"
                wget -O clean_mysql_logs.sh https://raw.githubusercontent.com/woniu336/open_shell/main/clean_mysql_logs.sh
                chmod +x clean_mysql_logs.sh
                
                echo -e "${GREEN}脚本下载完成！${NC}"
                echo -e "${YELLOW}请前往AMH面板后台添加以下命令：${NC}"
                echo -e "${GREEN}amh amcrontab run_sh $script_dir/clean_mysql_logs.sh${NC}"
                echo -e "${YELLOW}提示：在AMH面板 -> 计划任务 中添加上述命令${NC}"
                ;;
            9)
                while true; do
                    clear_screen
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${GREEN}             站点备份和还原              ${NC}"
                    echo -e "${BLUE}=================================================${NC}"
                    echo ""
                    echo -e "${GREEN}1.${NC} 安装配置 rclone"
                    echo -e "${GREEN}2.${NC} 下载备份脚本"
                    echo -e "${GREEN}3.${NC} 修改备份配置"
                    echo -e "${GREEN}4.${NC} 执行备份"
                    echo -e "${GREEN}5.${NC} 执行还原"
                    echo -e "${GREEN}0.${NC} 返回上级菜单"
                    echo ""
                    echo -e "${BLUE}=================================================${NC}"
                    
                    read -p "请输入选项 [0-5]: " backup_choice
                    case $backup_choice in
                        1)
                            echo -e "${YELLOW}开始安装 rclone...${NC}"
                            sudo -v ; curl https://rclone.org/install.sh | sudo bash
                            
                            echo -e "${YELLOW}创建 rclone 配置目录...${NC}"
                            mkdir -p /home/www/.config/rclone/
                            touch /home/www/.config/rclone/rclone.conf
                            
                            echo -e "${YELLOW}请编辑 rclone 配置文件，填入你的 r2 密钥信息...${NC}"
                            echo -e "${GREEN}配置文件模板：${NC}"
                            echo -e "[r2]
type = s3
provider = Cloudflare
access_key_id = xxxx
secret_access_key = xxxx
region = auto
endpoint = https://xxxxxx.r2.cloudflarestorage.com"
                            
                            read -n 1 -s -r -p "按任意键开始编辑配置文件..."
                            nano /home/www/.config/rclone/rclone.conf
                            ;;
                        2)
                            echo -e "${YELLOW}设置可执行目录...${NC}"
                            read -e -p "请输入脚本存放目录(例如/root/test): " script_dir
                            if [ -z "$script_dir" ]; then
                                echo -e "${RED}目录不能为空！${NC}"
                                continue
                            fi
                            
                            mkdir -p "$script_dir"
                            amh amcrontab set_sh "$script_dir"
                            
                            echo -e "${YELLOW}下载备份脚本...${NC}"
                            cd "$script_dir"
                            wget -O backup_amh.sh https://raw.githubusercontent.com/woniu336/open_shell/main/backup_amh.sh
                            wget -O restore_amh.sh https://raw.githubusercontent.com/woniu336/open_shell/main/restore_amh.sh
                            chmod +x backup_amh.sh
                            chmod +x restore_amh.sh
                            echo -e "${GREEN}脚本下载完成！${NC}"
                            ;;
                        3)
                            echo -e "${YELLOW}修改备份配置...${NC}"
                            if [ -f "backup_amh.sh" ]; then
                                nano backup_amh.sh
                                echo -e "${GREEN}备份脚本配置已更新！${NC}"
                            else
                                echo -e "${RED}未找到备份脚本，请先下载脚本！${NC}"
                            fi
                            
                            if [ -f "restore_amh.sh" ]; then
                                nano restore_amh.sh
                                echo -e "${GREEN}还原脚本配置已更新！${NC}"
                            else
                                echo -e "${RED}未找到还原脚本，请先下载脚本！${NC}"
                            fi
                            ;;
                        4)
                            echo -e "${YELLOW}执行备份命令...${NC}"
                            if [ -f "backup_amh.sh" ]; then
                                echo -e "${GREEN}请在AMH面板后台添加以下命令：${NC}"
                                echo -e "${GREEN}amh amcrontab run_sh $(pwd)/backup_amh.sh${NC}"
                                echo -e "${YELLOW}提示：在AMH面板 -> 计划任务 中添加上述命令${NC}"
                            else
                                echo -e "${RED}未找到备份脚本，请先下载并配置脚本！${NC}"
                            fi
                            ;;
                        5)
                            echo -e "${YELLOW}执行还原命令...${NC}"
                            if [ -f "restore_amh.sh" ]; then
                                echo -e "${GREEN}请在AMH面板后台添加以下命令：${NC}"
                                echo -e "${GREEN}amh amcrontab run_sh $(pwd)/restore_amh.sh${NC}"
                                echo -e "${YELLOW}提示：在AMH面板 -> 计划任务 中添加上述命令${NC}"
                            else
                                echo -e "${RED}未找到还原脚本，请先下载并配置脚本！${NC}"
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

# 主程序循环
while true; do
    clear_screen
    show_banner
    show_menu
    
    read -p "请输入选项 [0-8]: " choice
    
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
        8)
            amh_panel_management
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