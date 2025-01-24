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
        echo -e "${GREEN}所需组件已安装，跳过安装步骤...${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}正在安装缺失组件...${NC}"
    
    if [ -f /etc/debian_version ]; then
        apt update
        apt install -y python3-pip certbot
    elif [ -f /etc/redhat-release ]; then
        yum install -y python3-pip certbot
    else
        echo -e "${RED}不支持的操作系统${NC}"
        exit 1
    fi
    
    # 安装 Cloudflare DNS 插件
    pip3 install certbot-dns-cloudflare
}

# 配置 Cloudflare 凭证
setup_cloudflare() {
    local cf_config_dir="/root/.secrets"
    local cf_config_file="$cf_config_dir/cloudflare.ini"
    
    # 如果配置文件已存在且有效，直接返回
    if [ -f "$cf_config_file" ] && [ -s "$cf_config_file" ]; then
        echo -e "${GREEN}检测到有效的 Cloudflare 配置，跳过配置步骤...${NC}"
        return 0
    fi
    
    # 创建配置目录
    mkdir -p "$cf_config_dir"
    
    # 获取 Cloudflare API Token
    echo -e "${YELLOW}请输入 Cloudflare API Token:${NC}"
    echo -e "${YELLOW}(请确保 API Token 具有 Zone:DNS:Edit 权限)${NC}"
    read cf_api_token
    
    # 创建配置文件
    cat > "$cf_config_file" <<EOF
dns_cloudflare_api_token = $cf_api_token
EOF
    
    # 设置权限
    chmod 600 "$cf_config_file"
    echo -e "${GREEN}Cloudflare 配置已保存${NC}"
}



# 提示用户输入域名
add_yuming() {
    ip_address
    echo -e "请输入域名（多个域名用空格分隔）:"
    read -e yuming
}

# 申请证书
install_ssltls() {
    local domain_list="$1"
    local primary_domain=$(echo $domain_list | awk '{print $1}')
    local cert_path="/etc/letsencrypt/live/$primary_domain"
    local cf_credentials="/root/.secrets/cloudflare.ini"
    
    # 检查 Cloudflare 配置
    if [ ! -f "$cf_credentials" ]; then
        setup_cloudflare
    fi
    
    echo -e "${YELLOW}正在申请证书...${NC}"
    
    # 将域名列表转换为带有-d选项的字符串
    domains_with_d=""
    for domain in $domain_list; do
        domains_with_d+=" -d $domain"
    done
    
    # 申请证书
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$cf_credentials" \
        $domains_with_d \
        --preferred-challenges dns-01 \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        --key-type ecdsa \
        --force-renewal
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}证书申请成功！${NC}"
        # 复制到 Nginx 目录
        mkdir -p /etc/nginx/certs
        cp "$cert_path/fullchain.pem" "/etc/nginx/certs/${primary_domain}_cert.pem"
        cp "$cert_path/privkey.pem" "/etc/nginx/certs/${primary_domain}_key.pem"
        chmod 644 "/etc/nginx/certs/${primary_domain}_cert.pem"
        chmod 600 "/etc/nginx/certs/${primary_domain}_key.pem"
    else
        echo -e "${RED}证书申请失败！${NC}"
        return 1
    fi
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

# 设置自动续期
setup_cert_renewal() {
    # certbot 会自动创建续期任务
    systemctl enable certbot.timer
    systemctl start certbot.timer
    echo -e "${GREEN}自动续期任务已设置${NC}"
}

# 主函数
add_ssl() {
    # 清屏
    clear
    
    yuming="${1:-}"
    if [ -z "$yuming" ]; then
        add_yuming
    fi
    
    # 安装依赖
    install_dependency
    
    # 配置 Cloudflare（如果需要）
    setup_cloudflare
    
    # 申请证书
    install_ssltls "$yuming"
    
    # 设置自动续期
    setup_cert_renewal
    
    # 显示证书信息
    install_ssltls_text
}

# 运行主函数
add_ssl "$@"