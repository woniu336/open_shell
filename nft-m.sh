#!/bin/bash

# ============================================
# nftables 防火墙管理脚本
# 功能：中国IP白名单、黑名单管理、规则查看
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BLACKLIST_FILE="/etc/nftables.d/blacklist.conf"
WHITELIST_FILE="/etc/nftables.d/whitelist.conf"

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 检查 nftables 是否安装
check_nftables() {
    if ! command -v nft &> /dev/null; then
        echo -e "${RED}错误: nftables 未安装${NC}"
        echo "请先安装: apt install nftables 或 yum install nftables"
        exit 1
    fi
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}   nftables 防火墙管理工具${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC}  安装中国 IP 白名单规则"
    echo -e "${GREEN}2.${NC}  查看防火墙状态"
    echo ""
    echo -e "${YELLOW}--- 黑名单管理 ---${NC}"
    echo -e "${GREEN}3.${NC}  添加 IP 到黑名单"
    echo -e "${GREEN}4.${NC}  从黑名单移除 IP"
    echo -e "${GREEN}5.${NC}  查看黑名单"
    echo ""
    echo -e "${YELLOW}--- 白名单管理 ---${NC}"
    echo -e "${GREEN}6.${NC}  手动添加 IP 到白名单"
    echo -e "${GREEN}7.${NC}  从白名单移除 IP"
    echo -e "${GREEN}8.${NC}  放行 Bingbot（必应爬虫）"
    echo ""
    echo -e "${YELLOW}--- IP 查询 ---${NC}"
    echo -e "${GREEN}9.${NC}  检查 IP 是否在白名单"
    echo -e "${GREEN}10.${NC} 统计 IP 段数量"
    echo ""
    echo -e "${YELLOW}--- 系统管理 ---${NC}"
    echo -e "${GREEN}11.${NC} 手动更新中国 IP 段（自动保留黑白名单）"
    echo -e "${GREEN}12.${NC} 查看自动更新任务"
    echo -e "${GREEN}13.${NC} 完全清理防火墙配置"
    echo -e "${GREEN}14.${NC} 删除 nftables 规则"
    echo ""
    echo -e "${RED}0.${NC}  退出"
    echo ""
    echo -ne "${BLUE}请选择操作 [0-14]: ${NC}"
}

# 1. 安装中国 IP 白名单规则
install_china_whitelist() {
    echo -e "${YELLOW}正在下载并安装中国 IP 白名单规则...${NC}"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/nft_cn.sh
    chmod +x nft_cn.sh
    ./nft_cn.sh
    echo -e "${GREEN}✅ 安装完成${NC}"
    read -p "按回车键继续..."
}

# 2. 查看防火墙状态
view_firewall_status() {
    echo -e "${YELLOW}防火墙服务状态:${NC}"
    systemctl status nftables --no-pager
    echo ""
    echo -e "${YELLOW}nftables 表列表:${NC}"
    nft list tables
    read -p "按回车键继续..."
}

# 3. 添加 IP 到黑名单
add_to_blacklist() {
    read -p "请输入要拉黑的 IP 或 IP 段 (例如: 1.2.3.4 或 1.2.3.0/24): " ip
    if [ -z "$ip" ]; then
        echo -e "${RED}错误: IP 不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    mkdir -p /etc/nftables.d
    
    # 添加到黑名单集合
    nft add element inet filter blacklist { $ip } 2>/dev/null || {
        nft add set inet filter blacklist { type ipv4_addr \; flags interval \; }
        nft insert rule inet filter input ip saddr @blacklist drop
        nft add element inet filter blacklist { $ip }
    }
    
    # 保存到文件（去重）
    if ! grep -Fxq "$ip" "$BLACKLIST_FILE" 2>/dev/null; then
        echo "$ip" >> "$BLACKLIST_FILE"
    fi
    echo -e "${GREEN}✅ 已拉黑: $ip${NC}"
    read -p "按回车键继续..."
}

# 4. 从黑名单移除 IP
remove_from_blacklist() {
    read -p "请输入要解除拉黑的 IP 或 IP 段: " ip
    if [ -z "$ip" ]; then
        echo -e "${RED}错误: IP 不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    nft delete element inet filter blacklist { $ip } 2>/dev/null || {
        echo -e "${RED}错误: IP 不在黑名单中${NC}"
        read -p "按回车键继续..."
        return
    }
    
    sed -i "/^$ip$/d" "$BLACKLIST_FILE"
    echo -e "${GREEN}✅ 已解除拉黑: $ip${NC}"
    read -p "按回车键继续..."
}

# 5. 查看黑名单
view_blacklist() {
    echo -e "${YELLOW}=== 当前黑名单 ===${NC}"
    nft list set inet filter blacklist 2>/dev/null || echo "黑名单为空"
    read -p "按回车键继续..."
}

# 6. 手动添加 IP 到白名单
add_to_whitelist() {
    read -p "请输入要添加的 IP 或 IP 段 (例如: 6.6.6.6 或 1.2.3.0/24): " ip
    if [ -z "$ip" ]; then
        echo -e "${RED}错误: IP 不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    mkdir -p /etc/nftables.d
    
    nft add element inet filter china_ipv4 { $ip } 2>/dev/null || {
        echo -e "${RED}错误: 添加失败，请检查 IP 格式${NC}"
        read -p "按回车键继续..."
        return
    }
    
    # 保存到文件（去重）
    if ! grep -Fxq "$ip" "$WHITELIST_FILE" 2>/dev/null; then
        echo "$ip" >> "$WHITELIST_FILE"
    fi
    
    echo -e "${GREEN}✅ 已添加到白名单: $ip${NC}"
    read -p "按回车键继续..."
}

# 7. 从白名单移除 IP
remove_from_whitelist() {
    read -p "请输入要移除的 IP 或 IP 段: " ip
    if [ -z "$ip" ]; then
        echo -e "${RED}错误: IP 不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    nft delete element inet filter china_ipv4 { $ip } 2>/dev/null || {
        echo -e "${RED}错误: IP 不在白名单中${NC}"
        read -p "按回车键继续..."
        return
    }
    
    # 从文件中删除
    sed -i "/^$(echo "$ip" | sed 's/[.[\*^$()+?{|]/\\&/g')$/d" "$WHITELIST_FILE" 2>/dev/null
    
    echo -e "${GREEN}✅ 已从白名单移除: $ip${NC}"
    read -p "按回车键继续..."
}

# 8. 放行 Bingbot
allow_bingbot() {
    echo -e "${YELLOW}正在添加 Bingbot IP 段...${NC}"
    
    mkdir -p /etc/nftables.d
    
    cat > /tmp/bingbot.txt << 'EOF'
157.55.39.0/24
207.46.13.0/24
40.77.167.0/24
13.66.139.0/24
13.66.144.0/24
52.167.144.0/24
13.67.10.16/28
13.69.66.240/28
13.71.172.224/28
139.217.52.0/28
191.233.204.224/28
20.36.108.32/28
20.43.120.16/28
40.79.131.208/28
40.79.186.176/28
52.231.148.0/28
20.79.107.240/28
51.105.67.0/28
20.125.163.80/28
40.77.188.0/22
65.55.210.0/24
199.30.24.0/23
40.77.202.0/24
40.77.139.0/25
20.74.197.0/28
20.15.133.160/27
40.77.177.0/24
40.77.178.0/23
EOF

    {
        echo "add element inet filter china_ipv4 {"
        cat /tmp/bingbot.txt | sed 's/$/,/' | sed '$ s/,$//'
        echo "}"
    } | nft -f - 2>&1 | grep -v "interval overlaps" || echo "Bingbot IP 段添加完成（跳过了已存在的）"

    # 保存到白名单文件（去重）
    while read -r ip; do
        [ -z "$ip" ] && continue
        if ! grep -Fxq "$ip" "$WHITELIST_FILE" 2>/dev/null; then
            echo "$ip" >> "$WHITELIST_FILE"
        fi
    done < /tmp/bingbot.txt

    nft list ruleset > /etc/nftables/nftables.rules 2>/dev/null
    
    echo -e "${GREEN}✅ Bingbot 已放行并保存到白名单文件${NC}"
    read -p "按回车键继续..."
}

# 9. 检查 IP 是否在白名单
check_ip_in_whitelist() {
    read -p "请输入要查询的 IP 或 IP 段 (例如: 190.93.240.0/20): " ip
    if [ -z "$ip" ]; then
        echo -e "${RED}错误: IP 不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo -e "${YELLOW}检查 IPv4 白名单:${NC}"
    nft get element inet filter china_ipv4 { $ip } 2>/dev/null && echo -e "${GREEN}✅ IP 在白名单中${NC}" || echo -e "${RED}❌ IP 不在白名单中${NC}"
    
    read -p "按回车键继续..."
}

# 10. 统计 IP 段数量
count_ip_ranges() {
    echo -e "${YELLOW}统计中...${NC}"
    echo ""
    
    ipv4_count=$(nft list set inet filter china_ipv4 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | wc -l)
    echo -e "${GREEN}中国 IPv4 段数量: $ipv4_count${NC}"
    
    ipv6_count=$(nft list set inet filter china_ipv6 2>/dev/null | grep -oP '([0-9a-f:]+/\d+)' | wc -l)
    echo -e "${GREEN}IPv6 段数量: $ipv6_count${NC}"
    
    read -p "按回车键继续..."
}

# 11. 手动更新中国 IP 段（保留黑白名单）
manual_update() {
    echo -e "${YELLOW}正在更新中国 IP 段...${NC}"
    echo -e "${BLUE}注意: 将自动保留您的黑白名单设置${NC}"
    echo ""
    
    # 备份黑名单
    echo -e "${YELLOW}1. 备份黑名单...${NC}"
    if nft list set inet filter blacklist &>/dev/null; then
        nft list set inet filter blacklist > /tmp/blacklist_backup.nft
        echo -e "${GREEN}   ✓ 黑名单已备份${NC}"
    else
        echo -e "${BLUE}   - 无黑名单需要备份${NC}"
    fi
    
    # 备份手动添加的白名单
    echo -e "${YELLOW}2. 备份手动白名单...${NC}"
    if [ -f "$WHITELIST_FILE" ]; then
        cp "$WHITELIST_FILE" /tmp/whitelist_backup.txt
        echo -e "${GREEN}   ✓ 白名单已备份 ($(wc -l < $WHITELIST_FILE) 条记录)${NC}"
    else
        echo -e "${BLUE}   - 无白名单需要备份${NC}"
    fi
    
    # 执行更新
    echo -e "${YELLOW}3. 更新中国 IP 段...${NC}"
    if [ -f /usr/local/bin/update_china_nftables.sh ]; then
        /usr/local/bin/update_china_nftables.sh
        echo -e "${GREEN}   ✓ IP 段更新完成${NC}"
    else
        echo -e "${RED}   ✗ 更新脚本不存在${NC}"
        echo "   请先安装中国 IP 白名单规则（选项 1）"
        read -p "按回车键继续..."
        return
    fi
    
    # 恢复黑名单
    echo -e "${YELLOW}4. 恢复黑名单...${NC}"
    if [ -f /tmp/blacklist_backup.nft ]; then
        # 重新创建黑名单集合和规则
        nft add set inet filter blacklist { type ipv4_addr \; flags interval \; } 2>/dev/null
        nft insert rule inet filter input ip saddr @blacklist drop 2>/dev/null
        
        # 从备份中提取 IP 并恢复
        if [ -f "$BLACKLIST_FILE" ]; then
            while read -r ip; do
                [ -z "$ip" ] && continue
                nft add element inet filter blacklist { $ip } 2>/dev/null
            done < "$BLACKLIST_FILE"
            echo -e "${GREEN}   ✓ 黑名单已恢复 ($(wc -l < $BLACKLIST_FILE) 条记录)${NC}"
        fi
    fi
    
# 恢复手动添加的白名单
echo -e "${YELLOW}5. 恢复手动白名单...${NC}"
if [ -f /tmp/whitelist_backup.txt ]; then
    while read -r ip; do
        [ -z "$ip" ] && continue
        # 检查是否已存在于 china_ipv4 集合中
        if ! nft get element inet filter china_ipv4 { $ip } &>/dev/null; then
            nft add element inet filter china_ipv4 { $ip } 2>/dev/null
            echo -e "${GREEN}   ✓ 白名单已恢复: $ip${NC}"
        else
            echo -e "${BLUE}   - IP 已存在: $ip${NC}"
        fi
    done < /tmp/whitelist_backup.txt
    echo -e "${GREEN}   ✓ 白名单恢复完成${NC}"
else
    echo -e "${RED}白名单备份文件不存在或为空，请检查备份文件${NC}"
fi

    
    # 保存规则
    nft list ruleset > /etc/nftables/nftables.rules 2>/dev/null
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ 更新完成！黑白名单已完整保留${NC}"
    echo -e "${GREEN}========================================${NC}"
    read -p "按回车键继续..."
}

# 12. 查看自动更新任务
view_cron_jobs() {
    echo -e "${YELLOW}自动更新任务:${NC}"
    crontab -l | grep china || echo "未找到自动更新任务"
    read -p "按回车键继续..."
}

# 13. 完全清理防火墙配置
clean_firewall() {
    echo -e "${RED}警告: 此操作将清空所有防火墙规则！${NC}"
    read -p "确定要继续吗? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return
    fi
    
    echo -e "${YELLOW}正在清理防火墙...${NC}"
    
    systemctl stop iptables ip6tables firewalld ufw 2>/dev/null
    systemctl disable iptables ip6tables firewalld ufw 2>/dev/null
    
    nft flush ruleset
    nft delete table ip filter 2>/dev/null
    nft delete table ip6 filter 2>/dev/null
    nft delete table ip nat 2>/dev/null
    nft delete table ip6 nat 2>/dev/null
    
    systemctl enable nftables
    systemctl restart nftables
    
    echo -e "${GREEN}✅ 防火墙已清理，可以重新运行安装脚本${NC}"
    read -p "按回车键继续..."
}

# 14. 删除 nftables 规则
cleanup_nftables() {
    echo -e "${YELLOW}正在下载并运行清理脚本...${NC}"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/cleanup_nftables.sh
    chmod +x cleanup_nftables.sh
    ./cleanup_nftables.sh
    echo -e "${GREEN}✅ 清理完成${NC}"
    read -p "按回车键继续..."
}

# 主循环
main() {
    check_root
    check_nftables
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) install_china_whitelist ;;
            2) view_firewall_status ;;
            3) add_to_blacklist ;;
            4) remove_from_blacklist ;;
            5) view_blacklist ;;
            6) add_to_whitelist ;;
            7) remove_from_whitelist ;;
            8) allow_bingbot ;;
            9) check_ip_in_whitelist ;;
            10) count_ip_ranges ;;
            11) manual_update ;;
            12) view_cron_jobs ;;
            13) clean_firewall ;;
            14) cleanup_nftables ;;
            0) 
                echo -e "${GREEN}感谢使用！再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main
