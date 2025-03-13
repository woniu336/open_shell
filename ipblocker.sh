#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 root 权限运行此脚本${NC}"
    exit 1
fi

# 检查必要的命令
check_requirements() {
    local missing_tools=()
    for tool in ipset iptables wget awk logger; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}缺少必要的工具: ${missing_tools[*]}${NC}"
        echo "请安装缺少的工具："
        echo "Debian/Ubuntu: apt-get install iptables ipset"
        echo "CentOS/RHEL: yum install iptables ipset"
        exit 1
    fi
}

# 初始化防火墙
init_firewall() {
    echo -e "${YELLOW}正在初始化防火墙规则...${NC}"
    
    # 检查并删除已存在的规则
    ipset list banned_ips >/dev/null 2>&1 && ipset destroy banned_ips
    
    # 创建新的 ipset
    ipset create banned_ips hash:ip hashsize 65536 maxelem 1000000
    
    # 设置 iptables 规则
    iptables -N BANNED 2>/dev/null || true
    iptables -I FORWARD -j BANNED 2>/dev/null || true
    iptables -I INPUT -j BANNED 2>/dev/null || true
    iptables -I BANNED -m set --match-set banned_ips src -j DROP 2>/dev/null || true
    
    echo -e "${GREEN}防火墙规则初始化完成${NC}"
}

# 更新黑名单的核心功能
update_blacklist_core() {
    local silent_mode=$1
    cd /root/cron || exit 1

    [[ "$silent_mode" != "silent" ]] && echo "正在下载黑名单文件..."
    if ! wget -q https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-1d.ipv4 -O abuseipdb-s100-1d.ipv4.tmp; then
        [[ "$silent_mode" != "silent" ]] && echo -e "${RED}下载失败，使用上次的黑名单${NC}"
        logger "下载失败，使用上次的黑名单"
        return 1
    fi

    if [ ! -s abuseipdb-s100-1d.ipv4.tmp ]; then
        [[ "$silent_mode" != "silent" ]] && echo -e "${RED}下载文件为空${NC}"
        logger "下载文件为空，使用上次的黑名单"
        rm -f abuseipdb-s100-1d.ipv4.tmp
        return 1
    fi

    mv abuseipdb-s100-1d.ipv4.tmp abuseipdb-s100-1d.ipv4

    [[ "$silent_mode" != "silent" ]] && echo "正在处理 IP 列表..."
    # 检查并删除已存在的临时 ipset
    ipset list banned_ips.tmp >/dev/null 2>&1 && ipset destroy banned_ips.tmp

    # 创建临时 ipset
    ipset create banned_ips.tmp hash:ip hashsize 65536 maxelem 1000000

    # 提取有效IP到临时文件
    awk '!/^#/ && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $1 }' abuseipdb-s100-1d.ipv4 > valid_ips.tmp

    # 使用 ipset restore 批量添加
    while read -r ip; do
        echo "add banned_ips.tmp $ip"
    done < valid_ips.tmp | ipset restore -!

    # 清理临时文件
    rm -f valid_ips.tmp

    # 原子性地替换 ipset
    ipset swap banned_ips.tmp banned_ips
    ipset destroy banned_ips.tmp

    [[ "$silent_mode" != "silent" ]] && echo -e "${GREEN}IP 黑名单更新完成${NC}"
    logger "IP 黑名单更新完成"
}

# 命令行模式更新黑名单
cli_update() {
    logger "开始更新 IP 黑名单"
    update_blacklist_core "silent"
}

# 交互式更新 IP 黑名单
update_blacklist() {
    echo -e "${YELLOW}正在更新 IP 黑名单...${NC}"
    update_blacklist_core
}

# 创建定时任务脚本
create_cron_scripts() {
    echo -e "${YELLOW}正在创建定时任务脚本...${NC}"
    
    # 创建 ban_at_boot.sh
    cat > /root/cron/ban_at_boot.sh << 'EOF'
#!/bin/bash
set -e  # 遇到错误立即退出
cd /root/cron || exit 1

# 检查 Docker 是否真正启动
while ! docker info >/dev/null 2>&1; do
    echo "等待 Docker 启动..."
    sleep 2
done

# 检查 ipset 是否已存在，如存在则删除
ipset list banned_ips >/dev/null 2>&1 && ipset destroy banned_ips

# 创建 ipset 集合
ipset create banned_ips hash:ip hashsize 65536 maxelem 1000000

# 设置 iptables 规则
iptables -N BANNED 2>/dev/null || true
iptables -I FORWARD -j BANNED 2>/dev/null || true
iptables -I INPUT -j BANNED 2>/dev/null || true
iptables -I BANNED -m set --match-set banned_ips src -j DROP 2>/dev/null || true

# 下载并处理 IP 黑名单
wget -q https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-1d.ipv4 -O abuseipdb-s100-1d.ipv4.tmp

if [ -s abuseipdb-s100-1d.ipv4.tmp ]; then
    mv abuseipdb-s100-1d.ipv4.tmp abuseipdb-s100-1d.ipv4
    awk '!/^#/ && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $1 }' abuseipdb-s100-1d.ipv4 | while IFS= read -r line; do
        ipset add banned_ips "$line"
    done
fi
EOF

    # 创建 ban.sh
    cat > /root/cron/ban.sh << 'EOF'
#!/bin/bash
set -e
cd /root/cron || exit 1

# 添加日志
logger "开始更新 IP 黑名单"

# 下载失败时使用备份文件
if ! wget -q https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-1d.ipv4 -O abuseipdb-s100-1d.ipv4.tmp; then
    logger "下载失败，使用上次的黑名单"
    exit 1
fi

# 验证下载文件
if [ -s abuseipdb-s100-1d.ipv4.tmp ]; then
    mv abuseipdb-s100-1d.ipv4.tmp abuseipdb-s100-1d.ipv4
else
    logger "下载文件为空，使用上次的黑名单"
    rm -f abuseipdb-s100-1d.ipv4.tmp
    exit 1
fi

# 创建临时 ipset
ipset create banned_ips.tmp hash:ip hashsize 65536 maxelem 1000000

# 填充临时 ipset
awk '!/^#/ && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $1 }' abuseipdb-s100-1d.ipv4 | while IFS= read -r line; do
    ipset add banned_ips.tmp "$line"
done

# 原子性地替换 ipset
ipset swap banned_ips.tmp banned_ips
ipset destroy banned_ips.tmp

logger "IP 黑名单更新完成"
EOF

    # 设置执行权限
    chmod +x /root/cron/ban_at_boot.sh
    chmod +x /root/cron/ban.sh
    
    echo -e "${GREEN}定时任务脚本创建完成${NC}"
}

# 设置定时任务
setup_cron() {
    echo -e "${YELLOW}正在设置定时任务...${NC}"
    
    # 首先创建定时任务脚本
    create_cron_scripts
    
    # 检查是否已经存在相关定时任务
    if crontab -l 2>/dev/null | grep -q "/root/cron/ban"; then
        echo -e "${RED}定时任务已存在${NC}"
        return 1
    fi
    
    # 添加定时任务
    (crontab -l 2>/dev/null; echo "0 5 * * * /bin/bash /root/cron/ban.sh") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot /bin/bash /root/cron/ban_at_boot.sh") | crontab -
    
    echo -e "${GREEN}定时任务设置完成${NC}"
}

# 清理所有规则
cleanup_rules() {
    echo -e "${YELLOW}正在清理防火墙规则...${NC}"
    
    iptables -D BANNED -m set --match-set banned_ips src -j DROP 2>/dev/null || true
    iptables -D INPUT -j BANNED 2>/dev/null || true
    iptables -D FORWARD -j BANNED 2>/dev/null || true
    iptables -X BANNED 2>/dev/null || true
    ipset destroy banned_ips 2>/dev/null || true
    
    echo -e "${GREEN}防火墙规则已清理${NC}"
}

# 显示当前状态
show_status() {
    echo -e "${YELLOW}当前状态：${NC}"
    echo "----------------------------------------"
    echo -e "${GREEN}IPSet 规则：${NC}"
    if ipset list banned_ips >/dev/null 2>&1; then
        echo "已创建 IPSet 规则"
        echo "当前黑名单 IP 数量: $(ipset list banned_ips | grep -c "^[0-9]")"
    else
        echo "未创建 IPSet 规则"
    fi
    echo "----------------------------------------"
    echo -e "${GREEN}IPTables 规则：${NC}"
    iptables -L BANNED 2>/dev/null || echo "未创建 IPTables 规则"
    echo "----------------------------------------"
    echo -e "${GREEN}定时任务：${NC}"
    crontab -l | grep "/root/cron/ban" || echo "未设置定时任务"
    echo "----------------------------------------"
}

# 显示黑名单详情
show_blacklist() {
    echo -e "${YELLOW}IP 黑名单详情：${NC}"
    if ipset list banned_ips >/dev/null 2>&1; then
        local ip_count=$(ipset list banned_ips | grep -c "^[0-9]")
        echo -e "${GREEN}当前黑名单共有 ${ip_count} 个 IP${NC}"
        
        echo -e "\n是否要查看完整的 IP 列表？[y/N]"
        read -r show_full
        if [[ "$show_full" =~ ^[Yy]$ ]]; then
            echo -e "\n${YELLOW}黑名单 IP 列表：${NC}"
            ipset list banned_ips | grep "^[0-9]"
        fi
    else
        echo -e "${RED}黑名单未创建或为空${NC}"
    fi
}

# 显示拦截统计信息
show_block_stats() {
    echo -e "${YELLOW}拦截统计信息：${NC}"
    echo "----------------------------------------"
    if iptables -L BANNED -n -v -x >/dev/null 2>&1; then
        echo -e "${GREEN}详细拦截记录：${NC}"
        iptables -L BANNED -n -v -x
    else
        echo -e "${RED}未找到 BANNED 链或没有拦截记录${NC}"
    fi
    echo "----------------------------------------"
}

# 管理单个 IP
manage_single_ip() {
    while true; do
        clear
        echo -e "${YELLOW}IP 黑名单管理${NC}"
        echo "1. 添加 IP 到黑名单"
        echo "2. 从黑名单移除 IP"
        echo "3. 查看拦截统计"
        echo "0. 返回主菜单"
        
        read -rp "请选择操作 [0-3]: " op_choice
        
        case $op_choice in
            1)
                read -rp "请输入要封禁的 IP 地址: " ip_addr
                if [[ $ip_addr =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    if ipset add banned_ips "$ip_addr" 2>/dev/null; then
                        echo -e "${GREEN}成功将 $ip_addr 添加到黑名单${NC}"
                        logger "手动添加 IP $ip_addr 到黑名单"
                    else
                        echo -e "${RED}添加失败，IP 可能已在黑名单中${NC}"
                    fi
                else
                    echo -e "${RED}无效的 IP 地址格式${NC}"
                fi
                ;;
            2)
                read -rp "请输入要解封的 IP 地址: " ip_addr
                if [[ $ip_addr =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    if ipset del banned_ips "$ip_addr" 2>/dev/null; then
                        echo -e "${GREEN}成功将 $ip_addr 从黑名单中移除${NC}"
                        logger "手动从黑名单移除 IP $ip_addr"
                    else
                        echo -e "${RED}移除失败，IP 可能不在黑名单中${NC}"
                    fi
                else
                    echo -e "${RED}无效的 IP 地址格式${NC}"
                fi
                ;;
            3)
                show_block_stats
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                ;;
        esac
        
        echo -e "\n按回车键继续..."
        read -r
    done
}

# 主菜单
show_menu() {
    while true; do
        clear
        echo -e "\n${YELLOW}=== IP 黑名单防火墙管理系统 ===${NC}"
        echo "1. 初始化"
        echo "2. 更新"
        echo "3. 定时任务"
        echo "4. 清理"
        echo "5. 显示状态"
        echo "6. 管理单个 IP"
        echo "0. 退出"
        
        read -rp "请选择操作 [0-6]: " choice
        
        case $choice in
            1) init_firewall ;;
            2) update_blacklist ;;
            3) setup_cron ;;
            4) cleanup_rules ;;
            5) show_status ;;
            6) manage_single_ip ;;
            0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        
        echo -e "\n按回车键继续..."
        read -r
    done
}

# 主程序
main() {
    # 检查是否有命令行参数
    if [ "$1" = "update" ]; then
        cli_update
        exit 0
    fi

    # 创建必要的目录
    mkdir -p /root/cron
    
    # 检查必要的命令
    check_requirements
    
    # 显示菜单
    show_menu
}

main "$@" 