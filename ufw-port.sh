#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

# 检查UFW是否已启用
check_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo -e "${RED}请先安装 UFW${NC}"
        exit 1
    fi
    
    if [ "$(ufw status | grep -o "inactive")" = "inactive" ]; then
        echo -e "${RED}UFW 未启用，正在启用...${NC}"
        ufw enable
    fi
}

# 添加IP白名单规则
add_whitelist_rule() {
    echo -n "请输入要允许访问的端口号: "
    read port
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}无效的端口号${NC}"
        return 1
    fi
    
    echo -n "请输入要允许的IP地址: "
    read ip_address
    
    # 验证IP地址格式
    if [[ $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ $ip_address =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        # 先添加允许规则
        ufw allow from $ip_address to any port $port proto tcp
        
        # 然后添加默认拒绝规则
        ufw deny $port/tcp
        
        echo -e "${GREEN}已添加规则: 允许 $ip_address 访问端口 $port${NC}"
        
        # 重新加载UFW规则
        ufw reload
    else
        echo -e "${RED}无效的IP地址格式${NC}"
        return 1
    fi
}

# 删除规则
delete_rule() {
    echo "当前的UFW规则："
    ufw status numbered
    
    echo -n "请输入要删除的规则编号: "
    read rule_number
    
    if [[ $rule_number =~ ^[0-9]+$ ]]; then
        echo "y" | ufw delete $rule_number
        echo -e "${GREEN}规则已删除${NC}"
        ufw reload
    else
        echo -e "${RED}无效的规则编号${NC}"
    fi
}

# 查看当前规则
view_rules() {
    echo -e "${GREEN}当前的UFW规则：${NC}"
    ufw status verbose
}

# 清除端口的所有规则
clear_port_rules() {
    echo -n "请输入要清除规则的端口号: "
    read port
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}无效的端口号${NC}"
        return 1
    fi
    
    # 删除该端口的所有规则
    ufw delete deny $port/tcp
    ufw delete allow $port/tcp
    
    # 删除特定IP的规则
    rules=$(ufw status numbered | grep "$port/tcp" | awk '{print $1}' | sed 's/\[//' | sed 's/\]//' | sort -nr)
    for rule in $rules; do
        echo "y" | ufw delete $rule
    done
    
    echo -e "${GREEN}端口 $port 的所有规则已清除${NC}"
    ufw reload
}

# 显示菜单
show_menu() {
    clear
    echo "=================================="
    echo "    UFW端口访问控制管理脚本"
    echo "=================================="
    echo "1. 添加IP白名单规则"
    echo "2. 删除指定规则"
    echo "3. 查看当前规则"
    echo "4. 清除指定端口的所有规则"
    echo "0. 退出"
    echo "=================================="
    echo -n "请选择操作 [0-4]: "
}

# 主程序
main() {
    check_root
    check_ufw
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) add_whitelist_rule ;;
            2) delete_rule ;;
            3) view_rules ;;
            4) clear_port_rules ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        
        echo
        echo -n "按回车键继续..."
        read
    done
}

main 