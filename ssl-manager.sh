#!/bin/bash

# 默认配置（可被覆盖）
DEFAULT_EMAIL="123456@qq.com"
DEFAULT_TOKEN="TOKEN"

# 存储配置文件
CONFIG_FILE="/root/ssl-manager.conf"
CERTS_LIST_FILE="/root/ssl-certs.list"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 信息输出函数
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

title() {
    echo -e "${PURPLE}╔════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}  ${BOLD}${CYAN}$1${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
}

separator() {
    echo -e "${BLUE}────────────────────────────────────────────${NC}"
}

# 加载配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        # 创建默认配置
        save_config
    fi
    
    if [[ -f "$CERTS_LIST_FILE" ]]; then
        # 加载证书列表
        DOMAINS_LIST=($(cat "$CERTS_LIST_FILE" | grep -v "^#" | grep -v "^$"))
    else
        DOMAINS_LIST=()
    fi
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
# SSL证书管理工具配置文件
EMAIL="$DEFAULT_EMAIL"
TOKEN="$DEFAULT_TOKEN"
EOF
    chmod 600 "$CONFIG_FILE"
}

# 保存证书列表
save_certs_list() {
    printf "%s\n" "${DOMAINS_LIST[@]}" > "$CERTS_LIST_FILE"
}

# 添加域名到列表
add_domain_to_list() {
    local domain="$1"
    
    if [[ " ${DOMAINS_LIST[@]} " =~ " ${domain} " ]]; then
        warn "域名已存在于列表中: $domain"
        return 1
    fi
    
    DOMAINS_LIST+=("$domain")
    save_certs_list
    info "已添加域名到列表: $domain"
    return 0
}

# 从列表中移除域名
remove_domain_from_list() {
    local domain="$1"
    local new_list=()
    
    for d in "${DOMAINS_LIST[@]}"; do
        if [[ "$d" != "$domain" ]]; then
            new_list+=("$d")
        fi
    done
    
    if [[ ${#new_list[@]} -eq ${#DOMAINS_LIST[@]} ]]; then
        warn "域名不在列表中: $domain"
        return 1
    fi
    
    DOMAINS_LIST=("${new_list[@]}")
    save_certs_list
    info "已从列表中移除域名: $domain"
    return 0
}

# 显示当前配置
show_config() {
    echo ""
    echo -e "${BOLD}📋 当前配置:${NC}"
    echo -e "  📧 邮箱: ${CYAN}${EMAIL}${NC}"
    echo -e "  🔑 Token: ${CYAN}${TOKEN:0:10}******${NC}"
    echo ""
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        error "命令 $1 未安装"
        return 1
    fi
    return 0
}

# 检查并安装lego
install_lego() {
    if command -v lego &> /dev/null; then
        info "Lego 已安装，版本: $(lego --version 2>/dev/null | head -n1)"
        return 0
    fi
    
    warn "Lego 未安装，开始安装..."
    
    # 检测系统架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            error "不支持的架构: $ARCH"
            read -n 1 -s -r -p "按任意键返回菜单..."
            return 1
            ;;
    esac
    
    # 最新版本URL
    LEGO_VERSION="v4.12.3"
    LEGO_URL="https://github.com/go-acme/lego/releases/download/${LEGO_VERSION}/lego_${LEGO_VERSION}_linux_${ARCH}.tar.gz"
    
    # 下载并安装
    info "下载 Lego ${LEGO_VERSION}..."
    if ! wget -q $LEGO_URL -O /tmp/lego.tar.gz; then
        error "下载失败，请检查网络连接"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return 1
    fi
    
    info "解压并安装..."
    tar -xzf /tmp/lego.tar.gz -C /tmp
    sudo mv /tmp/lego /usr/local/bin/
    sudo chmod +x /usr/local/bin/lego
    
    # 清理临时文件
    rm -f /tmp/lego.tar.gz
    
    info "Lego 安装完成，版本: $(lego --version | head -n1)"
    return 0
}

# 清理环境变量
cleanup_env() {
    unset CLOUDFLARE_EMAIL
    unset CLOUDFLARE_DNS_API_TOKEN
    unset http_proxy
    unset https_proxy
    unset no_proxy
}

# 通用配置
setup_env() {
    mkdir -p /root/lego
    cd /root/lego || return 1
    
    export no_proxy="localhost,127.0.0.1,localaddress,.localdomain.com"
    export CLOUDFLARE_EMAIL="$EMAIL"
    export CLOUDFLARE_DNS_API_TOKEN="$TOKEN"
}

# 复制证书到Nginx目录
copy_certificates() {
    local domain="$1"
    local cert_dir="/etc/nginx/ssl/${domain}"
    local lego_cert_dir="/root/lego/certificates"
    
    # 检查证书文件是否存在
    if [[ ! -f "$lego_cert_dir/${domain}.crt" ]]; then
        error "证书文件未找到: $lego_cert_dir/${domain}.crt"
        return 1
    fi
    
    if [[ ! -f "$lego_cert_dir/${domain}.key" ]]; then
        error "私钥文件未找到: $lego_cert_dir/${domain}.key"
        return 1
    fi
    
    # 创建Nginx SSL目录
    info "创建Nginx SSL目录: $cert_dir"
    sudo mkdir -p "$cert_dir"
    
    # 复制证书文件
    info "复制证书文件到Nginx目录..."
    sudo cp "$lego_cert_dir/${domain}.crt" "$cert_dir/fullchain.pem"
    sudo cp "$lego_cert_dir/${domain}.key" "$cert_dir/privkey.pem"
    
    # 设置权限
    sudo chmod 600 "$cert_dir/privkey.pem"
    sudo chmod 644 "$cert_dir/fullchain.pem"
    
    # 设置文件所有者为nginx用户（如果存在）
    if id nginx &>/dev/null; then
        sudo chown nginx:nginx "$cert_dir"/*
    elif id www-data &>/dev/null; then
        sudo chown www-data:www-data "$cert_dir"/*
    fi
    
    echo "${cert_dir}/fullchain.pem"
    return 0
}

# 显示证书信息
show_cert_info() {
    local domain="$1"
    local cert_file="$2"
    local key_file="$3"
    local cert_dir="$4"
    
    echo ""
    separator
    info "🎉 证书申请完成！"
    separator
    info "域名: ${domain}"
    info "通配符证书: *.${domain}"
    
    if [[ -f "$cert_file" ]]; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
        info "证书有效期至: $expiry_date"
    fi
    
    separator
    echo "证书文件: $cert_file"
    echo "私钥文件: $key_file"
    echo "证书目录: $cert_dir"
    echo ""
    info "📋 Nginx 配置示例:"
    echo "ssl_certificate     $cert_file;"
    echo "ssl_certificate_key $key_file;"
    separator
    echo ""
}

# 申请证书（支持多域名）
apply_certificate() {
    local domain="$1"
    title "申请 SSL 证书"
    info "域名: $domain"
    info "邮箱: $EMAIL"
    
    # 安装lego
    install_lego
    
    # 设置环境
    if ! setup_env; then
        error "环境设置失败"
        return 1
    fi
    
    # 检查是否已有证书
    if [[ -f "/root/lego/certificates/${domain}.crt" ]]; then
        warn "检测到已有证书，将进行续签而不是重新申请"
        lego --email="$EMAIL" \
        --dns=cloudflare \
        --domains="$domain" \
        --domains="*.$domain" \
        --path="/root/lego/" \
        renew \
        --days=30
        
        if [[ $? -ne 0 ]]; then
            error "证书续签失败"
            cleanup_env
            return 1
        fi
    else
        # 申请新证书
        info "开始DNS验证..."
        lego --email="$EMAIL" \
        --dns=cloudflare \
        --domains="$domain" \
        --domains="*.$domain" \
        --path="/root/lego/" \
        run
        
        if [[ $? -ne 0 ]]; then
            error "证书申请失败"
            cleanup_env
            return 1
        fi
    fi
    
    # 复制证书到Nginx目录
    cert_path=$(copy_certificates "$domain")
    if [[ $? -ne 0 ]]; then
        cleanup_env
        return 1
    fi
    
    cert_dir="/etc/nginx/ssl/${domain}"
    cert_file="${cert_dir}/fullchain.pem"
    key_file="${cert_dir}/privkey.pem"
    
    # 显示证书信息
    show_cert_info "$domain" "$cert_file" "$key_file" "$cert_dir"
    
    # 添加到列表
    add_domain_to_list "$domain"
    
    cleanup_env
    return 0
}

# 获取有效的域名证书文件列表
get_valid_cert_files() {
    local lego_cert_dir="/root/lego/certificates"
    local cert_files=()
    
    if [[ -d "$lego_cert_dir" ]]; then
        # 使用 find 命令查找 .crt 文件，并排除特定文件
        while IFS= read -r -d '' cert_file; do
            local filename=$(basename "$cert_file")
            # 排除 issurer.crt 和其他非域名文件
            if [[ "$filename" != *".issuer.crt" ]] && [[ "$filename" != "_.crt" ]] && [[ "$filename" =~ ^[a-zA-Z0-9] ]]; then
                # 验证文件名格式（应该是域名.crt）
                local domain="${filename%.crt}"
                if [[ "$domain" =~ \. ]] && [[ ! "$domain" =~ ^_ ]]; then
                    cert_files+=("$cert_file")
                fi
            fi
        done < <(find "$lego_cert_dir" -name "*.crt" -type f -print0 2>/dev/null)
    fi
    
    echo "${cert_files[@]}"
}

# 获取有效的域名列表
get_valid_domains() {
    local domains=()
    local cert_files=($(get_valid_cert_files))
    
    for cert_file in "${cert_files[@]}"; do
        if [[ -f "$cert_file" ]]; then
            local domain=$(basename "$cert_file" .crt)
            # 确保是有效的域名格式
            if [[ "$domain" =~ \. ]] && [[ ! "$domain" =~ ^_ ]]; then
                domains+=("$domain")
            fi
        fi
    done
    
    # 去重并排序
    if [[ ${#domains[@]} -gt 0 ]]; then
        readarray -t domains < <(printf '%s\n' "${domains[@]}" | sort -u)
    fi
    
    echo "${domains[@]}"
}

# 单域名申请菜单
single_domain_menu() {
    while true; do
        clear
        title "单域名证书申请"
        
        show_config
        
        echo -e "${BOLD}请输入域名（如: example.com）:${NC}"
        read -p "域名: " domain
        
        if [[ -z "$domain" ]]; then
            error "域名不能为空"
            read -n 1 -s -r -p "按任意键重新输入..."
            continue
        fi
        
        # 验证域名格式
        if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
            error "域名格式不正确"
            read -n 1 -s -r -p "按任意键重新输入..."
            continue
        fi
        
        echo ""
        info "即将申请证书: $domain"
        echo "包含:"
        echo "  • $domain"
        echo "  • *.$domain (通配符)"
        echo ""
        
        read -p "是否继续？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            apply_certificate "$domain"
            if [[ $? -eq 0 ]]; then
                read -n 1 -s -r -p "按任意键返回菜单..."
            else
                read -n 1 -s -r -p "按任意键返回..."
            fi
            break
        else
            break
        fi
    done
}

# 批量续期所有证书
renew_all_certificates() {
    title "批量续期所有证书"
    
    # 检查lego是否安装
    if ! install_lego; then
        return 1
    fi
    
    # 获取有效的证书文件列表
    local cert_files=($(get_valid_cert_files))
    
    if [[ ${#cert_files[@]} -eq 0 ]]; then
        warn "未找到有效的证书文件"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return 1
    fi
    
    info "找到 ${#cert_files[@]} 个有效的证书"
    echo ""
    
    # 设置环境
    if ! setup_env; then
        error "环境设置失败"
        return 1
    fi
    
    local renewed_count=0
    local failed_count=0
    
    # 遍历所有有效的证书文件
    for cert_file in "${cert_files[@]}"; do
        local domain=$(basename "$cert_file" .crt)
        
        echo -e "${BOLD}处理域名: ${CYAN}$domain${NC}"
        
        # 检查证书是否需要续期（30天内过期）
        local days_left=$(openssl x509 -checkend $((30*86400)) -noout -in "$cert_file" 2>/dev/null && echo "有效" || echo "需要续期")
        
        if [[ "$days_left" == "有效" ]]; then
            info "证书在30天内有效，跳过"
            continue
        fi
        
        # 续期证书
        info "开始续期..."
        lego --email="$EMAIL" \
        --dns=cloudflare \
        --domains="$domain" \
        --domains="*.$domain" \
        --path="/root/lego/" \
        renew \
        --days=30
        
        if [[ $? -eq 0 ]]; then
            info "续期成功"
            
            # 复制证书到Nginx目录
            if copy_certificates "$domain"; then
                info "证书已复制到Nginx目录"
            else
                warn "证书复制失败"
            fi
            
            renewed_count=$((renewed_count + 1))
        else
            error "续期失败"
            failed_count=$((failed_count + 1))
        fi
        
        echo ""
    done
    
    # 重载Nginx
    if [[ $renewed_count -gt 0 ]] && command -v nginx &> /dev/null; then
        info "重载Nginx配置..."
        if sudo nginx -t &>/dev/null; then
            sudo systemctl restart nginx
            info "Nginx配置已重载"
        else
            warn "Nginx配置测试失败，请手动检查"
        fi
    fi
    
    echo ""
    separator
    info "续期完成报告:"
    echo "  成功续期: $renewed_count 个"
    echo "  失败: $failed_count 个"
    separator
    
    cleanup_env
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 续期特定域名
renew_specific_domain() {
    clear
    title "续期特定域名"
    
    # 获取有效的域名列表
    local domains=($(get_valid_domains))
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        warn "未找到任何有效的证书"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return 1
    fi
    
    echo -e "${BOLD}📋 现有证书列表:${NC}"
    echo ""
    for i in "${!domains[@]}"; do
        local domain="${domains[$i]}"
        local cert_file="/root/lego/certificates/${domain}.crt"
        
        # 显示证书信息
        if [[ -f "$cert_file" ]]; then
            local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
            echo -e "  ${GREEN}$((i+1))${NC}. ${domain} - 有效期至: ${expiry_date}"
        else
            echo -e "  ${GREEN}$((i+1))${NC}. ${domain} - ${YELLOW}证书文件缺失${NC}"
        fi
    done
    echo ""
    echo -e "  ${GREEN}0${NC}. 返回菜单"
    echo ""
    
    read -p "请选择要续期的域名编号 (输入域名也可): " choice
    
    if [[ "$choice" == "0" ]]; then
        return
    fi
    
    # 检查是否是数字选择
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -le ${#domains[@]} ]] && [[ $choice -gt 0 ]]; then
        local domain="${domains[$((choice-1))]}"
    else
        # 直接使用输入的域名
        local domain="$choice"
    fi
    
    # 验证域名是否有效
    local is_valid_domain=false
    for d in "${domains[@]}"; do
        if [[ "$d" == "$domain" ]]; then
            is_valid_domain=true
            break
        fi
    done
    
    if [[ "$is_valid_domain" == false ]]; then
        error "未找到该域名的有效证书: $domain"
        read -n 1 -s -r -p "按任意键返回..."
        return 1
    fi
    
    # 验证证书文件是否存在
    if [[ ! -f "/root/lego/certificates/${domain}.crt" ]]; then
        error "证书文件不存在: /root/lego/certificates/${domain}.crt"
        read -n 1 -s -r -p "按任意键返回..."
        return 1
    fi
    
    echo ""
    info "开始续期域名: $domain"
    
    # 安装lego
    if ! install_lego; then
        return 1
    fi
    
    # 设置环境
    if ! setup_env; then
        error "环境设置失败"
        return 1
    fi
    
    # 续期证书
    lego --email="$EMAIL" \
    --dns=cloudflare \
    --domains="$domain" \
    --domains="*.$domain" \
    --path="/root/lego/" \
    renew \
    --days=30
    
    if [[ $? -eq 0 ]]; then
        info "续期成功"
        
        # 复制证书到Nginx目录
        if copy_certificates "$domain"; then
            info "证书已复制到Nginx目录"
        fi
        
        # 重载Nginx
        if command -v nginx &> /dev/null; then
            info "重载Nginx配置..."
            sudo systemctl restart nginx
            info "Nginx配置已重载"
        fi
    else
        error "续期失败"
    fi
    
    cleanup_env
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 管理域名列表
manage_domains_list() {
    while true; do
        clear
        title "管理域名列表"
        
        echo -e "${BOLD}📋 当前域名列表:${NC}"
        echo ""
        
        if [[ ${#DOMAINS_LIST[@]} -eq 0 ]]; then
            echo "  列表为空"
        else
            for i in "${!DOMAINS_LIST[@]}"; do
                local domain="${DOMAINS_LIST[$i]}"
                local cert_file="/root/lego/certificates/${domain}.crt"
                
                if [[ -f "$cert_file" ]]; then
                    local days_left="有效"
                    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                    local expiry_secs=$(date -d "$expiry_date" +%s 2>/dev/null)
                    local now_secs=$(date +%s)
                    
                    if [[ -n "$expiry_secs" ]]; then
                        local days_left=$(( (expiry_secs - now_secs) / 86400 ))
                        if [[ $days_left -gt 0 ]]; then
                            days_left="${GREEN}${days_left}天${NC}"
                        else
                            days_left="${RED}已过期${NC}"
                        fi
                    fi
                else
                    days_left="${YELLOW}无证书${NC}"
                fi
                
                echo -e "  ${GREEN}$((i+1))${NC}. ${domain} - 状态: $days_left"
            done
        fi
        
        echo ""
        separator
        echo -e "${BOLD}操作选项:${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}. 添加域名"
        echo -e "  ${GREEN}2${NC}. 移除域名"
        echo -e "  ${GREEN}3${NC}. 清空列表"
        echo -e "  ${GREEN}0${NC}. 返回菜单"
        echo ""
        
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                read -p "请输入要添加的域名: " new_domain
                if [[ -n "$new_domain" ]]; then
                    add_domain_to_list "$new_domain"
                    read -n 1 -s -r -p "按任意键继续..."
                fi
                ;;
            2)
                if [[ ${#DOMAINS_LIST[@]} -eq 0 ]]; then
                    warn "列表为空"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi
                
                read -p "请输入要移除的域名: " remove_domain
                if [[ -n "$remove_domain" ]]; then
                    remove_domain_from_list "$remove_domain"
                    read -n 1 -s -r -p "按任意键继续..."
                fi
                ;;
            3)
                if [[ ${#DOMAINS_LIST[@]} -gt 0 ]]; then
                    read -p "确定要清空域名列表吗？(y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        DOMAINS_LIST=()
                        save_certs_list
                        info "域名列表已清空"
                    fi
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            0)
                break
                ;;
            *)
                error "无效的选择"
                sleep 1
                ;;
        esac
    done
}

# 修改配置
edit_config_menu() {
    while true; do
        clear
        title "修改配置"
        
        show_config
        
        echo -e "${BOLD}📝 配置选项:${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}. 修改邮箱"
        echo -e "  ${GREEN}2${NC}. 修改Cloudflare Token"
        echo -e "  ${GREEN}3${NC}. 查看当前Token"
        echo -e "  ${GREEN}0${NC}. 返回菜单"
        echo ""
        
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                read -p "请输入新的邮箱: " new_email
                if [[ -n "$new_email" ]]; then
                    EMAIL="$new_email"
                    save_config
                    info "邮箱已更新为: $EMAIL"
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            2)
                read -p "请输入Cloudflare Token: " new_token
                if [[ -n "$new_token" ]]; then
                    TOKEN="$new_token"
                    save_config
                    info "Token已更新"
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            3)
                echo ""
                echo -e "${BOLD}当前Token:${NC}"
                echo "$TOKEN"
                echo ""
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            0)
                break
                ;;
            *)
                error "无效的选择"
                sleep 1
                ;;
        esac
    done
}

# 安装Lego工具
install_lego_menu() {
    title "安装 Lego 工具"
    install_lego
}

# 显示帮助信息
show_help() {
    clear
    title "帮助信息"
    
    echo -e "${BOLD}🎯 功能说明:${NC}"
    echo ""
    echo "  1. 申请新证书 - 为单个域名申请SSL证书"
    echo "  2. 批量续期 - 自动续期所有已存在的证书"
    echo "  3. 续期特定域名 - 手动选择域名进行续期"
    echo "  4. 管理域名列表 - 管理需要监控的域名"
    echo "  5. 修改配置 - 更新邮箱和Token"
    echo "  6. 安装Lego - 安装证书管理工具"
    echo ""
    
    echo -e "${BOLD}📁 文件位置:${NC}"
    echo ""
    echo "  配置文件: $CONFIG_FILE"
    echo "  域名列表: $CERTS_LIST_FILE"
    echo "  Lego证书: /root/lego/certificates/"
    echo "  Nginx证书: /etc/nginx/ssl/{域名}/"
    echo ""
    
    echo -e "${BOLD}⚡ 自动续期设置:${NC}"
    echo ""
    echo "  建议设置cron定时任务，每月1号凌晨2点执行:"
    echo "  0 2 1 * * /root/ssl-manager.sh auto-renew"
    echo ""
    echo "  或者每周一凌晨2点检查:"
    echo "  0 2 * * 1 /root/ssl-manager.sh auto-renew"
    echo ""
    
    echo -e "${BOLD}🔧 使用前请确保:${NC}"
    echo ""
    echo "  1. 域名已正确解析到当前服务器"
    echo "  2. Cloudflare API Token有DNS编辑权限"
    echo "  3. 服务器已安装Nginx"
    echo "  4. 以root用户运行此脚本"
    echo ""
    
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 自动续期模式（用于cron任务）
auto_renew_mode() {
    echo "=========================================="
    echo "SSL证书自动续期任务 - $(date)"
    echo "=========================================="
    
    # 加载配置
    load_config
    
    # 检查lego
    if ! command -v lego &> /dev/null; then
        echo "错误: Lego未安装"
        exit 1
    fi
    
    # 获取有效的证书文件
    cert_files=($(get_valid_cert_files))
    
    if [[ ${#cert_files[@]} -eq 0 ]]; then
        echo "未找到有效的证书文件"
        exit 0
    fi
    
    echo "找到 ${#cert_files[@]} 个有效的证书"
    echo ""
    
    # 设置环境
    export CLOUDFLARE_EMAIL="$EMAIL"
    export CLOUDFLARE_DNS_API_TOKEN="$TOKEN"
    export no_proxy="localhost,127.0.0.1,localaddress,.localdomain.com"
    
    renewed_count=0
    failed_count=0
    
    # 遍历所有有效的证书文件
    for cert_file in "${cert_files[@]}"; do
        domain=$(basename "$cert_file" .crt)
        
        echo "处理域名: $domain"
        
        # 检查证书是否需要续期（30天内过期）
        if openssl x509 -checkend $((30*86400)) -noout -in "$cert_file" &>/dev/null; then
            echo "✓ 证书在30天内有效，跳过"
            continue
        fi
        
        # 续期证书
        lego --email="$EMAIL" \
        --dns=cloudflare \
        --domains="$domain" \
        --domains="*.$domain" \
        --path="/root/lego/" \
        renew \
        --days=30
        
        if [[ $? -eq 0 ]]; then
            echo "✓ 续期成功: $domain"
            
            # 复制到Nginx目录
            cert_dir="/etc/nginx/ssl/${domain}"
            mkdir -p "$cert_dir"
            cp "$cert_file" "$cert_dir/fullchain.pem"
            cp "${cert_file%.crt}.key" "$cert_dir/privkey.pem"
            chmod 600 "$cert_dir/privkey.pem"
            
            renewed_count=$((renewed_count + 1))
        else
            echo "✗ 续期失败: $domain"
            failed_count=$((failed_count + 1))
        fi
    done
    
    # 重载Nginx
    if [[ $renewed_count -gt 0 ]] && command -v nginx &> /dev/null; then
        if nginx -t &>/dev/null; then
            sudo systemctl restart nginx
            echo "Nginx配置已重载"
        fi
    fi
    
    echo "=========================================="
    echo "续期完成: 成功 $renewed_count, 失败 $failed_count"
    echo "完成时间: $(date)"
    echo "=========================================="
    
    # 清理环境变量
    unset CLOUDFLARE_EMAIL
    unset CLOUDFLARE_DNS_API_TOKEN
}

# 显示菜单
show_menu() {
    while true; do
        clear
        title "SSL 证书管理工具"
        
        # 显示证书统计
        local domains=($(get_valid_domains))
        local cert_count=${#domains[@]}
        
        echo -e "${BOLD}📊 证书统计:${NC}"
        echo -e "  有效证书: ${CYAN}$cert_count 个${NC}"
        echo -e "  域名列表: ${CYAN}${#DOMAINS_LIST[@]} 个${NC}"
        echo ""
        
        show_config
        
        echo -e "${BOLD}📌 主菜单${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}. 申请新证书"
        echo -e "  ${GREEN}2${NC}. 批量续期所有证书"
        echo -e "  ${GREEN}3${NC}. 续期特定域名"
        echo -e "  ${GREEN}4${NC}. 管理域名列表"
        echo -e "  ${GREEN}5${NC}. 修改配置"
        echo -e "  ${GREEN}6${NC}. 安装Lego工具"
        echo -e "  ${GREEN}7${NC}. 查看帮助"
        echo -e "  ${RED}0${NC}. 退出"
        echo ""
        separator
        
        read -p "请选择操作 (0-7): " choice
        echo ""
        
        case $choice in
            1)
                single_domain_menu
                ;;
            2)
                renew_all_certificates
                ;;
            3)
                renew_specific_domain
                ;;
            4)
                manage_domains_list
                ;;
            5)
                edit_config_menu
                ;;
            6)
                install_lego_menu
                read -n 1 -s -r -p "按任意键返回菜单..."
                ;;
            7)
                show_help
                ;;
            0)
                echo ""
                info "感谢使用，再见！"
                echo ""
                exit 0
                ;;
            *)
                error "无效的选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 主函数
main() {
    # 检查命令行参数
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "auto-renew"|"renew-all")
                auto_renew_mode
                exit 0
                ;;
            "menu")
                # 继续显示菜单
                ;;
            *)
                echo "用法: $0 [command]"
                echo ""
                echo "命令:"
                echo "  menu        显示菜单（默认）"
                echo "  auto-renew  自动续期所有证书（用于cron）"
                echo "  renew-all   自动续期所有证书（用于cron）"
                echo ""
                exit 1
                ;;
        esac
    fi
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        error "请使用root用户运行此脚本"
        echo "尝试使用: sudo $0"
        exit 1
    fi
    
    # 检查必需的命令
    for cmd in wget tar openssl; do
        if ! command -v $cmd &> /dev/null; then
            error "缺少必需的命令: $cmd"
            echo "请安装: apt-get install $cmd (Debian/Ubuntu)"
            echo "或: yum install $cmd (CentOS/RHEL)"
            exit 1
        fi
    done
    
    # 加载配置
    load_config
    
    # 显示菜单
    show_menu
}

# 运行主函数
main "$@"
