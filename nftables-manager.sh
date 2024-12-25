#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 root 权限运行此脚本${NC}"
    exit 1
fi

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
            echo -e "nftables 服务状态: ${YELLOW}未运行${NC}"
            echo "正在启动 nftables 服务..."
            systemctl start nftables
            systemctl enable nftables
        fi
    else
        echo -e "${YELLOW}未安装${NC}"
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

# 在文件开头的全局变量定义部分添加
RULES_FILE="/etc/nftables.conf"
TEMP_RULES="/tmp/nftables_temp.conf"
SYSCTL_CONF="/etc/sysctl.conf"

# 添加新的全局变量
NFTIP_SERVICE="nftip.service"
NFTIP_SCRIPT="/usr/local/bin/nftip.sh"

# 添加故障转移配置函数
configure_failover() {
    while true; do
        clear_screen
        echo -e "${CYAN}=== 故障转移配置 ===${NC}\n"
        
        # 检查 nftip 服务是否已安装
        if systemctl is-active --quiet nftip; then
            echo -e "当前状态: ${GREEN}故障转移服务运行中${NC}"
        else
            echo -e "当前状态: ${YELLOW}故障转移服务未运行${NC}"
        fi
        
        echo -e "\n${YELLOW}选项：${NC}"
        echo "  1. 配置故障转移"
        echo "  2. 启动/重启服务"
        echo "  3. 停止服务"
        echo "  4. 查看服务状态"
        echo "  5. 返回主菜单"
        
        echo -n -e "\n${YELLOW}请选择操作 [1-5]${NC}: "
        read -r failover_choice

        case $failover_choice in
            1)
                echo -e "\n${YELLOW}请输入故障转移配置：${NC}"
                echo -e "${BLUE}----------------------------------------${NC}"
                echo -n "主服务器 IP: "
                read -r main_server
                echo -n "备用服务器 IP: "
                read -r backup_server
                echo -n "本地端口 (多个端口用空格分隔): "
                read -r local_ports
                echo -n "目标端口 (与本地端口一一对应，用空格分隔): "
                read -r target_ports
                echo -n "检查间隔(秒) [默认10]: "
                read -r check_interval
                check_interval=${check_interval:-10}
                echo -n "失败次数阈值 [默认3]: "
                read -r required_fails
                required_fails=${required_fails:-3}
                
                # 创建 nftip.sh
                cat > "$NFTIP_SCRIPT" << EOF
#!/bin/bash

MAIN_SERVER="$main_server"
BACKUP_SERVER="$backup_server"
FAIL_COUNT=0
REQUIRED_FAILS=$required_fails
CHECK_INTERVAL=$check_interval
LOCAL_PORTS=($local_ports)
TARGET_PORTS=($target_ports)

switch_to_backup() {
   nft flush ruleset
   nft add table ip forward2jp
   nft add chain ip forward2jp prerouting { type nat hook prerouting priority -100 \; }
   nft add chain ip forward2jp postrouting { type nat hook postrouting priority 100 \; }
   
   for i in \${!LOCAL_PORTS[@]}; do
       nft add rule ip forward2jp prerouting tcp dport \${LOCAL_PORTS[i]} dnat to \$BACKUP_SERVER:\${TARGET_PORTS[i]}
       nft add rule ip forward2jp prerouting udp dport \${LOCAL_PORTS[i]} dnat to \$BACKUP_SERVER:\${TARGET_PORTS[i]}
   done
   nft add rule ip forward2jp postrouting ip daddr \$BACKUP_SERVER masquerade
}

switch_to_main() {
   nft flush ruleset
   nft add table ip forward2jp
   nft add chain ip forward2jp prerouting { type nat hook prerouting priority -100 \; }
   nft add chain ip forward2jp postrouting { type nat hook postrouting priority 100 \; }
   
   for i in \${!LOCAL_PORTS[@]}; do
       nft add rule ip forward2jp prerouting tcp dport \${LOCAL_PORTS[i]} dnat to \$MAIN_SERVER:\${TARGET_PORTS[i]}
       nft add rule ip forward2jp prerouting udp dport \${LOCAL_PORTS[i]} dnat to \$MAIN_SERVER:\${TARGET_PORTS[i]}
   done
   nft add rule ip forward2jp postrouting ip daddr \$MAIN_SERVER masquerade
}

# 验证端口数量是否匹配
if [ \${#LOCAL_PORTS[@]} -ne \${#TARGET_PORTS[@]} ]; then
    echo "错误：本地端口和目标端口数量不匹配"
    exit 1
fi

# 初始化规则
switch_to_main

while true; do
   if ! ping -c 3 -W 2 \$MAIN_SERVER &> /dev/null; then
       FAIL_COUNT=\$((FAIL_COUNT + 1))
       if [ \$FAIL_COUNT -ge \$REQUIRED_FAILS ]; then
           switch_to_backup
       fi
   else
       if [ \$FAIL_COUNT -ge \$REQUIRED_FAILS ]; then
           switch_to_main
       fi
       FAIL_COUNT=0
   fi
   sleep \$CHECK_INTERVAL
done
EOF
                chmod +x "$NFTIP_SCRIPT"
                
                # 创建 systemd 服务
                cat > "/etc/systemd/system/$NFTIP_SERVICE" << EOF
[Unit]
Description=NFTables IP Failover Service
After=network.target

[Service]
Type=simple
ExecStart=$NFTIP_SCRIPT
Restart=always

[Install]
WantedBy=multi-user.target
EOF
                
                systemctl daemon-reload
                echo -e "${GREEN}配置已保存！${NC}"
                ;;
            2)
                systemctl restart nftip
                systemctl enable nftip
                echo -e "${GREEN}服务已启动/重启！${NC}"
                ;;
            3)
                systemctl stop nftip
                systemctl disable nftip
                echo -e "${YELLOW}服务已停止！${NC}"
                ;;
            4)
                echo -e "\n${CYAN}服务状态：${NC}"
                systemctl status nftip
                ;;
            5)
                return
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}按回车键继续...${NC}"
        read -r
    done
}

# 检查并停止故障转移服务
check_and_stop_failover() {
    if systemctl is-active --quiet "$NFTIP_SERVICE"; then
        echo -e "${YELLOW}检测到故障转移服务正在运行，正在停止...${NC}"
        systemctl stop "$NFTIP_SERVICE"
        echo -e "${GREEN}故障转移服务已停止${NC}"
    fi
}

# 修改 add_forward_rule 函数
add_forward_rule() {
    # 检查并停止故障转移服务
    check_and_stop_failover
    
    echo -e "${YELLOW}请输入转发规则信息：${NC}"
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

# 添加系统优化函数
optimize_system() {
    echo -e "${YELLOW}正在配置系统优化参数...${NC}"
    
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
        echo -e "${YELLOW}备份原配置文件到 ${SYSCTL_CONF}.bak${NC}"
        cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak"
        echo -e "${YELLOW}更新系统配置...${NC}"
        grep -v -F -f <(grep -v '^#' "$tmp_sysctl" | cut -d= -f1 | tr -d ' ') "$SYSCTL_CONF" > "${SYSCTL_CONF}.tmp"
        mv "${SYSCTL_CONF}.tmp" "$SYSCTL_CONF"
    fi

    # 添加新的配置
    echo -e "${YELLOW}添加优化参数...${NC}"
    cat "$tmp_sysctl" >> "$SYSCTL_CONF"

    # 应用配置
    echo -e "${YELLOW}应用新配置...${NC}"
    if sysctl -p "$SYSCTL_CONF"; then
        echo -e "${GREEN}系统优化参数配置成功！${NC}"
    else
        echo -e "${RED}系统优化参数配置失败！${NC}"
        # 如果失败，恢复备份
        if [ -f "${SYSCTL_CONF}.bak" ]; then
            echo -e "${YELLOW}正在恢复原配置...${NC}"
            mv "${SYSCTL_CONF}.bak" "$SYSCTL_CONF"
            sysctl -p "$SYSCTL_CONF"
        fi
    fi

    # 清理临时文件
    rm -f "$tmp_sysctl"
}

# 修改 show_rules 函数，修复显示格式
show_rules() {
    echo -e "${BLUE}----------------------------------------${NC}"
    if nft list ruleset | grep -q "table ip forward2jp"; then
        echo -e "${YELLOW}当前转发规则：${NC}"
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
        echo -e "  ${YELLOW}当前没有配置任何转发规则${NC}"
    fi
    echo -e "${BLUE}----------------------------------------${NC}"
}

# 修改 delete_rules 函数
delete_rules() {
    clear_screen
    echo -e "${CYAN}=== 删除转发规则 ===${NC}\n"
    
    # 检查并停止故障转移服务
    check_and_stop_failover
    
    # 获取并显示当前规则
    show_rules
    
    echo -n "确定要删除所有转发规则吗？(y/n): "
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if nft list tables | grep -q "forward2jp"; then
            nft flush table ip forward2jp
            nft delete table ip forward2jp
            rm -f "$RULES_FILE"
            echo -e "${GREEN}所有转发规则已删除！${NC}"
        else
            echo -e "${YELLOW}没有找到任何转发规则${NC}"
        fi
    else
        echo "取消删除操作"
    fi
}

# 添加清屏函数
clear_screen() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          NFTables 转发规则管理器       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo
}

# 主菜单
main_menu() {
    while true; do
        clear_screen
        echo -e "${YELLOW}可用操作：${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${GREEN}1${NC}. 添加转发规则"
        echo -e "  ${GREEN}2${NC}. 删除转发规则"
        echo -e "  ${GREEN}3${NC}. 显示当前规则"
        echo -e "  ${GREEN}4${NC}. 系统性能优化"
        echo -e "  ${GREEN}5${NC}. 配置故障转移"
        echo -e "  ${GREEN}0${NC}. 退出程序"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo -n -e "${YELLOW}请选择操作 [0-5]${NC}: "
        read -r choice

        case $choice in
            1)
                clear_screen
                echo -e "${CYAN}=== 添加转发规则 ===${NC}\n"
                enable_ip_forward
                install_nftables
                add_forward_rule
                echo -e "\n${YELLOW}按回车键返回主菜单...${NC}"
                read -r
                ;;
            2)
                delete_rules
                echo -e "\n${YELLOW}按回车键返回主菜单...${NC}"
                read -r
                ;;
            3)
                clear_screen
                echo -e "${CYAN}=== 当前转发规则 ===${NC}\n"
                show_rules
                echo -e "\n${YELLOW}按回车键返回主菜单...${NC}"
                read -r
                ;;
            4)
                clear_screen
                echo -e "${CYAN}=== 系统性能优化 ===${NC}\n"
                optimize_system
                echo -e "\n${YELLOW}按回车键返回主菜单...${NC}"
                read -r
                ;;
            5)
                configure_failover
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
