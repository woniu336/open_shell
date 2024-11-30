#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 备份文件路径
BACKUP_DIR="/root/ufw_backups"
BACKUP_FILE="$BACKUP_DIR/ufw_backup_$(date +%Y%m%d_%H%M%S).rules"

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

# 初始化UFW
init_ufw() {
    # 检查UFW是否已安装
    if ! command -v ufw &> /dev/null; then
        echo -e "${GREEN}UFW未安装，正在安装...${NC}"
        apt update
        apt install -y ufw
        if [ $? -ne 0 ]; then
            echo -e "${RED}UFW安装失败，请检查系统环境后重试。${NC}"
            exit 1
        fi
        echo -e "${GREEN}UFW安装成功。${NC}"
    fi

    # 自动获取SSH端口
    SSH_PORTS=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')

    # 如果未找到自定义端口，则默认使用22
    if [ -z "$SSH_PORTS" ]; then
        SSH_PORTS=22
    fi

    # 允许所有检测到的SSH端口
    for PORT in $SSH_PORTS; do
        sudo ufw allow "$PORT/tcp"
        echo -e "${GREEN}已允许SSH端口: $PORT${NC}"
    done

    # 启用UFW
    sudo ufw --force enable
}

# 备份UFW规则
backup_rules() {
    mkdir -p "$BACKUP_DIR"
    sudo ufw status numbered > "$BACKUP_FILE"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}UFW规则已备份到: $BACKUP_FILE${NC}"
    else
        echo -e "${RED}备份失败${NC}"
    fi
}

# 添加中转IP
add_proxy_ip() {
    echo "请输入需要添加的中转IP："
    read -r proxy_ip
    
    if [[ ! $proxy_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}无效的IP地址格式${NC}"
        return 1
    fi

    # 备份当前规则
    backup_rules

    # 删除现有的80和443端口通用规则
    for rule in $(sudo ufw status numbered | grep -E "80/tcp|443/tcp" | grep "ALLOW" | cut -d"[" -f2 | cut -d"]" -f1 | sort -r); do
        sudo ufw delete $rule
    done

    # 添加新的规则
    sudo ufw allow from "$proxy_ip" to any port 80
    sudo ufw allow from "$proxy_ip" to any port 443

    sudo ufw reload
    echo -e "${GREEN}已添加中转IP: $proxy_ip${NC}"
    sudo ufw status numbered
}

# 恢复规则
restore_rules() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}没有找到备份目录${NC}"
        return 1
    fi

    echo "可用的备份文件："
    ls -1 "$BACKUP_DIR"
    echo "请输入要恢复的备份文件名："
    read -r backup_name

    if [ ! -f "$BACKUP_DIR/$backup_name" ]; then
        echo -e "${RED}备份文件不存在${NC}"
        return 1
    fi

    # 重置UFW规则
    sudo ufw --force reset
    
    # 从备份文件恢复规则
    while IFS= read -r line; do
        if [[ $line =~ \[([0-9]+)\].*ALLOW.*([0-9]+/tcp) ]]; then
            sudo ufw allow "${BASH_REMATCH[2]}"
        fi
    done < "$BACKUP_DIR/$backup_name"

    sudo ufw reload
    echo -e "${GREEN}规则已恢复${NC}"
    sudo ufw status numbered
}

# 删除中转IP
delete_proxy_ip() {
    echo "请输入需要删除的中转IP："
    read -r proxy_ip

    if [[ ! $proxy_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}无效的IP地址格式${NC}"
        return 1
    fi

    # 查找并删除指定IP的规则
    for rule in $(sudo ufw status numbered | grep "$proxy_ip" | cut -d"[" -f2 | cut -d"]" -f1 | sort -r); do
        sudo ufw delete $rule
    done

    sudo ufw reload
    echo -e "${GREEN}已删除中转IP: $proxy_ip的规则${NC}"
    sudo ufw status numbered
}

# 主菜单
show_menu() {
    while true; do
        echo -e "\n${GREEN}=== UFW中转IP管理菜单 ===${NC}"
        echo "1. 添加中转IP"
        echo "2. 恢复原有规则"
        echo "3. 删除中转IP"
        echo "4. 显示当前规则"
        echo "0. 退出"
        
        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1) add_proxy_ip ;;
            2) restore_rules ;;
            3) delete_proxy_ip ;;
            4) sudo ufw status numbered ;;
            0) echo "退出程序"; exit 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
    done
}

# 主程序
check_root
init_ufw
show_menu