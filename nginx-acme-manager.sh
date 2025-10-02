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
    keepalive_timeout 65;
    keepalive_requests 100;
    reset_timedout_connection on;

    client_max_body_size 100m;
    client_body_buffer_size 128k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 8k;

    client_body_temp_path cache/client_temp;

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

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

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

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    location / {
        proxy_pass http://${UPSTREAM_NAME};
        proxy_http_version 1.1;

        # 代理超时与重试
        proxy_connect_timeout 5s;
        proxy_send_timeout 15s;
        proxy_read_timeout 15s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }

    location ^~ /.well-known/acme-challenge/ {
        root ${NGINX_PREFIX}/html;
        allow all;
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

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    location / {
        proxy_pass http://${UPSTREAM_NAME};
        proxy_http_version 1.1;

        # 代理超时与重试
        proxy_connect_timeout 5s;
        proxy_send_timeout 15s;
        proxy_read_timeout 15s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }

    location ^~ /.well-known/acme-challenge/ {
        root ${NGINX_PREFIX}/html;
        allow all;
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
    echo "  0) 退出"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# 主循环
main() {
    while true; do
        show_menu
        read -p "请选择操作 [0-11]: " choice
        
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
            0) print_msg "退出脚本"; exit 0 ;;
            *) print_error "无效选项，请重新选择" ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 运行主程序
main
