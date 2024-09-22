#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 配置文件路径
CONFIG_FILE="/root/quark/quark_config.json"
MOVIE_LIST_FILE="/root/quark/movie_list.txt"
MOVIE_LIST_SCRIPT="/root/quark/movie_list.py"
QUARK_AUTO_SAVE_SCRIPT="/root/quark/quark_auto_save.py"

# 函数: 显示菜单
show_menu() {
    echo -e "${YELLOW}=== 夸克网盘自动追更管理脚本 ===${NC}"
    echo "1. 更新Cookie"
    echo "2. 添加转存信息"
    echo "3. 测试新添加的转存"
    echo "4. 运行全部转存"
    echo "5. 设置定时转存任务"
    echo "6. 设置钉钉通知"
    echo "7. 删除转存任务"
    echo "0. 退出"
    echo -e "${YELLOW}=================================${NC}"
}

# 函数: 更新Cookie
update_cookie() {
    echo -e "${YELLOW}请输入新的Cookie:${NC}"
    read new_cookie
    sed -i 's/"cookie": \[.*\]/"cookie": ["'"$new_cookie"'"]/' $CONFIG_FILE
    echo -e "${GREEN}Cookie已更新${NC}"
}

# 函数: 添加转存信息
add_transfer_info() {
    while true; do
        echo -e "${YELLOW}请输入文件名:${NC}"
        read movie_name
        
        echo -e "${YELLOW}请输入转存链接:${NC}"
        read share_url
        
        echo -e "${YELLOW}请输入转存目录(提示：目录不能为空):${NC}"
        read save_path
        
        echo -e "${YELLOW}转存子目录,多个以|分隔 (如果不转存,直接按回车):${NC}"
        read sub_dir

        # 构建转存信息字符串
        transfer_info="${movie_name}=${share_url}=${save_path}"
        if [ ! -z "$sub_dir" ]; then
            transfer_info="${transfer_info}=${sub_dir}"
        fi

        # 添加到文件末尾
        echo "$transfer_info" >> $MOVIE_LIST_FILE
        
        echo -e "${GREEN}转存信息已添加到 $MOVIE_LIST_FILE ${NC}"
        
        # 运行 Python 脚本更新 JSON 配置
        python3 $MOVIE_LIST_SCRIPT
        echo -e "${GREEN}JSON 配置已更新${NC}"
        
        echo -e "${YELLOW}是否继续添加? (y/n)${NC}"
        read continue_add
        if [[ $continue_add != "y" ]]; then
            break
        fi
    done
}

# 函数: 测试新添加的转存
test_new_transfer() {
    if [ ! -s "$MOVIE_LIST_FILE" ]; then
        echo -e "${RED}movie_list.txt 为空,没有可测试的转存信息${NC}"
        return
    fi

    last_line=$(tail -n 1 "$MOVIE_LIST_FILE")
    IFS='=' read -ra ADDR <<< "$last_line"
    movie_name=${ADDR[0]}
    
    echo -e "${YELLOW}测试最新添加的转存: $movie_name${NC}"
    
    # 获取tasklist中最后一个任务的索引
    last_index=$(jq '.tasklist | length - 1' "$CONFIG_FILE")
    
    if [ "$last_index" -ge 0 ]; then
        python3 "$QUARK_AUTO_SAVE_SCRIPT" "$CONFIG_FILE" "$last_index"
        echo -e "${GREEN}测试完成${NC}"
    else
        echo -e "${RED}配置文件中没有任务,无法测试${NC}"
    fi
}

# 函数: 运行全部转存
run_all_transfers() {
    echo -e "${YELLOW}运行全部转存任务...${NC}"
    python3 $QUARK_AUTO_SAVE_SCRIPT $CONFIG_FILE
    echo -e "${GREEN}全部转存任务已完成${NC}"
}

# 函数: 设置定时转存任务
set_cron_job() {
    echo -e "${YELLOW}请输入定时任务表达式 (例如: 0 8,18,21 * * * 表示在每天的8点、18点和21点执行):${NC}"
    read cron_expression
    (crontab -l 2>/dev/null; echo "$cron_expression /usr/bin/python3 $QUARK_AUTO_SAVE_SCRIPT $CONFIG_FILE") | crontab -
    echo -e "${GREEN}定时任务已设置${NC}"
}

# 函数: 设置钉钉通知
set_dingtalk_notify() {
    echo -e "${YELLOW}请输入钉钉机器人的token(Webhook地址后面的token):${NC}"
    read access_token
    echo -e "${YELLOW}请输入钉钉机器人的secret(加签):${NC}"
    read secret

    # 更新配置文件中的钉钉通知设置
    jq '.push_config.DD_BOT_TOKEN = "'$access_token'" | .push_config.DD_BOT_SECRET = "'$secret'"' $CONFIG_FILE > tmp.$$.json && mv tmp.$$.json $CONFIG_FILE

    echo -e "${GREEN}钉钉通知设置已更新${NC}"
}

# 函数: 删除转存任务
delete_transfer_task() {
    echo -e "${YELLOW}请输入要删除的任务文件名:${NC}"
    read task_name

    # 从配置文件中删除匹配的任务
    jq '.tasklist = [.tasklist[] | select(.taskname != "'"$task_name"'")]' $CONFIG_FILE > tmp.$$.json && mv tmp.$$.json $CONFIG_FILE

    # 从 movie_list.txt 中删除对应的行
    sed -i "/^$task_name=/d" $MOVIE_LIST_FILE

    # 检查是否成功删除
    if grep -q "$task_name" $CONFIG_FILE; then
        echo -e "${RED}未找到名为 '$task_name' 的任务,删除失败${NC}"
    else
        echo -e "${GREEN}转存任务 '$task_name' 已成功删除${NC}"
    fi
}

# 函数: 等待用户按Enter键
wait_for_enter() {
    echo -e "${YELLOW}按Enter键返回主菜单...${NC}"
    read
}

# 主循环
while true; do
    clear
    show_menu
    read -p "请选择操作: " choice
    case $choice in
        1) update_cookie; wait_for_enter ;;
        2) add_transfer_info; wait_for_enter ;;
        3) test_new_transfer; wait_for_enter ;;
        4) run_all_transfers; wait_for_enter ;;
        5) set_cron_job; wait_for_enter ;;
        6) set_dingtalk_notify; wait_for_enter ;;
        7) delete_transfer_task; wait_for_enter ;;
        0) echo "退出程序"; exit 0 ;;
        *) echo -e "${RED}无效的选择,请重新输入${NC}"; wait_for_enter ;;
    esac
done