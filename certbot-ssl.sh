#!/bin/bash

# 颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
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
    pip3 install -q certbot-dns-cloudflare >/dev/null 2>&1
}

# 配置 Cloudflare 凭证
setup_cloudflare() {
    local cf_config_dir="/root/.secrets"
    local cf_config_file="$cf_config_dir/cloudflare.ini"
    
    # 如果配置文件已存在且有效，直接返回
    if [ -f "$cf_config_file" ] && [ -s "$cf_config_file" ]; then
        return 0
    fi
    
    # 创建配置目录
    mkdir -p "$cf_config_dir" >/dev/null 2>&1
    
    # 获取 Cloudflare API Token
    echo -e "${YELLOW}请输入 Cloudflare API Token:${NC}"
    echo -e "${YELLOW}(请确保 API Token 具有 Zone:DNS:Edit 权限)${NC}"
    read cf_api_token
    
    # 创建配置文件
    cat > "$cf_config_file" <<EOF
dns_cloudflare_api_token = $cf_api_token
EOF
    
    # 设置权限
    chmod 600 "$cf_config_file" >/dev/null 2>&1
}

# 提示用户输入域名和邮箱
add_yuming() {
    echo -e "请输入域名（多个域名用空格分隔）:"
    read -e yuming
    echo -e "请输入邮箱地址（用于接收证书过期通知）:"
    read -e email
}

# 安装 crontab
install_crontab() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|kali)
                apt update >/dev/null 2>&1
                apt install -y cron >/dev/null 2>&1
                systemctl enable cron >/dev/null 2>&1
                systemctl start cron >/dev/null 2>&1
                ;;
            centos|rhel|almalinux|rocky|fedora)
                yum install -y cronie >/dev/null 2>&1
                systemctl enable crond >/dev/null 2>&1
                systemctl start crond >/dev/null 2>&1
                ;;
            *)
                echo -e "${RED}不支持的发行版: $ID${NC}"
                return 1
                ;;
        esac
    else
        echo -e "${RED}无法确定操作系统类型${NC}"
        return 1
    fi
}

# 检查并安装 crontab
check_crontab_installed() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装 crontab...${NC}"
        install_crontab
    fi
}

# 设置证书自动续期
setup_cert_renewal() {
    # 检查并安装 crontab
    check_crontab_installed
    
    # 下载自动续期脚本
    if [ ! -f "auto_cert_renewal.sh" ]; then
        echo -e "${YELLOW}正在下载证书续期脚本...${NC}"
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/auto_cert_renewal.sh
        chmod +x auto_cert_renewal.sh
    fi

    # 添加定时任务（每天凌晨3点5分执行）
    local cron_job="5 3 * * * $(pwd)/auto_cert_renewal.sh"
    if ! (crontab -l 2>/dev/null | grep -Fq "$cron_job"); then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        echo -e "${GREEN}证书自动续期任务已添加${NC}"
    fi
}

# 申请证书
install_ssltls() {
    local domain_list="$1"
    local email="$2"
    local primary_domain=$(echo $domain_list | awk '{print $1}')
    local cert_path="/etc/letsencrypt/live/$primary_domain"
    local cf_credentials="/root/.secrets/cloudflare.ini"
    
    # 检查 Cloudflare 配置
    if [ ! -f "$cf_credentials" ]; then
        setup_cloudflare
    fi
    
    echo -e "${YELLOW}正在申请证书...${NC}"
    echo -e "${YELLOW}请耐心等待，DNS验证可能需要一些时间...${NC}"
    
    # 将域名列表转换为带有-d选项的字符串
    domains_with_d=""
    for domain in $domain_list; do
        domains_with_d+=" -d $domain"
    done
    
    # 申请证书，增加DNS传播等待时间到60秒
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
        --dns-cloudflare-propagation-seconds 30 \
        2>&1 | tee /tmp/certbot.log
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}证书申请成功！${NC}"
        # 复制到 Nginx 目录
        mkdir -p /etc/nginx/certs
        cp "$cert_path/fullchain.pem" "/etc/nginx/certs/${primary_domain}_cert.pem"
        cp "$cert_path/privkey.pem" "/etc/nginx/certs/${primary_domain}_key.pem"
        chmod 644 "/etc/nginx/certs/${primary_domain}_cert.pem"
        chmod 600 "/etc/nginx/certs/${primary_domain}_key.pem"
        
        # 设置自动续期
        setup_cert_renewal
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
    echo "公钥: /etc/nginx/certs/${primary_domain}_cert.pem"
    echo "私钥: /etc/nginx/certs/${primary_domain}_key.pem"
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

# 主函数
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

# 运行主函数
add_ssl "$@"