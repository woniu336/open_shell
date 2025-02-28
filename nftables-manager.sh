#!/bin/bash

# 颜色定义
RED='\033[0;31m'          # 错误信息保留红色
GREEN='\033[0;36m'        # 将成功信息改为青色
NC='\033[0m'              # 保持不变
BLUE='\033[0;34m'         # 深蓝色
CYAN='\033[1;36m'         # 亮青色（用于标题和重要信息）
WHITE='\033[1;37m'        # 亮白色（替代黄色）

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 root 权限运行此脚本${NC}"
    exit 1
fi

# 在文件开头的全局变量定义部分添加
RULES_FILE="/etc/nftables.conf"
TEMP_RULES="/tmp/nftables_temp.conf"
SYSCTL_CONF="/etc/sysctl.conf"

# 启用 IP 转发
enable_ip_forward() {
    echo "正在启用 IP 转发..."
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        sysctl -p
    fi
}

# 安装 nftables
install_nftables() {
    echo -n "检查 nftables 安装状态... "
    if command -v nft &> /dev/null; then
        echo -e "${GREEN}已安装${NC}"
        # 检查服务状态
        if systemctl is-active --quiet nftables; then
            echo -e "nftables 服务状态: ${GREEN}运行中${NC}"
        else
            echo -e "nftables 服务状态: ${WHITE}未运行${NC}"
            echo "正在启动 nftables 服务..."
            systemctl start nftables
            systemctl enable nftables
        fi
    else
        echo -e "${WHITE}未安装${NC}"
        echo "正在安装 nftables..."
        if apt update && apt install -y nftables; then
            systemctl enable nftables
            systemctl start nftables
            echo -e "${GREEN}nftables 安装成功！${NC}"
        else
            echo -e "${RED}nftables 安装失败！${NC}"
            exit 1
        fi
    fi
}

# 配置 UFW
configure_ufw() {
    echo -e "${WHITE}配置 UFW 设置...${NC}"
    
    # 确保 UFW 已安装
    if ! command -v ufw &> /dev/null; then
        echo "正在安装 UFW..."
        apt update && apt install -y ufw
    fi
    
    # 配置 UFW 以允许转发
    if [ -f "/etc/default/ufw" ]; then
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    fi
    
    # 启用 UFW
    echo "正在启用 UFW..."
    ufw --force enable
    
    echo -e "${GREEN}UFW 配置完成！${NC}"
}

# 修改 add_forward_rule 函数，移除 UFW 规则添加
add_forward_rule() {
    echo -e "${WHITE}请输入转发规则信息：${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -n "目标服务器 IP: "
    read -r target_ip
    echo -n "本地端口: "
    read -r local_port
    echo -n "目标端口: "
    read -r target_port
    echo -e "${BLUE}----------------------------------------${NC}"

    # 如果配置文件不存在，创建基础配置
    if [ ! -f "$RULES_FILE" ] || ! grep -q "table ip forward2jp" "$RULES_FILE"; then
        cat > "$RULES_FILE" << EOF
#!/usr/sbin/nft -f

flush ruleset

table ip forward2jp {
    chain prerouting {
        type nat hook prerouting priority -100;
    }

    chain postrouting {
        type nat hook postrouting priority 100;
    }
}
EOF
    fi

    # 创建临时文件
    cp "$RULES_FILE" "$TEMP_RULES"

    # 在 prerouting 链的末尾添加新规则
    sed -i "/type nat hook prerouting priority -100;/a\\        tcp dport ${local_port} dnat to ${target_ip}:${target_port}\\n        udp dport ${local_port} dnat to ${target_ip}:${target_port}" "$TEMP_RULES"

    # 确保 postrouting 链中有对应的 masquerade 规则
    if ! grep -q "ip daddr ${target_ip} masquerade" "$TEMP_RULES"; then
        sed -i "/type nat hook postrouting priority 100;/a\\        ip daddr ${target_ip} masquerade" "$TEMP_RULES"
    fi

    # 测试新配置是否有效
    if nft -c -f "$TEMP_RULES"; then
        mv "$TEMP_RULES" "$RULES_FILE"
        nft -f "$RULES_FILE"
        echo -e "${GREEN}转发规则添加成功！${NC}"
    else
        echo -e "${RED}转发规则添加失败！配置无效${NC}"
        rm -f "$TEMP_RULES"
        return 1
    fi
}

# 修改 delete_rules 函数
delete_rules() {
    clear_screen
    echo -e "${CYAN}=== 删除转发规则 ===${NC}\n"
    
    # 获取并显示当前规则
    show_rules
    
    echo -e "\n${WHITE}删除选项：${NC}"
    echo "1. 删除单个转发规则"
    echo "2. 删除所有转发规则"
    echo "3. 返回主菜单"
    
    echo -n -e "\n${WHITE}请选择操作 [1-3]${NC}: "
    read -r delete_choice
    
    case $delete_choice in
        1)
            echo -n -e "\n${WHITE}请输入要删除的规则序号：${NC} "
            read -r rule_number
            if [[ "$rule_number" =~ ^[0-9]+$ ]]; then
                # 获取要删除的规则信息
                rule_info=$(nft list table ip forward2jp | grep 'dnat to' | grep 'tcp' | sed -n "${rule_number}p")
                if [ -n "$rule_info" ]; then
                    # 从规则信息中提取端口和IP
                    local_port=$(echo "$rule_info" | awk '{for(i=1;i<=NF;i++) if($i=="dport") print $(i+1)}' | tr -d ',')
                    target_info=$(echo "$rule_info" | awk '{for(i=1;i<=NF;i++) if($i=="to") print $(i+1)}')
                    
                    # 创建临时文件
                    cp "$RULES_FILE" "$TEMP_RULES"
                    
                    # 删除指定的规则（TCP和UDP）
                    sed -i "/tcp dport ${local_port} dnat to ${target_info}/d" "$TEMP_RULES"
                    sed -i "/udp dport ${local_port} dnat to ${target_info}/d" "$TEMP_RULES"
                    
                    # 检查是否还有其他使用相同目标IP的规则
                    target_ip=$(echo "$target_info" | cut -d: -f1)
                    if ! grep -q "dnat to.*${target_ip}" "$TEMP_RULES"; then
                        # 如果没有，删除对应的 masquerade 规则
                        sed -i "/ip daddr ${target_ip} masquerade/d" "$TEMP_RULES"
                    fi
                    
                    # 应用新配置
                    if nft -c -f "$TEMP_RULES"; then
                        mv "$TEMP_RULES" "$RULES_FILE"
                        nft -f "$RULES_FILE"
                        echo -e "${GREEN}规则删除成功！${NC}"
                    else
                        echo -e "${RED}规则删除失败！配置无效${NC}"
                        rm -f "$TEMP_RULES"
                    fi
                else
                    echo -e "${RED}未找到指定序号的规则${NC}"
                fi
            else
                echo -e "${RED}无效的规则序号${NC}"
            fi
            ;;
        2)
            echo -n "确定要删除所有转发规则吗？(y/n): "
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                # 删除 nftables 规则
                if nft list tables | grep -q "forward2jp"; then
                    nft flush table ip forward2jp
                    nft delete table ip forward2jp
                    rm -f "$RULES_FILE"
                    echo -e "${GREEN}所有转发规则已删除！${NC}"
                else
                    echo -e "${WHITE}没有找到任何 nftables 规则${NC}"
                fi
            else
                echo "取消删除操作"
            fi
            ;;
        3)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            ;;
    esac
}

# 添加清屏函数
clear_screen() {
    clear
    echo -e "${CYAN}┌────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE}          NFTables 转发规则管理器       ${CYAN}│${NC}"
    echo -e "${CYAN}└────────────────────────────────────────┘${NC}"
    echo
}

# 添加新函数
check_ufw_status() {
    if ! ufw status | grep -q "Status: active"; then
        echo -e "${WHITE}检测到 UFW 未启用，正在重新启用...${NC}"
        configure_ufw
    fi
}

# 修改 show_rules 函数
show_rules() {
    echo -e "${BLUE}----------------------------------------${NC}"
    if nft list ruleset | grep -q "table ip forward2jp"; then
        echo -e "${WHITE}当前转发规则：${NC}"
        nft list table ip forward2jp | grep 'dnat to' | grep 'tcp' | awk '
        {
            for(i=1; i<=NF; i++) {
                if($i == "dport") local_port = $(i+1)
                if($i == "to") {
                    split($(i+1), dest, ":")
                    target_ip = dest[1]
                    target_port = dest[2]
                }
            }
            if(local_port && target_ip && target_port) {
                gsub(/,/, "", local_port)
                printf "%d. 本地端口: %s, 目标IP: %s, 目标端口: %s\n", 
                    NR, local_port, target_ip, target_port
            }
        }'
    else
        echo -e "  ${WHITE}当前没有配置任何转发规则${NC}"
    fi
    echo -e "${BLUE}----------------------------------------${NC}"
}

# 添加系统优化函数
optimize_system() {
    echo -e "${WHITE}正在配置系统优化参数...${NC}"
    
    # 创建临时文件
    local tmp_sysctl="/tmp/sysctl_temp.conf"

    # 基础网络优化参数
    cat > "$tmp_sysctl" << EOF
# 启用IP转发
net.ipv4.ip_forward = 1

# BBR优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 内存优化
vm.swappiness = 1

# TCP缓冲区优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 212992 16777216
net.ipv4.tcp_wmem = 4096 212992 16777216

# 连接跟踪优化
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120
EOF

    # 备份和更新sysctl配置
    if [ -f "$SYSCTL_CONF" ]; then
        echo -e "${WHITE}备份原配置文件到 ${SYSCTL_CONF}.bak${NC}"
        cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak"
        echo -e "${WHITE}更新系统配置...${NC}"
        grep -v -F -f <(grep -v '^#' "$tmp_sysctl" | cut -d= -f1 | tr -d ' ') "$SYSCTL_CONF" > "${SYSCTL_CONF}.tmp"
        mv "${SYSCTL_CONF}.tmp" "$SYSCTL_CONF"
    fi

    # 添加新的配置
    echo -e "${WHITE}添加优化参数...${NC}"
    cat "$tmp_sysctl" >> "$SYSCTL_CONF"

    # 应用配置
    echo -e "${WHITE}应用新配置...${NC}"
    if sysctl -p "$SYSCTL_CONF"; then
        echo -e "${GREEN}系统优化参数配置成功！${NC}"
    else
        echo -e "${RED}系统优化参数配置失败！${NC}"
        # 如果失败，恢复备份
        if [ -f "${SYSCTL_CONF}.bak" ]; then
            echo -e "${WHITE}正在恢复原配置...${NC}"
            mv "${SYSCTL_CONF}.bak" "$SYSCTL_CONF"
            sysctl -p "$SYSCTL_CONF"
        fi
    fi

    # 清理临时文件
    rm -f "$tmp_sysctl"
}

# 修改主菜单
main_menu() {
    while true; do
        check_ufw_status
        clear_screen
        echo -e "${CYAN}可用操作：${NC}"
        echo -e "${BLUE}┌────────────────────────────────────────┐${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}1${NC}. 添加转发规则                        ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}2${NC}. 删除转发规则                        ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}3${NC}. 显示当前规则                        ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}4${NC}. 系统性能优化                        ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}0${NC}. 退出程序                            ${BLUE}│${NC}"
        echo -e "${BLUE}└────────────────────────────────────────┘${NC}"
        echo
        echo -n -e "${CYAN}请选择操作 [0-4]${NC}: "
        read -r choice

        case $choice in
            1)
                clear_screen
                echo -e "${CYAN}=== 添加转发规则 ===${NC}\n"
                enable_ip_forward
                install_nftables
                configure_ufw
                add_forward_rule
                echo -e "\n${WHITE}按回车键返回主菜单...${NC}"
                read -r
                ;;
            2)
                delete_rules
                echo -e "\n${WHITE}按回车键返回主菜单...${NC}"
                read -r
                ;;
            3)
                clear_screen
                echo -e "${CYAN}=== 当前转发规则 ===${NC}\n"
                show_rules
                echo -e "\n${WHITE}按回车键返回主菜单...${NC}"
                read -r
                ;;
            4)
                clear_screen
                echo -e "${CYAN}=== 系统性能优化 ===${NC}\n"
                optimize_system
                echo -e "\n${WHITE}按回车键返回主菜单...${NC}"
                read -r
                ;;
            0)
                clear_screen
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}无效的选择，请重试${NC}"
                sleep 1
                ;;
        esac
    done
}

# 运行主菜单
main_menu 