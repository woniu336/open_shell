#!/bin/bash
# Nginx ACME 自动化管理脚本（标准路径增强版）

# --- 颜色定义 (兼容 256 色) ---
LOG_BACK='\033[0;40;37m'
BG_MAIN='\033[38;5;240m'  # 灰色边框
PRIMARY='\033[38;5;75m'   # 亮蓝色
SUCCESS='\033[38;5;77m'   # 柔和绿
WARNING='\033[38;5;214m'  # 橙色
DANGER='\033[38;5;196m'   # 红色
INFO='\033[38;5;44m'      # 青色
TITLE='\033[1;37m'        # 粗体白
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m'

# 标准路径定义
NGINX_PREFIX="/usr/local/nginx"
BUILD_DIR="/usr/local/src/nginx-build"
NGINX_VERSION="1.28.0"

# 标准系统路径
NGINX_CONF_DIR="/etc/nginx"
NGINX_CONF_D_DIR="/etc/nginx/conf.d"
NGINX_SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
NGINX_SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
NGINX_STREAMS_AVAILABLE_DIR="/etc/nginx/streams-available"
NGINX_STREAMS_ENABLED_DIR="/etc/nginx/streams-enabled"
NGINX_MODULES_DIR="/usr/lib/nginx/modules"
NGINX_LOG_DIR="/var/log/nginx"
NGINX_CACHE_DIR="/var/cache/nginx"
NGINX_PID_DIR="/run"
NGINX_LOCK_DIR="/var/lock"
NGINX_USER="www-data"
NGINX_GROUP="www-data"
NGINX_SBIN_PATH="/usr/sbin/nginx"

# 打印消息函数
print_msg() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[DONE]${NC} $1"; }
print_error() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_title() { echo -e "${WHITE}$1${NC}"; }

# 权限检查
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户或 sudo 运行此脚本"
        exit 1
    fi
}

# 1. 系统依赖安装
install_dependencies() {
    print_msg "正在更新系统并安装编译环境..."
    apt update && apt install -y build-essential libpcre3-dev zlib1g-dev libssl-dev \
        pkg-config libclang-dev git wget curl tree tar jq cmake
    [ $? -eq 0 ] || { print_error "依赖安装失败"; exit 1; }
    print_success "系统依赖安装完成"
}

# 2. Rust 安装
install_rust() {
    if command -v rustc &> /dev/null; then
        print_warning "Rust 已存在，跳过安装"
        return 0
    fi
    print_msg "正在安装 Rust 工具链..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    if command -v rustc &> /dev/null; then
        print_success "Rust 工具链安装完成"
    else
        print_error "Rust 工具链安装失败"
        exit 1
    fi
}

# 3. 目录结构初始化
create_directories() {
    print_msg "初始化目录结构..."
    
    # 配置目录
    mkdir -pv ${NGINX_CONF_DIR}/{conf.d,sites-available,sites-enabled,streams-available,streams-enabled,acme}
    
    # 模块目录
    mkdir -pv ${NGINX_MODULES_DIR}
    
    # 日志目录
    mkdir -pv ${NGINX_LOG_DIR}
    
    # 缓存目录
    mkdir -pv ${NGINX_CACHE_DIR}/{proxy,client_body_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}
    
    # 运行时目录
    mkdir -pv ${NGINX_PID_DIR} ${NGINX_LOCK_DIR}
    
    # 源码目录
    mkdir -pv ${BUILD_DIR}
    
    # ACME 验证目录
    mkdir -pv /var/www/html/.well-known/acme-challenge
    
    # ACME 证书存储目录
    mkdir -pv ${NGINX_CONF_DIR}/acme/{letsencrypt,staging}
    
    print_success "目录结构初始化完成"
}

# 4. 源码下载
download_sources() {
    print_msg "下载源码..."
    cd ${BUILD_DIR}
    
    # 下载 Nginx ACME 模块
    if [ ! -d "nginx-acme" ]; then
        print_msg "克隆 Nginx ACME 模块..."
        git clone https://github.com/nginx/nginx-acme.git
        [ $? -eq 0 ] || { print_error "ACME 模块下载失败"; exit 1; }
    else
        print_warning "ACME 模块已存在，跳过下载"
    fi
    
    # 下载 Nginx Brotli 模块
    if [ ! -d "ngx_brotli" ]; then
        print_msg "克隆 Nginx Brotli 模块..."
        git clone https://github.com/google/ngx_brotli.git
        [ $? -eq 0 ] || { print_error "Brotli 模块下载失败"; exit 1; }
        cd ngx_brotli
        git submodule update --init
        cd ${BUILD_DIR}
        print_success "Brotli 模块下载并初始化完成"
    else
        print_warning "Brotli 模块已存在，跳过下载"
    fi
    
    # 下载 Nginx 源码
    if [ ! -f "nginx-${NGINX_VERSION}.tar.gz" ]; then
        print_msg "下载 Nginx v${NGINX_VERSION}..."
        wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
        [ $? -eq 0 ] || { print_error "Nginx 源码下载失败"; exit 1; }
    else
        print_warning "Nginx 源码已存在，跳过下载"
    fi
    
    # 解压源码
    if [ ! -d "nginx-${NGINX_VERSION}" ]; then
        tar -zxf nginx-${NGINX_VERSION}.tar.gz
    fi
    
    print_success "源码下载完成"
}

# 5. 编译 Brotli 库
compile_brotli_libs() {
    print_msg "编译 Brotli 库..."
    cd ${BUILD_DIR}/ngx_brotli/deps/brotli
    
    # 清理之前的构建
    rm -rf out
    
    # 创建构建目录
    mkdir -p out && cd out
    
    # 配置和编译
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
    [ $? -eq 0 ] || { print_error "Brotli CMake 配置失败"; exit 1; }
    
    make -j$(nproc)
    [ $? -eq 0 ] || { print_error "Brotli 库编译失败"; exit 1; }
    
    # 安装库文件到系统路径
    make install
    [ $? -eq 0 ] || { print_error "Brotli 库安装失败"; exit 1; }
    
    # 确保库文件在标准库路径中
    ldconfig
    
    print_success "Brotli 库编译安装完成"
}

# 6. 编译与安装 Nginx
compile_nginx() {
    print_msg "开始编译 Nginx (大约需要 5 分钟)..."
    cd ${BUILD_DIR}/nginx-${NGINX_VERSION}
    
    # 设置 Brotli 库路径
    BROTLI_LIB_PATH="${BUILD_DIR}/ngx_brotli/deps/brotli/out"
    
    ./configure \
        --prefix=${NGINX_PREFIX} \
        --conf-path=${NGINX_CONF_DIR}/nginx.conf \
        --sbin-path=${NGINX_SBIN_PATH} \
        --modules-path=${NGINX_MODULES_DIR} \
        --error-log-path=${NGINX_LOG_DIR}/error.log \
        --http-log-path=${NGINX_LOG_DIR}/access.log \
        --pid-path=${NGINX_PID_DIR}/nginx.pid \
        --lock-path=${NGINX_LOCK_DIR}/nginx.lock \
        --http-client-body-temp-path=${NGINX_CACHE_DIR}/client_body_temp \
        --http-proxy-temp-path=${NGINX_CACHE_DIR}/proxy_temp \
        --http-fastcgi-temp-path=${NGINX_CACHE_DIR}/fastcgi_temp \
        --http-uwsgi-temp-path=${NGINX_CACHE_DIR}/uwsgi_temp \
        --http-scgi-temp-path=${NGINX_CACHE_DIR}/scgi_temp \
        --user=${NGINX_USER} \
        --group=${NGINX_GROUP} \
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
        --add-dynamic-module=${BUILD_DIR}/nginx-acme \
        --add-module=${BUILD_DIR}/ngx_brotli
    
    [ $? -eq 0 ] || { print_error "配置失败"; exit 1; }
    
    make -j$(nproc) && make install
    [ $? -eq 0 ] && print_success "Nginx 编译安装成功" || { print_error "编译失败"; exit 1; }
}

# 6. 配置环境
configure_system() {
    # 创建用户
    if ! id "${NGINX_USER}" &>/dev/null; then
        print_msg "创建 ${NGINX_USER} 用户..."
        useradd -r -s /sbin/nologin ${NGINX_USER}
    fi
    
    # 设置权限
    print_msg "设置目录权限..."
    chown -R ${NGINX_USER}:${NGINX_GROUP} ${NGINX_LOG_DIR} ${NGINX_CACHE_DIR}
    chown -R root:${NGINX_GROUP} ${NGINX_CONF_DIR}
    chmod 755 ${NGINX_CONF_DIR}
    chmod 644 ${NGINX_CONF_DIR}/*.conf 2>/dev/null || true
    chmod 755 ${NGINX_SITES_AVAILABLE_DIR} ${NGINX_SITES_ENABLED_DIR}
    chmod 755 ${NGINX_STREAMS_AVAILABLE_DIR} ${NGINX_STREAMS_ENABLED_DIR}
    chown -R ${NGINX_USER}:${NGINX_GROUP} ${NGINX_CONF_DIR}/acme
    chown -R ${NGINX_USER}:${NGINX_GROUP} /var/www/html/.well-known
    
    # 下载默认配置
    print_msg "下载默认配置文件..."
    wget -O ${NGINX_CONF_DIR}/nginx.conf https://raw.githubusercontent.com/woniu336/open_shell/main/acme/nginx.conf
    [ $? -eq 0 ] && print_success "配置文件下载完成" || print_warning "配置文件下载失败，将使用默认配置"
    
    # 复制 mime.types
    cp ${BUILD_DIR}/nginx-${NGINX_VERSION}/conf/mime.types ${NGINX_CONF_DIR}/
    
    # 创建 Service
    cat > /etc/systemd/system/nginx.service << EOF
[Unit]
Description=Nginx HTTP Server
After=network.target

[Service]
Type=forking
PIDFile=${NGINX_PID_DIR}/nginx.pid
ExecStartPre=${NGINX_SBIN_PATH} -t -c ${NGINX_CONF_DIR}/nginx.conf
ExecStart=${NGINX_SBIN_PATH} -c ${NGINX_CONF_DIR}/nginx.conf
ExecReload=${NGINX_SBIN_PATH} -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true
Restart=on-failure
RestartSec=5s
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable nginx
    
    print_success "系统配置完成"
}

# ---------------- 核心管理功能 ----------------

# 备份功能 (压缩包格式)
backup_config() {
    local BKP_DIR="/root/nginx_backups"
    mkdir -p "$BKP_DIR"
    local BKP_NAME="nginx_conf_$(date +%Y%m%d_%H%M%S).tar.gz"
    local BKP_PATH="$BKP_DIR/$BKP_NAME"
    
    print_msg "正在创建压缩备份..."
    
    # 创建备份信息文件
    cat > /tmp/backup_info.txt << EOF
备份时间: $(date)
Nginx 版本: ${NGINX_VERSION}
配置路径: ${NGINX_CONF_DIR}
系统信息: $(uname -a)
备份脚本版本: 2.0
EOF
    
    # 创建压缩备份
    tar -czf "$BKP_PATH" \
        -C / \
        etc/nginx \
        var/www/html \
        /tmp/backup_info.txt \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "备份已保存至: $BKP_PATH"
        echo -e "${CYAN}备份详情:${NC}"
        ls -lh "$BKP_PATH"
        echo -e "${CYAN}备份包含:${NC}"
        tar -tzf "$BKP_PATH" | head -20
        [ $(tar -tzf "$BKP_PATH" | wc -l) -gt 20 ] && echo "... (更多文件)"
        
        # 清理旧的备份（保留最近10个）
        cd "$BKP_DIR"
        ls -t *.tar.gz 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
    else
        print_error "备份失败"
    fi
    
    rm -f /tmp/backup_info.txt
}

# 恢复功能 (支持压缩包)
restore_config() {
    local BKP_DIR="/root/nginx_backups"
    mkdir -p "$BKP_DIR" 2>/dev/null
    
    print_msg "查找可用的备份文件 (.tar.gz):"
    local backups=($(ls -t "$BKP_DIR"/*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_error "未发现备份文件"
        echo -e "${YELLOW}备份目录: $BKP_DIR${NC}"
        return 1
    fi

    echo -e "${CYAN}可用备份:${NC}"
    for i in "${!backups[@]}"; do
        local size=$(ls -lh "${backups[$i]}" | awk '{print $5}')
        local mtime=$(stat -c "%y" "${backups[$i]}" | cut -d'.' -f1)
        echo -e "  ${GREEN}$i)${NC} ${backups[$i]##*/} (${size}, ${mtime})"
    done
    
    read -p "选择恢复编号: " bkp_idx
    
    if ! [[ "$bkp_idx" =~ ^[0-9]+$ ]] || [ "$bkp_idx" -ge ${#backups[@]} ]; then
        print_error "选择无效"
        return 1
    fi
    
    local target_bkp="${backups[$bkp_idx]}"
    
    if [ -f "$target_bkp" ]; then
        print_warning "恢复将覆盖当前配置！是否继续? (y/n)"
        read confirm
        [[ "$confirm" != "y" ]] && { print_warning "已取消恢复"; return; }
        
        # 停止 Nginx
        print_msg "停止 Nginx 服务..."
        systemctl stop nginx 2>/dev/null || pkill -9 nginx 2>/dev/null
        sleep 2
        
        # 创建当前配置备份
        local CURRENT_BKP="/tmp/nginx_pre_restore_$(date +%s).tar.gz"
        tar -czf "$CURRENT_BKP" -C / etc/nginx var/www/html 2>/dev/null
        print_warning "当前配置已备份到: $CURRENT_BKP"
        
        # 恢复配置
        print_msg "正在恢复配置..."
        tar -xzf "$target_bkp" -C /
        
        if [ $? -eq 0 ]; then
            print_success "配置恢复完成"
            
            # 静默启动 Nginx
            print_msg "正在启动 Nginx..."
            systemctl start nginx &>/dev/null
            sleep 2
            
            if systemctl is-active nginx >/dev/null 2>&1; then
                print_success "Nginx 启动成功"
            else
                print_warning "Nginx 启动失败，请检查配置"
                systemctl status nginx --no-pager
            fi
        else
            print_error "恢复失败"
            # 恢复之前的配置
            print_msg "尝试恢复之前的配置..."
            tar -xzf "$CURRENT_BKP" -C /
        fi
        
        rm -f "$CURRENT_BKP"
    else
        print_error "备份文件不存在"
    fi
}

# 站点管理
manage_sites() {
    echo -e "\n${BLUE}--- 站点状态管理 ---${NC}"
    echo " 1) 启用站点 (Link)"
    echo " 2) 禁用站点 (Unlink)"
    read -p "选择操作: " op
    
    case $op in
        1)
            echo -e "${CYAN}可用站点配置:${NC}"
            ls -1 ${NGINX_SITES_AVAILABLE_DIR} 2>/dev/null || echo "  暂无配置"
            read -p "输入要启用的域名: " dom
            if [ -f "${NGINX_SITES_AVAILABLE_DIR}/$dom" ]; then
                ln -sf ${NGINX_SITES_AVAILABLE_DIR}/$dom ${NGINX_SITES_ENABLED_DIR}/
                print_success "站点已启用: $dom"
            else
                print_error "配置文件不存在: $dom"
            fi
            ;;
        2)
            echo -e "${CYAN}已启用的站点:${NC}"
            ls -1 ${NGINX_SITES_ENABLED_DIR} 2>/dev/null || echo "  暂无启用站点"
            read -p "输入要禁用的域名: " dom
            if [ -L "${NGINX_SITES_ENABLED_DIR}/$dom" ]; then
                rm -f ${NGINX_SITES_ENABLED_DIR}/$dom
                print_success "站点已禁用: $dom"
            else
                print_error "站点未启用: $dom"
            fi
            ;;
        *)
            print_error "无效操作"
            return 1
            ;;
    esac
    
    # 测试并重载配置
    nginx -t && systemctl reload nginx
}

# 端口转发管理（新功能）
manage_streams() {
    echo -e "\n${BLUE}--- 端口转发管理 ---${NC}"
    echo " 1) 启用转发规则"
    echo " 2) 禁用转发规则"
    read -p "选择操作: " op
    
    case $op in
        1)
            echo -e "${CYAN}可用转发配置:${NC}"
            ls -1 ${NGINX_STREAMS_AVAILABLE_DIR} 2>/dev/null || echo "  暂无配置"
            read -p "输入要启用的配置名: " cfg
            if [ -f "${NGINX_STREAMS_AVAILABLE_DIR}/$cfg" ]; then
                ln -sf ${NGINX_STREAMS_AVAILABLE_DIR}/$cfg ${NGINX_STREAMS_ENABLED_DIR}/
                print_success "转发规则已启用: $cfg"
            else
                print_error "配置文件不存在: $cfg"
            fi
            ;;
        2)
            echo -e "${CYAN}已启用的转发规则:${NC}"
            ls -1 ${NGINX_STREAMS_ENABLED_DIR} 2>/dev/null || echo "  暂无启用规则"
            read -p "输入要禁用的配置名: " cfg
            if [ -L "${NGINX_STREAMS_ENABLED_DIR}/$cfg" ]; then
                rm -f ${NGINX_STREAMS_ENABLED_DIR}/$cfg
                print_success "转发规则已禁用: $cfg"
            else
                print_error "转发规则未启用: $cfg"
            fi
            ;;
        *)
            print_error "无效操作"
            return 1
            ;;
    esac
    
    nginx -t && systemctl reload nginx
}

# 列出所有配置
list_all_configs() {
    echo -e "\n${BLUE}=== 配置概览 ===${NC}"
    
    echo -e "${CYAN}站点配置:${NC}"
    if [ -d "${NGINX_SITES_AVAILABLE_DIR}" ] && [ -n "$(ls -A ${NGINX_SITES_AVAILABLE_DIR} 2>/dev/null)" ]; then
        for site in $(ls -1 ${NGINX_SITES_AVAILABLE_DIR}); do
            if [ -L "${NGINX_SITES_ENABLED_DIR}/$site" ]; then
                echo -e "  ${GREEN}✓${NC} $site"
            else
                echo -e "  ${YELLOW}○${NC} $site"
            fi
        done
    else
        echo "  暂无站点配置"
    fi
    
    echo -e "\n${CYAN}端口转发配置:${NC}"
    if [ -d "${NGINX_STREAMS_AVAILABLE_DIR}" ] && [ -n "$(ls -A ${NGINX_STREAMS_AVAILABLE_DIR} 2>/dev/null)" ]; then
        for stream in $(ls -1 ${NGINX_STREAMS_AVAILABLE_DIR}); do
            if [ -L "${NGINX_STREAMS_ENABLED_DIR}/$stream" ]; then
                echo -e "  ${GREEN}✓${NC} $stream"
            else
                echo -e "  ${YELLOW}○${NC} $stream"
            fi
        done
    else
        echo "  暂无转发配置"
    fi
    
    echo -e "\n${CYAN}证书状态:${NC}"
    if [ -d "${NGINX_CONF_DIR}/acme/letsencrypt" ]; then
        echo "  ACME 证书目录存在"
        find ${NGINX_CONF_DIR}/acme/letsencrypt -name "*.pem" | head -5 | while read cert; do
            echo "  - $(basename $cert)"
        done
    else
        echo "  暂无证书"
    fi
    
    echo -e "\n${CYAN}服务状态:${NC}"
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo -e "  ${GREEN}●${NC} Nginx 运行中"
    else
        echo -e "  ${RED}●${NC} Nginx 未运行"
    fi
}

# 查看证书状态
view_cert_status() {
    echo -e "\n${BLUE}=== 证书状态 ===${NC}"
    
    if [ -d "${NGINX_CONF_DIR}/acme" ]; then
        echo -e "${CYAN}证书目录结构:${NC}"
        tree ${NGINX_CONF_DIR}/acme -L 2
        
        echo -e "\n${CYAN}证书详情:${NC}"
        find ${NGINX_CONF_DIR}/acme -name "*.pem" -exec echo "  - {}" \;
    else
        print_warning "ACME 证书目录不存在"
    fi
    
    echo -e "\n${CYAN}Nginx 模块:${NC}"
    ls -la ${NGINX_MODULES_DIR}/
}

# 测试并重载配置
test_and_reload() {
    print_msg "测试 Nginx 配置..."
    if nginx -t; then
        print_success "配置测试通过"
        print_msg "重载 Nginx 配置..."
        systemctl reload nginx && print_success "配置重载成功"
    else
        print_error "配置测试失败，请检查错误信息"
    fi
}

# 停止 Nginx
stop_nginx() {
    print_msg "停止 Nginx..."
    
    # 检查是否有 systemd 服务
    if systemctl is-active nginx >/dev/null 2>&1; then
        systemctl stop nginx
    else
        ${NGINX_SBIN_PATH} -s stop
    fi
    
    if [ $? -eq 0 ]; then
        print_msg "Nginx 已停止"
    else
        print_error "Nginx 停止失败"
    fi
}


# 卸载 Nginx
uninstall_nginx() {
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}          警告：卸载操作              ${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "此操作将删除："
    echo " - Nginx 程序文件"
    echo " - 配置文件目录: ${NGINX_CONF_DIR}"
    echo " - 日志目录: ${NGINX_LOG_DIR}"
    echo " - 缓存目录: ${NGINX_CACHE_DIR}"
    echo " - 源码编译目录: ${BUILD_DIR}"
    echo ""
    echo -e "${YELLOW}注意：此操作不可恢复！${NC}"
    echo -e "${YELLOW}建议在卸载前先执行备份操作${NC}"
    echo ""
    
    read -p "确认卸载？输入 YES 继续，其他键取消: " CONFIRM
    
    if [ "$CONFIRM" != "YES" ]; then
        print_warning "已取消卸载操作"
        return
    fi
    
    # 停止 Nginx
    stop_nginx
    sleep 2
    
    # 删除安装目录
    if [ -d "${NGINX_PREFIX}" ]; then
        rm -rf ${NGINX_PREFIX}
        print_msg "Nginx 安装目录已删除"
    fi
    
    # 删除配置文件（保留备份）
    print_msg "清理配置文件..."
    rm -rf ${NGINX_CONF_DIR} ${NGINX_LOG_DIR} ${NGINX_CACHE_DIR}
    
    # 删除源码编译目录
    if [ -d "${BUILD_DIR}" ]; then
        rm -rf ${BUILD_DIR}
        print_msg "源码编译目录已删除"
    fi
    
    # 删除 systemd 服务
    systemctl disable nginx 2>/dev/null
    rm -f /etc/systemd/system/nginx.service
    systemctl daemon-reload
    
    print_success "卸载完成！"
    echo -e "${YELLOW}提示：备份文件仍保留在 /root/nginx_backups/${NC}"
}

# ---------------- 业务接入功能 ----------------

# 添加反向代理站点
add_proxy_site() {
    print_title "=== 添加反向代理站点 ==="
    
    read -p "请输入域名 (如 api.example.com): " DOMAIN
    read -p "后端IP (默认 127.0.0.1): " B_IP
    B_IP=${B_IP:-127.0.0.1}
    read -p "后端端口: " B_PORT
    
    cat > ${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN} << EOF
# ===== WebSocket 智能判断 =====
map \$http_upgrade \$connection_upgrade {
    default      "";       
    websocket    "upgrade"; 
}

# ===== HTTP → HTTPS =====
server {
    listen 80;
    listen [::]:80;
    
    server_name ${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# ===== HTTPS 443 =====
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    
    server_name ${DOMAIN};
    
    access_log /var/log/nginx/${DOMAIN}-access.log main buffer=64k flush=10s;
    error_log /var/log/nginx/${DOMAIN}-error.log warn;
    
    acme_certificate letsencrypt;
    ssl_certificate \$acme_certificate;
    ssl_certificate_key \$acme_certificate_key;
    ssl_certificate_cache max=2;
    
    gzip on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
              application/json application/javascript application/xml 
              application/rss+xml image/svg+xml;
    
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css text/xml text/javascript 
                 application/json application/javascript application/xml 
                 application/rss+xml image/svg+xml;
    
    # ===== 静态资源 =====
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|bmp|swf|eot|svg|ttf|woff|woff2|webp)\$ {
        proxy_pass http://${B_IP}:${B_PORT};
        
        # HTTP/1.1 持久连接
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # 获取原始文件（禁用后端压缩）
        proxy_set_header Accept-Encoding "";
        #proxy_hide_header Vary;
        
        # 代理头
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # 缓存配置
        proxy_cache my_proxy_cache;
        proxy_cache_key "$scheme$host$request_uri$is_args$args";
        proxy_cache_valid 200 302 304 30d;
        proxy_cache_valid 404 1m;
        proxy_cache_valid any 10s;
        proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;

        # 忽略后端缓存头
        #proxy_ignore_headers Cache-Control Expires;      
        
        # 性能优化
        expires 30d;
        etag on;
        sendfile on;
        tcp_nopush on;
        log_not_found off;
        access_log off;
    }
    
    # ===== 动态内容 =====
    location / {
        proxy_pass http://${B_IP}:${B_PORT};
        
        # WebSocket支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        
        # 代理头
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
    }
}
EOF
    
    # 创建目录并设置权限
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R ${NGINX_USER}:${NGINX_GROUP} /var/www/html/.well-known
    
    # 启用站点
    ln -sf ${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN} ${NGINX_SITES_ENABLED_DIR}/
    
    print_success "反向代理站点已创建: ${DOMAIN}"
    print_msg "目标: http://${B_IP}:${B_PORT}"
    echo -e "${YELLOW}提示: 请确保域名 ${DOMAIN} 已解析到本机IP${NC}"
}

# 添加负载均衡站点
add_load_balancing_site() {
    print_title "=== 添加负载均衡站点 ==="
    
    read -p "请输入域名 (如 api.example.com): " DOMAIN
    
    echo "请输入后端服务器列表 (格式: IP:PORT，多个用空格隔开):"
    echo "例如: 192.168.1.100:8080 192.168.1.101:8080"
    read -a BACKENDS
    
    if [ ${#BACKENDS[@]} -eq 0 ]; then
        print_error "至少需要一个后端服务器"
        return 1
    fi
    
    # 生成upstream名称
    UPSTREAM_NAME=$(echo $DOMAIN | sed 's/\./_/g')
    
    # 构建server列表
    SERVER_LIST=""
    for backend in "${BACKENDS[@]}"; do
        SERVER_LIST="${SERVER_LIST}    server ${backend};\n"
    done
    
    cat > ${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN} << EOF
# ===== WebSocket 智能判断 =====
map \$http_upgrade \$connection_upgrade {
    default      "";       
    websocket    "upgrade"; 
}


upstream ${UPSTREAM_NAME} {
    keepalive          320;
    keepalive_requests 500;
    keepalive_timeout  60s;

$(echo -e "${SERVER_LIST}")
}

# ===== HTTP → HTTPS =====
server {
    listen 80;
    listen [::]:80;
    
    server_name ${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# ===== HTTPS 443 =====
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    
    server_name ${DOMAIN};
    
    access_log /var/log/nginx/${DOMAIN}-access.log main buffer=64k flush=10s;
    error_log /var/log/nginx/${DOMAIN}-error.log warn;
    
    acme_certificate letsencrypt;
    ssl_certificate \$acme_certificate;
    ssl_certificate_key \$acme_certificate_key;
    ssl_certificate_cache max=2;
    
    gzip on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
              application/json application/javascript application/xml 
              application/rss+xml image/svg+xml;
    
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css text/xml text/javascript 
                 application/json application/javascript application/xml 
                 application/rss+xml image/svg+xml;
    
    # ===== 静态资源 =====
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|bmp|swf|eot|svg|ttf|woff|woff2|webp)\$ {
        proxy_pass http://${UPSTREAM_NAME};

        # HTTP/1.1 持久连接
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        # 超时控制
        proxy_connect_timeout 1s;
        proxy_send_timeout 2s;
        proxy_read_timeout 3s;
        
        # 故障转移配置
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_timeout 5s;
        proxy_next_upstream_tries 2;
        
        
        # 获取原始文件（禁用后端压缩）
        proxy_set_header Accept-Encoding "";
        #proxy_hide_header Vary;
        
        # 代理头
        proxy_set_header Host               \$host;
        proxy_set_header X-Real-IP          \$remote_addr;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto  \$scheme;
        proxy_set_header X-Forwarded-Port   \$server_port;
        
        # 缓存配置
        proxy_cache my_proxy_cache;
        proxy_cache_key "$scheme$host$request_uri$is_args$args";
        proxy_cache_valid 200 302 304 30d;
        proxy_cache_valid 404 1m;
        proxy_cache_valid any 10s;
        proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
        
        # 忽略后端缓存头
        #proxy_ignore_headers Cache-Control Expires;
        
        # 性能优化
        expires 30d;
        etag on;
        sendfile on;
        tcp_nopush on;
        log_not_found off;
        access_log off;
    }
    
    # ===== 动态内容 =====
    location / {
        proxy_pass http://${UPSTREAM_NAME};

        # 超时控制（比静态稍长）
        proxy_connect_timeout 2s;
        proxy_send_timeout 5s;
        proxy_read_timeout 8s;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
        
        # WebSocket支持
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        
        # 代理头
        proxy_set_header Host               \$host;
        proxy_set_header X-Real-IP          \$remote_addr;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto  \$scheme;
        proxy_set_header X-Forwarded-Port   \$server_port;
    }
}
EOF
    
    # 创建目录并设置权限
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R ${NGINX_USER}:${NGINX_GROUP} /var/www/html/.well-known
    
    # 启用站点
    ln -sf ${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN} ${NGINX_SITES_ENABLED_DIR}/
    
    print_success "负载均衡站点已创建: ${DOMAIN}"
    print_msg "后端服务器:"
    for backend in "${BACKENDS[@]}"; do
        echo "  - $backend"
    done
}

# 添加静态站点
add_static_site() {
    print_title "=== 添加静态站点 ==="
    
    read -p "请输入域名 (如 www.example.com): " DOMAIN
    
    # 创建网站根目录
    SITE_ROOT="/var/www/html/${DOMAIN}"
    mkdir -p ${SITE_ROOT}
    
    cat > ${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN} << EOF
# ===== HTTP → HTTPS =====
server {
    listen 80;
    listen [::]:80;
    
    server_name ${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# ===== HTTPS 443 =====
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    
    server_name ${DOMAIN};
    
    access_log /var/log/nginx/${DOMAIN}-access.log main buffer=64k flush=10s;
    error_log /var/log/nginx/${DOMAIN}-error.log warn;
    
    acme_certificate letsencrypt;
    ssl_certificate \$acme_certificate;
    ssl_certificate_key \$acme_certificate_key;
    ssl_certificate_cache max=2;
    
    # 站点配置
    root ${SITE_ROOT};
    index index.html index.htm;
    
    access_log /var/log/nginx/${DOMAIN}.log;
    error_log /var/log/nginx/${DOMAIN}.error.log;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)\$ {
        expires 30d;
    }
    
    location ~* \.(woff|woff2|ttf|eot|svg)\$ {
        expires 1y;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    
    location = /robots.txt {
        log_not_found off;
        access_log off;
    }
}
EOF
    
    # 创建目录并设置权限
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R ${NGINX_USER}:${NGINX_GROUP} /var/www/html/.well-known
    chown -R ${NGINX_USER}:${NGINX_GROUP} ${SITE_ROOT}
    chmod 755 ${SITE_ROOT}
    
    # 启用站点
    ln -sf ${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN} ${NGINX_SITES_ENABLED_DIR}/
    
    print_success "静态站点已创建: ${DOMAIN}"
    print_msg "网站根目录: ${SITE_ROOT}"
    print_msg "请将您的网站文件上传至此目录"
}

# 添加重定向站点
add_redirect_site() {
    print_title "=== 添加重定向站点 ==="
    
    read -p "请输入源域名 (如 old.example.com): " SOURCE_DOMAIN
    read -p "请输入目标域名 (如 new.example.com): " TARGET_DOMAIN
    
    cat > ${NGINX_SITES_AVAILABLE_DIR}/${SOURCE_DOMAIN} << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name ${SOURCE_DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://${TARGET_DOMAIN}\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    
    server_name ${SOURCE_DOMAIN};

    acme_certificate letsencrypt;
    ssl_certificate \$acme_certificate;
    ssl_certificate_key \$acme_certificate_key;
    ssl_certificate_cache max=2;

    location / {
        return 301 https://${TARGET_DOMAIN}\$request_uri;
    }
}
EOF
    
    # 创建目录并设置权限
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R ${NGINX_USER}:${NGINX_GROUP} /var/www/html/.well-known
    
    # 启用站点
    ln -sf ${NGINX_SITES_AVAILABLE_DIR}/${SOURCE_DOMAIN} ${NGINX_SITES_ENABLED_DIR}/
    
    print_success "重定向站点已创建: ${SOURCE_DOMAIN}"
    print_msg "重定向到: https://${TARGET_DOMAIN}"
}

# 添加四层端口转发
add_port_forward() {
    print_title "=== 添加四层端口转发 ==="
    
    read -p "请输入配置名称 (如 mysql-proxy): " CONFIG_NAME
    read -p "请输入监听端口: " LISTEN_PORT
    read -p "请输入目标地址 (IP:PORT): " TARGET
    
    # 验证端口格式
    if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]]; then
        print_error "端口号必须是数字"
        return 1
    fi
    
    cat > ${NGINX_STREAMS_AVAILABLE_DIR}/${CONFIG_NAME} << EOF
upstream ${CONFIG_NAME}_backend {
    server ${TARGET};
}

server {
    listen ${LISTEN_PORT};
    proxy_pass ${CONFIG_NAME}_backend;
    proxy_timeout 60s;
    proxy_connect_timeout 10s;
}
EOF

    
    # 启用配置
    ln -sf ${NGINX_STREAMS_AVAILABLE_DIR}/${CONFIG_NAME} ${NGINX_STREAMS_ENABLED_DIR}/
    
    print_success "端口转发已创建: ${CONFIG_NAME}"
    print_msg "监听端口: ${LISTEN_PORT}"
    print_msg "转发到: ${TARGET}"
    print_warning "请确保防火墙已开放端口 ${LISTEN_PORT}"
}

# 删除站点配置
delete_site_config() {
    echo -e "\n${BLUE}=== 站点列表 ===${NC}"
    
    if [ ! -d "${NGINX_SITES_AVAILABLE_DIR}" ] || [ -z "$(ls -A ${NGINX_SITES_AVAILABLE_DIR} 2>/dev/null)" ]; then
        print_warning "暂无站点配置"
        return
    fi
    
    # 显示所有站点
    for config in $(ls -1 ${NGINX_SITES_AVAILABLE_DIR}); do
        if [ -L "${NGINX_SITES_ENABLED_DIR}/${config}" ]; then
            echo -e "  ${GREEN}✓${NC} ${config}"
        else
            echo -e "  ${YELLOW}○${NC} ${config}"
        fi
    done
    
    echo ""
    read -p "请输入要删除的域名配置: " DOMAIN
    
    # 确认删除
    read -p "确认删除 ${DOMAIN}？此操作不可恢复 (y/n): " CONFIRM
    [[ "$CONFIRM" != "y" ]] && { print_warning "已取消删除"; return; }
    
    # 禁用站点
    if [ -L "${NGINX_SITES_ENABLED_DIR}/${DOMAIN}" ]; then
        rm -f ${NGINX_SITES_ENABLED_DIR}/${DOMAIN}
        print_msg "已禁用站点: ${DOMAIN}"
    fi
    
    # 删除配置文件
    if [ -f "${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN}" ]; then
        rm -f ${NGINX_SITES_AVAILABLE_DIR}/${DOMAIN}
        print_success "站点配置已删除: ${DOMAIN}"
    else
        print_error "配置文件不存在: ${DOMAIN}"
    fi
}

# ---------------- 完整安装 ----------------
full_install() {
    print_title "开始 Nginx ACME 完整安装"
    check_root
    install_dependencies
    install_rust
    create_directories
    download_sources
    compile_brotli_libs
    compile_nginx
    configure_system
    
    print_title "安装完成"
    print_success "所有流程已完成"
    print_msg "正在启动 Nginx..."
    systemctl start nginx
    
    if systemctl is-active nginx >/dev/null 2>&1; then
        print_success "Nginx 启动成功"
        echo ""
        systemctl status nginx --no-pager
    else
        print_error "Nginx 启动失败"
        journalctl -u nginx -n 20 --no-pager
    fi
    
    echo -e "\n${GREEN}安装总结:${NC}"
    echo "  - Nginx 版本: ${NGINX_VERSION}"
    echo "  - 配置目录: ${NGINX_CONF_DIR}"
    echo "  - 日志目录: ${NGINX_LOG_DIR}"
    echo "  - ACME 模块: 已启用"
    echo "  - Brotli 模块: 已启用"
    echo "  - 证书目录: ${NGINX_CONF_DIR}/acme"
    echo -e "\n${YELLOW}下一步:${NC}"
    echo "  使用菜单选项 2-6 添加您的第一个站点"
}

show_menu() {
    clear
    echo -e "${PRIMARY}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${PRIMARY}│${NC}          ${TITLE}Nginx ACME 自动化管理工具 (v2.1)${NC}          ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}├────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PRIMARY}│${NC}  ${INFO}[ 基础部署 ]${NC}                                        ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    1. 完整初始化安装 (首次使用)                      ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}├────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PRIMARY}│${NC}  ${INFO}[ 业务接入 ]${NC}                                        ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    2. 反向代理            3. 负载均衡                ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    4. 静态站点            5. 重定向                  ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    6. 四层端口转发                                   ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}├────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PRIMARY}│${NC}  ${INFO}[ 站点管理 ]${NC}                                        ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    7. 站点启用/禁用       8. 端口转发管理            ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    9. 查看所有配置        10. 删除站点配置           ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}├────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PRIMARY}│${NC}  ${INFO}[ 运维工具 ]${NC}                                        ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    11. 测试并重载配置     12. 查看证书               ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    13. ${SUCCESS}备份配置(GZ)${NC}       14. ${WARNING}还原配置(GZ)${NC}           ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}│${NC}    15. ${DANGER}卸载 Nginx${NC}         0.  退出脚本               ${PRIMARY}│${NC}"
    echo -e "${PRIMARY}└────────────────────────────────────────────────────────┘${NC}"
    echo -en "${PRIMARY} 请输入指令 [0-15]: ${NC}"
}

# 主循环
main() {
    while true; do
        show_menu
        read -p " 请选择操作 [0-15]: " choice
        
        case $choice in
            1) full_install ;;
            2) add_proxy_site && test_and_reload ;;
            3) add_load_balancing_site && test_and_reload ;;
            4) add_static_site && test_and_reload ;;
            5) add_redirect_site && test_and_reload ;;
            6) add_port_forward && test_and_reload ;;
            7) manage_sites ;;
            8) manage_streams ;;
            9) list_all_configs ;;
            10) delete_site_config && test_and_reload ;;
            11) test_and_reload ;;
            12) view_cert_status ;;
            13) backup_config ;;
            14) restore_config ;;
            15) uninstall_nginx ;;
            0) 
                print_msg "感谢使用，再见！"
                exit 0
                ;;
            *) print_error "无效输入，请重新选择" ;;
        esac
        
        if [ "$choice" != "0" ]; then
            echo -e "\n${CYAN}按回车键返回菜单...${NC}"
            read
        fi
    done
}

# 脚本入口
main
