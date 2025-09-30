#!/bin/bash

CONFIG_FILE="/etc/haproxy/haproxy.cfg"

# 检查是否已安装 HAProxy
is_installed() {
    dpkg -l | grep -qw haproxy
}

# 安装 HAProxy
install_haproxy() {
    if is_installed; then
        echo "✅ 已检测到 HAProxy 已安装，跳过安装步骤。"
    else
        echo "正在安装 HAProxy..."
        apt update && apt install -y haproxy
        systemctl enable haproxy
        systemctl start haproxy
        echo "✅ HAProxy 安装完成"
    fi
}

# 修改后端 IP
modify_backend() {
    read -p "请输入后端主服务器 IP: " MAIN_IP
    read -p "请输入备用服务器 IP（可留空）: " BACKUP_IP

    cat > $CONFIG_FILE <<EOF
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 30000

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend http_redirect
    bind *:80
    mode http
    option httplog
    redirect scheme https code 301

frontend tcp_front_443
    bind *:443
    mode tcp
    option tcplog
    rate-limit sessions 15000
    default_backend servers_443

backend servers_443
    mode tcp
    server web1 ${MAIN_IP}:443 check inter 10s rise 2 fall 3
EOF

    if [[ -n "$BACKUP_IP" ]]; then
        echo "    server web2 ${BACKUP_IP}:443 check inter 10s rise 2 fall 3 backup" >> $CONFIG_FILE
    fi

    haproxy -c -f $CONFIG_FILE && systemctl restart haproxy
    echo "✅ 后端服务器已更新并应用配置"
}

# 是否启用备用服务器为负载均衡
enable_load_balancing() {
    echo "正在将备用服务器改为负载均衡..."
    sed -i 's/backup//' $CONFIG_FILE
    haproxy -c -f $CONFIG_FILE && systemctl restart haproxy
    echo "✅ 已修改为负载均衡模式"
}

# 启用 PROXY 协议（仅提示）
enable_proxy_protocol() {
    echo "正在修改 haproxy.cfg 启用 PROXY 协议..."
    sed -i 's/server web1.*/& send-proxy-v2/' $CONFIG_FILE
    sed -i 's/server web2.*/& send-proxy-v2/' $CONFIG_FILE
    haproxy -c -f $CONFIG_FILE && systemctl restart haproxy
    echo "✅ HAProxy 已启用 PROXY 协议"

    echo ""
    echo "👉 请在 Nginx 配置中手动添加以下内容："
    echo "-----------------------------------"
    echo "listen 443 ssl http2 proxy_protocol;"
    echo "set_real_ip_from 你的HAProxy服务器IP;"
    echo "real_ip_header proxy_protocol;"
    echo "-----------------------------------"
    echo ""
}

# 检查 HAProxy 状态
check_status() {
    systemctl status haproxy --no-pager
}

# 菜单
while true; do
    echo "========= HAProxy 管理菜单 ========="
    echo "1) 安装 HAProxy"
    echo "2) 修改后端服务器"
    echo "3) 启用备用服务器为负载均衡"
    echo "4) 启用 PROXY 协议 (仅提示 Nginx 配置)"
    echo "5) 检查 HAProxy 状态"
    echo "6) 退出"
    echo "==================================="
    read -p "请选择操作 [1-6]: " choice
    case $choice in
        1) install_haproxy ;;
        2) modify_backend ;;
        3) enable_load_balancing ;;
        4) enable_proxy_protocol ;;
        5) check_status ;;
        6) exit 0 ;;
        *) echo "无效选择，请重试" ;;
    esac
done
