#!/bin/bash

# 将原来的 GREEN 相关颜色改为科技蓝
TECH_BLUE='\033[38;5;33m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}请使用 root 权限运行此脚本${NC}"
        echo "命令: sudo $0"
        exit 1
    fi
}

# 检查必要工具是否安装
check_requirements() {
    local tools=("whois" "ipset" "iptables" "ufw" "systemctl")
    local missing_tools=()

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${YELLOW}缺少以下工具，正在安装：${NC}"
        echo "${missing_tools[*]}"
        apt update
        apt install -y "${missing_tools[@]}"
    fi
}

# 创建 ipset 并添加 ASN IP 范围
setup_ipset() {
    local asn=$1
    local set_name="blocked-asn-${asn#AS}"

    # 如果 ipset 已存在，先删除
    ipset list "$set_name" &>/dev/null && ipset destroy "$set_name"

    # 创建新的 ipset
    ipset create "$set_name" hash:net hashsize 4096

    # 获取 ASN 的 IP 范围
    echo -e "${BLUE}正在获取 ASN $asn 的 IP 范围...${NC}"
    whois -h whois.radb.net -- "-i origin $asn" | \
        grep -Eo "([0-9.]+){4}/[0-9]+" | sort -u | \
        while read -r ip; do
            # 将错误信息重定向到 /dev/null
            ipset add "$set_name" "$ip" 2>/dev/null
        done

    # 显示添加的 IP 范围数量
    local count=$(ipset list "$set_name" | grep -c "/")
    echo -e "${GREEN}已添加 ASN $asn 的 $count 个 IP 范围到 ipset${NC}"
    return 0
}

# 配置 iptables 规则
setup_iptables() {
    local asn=$1
    local set_name="blocked-asn-${asn#AS}"

    # 检查规则是否已存在
    if ! iptables -C INPUT -m set --match-set "$set_name" src -j DROP &>/dev/null; then
        iptables -I INPUT -m set --match-set "$set_name" src -j DROP
        echo -e "${GREEN}已添加 iptables 规则${NC}"
    fi
}

# 配置 UFW 规则
setup_ufw() {
    local asn=$1
    local set_name="blocked-asn-${asn#AS}"
    local rules_file="/etc/ufw/before.rules"

    # 备份原始规则文件
    if [ ! -f "${rules_file}.bak" ]; then
        cp "$rules_file" "${rules_file}.bak"
    fi

    # 检查是否已有 ipset 规则
    if ! grep -q "$set_name" "$rules_file"; then
        # 在适当位置添加规则
        sed -i "/^*filter/a -A ufw-before-input -m set --match-set $set_name src -j DROP" "$rules_file"
        echo -e "${GREEN}已添加 UFW 规则${NC}"
        
        # 重新加载 UFW
        ufw reload
    fi
}

# 创建系统服务
create_systemd_service() {
    local service_file="/etc/systemd/system/asn-blocker.service"
    local script_path=$(readlink -f "$0")

    cat > "$service_file" << EOF
[Unit]
Description=ASN Blocker Service
After=network.target

[Service]
Type=oneshot
ExecStart=$script_path --reload
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable asn-blocker.service
    echo -e "${GREEN}已创建并启用系统服务${NC}"
}

# 获取所有已拦截的 ASN 列表
get_blocked_asns() {
    ipset list -n | grep "blocked-asn-" | while read -r set; do
        echo "AS${set#blocked-asn-}"
    done
}

# 删除 ASN 拦截
remove_asn_block() {
    local asn_list=($(get_blocked_asns))

    if [ ${#asn_list[@]} -eq 0 ]; then
        echo -e "${YELLOW}当前没有已拦截的 ASN${NC}"
        return 1
    fi

    echo -e "${GREEN}当前已拦截的 ASN 列表：${NC}"
    echo "----------------------------------------"

    # 显示 ASN 列表及其 IP 段数量
    local i=1
    declare -A asn_map  # 创建关联数组存储序号和ASN的对应关系

    for asn in "${asn_list[@]}"; do
        local set_name="blocked-asn-${asn#AS}"
        local ip_count=$(ipset list "$set_name" | grep -c "/")
        asn_map[$i]=$asn
        printf "%2d) %s (包含 %d 个 IP 段)\n" $i "$asn" "$ip_count"
        ((i++))
    done

    echo "----------------------------------------"
    echo "0) 返回主菜单"
    echo

    # 获取用户选择
    local choice
    while true; do
        read -p "请输入要删除的 ASN 序号: " choice
        if [[ "$choice" == "0" ]]; then
            echo "操作已取消"
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -lt "$i" ]; then
            break
        else
            echo -e "${RED}无效的选择，请重新输入${NC}"
        fi
    done

    # 获取选中的 ASN
    local selected_asn="${asn_map[$choice]}"
    local set_name="blocked-asn-${selected_asn#AS}"

    echo -e "${BLUE}正在删除 $selected_asn ...${NC}"

    # 删除 iptables 规则
    iptables -D INPUT -m set --match-set "$set_name" src -j DROP &>/dev/null

    # 删除 ipset
    ipset destroy "$set_name" &>/dev/null

    # 从 UFW 规则中删除
    sed -i "/-A ufw-before-input -m set --match-set $set_name src -j DROP/d" /etc/ufw/before.rules

    ufw reload >/dev/null 2>&1
    echo -e "${GREEN}已成功删除 $selected_asn 的拦截规则${NC}"
}

# 显示当前规则
show_rules() {
    echo -e "${TECH_BLUE}┌─────────────── ASN 拦截规则概览 ───────────────┐${NC}"
    echo

    # ASN IP段统计
    if ipset list -n | grep -q "blocked-asn-"; then
        echo -e "${TECH_BLUE}● ASN IP段统计${NC}"
        echo "| ASN编号 | IP段总数 | /24网段数 | /23网段数 | /22网段数 | 其他网段数 |"
        echo "|----------|-----------|------------|------------|------------|------------|"
        
        for set in $(ipset list -n | grep "blocked-asn-"); do
            asn="${set#blocked-asn-}"
            total_ips=$(ipset list "$set" | grep -c "/")
            
            ip_ranges=$(ipset list "$set" | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}")
            count_24=$(echo "$ip_ranges" | grep -c "/24")
            count_23=$(echo "$ip_ranges" | grep -c "/23")
            count_22=$(echo "$ip_ranges" | grep -c "/22")
            count_others=$((total_ips - count_24 - count_23 - count_22))
            
            printf "| AS%-6s | %9d | %10d | %10d | %10d | %10d |\n" \
                "$asn" "$total_ips" "$count_24" "$count_23" "$count_22" "$count_others"
        done
    else
        echo -e "${YELLOW}当前没有 ASN 拦截规则${NC}"
    fi

    echo
    # IPTables规则
    echo -e "${TECH_BLUE}● IPTables 规则${NC}"
    echo "| 规则类型 | 动作 | 协议 | 来源地址 | 目标地址 | ASN |"
    echo "|----------|------|--------|-----------|-----------|-----|"
    if iptables -L INPUT -n | grep -q "match-set blocked-asn-"; then
        iptables -L INPUT -n | grep "match-set blocked-asn-" | \
        while read -r line; do
            action=$(echo "$line" | awk '{print $1}')
            proto=$(echo "$line" | awk '{print $2}')
            src=$(echo "$line" | awk '{print $4}')
            dst=$(echo "$line" | awk '{print $5}')
            asn=$(echo "$line" | grep -o "blocked-asn-[0-9]\+" | sed 's/blocked-asn-/AS/')
            printf "| IPTables | %s | %s | %s | %s | %s |\n" "$action" "$proto" "$src" "$dst" "$asn"
        done
    else
        echo "| IPTables | 无规则 | - | - | - | - |"
    fi

    echo
    # UFW规则
    echo -e "${TECH_BLUE}● UFW 规则${NC}"
    echo "| 规则类型 | 链 | ASN | 动作 |"
    echo "|----------|-----|-----|------|"
    if grep -q "blocked-asn-" /etc/ufw/before.rules; then
        grep "blocked-asn-" /etc/ufw/before.rules | \
        while read -r line; do
            chain=$(echo "$line" | awk '{print $2}')
            asn=$(echo "$line" | grep -o "blocked-asn-[0-9]\+" | sed 's/blocked-asn-/AS/')
            action=$(echo "$line" | awk '{print $NF}')
            printf "| UFW | %s | %s | %s |\n" "$chain" "$asn" "$action"
        done
    else
        echo "| UFW | 无规则 | - | - |"
    fi

    echo -e "\n${TECH_BLUE}└──────────────────────────────────────────────┘${NC}"
}

# 查看拦截记录函数
show_block_stats() {
    echo -e "${TECH_BLUE}===== ASN 拦截统计 =====${NC}"
    echo
    echo "| ASN编号 | 数据包数量 | 流量大小 |"
    echo "|---------|------------|----------|"
    
    iptables -L INPUT -v -n | grep "blocked-asn" | \
    awk '{
        match($0,/blocked-asn-([0-9]+)/,a); 
        packets=$1;
        bytes=$2;
        # 转换字节到合适单位
        if(bytes < 1024) unit="B";
        else if(bytes < 1048576) {bytes=bytes/1024; unit="KB";}
        else if(bytes < 1073741824) {bytes=bytes/1048576; unit="MB";}
        else {bytes=bytes/1073741824; unit="GB";}
        printf "| AS%-6s | %10s | %6.1f%s |\n", a[1], packets, bytes, unit
    }'
}

# 显示交互式菜单
show_menu() {
    clear
    echo -e "${TECH_BLUE}┌────────────────────────────────────┐${NC}"
    echo -e "${TECH_BLUE}│          ASN 拦截器管理系统       │${NC}"
    echo -e "${TECH_BLUE}├────────────────────────────────────┤${NC}"
    echo -e "${TECH_BLUE}│${NC} 1. 添加 ASN 拦截                    ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 2. 删除 ASN 拦截                    ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 3. 查看当前规则                     ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 4. 查看拦截记录                     ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 5. 重新加载所有规则                 ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}├────────────────────────────────────┤${NC}"
    echo -e "${TECH_BLUE}│${NC}            服务管理                 ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}├────────────────────────────────────┤${NC}"
    echo -e "${TECH_BLUE}│${NC} 6. 安装系统服务                     ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 7. 启动服务                         ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 8. 停止服务                         ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 9. 查看服务状态                     ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 10. 启用开机自启                    ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}│${NC} 11. 禁用开机自启                    ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}├────────────────────────────────────┤${NC}"
    echo -e "${TECH_BLUE}│${NC} 0. 退出程序                         ${TECH_BLUE}│${NC}"
    echo -e "${TECH_BLUE}└────────────────────────────────────┘${NC}"
    echo -ne "请输入选项编号: "
}

# 获取 ASN 输入
get_asn_input() {
    local prompt=$1
    local asn=""
    while true; do
        read -p "$prompt" asn
        if [[ $asn =~ ^AS[0-9]+$ ]]; then
            echo "$asn"
            return 0
        else
            echo -e "${RED}无效的 ASN 格式。请使用格式 'AS' 后跟数字（例如：AS12345）${NC}"
        fi
    done
}

# 按任意键继续
press_any_key() {
    echo
    read -n 1 -s -r -p "按任意键继续..."
    echo
}

# 交互式菜单主循环
interactive_menu() {
    while true; do
        show_menu
        read -r choice
        echo

        case $choice in
            1)
                asn=$(get_asn_input "请输入要拦截的 ASN (格式: AS12345): ")
                setup_ipset "$asn"
                setup_iptables "$asn"
                setup_ufw "$asn"
                ;;
            2)
                remove_asn_block
                ;;
            3)
                show_rules
                ;;
            4)
                show_block_stats
                ;;
            5)
                echo -e "${BLUE}正在重新加载所有规则...${NC}"
                for set in $(ipset list -n | grep "blocked-asn-"); do
                    asn="AS${set#blocked-asn-}"
                    setup_ipset "$asn"
                    setup_iptables "$asn"
                done
                ufw reload
                echo -e "${TECH_BLUE}规则重新加载完成${NC}"
                ;;
            6)
                create_systemd_service
                ;;
            7)
                systemctl start asn-blocker
                echo -e "${GREEN}服务已启动${NC}"
                ;;
            8)
                systemctl stop asn-blocker
                echo -e "${GREEN}服务已停止${NC}"
                ;;
            9)
                systemctl status asn-blocker
                ;;
            10)
                systemctl enable asn-blocker
                echo -e "${GREEN}已启用开机自启${NC}"
                ;;
            11)
                systemctl disable asn-blocker
                echo -e "${GREEN}已禁用开机自启${NC}"
                ;;
            0)
                echo -e "${GREEN}退出程序${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                ;;
        esac
        press_any_key
    done
}

# 获取 ASN 列表
get_blocked_asns() {
    ipset list -n | grep "blocked-asn-" | while read -r set; do
        echo "AS${set#blocked-asn-}"
    done
}

# 主程序
main() {
    check_root
    check_requirements

    if [ $# -eq 0 ]; then
        # 无参数时启动交互式菜单
        interactive_menu
    else
        # 命令行参数处理
        case "$1" in
            --add)
                if [ -z "$2" ]; then
                    echo -e "${RED}错误: 请指定 ASN 号码${NC}"
                    exit 1
                fi
                setup_ipset "$2"
                setup_iptables "$2"
                setup_ufw "$2"
                ;;
            --remove)
                if [ -z "$2" ]; then
                    echo -e "${RED}错误: 请指定 ASN 号码${NC}"
                    exit 1
                fi
                remove_asn_block "$2"
                ;;
            --reload)
                echo -e "${BLUE}正在重新加载所有规则...${NC}"
                for set in $(ipset list -n | grep "blocked-asn-"); do
                    asn="AS${set#blocked-asn-}"
                    setup_ipset "$asn"
                    setup_iptables "$asn"
                done
                ufw reload
                echo -e "${GREEN}规则重新加载完成${NC}"
                ;;
            --install)
                create_systemd_service
                ;;
            --list)
                show_rules
                ;;
            --help)
                show_help
                ;;
            *)
                show_help
                exit 1
                ;;
        esac
    fi
}

main "$@"