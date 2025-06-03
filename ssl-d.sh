#!/bin/bash

# 颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

# 检查组件是否已安装
check_component() {
    local component="$1"
    if command -v "$component" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 安装依赖
install_dependency() {
    local need_install=0
    
    # 检查必要组件
    if ! check_component "certbot"; then
        need_install=1
    fi
    
    # 检查 certbot-dns-cloudflare 插件
    if ! pip3 list 2>/dev/null | grep -q "certbot-dns-cloudflare" 2>/dev/null; then
        need_install=1
    fi
    
    # 如果所有组件都已安装，则跳过
    if [ $need_install -eq 0 ]; then
        return 0
    fi
    
    # 静默安装缺失组件
    if [ -f /etc/debian_version ]; then
        apt update >/dev/null 2>&1
        apt install -y python3-pip certbot >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        yum install -y python3-pip certbot >/dev/null 2>&1
    else
        echo -e "${RED}不支持的操作系统${NC}"
        exit 1
    fi
    
    # 静默安装 Cloudflare DNS 插件
    sudo apt install certbot python3-certbot-dns-cloudflare >/dev/null 2>&1
}

# 配置 Cloudflare 凭证
setup_cloudflare() {
    local domain="$1"
    local cf_config_dir="/root/.secrets"
    local cf_config_file="$cf_config_dir/${domain}.ini"
    local default_config_file="$cf_config_dir/cloudflare.ini"
    
    # 如果域名特定的配置文件已存在且有效，直接返回
    if [ -f "$cf_config_file" ] && [ -s "$cf_config_file" ]; then
        return 0
    fi
    
    # 如果默认配置文件存在且有效，询问是否使用默认配置
    if [ -f "$default_config_file" ] && [ -s "$default_config_file" ]; then
        echo -e "${YELLOW}检测到默认 Cloudflare 配置文件。是否使用默认配置？(y/n)${NC}"
        read use_default
        if [[ $use_default =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # 创建配置目录
    mkdir -p "$cf_config_dir" >/dev/null 2>&1
    
    # 获取 Cloudflare API Token
    echo -e "${YELLOW}请输入 ${domain} 的 Cloudflare API Token:${NC}"
    echo -e "${YELLOW}(请确保 API Token 具有 Zone:DNS:Edit 权限)${NC}"
    read cf_api_token
    
    # 创建配置文件
    cat > "$cf_config_file" <<EOF
dns_cloudflare_api_token = $cf_api_token
EOF
    
    # 设置权限
    chmod 600 "$cf_config_file" >/dev/null 2>&1
    
    # 如果是第一次配置，询问是否设为默认配置
    if [ ! -f "$default_config_file" ]; then
        echo -e "${YELLOW}是否将此配置设为默认配置？(y/n)${NC}"
        read set_default
        if [[ $set_default =~ ^[Yy]$ ]]; then
            cp "$cf_config_file" "$default_config_file"
            chmod 600 "$default_config_file" >/dev/null 2>&1
        fi
    fi
}

# 清屏函数
clear_screen() {
    clear
}

# 提示用户输入域名和邮箱
add_yuming() {
    echo -e "请输入域名（多个域名用空格分隔）:"
    read -e yuming
    echo -e "请输入邮箱地址（用于接收证书过期通知）:"
    read -e email
}

# 创建HAProxy证书文件
create_haproxy_cert() {
    local domain="$1"
    local cert_path="/etc/letsencrypt/live/$domain"
    local haproxy_cert_dir="/etc/haproxy/certs"
    
    # 创建HAProxy证书目录
    mkdir -p "$haproxy_cert_dir"
    
    # 合并证书文件（fullchain.pem + privkey.pem）
    if [ -f "$cert_path/fullchain.pem" ] && [ -f "$cert_path/privkey.pem" ]; then
        cat "$cert_path/fullchain.pem" "$cert_path/privkey.pem" > "$haproxy_cert_dir/${domain}.pem"
        chmod 600 "$haproxy_cert_dir/${domain}.pem"
        echo -e "${GREEN}HAProxy证书文件已创建: $haproxy_cert_dir/${domain}.pem${NC}"
        return 0
    else
        echo -e "${RED}证书文件不存在，无法创建HAProxy证书${NC}"
        return 1
    fi
}

# 申请证书
install_ssltls() {
    local domain_list="$1"
    local email="$2"
    local primary_domain=$(echo $domain_list | awk '{print $1}')
    local cert_path="/etc/letsencrypt/live/$primary_domain"
    
    # 检查主域名的 Cloudflare 配置
    local cf_credentials="/root/.secrets/${primary_domain}.ini"
    if [ ! -f "$cf_credentials" ]; then
        cf_credentials="/root/.secrets/cloudflare.ini"
        if [ ! -f "$cf_credentials" ]; then
            setup_cloudflare "$primary_domain"
            cf_credentials="/root/.secrets/${primary_domain}.ini"
        fi
    fi
    
    echo -e "${YELLOW}正在申请证书...${NC}"
    echo -e "${YELLOW}请耐心等待，DNS验证可能需要一些时间...${NC}"
    
    # 将域名列表转换为带有-d选项的字符串
    domains_with_d=""
    for domain in $domain_list; do
        domains_with_d+=" -d $domain"
    done
    
    # 使用对应的凭证文件申请证书
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$cf_credentials" \
        $domains_with_d \
        --preferred-challenges dns-01 \
        --agree-tos \
        --email "$email" \
        --non-interactive \
        --key-type ecdsa \
        --force-renewal \
        --dns-cloudflare-propagation-seconds 60 \
        2>&1 | tee /tmp/certbot.log
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}证书申请成功！${NC}"
        
        # 创建HAProxy格式的证书文件
        create_haproxy_cert "$primary_domain"
        
        # 重启HAProxy服务（如果存在）
        if systemctl is-active --quiet haproxy; then
            systemctl restart haproxy
            echo -e "${GREEN}HAProxy服务已重新加载${NC}"
        fi
        
    else
        echo -e "${RED}证书申请失败！${NC}"
        echo -e "${YELLOW}错误详情：${NC}"
        grep -i "error\|failed\|problem" /tmp/certbot.log
        echo -e "${YELLOW}可能的解决方案：${NC}"
        echo "1. 确保域名已正确添加到Cloudflare"
        echo "2. 确保Cloudflare API Token权限正确"
        echo "3. 检查域名DNS解析是否正常"
        rm -f /tmp/certbot.log
        return 1
    fi
    rm -f /tmp/certbot.log
}

# 显示证书信息
install_ssltls_text() {
    local primary_domain=$(echo $yuming | awk '{print $1}')
    echo -e "${YELLOW}证书信息 (主域名: $primary_domain)${NC}"
    echo "证书存放路径:"
    echo "公钥: /etc/letsencrypt/live/${primary_domain}/fullchain.pem"
    echo "私钥: /etc/letsencrypt/live/${primary_domain}/privkey.pem"
    echo "HAProxy证书: /etc/haproxy/certs/${primary_domain}.pem"
    echo ""
    echo -e "${YELLOW}包含的域名:${NC}"
    for domain in $yuming; do
        echo "- $domain"
    done
    echo ""
    
    # 显示已申请证书的到期情况
    echo -e "${YELLOW}已申请的证书到期情况${NC}"
    echo "站点信息                      证书到期时间"
    echo "------------------------"
    for cert_dir in /etc/letsencrypt/live/*; do
        local cert_file="$cert_dir/fullchain.pem"
        if [ -f "$cert_file" ]; then
            local domain=$(basename "$cert_dir")
            local expire_date=$(openssl x509 -noout -enddate -in "$cert_file" | awk -F'=' '{print $2}')
            local formatted_date=$(date -d "$expire_date" '+%Y-%m-%d')
            printf "%-30s%s\n" "$domain" "$formatted_date"
        fi
    done
    echo ""
}

# 证书申请主函数
add_ssl() {
    # 静默安装依赖
    install_dependency
    
    # 静默配置 Cloudflare（如果需要）
    setup_cloudflare
    
    # 清屏
    clear
    
    yuming="${1:-}"
    if [ -z "$yuming" ]; then
        add_yuming
    fi
    
    # 申请证书
    install_ssltls "$yuming" "$email"
    
    # 显示证书信息
    install_ssltls_text
}

# 查看证书状态函数
view_cert_status() {
    if [ -d "/etc/letsencrypt/live/" ]; then
        echo -e "${YELLOW}已申请的证书到期情况${NC}"
        echo "站点信息                      证书到期时间"
        echo "------------------------"
        for cert_dir in /etc/letsencrypt/live/*; do
            local cert_file="$cert_dir/fullchain.pem"
            if [ -f "$cert_file" ]; then
                local domain=$(basename "$cert_dir")
                local expire_date=$(openssl x509 -noout -enddate -in "$cert_file" | awk -F'=' '{print $2}')
                local formatted_date=$(date -d "$expire_date" '+%Y-%m-%d')
                printf "%-30s%s\n" "$domain" "$formatted_date"
            fi
        done
        echo ""
    else
        echo -e "${RED}未找到任何SSL证书${NC}"
    fi
}

# 证书自动续期函数
auto_renew_certs() {
    echo -e "${YELLOW}开始检查证书续期...${NC}"
    
    # 定义证书存储目录
    certs_directory="/etc/letsencrypt/live/"
    cf_credentials="/root/.secrets/cloudflare.ini"
    
    # 检查 Cloudflare 配置文件
    if [ ! -f "$cf_credentials" ]; then
        echo -e "${RED}错误: Cloudflare 配置文件不存在${NC}"
        echo "请先运行此脚本配置 Cloudflare API Token"
        exit 1
    fi
    
    days_before_expiry=5  # 设置在证书到期前几天触发续签
    
    # 遍历所有证书文件
    for cert_dir in $certs_directory*; do
        # 获取域名
        yuming=$(basename "$cert_dir")
        
        # 忽略 README 目录
        if [ "$yuming" = "README" ]; then
            continue
        fi
        
        # 输出正在检查的证书信息
        echo -e "${YELLOW}检查证书过期日期： ${yuming}${NC}"
        
        # 获取fullchain.pem文件路径
        cert_file="${cert_dir}/fullchain.pem"
        
        # 检查证书文件是否存在
        if [ ! -f "$cert_file" ]; then
            echo -e "${RED}证书文件不存在: $cert_file${NC}"
            continue
        fi
        
        # 获取证书过期日期
        expiration_date=$(openssl x509 -enddate -noout -in "${cert_file}" | cut -d "=" -f 2-)
        
        # 输出证书过期日期
        echo "过期日期： ${expiration_date}"
        
        # 将日期转换为时间戳
        expiration_timestamp=$(date -d "${expiration_date}" +%s)
        current_timestamp=$(date +%s)
        
        # 计算距离过期还有几天
        days_until_expiry=$(( ($expiration_timestamp - $current_timestamp) / 86400 ))
        
        # 检查是否需要续签
        if [ $days_until_expiry -le $days_before_expiry ]; then
            echo -e "${YELLOW}证书将在${days_before_expiry}天内过期，正在进行自动续签。${NC}"
            
            # 获取所有相关域名
            domains=$(openssl x509 -in "$cert_file" -text -noout | grep "DNS:" | sed 's/DNS://g' | tr -d ' ' | tr ',' ' ')
            
            # 构建域名参数
            domains_param=""
            for domain in $domains; do
                domains_param+=" -d $domain"
            done
            
            # 使用 certbot 续签证书
            certbot certonly \
                --dns-cloudflare \
                --dns-cloudflare-credentials "$cf_credentials" \
                $domains_param \
                --preferred-challenges dns-01 \
                --agree-tos \
                --email "admin@example.com" \
                --non-interactive \
                --key-type ecdsa \
                --force-renewal \
                --dns-cloudflare-propagation-seconds 30
                
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}证书续签成功${NC}"
                
                # 创建HAProxy格式的证书文件
                create_haproxy_cert "$yuming"
                
                # 重启HAProxy服务（如果存在）
                if systemctl is-active --quiet haproxy; then
                    systemctl restart haproxy
                    echo -e "${GREEN}HAProxy服务已重新加载${NC}"
                fi
                
                echo -e "${GREEN}证书和配置文件已更新${NC}"
            else
                echo -e "${RED}证书续签失败${NC}"
            fi
        else
            # 若未满足续签条件，则输出证书仍然有效
            echo -e "${GREEN}证书仍然有效，距离过期还有 ${days_until_expiry} 天。${NC}"
        fi
        
        # 输出分隔线
        echo "--------------------------"
    done
}

# 安装定时任务
install_cron_job() {
    local script_path=$(realpath "$0")
    local cron_job="0 2 * * * $script_path --auto-renew >> /var/log/ssl-auto-renew.log 2>&1"
    
    # 检查是否已存在定时任务
    if crontab -l 2>/dev/null | grep -q "$script_path --auto-renew"; then
        echo -e "${YELLOW}定时任务已存在${NC}"
        return 0
    fi
    
    # 添加定时任务
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}定时任务安装成功！${NC}"
        echo "任务将在每天凌晨2点自动检查并续期证书"
        echo "日志文件: /var/log/ssl-auto-renew.log"
    else
        echo -e "${RED}定时任务安装失败${NC}"
    fi
}

# 卸载定时任务
uninstall_cron_job() {
    local script_path=$(realpath "$0")
    
    # 移除定时任务
    crontab -l 2>/dev/null | grep -v "$script_path --auto-renew" | crontab -
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}定时任务已移除${NC}"
    else
        echo -e "${RED}定时任务移除失败${NC}"
    fi
}

# SSL证书申请函数
ssl_cert_menu() {
    while true; do
        clear_screen
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}            SSL证书申请 - haproxy版              ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 申请SSL证书"
        echo -e "${GREEN}2.${NC} 查看证书状态"
        echo -e "${GREEN}3.${NC} 手动续期检查"
        echo -e "${GREEN}4.${NC} 安装自动续期定时任务"
        echo -e "${GREEN}5.${NC} 卸载自动续期定时任务"
        echo -e "${GREEN}0.${NC} 退出"
        echo ""
        echo -e "${BLUE}=================================================${NC}"

        read -p "请输入选项 [0-5]: " ssl_choice
        case $ssl_choice in
            1)
                # 调用申请证书函数
                add_ssl
                ;;
            2)
                view_cert_status
                ;;
            3)
                auto_renew_certs
                ;;
            4)
                install_cron_job
                ;;
            5)
                uninstall_cron_job
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项，请重新选择${NC}"
                ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 主函数
main() {
    # 检查命令行参数
    if [ "$1" = "--auto-renew" ]; then
        auto_renew_certs
        exit 0
    fi
    
    ssl_cert_menu
}

# 运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi