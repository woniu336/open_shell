#!/bin/bash

# 钉钉机器人Webhook URL
DINGTALK_WEBHOOK=""

# 通知频率(默认为120秒)
NOTIFICATION_INTERVAL=180

# 设置钉钉 Webhook 函数 (如果还未更新)
set_dingtalk_webhook() {
    read -p "请输入完整的钉钉机器人 Webhook URL: " webhook
    DINGTALK_WEBHOOK=$webhook
    if [ -n "$DINGTALK_WEBHOOK" ]; then
        log_info "钉钉 Webhook 已成功设置为: $DINGTALK_WEBHOOK"
        # 可选: 将 Webhook URL 保存到配置文件中
        echo "DINGTALK_WEBHOOK=$DINGTALK_WEBHOOK" > /etc/fail2ban/dingtalk_config
    else
        log_error "钉钉 Webhook 设置失败。请确保输入了有效的 URL。"
    fi
}

# 设置通知频率函数
set_notification_interval() {
    # 定义颜色
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color

    clear
    echo -e "${BLUE}======================================${NC}"
    echo -e "${GREEN}        通知频率设置${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo
    echo -e "${YELLOW}当前通知频率为:${NC} ${GREEN}$NOTIFICATION_INTERVAL 秒${NC}"
    echo
    echo -e "${YELLOW}要更改通知频率，请按以下步骤操作：${NC}"
    echo
    echo -e "${BLUE}1.${NC} 使用文本编辑器打开此脚本文件"
    echo -e "${BLUE}2.${NC} 找到 ${GREEN}'NOTIFICATION_INTERVAL='${NC} 这一行"
    echo -e "${BLUE}3.${NC} 将其值改为您想要的秒数"
    echo -e "${BLUE}4.${NC} 保存文件并退出编辑器"
    echo -e "${BLUE}5.${NC} 停止通知监控（如果正在运行）"
    echo -e "${BLUE}6.${NC} 重新设置 Webhook"
    echo -e "${BLUE}7.${NC} 启动通知监控"
    echo
    echo -e "${YELLOW}注意：${NC}更改后，新的频率将在下次启动监控时生效"
    echo
    echo -e "${BLUE}======================================${NC}"
}

# 日志函数
log_error() {
    echo "[错误] $1" >&2
    logger -t fail2ban-script "[错误] $1"
}

log_info() {
    echo "[信息] $1"
    logger -t fail2ban-script "[信息] $1"
}


# 安装 Fail2ban 函数
install_fail2ban() {
    log_info "检查 Fail2ban 是否已安装..."
    if ! [ -x "$(command -v fail2ban-client)" ]; then
        log_info "Fail2ban 未安装，是否要安装? (y/n)"
        read -r install_choice
        if [[ $install_choice =~ ^[Yy]$ ]]; then
            log_info "开始安装 Fail2ban..."
            apt update -y && apt install -y fail2ban
            if [ $? -eq 0 ]; then
                log_info "Fail2ban 安装成功"
                systemctl enable fail2ban
                systemctl restart fail2ban
                log_info "Fail2ban 服务已启动并设置为开机自启"
                # 只在首次安装时下载配置文件
                download_files
            else
                log_error "Fail2ban 安装失败，请检查您的系统和网络设置"
                return 1
            fi
        else
            log_info "取消安装 Fail2ban"
            return 1
        fi
    else
        log_info "Fail2ban 已经安装，跳过安装步骤"
    fi
}

# 文件下载函数
download_files() {
    if [ -f "/etc/fail2ban/jail.d/nginx.local" ] && [ -f "/etc/fail2ban/jail.d/sshd.local" ]; then
        log_info "配置文件已存在，跳过下载"
        return 0
    fi

    log_info "检查并下载配置文件..."
    
    # 创建临时目录
    temp_dir=$(mktemp -d)
    
    # 下载文件到临时目录
    cd "$temp_dir"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban-s/fail2ban-nginx-cc.conf > /dev/null 2>&1
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban-s/nginx-bad-request.conf > /dev/null 2>&1
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban-s/nginx.local > /dev/null 2>&1
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban-s/sshd.local > /dev/null 2>&1
    
    # 检查并复制文件
    for file in fail2ban-nginx-cc.conf nginx-bad-request.conf; do
        if [ ! -f "/etc/fail2ban/filter.d/$file" ]; then
            cp "$file" "/etc/fail2ban/filter.d/"
            log_info "已添加 $file 到 /etc/fail2ban/filter.d/"
        else
            log_info "$file 已存在，跳过"
        fi
    done
    
    # 检查并复制 jail 配置文件
    if [ ! -f "/etc/fail2ban/jail.d/nginx.local" ]; then
        cp nginx.local /etc/fail2ban/jail.d/
        log_info "已添加 nginx.local 到 /etc/fail2ban/jail.d/"
    else
        log_info "nginx.local 已存在，跳过"
    fi
    
    if [ ! -f "/etc/fail2ban/jail.d/sshd.local" ]; then
        cp sshd.local /etc/fail2ban/jail.d/
        log_info "已添加 sshd.local 到 /etc/fail2ban/jail.d/"
    else
        log_info "sshd.local 已存在，跳过"
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    log_info "配置文件检查完成"
}

# 卸载函数
uninstall_fail2ban() {
    log_info "开始卸载 Fail2ban..."
    
    log_info "停止 Fail2ban 服务..."
    systemctl stop fail2ban
    systemctl disable fail2ban
    
    log_info "卸载 Fail2ban 软件包..."
    apt remove --purge fail2ban -y
    
    log_info "删除 Fail2ban 相关文件..."
    rm -rf /etc/fail2ban
    rm -rf /var/lib/fail2ban
    rm -f /var/log/fail2ban.log
    
    find / -name "fail2ban" -type d
    
    systemctl daemon-reload
    
    log_info "Fail2ban 已完全卸载和清理。"
}

# 修改特定过滤器的日志路径函数
modify_log_path() {
    read -p "请输入新的日志路径: " new_path

    sed -i '
        /\[fail2ban-nginx-cc\]/,/^$/ s|logpath = .*|logpath = '"$new_path"'|
        /\[nginx-bad-request\]/,/^$/ s|logpath = .*|logpath = '"$new_path"'|
        /\[php-url-fopen\]/,/^$/ s|logpath = .*|logpath = '"$new_path"'|
    ' /etc/fail2ban/jail.d/nginx.local

    systemctl restart fail2ban
    log_info "日志路径已更新为 $new_path"
    log_info "Fail2ban 服务已重启"
}

# 修改: 解析 Fail2ban 状态并格式化输出
parse_fail2ban_status() {
    local filter=$1
    local status_output

    status_output=$(fail2ban-client status "$filter" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "无法获取 $filter 的状态信息"
        return 1
    fi

    local currently_failed=$(echo "$status_output" | grep "Currently failed:" | awk '{print $NF}')
    local total_failed=$(echo "$status_output" | grep "Total failed:" | awk '{print $NF}')
    local currently_banned=$(echo "$status_output" | grep "Currently banned:" | awk '{print $NF}')
    local total_banned=$(echo "$status_output" | grep "Total banned:" | awk '{print $NF}')
    local banned_ip_list=$(echo "$status_output" | grep -oP '(?<=Banned IP list:\s).*' | tr -d '[]')
    local log_path

    if [ "$filter" = "sshd" ]; then
        log_path="/var/log/auth.log"
    else
        log_path=$(grep "\[$filter\]" -A 10 /etc/fail2ban/jail.d/nginx.local | grep "logpath =" | awk -F'=' '{print $2}' | tr -d ' ')
    fi

    echo "过滤器: $filter"
    echo "当前失败次数: ${currently_failed:-0}"
    echo "总失败次数: ${total_failed:-0}"
    echo "当前封禁次数: ${currently_banned:-0}"
    echo "总封禁次数: ${total_banned:-0}"
    echo "日志路径: ${log_path:-未设置}"
    echo "封禁IP列表: ${banned_ip_list:-无}"
}

# 修改: 查看网站拦截记录函数 (现在包括 SSH)
view_website_bans() {
    log_info "正在获取网站和 SSH 拦截记录..."
    echo "----------------------------------------"
    printf "| %-25s | %-10s |\n" "过滤器" "拦截状态"
    echo "----------------------------------------"

    local active_jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/^[^:]+:[ \t]*//' | tr ',' ' ')

    for jail in $active_jails
    do
        local status_output
        status_output=$(fail2ban-client status "$jail" 2>/dev/null)
        if [ $? -ne 0 ]; then
            log_error "无法获取 $jail 的状态信息"
            continue
        fi

        local currently_banned=$(echo "$status_output" | grep "Currently banned:" | awk '{print $NF}')
        currently_banned=${currently_banned:-0}

        local status
        if [ "$currently_banned" -gt "0" ]; then
            status="有拦截"
            printf "| %-25s | %-10s |\n" "$jail" "$status"
            parse_fail2ban_status "$jail"
        else
            status="无拦截"
            printf "| %-25s | %-10s |\n" "$jail" "$status"
        fi
        echo "----------------------------------------"
    done
}

# 修改: 发送钉钉通知函数
send_dingtalk_notification() {
    local filter=$1
    local currently_banned=$2
    local details=$3

    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # 构建消息内容
    local content="Fail2ban 拦截通知 ($timestamp)\n"
    content+="================\n\n"
    content+="$details\n"
    content+="当前封禁 IP 数: $currently_banned"

    # 发送钉钉通知
    curl -s "$DINGTALK_WEBHOOK" \
       -H 'Content-Type: application/json' \
       -d '{
        "msgtype": "text",
        "text": {
            "content": "'"${content}"'"
        }
    }'

    if [ $? -eq 0 ]; then
        log_info "钉钉通知发送成功 (${filter})"
    else
        log_error "钉钉通知发送失败 (${filter})"
    fi
}

# 查看SSH拦截记录函数
view_ssh_bans() {
    echo "----------------------------------------"
    printf "| %-25s | %-10s |\n" "过滤器" "拦截状态"
    echo "----------------------------------------"
    filter="sshd"
    status_output=$(fail2ban-client status $filter 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_error "无法获取 $filter 的状态信息"
        return 1
    fi

    local currently_banned=$(echo "$status_output" | grep "Currently banned:" | awk '{print $NF}')
    currently_banned=${currently_banned:-0}

    local status
    if [ "$currently_banned" -gt "0" ]; then
        status="有拦截"
        printf "| %-25s | %-10s |\n" "$filter" "$status"
        parse_fail2ban_status "$filter"
    else
        status="无拦截"
        printf "| %-25s | %-10s |\n" "$filter" "$status"
    fi
    echo "----------------------------------------"
}

# 修改: 监控和通知函数
monitor_and_notify() {
    while true; do
        for jail in $(fail2ban-client status | grep "Jail list:" | sed -E 's/^[^:]+:[ \t]*//' | tr ',' ' '); do
            status_output=$(fail2ban-client status "$jail" 2>/dev/null)
            currently_banned=$(echo "$status_output" | grep "Currently banned:" | awk '{print $NF}')
            
            if [ "${currently_banned:-0}" -gt "0" ]; then
                details=$(parse_fail2ban_status "$jail")
                send_dingtalk_notification "$jail" "$currently_banned" "$details"
            fi
        done
        sleep $NOTIFICATION_INTERVAL
    done
}


# 默认 SSH 端口
SSH_PORT=22

# 获取当前主机的 IP 地址
HOST_IP=$(hostname -I | awk '{print $1}')


# 新增: 检查 SSH 端口函数
check_ssh_port() {
    # 检查 sshd_config 文件中的 Port 设置
    local config_port=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}')
    if [ ! -z "$config_port" ]; then
        SSH_PORT=$config_port
    fi
    echo -e "${YELLOW}当前 SSH 端口: $SSH_PORT${NC}"
}

# 检查并安装 sshpass
check_and_install_sshpass() {
    if ! command -v sshpass &> /dev/null
    then
        echo -e "${YELLOW}sshpass 未安装，正在尝试安装...${NC}"
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update
            sudo apt-get install -y sshpass
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y sshpass
        elif [ -x "$(command -v brew)" ]; then
            brew install hudochenkov/sshpass/sshpass
        else
            echo -e "${RED}无法确定包管理器，请手动安装 sshpass${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}sshpass 已安装${NC}"
    fi
}

# 测试 SSH Fail2ban 函数
test_ssh_fail2ban() {
    echo -e "${YELLOW}开始测试 SSH Fail2ban 配置...${NC}"
    echo -e "${YELLOW}请确保您已经正确配置了 Fail2ban 并启用了 SSH 防护。${NC}"
    echo

    # 检查并安装 sshpass
    check_and_install_sshpass

    # 1. 检查 Fail2ban 状态
    echo -e "${GREEN}1. 检查 Fail2ban 状态${NC}"
    sudo systemctl is-active fail2ban
    echo

    # 2. 检查 SSH jail 是否启用
    echo -e "${GREEN}2. 检查 SSH jail 是否启用${NC}"
    sudo fail2ban-client status sshd
    echo

    # 3. 模拟 SSH 登录失败
    echo -e "${GREEN}3. 模拟 SSH 登录失败${NC}"
    echo -e "${YELLOW}将尝试使用错误的密码登录 5 次...${NC}"
    for i in {1..5}
    do
        echo -e "${YELLOW}尝试 $i/5${NC}"
        sshpass -p "wrongpassword" ssh -o StrictHostKeyChecking=no -p $SSH_PORT fakeuser@$HOST_IP
    done
    echo

    # 4. 检查 Fail2ban 日志
    echo -e "${GREEN}4. 检查 Fail2ban 日志${NC}"
    sudo tail -n 20 /var/log/fail2ban.log
    echo

    # 5. 再次检查 SSH jail 状态
    echo -e "${GREEN}5. 再次检查 SSH jail 状态${NC}"
    sudo fail2ban-client status sshd
    echo

    echo -e "${YELLOW}测试完成。请检查上面的输出以确认 Fail2ban 是否正确拦截了模拟的攻击。${NC}"
}

# 新增: UFW 管理函数
ufw_management() {
    while true; do
        clear
        echo -e "${BLUE}================================================${NC}"
        echo -e "${YELLOW}              UFW 防火墙管理${NC}"
        echo -e "${BLUE}================================================${NC}"
        echo
        echo -e "${CYAN}1.${NC} 屏蔽 IP"
        echo -e "${CYAN}2.${NC} 解除 IP 屏蔽"
        echo -e "${CYAN}3.${NC} 查看已屏蔽的 IP"
        echo -e "${CYAN}4.${NC} 开启 UFW"
        echo -e "${CYAN}5.${NC} 关闭 UFW"
        echo -e "${CYAN}6.${NC} 查看 UFW 状态"
        echo -e "${CYAN}0.${NC} 返回主菜单"
        echo
        echo -e "${BLUE}================================================${NC}"
        echo
        read -p "$(echo -e ${YELLOW}"请输入你的选择: "${NC})" ufw_choice
        case $ufw_choice in
            1)
                read -p "请输入要屏蔽的 IP 地址: " ip_to_block
                sudo ufw deny from $ip_to_block
                log_info "IP $ip_to_block 已被屏蔽"
                ;;
            2)
                read -p "请输入要解除屏蔽的 IP 地址: " ip_to_unblock
                sudo ufw delete deny from $ip_to_unblock
                log_info "IP $ip_to_unblock 已解除屏蔽"
                ;;
            3)
                echo -e "${YELLOW}已屏蔽的 IP 列表：${NC}"
                sudo ufw status | grep DENY
                ;;
            4)
                sudo ufw enable
                log_info "UFW 已开启"
                ;;
            5)
                sudo ufw disable
                log_info "UFW 已关闭"
                ;;
            6)
                sudo ufw status verbose
                ;;
            0)
                return
                ;;
            *)
                log_error "无效选择，请重试"
                ;;
        esac
        echo
        read -p "$(echo -e ${YELLOW}"按任意键继续..."${NC})"
    done
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color


# 修改: 主菜单函数
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================${NC}"
        echo -e "${YELLOW}          Fail2ban 服务器防御程序${NC}"
        echo -e "${BLUE}================================================${NC}"
        echo
        echo -e "${GREEN}Fail2ban 管理:${NC}"
        echo -e "${CYAN}1.${NC} 安装/重新安装 Fail2ban"
        echo
        echo -e "${GREEN}SSH 防护:${NC}"
        echo -e "${CYAN}2.${NC} 开启 SSH 防暴力破解"
        echo -e "${CYAN}3.${NC} 关闭 SSH 防暴力破解"
        echo -e "${CYAN}4.${NC} 模拟 SSH 登录失败"
        echo
        echo -e "${GREEN}网站防护:${NC}"
        echo -e "${CYAN}5.${NC} 开启网站保护"
        echo -e "${CYAN}6.${NC} 关闭网站保护"
        echo
        echo -e "${GREEN}查看记录:${NC}"
        echo -e "${CYAN}7.${NC} 查看所有拦截记录"
        echo -e "${CYAN}8.${NC} 查看日志实时监控"
        echo
        echo -e "${GREEN}配置选项:${NC}"
        echo -e "${CYAN}9.${NC} 配置拦截参数"
        echo -e "${CYAN}10.${NC} 卸载防御程序"
        echo -e "${CYAN}11.${NC} 解除被 ban 的 IP"
        echo -e "${CYAN}12.${NC} 修改监控日志路径"
        echo
        echo -e "${GREEN}钉钉通知:${NC}"
        echo -e "${CYAN}13.${NC} 钉钉通知设置"
        echo -e "${CYAN}14.${NC} 启动钉钉通知监控"
        echo -e "${CYAN}15.${NC} 停止钉钉通知监控"
        echo
        echo -e "${GREEN}UFW 防火墙:${NC}"
        echo -e "${CYAN}16.${NC} UFW 防火墙管理"
        echo
        echo -e "${RED}0. 退出${NC}"
        echo -e "${BLUE}================================================${NC}"
        echo
        read -p "$(echo -e ${YELLOW}"请输入你的选择: "${NC})" choice
        case $choice in
            1)
                install_fail2ban
                ;;
            2)
                sed -i 's/false/true/g' /etc/fail2ban/jail.d/sshd.local
                systemctl restart fail2ban
                log_info "SSH防暴力破解已开启"
                ;;
            3)
                sed -i 's/true/false/g' /etc/fail2ban/jail.d/sshd.local
                systemctl restart fail2ban
                log_info "SSH防暴力破解已关闭"
                ;;
            4)
                check_ssh_port
                test_ssh_fail2ban
                ;;
            5)
                sed -i 's/false/true/g' /etc/fail2ban/jail.d/nginx.local
                systemctl restart fail2ban
                log_info "网站保护已开启"
                ;;
            6)
                sed -i 's/true/false/g' /etc/fail2ban/jail.d/nginx.local
                systemctl restart fail2ban
                log_info "网站保护已关闭"
                ;;
            7)
                view_website_bans
                ;;
            8)
                tail -f /var/log/fail2ban.log
                ;;
            9)
                nano /etc/fail2ban/jail.d/nginx.local
                systemctl restart fail2ban
                log_info "配置已更新，fail2ban 服务已重启"
                ;;
            10)
                read -p "$(echo -e ${RED}"确定要卸载防御程序吗？此操作将完全移除 Fail2ban (y/n): "${NC})" confirm
                if [ "$confirm" = "y" ]; then
                    uninstall_fail2ban
                else
                    log_info "取消卸载"
                fi
                ;;
            11)
                read -p "请输入被ban的IP地址: " banned_ip
                sudo fail2ban-client unban $banned_ip
                log_info "IP $banned_ip 已解除封禁"
                ;;
            12)
                modify_log_path
                ;;
            13)
                dingtalk_submenu
                ;;
            14)
                if [ -z "$DINGTALK_WEBHOOK" ]; then
                    log_error "请先设置钉钉 Webhook"
                elif [ -f /var/run/fail2ban_monitor.pid ]; then
                    log_info "监控进程已在运行（PID: $(cat /var/run/fail2ban_monitor.pid)）"
                else
                    log_info "启动钉钉通知监控进程..."
                    monitor_and_notify &
                    echo $! > /var/run/fail2ban_monitor.pid
                    log_info "监控进程已在后台启动（PID: $(cat /var/run/fail2ban_monitor.pid)）"
                fi
                ;;
            15)
                if [ -f /var/run/fail2ban_monitor.pid ]; then
                    kill $(cat /var/run/fail2ban_monitor.pid)
                    rm /var/run/fail2ban_monitor.pid
                    log_info "监控进程已停止"
                else
                    log_info "没有正在运行的监控进程"
                fi
                ;;
            16)
                ufw_management
                ;;
            0)
                echo -e "${GREEN}感谢使用 Fail2ban 服务器防御程序，再见！${NC}"
                exit 0
                ;;
            *)
                log_error "无效选择，请重试"
                ;;
        esac
        echo
        read -p "$(echo -e ${YELLOW}"按任意键返回主菜单..."${NC})"
    done
}
# 钉钉通知设置子菜单
dingtalk_submenu() {
    while true; do
        clear
        echo "钉钉通知设置"
        echo "------------------------"
        echo "1. 设置钉钉 Webhook"
        echo "2. 查看/更改通知频率说明"
        echo "3. 返回主菜单"
        echo "------------------------"
        read -p "请输入你的选择: " subchoice
        case $subchoice in
            1)
                set_dingtalk_webhook
                echo "------------------------"
                read -p "按任意键继续..."
                ;;
            2)
                set_notification_interval
                echo "------------------------"
                read -p "按任意键继续..."
                ;;
            3)
                return
                ;;
            *)
                log_error "无效选择，请重试"
                echo "------------------------"
                read -p "按任意键继续..."
                ;;
        esac
    done
}

# 主程序
if [ "$(id -u)" != "0" ]; then
    log_error "错误：此脚本需要 root 权限运行"
    exit 1
fi

install_fail2ban
download_files
main_menu