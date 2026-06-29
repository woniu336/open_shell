#!/bin/bash
set -e

NGINX_NEW_VER="1.30.3"
BUILD_DIR="/usr/local/src/nginx-build"
BACKUP_DIR="/root/nginx_backups"
DATE_TAG=$(date +%Y%m%d_%H%M%S)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $1"; }
err()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

[ "$EUID" -ne 0 ] && err "请使用 root 用户运行"
info "当前版本: $(nginx -v 2>&1)"

# === 1. 备份 ===
info "备份配置..."
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/nginx_conf_$DATE_TAG.tar.gz" -C / etc/nginx var/www/html 2>/dev/null
ok "备份: $BACKUP_DIR/nginx_conf_$DATE_TAG.tar.gz"

# === 2. 修改原脚本版本号 ===
sed -i 's/NGINX_VERSION="1.30.2"/NGINX_VERSION="1.30.3"/' /root/nginx-acme.sh
ok "版本号已更新为 1.30.3"

# === 3. 下载源码 ===
cd "$BUILD_DIR"
if [ ! -f "nginx-$NGINX_NEW_VER.tar.gz" ]; then
    info "下载 nginx-$NGINX_NEW_VER..."
    wget "https://nginx.org/download/nginx-$NGINX_NEW_VER.tar.gz"
fi
if [ ! -d "nginx-$NGINX_NEW_VER" ]; then
    tar -zxf "nginx-$NGINX_NEW_VER.tar.gz"
fi
cd "nginx-$NGINX_NEW_VER"

# === 4. 编译安装（与 nginx-acme.sh 相同参数） ===
BROTLI_LIB_PATH="$BUILD_DIR/ngx_brotli/deps/brotli/out"

info "配置编译参数..."
./configure \
    --prefix=/usr/local/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --lock-path=/var/lock/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_body_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=www-data \
    --group=www-data \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_realip_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
    --with-ld-opt="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L${BROTLI_LIB_PATH}" \
    --add-dynamic-module="$BUILD_DIR/nginx-acme" \
    --add-module="$BUILD_DIR/ngx_brotli"

info "编译中 (可能需 3-5 分钟)..."
make -j$(nproc)
make install

# === 5. 验证 ===
echo ""
nginx -v 2>&1 | grep "$NGINX_NEW_VER" && ok "版本正确" || err "版本不匹配"
nginx -t || err "配置测试失败"
nginx -s reload && ok "升级完成！热重载成功"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   NGINX 已升级至 $NGINX_NEW_VER${NC}"
echo -e "${GREEN}   配置文件已备份至 $BACKUP_DIR${NC}"
echo -e "${GREEN}========================================${NC}"
