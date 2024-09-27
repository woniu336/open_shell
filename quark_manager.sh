#!/bin/bash

# 颜色定义
CYAN='\033[0;36m'
LIGHT_CYAN='\033[1;36m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 配置文件路径
CONFIG_FILE="/root/quark/quark_config.json"
MOVIE_LIST_FILE="/root/quark/movie_list.txt"
MOVIE_LIST_SCRIPT="/root/quark/movie_list.py"
QUARK_AUTO_SAVE_SCRIPT="/root/quark/quark_auto_save.py"

# 函数: 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}┌────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│       夸克网盘自动追更管理脚本             │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│  教程：https://woniu336.github.io/p/330/   │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────┤${NC}"
    echo -e "${LIGHT_CYAN}│  1.${NC} 更新Cookie                           ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  2.${NC} 添加转存信息                         ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  3.${NC} 测试新添加的转存                     ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  4.${NC} 运行全部转存                         ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  5.${NC} 设置定时转存任务                     ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  6.${NC} 设置钉钉通知                         ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  7.${NC} 删除转存任务                         ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  8.${NC} 检查链接有效性                       ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  9.${NC} 设置脚本启动快捷键                   ${CYAN}│${NC}"
    echo -e "${LIGHT_CYAN}│  0.${NC} 退出                                 ${CYAN}│${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────┘${NC}"
}

# 新增函数：设置脚本启动快捷键
set_shortcut() {
    sed -i '/alias.*quark_manager.sh/d' ~/.bashrc
    read -p "请输入你想要的快捷按键 (例如: Q): " shortcut
    echo "alias $shortcut='bash $PWD/quark_manager.sh'" >> ~/.bashrc
    source ~/.bashrc
    echo -e "${GREEN}快捷键已添加。请重新启动终端，或运行 'source ~/.bashrc' 以使修改生效。${PLAIN}"
    sleep 5
}

# 函数: 更新Cookie
update_cookie() {
    echo -e "${YELLOW}请输入新的Cookie:${NC}"
    read new_cookie
    # 使用jq命令更新JSON配置文件
    jq --arg cookie "$new_cookie" '.cookie = [$cookie]' $CONFIG_FILE > tmp.$$.json && mv tmp.$$.json $CONFIG_FILE
    echo -e "${GREEN}Cookie已更新${NC}"
}

# 函数: 添加转存信息
add_transfer_info() {
    while true; do
        echo -e "${YELLOW}请输入文件名:${NC}"
        read movie_name
        
        echo -e "${YELLOW}请输入转存链接:${NC}"
        read share_url
        
        echo -e "${YELLOW}请输入转存目录 (例如：/电视剧/繁花):${NC}"
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
    while true; do
        clear
        echo -e "${LIGHT_BLUE}======= 定时任务子菜单 =======${NC}"
        echo -e "${BLUE}1.${NC} 设置定时任务"
        echo -e "${BLUE}2.${NC} 删除定时任务"
        echo -e "${BLUE}0.${NC} 返回主菜单"
        echo -e "${LIGHT_BLUE}================================${NC}"
        read -p "请选择操作: " subchoice

        case $subchoice in
            1)
                echo -e "${YELLOW}请输入定时任务表达式 (直接回车使用默认: 0 8,18,21 * * *):${NC}"
                read cron_expression
                if [ -z "$cron_expression" ]; then
                    cron_expression="0 8,18,21 * * *"
                fi
                (crontab -l 2>/dev/null | grep -v "quark_auto_save.py"; echo "$cron_expression python3 $QUARK_AUTO_SAVE_SCRIPT $CONFIG_FILE") | crontab -
                echo -e "${GREEN}定时任务已设置: $cron_expression${NC}"
                ;;
            2)
                crontab -l 2>/dev/null | grep -v "quark_auto_save.py" | crontab -
                echo -e "${GREEN}定时任务已删除${NC}"
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                ;;
        esac
        
        echo -e "${YELLOW}按Enter键继续...${NC}"
        read
    done
}


# 函数: 设置钉钉通知
set_dingtalk_notify() {
    echo -e "${YELLOW}请输入钉钉机器人的token【Webhook地址后面的token】:${NC}"
    read access_token
    echo -e "${YELLOW}请输入钉钉机器人的secret【加签】:${NC}"
    read secret

    # 更新配置文件中的钉钉通知设置
    jq '.push_config.DD_BOT_TOKEN = "'$access_token'" | .push_config.DD_BOT_SECRET = "'$secret'"' $CONFIG_FILE > tmp.$$.json && mv tmp.$$.json $CONFIG_FILE

    echo -e "${GREEN}钉钉通知设置已更新${NC}"
}

# 函数: 删除转存任务
delete_transfer_task() {
    # 从配置文件中获取任务总数
    task_count=$(jq '.tasklist | length' $CONFIG_FILE)
    
    echo -e "${YELLOW}当前共有 $task_count 个转存任务${NC}"
    
    # 显示任务列表
    echo -e "\n${LIGHT_BLUE}============ 转存任务列表 ============${NC}"
    printf "${BLUE}%-6s %-30s${NC}\n" "序号" "文件名"
    echo -e "${LIGHT_BLUE}=======================================${NC}"
    
    for i in $(seq 0 $((task_count-1))); do
        task_name=$(jq -r ".tasklist[$i].taskname" $CONFIG_FILE)
        if [ $((i % 2)) -eq 0 ]; then
            printf "${GREEN}%-6s %-30s${NC}\n" "$((i+1))" "$task_name"
        else
            printf "${YELLOW}%-6s %-30s${NC}\n" "$((i+1))" "$task_name"
        fi
    done
    
    echo -e "${LIGHT_BLUE}=======================================${NC}\n"
    
    echo -e "${YELLOW}请输入要删除的任务序号或文件名:${NC}"
    read input
    
    # 判断输入是序号还是文件名
    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -le "$task_count" ] && [ "$input" -gt 0 ]; then
        # 输入为序号
        index=$((input-1))
        task_name=$(jq -r ".tasklist[$index].taskname" $CONFIG_FILE)
    else
        # 输入为文件名
        task_name=$input
    fi
    
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

# 函数: 检查链接有效性
check_link_validity() {
    echo -e "${YELLOW}正在检查所有转存链接的有效性...${NC}"
    python3 /root/quark/check_quark_links.py "$CONFIG_FILE"
    echo -e "${YELLOW}检查完成。${NC}"
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
        5) set_cron_job ;;
        6) set_dingtalk_notify; wait_for_enter ;;
        7) delete_transfer_task; wait_for_enter ;;
        8) check_link_validity; wait_for_enter ;;
        9) set_shortcut; wait_for_enter ;;
        0) echo -e "${GREEN}退出程序${NC}"; exit 0 ;;
        *) echo -e "${RED}无效的选择,请重新输入${NC}"; wait_for_enter ;;
    esac
done