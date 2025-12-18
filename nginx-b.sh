#!/bin/bash

set -e

BLACKLIST_TXT="/etc/nginx/blacklist.txt"
BLACKLIST_CONF="/etc/nginx/dynamic/blacklist.conf"
GEN_SCRIPT="/usr/local/bin/gen_nginx_blacklist.sh"
WATCHER_SCRIPT="/usr/local/bin/nginx-blacklist-watcher.sh"
SERVICE_FILE="/etc/systemd/system/nginx-blacklist-watcher.service"

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 请使用 root 运行该脚本"
        exit 1
    fi
}

install_inotify() {
    echo "▶ 安装 inotify-tools..."
    apt update
    apt install -y inotify-tools
}

init_files() {
    echo "▶ 初始化目录和文件..."
    mkdir -p /etc/nginx/dynamic
    [[ -f "$BLACKLIST_TXT" ]] || echo "# 黑名单IP，每行一个，如：1.2.3.4" > "$BLACKLIST_TXT"
    touch "$BLACKLIST_CONF"
}

create_gen_script() {
    echo "▶ 创建 blacklist 生成脚本..."
    cat > "$GEN_SCRIPT" <<'EOF'
#!/bin/bash

INPUT="/etc/nginx/blacklist.txt"
OUTPUT="/etc/nginx/dynamic/blacklist.conf"

echo "# Auto-generated from blacklist.txt. DO NOT EDIT." > "$OUTPUT"

while IFS= read -r line; do
    line=$(echo "$line" | xargs)
    if [[ -n "$line" && "$line" != \#* ]]; then
        echo "deny $line;" >> "$OUTPUT"
    fi
done < "$INPUT"

nginx -t && systemctl reload nginx
EOF

    chmod +x "$GEN_SCRIPT"
}

create_watcher_script() {
    echo "▶ 创建 inotify 监听脚本..."
    cat > "$WATCHER_SCRIPT" <<'EOF'
#!/bin/bash

WATCH_FILE="/etc/nginx/blacklist.txt"

while inotifywait -e close_write,moved_to,attrib "$WATCH_FILE"; do
    echo "[$(date)] blacklist.txt changed, regenerating..."
    /usr/local/bin/gen_nginx_blacklist.sh
done
EOF

    chmod +x "$WATCHER_SCRIPT"
}

create_service() {
    echo "▶ 创建 systemd 服务..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nginx Blacklist File Watcher
After=nginx.service
Requires=nginx.service

[Service]
Type=simple
User=root
ExecStart=$WATCHER_SCRIPT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

start_service() {
    systemctl enable nginx-blacklist-watcher
    systemctl restart nginx-blacklist-watcher
}

edit_blacklist() {
    echo "▶ 编辑 blacklist.txt"
    ${EDITOR:-nano} "$BLACKLIST_TXT"
}

show_blacklist() {
    echo "▶ 当前 blacklist.txt 内容："
    echo "--------------------------------"
    cat "$BLACKLIST_TXT"
    echo "--------------------------------"
}

gen_now() {
    echo "▶ 手动生成并重载 Nginx..."
    "$GEN_SCRIPT"
}

service_status() {
    systemctl status nginx-blacklist-watcher --no-pager
}

service_logs() {
    journalctl -u nginx-blacklist-watcher -n 50 --no-pager
}


uninstall_all() {
    echo "⚠️ 即将卸载 nginx-blacklist-watcher"
    read -rp "确认卸载？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return

    systemctl stop nginx-blacklist-watcher || true
    systemctl disable nginx-blacklist-watcher || true

    rm -f /usr/local/bin/nginx-blacklist-watcher.sh
    rm -f /usr/local/bin/gen_nginx_blacklist.sh
    rm -f /etc/systemd/system/nginx-blacklist-watcher.service

    systemctl daemon-reload

    echo "✅ 卸载完成"
}


menu() {
    clear
    echo "========== Nginx 黑名单管理 =========="
    echo "1) 安装 & 初始化全部环境（首次运行）"
    echo "2) 编辑 /etc/nginx/blacklist.txt"
    echo "3) 查看 blacklist.txt"
    echo "4) 手动生成 blacklist.conf 并重载 Nginx"
    echo "5) 查看 watcher 服务状态"
    echo "6) 查看 watcher 最近日志"
    echo "7) 卸载 nginx 黑名单监听服务"
    echo "0) 退出"
    echo "======================================"
    read -rp "请选择: " choice

    case "$choice" in
        1)
            install_inotify
            init_files
            create_gen_script
            create_watcher_script
            create_service
            start_service
            ;;
        2) edit_blacklist ;;
        3) show_blacklist ;;
        4) gen_now ;;
        5) service_status ;;
        6) service_logs ;;
        7) uninstall_all ;;
        0) exit 0 ;;
        *) echo "❌ 无效选择" ;;
    esac

    read -rp "按回车继续..."
}

require_root
while true; do
    menu
done
