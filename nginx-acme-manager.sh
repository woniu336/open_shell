#!/bin/bash

# Nginx ACME 自动化管理脚本
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NGINX_PREFIX="/app/nginx"
BUILD_DIR="/app/nginx-build"
NGINX_VERSION="1.28.0"

# 打印带颜色的消息
print_msg() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否以root运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户或 sudo 运行此脚本"
        exit 1
    fi
}

# 安装系统依赖
install_dependencies() {
    print_msg "开始安装系统依赖..."
    apt update
    apt install -y build-essential libpcre3-dev zlib1g-dev libssl-dev \
        pkg-config libclang-dev git wget curl tree
    
    if [ $? -eq 0 ]; then
        print_msg "系统依赖安装完成"
    else
        print_error "系统依赖安装失败"
        exit 1
    fi
}

# 安装 Rust 工具链
install_rust() {
    print_msg "开始安装 Rust 工具链..."
    if command -v rustc &> /dev/null; then
        print_warning "Rust 已安装，跳过..."
        return 0
    fi
    
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    
    if command -v rustc &> /dev/null; then
        print_msg "Rust 工具链安装完成"
    else
        print_error "Rust 工具链安装失败"
        exit 1
    fi
}

# 创建目录结构
create_directories() {
    print_msg "创建目录结构..."
    mkdir -pv ${NGINX_PREFIX}/{logs,conf,cache,acme} ${BUILD_DIR}
    mkdir -pv ${NGINX_PREFIX}/cache/{client_temp,proxy_cache}
    mkdir -pv ${NGINX_PREFIX}/acme/{letsencrypt,staging}
    mkdir -pv ${NGINX_PREFIX}/conf/conf.d
    print_msg "目录结构创建完成"
}

# 下载源码
download_sources() {
    print_msg "开始下载源码..."
    cd ${BUILD_DIR}
    
    # 下载 ACME 模块
    if [ ! -d "${BUILD_DIR}/nginx-acme" ]; then
        print_msg "下载 ACME 模块..."
        git clone https://github.com/nginx/nginx-acme.git ${BUILD_DIR}/nginx-acme
    else
        print_warning "ACME 模块已存在，跳过下载"
    fi
    
    # 下载 Nginx 源码
    if [ ! -f "nginx-${NGINX_VERSION}.tar.gz" ]; then
        print_msg "下载 Nginx ${NGINX_VERSION}..."
        wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
    else
        print_warning "Nginx 源码已存在，跳过下载"
    fi
    
    # 解压
    if [ ! -d "nginx-${NGINX_VERSION}" ]; then
        tar -zxf nginx-${NGINX_VERSION}.tar.gz
    fi
    
    print_msg "源码下载完成"
}

# 编译 Nginx
compile_nginx() {
    print_msg "开始编译 Nginx (大约需要 5 分钟)..."
    cd ${BUILD_DIR}/nginx-${NGINX_VERSION}
    
    ./configure \
        --prefix=${NGINX_PREFIX} \
        --error-log-path=${NGINX_PREFIX}/logs/error.log \
        --http-log-path=${NGINX_PREFIX}/logs/access.log \
        --pid-path=${NGINX_PREFIX}/nginx.pid \
        --lock-path=${NGINX_PREFIX}/nginx.lock \
        --http-client-body-temp-path=${NGINX_PREFIX}/cache/client_temp \
        --http-proxy-temp-path=${NGINX_PREFIX}/cache/proxy_temp \
        --user=nginx \
        --group=nginx \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_realip_module \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
        --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
        --add-dynamic-module=${BUILD_DIR}/nginx-acme
    
    if [ $? -ne 0 ]; then
        print_error "配置失败"
        exit 1
    fi
    
    make && make modules && make install
    
    if [ $? -eq 0 ]; then
        print_msg "Nginx 编译安装完成"
    else
        print_error "Nginx 编译安装失败"
        exit 1
    fi
}

# 创建 nginx 用户
create_nginx_user() {
    if id "nginx" &>/dev/null; then
        print_warning "nginx 用户已存在"
    else
        print_msg "创建 nginx 用户..."
        useradd -r -s /sbin/nologin nginx
    fi
}

# 设置权限
set_permissions() {
    print_msg "设置目录权限..."
    chown -R nginx:nginx ${NGINX_PREFIX}
}

# 配置全局 nginx.conf
configure_nginx() {
    print_msg "配置全局 nginx.conf..."
    read -p "请输入 ACME 联系邮箱: " ACME_EMAIL
    
    if [ -z "$ACME_EMAIL" ]; then
        ACME_EMAIL="admin@example.com"
        print_warning "未输入邮箱，使用默认: $ACME_EMAIL"
    fi
    
    cat > ${NGINX_PREFIX}/conf/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;

error_log logs/error.log warn;
pid nginx.pid;

# ACME 模块
load_module modules/ngx_http_acme_module.so;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    include mime.types;
    default_type application/octet-stream;

    # 日志
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';
    access_log logs/access.log main;

    # 基础性能
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65s 60s;
    keepalive_requests 1000;
    reset_timedout_connection on;

    # === 客户端请求体配置 ===
    client_max_body_size 100m;
    client_body_buffer_size 256k;
    client_body_timeout 30s;
	
    # === 客户端请求头配置 ===
    client_header_buffer_size 4k;
    large_client_header_buffers 4 16k;
    client_header_timeout 10s;
    
    # === 临时文件路径 ===
    client_body_temp_path cache/client_temp;
    
    # === 防止慢速攻击 ===
    client_body_in_single_buffer off;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1024;
    gzip_buffers 16 8k;
    gzip_types
        text/plain
        text/css
        application/json
        application/javascript
        application/xml+rss
        application/rss+xml
        application/atom+xml
        application/xhtml+xml
        font/truetype
        font/opentype
        application/vnd.ms-fontobject
        image/svg+xml;
    gzip_disable "msie6";

    # DNS
    resolver 8.8.8.8 1.0.0.1 valid=300s ipv6=off;
    resolver_timeout 5s;

    # 全局代理头（所有站点都生效）
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_hide_header X-Powered-By;
    proxy_hide_header Server;

    # 隐藏 Nginx 版本号
    server_tokens off;

    # ACME
    acme_shared_zone zone=acme_shared:2M;
    acme_issuer letsencrypt {
        uri https://acme-v02.api.letsencrypt.org/directory;
        contact mailto:ACME_EMAIL_PLACEHOLDER;
        state_path acme/letsencrypt;
        accept_terms_of_service;
    }

    # SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:20m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_buffer_size 4k;

    # 全局限流（保持）
    limit_req_zone $binary_remote_addr zone=req_limit:10m rate=200r/s;
    limit_req zone=req_limit burst=300;
    limit_req_status 429;

    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
    limit_conn conn_limit 100;
    limit_conn_status 429;

    # HTTP → HTTPS 跳转
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;
        location / {
            return 301 https://$host$request_uri;
        }
    }

    # 禁止 IP 直接访问
    server {
        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;
        server_name _;
        ssl_reject_handshake on;
    }

    include conf.d/*.conf;
}
EOF
    
    # 替换邮箱
    sed -i "s/ACME_EMAIL_PLACEHOLDER/$ACME_EMAIL/g" ${NGINX_PREFIX}/conf/nginx.conf
    print_msg "nginx.conf 配置完成"
}

# 添加站点配置（多域名带跳转）
add_site_with_redirect() {
    read -p "请输入主域名（如 example.com）: " DOMAIN
    read -p "请输入源站 IP:PORT（如 6.6.6.6:80）: " BACKEND
    read -p "是否添加备用源站？(y/n): " ADD_BACKUP
    
    BACKUP_SERVER=""
    if [ "$ADD_BACKUP" = "y" ]; then
        read -p "请输入备用源站 IP:PORT: " BACKUP
        BACKUP_SERVER="    #server ${BACKUP} backup;"
    fi
    
    UPSTREAM_NAME=$(echo $DOMAIN | sed 's/\./_/g')
    
    cat > ${NGINX_PREFIX}/conf/conf.d/${DOMAIN}.conf << EOF
upstream ${UPSTREAM_NAME} {
    server ${BACKEND};
${BACKUP_SERVER}
    keepalive 32;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ${DOMAIN} www.${DOMAIN};

    # 根域名跳转
    if (\$host = ${DOMAIN}) {
        return 301 https://www.${DOMAIN}\$request_uri;
    }

    access_log logs/${DOMAIN}-access.log;
    error_log logs/${DOMAIN}-error.log warn;

    acme_certificate letsencrypt;
    ssl_certificate \$acme_certificate;
    ssl_certificate_key \$acme_certificate_key;
    ssl_certificate_cache max=2;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    location / {
        proxy_pass http://${UPSTREAM_NAME};
        proxy_http_version 1.1;

        # 代理超时与重试
        proxy_connect_timeout 5s;
        proxy_send_timeout 15s;
        proxy_read_timeout 15s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root ${NGINX_PREFIX}/html;
        internal;
    }
}
EOF
    
    print_msg "站点配置已创建: ${NGINX_PREFIX}/conf/conf.d/${DOMAIN}.conf"
}

# 添加站点配置（单域名无跳转）
add_site_single() {
    read -p "请输入域名（如 tv.example.com）: " DOMAIN
    read -p "请输入源站 IP:PORT（如 6.6.6.6:80）: " BACKEND
    read -p "是否添加备用源站？(y/n): " ADD_BACKUP
    
    BACKUP_SERVER=""
    if [ "$ADD_BACKUP" = "y" ]; then
        read -p "请输入备用源站 IP:PORT: " BACKUP
        BACKUP_SERVER="    #server ${BACKUP} backup;"
    fi
    
    UPSTREAM_NAME=$(echo $DOMAIN | sed 's/\./_/g')
    
    cat > ${NGINX_PREFIX}/conf/conf.d/${DOMAIN}.conf << EOF
upstream ${UPSTREAM_NAME} {
    server ${BACKEND};
${BACKUP_SERVER}
    keepalive 32;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ${DOMAIN};

    access_log logs/${DOMAIN}-access.log;
    error_log logs/${DOMAIN}-error.log warn;

    acme_certificate letsencrypt;
    ssl_certificate \$acme_certificate;
    ssl_certificate_key \$acme_certificate_key;
    ssl_certificate_cache max=2;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    location / {
        proxy_pass http://${UPSTREAM_NAME};
        proxy_http_version 1.1;

        # 代理超时与重试
        proxy_connect_timeout 5s;
        proxy_send_timeout 15s;
        proxy_read_timeout 15s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root ${NGINX_PREFIX}/html;
        internal;
    }
}
EOF
    
    print_msg "站点配置已创建: ${NGINX_PREFIX}/conf/conf.d/${DOMAIN}.conf"
}

# 测试配置
test_config() {
    print_msg "测试 Nginx 配置..."
    cd ${NGINX_PREFIX}
    ./sbin/nginx -c conf/nginx.conf -t
}

# 启动 Nginx
start_nginx() {
    print_msg "启动 Nginx..."
    cd ${NGINX_PREFIX}
    ./sbin/nginx -c conf/nginx.conf
    
    if [ $? -eq 0 ]; then
        print_msg "Nginx 启动成功"
    else
        print_error "Nginx 启动失败（可能已在运行）"
    fi
}

# 重载 Nginx
reload_nginx() {
    print_msg "重载 Nginx 配置..."
    cd ${NGINX_PREFIX}
    ./sbin/nginx -c conf/nginx.conf -s reload
    
    if [ $? -eq 0 ]; then
        print_msg "Nginx 重载成功"
    else
        print_error "Nginx 重载失败"
    fi
}

# 停止 Nginx
stop_nginx() {
    print_msg "停止 Nginx..."
    cd ${NGINX_PREFIX}
    ./sbin/nginx -s stop
    
    if [ $? -eq 0 ]; then
        print_msg "Nginx 已停止"
    else
        print_error "Nginx 停止失败"
    fi
}

# 查看证书
view_certificates() {
    print_msg "证书目录结构:"
    cd ${NGINX_PREFIX}
    tree acme/ modules/ 2>/dev/null || ls -lR acme/ modules/
}

# 列出站点
list_sites() {
    print_msg "已配置的站点:"
    ls -1 ${NGINX_PREFIX}/conf/conf.d/*.conf 2>/dev/null | xargs -n1 basename
}

# 删除站点
delete_site() {
    list_sites
    read -p "请输入要删除的配置文件名（如 example.com.conf）: " CONF_FILE
    
    if [ -f "${NGINX_PREFIX}/conf/conf.d/${CONF_FILE}" ]; then
        rm -f ${NGINX_PREFIX}/conf/conf.d/${CONF_FILE}
        print_msg "站点配置已删除: ${CONF_FILE}"
    else
        print_error "配置文件不存在"
    fi
}

# 查看状态
check_status() {
    if pgrep -x "nginx" > /dev/null; then
        print_msg "Nginx 运行中"
        ps aux | grep nginx | grep -v grep
    else
        print_warning "Nginx 未运行"
    fi
}

# 备份配置
backup_config() {
    BACKUP_DIR="/root/nginx_backup_$(date +%Y%m%d_%H%M%S)"
    print_msg "开始备份到: ${BACKUP_DIR}"
    
    mkdir -p ${BACKUP_DIR}
    
    # 备份配置文件
    if [ -d "${NGINX_PREFIX}/conf" ]; then
        cp -r ${NGINX_PREFIX}/conf ${BACKUP_DIR}/
        print_msg "配置文件已备份"
    fi
    
    # 备份证书
    if [ -d "${NGINX_PREFIX}/acme" ]; then
        cp -r ${NGINX_PREFIX}/acme ${BACKUP_DIR}/
        print_msg "证书文件已备份"
    fi
    
    # 创建备份信息文件
    cat > ${BACKUP_DIR}/backup_info.txt << EOF
备份时间: $(date)
Nginx 版本: ${NGINX_VERSION}
Nginx 路径: ${NGINX_PREFIX}
构建路径: ${BUILD_DIR}
EOF
    
    print_msg "备份完成: ${BACKUP_DIR}"
    ls -lh ${BACKUP_DIR}
}

# 恢复配置
restore_config() {
    print_msg "可用的备份目录："
    ls -dt /root/nginx_backup_* 2>/dev/null
    
    if [ $? -ne 0 ]; then
        print_error "没有找到备份目录"
        return
    fi
    
    echo ""
    read -p "请输入要恢复的备份目录完整路径: " RESTORE_DIR
    
    if [ ! -d "$RESTORE_DIR" ]; then
        print_error "备份目录不存在"
        return
    fi
    
    # 显示备份信息
    if [ -f "$RESTORE_DIR/backup_info.txt" ]; then
        echo ""
        print_msg "备份信息："
        cat "$RESTORE_DIR/backup_info.txt"
        echo ""
    fi
    
    read -p "确认恢复此备份？(y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        print_warning "已取消恢复操作"
        return
    fi
    
    # 停止 Nginx
    if pgrep -x "nginx" > /dev/null; then
        print_msg "停止 Nginx 服务..."
        ${NGINX_PREFIX}/sbin/nginx -s stop 2>/dev/null
        sleep 2
    fi
    
    # 恢复配置文件
    if [ -d "$RESTORE_DIR/conf" ]; then
        print_msg "恢复配置文件..."
        rm -rf ${NGINX_PREFIX}/conf.bak 2>/dev/null
        mv ${NGINX_PREFIX}/conf ${NGINX_PREFIX}/conf.bak 2>/dev/null
        cp -r $RESTORE_DIR/conf ${NGINX_PREFIX}/
        print_msg "配置文件已恢复"
    fi
    
    # 恢复证书
    if [ -d "$RESTORE_DIR/acme" ]; then
        print_msg "恢复证书文件..."
        rm -rf ${NGINX_PREFIX}/acme.bak 2>/dev/null
        mv ${NGINX_PREFIX}/acme ${NGINX_PREFIX}/acme.bak 2>/dev/null
        cp -r $RESTORE_DIR/acme ${NGINX_PREFIX}/
        print_msg "证书文件已恢复"
    fi
    
    # 设置权限
    chown -R nginx:nginx ${NGINX_PREFIX}
    
    print_msg "=== 恢复完成 ==="
    print_warning "旧配置已备份到 ${NGINX_PREFIX}/conf.bak 和 ${NGINX_PREFIX}/acme.bak"
    print_msg "请测试配置后重新启动 Nginx"
}

# 日志管理菜单
log_management() {
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}          日志管理${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo "  1) 查看日志统计"
        echo "  2) 备份日志"
        echo "  3) 删除旧日志"
        echo "  4) 清空所有日志"
        echo "  0) 返回主菜单"
        echo ""
        echo -e "${BLUE}========================================${NC}"
        
        read -p "请选择操作 [0-4]: " log_choice
        
        case $log_choice in
            1) view_log_stats ;;
            2) backup_logs ;;
            3) delete_old_logs ;;
            4) clear_all_logs ;;
            0) return ;;
            *) print_error "无效选项，请重新选择" ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 查看日志统计
view_log_stats() {
    print_msg "日志目录统计："
    if [ -d "${NGINX_PREFIX}/logs" ]; then
        echo ""
        echo "文件列表："
        ls -lh ${NGINX_PREFIX}/logs/
        echo ""
        echo "磁盘占用："
        du -sh ${NGINX_PREFIX}/logs/
        echo ""
        echo "文件数量："
        find ${NGINX_PREFIX}/logs/ -type f | wc -l
    else
        print_error "日志目录不存在"
    fi
}

# 备份日志
backup_logs() {
    LOG_BACKUP_DIR="/root/nginx_logs_backup_$(date +%Y%m%d_%H%M%S)"
    
    read -p "备份最近几天的日志？(默认7天): " DAYS
    DAYS=${DAYS:-7}
    
    print_msg "开始备份最近 ${DAYS} 天的日志到: ${LOG_BACKUP_DIR}"
    
    mkdir -p ${LOG_BACKUP_DIR}
    
    if [ -d "${NGINX_PREFIX}/logs" ]; then
        find ${NGINX_PREFIX}/logs -type f -mtime -${DAYS} -exec cp {} ${LOG_BACKUP_DIR}/ \;
        
        # 创建备份信息
        cat > ${LOG_BACKUP_DIR}/backup_info.txt << EOF
备份时间: $(date)
备份范围: 最近 ${DAYS} 天
Nginx 路径: ${NGINX_PREFIX}
EOF
        
        print_msg "日志备份完成: ${LOG_BACKUP_DIR}"
        ls -lh ${LOG_BACKUP_DIR}
    else
        print_error "日志目录不存在"
    fi
}

# 删除旧日志
delete_old_logs() {
    read -p "删除多少天前的日志？(默认30天): " DAYS
    DAYS=${DAYS:-30}
    
    echo ""
    print_warning "将删除 ${DAYS} 天前的日志文件"
    
    if [ -d "${NGINX_PREFIX}/logs" ]; then
        echo ""
        echo "将删除以下文件："
        find ${NGINX_PREFIX}/logs -type f -mtime +${DAYS}
        echo ""
        
        read -p "确认删除？(y/n): " CONFIRM
        if [ "$CONFIRM" = "y" ]; then
            DELETED=$(find ${NGINX_PREFIX}/logs -type f -mtime +${DAYS} | wc -l)
            find ${NGINX_PREFIX}/logs -type f -mtime +${DAYS} -delete
            print_msg "已删除 ${DELETED} 个旧日志文件"
        else
            print_warning "已取消删除操作"
        fi
    else
        print_error "日志目录不存在"
    fi
}

# 清空所有日志
clear_all_logs() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}        警告：清空所有日志${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    print_warning "此操作将清空 ${NGINX_PREFIX}/logs 目录下的所有日志文件"
    echo ""
    read -p "确认清空所有日志？输入 YES 继续: " CONFIRM
    
    if [ "$CONFIRM" != "YES" ]; then
        print_warning "已取消清空操作"
        return
    fi
    
    if [ -d "${NGINX_PREFIX}/logs" ]; then
        rm -f ${NGINX_PREFIX}/logs/*.log
        print_msg "所有日志文件已清空"
        
        # 重新加载 Nginx 以创建新日志文件
        if pgrep -x "nginx" > /dev/null; then
            ${NGINX_PREFIX}/sbin/nginx -s reopen 2>/dev/null
            print_msg "日志文件已重新打开"
        fi
    else
        print_error "日志目录不存在"
    fi
}

# 卸载 Nginx（修正版）
uninstall_nginx() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}        警告：卸载操作${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "此操作将删除："
    echo "  - Nginx 程序目录: ${NGINX_PREFIX}"
    echo "  - 源码编译目录: ${BUILD_DIR}"
    echo "  - nginx 系统用户"
    echo ""
    echo -e "${YELLOW}注意：此操作不可恢复！${NC}"
    echo -e "${YELLOW}建议在卸载前先执行备份操作（菜单选项 12）${NC}"
    echo ""
    read -p "确认卸载？输入 YES 继续，其他键取消: " CONFIRM
    
    if [ "$CONFIRM" != "YES" ]; then
        print_warning "已取消卸载操作"
        return
    fi
    
    # 1. 停止 Nginx 服务（多次尝试确保停止）
    if pgrep -x "nginx" > /dev/null; then
        print_msg "停止 Nginx 服务..."
        
        # 尝试优雅停止
        if [ -f "${NGINX_PREFIX}/sbin/nginx" ]; then
            ${NGINX_PREFIX}/sbin/nginx -s quit 2>/dev/null
            sleep 3
        fi
        
        # 检查是否还在运行
        if pgrep -x "nginx" > /dev/null; then
            print_warning "优雅停止失败，尝试强制停止..."
            ${NGINX_PREFIX}/sbin/nginx -s stop 2>/dev/null
            sleep 2
        fi
        
        # 最后检查，如果还在运行则强制杀死进程
        if pgrep -x "nginx" > /dev/null; then
            print_warning "强制停止失败，使用 kill 命令..."
            pkill -9 nginx 2>/dev/null
            sleep 1
        fi
        
        # 验证是否已停止
        if pgrep -x "nginx" > /dev/null; then
            print_error "无法停止 Nginx 进程，卸载中止"
            print_warning "请手动停止所有 Nginx 进程后重试"
            return 1
        else
            print_msg "Nginx 服务已停止"
        fi
    else
        print_msg "Nginx 未在运行"
    fi
    
    # 2. 删除 Nginx 程序目录
    if [ -d "${NGINX_PREFIX}" ]; then
        print_msg "删除 Nginx 程序目录: ${NGINX_PREFIX}"
        rm -rf ${NGINX_PREFIX}
        if [ $? -eq 0 ]; then
            print_msg "✓ Nginx 程序目录已删除"
        else
            print_error "✗ 删除 Nginx 程序目录失败"
        fi
    else
        print_warning "Nginx 程序目录不存在，跳过"
    fi
    
    # 3. 删除源码编译目录
    if [ -d "${BUILD_DIR}" ]; then
        print_msg "删除源码编译目录: ${BUILD_DIR}"
        rm -rf ${BUILD_DIR}
        if [ $? -eq 0 ]; then
            print_msg "✓ 源码编译目录已删除"
        else
            print_error "✗ 删除源码编译目录失败"
        fi
    else
        print_warning "源码编译目录不存在，跳过"
    fi
    
    # 4. 删除 nginx 用户（确保没有进程在使用）
    if id "nginx" &>/dev/null; then
        print_msg "删除 nginx 系统用户..."
        
        # 检查是否有进程属于 nginx 用户
        if ps -u nginx &>/dev/null; then
            print_warning "检测到 nginx 用户还有运行的进程，尝试终止..."
            pkill -9 -u nginx 2>/dev/null
            sleep 1
        fi
        
        # 删除用户
        userdel nginx 2>/dev/null
        if [ $? -eq 0 ]; then
            print_msg "✓ nginx 用户已删除"
        else
            # 尝试强制删除
            userdel -f nginx 2>/dev/null
            if [ $? -eq 0 ]; then
                print_msg "✓ nginx 用户已强制删除"
            else
                print_warning "✗ 删除 nginx 用户失败（可能需要手动删除）"
            fi
        fi
        
        # 删除用户的家目录（如果存在）
        if [ -d "/home/nginx" ]; then
            rm -rf /home/nginx
            print_msg "✓ nginx 用户家目录已删除"
        fi
    else
        print_warning "nginx 用户不存在，跳过"
    fi
    
    # 5. 清理可能残留的 PID 和 lock 文件
    print_msg "清理残留文件..."
    rm -f /var/run/nginx.pid 2>/dev/null
    rm -f /var/lock/nginx.lock 2>/dev/null
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}        卸载完成${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "已完成的操作："
    echo "  ✓ 停止 Nginx 服务"
    echo "  ✓ 删除 Nginx 程序目录 (${NGINX_PREFIX})"
    echo "  ✓ 删除源码编译目录 (${BUILD_DIR})"
    echo "  ✓ 删除 nginx 系统用户"
    echo "  ✓ 清理残留文件"
    echo ""
    print_msg "卸载完成！如需重新安装，请运行菜单选项 1"
    echo ""
}

# 完整安装
full_install() {
    check_root
    install_dependencies
    install_rust
    create_directories
    download_sources
    compile_nginx
    create_nginx_user
    set_permissions
    configure_nginx
    print_msg "=== 安装完成 ==="
    print_msg "请使用菜单选项测试配置并启动 Nginx"
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Nginx ACME 自动化管理脚本${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "  1) 完整安装（首次使用）"
    echo "  2) 添加站点（多域名带跳转）"
    echo "  3) 添加站点（单域名无跳转）"
    echo "  4) 列出所有站点"
    echo "  5) 删除站点配置"
    echo "  6) 测试配置"
    echo "  7) 启动 Nginx"
    echo "  8) 重载 Nginx"
    echo "  9) 停止 Nginx"
    echo " 10) 查看证书"
    echo " 11) 查看 Nginx 状态"
    echo " 12) 备份配置和证书"
    echo " 13) 恢复配置和证书"
    echo " 14) 日志管理"
    echo " 15) 卸载 Nginx"
    echo "  0) 退出"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# 主循环
main() {
    while true; do
        show_menu
        read -p "请选择操作 [0-15]: " choice
        
        case $choice in
            1) full_install ;;
            2) add_site_with_redirect; reload_nginx ;;
            3) add_site_single; reload_nginx ;;
            4) list_sites ;;
            5) delete_site; reload_nginx ;;
            6) test_config ;;
            7) start_nginx ;;
            8) reload_nginx ;;
            9) stop_nginx ;;
            10) view_certificates ;;
            11) check_status ;;
            12) backup_config ;;
            13) restore_config ;;
            14) log_management ;;
            15) uninstall_nginx ;;
            0) print_msg "退出脚本"; exit 0 ;;
            *) print_error "无效选项，请重新选择" ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 运行主程序
main
