#!/bin/bash

SCRIPT_URL="https://raw.githubusercontent.com/woniu336/open_shell/main/indexnow-submit-script.sh"
SCRIPT_NAME="indexnow-submit-script.sh"
SEARCH_ENGINE="www.bing.com"

# 下载脚本
download_script() {
    curl -sS -O $SCRIPT_URL && chmod +x $SCRIPT_NAME
}

# 添加任务
add_task() {
    read -p "请输入API密钥: " API_KEY
    read -p "请输入你的网站域名: " SITE_DOMAIN
    read -p "请输入站点地图URL: " SITEMAP_URL
    read -p "请输入定时任务的时间（格式：分 时 * * *，例如：20 5 * * *）: " CRON_TIME

    (crontab -l ; echo "$CRON_TIME cd ~ && ./$SCRIPT_NAME $SEARCH_ENGINE $API_KEY $SITE_DOMAIN $SITEMAP_URL >/dev/null 2>&1") | crontab -
    echo "任务已添加。"
}

# 显示已存在的任务
list_tasks() {
    echo "已存在的任务："
    crontab -l | grep "./$SCRIPT_NAME"
}

# 删除任务
delete_task() {
    list_tasks
    read -p "确认删除以上所有相关任务吗？(y/n): " CONFIRM
    if [[ $CONFIRM == "y" || $CONFIRM == "Y" ]]; then
        crontab -l | grep -v "./$SCRIPT_NAME" | crontab -
        echo "所有相关任务已删除。"
    else
        echo "取消删除任务。"
    fi
}

# 菜单
show_menu() {
    echo "==============================="
    echo "      indexnow 定时任务"
    echo "==============================="
    echo "1. 添加任务"
    echo "2. 删除任务"
    echo "3. 退出"
    echo "==============================="
    read -p "请选择操作: " OPTION

    case $OPTION in
        1)
            download_script
            add_task
            ;;
        2)
            delete_task
            ;;
        3)
            exit 0
            ;;
        *)
            echo "无效的选择，请重新选择。"
            show_menu
            ;;
    esac
}

# 主程序
show_menu