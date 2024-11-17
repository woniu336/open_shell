#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 清屏函数
clear_screen() {
    clear
    echo -e "${BLUE}=== IPTables 规则管理工具 ===${NC}\n"
}

# 绘制表格边框的函数
draw_table_header() {
    echo "┌────┬───────────┬─────────────────┬─────────────────┬────────────┐"
    echo "│ 序号│   链名    │     源地址      │     目标地址    │    端口    │"
    echo "├────┼───────────┼─────────────────┼─────────────────┼────────────┤"
}

draw_table_footer() {
    echo "└────┴───────────┴─────────────────┴─────────────────┴────────────┘"
}

# 获取并显示规则
show_rules() {
    clear_screen
    local rules=$(iptables-save -t nat)
    local rule_number=1
    
    draw_table_header
    
    while IFS= read -r line; do
        if [[ $line == -A* ]]; then
            # 提取规则信息
            chain=$(echo $line | awk '{print $2}')
            source_addr=$(echo $line | grep -o -E 's [0-9./]+' | cut -d' ' -f2)
            dest_addr=$(echo $line | grep -o -E 'd [0-9./]+' | cut -d' ' -f2)
            port=$(echo $line | grep -o -E 'dport [0-9]+' | cut -d' ' -f2)
            
            # 设置默认值
            source_addr=${source_addr:-"*"}
            dest_addr=${dest_addr:-"*"}
            port=${port:-"*"}
            
            # 格式化输出
            printf "│ %-3d│ %-10s│ %-15s│ %-15s│ %-11s│\n" \
                "$rule_number" "$chain" "$source_addr" "$dest_addr" "$port"
            
            # 存储规则用于后续删除
            rules_array[$rule_number]="$line"
            ((rule_number++))
        fi
    done <<< "$rules"
    
    draw_table_footer
}

# 删除规则
delete_rule() {
    echo -e "\n${GREEN}请输入要删除的规则序号 (输入 0 返回主菜单)：${NC}"
    read choice
    
    if [[ "$choice" == "0" ]]; then
        return
    fi
    
    if [[ -n "${rules_array[$choice]}" ]]; then
        local rule="${rules_array[$choice]}"
        local delete_cmd=$(echo "$rule" | sed 's/-A/-D/')
        
        echo -e "${RED}确认删除以下规则？ (y/n)${NC}"
        echo "$rule"
        read confirm
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            iptables -t nat $delete_cmd
            echo -e "${GREEN}规则已删除${NC}"
        else
            echo -e "${BLUE}操作已取消${NC}"
        fi
    else
        echo -e "${RED}无效的规则序号${NC}"
    fi
    
    echo -e "\n${GREEN}按回车键继续...${NC}"
    read
}

# 主菜单
show_menu() {
    while true; do
        clear_screen
        show_rules
        echo -e "\n${GREEN}操作菜单：${NC}"
        echo "1. 刷新规则列表"
        echo "2. 删除规则"
        echo "3. 添加新规则"
        echo "0. 退出"
        
        echo -e "\n${GREEN}请选择操作 [0-3]:${NC}"
        read choice
        
        case $choice in
            1) continue ;;
            2) delete_rule ;;
            3) 
                echo -e "\n${BLUE}请按以下格式输入规则：${NC}"
                echo "本地端口 目标域名/IP 目标端口"
                echo "例如: 8080 example.com 80"
                read local_port target_host target_port
                if [[ -n $local_port && -n $target_host && -n $target_port ]]; then
                    bash /root/port_forward.sh $local_port $target_host $target_port
                    echo -e "${GREEN}规则添加完成，按回车键继续...${NC}"
                    read
                fi
                ;;
            0) exit 0 ;;
            *) 
                echo -e "${RED}无效的选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}此脚本需要root权限运行${NC}"
    exit 1
fi

# 启动主菜单
show_menu