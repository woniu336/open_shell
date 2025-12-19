#!/bin/bash

# Fail2Ban 自动安装配置脚本 (Debian/Ubuntu专用版)

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 样式定义
BOLD='\033[1m'
UNDERLINE='\033[4m'
RESET='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 打印分隔线
print_separator() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
}

# 打印标题
print_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║             Fail2Ban 自动安装配置工具               ║"
    echo "║                Debian/Ubuntu 专用版                 ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# 等待用户按键
press_any_key() {
    echo ""
    echo -e "${YELLOW}按回车键继续...${NC}"
    read
}

# 检查系统类型
check_os() {
    if [[ ! -f /etc/debian_version ]]; then
        print_header
        log_error "此脚本仅支持Debian/Ubuntu系统"
        exit 1
    fi
}

# 检查是否以root运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_header
        log_error "此脚本必须以root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 安装Fail2Ban
install_fail2ban() {
    if command -v fail2ban-server &> /dev/null; then
        log_info "Fail2Ban 已经安装"
        return 0
    fi
    
    print_header
    echo -e "${CYAN}${BOLD}安装Fail2Ban和rsyslog${RESET}"
    print_separator
    
    log_info "开始安装Fail2Ban和rsyslog..."
    
    # 更新源并安装
    echo ""
    echo -e "${YELLOW}正在更新软件源...${NC}"
    apt update
    
    echo ""
    echo -e "${YELLOW}正在安装fail2ban和rsyslog...${NC}"
    apt install -y fail2ban rsyslog
    
    # 检查安装是否成功
    if ! command -v fail2ban-server &> /dev/null; then
        log_error "Fail2Ban 安装失败"
        exit 1
    fi
    
    log_info "Fail2Ban 和 rsyslog 安装成功"
}

# 配置Nginx过滤器
configure_nginx_filters() {
    print_header
    echo -e "${CYAN}${BOLD}配置Nginx过滤器${RESET}"
    print_separator
    
    log_info "配置Nginx过滤器..."
    
    # 1. 防恶意扫描过滤器
    cat > /etc/fail2ban/filter.d/nginx-bad-request.conf << 'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD) .*\.(php|asp|aspx|jsp|cgi|env|git|yml|sql|bak|tar|gz|zip|rar|sh) HTTP.*" (400|401|403|404|444)
           ^<HOST> - - \[.*\] "(GET|POST|HEAD) .*/(phpmyadmin|admin|setup|manager|dashboard|wp-login|xmlrpc).* HTTP.*" (400|401|403|404|444)
           ^<HOST> - - \[.*\] "(GET|POST) .*/\.\.\/.* HTTP.*" (400|401|403|404|444)
           ^<HOST> - - \[.*\] "(POST) .*(php://input).* HTTP.*" (400|401|403|404|444)
           ^<HOST> - - \[.*\] "PROPFIND .* HTTP.*" (400|401|403|404|444)
           ^<HOST> - - \[.*\] "(GET|POST) .*(%%2e|%%2f|%%25).* HTTP.*" (400|401|403|404|444)
           ^<HOST> - - \[.*\] "CONNECT .*:\d+ HTTP.*" (400|444)
           ^<HOST> - - \[.*\] "GET .* HTTP.*" (400|401|403|404|444) .*"(zgrab|Nuclei|nikto|sqlmap|wpscan|Wfuzz)"
           ^<HOST> - - \[.*\] "[^[:print:]]{3,}" (400|444)
           ^<HOST> - - \[.*\] "\xA0\x05\x00.*HTTP.*" 400
           ^<HOST> - - \[.*\] "^[^A-Za-z]" (400|444)

datepattern = ^[^\[]*\[({DATE})
{DAY} {MON} {YEAR} {HOUR}:{MIN}:{SEC} {TZ}

ignoreregex = ^<HOST> - - \[.*\] ".*" 200
EOF
    
    # 2. 防CC攻击过滤器
    cat > /etc/fail2ban/filter.d/nginx-cc.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* HTTP.* (403|429) .*$ 
ignoreregex = ^.*(\/(?:robots\.txt|favicon\.ico|.*\.(?:jpg|png|gif|jpeg|svg|webp|bmp|tiff|css|js|woff|woff2|eot|ttf|otf))$)
EOF
    
    log_info "Nginx过滤器配置完成"
}

# 配置Jail规则
configure_jail() {
    print_header
    echo -e "${CYAN}${BOLD}配置Jail规则${RESET}"
    print_separator
    
    # 备份原有配置
    if [ -f /etc/fail2ban/jail.local ]; then
        cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.$(date +%Y%m%d%H%M%S)
        log_info "已备份原有 jail.local 配置"
    fi
    
    # 创建基础jail.local配置
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
ignoreip = 127.0.0.1/8 192.168.0.0/16 10.0.0.0/8
bantime  = 1h
findtime = 15m
maxretry = 10
banaction = ufw

# ==========================================
# Nginx 规则 1：防止恶意扫描
# ==========================================
[nginx-bad-request]
enabled  = true
logpath  = /var/log/nginx/access.log
filter   = nginx-bad-request
port     = 80,443
maxretry = 5
bantime  = 24h

# ==========================================
# Nginx 规则 2：防止 CC 攻击
# ==========================================
[nginx-cc]
enabled  = true
port     = 80,443
logpath  = /var/log/nginx/access.log
filter   = nginx-cc
findtime = 300
maxretry = 10
bantime  = 2h

# ==========================================
# SSH 保护规则
# ==========================================
[sshd]
ignoreip = 127.0.0.1/8
enabled = true
filter = sshd
port = 22
maxretry = 3
findtime = 300
bantime = -1
banaction = ufw
logpath = /var/log/auth.log
EOF
    
    echo ""
    log_info "Jail规则配置完成"
    
    # 简单的SSH端口提示
    echo -e "${YELLOW}提示：SSH端口默认为22，如需修改请在安装后编辑配置文件${NC}"
    
    press_any_key
}

# 重启服务
restart_services() {
    print_header
    echo -e "${CYAN}${BOLD}重启Fail2Ban服务${RESET}"
    print_separator
    
    log_info "重启Fail2Ban服务..."
    
    systemctl restart fail2ban
    
    if systemctl is-active --quiet fail2ban; then
        log_info "Fail2Ban 服务启动成功"
    else
        log_error "Fail2Ban 服务启动失败"
        systemctl status fail2ban --no-pager
        exit 1
    fi
}

# 卸载Fail2Ban
uninstall_fail2ban() {
    print_header
    echo -e "${RED}${BOLD}卸载Fail2Ban${RESET}"
    print_separator
    
    echo -e "${YELLOW}警告：此操作将完全卸载Fail2Ban并删除所有配置${NC}"
    echo ""
    echo "将要执行的操作："
    echo "1. 停止Fail2Ban服务"
    echo "2. 禁用开机启动"
    echo "3. 卸载Fail2Ban软件包"
    echo "4. 清理残留文件"
    echo "5. 删除配置文件"
    echo ""
    
    read -p "确定要卸载Fail2Ban吗？[y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}取消卸载操作${NC}"
        press_any_key
        return
    fi
    
    echo ""
    echo -e "${YELLOW}开始卸载Fail2Ban...${NC}"
    print_separator
    
    # 1. 停止服务
    echo -e "${GREEN}[1/6] 停止Fail2Ban服务...${NC}"
    systemctl stop fail2ban 2>/dev/null || true
    
    # 2. 禁用开机启动
    echo -e "${GREEN}[2/6] 禁用开机启动...${NC}"
    systemctl disable fail2ban 2>/dev/null || true
    
    # 3. 卸载软件包
    echo -e "${GREEN}[3/6] 卸载Fail2Ban软件包...${NC}"
    apt-get remove --purge -y fail2ban
    
    # 4. 清理依赖包
    echo -e "${GREEN}[4/6] 清理无用依赖包...${NC}"
    apt-get autoremove -y
    
    # 5. 清理包缓存
    echo -e "${GREEN}[5/6] 清理包缓存...${NC}"
    apt-get clean
    
    # 6. 删除配置文件和日志
    echo -e "${GREEN}[6/6] 删除配置文件和日志...${NC}"
    
    # 删除主配置文件
    rm -f /etc/fail2ban/jail.local
    rm -f /etc/fail2ban/jail.local.bak.* 2>/dev/null || true
    
    # 删除自定义过滤器
    rm -f /etc/fail2ban/filter.d/nginx-bad-request.conf
    rm -f /etc/fail2ban/filter.d/nginx-cc.conf
    
    # 删除日志文件
    rm -f /var/log/fail2ban.log 2>/dev/null || true
    rm -f /var/log/fail2ban.log.1 2>/dev/null || true
    rm -f /var/log/fail2ban.* 2>/dev/null || true
    
    # 删除数据文件
    rm -rf /var/lib/fail2ban
    
    # 删除锁文件
    rm -f /var/run/fail2ban/fail2ban.sock 2>/dev/null || true
    rm -f /var/run/fail2ban/fail2ban.pid 2>/dev/null || true
    
    # 删除配置文件目录（如果为空）
    if [ -d /etc/fail2ban ]; then
        if [ -z "$(ls -A /etc/fail2ban 2>/dev/null)" ]; then
            rm -rf /etc/fail2ban
        fi
    fi
    
    print_separator
    echo -e "${GREEN}${BOLD}Fail2Ban 已完全卸载${NC}"
    echo ""
    echo -e "${YELLOW}建议重启系统以确保所有更改生效${NC}"
    echo ""
    
    press_any_key
}

# 手动编辑jail.local配置文件
edit_jail_config() {
    print_header
    echo -e "${CYAN}${BOLD}编辑Fail2Ban配置${RESET}"
    print_separator
    
    echo -e "${YELLOW}提示：${NC}"
    echo "1. 修改SSH端口：找到 [sshd] 段的 port = 22，改为您的实际端口"
    echo "2. 保存后需要重启Fail2Ban服务"
    echo ""
    
    read -p "按回车键开始编辑或按Ctrl+C取消..."
    
    if command -v nano &> /dev/null; then
        nano /etc/fail2ban/jail.local
    elif command -v vim &> /dev/null; then
        vim /etc/fail2ban/jail.local
    elif command -v vi &> /dev/null; then
        vi /etc/fail2ban/jail.local
    else
        log_error "未找到可用的文本编辑器"
        press_any_key
        return 1
    fi
    
    # 询问是否重启服务
    echo ""
    read -p "配置已保存，是否重启Fail2Ban服务使配置生效？[Y/n]: " restart_choice
    
    if [[ "$restart_choice" =~ ^[Nn]$ ]]; then
        log_warn "请记得手动重启Fail2Ban服务: sudo systemctl restart fail2ban"
    else
        systemctl restart fail2ban
        if systemctl is-active --quiet fail2ban; then
            log_info "Fail2Ban 服务重启成功"
        else
            log_error "Fail2Ban 服务重启失败"
            systemctl status fail2ban --no-pager
        fi
    fi
    
    press_any_key
}

# 查看封禁状态
view_status() {
    while true; do
        print_header
        echo -e "${CYAN}${BOLD}查看封禁状态${RESET}"
        print_separator
        
        echo -e "${MAGENTA}${BOLD}请选择要查看的监狱：${RESET}"
        echo ""
        echo -e "${GREEN}[1]${NC} 查看所有监狱状态"
        echo -e "${GREEN}[2]${NC} 查看SSH监狱状态"
        echo -e "${GREEN}[3]${NC} 查看Nginx恶意扫描监狱状态"
        echo -e "${GREEN}[4]${NC} 查看Nginx CC攻击监狱状态"
        echo -e "${YELLOW}[0]${NC} 返回主菜单"
        echo ""
        
        read -p "请输入选项 [0-4]: " choice
        
        case $choice in
            1)
                echo ""
                echo -e "${CYAN}════════════ 所有监狱状态 ════════════${NC}"
                fail2ban-client status
                ;;
            2)
                echo ""
                echo -e "${CYAN}════════════ SSH监狱状态 ════════════${NC}"
                fail2ban-client status sshd
                ;;
            3)
                echo ""
                echo -e "${CYAN}════════════ Nginx恶意扫描监狱状态 ════════════${NC}"
                fail2ban-client status nginx-bad-request
                ;;
            4)
                echo ""
                echo -e "${CYAN}════════════ Nginx CC攻击监狱状态 ════════════${NC}"
                fail2ban-client status nginx-cc
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                sleep 1
                continue
                ;;
        esac
        
        press_any_key
    done
}

# 手动解封IP
unban_ip() {
    print_header
    echo -e "${CYAN}${BOLD}手动解封IP${RESET}"
    print_separator
    
    while true; do
        echo -e "${YELLOW}请输入要解封的IP地址 (例如: 192.168.1.100)${NC}"
        echo -e "${YELLOW}输入 'q' 返回主菜单${NC}"
        echo ""
        read -p "IP地址: " ip_address
        
        if [[ "$ip_address" == "q" ]]; then
            return
        fi
        
        # 验证IP地址格式
        if [[ ! $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}无效的IP地址格式，请重新输入${NC}"
            sleep 1
            continue
        fi
        
        echo ""
        echo -e "${MAGENTA}${BOLD}请选择要解封的监狱：${RESET}"
        echo ""
        echo -e "${GREEN}[1]${NC} SSH监狱 (sshd)"
        echo -e "${GREEN}[2]${NC} Nginx恶意扫描监狱 (nginx-bad-request)"
        echo -e "${GREEN}[3]${NC} Nginx CC攻击监狱 (nginx-cc)"
        echo -e "${GREEN}[4]${NC} 从所有监狱解封"
        echo -e "${YELLOW}[0]${NC} 返回"
        echo ""
        
        read -p "请选择 [0-4]: " choice
        
        case $choice in
            1)
                fail2ban-client set sshd unbanip "$ip_address"
                log_info "已从SSH监狱解封IP: $ip_address"
                ;;
            2)
                fail2ban-client set nginx-bad-request unbanip "$ip_address"
                log_info "已从Nginx恶意扫描监狱解封IP: $ip_address"
                ;;
            3)
                fail2ban-client set nginx-cc unbanip "$ip_address"
                log_info "已从Nginx CC攻击监狱解封IP: $ip_address"
                ;;
            4)
                fail2ban-client set sshd unbanip "$ip_address"
                fail2ban-client set nginx-bad-request unbanip "$ip_address"
                fail2ban-client set nginx-cc unbanip "$ip_address"
                log_info "已从所有监狱解封IP: $ip_address"
                ;;
            0)
                continue
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
        
        press_any_key
        break
    done
}

# 查看被封禁的IP列表
view_banned_ips() {
    while true; do
        print_header
        echo -e "${CYAN}${BOLD}查看被封禁的IP列表${RESET}"
        print_separator
        
        echo -e "${MAGENTA}${BOLD}请选择要查看的监狱：${RESET}"
        echo ""
        echo -e "${GREEN}[1]${NC} SSH监狱被封禁IP"
        echo -e "${GREEN}[2]${NC} Nginx恶意扫描监狱被封禁IP"
        echo -e "${GREEN}[3]${NC} Nginx CC攻击监狱被封禁IP"
        echo -e "${YELLOW}[0]${NC} 返回主菜单"
        echo ""
        
        read -p "请输入选项 [0-3]: " choice
        
        case $choice in
            1)
                echo ""
                echo -e "${CYAN}════════════ SSH监狱被封禁IP ════════════${NC}"
                fail2ban-client get sshd banned
                ;;
            2)
                echo ""
                echo -e "${CYAN}════════════ Nginx恶意扫描监狱被封禁IP ════════════${NC}"
                fail2ban-client get nginx-bad-request banned
                ;;
            3)
                echo ""
                echo -e "${CYAN}════════════ Nginx CC攻击监狱被封禁IP ════════════${NC}"
                fail2ban-client get nginx-cc banned
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                sleep 1
                continue
                ;;
        esac
        
        press_any_key
    done
}

# 一键安装配置
auto_install() {
    print_header
    check_os
    check_root
    
    echo -e "${CYAN}${BOLD}开始一键安装配置Fail2Ban${RESET}"
    print_separator
    
    install_fail2ban
    configure_nginx_filters
    configure_jail
    restart_services
    
    print_header
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║            Fail2Ban 安装配置完成！                 ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}已安装的防护规则：${NC}"
    echo -e "${GREEN}✓${NC} SSH暴力破解防护"
    echo -e "${GREEN}✓${NC} Nginx恶意文件扫描防护"
    echo -e "${GREEN}✓${NC} Nginx CC攻击防护"
    echo ""
    
    # 简洁的SSH端口提示
    echo -e "${YELLOW}提示：${NC}"
    echo "SSH端口默认为22，如需修改请使用菜单选项2编辑配置文件"
    echo ""
    
    echo -e "${YELLOW}常用命令：${NC}"
    echo -e "查看状态：${CYAN}fail2ban-client status${NC}"
    echo -e "查看SSH监狱：${CYAN}fail2ban-client status sshd${NC}"
    
    press_any_key
}

# 主菜单
main_menu() {
    while true; do
        print_header
        
        # 显示系统信息
        echo -e "${CYAN}系统信息：${NC}"
        echo -e "系统: ${GREEN}$(lsb_release -ds 2>/dev/null || echo "Debian/Ubuntu")${NC}"
        echo -e "Fail2Ban: ${GREEN}$(command -v fail2ban-server &>/dev/null && echo "已安装" || echo "未安装")${NC}"
        print_separator
        
        echo -e "${MAGENTA}${BOLD}主菜单${RESET}"
        echo ""
        echo -e "${GREEN}[1]${NC} 一键安装配置Fail2Ban"
        echo -e "${GREEN}[2]${NC} 编辑配置文件"
        echo -e "${GREEN}[3]${NC} 查看封禁状态"
        echo -e "${GREEN}[4]${NC} 查看被封禁IP"
        echo -e "${GREEN}[5]${NC} 手动解封IP"
        echo -e "${GREEN}[6]${NC} 重启Fail2Ban"
        echo -e "${GREEN}[7]${NC} 查看Fail2Ban日志"
        echo -e "${RED}[8]${NC} 卸载Fail2Ban"
        echo -e "${RED}[0]${NC} 退出"
        echo ""
        
        read -p "请输入选项 [0-8]: " choice
        
        case $choice in
            1)
                auto_install
                ;;
            2)
                edit_jail_config
                ;;
            3)
                view_status
                ;;
            4)
                view_banned_ips
                ;;
            5)
                unban_ip
                ;;
            6)
                print_header
                echo -e "${CYAN}${BOLD}重启Fail2Ban服务${RESET}"
                print_separator
                systemctl restart fail2ban
                if systemctl is-active --quiet fail2ban; then
                    log_info "Fail2Ban 服务已重启"
                else
                    log_error "Fail2Ban 服务重启失败"
                fi
                press_any_key
                ;;
            7)
                print_header
                echo -e "${CYAN}${BOLD}查看Fail2Ban日志${RESET}"
                print_separator
                echo -e "${YELLOW}最近20条日志：${NC}"
                journalctl -u fail2ban -n 20 --no-pager
                press_any_key
                ;;
            8)
                uninstall_fail2ban
                ;;
            0)
                print_header
                echo -e "${GREEN}感谢使用，再见！${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 主函数 - 直接运行显示菜单
main() {
    check_os
    check_root
    main_menu
}

# 运行主函数
main
