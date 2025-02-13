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

# 检查必要的命令
check_requirements() {
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}请先安装 curl${NC}"
        exit 1
    fi
}

# 获取 Cloudflare IP 列表
get_cloudflare_ips() {
    local ipv4_list=$(curl -s https://www.cloudflare.com/ips-v4)
    local ipv6_list=$(curl -s https://www.cloudflare.com/ips-v6)
    
    if [ -z "$ipv4_list" ] || [ -z "$ipv6_list" ]; then
        echo -e "${RED}无法获取 Cloudflare IP 列表${NC}"
        return 1
    fi
    
    echo "IPv4_LIST:$ipv4_list"
    echo "IPv6_LIST:$ipv6_list"
}

# 添加Cloudflare规则
add_cloudflare_rules() {
    echo -e "${GREEN}正在添加 Cloudflare IP 规则...${NC}"
    
    # 先移除现有规则
    remove_cloudflare_rules
    
    # 禁止来自 IPv4 的所有 HTTP/S 访问请求
    echo "Setting up IPv4 rules..."
    iptables -I INPUT -p tcp -m multiport --dports 80,443 -j DROP

    # 对 Cloudflare CDN IPv4 地址开放 HTTP/S 入站访问
    for i in `curl -s https://www.cloudflare.com/ips-v4`; do 
        echo "Adding Cloudflare IPv4: $i"
        iptables -I INPUT -s $i -p tcp -m multiport --dport 80,443 -j ACCEPT
    done

    # 禁止来自 IPv6 的所有 HTTP/S 访问请求
    echo "Setting up IPv6 rules..."
    ip6tables -I INPUT -p tcp -m multiport --dports 80,443 -j DROP

    # 对 Cloudflare CDN IPv6 地址开放 HTTP/S 入站访问
    for i in `curl -s https://www.cloudflare.com/ips-v6`; do 
        echo "Adding Cloudflare IPv6: $i"
        ip6tables -I INPUT -s $i -p tcp -m multiport --dport 80,443 -j ACCEPT
    done
    
    # 保存规则
    save_rules
    
    echo -e "${GREEN}Cloudflare 规则添加完成${NC}"
}

# 添加白名单IP
add_whitelist_ip() {
    echo -n "请输入要添加的IP地址 (IPv4 或 IPv6): "
    read ip_address
    
    if [[ $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # IPv4
        iptables -I INPUT 1 -p tcp -s "$ip_address" --match multiport --dports 80,443 -j ACCEPT
        echo -e "${GREEN}已添加IPv4: $ip_address${NC}"
    elif [[ $ip_address =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        # IPv6
        ip6tables -I INPUT 1 -p tcp -s "$ip_address" --match multiport --dports 80,443 -j ACCEPT
        echo -e "${GREEN}已添加IPv6: $ip_address${NC}"
    else
        echo -e "${RED}无效的IP地址格式${NC}"
    fi
    
    save_rules
}

# 删除单个IP规则
delete_ip() {
    echo "当前的IPv4规则："
    iptables -L INPUT -n --line-numbers | grep -E "80,443" | grep "ACCEPT"
    echo -e "\n当前的IPv6规则："
    ip6tables -L INPUT -n --line-numbers | grep -E "80,443" | grep "ACCEPT"
    
    echo -n "请选择规则类型 (4/6): "
    read ip_version
    echo -n "请输入要删除的规则行号: "
    read rule_number
    
    if [[ $rule_number =~ ^[0-9]+$ ]]; then
        if [ "$ip_version" = "4" ]; then
            iptables -D INPUT $rule_number
        elif [ "$ip_version" = "6" ]; then
            ip6tables -D INPUT $rule_number
        else
            echo -e "${RED}无效的版本选择${NC}"
            return 1
        fi
        echo -e "${GREEN}规则已删除${NC}"
        save_rules
    else
        echo -e "${RED}无效的行号${NC}"
    fi
}

# 移除Cloudflare规则
remove_cloudflare_rules() {
    echo -e "${GREEN}正在移除 Cloudflare 规则...${NC}"
    
    # 移除 IPv4 规则
    echo "Removing IPv4 rules..."
    while true; do
        # 获取第一个包含 80,443 的 ACCEPT 规则的行号
        line=$(iptables -L INPUT -n --line-numbers | grep -E "80,443" | grep "ACCEPT" | head -n1 | awk '{print $1}')
        if [ -z "$line" ]; then
            break
        fi
        echo "Removing IPv4 rule at line $line"
        iptables -D INPUT $line
    done
    
    # 移除 IPv6 规则
    echo "Removing IPv6 rules..."
    while true; do
        # 获取第一个包含 80,443 的 ACCEPT 规则的行号
        line=$(ip6tables -L INPUT -n --line-numbers | grep -E "80,443" | grep "ACCEPT" | head -n1 | awk '{print $1}')
        if [ -z "$line" ]; then
            break
        fi
        echo "Removing IPv6 rule at line $line"
        ip6tables -D INPUT $line
    done
    
    # 移除 IPv4 DROP 规则
    iptables -D INPUT -p tcp -m multiport --dports 80,443 -j DROP 2>/dev/null
    
    # 移除 IPv6 DROP 规则
    ip6tables -D INPUT -p tcp -m multiport --dports 80,443 -j DROP 2>/dev/null
    
    # 保存规则
    save_rules
    
    echo -e "${GREEN}Cloudflare 规则已移除${NC}"
}

# 保存规则
save_rules() {
    echo "保存规则..."
    mkdir -p /etc/iptables/
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    echo -e "${GREEN}规则已保存${NC}"
}

# 查看规则
view_rules() {
    echo -e "${GREEN}当前的IPv4规则：${NC}"
    iptables -L INPUT -n --line-numbers | grep -E "80|443"
    echo -e "\n${GREEN}当前的IPv6规则：${NC}"
    ip6tables -L INPUT -n --line-numbers | grep -E "80|443"
}

# 主菜单
show_menu() {
    clear
    echo "==================================="
    echo "     iptables 管理脚本"
    echo "==================================="
    echo "1. 仅允许Cloudflare访问"
    echo "2. 添加IP白名单"
    echo "3. 删除单个IP规则"
    echo "4. 移除Cloudflare规则"
    echo "5. 查看当前规则"
    echo "0. 退出"
    echo "==================================="
    echo -n "请选择操作 [0-5]: "
}

# 主程序
main() {
    check_root
    check_requirements
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) add_cloudflare_rules ;;
            2) add_whitelist_ip ;;
            3) delete_ip ;;
            4) remove_cloudflare_rules ;;
            5) view_rules ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        
        echo
        echo -n "按回车键继续..."
        read
    done
}

main 