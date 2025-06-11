#!/bin/bash

# HAProxy域名路由配置管理脚本
# 作者: AI Assistant
# 版本: 1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 配置文件路径
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/etc/haproxy/backup"

# 创建备份目录
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
    fi
}

# 打印横幅
print_banner() {
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${WHITE}           HAProxy 域名路由配置工具${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "${YELLOW}        智能域名后端映射管理系统${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

# 打印菜单
print_menu() {
    echo -e "${BLUE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│                 主菜单选项                  │${NC}"
    echo -e "${BLUE}├─────────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│  ${WHITE}1.${NC} ${GREEN}检查并安装 HAProxy${NC}                   ${BLUE}│${NC}"
    echo -e "${BLUE}│  ${WHITE}2.${NC} ${GREEN}添加域名和后端服务器${NC}                 ${BLUE}│${NC}"
    echo -e "${BLUE}│  ${WHITE}3.${NC} ${GREEN}查看当前配置${NC}                       ${BLUE}│${NC}"
    echo -e "${BLUE}│  ${WHITE}4.${NC} ${GREEN}重启 HAProxy 服务${NC}                   ${BLUE}│${NC}"
    echo -e "${BLUE}│  ${WHITE}5.${NC} ${GREEN}验证配置文件${NC}                       ${BLUE}│${NC}"
    echo -e "${BLUE}│  ${WHITE}6.${NC} ${GREEN}备份当前配置${NC}                       ${BLUE}│${NC}"
    echo -e "${BLUE}│  ${WHITE}0.${NC} ${RED}退出程序${NC}                           ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────┘${NC}"
    echo ""
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

# 安装HAProxy
install_haproxy() {
    echo -e "${CYAN}正在检查 HAProxy 安装状态...${NC}"
    
    if command -v haproxy &> /dev/null; then
        echo -e "${GREEN}√ HAProxy 已经安装${NC}"
        haproxy -v | head -n 1
    else
        echo -e "${YELLOW}HAProxy 未安装，开始安装...${NC}"
        
        # 更新包列表
        echo -e "${CYAN}更新软件包列表...${NC}"
        apt update
        
        # 安装HAProxy
        echo -e "${CYAN}安装 HAProxy...${NC}"
        apt install haproxy -y
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}√ HAProxy 安装成功${NC}"
        else
            echo -e "${RED}× HAProxy 安装失败${NC}"
            return 1
        fi
    fi
    
    # 启动并启用服务
    echo -e "${CYAN}配置 HAProxy 服务...${NC}"
    systemctl start haproxy
    systemctl enable haproxy
    
    # 检查服务状态
    if systemctl is-active --quiet haproxy; then
        echo -e "${GREEN}√ HAProxy 服务运行正常${NC}"
    else
        echo -e "${YELLOW}⚠ HAProxy 服务未运行，稍后将在配置完成后启动${NC}"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 生成基础HAProxy配置
generate_base_config() {
    cat > "$HAPROXY_CFG" << 'EOF'
global
    log /dev/log local0 warning
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon
    maxconn 20000
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s

defaults
    log global
    mode http
    option dontlognull
    option httplog
    option http-keep-alive
    option forwardfor
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    timeout http-keep-alive 15s
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend http-in
    bind *:80

EOF
}

# 检查配置文件是否存在基础结构
check_config_structure() {
    if [ ! -f "$HAPROXY_CFG" ] || ! grep -q "frontend http-in" "$HAPROXY_CFG"; then
        echo -e "${YELLOW}配置文件不存在或结构不完整，生成基础配置...${NC}"
        create_backup_dir
        [ -f "$HAPROXY_CFG" ] && cp "$HAPROXY_CFG" "$BACKUP_DIR/haproxy.cfg.$(date +%Y%m%d_%H%M%S)"
        generate_base_config
    fi
}

# 添加域名和后端
add_domain_backend() {
    check_config_structure
    
    echo -e "${CYAN}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│            添加域名和后端服务器             │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────┘${NC}"
    echo ""
    
    # 获取当前最大的backend编号
    backend_num=$(grep -o "backend backend[0-9]*" "$HAPROXY_CFG" 2>/dev/null | grep -o "[0-9]*" | sort -n | tail -1)
    if [ -z "$backend_num" ]; then
        backend_num=0
    fi
    
    while true; do
        backend_num=$((backend_num + 1))
        
        echo -e "${GREEN}配置后端服务器 #$backend_num${NC}"
        echo -e "${BLUE}─────────────────────────────${NC}"
        
        # 输入域名
        while true; do
            echo -e "${YELLOW}请输入域名（多个域名用空格分隔）:${NC}"
            echo -e "${CYAN}示例: example.com www.example.com api.example.com${NC}"
            read -p "> " domains
            
            if [ -n "$domains" ]; then
                # 验证域名格式
                valid=true
                for domain in $domains; do
                    if ! [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
                        echo -e "${RED}无效的域名格式: $domain${NC}"
                        valid=false
                        break
                    fi
                done
                
                if [ "$valid" = true ]; then
                    break
                fi
            else
                echo -e "${RED}域名不能为空${NC}"
            fi
        done
        
        # 输入后端IP
        while true; do
            echo -e "${YELLOW}请输入后端服务器IP:端口:${NC}"
            echo -e "${CYAN}示例: 192.168.1.100:80 或 8.8.8.8:443${NC}"
            read -p "> " backend_ip
            
            if [[ "$backend_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$ ]]; then
                break
            else
                echo -e "${RED}请输入正确的IP:端口格式${NC}"
            fi
        done
        
        # 显示确认信息
        echo ""
        echo -e "${GREEN}配置确认:${NC}"
        echo -e "${WHITE}域名: ${CYAN}$domains${NC}"
        echo -e "${WHITE}后端: ${CYAN}$backend_ip${NC}"
        echo ""
        
        read -p "确认添加这个配置吗? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # 添加ACL规则到frontend
            acl_line="    acl domain$backend_num hdr(host) -i $domains"
            use_backend_line="    use_backend backend$backend_num if domain$backend_num"
            
            # 在frontend段添加ACL和use_backend规则
            sed -i "/^frontend http-in/,/^backend\|^$/ {
                /^backend\|^$/i\\
$acl_line\\
$use_backend_line
            }" "$HAPROXY_CFG"
            
            # 添加backend配置
            echo "" >> "$HAPROXY_CFG"
            echo "backend backend$backend_num" >> "$HAPROXY_CFG"
            echo "    server server$backend_num $backend_ip check" >> "$HAPROXY_CFG"
            
            echo -e "${GREEN}√ 配置已添加成功${NC}"
        else
            echo -e "${YELLOW}已取消添加${NC}"
        fi
        
        echo ""
        read -p "是否继续添加其他域名和后端? (y/n): " continue_add
        if [[ ! "$continue_add" =~ ^[Yy]$ ]]; then
            break
        fi
        echo ""
    done
    
    # 修复配置文件格式
    echo "" >> "$HAPROXY_CFG"
    
    echo -e "${GREEN}域名和后端配置完成！${NC}"
    echo ""
    read -p "按回车键继续..."
}

# 查看当前配置
view_config() {
    echo -e "${CYAN}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│              当前 HAProxy 配置              │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────┘${NC}"
    echo ""
    
    if [ -f "$HAPROXY_CFG" ]; then
        echo -e "${GREEN}域名路由规则:${NC}"
        echo -e "${BLUE}─────────────────────────────${NC}"
        
        # 提取并显示域名映射关系
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*acl[[:space:]]+domain[0-9]+[[:space:]]+hdr\(host\)[[:space:]]+-i[[:space:]]+(.+)$ ]]; then
                domains="${BASH_REMATCH[1]}"
                acl_name=$(echo "$line" | grep -o "domain[0-9]*")
                backend_name="backend${acl_name#domain}"
                
                # 查找对应的backend IP
                backend_ip=$(grep -A1 "^backend $backend_name" "$HAPROXY_CFG" | grep "server" | awk '{print $3}' | cut -d' ' -f1)
                
                echo -e "${WHITE}域名: ${CYAN}$domains${NC}"
                echo -e "${WHITE}后端: ${GREEN}$backend_ip${NC}"
                echo ""
            fi
        done < "$HAPROXY_CFG"
        
        echo -e "${BLUE}─────────────────────────────${NC}"
        echo -e "${YELLOW}完整配置文件内容:${NC}"
        echo -e "${BLUE}─────────────────────────────${NC}"
        cat "$HAPROXY_CFG"
    else
        echo -e "${RED}配置文件不存在${NC}"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 重启HAProxy服务
restart_haproxy() {
    echo -e "${CYAN}正在重启 HAProxy 服务...${NC}"
    
    systemctl restart haproxy
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}√ HAProxy 服务重启成功${NC}"
        
        # 检查服务状态
        if systemctl is-active --quiet haproxy; then
            echo -e "${GREEN}√ 服务运行状态正常${NC}"
        else
            echo -e "${RED}× 服务启动失败${NC}"
            systemctl status haproxy
        fi
    else
        echo -e "${RED}× HAProxy 服务重启失败${NC}"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 验证配置文件
validate_config() {
    echo -e "${CYAN}正在验证 HAProxy 配置文件...${NC}"
    
    if [ ! -f "$HAPROXY_CFG" ]; then
        echo -e "${RED}× 配置文件不存在${NC}"
        return 1
    fi
    
    result=$(haproxy -c -f "$HAPROXY_CFG" 2>&1)
    
    if echo "$result" | grep -q "Configuration file is valid"; then
        echo -e "${GREEN}√ 配置文件验证通过${NC}"
        echo -e "${GREEN}配置文件格式正确，可以安全重启服务${NC}"
    else
        echo -e "${RED}× 配置文件验证失败${NC}"
        echo -e "${YELLOW}错误详情:${NC}"
        echo "$result"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 备份配置
backup_config() {
    create_backup_dir
    
    if [ -f "$HAPROXY_CFG" ]; then
        backup_file="$BACKUP_DIR/haproxy.cfg.$(date +%Y%m%d_%H%M%S)"
        cp "$HAPROXY_CFG" "$backup_file"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}√ 配置已备份到: $backup_file${NC}"
        else
            echo -e "${RED}× 备份失败${NC}"
        fi
    else
        echo -e "${RED}× 配置文件不存在，无法备份${NC}"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 主程序循环
main() {
    check_root
    
    while true; do
        print_banner
        print_menu
        
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                install_haproxy
                ;;
            2)
                add_domain_backend
                ;;
            3)
                view_config
                ;;
            4)
                restart_haproxy
                ;;
            5)
                validate_config
                ;;
            6)
                backup_config
                ;;
            0)
                echo -e "${GREEN}感谢使用 HAProxy 配置工具！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请输入 0-6 之间的数字${NC}"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main