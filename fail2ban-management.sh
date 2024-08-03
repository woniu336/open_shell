#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以root权限运行" 1>&2
   exit 1
fi

# 函数: 检查并安装fail2ban
check_and_install_fail2ban() {
    if ! command -v fail2ban-client &> /dev/null; then
        echo "未检测到 fail2ban。是否安装? (y/n)"
        read -r install_choice
        if [ "$install_choice" = "y" ]; then
            apt-get update && apt-get install -y fail2ban
            if [ $? -ne 0 ]; then
                echo "fail2ban 安装失败。请检查您的网络连接和系统状态。"
                exit 1
            fi
        else
            echo "fail2ban 未安装。退出脚本。"
            exit 1
        fi
    fi
}

# 函数: 确保配置文件存在
ensure_config_file() {
    local file=$1
    local content=$2
    if [ ! -f "$file" ]; then
        echo "创建配置文件: $file"
        echo "$content" > "$file"
    fi
}

# 函数: 显示菜单
show_menu() {
    clear
    echo "服务器防御程序已启动"
    echo "------------------------"
    echo "1. 开启SSH防暴力破解"
    echo "2. 关闭SSH防暴力破解"
    echo "3. 开启网站保护"
    echo "4. 关闭网站保护"
    echo "------------------------"
    echo "5. 查看SSH拦截记录"
    echo "6. 查看网站拦截记录"
    echo "7. 查看防御规则列表"
    echo "8. 查看日志实时监控"
    echo "------------------------"
    echo "9. 配置拦截参数"
    echo "------------------------"
    echo "10. 对接cloudflare防火墙"
    echo "------------------------"
    echo "11. 卸载防御程序"
    echo "------------------------"
    echo "12. 解除被ban的IP"
    echo "------------------------"
    echo "0. 退出"
    echo "------------------------"
}

# 函数: 切换服务状态
toggle_service() {
    local file=$1
    local status=$2
    if [ -f "$file" ]; then
        sed -i "s/enabled = .*/enabled = $status/" "$file"
        echo "更新配置文件: $file"
    else
        echo "警告: 配置文件 $file 不存在。创建新文件。"
        echo "[sshd]
enabled = $status
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5" > "$file"
    fi
    systemctl restart fail2ban
    if [ $? -eq 0 ]; then
        echo "服务状态已更新。"
    else
        echo "更新服务状态失败。请检查fail2ban服务。"
    fi
}

# 函数: 查看状态
view_status() {
    fail2ban-client status "$1"
    echo "按任意键返回..."
    read -n 1 -s -r
}

# 函数: 解封IP
unban_ip() {
    read -p "请输入被ban的IP地址: " banned_ip
    if [[ $banned_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        sudo fail2ban-client unban "$banned_ip"
        echo "IP $banned_ip 已解封"
    else
        echo "无效的IP地址格式"
    fi
    echo "按任意键返回..."
    read -n 1 -s -r
}

# 主程序开始
check_and_install_fail2ban

# 确保必要的配置文件存在
ensure_config_file "/etc/fail2ban/jail.d/sshd.local" "[sshd]
enabled = false
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5"

ensure_config_file "/etc/fail2ban/jail.d/nginx.local" "[nginx-http-auth]
enabled = false
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log"

# 主循环
while true; do
    show_menu
    read -p "请输入你的选择: " choice

    case $choice in
        1) toggle_service "/etc/fail2ban/jail.d/sshd.local" "true" ;;
        2) toggle_service "/etc/fail2ban/jail.d/sshd.local" "false" ;;
        3) toggle_service "/etc/fail2ban/jail.d/nginx.local" "true" ;;
        4) toggle_service "/etc/fail2ban/jail.d/nginx.local" "false" ;;
        5) view_status "sshd" ;;
        6) 
            for service in fail2ban-nginx-cc nginx-bad-request nginx-botsearch nginx-http-auth nginx-limit-req php-url-fopen; do
                view_status "$service"
            done
            ;;
        7) view_status ;;
        8) 
            echo "按Ctrl+C退出日志查看"
            tail -f /var/log/fail2ban.log
            ;;
        9)
            if ! command -v nano &> /dev/null; then
                apt-get install -y nano
            fi
            nano /etc/fail2ban/jail.d/nginx.local
            ;;
        10)
            echo "对接cloudflare防火墙功能尚未实现"
            ;;
        11)
            read -p "确定要卸载fail2ban吗? (y/n) " uninstall_choice
            if [ "$uninstall_choice" = "y" ]; then
                systemctl disable fail2ban
                systemctl stop fail2ban
                apt remove -y --purge fail2ban
                find / -name "fail2ban" -type d -exec rm -rf {} +
                echo "fail2ban已卸载"
            fi
            ;;
        12) unban_ip ;;
        0) echo "退出程序"; exit 0 ;;
        *) echo "无效的选择,请重试。" ;;
    esac

    # 暂停等待用户输入
    [ "$choice" != "8" ] && read -n 1 -s -r -p "按任意键继续..."
done
