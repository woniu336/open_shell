#!/bin/bash

###################
# 颜色定义
###################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

###################
# 全局变量
###################
FORWARD_RULES_FILE="/etc/iptables-forward-rules.conf"
BACKUP_DIR="/root/iptables_backups"
BACKUP_FILE="${BACKUP_DIR}/iptables_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
SYSCTL_CONF="/etc/sysctl.conf"

###################
# 辅助函数
###################
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：此脚本需要root权限运行${NC}"
        exit 1
    fi
}

print_banner() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                        IPTables 端口转发管理工具                           ${NC}"
    echo -e "${CYAN}                        作者: 路飞    版本: 3.2                           ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

backup_rules() {
    mkdir -p "$BACKUP_DIR"
    # 创建临时文件保存 iptables 规则
    temp_rules="/tmp/iptables_rules.v4"
    iptables-save > "$temp_rules"

    # 确保转发规则文件存在
    if [ ! -f "$FORWARD_RULES_FILE" ]; then
        touch "$FORWARD_RULES_FILE"
    fi

    # 创建 tar.gz 压缩包，包含 iptables 规则和转发规则文件
    tar -czf "$BACKUP_FILE" -C /tmp iptables_rules.v4 -C /etc iptables-forward-rules.conf

    # 删除临时规则文件
    rm -f "$temp_rules"

    echo -e "${GREEN}规则已备份到: $BACKUP_FILE${NC}"
}

###################
# 功能函数
###################
enable_ip_forward() {
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
        cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak"
        grep -v -F -f <(grep -v '^#' "$tmp_sysctl" | cut -d= -f1 | tr -d ' ') "$SYSCTL_CONF" > "${SYSCTL_CONF}.tmp"
        mv "${SYSCTL_CONF}.tmp" "$SYSCTL_CONF"
    fi

    # 添加新的配置
    cat "$tmp_sysctl" >> "$SYSCTL_CONF"

    # 应用配置
    sysctl -p "$SYSCTL_CONF"

    # 清理临时文件
    rm -f "$tmp_sysctl"

    # 创建开机自启动脚本
    create_startup_script

    echo -e "${GREEN}IP转发已启用、系统参数已优化，并已创建开机自启动脚本${NC}"
}

add_forward_rule() {
    echo -e "${YELLOW}请输入源端口：${NC}"
    read -p "> " src_port

    echo -e "${YELLOW}请输入目标服务器IP：${NC}"
    read -p "> " target_ip

    echo -e "${YELLOW}请输入目标端口：${NC}"
    read -p "> " target_port

    # 输入验证
    if [[ ! $src_port =~ ^[0-9]+$ ]] || [[ ! $target_port =~ ^[0-9]+$ ]] || \
       [[ ! $target_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${RED}无效的输入格式${NC}"
        return 1
    fi

    # 检查端口是否已被使用
    if grep -q "^$src_port " "$FORWARD_RULES_FILE" 2>/dev/null; then
        echo -e "${RED}源端口 $src_port 已被使用${NC}"
        return 1
    fi

    # 添加到配置文件
    mkdir -p "$(dirname "$FORWARD_RULES_FILE")"
    echo "$src_port $target_ip $target_port" >> "$FORWARD_RULES_FILE"

    # 添加iptables规则
    iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${target_ip}:${target_port}"
    iptables -t nat -A POSTROUTING -p tcp -d "${target_ip}" --dport "${target_port}" -j MASQUERADE
    iptables -A FORWARD -p tcp -d "${target_ip}" --dport "${target_port}" -j ACCEPT
    iptables -A FORWARD -p tcp -s "${target_ip}" --sport "${target_port}" -j ACCEPT

    echo -e "${GREEN}转发规则添加成功${NC}"
    
    # 添加规则后立即进行优化
    echo -e "${YELLOW}正在优化转发规则...${NC}"
    optimize_rules
    
    sleep 1
}

delete_forward_rule() {
    if [ ! -f "$FORWARD_RULES_FILE" ]; then
        echo -e "${RED}没有可删除的规则${NC}"
        sleep 1
        return
    fi

    echo -e "${YELLOW}请选择要删除的规则编号：${NC}"
    awk '{printf NR ". %s -> %s:%s\n", $1, $2, $3}' "$FORWARD_RULES_FILE"
    read -p "> " rule_num

    if [[ ! $rule_num =~ ^[0-9]+$ ]]; then
        echo -e "${RED}无效的输入${NC}"
        sleep 1
        return
    fi

    local rule
    rule=$(sed -n "${rule_num}p" "$FORWARD_RULES_FILE")
    if [ -n "$rule" ]; then
        read -r src_port target_ip target_port <<< "$rule"

        # 删除iptables规则
        iptables -t nat -D PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${target_ip}:${target_port}" 2>/dev/null
        iptables -t nat -D POSTROUTING -p tcp -d "${target_ip}" --dport "${target_port}" -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -p tcp -d "${target_ip}" --dport "${target_port}" -j ACCEPT 2>/dev/null
        iptables -D FORWARD -p tcp -s "${target_ip}" --sport "${target_port}" -j ACCEPT 2>/dev/null

        # 从配置文件中删除
        sed -i "${rule_num}d" "$FORWARD_RULES_FILE"

        echo -e "${GREEN}规则已删除${NC}"

        # 删除与目标IP相关的80端口规则
        grep " $target_ip 80$" "$FORWARD_RULES_FILE" > /dev/null
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}检测到与目标IP相关的80端口规则，正在删除...${NC}"
            # 获取所有包含目标IP和80端口的规则编号
            grep -n " $target_ip 80$" "$FORWARD_RULES_FILE" | while IFS=: read -r line_num line_content; do
                src_p=$(echo "$line_content" | awk '{print $1}')
                tgt_ip=$(echo "$line_content" | awk '{print $2}')
                tgt_p=$(echo "$line_content" | awk '{print $3}')

                # 删除iptables规则
                iptables -t nat -D PREROUTING -p tcp --dport "$src_p" -j DNAT --to-destination "${tgt_ip}:${tgt_p}" 2>/dev/null
                iptables -t nat -D POSTROUTING -p tcp -d "${tgt_ip}" --dport "${tgt_p}" -j MASQUERADE 2>/dev/null
                iptables -D FORWARD -p tcp -d "${tgt_ip}" --dport "${tgt_p}" -j ACCEPT 2>/dev/null
                iptables -D FORWARD -p tcp -s "${tgt_ip}" --sport "${tgt_p}" -j ACCEPT 2>/dev/null

                # 从配置文件中删除
                sed -i "${line_num}d" "$FORWARD_RULES_FILE"

                echo -e "${GREEN}关联的80端口规则已删除${NC}"
            done
        fi
    else
        echo -e "${RED}无效的规则编号${NC}"
    fi
    sleep 1
}

save_rules() {
    mkdir -p "$BACKUP_DIR"

    # 创建临时文件保存 iptables 规则
    temp_rules="/tmp/iptables_rules.v4"
    iptables-save > "$temp_rules"

    # 确保转发规则文件存在
    if [ ! -f "$FORWARD_RULES_FILE" ]; then
        touch "$FORWARD_RULES_FILE"
    fi

    # 创建 tar.gz 压缩包，包含 iptables 规则和转发规则文件
    tar -czf "$BACKUP_FILE" -C /tmp iptables_rules.v4 -C /etc iptables-forward-rules.conf

    # 删除临时规则文件
    rm -f "$temp_rules"

    echo -e "${GREEN}规则已备份到: $BACKUP_FILE${NC}"
    sleep 1
}

create_startup_script() {
    # 创建启动脚本目录
    mkdir -p /usr/local/bin

    # 创建启动脚本
    cat > /usr/local/bin/iptables-forward.sh << 'EOF'
#!/bin/bash

# 启用IP转发
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -p

# 恢复转发规则
FORWARD_RULES_FILE="/etc/iptables-forward-rules.conf"
if [ -f "$FORWARD_RULES_FILE" ]; then
    while read -r src_port target_ip target_port; do
        # NAT规则
        iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${target_ip}:${target_port}"
        iptables -t nat -A POSTROUTING -p tcp -d "${target_ip}" --dport "${target_port}" -j MASQUERADE

        # FORWARD规则
        iptables -A FORWARD -p tcp -d "${target_ip}" --dport "${target_port}" -j ACCEPT
        iptables -A FORWARD -p tcp -s "${target_ip}" --sport "${target_port}" -j ACCEPT
    done < "$FORWARD_RULES_FILE"
fi

# 允许已建立的连接
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
EOF

    chmod +x /usr/local/bin/iptables-forward.sh

    # 根据系统类型添加开机启动
    if [ -d /etc/systemd/system ]; then
        # Debian/Ubuntu/CentOS等使用systemd系统
        cat > /etc/systemd/system/iptables-forward.service << EOF
[Unit]
Description=IPTables Forward Rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/iptables-forward.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable iptables-forward.service
        echo -e "${GREEN}已创建并启用systemd服务${NC}"

    elif [ -f /etc/crontab ]; then
        # 其他Linux系统使用crontab
        echo "@reboot root /usr/local/bin/iptables-forward.sh" >> /etc/crontab
        echo -e "${GREEN}已添加到crontab开机任务${NC}"

    else
        # 其他Linux系统
        if [ -f /etc/rc.local ]; then
            sed -i '/exit 0/i\/usr/local/bin/iptables-forward.sh' /etc/rc.local
        else
            cat > /etc/rc.local << EOF
#!/bin/bash
/usr/local/bin/iptables-forward.sh
exit 0
EOF
            chmod +x /etc/rc.local
        fi
        echo -e "${GREEN}已添加到rc.local${NC}"
    fi

    echo -e "${GREEN}开机自启动脚本创建成功！${NC}"
    echo -e "${CYAN}脚本位置：/usr/local/bin/iptables-forward.sh${NC}"
}

restore_rules() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}没有找到备份目录${NC}"
        return
    fi

    echo -e "${YELLOW}可用的备份文件：${NC}"
    ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | nl -w2 -s'. '
    if [ $? -ne 0 ]; then
        echo -e "${RED}没有找到备份文件${NC}"
        sleep 1
        return
    fi
    echo ""
    echo -e "${YELLOW}请选择要恢复的备份文件编号（输入0取消）：${NC}"
    read -p "> " choice

    if [[ $choice == "0" ]]; then
        return
    fi

    selected_file=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | sed -n "${choice}p")
    if [[ -n "$selected_file" && -f "$selected_file" ]]; then
        # 备份当前规则
        backup_rules

        # 创建临时目录解压备份文件
        temp_extract="/tmp/iptables_restore_$(date +%s)"
        mkdir -p "$temp_extract"
        tar -xzf "$selected_file" -C "$temp_extract"

        # 恢复 iptables 规则
        if [ -f "$temp_extract/iptables_rules.v4" ]; then
            iptables-restore < "$temp_extract/iptables_rules.v4"
        fi

        # 恢复转发规则文件
        if [ -f "$temp_extract/iptables-forward-rules.conf" ]; then
            cp "$temp_extract/iptables-forward-rules.conf" "$FORWARD_RULES_FILE"
        fi

        # 清理临时目录
        rm -rf "$temp_extract"

        echo -e "${GREEN}规则已恢复自: $selected_file${NC}"
    else
        echo -e "${RED}无效的选择${NC}"
    fi
    sleep 1
}

optimize_rules() {
    echo -e "${YELLOW}开始优化规则...${NC}"
    
    # 1. 保存当前所有目标IP
    local target_ips=()
    if [ -f "$FORWARD_RULES_FILE" ]; then
        target_ips=($(awk '{print $2}' "$FORWARD_RULES_FILE" | sort -u))
    fi

    for target_ip in "${target_ips[@]}"; do
        echo -e "${CYAN}正在优化 ${target_ip} 相关规则...${NC}"
        
        # 2. 删除重复的单端口FORWARD规则
        iptables -D FORWARD -p tcp -d "${target_ip}" --dport 443 -j ACCEPT 2>/dev/null
        iptables -D FORWARD -p tcp -s "${target_ip}" --sport 443 -j ACCEPT 2>/dev/null
        
        # 3. 确保只有一条multiport规则
        iptables -D FORWARD -p tcp -d "${target_ip}" -m multiport --dports 80,443 -j ACCEPT 2>/dev/null
        iptables -D FORWARD -p tcp -s "${target_ip}" -m multiport --sports 80,443 -j ACCEPT 2>/dev/null
        
        # 4. 添加优化后的规则
        iptables -A FORWARD -p tcp -d "${target_ip}" -m multiport --dports 80,443 -j ACCEPT
        iptables -A FORWARD -p tcp -s "${target_ip}" -m multiport --sports 80,443 -j ACCEPT
        
        # 5. 优化NAT规则
        # 删除多余的MASQUERADE规则
        iptables -t nat -D POSTROUTING -p tcp -d "${target_ip}" --dport 443 -j MASQUERADE 2>/dev/null
        
        # 确保SNAT规则正确（如果存在）
        local public_ip=$(curl -s ifconfig.me)
        if [ -n "$public_ip" ]; then
            iptables -t nat -D POSTROUTING -p tcp -d "${target_ip}" -j SNAT --to-source "$public_ip" 2>/dev/null
            iptables -t nat -A POSTROUTING -p tcp -d "${target_ip}" -j SNAT --to-source "$public_ip"
        fi
    done
    
    echo -e "${GREEN}规则优化完成！${NC}"
    
    # 显示优化后的规则
    echo -e "\n${CYAN}优化后的规则：${NC}"
    check_forward_status
}

check_forward_status() {
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                           系统状态                              │${NC}"
    echo -e "${CYAN}├──────────────────┬──────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│    IP转发状态    │${NC} $(cat /proc/sys/net/ipv4/ip_forward)                                        ${CYAN}│${NC}"
    echo -e "${CYAN}│    当前连接数    │${NC} $(netstat -nat | grep ESTABLISHED | wc -l)                                       ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────┴──────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                        当前转发规则                             │${NC}"
    echo -e "${CYAN}├────────────┬───────────────────────┬────────────────────────────┤${NC}"
    echo -e "${CYAN}│   源端口   │       目标IP          │          目标端口         │${NC}"
    echo -e "${CYAN}├────────────┼───────────────────────┼────────────────────────────┤${NC}"
    if [ -f "$FORWARD_RULES_FILE" ]; then
        while read -r src_port target_ip target_port; do
            printf "${CYAN}│${NC} %-10s ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-20s ${CYAN}│${NC}\n" "$src_port" "$target_ip" "$target_port"
        done < "$FORWARD_RULES_FILE"
    else
        echo -e "${CYAN}│${NC} 暂无转发规则                                                  ${CYAN}│${NC}"
    fi
    echo -e "${CYAN}└────────────┴───────────────────────┴────────────────────────────┘${NC}"
    echo ""

    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                         NAT规则统计                             │${NC}"
    echo -e "${CYAN}├────────┬──────────┬──────────┬─────────────────────────────────┤${NC}"
    echo -e "${CYAN}│  类型  │  包计数  │ 字节计数 │           规则详情             │${NC}"
    echo -e "${CYAN}├────────┼──────────┼──────────┼─────────────────────────────────┤${NC}"
    if [ -f "$FORWARD_RULES_FILE" ]; then
        while read -r src_port target_ip target_port; do
            # DNAT规则
            dnat_info=$(iptables -t nat -L PREROUTING -n -v | grep "${target_ip}:${target_port}")
            if [ -n "$dnat_info" ]; then
                packets=$(echo "$dnat_info" | awk '{print $2}')
                bytes=$(echo "$dnat_info" | awk '{print $3}')
                printf "${CYAN}│${NC} %-6s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-31s ${CYAN}│${NC}\n" \
                    "DNAT" "$packets" "$bytes" "$src_port -> ${target_ip}:${target_port}"
            fi
            
            # SNAT规则 - 修改这部分以正确处理多行输出
            snat_info=$(iptables -t nat -L POSTROUTING -n -v | grep "${target_ip}" | grep "to:" | head -n 1)
            if [ -n "$snat_info" ]; then
                packets=$(echo "$snat_info" | awk '{print $2}')
                bytes=$(echo "$snat_info" | awk '{print $3}')
                to_addr=$(echo "$snat_info" | grep -o 'to:[^ ]*' | cut -d: -f2)
                printf "${CYAN}│${NC} %-6s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-31s ${CYAN}│${NC}\n" \
                    "SNAT" "$packets" "$bytes" "${target_ip} -> ${to_addr}"
            fi
        done < "$FORWARD_RULES_FILE"
    else
        echo -e "${CYAN}│${NC} 暂无NAT规则                                                   ${CYAN}│${NC}"
    fi
    echo -e "${CYAN}└────────┴──────────┴──────────┴─────────────────────────────────┘${NC}"
    echo ""

    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                      FORWARD链规则统计                          │${NC}"
    echo -e "${CYAN}├────────┬──────────┬──────────┬─────────────────────────────────┤${NC}"
    echo -e "${CYAN}│  方向  │  包计数  │ 字节计数 │           规则详情             │${NC}"
    echo -e "${CYAN}├────────┼──────────┼──────────┼─────────────────────────────────┤${NC}"
    if [ -f "$FORWARD_RULES_FILE" ]; then
        while read -r src_port target_ip target_port; do
            # 入站规则
            in_info=$(iptables -L FORWARD -n -v | grep "${target_ip}" | grep "dport")
            if [ -n "$in_info" ]; then
                packets=$(echo "$in_info" | awk '{print $2}')
                bytes=$(echo "$in_info" | awk '{print $3}')
                printf "${CYAN}│${NC} %-6s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-31s ${CYAN}│${NC}\n" \
                    "入站" "$packets" "$bytes" "目标:${target_ip} 端口:80,443"
            fi
            
            # 出站规则
            out_info=$(iptables -L FORWARD -n -v | grep "${target_ip}" | grep "sport")
            if [ -n "$out_info" ]; then
                packets=$(echo "$out_info" | awk '{print $2}')
                bytes=$(echo "$out_info" | awk '{print $3}')
                printf "${CYAN}│${NC} %-6s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-31s ${CYAN}│${NC}\n" \
                    "出站" "$packets" "$bytes" "源:${target_ip} 端口:80,443"
            fi
        done < "$FORWARD_RULES_FILE"
    else
        echo -e "${CYAN}│${NC} 暂无FORWARD规则                                              ${CYAN}│${NC}"
    fi
    echo -e "${CYAN}└────────┴──────────┴──────────┴─────────────────────────────────┘${NC}"
}

manage_forward_rules() {
    while true; do
        clear
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}                           转发规则管理                                   ${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}请选择操作：${NC}"
        echo "1. 添加新的转发规则"
        echo "2. 删除转发规则"
        echo "0. 返回主菜单"

        echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}请选择操作 [0-2]:${NC}"
        read -p "> " sub_choice

        case $sub_choice in
            1)
                add_forward_rule
                read -p "按回车继续..."
                ;;
            2)
                delete_forward_rule
                read -p "按回车继续..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                sleep 1
                ;;
        esac
    done
}

###################
# 主菜单
###################
show_menu() {
    while true; do
        print_banner
        echo -e "${YELLOW}请选择操作：${NC}"
        echo "1. 启用IP转发并优化和自启"
        echo "2. 转发规则管理"
        echo "3. 保存当前规则"
        echo "4. 查询转发规则"
        echo "5. 恢复之前的规则"
        echo "0. 退出"

        echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}请选择操作 [0-5]:${NC}"
        read -p "> " choice

        case $choice in
            1)
                enable_ip_forward
                read -p "按回车继续..."
                ;;
            2)
                manage_forward_rules
                ;;
            3)
                save_rules
                read -p "按回车继续..."
                ;;
            4)
                check_forward_status
                read -p "按回车继续..."
                ;;
            5)
                restore_rules
                read -p "按回车继续..."
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                sleep 1
                ;;
        esac
    done
}

###################
# 主程序
###################
check_root
show_menu