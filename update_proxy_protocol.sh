#!/usr/bin/env bash
set -e

NGINX_PREFIX="/opt/om/nginx"
CONF_DIR="$NGINX_PREFIX/conf/sites"

show_menu() {
    clear
    echo "======================================"
    echo "  OpenResty Proxy Protocol 管理工具"
    echo "======================================"
    echo
    echo "1) 启用 Proxy Protocol（自动备份）"
    echo "2) 关闭 Proxy Protocol（不备份，直接还原）"
    echo "0) 退出"
    echo
}

enable_proxy_protocol() {
    BACKUP_DIR="$CONF_DIR/.bak_$(date +%Y%m%d_%H%M%S)"

    echo "[INFO] 备份目录: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    echo "[INFO] 开始启用 Proxy Protocol..."

    for conf in "$CONF_DIR"/*.conf; do
        [ -f "$conf" ] || continue

        if grep -qE 'listen[[:space:]]+443[[:space:]]+ssl;' "$conf" \
           && ! grep -qE 'listen[[:space:]]+443[[:space:]]+ssl[[:space:]]+proxy_protocol;' "$conf"; then

            echo "  -> 修改: $(basename "$conf")"
            cp "$conf" "$BACKUP_DIR/"
            sed -i 's/listen[[:space:]]\+443[[:space:]]\+ssl;/listen 443 ssl proxy_protocol;/g' "$conf"
        fi
    done

    reload_openresty "$BACKUP_DIR"
}

disable_proxy_protocol() {
    echo "[INFO] 开始关闭 Proxy Protocol（无备份）..."

    for conf in "$CONF_DIR"/*.conf; do
        [ -f "$conf" ] || continue

        if grep -qE 'listen[[:space:]]+443[[:space:]]+ssl[[:space:]]+proxy_protocol;' "$conf"; then
            echo "  -> 还原: $(basename "$conf")"
            sed -i 's/listen[[:space:]]\+443[[:space:]]\+ssl[[:space:]]\+proxy_protocol;/listen 443 ssl;/g' "$conf"
        fi
    done

    reload_openresty ""
}

reload_openresty() {
    BACKUP_HINT="$1"

    echo "[INFO] 检测 OpenResty 配置..."
    if openresty -t -p "$NGINX_PREFIX"; then
        echo "[INFO] 配置检测通过，正在 reload..."
        openresty -s reload -p "$NGINX_PREFIX"
        echo "[OK] OpenResty reload 完成"
    else
        echo "[ERROR] 配置检测失败，未 reload"
        if [ -n "$BACKUP_HINT" ]; then
            echo "[HINT] 配置已备份在: $BACKUP_HINT"
        fi
        exit 1
    fi
}

while true; do
    show_menu
    read -rp "请输入选项 [0-2]: " choice

    case "$choice" in
        1)
            enable_proxy_protocol
            read -rp "操作完成，按回车返回菜单..."
            ;;
        2)
            disable_proxy_protocol
            read -rp "操作完成，按回车返回菜单..."
            ;;
        0)
            echo "Bye 👋"
            exit 0
            ;;
        *)
            echo "无效选项"
            sleep 1
            ;;
    esac
done
