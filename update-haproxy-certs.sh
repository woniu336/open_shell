#!/bin/bash

# Let's Encrypt证书整理脚本
# 功能：保留最新证书，删除旧证书，为HAProxy生成合并的证书文件
# 兼容已处理和未处理的证书文件

set -e  # 遇到错误立即退出

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
ARCHIVE_DIR="/etc/letsencrypt/archive"
LIVE_DIR="/etc/letsencrypt/live"
HAPROXY_CERTS_DIR="/etc/haproxy/certs"
CERT_TYPES=("cert" "chain" "fullchain" "privkey")

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

# 检查目录是否存在
if [ ! -d "$ARCHIVE_DIR" ]; then
    log_error "证书目录不存在: $ARCHIVE_DIR"
    exit 1
fi

# 创建HAProxy证书目录（如果不存在）
if [ ! -d "$HAPROXY_CERTS_DIR" ]; then
    log_info "创建HAProxy证书目录: $HAPROXY_CERTS_DIR"
    mkdir -p "$HAPROXY_CERTS_DIR"
fi

# 遍历所有域名文件夹
for domain_dir in "$ARCHIVE_DIR"/*; do
    # 跳过非目录文件
    [ ! -d "$domain_dir" ] && continue
    
    domain=$(basename "$domain_dir")
    log_info "处理域名: $domain"
    
    # 对每种证书类型找到最新版本
    for cert_type in "${CERT_TYPES[@]}"; do
        # 先检查是否已存在无数字后缀的文件
        clean_file="$domain_dir/${cert_type}.pem"
        
        if [ -f "$clean_file" ]; then
            # 文件已经是无数字后缀的，检查是否有其他带数字的旧文件需要删除
            log_info "  ${cert_type}.pem 已存在（无需处理）"
            
            # 删除可能存在的带数字的旧文件
            for old_file in "$domain_dir/${cert_type}"[0-9]*.pem; do
                if [ -f "$old_file" ]; then
                    log_info "    删除旧证书: $(basename "$old_file")"
                    rm -f "$old_file"
                fi
            done
        else
            # 查找带数字后缀的文件
            latest_file=$(ls -v "$domain_dir/${cert_type}"[0-9]*.pem 2>/dev/null | tail -n 1)
            
            if [ -z "$latest_file" ]; then
                log_warn "  未找到 ${cert_type} 类型的证书文件"
                continue
            fi
            
            # 获取最新文件的编号
            latest_num=$(echo "$latest_file" | grep -oP "${cert_type}\K[0-9]+(?=\.pem)")
            log_info "  ${cert_type} 最新版本: ${cert_type}${latest_num}.pem"
            
            # 删除旧版本证书
            for old_file in "$domain_dir/${cert_type}"[0-9]*.pem; do
                old_num=$(echo "$old_file" | grep -oP "${cert_type}\K[0-9]+(?=\.pem)")
                if [ "$old_num" != "$latest_num" ]; then
                    log_info "    删除旧证书: $(basename "$old_file")"
                    rm -f "$old_file"
                fi
            done
            
            # 重命名最新证书（去掉数字后缀）
            log_info "    重命名: $(basename "$latest_file") -> ${cert_type}.pem"
            mv "$latest_file" "$clean_file"
        fi
    done
    
    # 更新 /etc/letsencrypt/live/ 中的符号链接
    live_domain_dir="$LIVE_DIR/$domain"
    if [ -d "$live_domain_dir" ]; then
        log_info "  更新符号链接: $live_domain_dir"
        for cert_type in "${CERT_TYPES[@]}"; do
            link_file="$live_domain_dir/${cert_type}.pem"
            target_file="../../archive/$domain/${cert_type}.pem"
            
            # 检查链接是否已经正确
            if [ -L "$link_file" ]; then
                current_target=$(readlink "$link_file")
                if [ "$current_target" = "$target_file" ]; then
                    log_info "    链接已正确: ${cert_type}.pem"
                    continue
                fi
                # 删除错误的符号链接
                rm -f "$link_file"
            fi
            
            # 创建新的符号链接
            if [ -f "$domain_dir/${cert_type}.pem" ]; then
                ln -s "$target_file" "$link_file"
                log_info "    创建链接: ${cert_type}.pem -> $target_file"
            fi
        done
    else
        log_warn "  未找到对应的live目录: $live_domain_dir"
    fi
    
    # 检查必需的证书文件是否存在
    fullchain_file="$domain_dir/fullchain.pem"
    privkey_file="$domain_dir/privkey.pem"
    
    if [ ! -f "$fullchain_file" ] || [ ! -f "$privkey_file" ]; then
        log_error "  缺少必需的证书文件 (fullchain.pem 或 privkey.pem)"
        continue
    fi
    
    # 合并证书文件（fullchain在上，privkey在下）
    combined_cert="$HAPROXY_CERTS_DIR/${domain}.pem"
    log_info "  生成合并证书: ${domain}.pem"
    cat "$fullchain_file" "$privkey_file" > "$combined_cert"
    
    # 设置适当的权限
    chmod 600 "$combined_cert"
    log_info "  设置权限: 600"
    
    log_info "  ✓ 域名 $domain 处理完成"
    echo ""
done

# 重启HAProxy服务
log_info "重启HAProxy服务..."
if systemctl restart haproxy; then
    log_info "✓ HAProxy重启成功"
else
    log_error "✗ HAProxy重启失败"
    exit 1
fi

log_info "========================================="
log_info "所有证书处理完成！"
log_info "证书状态验证："
log_info "========================================="

# 验证证书状态
if [ -d "$LIVE_DIR" ]; then
    echo -e "${YELLOW}已申请的证书到期情况${NC}"
    echo "站点信息                      证书到期时间"
    echo "------------------------------------------------"
    for cert_dir in "$LIVE_DIR"/*; do
        if [ -d "$cert_dir" ]; then
            cert_file="$cert_dir/fullchain.pem"
            if [ -f "$cert_file" ] || [ -L "$cert_file" ]; then
                domain=$(basename "$cert_dir")
                if expire_date=$(openssl x509 -noout -enddate -in "$cert_file" 2>/dev/null | awk -F'=' '{print $2}'); then
                    formatted_date=$(date -d "$expire_date" '+%Y-%m-%d' 2>/dev/null || echo "$expire_date")
                    printf "%-30s%s\n" "$domain" "$formatted_date"
                else
                    printf "%-30s%s\n" "$domain" "无法读取证书"
                fi
            fi
        fi
    done
    echo ""
fi
