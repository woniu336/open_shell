#!/bin/bash

# 彩色输出定义
GREEN='\033[0;32m'
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
    echo -e "${GREEN}===== 当前 ASN 拦截规则 =====${NC}"
    echo

    echo -e "${YELLOW}IPSet 规则列表:${NC}"
    if ipset list -n | grep -q "blocked-asn-"; then
        for set in $(ipset list -n | grep "blocked-asn-"); do
            echo "----------------------------------------"
            echo "ASN: AS${set#blocked-asn-}"

            # 获取该 ASN 的统计信息
            local total_ips=$(ipset list "$set" | grep -c "/")
            local ip_ranges=$(ipset list "$set" | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}")

            # 统计不同掩码的 IP 段数量
            echo "IP 段统计:"
            echo "$ip_ranges" | awk -F'/' '{count[$2]++} END {
                for (mask in count) {
                    printf "  /%s 的网段: %d 个\n", mask, count[mask]
                }
            }' | sort -n -k2 -t"/"

            echo "总计: $total_ips 个 IP 段"

            # 显示前5个 IP 段作为示例
            echo "示例 IP 段 (前5个):"
            echo "$ip_ranges" | head -n 5 | sed 's/^/  /'

            # 如果有更多 IP 段，显示省略信息
            if [ "$total_ips" -gt 5 ]; then
                echo "  ... 等共 $total_ips 个 IP 段"
            fi
        done
    else
        echo -e "${YELLOW}当前没有 ASN 拦截规则${NC}"
    fi

    echo
    echo -e "${YELLOW}IPTables 规则:${NC}"
    if iptables -L INPUT -n | grep -q "match-set blocked-asn-"; then
        iptables -L INPUT -n | grep "match-set blocked-asn-" | sed 's/^/  /'
    else
        echo "  没有相关 iptables 规则"
    fi

    echo
    echo -e "${YELLOW}UFW 规则 (/etc/ufw/before.rules):${NC}"
    if grep -q "blocked-asn-" /etc/ufw/before.rules; then
        grep "blocked-asn-" /etc/ufw/before.rules | sed 's/^/  /'
    else
        echo "  没有相关 UFW 规则"
    fi
}

# 显示使用帮助
show_help() {
    local script_name=$(basename "$0")
    echo -e "${GREEN}ASN 拦截器使用说明${NC}"
    echo
    echo "安装脚本:"
    echo "  chmod +x $script_name"
    echo
    echo "可用命令:"
    echo "  添加 ASN 拦截:"
    echo "    sudo ./$script_name --add AS12345"
    echo
    echo "  删除 ASN 拦截:"
    echo "    sudo ./$script_name --remove AS12345"
    echo
    echo "  查看当前规则:"
    echo "    sudo ./$script_name --list"
    echo
    echo "  重新加载所有规则:"
    echo "    sudo ./$script_name --reload"
    echo
    echo "  安装为系统服务:"
    echo "    sudo ./$script_name --install"
    echo
    echo "  显示帮助信息:"
    echo "    sudo ./$script_name --help"
    echo
    echo "服务管理命令:"
    echo "  启动服务:"
    echo "    sudo systemctl start asn-blocker"
    echo
    echo "  停止服务:"
    echo "    sudo systemctl stop asn-blocker"
    echo
    echo "  查看服务状态:"
    echo "    sudo systemctl status asn-blocker"
    echo
    echo "  启用开机自启:"
    echo "    sudo systemctl enable asn-blocker"
    echo
    echo "  禁用开机自启:"
    echo "    sudo systemctl disable asn-blocker"
}

# 显示交互式菜单
show_menu() {
    clear
    echo -e "${GREEN}===================================${NC}"
    echo -e "${GREEN}        ASN 拦截器管理菜单        ${NC}"
    echo -e "${GREEN}===================================${NC}"
    echo "1. 添加 ASN 拦截"
    echo "2. 删除 ASN 拦截"
    echo "3. 查看当前规则"
    echo "4. 重新加载所有规则"
    echo "5. 安装系统服务"
    echo "-----------------服务管理----------------"
    echo "6. 启动服务"
    echo "7. 停止服务"
    echo "8. 查看服务状态"
    echo "9. 启用开机自启"
    echo "10. 禁用开机自启"
    echo "-----------------其他选项----------------"
    echo "11. 显示帮助信息"
    echo "0. 退出程序"
    echo -e "${GREEN}===================================${NC}"
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
                echo -e "${BLUE}正在重新加载所有规则...${NC}"
                for set in $(ipset list -n | grep "blocked-asn-"); do
                    asn="AS${set#blocked-asn-}"
                    setup_ipset "$asn"
                    setup_iptables "$asn"
                done
                ufw reload
                echo -e "${GREEN}规则重新加载完成${NC}"
                ;;
            5)
                create_systemd_service
                ;;
            6)
                systemctl start asn-blocker
                echo -e "${GREEN}服务已启动${NC}"
                ;;
            7)
                systemctl stop asn-blocker
                echo -e "${GREEN}服务已停止${NC}"
                ;;
            8)
                systemctl status asn-blocker
                ;;
            9)
                systemctl enable asn-blocker
                echo -e "${GREEN}已启用开机自启${NC}"
                ;;
            10)
                systemctl disable asn-blocker
                echo -e "${GREEN}已禁用开机自启${NC}"
                ;;
            11)
                show_help
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