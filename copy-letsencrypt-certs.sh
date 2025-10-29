#!/bin/bash

# Let's Encrypt证书自动复制脚本
# 用途：将Let's Encrypt证书复制到Nginx证书目录并重载Nginx

set -e  # 遇到错误立即退出

# 定义目录
LETSENCRYPT_DIR="/etc/letsencrypt/live"
NGINX_CERTS_DIR="/etc/nginx/certs"
LOG_FILE="/var/log/nginx-cert-copy.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    log "错误：请使用root权限运行此脚本"
    exit 1
fi

# 检查源目录是否存在
if [ ! -d "$LETSENCRYPT_DIR" ]; then
    log "错误：Let's Encrypt目录不存在: $LETSENCRYPT_DIR"
    exit 1
fi

# 确保Nginx证书目录存在
if [ ! -d "$NGINX_CERTS_DIR" ]; then
    log "创建Nginx证书目录: $NGINX_CERTS_DIR"
    mkdir -p "$NGINX_CERTS_DIR"
fi

log "========== 开始复制证书 =========="

# 证书复制计数器
copied_count=0
error_count=0

# 临时关闭set -e，避免在循环中因错误退出
set +e

# 遍历letsencrypt目录下的所有子目录
for domain_dir in "$LETSENCRYPT_DIR"/*; do
    # 跳过README文件和非目录
    if [ ! -d "$domain_dir" ]; then
        continue
    fi
    
    domain=$(basename "$domain_dir")
    
    # 跳过README目录（如果存在）
    if [ "$domain" = "README" ]; then
        log "跳过: $domain"
        continue
    fi
    
    fullchain_src="$domain_dir/fullchain.pem"
    privkey_src="$domain_dir/privkey.pem"
    
    # 检查证书文件是否存在
    if [ ! -f "$fullchain_src" ] || [ ! -f "$privkey_src" ]; then
        log "警告: $domain 的证书文件不完整，跳过"
        error_count=$((error_count + 1))
        continue
    fi
    
    # 定义目标文件路径
    fullchain_dest="$NGINX_CERTS_DIR/${domain}_cert.pem"
    privkey_dest="$NGINX_CERTS_DIR/${domain}_key.pem"
    
    # 复制证书文件
    if cp "$fullchain_src" "$fullchain_dest" && cp "$privkey_src" "$privkey_dest"; then
        # 设置正确的权限
        chmod 644 "$fullchain_dest"
        chmod 600 "$privkey_dest"
        log "成功: $domain 证书已复制"
        copied_count=$((copied_count + 1))
    else
        log "错误: 复制 $domain 证书失败"
        error_count=$((error_count + 1))
    fi
done

# 重新启用set -e
set -e

log "========== 复制完成 =========="
log "成功复制: $copied_count 个域名"
log "失败/跳过: $error_count 个域名"

# 只有在成功复制了至少一个证书时才重载Nginx
if [ $copied_count -gt 0 ]; then
    log "========== 测试Nginx配置 =========="
    if nginx -t 2>&1 | tee -a "$LOG_FILE"; then
        log "Nginx配置测试通过"
        log "========== 重载Nginx =========="
        if service nginx reload; then
            log "成功: Nginx已重载"
            exit 0
        else
            log "错误: Nginx重载失败"
            exit 1
        fi
    else
        log "错误: Nginx配置测试失败，不执行重载"
        exit 1
    fi
else
    log "警告: 没有成功复制任何证书，跳过Nginx重载"
    exit 1
fi
