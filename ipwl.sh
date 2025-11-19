#!/bin/bash
# 脚本名称: ipwl.sh
# 描述: 针对Debian系统创建和管理基于端口的IP白名单
# 作者: Claude
# 日期: 2025-05-10

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 请使用root权限运行此脚本${NC}" >&2
        echo "使用方法: sudo $0"
        exit 1
    fi
}

# 安装ipset
install_ipset() {
    if ! command -v ipset &> /dev/null; then
        echo -e "${YELLOW}检测到ipset未安装，正在安装...${NC}"
        apt-get update -qq
        apt-get install -y ipset
        if [ $? -ne 0 ]; then
            echo -e "${RED}安装ipset失败，请检查您的网络连接或手动安装${NC}" >&2
            exit 1
        fi
        echo -e "${GREEN}ipset安装成功${NC}"
    fi
}

# 清屏并显示标题
show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        端口IP白名单管理系统 - Debian专用          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 显示主菜单
show_main_menu() {
    show_header
    echo -e "${GREEN}主菜单:${NC}"
    echo ""
    echo "  1) 创建新的端口白名单"
    echo "  2) 管理现有端口白名单"
    echo "  3) 查看所有白名单配置"
    echo "  4) 删除端口白名单"
    echo "  5) 备份/恢复配置"
    echo "  6) 清理UFW冲突规则"
    echo ""
    echo "  0) 退出"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 验证端口号
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# 验证IP地址
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    # 检查每个段是否在0-255范围内
    IFS='.' read -ra ADDR <<< "$ip"
    for i in "${ADDR[@]}"; do
        if [ "$i" -gt 255 ]; then
            return 1
        fi
    done
    return 0
}

# 创建新的端口白名单
create_whitelist() {
    show_header
    echo -e "${GREEN}=== 创建新的端口白名单 ===${NC}"
    echo ""
    
    read -p "请输入需要设置白名单的端口号: " port
    
    if ! validate_port "$port"; then
        echo -e "${RED}错误: 请输入有效的端口号 (1-65535)${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    local set_name="whitelist_port_${port}"
    
    # 检查集合是否已存在
    if ipset list -n 2>/dev/null | grep -q "^${set_name}$"; then
        echo -e "${YELLOW}警告: 端口 ${port} 的白名单已存在${NC}"
        read -p "是否要添加新IP到现有白名单? (y/n): " choice
        if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
            echo -e "${YELLOW}操作已取消${NC}"
            read -p "按回车键继续..."
            return
        fi
    else
        # 创建新集合
        ipset create "${set_name}" hash:ip
        echo -e "${GREEN}已创建白名单集合: ${set_name}${NC}"
    fi
    
    # 添加IP地址
    echo ""
    echo -e "${CYAN}请输入要添加到白名单的IP地址${NC}"
    echo -e "${YELLOW}提示: 输入 'q' 完成添加${NC}"
    echo ""
    
    while true; do
        read -p "IP地址 (或输入 q 退出): " ip_address
        
        if [[ "$ip_address" == "q" || "$ip_address" == "Q" ]]; then
            break
        fi
        
        if ! validate_ip "$ip_address"; then
            echo -e "${RED}错误: 无效的IP地址格式，请重新输入${NC}"
            continue
        fi
        
        # 检查IP是否已存在
        if ipset test "${set_name}" "${ip_address}" 2>/dev/null; then
            echo -e "${YELLOW}IP ${ip_address} 已存在于白名单中${NC}"
        else
            ipset add "${set_name}" "${ip_address}"
            echo -e "${GREEN}✓ 已添加 ${ip_address}${NC}"
        fi
    done
    
    # 配置iptables规则
    configure_iptables_rules "$port" "$set_name"
    
    # 保存配置
    save_configuration
    
    echo ""
    echo -e "${GREEN}端口 ${port} 的白名单配置完成!${NC}"
    read -p "按回车键继续..."
}

# 配置iptables规则
configure_iptables_rules() {
    local port=$1
    local set_name=$2
    
    echo ""
    echo -e "${CYAN}正在配置iptables规则...${NC}"
    
    # 清理UFW冲突规则
    clean_ufw_rules "$port"
    
    # 检查并添加允许规则
    if ! iptables -C INPUT -p tcp --dport ${port} -m set --match-set ${set_name} src -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport ${port} -m set --match-set ${set_name} src -j ACCEPT
        echo -e "${GREEN}✓ 已添加白名单通行规则${NC}"
    else
        echo -e "${YELLOW}白名单通行规则已存在${NC}"
    fi
    
    # 检查并添加拒绝规则
    if ! iptables -C INPUT -p tcp --dport ${port} -j DROP 2>/dev/null; then
        iptables -A INPUT -p tcp --dport ${port} -j DROP
        echo -e "${GREEN}✓ 已添加默认拒绝规则${NC}"
    else
        echo -e "${YELLOW}默认拒绝规则已存在${NC}"
    fi
}

# 清理UFW冲突规则
clean_ufw_rules() {
    local port=$1
    
    if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "active"; then
        if ufw status numbered 2>/dev/null | grep -q "\\b${port}\\b"; then
            echo -e "${YELLOW}检测到UFW中有端口 ${port} 的规则，正在清理...${NC}"
            local rule_numbers=$(ufw status numbered | grep -E "^\[[0-9]+\].*\b${port}\b" | sed -E 's/^\[([0-9]+)\].*/\1/' | sort -nr)
            for num in $rule_numbers; do
                ufw --force delete $num &>/dev/null
            done
            echo -e "${GREEN}✓ UFW冲突规则已清理${NC}"
        fi
    fi
}

# 管理现有白名单
manage_whitelist() {
    show_header
    echo -e "${GREEN}=== 管理现有端口白名单 ===${NC}"
    echo ""
    
    # 列出所有白名单
    local whitelists=$(ipset list -n 2>/dev/null | grep "^whitelist_port_")
    
    if [ -z "$whitelists" ]; then
        echo -e "${YELLOW}当前没有配置任何端口白名单${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo "现有的端口白名单:"
    echo ""
    local i=1
    declare -A port_map
    while IFS= read -r setname; do
        local port=$(echo "$setname" | sed 's/whitelist_port_//')
        echo "  $i) 端口 $port"
        port_map[$i]=$port
        ((i++))
    done <<< "$whitelists"
    
    echo ""
    echo "  0) 返回主菜单"
    echo ""
    read -p "请选择要管理的端口: " choice
    
    if [ "$choice" = "0" ]; then
        return
    fi
    
    if [ -z "${port_map[$choice]}" ]; then
        echo -e "${RED}无效的选择${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    local selected_port="${port_map[$choice]}"
    manage_port_menu "$selected_port"
}

# 端口管理子菜单
manage_port_menu() {
    local port=$1
    local set_name="whitelist_port_${port}"
    
    while true; do
        show_header
        echo -e "${GREEN}=== 管理端口 ${port} 的白名单 ===${NC}"
        echo ""
        echo -e "${CYAN}当前白名单IP列表:${NC}"
        local ips=$(ipset list "${set_name}" 2>/dev/null | grep -E '^[0-9]+\.')
        if [ -z "$ips" ]; then
            echo -e "${YELLOW}  (空)${NC}"
        else
            echo "$ips" | nl -w2 -s'. '
        fi
        echo ""
        echo "操作选项:"
        echo "  1) 添加IP到白名单"
        echo "  2) 从白名单删除IP"
        echo "  3) 清空白名单"
        echo ""
        echo "  0) 返回上级菜单"
        echo ""
        read -p "请选择操作: " action
        
        case $action in
            1)
                add_ip_to_whitelist "$set_name"
                ;;
            2)
                remove_ip_from_whitelist "$set_name"
                ;;
            3)
                clear_whitelist "$set_name" "$port"
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 添加IP到白名单
add_ip_to_whitelist() {
    local set_name=$1
    
    echo ""
    read -p "请输入要添加的IP地址: " ip_address
    
    if ! validate_ip "$ip_address"; then
        echo -e "${RED}错误: 无效的IP地址格式${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    if ipset test "${set_name}" "${ip_address}" 2>/dev/null; then
        echo -e "${YELLOW}IP ${ip_address} 已存在于白名单中${NC}"
    else
        ipset add "${set_name}" "${ip_address}"
        echo -e "${GREEN}✓ 已添加 ${ip_address}${NC}"
        save_configuration
    fi
    
    read -p "按回车键继续..."
}

# 从白名单删除IP
remove_ip_from_whitelist() {
    local set_name=$1
    
    echo ""
    read -p "请输入要删除的IP地址: " ip_address
    
    if ipset test "${set_name}" "${ip_address}" 2>/dev/null; then
        ipset del "${set_name}" "${ip_address}"
        echo -e "${GREEN}✓ 已删除 ${ip_address}${NC}"
        save_configuration
    else
        echo -e "${YELLOW}IP ${ip_address} 不在白名单中${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 清空白名单
clear_whitelist() {
    local set_name=$1
    local port=$2
    
    echo ""
    echo -e "${YELLOW}警告: 这将清空端口 ${port} 的所有白名单IP${NC}"
    read -p "确认继续? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        ipset flush "${set_name}"
        echo -e "${GREEN}✓ 白名单已清空${NC}"
        save_configuration
    else
        echo -e "${YELLOW}操作已取消${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 查看所有白名单配置
view_all_whitelists() {
    show_header
    echo -e "${GREEN}=== 所有端口白名单配置 ===${NC}"
    echo ""
    
    local whitelists=$(ipset list -n 2>/dev/null | grep "^whitelist_port_")
    
    if [ -z "$whitelists" ]; then
        echo -e "${YELLOW}当前没有配置任何端口白名单${NC}"
    else
        while IFS= read -r setname; do
            local port=$(echo "$setname" | sed 's/whitelist_port_//')
            echo -e "${CYAN}端口 ${port}:${NC}"
            local ips=$(ipset list "${setname}" 2>/dev/null | grep -E '^[0-9]+\.')
            if [ -z "$ips" ]; then
                echo -e "${YELLOW}  (空)${NC}"
            else
                echo "$ips" | sed 's/^/  /'
            fi
            echo ""
        done <<< "$whitelists"
        
        echo -e "${CYAN}iptables规则:${NC}"
        iptables -L INPUT -n --line-numbers | grep -E "whitelist_port_|tcp dpt:" | sed 's/^/  /'
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 删除端口白名单
delete_whitelist() {
    show_header
    echo -e "${GREEN}=== 删除端口白名单 ===${NC}"
    echo ""
    
    local whitelists=$(ipset list -n 2>/dev/null | grep "^whitelist_port_")
    
    if [ -z "$whitelists" ]; then
        echo -e "${YELLOW}当前没有配置任何端口白名单${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo "现有的端口白名单:"
    echo ""
    local i=1
    declare -A port_map
    while IFS= read -r setname; do
        local port=$(echo "$setname" | sed 's/whitelist_port_//')
        echo "  $i) 端口 $port"
        port_map[$i]=$port
        ((i++))
    done <<< "$whitelists"
    
    echo ""
    echo "  0) 返回主菜单"
    echo ""
    read -p "请选择要删除的端口: " choice
    
    if [ "$choice" = "0" ]; then
        return
    fi
    
    if [ -z "${port_map[$choice]}" ]; then
        echo -e "${RED}无效的选择${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    local port="${port_map[$choice]}"
    local set_name="whitelist_port_${port}"
    
    echo ""
    echo -e "${YELLOW}警告: 这将删除端口 ${port} 的白名单配置及相关iptables规则${NC}"
    read -p "确认删除? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        # 删除iptables规则
        iptables -D INPUT -p tcp --dport ${port} -m set --match-set ${set_name} src -j ACCEPT 2>/dev/null
        iptables -D INPUT -p tcp --dport ${port} -j DROP 2>/dev/null
        
        # 删除ipset集合
        ipset destroy "${set_name}" 2>/dev/null
        
        echo -e "${GREEN}✓ 端口 ${port} 的白名单已删除${NC}"
        save_configuration
    else
        echo -e "${YELLOW}操作已取消${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 保存配置
save_configuration() {
    mkdir -p /etc/iptables
    
    # 保存iptables规则
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    
    # 保存ipset规则
    ipset save > /etc/iptables/ipset.conf 2>/dev/null
    
    # 创建启动恢复脚本
    if [ ! -f /etc/network/if-pre-up.d/iptables-restore ]; then
        cat > /etc/network/if-pre-up.d/iptables-restore << 'EOF'
#!/bin/sh
# 恢复ipset规则
if [ -f /etc/iptables/ipset.conf ]; then
    ipset restore -f /etc/iptables/ipset.conf
fi
# 恢复iptables规则
if [ -f /etc/iptables/rules.v4 ]; then
    iptables-restore < /etc/iptables/rules.v4
fi
exit 0
EOF
        chmod +x /etc/network/if-pre-up.d/iptables-restore
    fi
}

# 备份/恢复配置
backup_restore_menu() {
    show_header
    echo -e "${GREEN}=== 备份/恢复配置 ===${NC}"
    echo ""
    echo "  1) 备份当前配置"
    echo "  2) 恢复配置"
    echo "  3) 查看备份信息"
    echo ""
    echo "  0) 返回主菜单"
    echo ""
    read -p "请选择操作: " choice
    
    case $choice in
        1)
            backup_configuration
            ;;
        2)
            restore_configuration
            ;;
        3)
            show_backup_info
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            sleep 1
            ;;
    esac
}

# 备份配置
backup_configuration() {
    local backup_dir="/root/ipwl_backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${backup_dir}/backup_${timestamp}"
    
    echo ""
    mkdir -p "$backup_path"
    
    # 备份ipset
    ipset save > "${backup_path}/ipset.conf"
    
    # 备份iptables
    iptables-save > "${backup_path}/rules.v4"
    
    echo -e "${GREEN}✓ 配置已备份到: ${backup_path}${NC}"
    read -p "按回车键继续..."
}

# 恢复配置
restore_configuration() {
    local backup_dir="/root/ipwl_backups"
    
    echo ""
    if [ ! -d "$backup_dir" ]; then
        echo -e "${YELLOW}没有找到备份目录${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    local backups=$(ls -1 "$backup_dir" 2>/dev/null)
    if [ -z "$backups" ]; then
        echo -e "${YELLOW}没有找到备份${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo "可用的备份:"
    echo ""
    local i=1
    declare -A backup_map
    while IFS= read -r backup; do
        echo "  $i) $backup"
        backup_map[$i]=$backup
        ((i++))
    done <<< "$backups"
    
    echo ""
    read -p "请选择要恢复的备份 (0取消): " choice
    
    if [ "$choice" = "0" ] || [ -z "${backup_map[$choice]}" ]; then
        echo -e "${YELLOW}操作已取消${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    local selected_backup="${backup_map[$choice]}"
    local backup_path="${backup_dir}/${selected_backup}"
    
    echo ""
    echo -e "${YELLOW}警告: 这将覆盖当前配置${NC}"
    read -p "确认恢复? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        ipset restore -f "${backup_path}/ipset.conf" 2>/dev/null
        iptables-restore < "${backup_path}/rules.v4" 2>/dev/null
        save_configuration
        echo -e "${GREEN}✓ 配置已恢复${NC}"
    else
        echo -e "${YELLOW}操作已取消${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 查看备份信息
show_backup_info() {
    local backup_dir="/root/ipwl_backups"
    
    echo ""
    if [ ! -d "$backup_dir" ]; then
        echo -e "${YELLOW}没有找到备份目录${NC}"
    else
        echo -e "${CYAN}备份位置: ${backup_dir}${NC}"
        echo ""
        ls -lh "$backup_dir" 2>/dev/null | tail -n +2
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 清理UFW冲突规则菜单
clean_ufw_menu() {
    show_header
    echo -e "${GREEN}=== 清理UFW冲突规则 ===${NC}"
    echo ""
    
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}系统未安装UFW${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    if ! ufw status 2>/dev/null | grep -q "active"; then
        echo -e "${YELLOW}UFW未启用${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    read -p "请输入要清理的端口号: " port
    
    if ! validate_port "$port"; then
        echo -e "${RED}错误: 无效的端口号${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    clean_ufw_rules "$port"
    echo ""
    read -p "按回车键继续..."
}

# 主程序
main() {
    check_root
    install_ipset
    
    while true; do
        show_main_menu
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                create_whitelist
                ;;
            2)
                manage_whitelist
                ;;
            3)
                view_all_whitelists
                ;;
            4)
                delete_whitelist
                ;;
            5)
                backup_restore_menu
                ;;
            6)
                clean_ufw_menu
                ;;
            0)
                echo ""
                echo -e "${GREEN}感谢使用，再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main
