#!/bin/bash

# HAProxy配置管理脚本
# 作者: 自动化配置工具
# 版本: 1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
CONFIG_URL="https://raw.githubusercontent.com/woniu336/open_shell/main/443_haproxy.cfg"
SSL_SCRIPT_URL="https://raw.githubusercontent.com/woniu336/open_shell/main/ssl-d.sh"

# 打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message $RED "错误: 此脚本需要root权限运行"
        print_message $YELLOW "请使用: sudo $0"
        exit 1
    fi
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}     HAProxy 配置管理工具      ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    echo -e "${GREEN}1.${NC} 申请SSL证书"
    echo -e "${GREEN}2.${NC} 安装HAProxy"
    echo -e "${GREEN}3.${NC} 配置站点"
    echo -e "${GREEN}4.${NC} 测试SSL证书"
    echo -e "${GREEN}5.${NC} 查看HAProxy状态"
    echo -e "${GREEN}6.${NC} 重启HAProxy服务"
    echo -e "${GREEN}0.${NC} 退出"
    echo
    echo -n -e "${YELLOW}请选择操作 [0-6]: ${NC}"
}

# 申请SSL证书
apply_ssl_cert() {
    print_message $BLUE "正在下载SSL证书申请脚本..."
    
    # 下载并执行SSL证书脚本
    if curl -sS -O "$SSL_SCRIPT_URL"; then
        chmod +x ssl-d.sh
        print_message $GREEN "SSL证书脚本下载成功，正在执行..."
        ./ssl-d.sh
    else
        print_message $RED "SSL证书脚本下载失败，请检查网络连接"
        return 1
    fi
}

# 检查HAProxy是否已安装
check_haproxy_installed() {
    if command -v haproxy >/dev/null 2>&1; then
        return 0  # 已安装
    else
        return 1  # 未安装
    fi
}

# 安装HAProxy
install_haproxy() {
    print_message $BLUE "正在安装HAProxy..."
    
    # 更新包列表
    apt update >/dev/null 2>&1
    
    # 安装HAProxy
    if apt install haproxy -y; then
        print_message $GREEN "HAProxy安装成功"
        
        # 启动并启用HAProxy服务
        systemctl start haproxy
        systemctl enable haproxy
        
        print_message $GREEN "HAProxy服务已启动并设置为开机自启"
        return 0
    else
        print_message $RED "HAProxy安装失败"
        return 1
    fi
}

# 配置站点
configure_site() {
    print_message $BLUE "开始配置站点..."
    
    # 静默检查HAProxy是否安装
    if ! check_haproxy_installed; then
        print_message $YELLOW "检测到HAProxy未安装，正在自动安装..."
        if ! install_haproxy; then
            print_message $RED "HAProxy安装失败，无法继续配置"
            return 1
        fi
    else
        print_message $GREEN "HAProxy已安装，跳过安装步骤"
    fi
    
    # 备份原配置文件
    if [[ -f "$HAPROXY_CONFIG" ]]; then
        cp "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
        print_message $YELLOW "原配置文件已备份"
    fi
    
    # 下载新配置文件
    print_message $BLUE "正在下载配置文件模板..."
    if curl -sS -o "$HAPROXY_CONFIG" "$CONFIG_URL"; then
        print_message $GREEN "配置文件下载成功"
    else
        print_message $RED "配置文件下载失败，请检查网络连接"
        return 1
    fi
    
    # 交互式配置
    echo
    print_message $YELLOW "请输入域名配置信息:"
    echo -n -e "${BLUE}请输入域名 (多个域名用空格分隔): ${NC}"
    read -r domains
    
    if [[ -z "$domains" ]]; then
        print_message $RED "域名不能为空"
        return 1
    fi
    
    echo -n -e "${BLUE}请输入后端服务器IP地址: ${NC}"
    read -r backend_ip
    
    if [[ -z "$backend_ip" ]]; then
        print_message $RED "后端IP地址不能为空"
        return 1
    fi
    
    # 验证IP地址格式（简单验证）
    if ! [[ $backend_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_message $RED "IP地址格式不正确"
        return 1
    fi
    
    # 修改配置文件
    print_message $BLUE "正在更新配置文件..."
    
    # 替换域名配置
    sed -i "s/123\.com 456\.com/$domains/g" "$HAPROXY_CONFIG"
    
    # 替换后端IP地址
    sed -i "s/8\.8\.8\.8/$backend_ip/g" "$HAPROXY_CONFIG"
    
    # 检查配置文件语法
    print_message $BLUE "正在检查配置文件语法..."
    if haproxy -c -f "$HAPROXY_CONFIG"; then
        print_message $GREEN "配置文件语法检查通过"
        
        # 重启HAProxy服务
        print_message $BLUE "正在重启HAProxy服务..."
        if systemctl restart haproxy; then
            print_message $GREEN "HAProxy服务重启成功"
            echo
            print_message $GREEN "=== 站点配置成功 ==="
            print_message $YELLOW "域名: $domains"
            print_message $YELLOW "后端服务器: $backend_ip:80"
            print_message $YELLOW "HTTP端口: 80 (自动跳转HTTPS)"
            print_message $YELLOW "HTTPS端口: 443"
            echo
            print_message $BLUE "请确保:"
            print_message $BLUE "1. 域名已正确解析到此服务器"
            print_message $BLUE "2. SSL证书已放置在 /etc/haproxy/certs/ 目录"
            print_message $BLUE "3. 后端服务器 $backend_ip:80 正常运行"
        else
            print_message $RED "HAProxy服务重启失败"
            return 1
        fi
    else
        print_message $RED "配置文件语法错误，请检查配置"
        return 1
    fi
}

# 测试SSL证书是否匹配域名
test_ssl_cert() {
    print_message $BLUE "开始测试SSL证书和域名匹配..."
    
    # 检查证书目录是否存在
    local cert_dir="/etc/haproxy/certs"
    if [[ ! -d "$cert_dir" ]]; then
        print_message $RED "证书目录 $cert_dir 不存在"
        return 1
    fi
    
    # 检查HAProxy配置文件是否存在
    if [[ ! -f "$HAPROXY_CONFIG" ]]; then
        print_message $RED "HAProxy配置文件不存在，请先配置站点"
        return 1
    fi
    
    # 从配置文件中提取域名
    local domains_line
    domains_line=$(grep -i "acl domain1_https hdr(host)" "$HAPROXY_CONFIG" 2>/dev/null)
    
    if [[ -z "$domains_line" ]]; then
        print_message $RED "无法从配置文件中找到域名配置"
        print_message $YELLOW "请手动输入要测试的域名"
        echo -n -e "${BLUE}请输入域名 (多个域名用空格分隔): ${NC}"
        read -r manual_domains
        
        if [[ -z "$manual_domains" ]]; then
            print_message $RED "域名不能为空"
            return 1
        fi
        
        domains_array=($manual_domains)
    else
        # 提取域名（去掉ACL配置的前缀和后缀）
        local domains_part
        domains_part=$(echo "$domains_line" | sed 's/.*hdr(host) -i //' | sed 's/$//')
        domains_array=($domains_part)
    fi
    
    if [[ ${#domains_array[@]} -eq 0 ]]; then
        print_message $RED "未找到要测试的域名"
        return 1
    fi
    
    # 检查openssl工具
    if ! command -v openssl >/dev/null 2>&1; then
        print_message $RED "错误: 未找到openssl命令"
        print_message $YELLOW "请安装openssl: apt install openssl -y"
        return 1
    fi
    
    print_message $YELLOW "找到以下域名，开始测试:"
    printf '%s\n' "${domains_array[@]}" | sed 's/^/  - /'
    echo
    
    # 显示证书目录内容
    print_message $BLUE "证书目录 ($cert_dir) 内容:"
    if ls -la "$cert_dir"/*.pem 2>/dev/null | head -10; then
        echo
    else
        print_message $YELLOW "证书目录中未找到 .pem 文件"
        echo
    fi
    
    local success_count=0
    local total_count=${#domains_array[@]}
    
    # 逐个测试域名
    for domain in "${domains_array[@]}"; do
        print_message $BLUE "Testing $domain:"
        echo "----------------------------------------"
        
        # 1. 检查是否有对应的证书文件
        local cert_found=false
        local cert_files=("$cert_dir/$domain.pem" "$cert_dir/${domain}.crt" "$cert_dir/fullchain.pem" "$cert_dir/cert.pem")
        
        for cert_file in "${cert_files[@]}"; do
            if [[ -f "$cert_file" ]]; then
                print_message $GREEN "✓ 找到证书文件: $cert_file"
                
                # 检查证书文件中的域名信息
                local cert_subject
                cert_subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null)
                if [[ -n "$cert_subject" ]]; then
                    echo -e "${YELLOW}本地证书主题:${NC} $cert_subject"
                    
                    # 检查SAN信息
                    local cert_san
                    cert_san=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -n1)
                    if [[ -n "$cert_san" ]]; then
                        echo -e "${YELLOW}本地证书SAN:${NC} $cert_san"
                    fi
                fi
                cert_found=true
                break
            fi
        done
        
        if [[ "$cert_found" == false ]]; then
            print_message $RED "✗ 未找到域名 $domain 对应的证书文件"
            print_message $YELLOW "查找的文件: ${cert_files[*]}"
        fi
        
        # 2. 测试在线证书（使用你提供的代码逻辑）
        print_message $BLUE "在线证书测试:"
        local online_cert_subject
        online_cert_subject=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
        
        if [[ -n "$online_cert_subject" ]]; then
            print_message $GREEN "✓ 在线证书获取成功"
            echo -e "${YELLOW}在线证书主题:${NC} $online_cert_subject"
            
            # 比较本地证书和在线证书
            if [[ "$cert_found" == true && -n "$cert_subject" ]]; then
                if [[ "$cert_subject" == "$online_cert_subject" ]]; then
                    print_message $GREEN "✓ 本地证书与在线证书匹配"
                    ((success_count++))
                else
                    print_message $RED "✗ 本地证书与在线证书不匹配"
                    print_message $YELLOW "本地: $cert_subject"
                    print_message $YELLOW "在线: $online_cert_subject"
                fi
            fi
        else
            print_message $RED "✗ 无法获取在线证书"
            print_message $YELLOW "可能原因: 域名解析错误、服务未启动或证书配置问题"
        fi
        
        echo "---"
        echo
    done
    
    # 显示测试总结
    print_message $BLUE "=== SSL证书匹配测试总结 ==="
    print_message $YELLOW "总域名数: $total_count"
    print_message $GREEN "匹配成功: $success_count"
    print_message $RED "匹配失败: $((total_count - success_count))"
    
    if [[ $success_count -eq $total_count ]]; then
        print_message $GREEN "🎉 所有域名的证书都匹配正确！"
    elif [[ $success_count -gt 0 ]]; then
        print_message $YELLOW "⚠️  部分域名的证书存在问题"
    else
        print_message $RED "❌ 所有域名的证书都不匹配"
    fi
    
    print_message $BLUE "建议检查:"
    print_message $BLUE "1. 证书文件是否正确放置在 /etc/haproxy/certs/ 目录"
    print_message $BLUE "2. 证书文件命名是否正确 (domain.pem 或 fullchain.pem)"
    print_message $BLUE "3. HAProxy配置中的证书路径是否正确"
    print_message $BLUE "4. 域名是否正确解析到此服务器"
}
check_haproxy_status() {
    print_message $BLUE "HAProxy服务状态:"
    systemctl status haproxy --no-pager
    echo
    print_message $BLUE "HAProxy进程信息:"
    ps aux | grep haproxy | grep -v grep
}

# 重启HAProxy服务
restart_haproxy() {
    print_message $BLUE "正在重启HAProxy服务..."
    if systemctl restart haproxy; then
        print_message $GREEN "HAProxy服务重启成功"
        systemctl status haproxy --no-pager -l
    else
        print_message $RED "HAProxy服务重启失败"
        print_message $YELLOW "请检查配置文件和日志"
    fi
}

# 主程序
main() {
    check_root
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                apply_ssl_cert
                read -p "按回车键继续..." -r
                ;;
            2)
                if check_haproxy_installed; then
                    print_message $YELLOW "HAProxy已经安装"
                else
                    install_haproxy
                fi
                read -p "按回车键继续..." -r
                ;;
            3)
                configure_site
                read -p "按回车键继续..." -r
                ;;
            4)
                test_ssl_cert
                read -p "按回车键继续..." -r
                ;;
            5)
                check_haproxy_status
                read -p "按回车键继续..." -r
                ;;
            6)
                restart_haproxy
                read -p "按回车键继续..." -r
                ;;
            0)
                print_message $GREEN "感谢使用HAProxy配置管理工具！"
                exit 0
                ;;
            *)
                print_message $RED "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 执行主程序
main