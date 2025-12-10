#!/bin/bash

# IP黑名单管理脚本
# 使用ipset高效管理大量IP封禁规则
# 使用rc.local方式实现规则持久化

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
BLACKLIST_NAME="blacklist"
IPSET_CONF="/etc/ipset.conf"
IPTABLES_RULES="/etc/iptables.rules"

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检测系统类型
detect_system() {
    if [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

# 安装ipset
install_ipset() {
    local system=$(detect_system)
    
    echo -e "${YELLOW}正在检查ipset安装状态...${NC}"
    
    if command -v ipset &> /dev/null; then
        echo -e "${GREEN}✓ ipset已安装${NC}"
        setup_rc_local
        return 0
    fi
    
    echo -e "${YELLOW}ipset未安装，正在安装...${NC}"
    
    case $system in
        debian)
            apt-get update
            apt-get install -y ipset
            setup_rc_local
            ;;
        redhat)
            yum install -y ipset iptables-services
            ;;
        *)
            echo -e "${RED}无法识别的系统类型，请手动安装ipset${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✓ ipset安装完成${NC}"
}

# 设置rc.local自动加载规则
setup_rc_local() {
    echo -e "${YELLOW}正在配置rc.local自动加载规则...${NC}"
    
    # 创建或更新rc.local
    cat << 'RCEOF' | tee /etc/rc.local > /dev/null
#!/bin/bash

# 恢复ipset规则
if [ -f /etc/ipset.conf ]; then
    ipset restore -f /etc/ipset.conf
fi

# 恢复iptables规则
if [ -f /etc/iptables.rules ]; then
    iptables-restore < /etc/iptables.rules
fi

exit 0
RCEOF
    
    # 添加执行权限
    chmod +x /etc/rc.local
    
    # 启用systemd服务（如果系统使用systemd）
    if [ -d /etc/systemd/system ]; then
        # 检查rc-local服务是否存在
        if [ ! -f /etc/systemd/system/rc-local.service ]; then
            cat > /etc/systemd/system/rc-local.service << 'SERVICEEOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
SERVICEEOF
        fi
        
        systemctl daemon-reload 2>/dev/null
        systemctl enable rc-local.service 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ rc.local配置完成${NC}"
}

# 初始化ipset集合
init_ipset() {
    # 检查集合是否存在
    if ipset list "$BLACKLIST_NAME" &> /dev/null; then
        echo -e "${GREEN}✓ 黑名单集合已存在${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}正在创建黑名单集合...${NC}"
    ipset create "$BLACKLIST_NAME" hash:ip timeout 0
    echo -e "${GREEN}✓ 黑名单集合创建完成${NC}"
}

# 初始化iptables规则
init_iptables() {
    # 检查规则是否已存在
    if iptables -C INPUT -m set --match-set "$BLACKLIST_NAME" src -j DROP 2>/dev/null; then
        echo -e "${GREEN}✓ iptables规则已存在${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}正在添加iptables规则...${NC}"
    iptables -I INPUT -m set --match-set "$BLACKLIST_NAME" src -j DROP
    echo -e "${GREEN}✓ iptables规则添加完成${NC}"
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [ $octet -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 添加IP到黑名单
add_ips() {
    echo -e "${BLUE}请输入要封禁的IP地址（多个IP用空格分隔）:${NC}"
    read -r ip_input
    
    if [[ -z "$ip_input" ]]; then
        echo -e "${RED}错误: 未输入任何IP地址${NC}"
        return 1
    fi
    
    local success_count=0
    local fail_count=0
    
    for ip in $ip_input; do
        if ! validate_ip "$ip"; then
            echo -e "${RED}✗ 无效的IP地址: $ip${NC}"
            fail_count=$((fail_count + 1))
            continue
        fi
        
        # 检查IP是否已存在
        if ipset test "$BLACKLIST_NAME" "$ip" 2>/dev/null; then
            echo -e "${YELLOW}⚠ IP已在黑名单中: $ip${NC}"
            continue
        fi
        
        # 添加IP
        if ipset add "$BLACKLIST_NAME" "$ip" 2>/dev/null; then
            echo -e "${GREEN}✓ 成功封禁: $ip${NC}"
            success_count=$((success_count + 1))
        else
            echo -e "${RED}✗ 封禁失败: $ip${NC}"
            fail_count=$((fail_count + 1))
        fi
    done
    
    echo ""
    echo -e "${GREEN}成功: $success_count${NC} | ${RED}失败: $fail_count${NC}"
    
    if [ $success_count -gt 0 ]; then
        save_rules
    fi
}

# 删除IP从黑名单
remove_ips() {
    echo -e "${BLUE}请输入要解封的IP地址（多个IP用空格分隔）:${NC}"
    read -r ip_input
    
    if [[ -z "$ip_input" ]]; then
        echo -e "${RED}错误: 未输入任何IP地址${NC}"
        return 1
    fi
    
    local success_count=0
    local fail_count=0
    
    for ip in $ip_input; do
        if ! validate_ip "$ip"; then
            echo -e "${RED}✗ 无效的IP地址: $ip${NC}"
            fail_count=$((fail_count + 1))
            continue
        fi
        
        # 检查IP是否存在
        if ! ipset test "$BLACKLIST_NAME" "$ip" 2>/dev/null; then
            echo -e "${YELLOW}⚠ IP不在黑名单中: $ip${NC}"
            continue
        fi
        
        # 删除IP
        if ipset del "$BLACKLIST_NAME" "$ip" 2>/dev/null; then
            echo -e "${GREEN}✓ 成功解封: $ip${NC}"
            success_count=$((success_count + 1))
        else
            echo -e "${RED}✗ 解封失败: $ip${NC}"
            fail_count=$((fail_count + 1))
        fi
    done
    
    echo ""
    echo -e "${GREEN}成功: $success_count${NC} | ${RED}失败: $fail_count${NC}"
    
    if [ $success_count -gt 0 ]; then
        save_rules
    fi
}

# 查看黑名单
view_blacklist() {
    echo -e "${BLUE}======== 当前黑名单 ========${NC}"
    
    local count=$(ipset list "$BLACKLIST_NAME" | grep -c "^[0-9]" || echo 0)
    
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}黑名单为空${NC}"
    else
        echo -e "${GREEN}共有 $count 个IP被封禁:${NC}"
        echo ""
        ipset list "$BLACKLIST_NAME" | grep "^[0-9]" | nl
    fi
    
    echo -e "${BLUE}============================${NC}"
}

# 保存规则
save_rules() {
    echo -e "${YELLOW}正在保存规则...${NC}"
    
    # 保存ipset规则
    ipset save > "$IPSET_CONF"
    
    # 保存iptables规则
    iptables-save > "$IPTABLES_RULES"
    
    echo -e "${GREEN}✓ 规则已保存${NC}"
}

# 清空黑名单
clear_blacklist() {
    echo -e "${RED}警告: 此操作将清空所有黑名单IP!${NC}"
    echo -e "${YELLOW}确认清空? (yes/no):${NC}"
    read -r confirm
    
    if [[ "$confirm" == "yes" ]]; then
        ipset flush "$BLACKLIST_NAME"
        save_rules
        echo -e "${GREEN}✓ 黑名单已清空${NC}"
    else
        echo -e "${YELLOW}操作已取消${NC}"
    fi
}

# 屏蔽AmazonBot爬虫
block_amazonbot() {
    echo -e "${YELLOW}正在从GitHub下载AmazonBot IP列表...${NC}"
    
    local url="https://raw.githubusercontent.com/woniu336/open_shell/main/amazonbot_ips.txt"
    local temp_file="/tmp/amazonbot_ips.txt"
    
    # 下载IP列表
    if command -v curl &> /dev/null; then
        curl -sSL "$url" -o "$temp_file"
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$temp_file"
    else
        echo -e "${RED}错误: 系统中未找到curl或wget，请先安装${NC}"
        return 1
    fi
    
    if [[ ! -f "$temp_file" ]]; then
        echo -e "${RED}错误: 下载失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 下载完成${NC}"
    echo -e "${YELLOW}正在批量封禁AmazonBot IP...${NC}"
    
    local total=0
    local success_count=0
    local skip_count=0
    local fail_count=0
    
    # 读取并处理每个IP
    while IFS= read -r ip || [[ -n "$ip" ]]; do
        # 跳过空行和注释
        [[ -z "$ip" || "$ip" =~ ^[[:space:]]*# ]] && continue
        
        # 去除首尾空格
        ip=$(echo "$ip" | xargs)
        
        total=$((total + 1))
        
        # 验证IP格式
        if ! validate_ip "$ip"; then
            echo -e "${RED}✗ 无效的IP: $ip${NC}"
            fail_count=$((fail_count + 1))
            continue
        fi
        
        # 检查IP是否已存在
        if ipset test "$BLACKLIST_NAME" "$ip" 2>/dev/null; then
            skip_count=$((skip_count + 1))
            continue
        fi
        
        # 添加IP
        if ipset add "$BLACKLIST_NAME" "$ip" 2>/dev/null; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done < "$temp_file"
    
    # 删除临时文件
    rm -f "$temp_file"
    
    echo ""
    echo -e "${BLUE}总计: $total 个IP${NC}"
    echo -e "${GREEN}✓ 成功封禁: $success_count${NC}"
    echo -e "${YELLOW}⚠ 已存在跳过: $skip_count${NC}"
    echo -e "${RED}✗ 失败: $fail_count${NC}"
    
    if [ $success_count -gt 0 ]; then
        save_rules
        echo -e "${GREEN}✓ AmazonBot爬虫已屏蔽${NC}"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}    IP黑名单管理工具${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    echo "1. 添加IP到黑名单"
    echo "2. 从黑名单删除IP"
    echo "3. 查看黑名单"
    echo "4. 清空黑名单"
    echo "5. 屏蔽AmazonBot爬虫"
    echo "0. 退出"
    echo ""
    echo -e "${BLUE}================================${NC}"
}

# 主函数
main() {
    check_root
    install_ipset
    init_ipset
    init_iptables
    
    while true; do
        show_menu
        echo -e "${BLUE}请选择操作 [0-5]:${NC}"
        read -r choice
        
        case $choice in
            1)
                add_ips
                ;;
            2)
                remove_ips
                ;;
            3)
                view_blacklist
                ;;
            4)
                clear_blacklist
                ;;
            5)
                block_amazonbot
                ;;
            0)
                echo -e "${GREEN}再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                ;;
        esac
        
        echo ""
        echo -e "${YELLOW}按回车键继续...${NC}"
        read -r
    done
}

# 运行主函数
main
