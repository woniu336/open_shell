#!/bin/bash
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
TECH_BLUE='\033[38;2;0;255;255m'  # 使用科技蓝替换黄色
NC='\033[0m' # No Color


# 显示菜单的函数
display_menu() {
    clear
    echo -e "\n${TECH_BLUE}============ 监控脚本 ===============${NC}"
    echo "适用：debian/ubuntu"
    echo "教程：https://woniu336.github.io/p/316/"
    echo "提醒：重新添加会清除原有内容"
    echo -e "${TECH_BLUE}======================================${NC}"
	echo ""
    echo "1. 初始化脚本"
    echo "2. 设置 Webhook URL"
    echo "3. 添加需要检查 SSL 证书的域名"
    echo "4. 添加需要被监控的服务器"
    echo "5. 添加需要检查到期的域名"
    echo "6. 添加定时任务"
    echo "7. 删除定时任务"
    echo "0. 退出"
    echo "=================================="
}

# 初始化环境的函数
initialize_environment() {
    echo "正在创建必要文件..."
    mkdir -p /home/domain
    touch /home/domain/warnfile
    touch /home/domain/logssl
    touch /home/domain/serverlog
    touch /home/domain/check_ssl.txt
    sudo apt-get update
	sudo apt-get install whois bc
	pip install requests

    echo "正在下载关键脚本..."
    cd /home/domain
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/domain_expiry_reminder.sh
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/warnsrc.py
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/daily_report.sh
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/check_ssl.sh
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/monitor_server.sh

    echo "正在设置权限..."
    chmod -R 755 /home/domain

    echo "环境初始化完成。"
    read -p "按回车键继续..."
}

# 添加需要检查 SSL 证书的域名
add_ssl_check_domains() {
    echo ""
	echo "提示：输入需要检查 SSL 证书的域名（每行一个/回车换行）"
    echo "-------------------------------------------------------------"    
    > /home/domain/check_ssl.txt  # 清空文件
    while true; do
        read -p "输入域名（或输入 done 结束）: " domain
        if [[ "$domain" == "done" ]]; then
            break
        fi
        if [[ -n "$domain" ]]; then
            echo "$domain" >> /home/domain/check_ssl.txt
            echo "已添加: $domain"
        fi
    done
    
    echo "已添加的域名："
    cat /home/domain/check_ssl.txt
    read -p "按回车键继续..."
}

# 添加需要被监控的服务器
add_monitored_servers() {
    echo "------------------------------------------------------"
    echo "格式为：IP地址 端口 标签"
    echo "例如：8.8.8.8 2233 腾讯云"
    echo "------------------------------------------------------"
    server_array="declare -A TARGET_SERVERS=(\n"
    while true; do
        read -p "输入服务器详情（或输入 done 结束）: " input
        if [[ "$input" == "done" ]]; then
            break
        fi
        if [[ -n "$input" ]]; then
            ip=$(echo $input | awk '{print $1}')
            port=$(echo $input | awk '{print $2}')
            label=$(echo $input | awk '{print $3}')
            if [[ -n "$ip" && -n "$port" && -n "$label" ]]; then
                server_array+="    [\"$ip\"]=\"$port|$label\"\n"
                echo "已添加: $ip:$port:$label"
            else
                echo "输入格式不正确，请重试。"
            fi
        fi
    done
    server_array+=")"
    
    # 替换脚本中的 TARGET_SERVERS 数组
    sed -i '/declare -A TARGET_SERVERS/,/)/c\'"$server_array" /home/domain/monitor_server.sh
    
    echo "已添加的服务器详情："
    grep -oP '(?<=\[")[^"]+(?="\]).*' /home/domain/monitor_server.sh | sed 's/"]="/:/; s/|/:/g'
    read -p "按回车键继续..."
}

# 添加需要检查到期的域名
add_expiry_check_domains() {
    echo ""
	echo "提示：输入需要检查到期的域名（每行一个/回车换行）"
    echo "---------------------------------------------------------"     
    domains=""
    while true; do
        read -p "输入域名（或输入 done 结束）: " domain
        if [[ "$domain" == "done" ]]; then
            break
        fi
        if [[ -n "$domain" ]]; then
            domains+=" $domain"
            echo "已添加: $domain"
        fi
    done
    
    sed -i "s/for line in .*/for line in$domains/" /home/domain/domain_expiry_reminder.sh
    echo "已添加的域名：$domains"
    read -p "按回车键继续..."
}

# 设置 Webhook URL
set_webhook_url() {
    read -p "输入 Webhook URL: " webhook_url
    sed -i "s|TOKEN=\".*\"|TOKEN=\"$webhook_url\"|" /home/domain/check_ssl.sh
    sed -i "s|DINGTALK_WEBHOOK=\".*\"|DINGTALK_WEBHOOK=\"$webhook_url\"|" /home/domain/monitor_server.sh
    sed -i "s|url = '.*'|url = '$webhook_url'|" /home/domain/warnsrc.py
    sed -i "s|DINGTALK_WEBHOOK=\".*\"|DINGTALK_WEBHOOK=\"$webhook_url\"|" /home/domain/daily_report.sh
    echo "Webhook URL 已设置成功。"
    read -p "按回车键继续..."
}

# 添加定时任务的函数
add_cron_jobs() {
    local crontab_list=$(crontab -l 2>/dev/null)

    # 检查并添加任务
    add_cron_job "30 2 */3 * * cd /home/domain && ./domain_expiry_reminder.sh >/dev/null 2>&1" "每 3 天的凌晨 2:30 执行域名到期检测任务"
    add_cron_job "10 3 * * * cd /home/domain && ./check_ssl.sh >/dev/null 2>&1" "每天凌晨 3:10 执行SSL 证书检查任务"
    add_cron_job "*/2 * * * * cd /home/domain && ./monitor_server.sh >/dev/null 2>&1" "每 2 分钟执行服务器监控任务"
    add_cron_job "0 14 * * * cd /home/domain && ./daily_report.sh >/dev/null 2>&1" "每天下午 2 点生成报告发送至钉钉"

    echo "定时任务添加成功。"
    read -p "按回车键继续..."
}

# 辅助函数：检查并添加单个任务
add_cron_job() {
    local job=$1
    local description=$2

    if echo "$crontab_list" | grep -qF "/home/domain"; then
        echo "任务已存在，跳过添加：$description"
    else
        (crontab -l 2>/dev/null; echo "$job") | crontab -
        echo "任务添加成功：$description"
    fi
}

# 删除定时任务的函数
remove_cron_jobs() {
    local crontab_list=$(crontab -l 2>/dev/null)
    local new_crontab=$(echo "$crontab_list" | grep -vF "/home/domain")

    echo "$new_crontab" | crontab -
    echo "包含 '/home/domain' 的定时任务已删除。"
    read -p "按回车键继续..."
}

# 主循环
while true; do
    display_menu
    read -p "请输入您的选择: " choice

    case $choice in
        1) initialize_environment ;;
        2) set_webhook_url ;;
        3) add_ssl_check_domains ;;
        4) add_monitored_servers ;;
        5) add_expiry_check_domains ;;
        6) add_cron_jobs ;;
		7) remove_cron_jobs ;;
        0) echo "正在退出..."; exit 0 ;;
        *) echo "无效选项。请重试。"; read -p "按回车键继续..." ;;
    esac
done