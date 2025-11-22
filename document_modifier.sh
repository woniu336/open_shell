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
    echo "4. 添加需要检查到期的域名"
    echo "5. 添加定时任务"
    echo "6. 删除定时任务"
    echo "7. 钉钉通知测试★"
    echo "0. 退出"
    echo "=================================="
}

# 初始化环境的函数
initialize_environment() {
    echo "正在创建必要文件..."
    mkdir -p /home/domain
    touch /home/domain/warnfile
    touch /home/domain/logssl
    touch /home/domain/check_ssl.txt
    touch /home/domain/domains.txt
    sudo apt-get update
	sudo apt-get install whois bc
	pip install requests

    echo "正在下载关键脚本..."
    cd /home/domain
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/domain_expiry_reminder.sh
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/warnsrc.py
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/daily_report.sh
    wget https://raw.githubusercontent.com/woniu336/open_shell/main/check_ssl.sh

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

# 添加需要检查到期的域名 - 修改为生成配置文件
add_expiry_check_domains() {
    echo ""
    echo "提示：输入需要检查到期的域名（每行一个/回车换行）"
    echo "---------------------------------------------------------"
    
    # 清空配置文件
    > /home/domain/domains.txt
    
    # 添加配置文件说明
    cat > /home/domain/domains.txt << 'EOF'
# 域名到期监控配置文件
# 每行一个域名，支持注释（#开头）
# 示例：
# example.com
# test.cc

EOF
    
    # 收集域名
    while true; do
        read -p "输入域名（或输入 done 结束）: " domain
        if [[ "$domain" == "done" ]]; then
            break
        fi
        if [[ -n "$domain" ]]; then
            echo "$domain" >> /home/domain/domains.txt
            echo "已添加: $domain"
        fi
    done
    
    echo ""
    echo "配置文件已生成: /home/domain/domains.txt"
    echo "已添加的域名："
    echo "-------------------------------------"
    grep -v '^#' /home/domain/domains.txt | grep -v '^$'
    echo "-------------------------------------"
    echo ""
    echo "提示：您可以随时编辑 /home/domain/domains.txt 文件来添加、删除或注释域名"
    read -p "按回车键继续..."
}

# 设置 Webhook URL
set_webhook_url() {
    read -p "输入 Webhook URL: " webhook_url
    sed -i "s|TOKEN=\".*\"|TOKEN=\"$webhook_url\"|" /home/domain/check_ssl.sh
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

# 通知测试子菜单
notification_test_menu() {
    local choice
    while true; do
        clear
        echo -e "${TECH_BLUE}========== 通知测试子菜单 ===========${NC}"
        echo "1. 证书到期测试"
        echo "2. 域名到期测试"
        echo "3. 每日报告测试"
        echo "0. 返回主菜单"
        echo "=================================="
        read -p "请选择测试类型: " choice

        case $choice in
            1) ssl_expiry_test ;;
            2) domain_expiry_test ;;
            3) daily_report_test ;;
            0) break ;;
            *) echo "无效选项，请重试。"; read -p "按回车键继续..." ;;
        esac
    done
}

# SSL 证书到期测试
ssl_expiry_test() {
    echo "正在执行 SSL 证书到期测试..."
    cd /home/domain
    # 备份整行原始设置，使用 `sed` 来去除行首行尾的空白字符
    original_line=$(grep 'if \[ $days -lt [0-9]* \];' check_ssl.sh | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    # 提取原始天数
    original_value=$(echo "$original_line" | awk '{print $5}' | tr -d ';')
    echo "原始设置为: $original_value 天"
    # 提示用户输入测试值
    read -p "请输入测试的天数（多少天内到期提醒）: " test_days
    # 修改为测试值
    sed -i "s/if \[ \$days -lt [0-9]* \];/if [ \$days -lt $test_days ];/" check_ssl.sh
    echo "已将设置修改为: $test_days 天"
    # 运行测试
    ./check_ssl.sh
    # 询问用户是否收到通知
    read -p "你是否收到了通知？(y/n): " received_notification
    if [[ $received_notification == "y" ]]; then
        echo "测试成功！"
    else
        echo "测试失败，请检查你的设置。"
    fi
    # 询问是否恢复原始设置
    read -p "是否恢复原始设置？(y/n): " restore_settings
    if [[ $restore_settings == "y" ]]; then
        # 使用 sed 的内联编辑模式来精确替换，避免引入额外的空格
        sed -i "s/^[[:space:]]*if \[ \$days -lt [0-9]* \];.*$/$original_line/" check_ssl.sh
        echo "已恢复原始设置为: $original_value 天"
    else
        echo "保留当前设置为: $test_days 天"
    fi
    read -p "按回车键继续..."
}

# 域名到期测试
domain_expiry_test() {
    echo "正在执行域名到期测试..."
    cd /home/domain
    
    # 检查域名配置文件是否存在
    if [ ! -f /home/domain/domains.txt ]; then
        echo "错误：域名配置文件 /home/domain/domains.txt 不存在"
        echo "请先执行菜单选项 4 添加需要检查到期的域名"
        read -p "按回车键继续..."
        return
    fi
    
    # 检查配置文件是否有有效域名
    if ! grep -v '^[[:space:]]*#' /home/domain/domains.txt | grep -v '^[[:space:]]*$' | grep -q .; then
        echo "错误：域名配置文件中没有有效的域名"
        echo "请先执行菜单选项 4 添加需要检查到期的域名"
        read -p "按回车键继续..."
        return
    fi
    
    # 提取原始天数 - 修复版
    original_value=$(grep '^WARN_DAYS=' domain_expiry_reminder.sh | grep -oE '[0-9]+' | head -1)
    
    # 如果找不到就让用户输入
    if [ -z "$original_value" ]; then
        echo "无法自动检测原始天数"
        read -p "请输入当前配置的告警天数: " original_value
    else
        echo "原始设置为: $original_value 天"
    fi
    
    # 提示用户输入测试值
    read -p "请输入测试的天数（多少天内到期提醒）: " test_days
    
    # 验证输入
    if ! [[ "$test_days" =~ ^[0-9]+$ ]]; then
        echo "错误：请输入有效的数字"
        read -p "按回车键继续..."
        return
    fi
    
    # 创建备份
    cp domain_expiry_reminder.sh domain_expiry_reminder.sh.bak
    
    # 修改 WARN_DAYS 变量（精确匹配，确保等号后有值）
    sed -i "s/^WARN_DAYS=[0-9]*/WARN_DAYS=$test_days/" domain_expiry_reminder.sh
    
    echo "已将设置修改为: $test_days 天"
    
    # 验证修改是否成功
    new_value=$(grep '^WARN_DAYS=' domain_expiry_reminder.sh | grep -oE '[0-9]+')
    if [ "$new_value" = "$test_days" ]; then
        echo "✓ 修改成功，当前值: $new_value"
    else
        echo "✗ 修改失败，恢复备份..."
        mv domain_expiry_reminder.sh.bak domain_expiry_reminder.sh
        read -p "按回车键继续..."
        return
    fi
    
    # 运行测试
    ./domain_expiry_reminder.sh
    
    # 询问用户是否收到通知
    read -p "你是否收到了通知？(y/n): " received_notification
    if [[ $received_notification == "y" ]]; then
        echo "测试成功！"
    else
        echo "测试失败，请检查你的设置。"
    fi
    
    # 询问是否恢复原始设置
    read -p "是否恢复原始设置？(y/n): " restore_settings
    if [[ $restore_settings == "y" ]]; then
        mv domain_expiry_reminder.sh.bak domain_expiry_reminder.sh
        echo "已恢复原始设置为: $original_value 天"
    else
        rm -f domain_expiry_reminder.sh.bak
        echo "保留当前设置为: $test_days 天"
    fi
    read -p "按回车键继续..."
}

# 每日报告测试
daily_report_test() {
    echo "正在执行每日报告测试..."
    cd /home/domain
    ./daily_report.sh
    # 询问用户是否收到每日报告
    read -p "你是否收到了每日报告？(y/n): " received_notification
    if [[ $received_notification == "y" ]]; then
        echo "测试成功！"
    else
        echo "测试失败，请检查你的设置。"
    fi
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
        4) add_expiry_check_domains ;;
        5) add_cron_jobs ;;
        6) remove_cron_jobs ;;
        7) notification_test_menu ;;
        0) echo "正在退出..."; exit 0 ;;
        *) echo "无效选项。请重试。"; read -p "按回车键继续..." ;;
    esac
done
