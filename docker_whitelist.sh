#!/bin/bash

# Docker端口白名单管理脚本
# 使用ipset和iptables实现IP白名单访问控制

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
IPSET_NAME="allowed_ips"

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须以root权限运行${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查并安装ipset
install_ipset() {
    if ! command -v ipset &> /dev/null; then
        echo -e "${YELLOW}ipset未安装，正在安装...${NC}"
        apt-get update
        apt-get install ipset -y
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}ipset安装成功!${NC}"
        else
            echo -e "${RED}ipset安装失败!${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}ipset已安装${NC}"
    fi
}

# 创建ipset集合
create_ipset() {
    if ipset list "$IPSET_NAME" &> /dev/null; then
        echo -e "${YELLOW}IP集合 $IPSET_NAME 已存在${NC}"
    else
        ipset create "$IPSET_NAME" hash:ip
        echo -e "${GREEN}IP集合 $IPSET_NAME 创建成功!${NC}"
    fi
}

# 添加IP到白名单
add_ip() {
    read -p "请输入要添加的IP地址: " ip
    
    # 验证IP格式
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}错误: IP地址格式不正确${NC}"
        return
    fi
    
    # 检查IP是否已存在
    if ipset test "$IPSET_NAME" "$ip" &> /dev/null; then
        echo -e "${YELLOW}IP $ip 已存在于白名单中${NC}"
        return
    fi
    
    ipset add "$IPSET_NAME" "$ip"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}IP $ip 添加成功!${NC}"
    else
        echo -e "${RED}IP $ip 添加失败!${NC}"
    fi
}

# 删除IP从白名单
delete_ip() {
    read -p "请输入要删除的IP地址: " ip
    
    if ipset test "$IPSET_NAME" "$ip" &> /dev/null; then
        ipset del "$IPSET_NAME" "$ip"
        echo -e "${GREEN}IP $ip 删除成功!${NC}"
    else
        echo -e "${YELLOW}IP $ip 不在白名单中${NC}"
    fi
}

# 查看白名单
list_ips() {
    echo -e "${BLUE}=== 当前白名单IP列表 ===${NC}"
    if ipset list "$IPSET_NAME" &> /dev/null; then
        ipset list "$IPSET_NAME" | grep -E '^[0-9]' | nl
    else
        echo -e "${YELLOW}白名单为空或不存在${NC}"
    fi
}

# 添加端口规则
add_port_rule() {
    read -p "请输入要保护的端口号: " port
    
    # 验证端口号
    if [[ ! $port =~ ^[0-9]+$ ]] || [ $port -lt 1 ] || [ $port -gt 65535 ]; then
        echo -e "${RED}错误: 端口号必须在1-65535之间${NC}"
        return
    fi
    
    # 检查规则是否已存在
    if iptables -C DOCKER-USER -m set --match-set "$IPSET_NAME" src -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        echo -e "${YELLOW}端口 $port 的规则已存在${NC}"
        return
    fi
    
    # 添加允许规则
    iptables -I DOCKER-USER 1 -m set --match-set "$IPSET_NAME" src -p tcp --dport "$port" -j ACCEPT
    # 添加拒绝规则
    iptables -I DOCKER-USER 2 -p tcp --dport "$port" -j DROP
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口 $port 的白名单规则添加成功!${NC}"
        echo -e "${BLUE}提示: 只有白名单中的IP可以访问端口 $port${NC}"
    else
        echo -e "${RED}规则添加失败!${NC}"
    fi
}

# 删除端口规则
delete_port_rule() {
    read -p "请输入要删除保护的端口号: " port
    
    # 删除允许规则
    iptables -D DOCKER-USER -m set --match-set "$IPSET_NAME" src -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    # 删除拒绝规则
    iptables -D DOCKER-USER -p tcp --dport "$port" -j DROP 2>/dev/null
    
    echo -e "${GREEN}端口 $port 的规则已删除${NC}"
}

# 查看当前规则
list_rules() {
    echo -e "${BLUE}=== 当前iptables规则 ===${NC}"
    iptables -L DOCKER-USER -n --line-numbers | grep -E "ACCEPT|DROP"
}

# 保存配置
save_config() {
    echo -e "${YELLOW}正在保存配置...${NC}"
    
    # 保存ipset
    ipset save > /etc/ipset.conf
    
    # 保存iptables
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables.rules
        echo -e "${GREEN}配置已保存到 /etc/ipset.conf 和 /etc/iptables.rules${NC}"
    else
        echo -e "${YELLOW}iptables-save未找到，建议安装iptables-persistent${NC}"
    fi
}

# 恢复配置
restore_config() {
    if [ -f /etc/ipset.conf ]; then
        ipset restore < /etc/ipset.conf
        echo -e "${GREEN}ipset配置已恢复${NC}"
    fi
    
    if [ -f /etc/iptables.rules ]; then
        iptables-restore < /etc/iptables.rules
        echo -e "${GREEN}iptables配置已恢复${NC}"
    fi
}

# 清空所有配置
clear_all() {
    read -p "确认要清空所有白名单和规则吗? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        # 清空iptables规则
        iptables -F DOCKER-USER 2>/dev/null
        # 清空ipset
        ipset flush "$IPSET_NAME" 2>/dev/null
        echo -e "${GREEN}所有配置已清空${NC}"
    else
        echo -e "${YELLOW}操作已取消${NC}"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Docker端口白名单管理工具               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}IP白名单管理:${NC}"
    echo "  1) 添加IP到白名单"
    echo "  2) 从白名单删除IP"
    echo "  3) 查看白名单IP列表"
    echo ""
    echo -e "${GREEN}端口规则管理:${NC}"
    echo "  4) 添加端口保护规则"
    echo "  5) 删除端口保护规则"
    echo "  6) 查看当前规则"
    echo ""
    echo -e "${GREEN}配置管理:${NC}"
    echo "  7) 保存当前配置"
    echo "  8) 恢复保存的配置"
    echo "  9) 清空所有配置"
    echo ""
    echo "  0) 退出"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 主程序
main() {
    check_root
    install_ipset
    create_ipset
    
    while true; do
        show_menu
        read -p "请选择操作 [0-9]: " choice
        echo ""
        
        case $choice in
            1) add_ip ;;
            2) delete_ip ;;
            3) list_ips ;;
            4) add_port_rule ;;
            5) delete_port_rule ;;
            6) list_rules ;;
            7) save_config ;;
            8) restore_config ;;
            9) clear_all ;;
            0) 
                echo -e "${GREEN}感谢使用，再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 运行主程序
main
