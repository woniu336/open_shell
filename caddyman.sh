#!/bin/sh

# --- 配置 ---
CADDYFILE_MAIN="/etc/caddy/Caddyfile"
CADDYFILE_CONF_D="/etc/caddy/conf.d"
# --- 结束配置 ---

# --- 颜色定义 (POSIX 兼容) ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m' # 粗体白 (用于标题)
C_NC='\033[0m'       # 无颜色 (重置)
# --- 结束颜色定义 ---


# --- 辅助函数 ---

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf "%b" "${C_RED}错误: 此脚本必须以 root 权限运行。${C_NC}\n"
        exit 1
    fi
}

detect_os() {
    PKG_MANAGER=""
    SERVICE_CMD=""
    
    if command -v apt > /dev/null; then
        PKG_MANAGER="apt-get"
        SERVICE_CMD="systemctl"
    elif command -v apk > /dev/null; then
        PKG_MANAGER="apk"
        SERVICE_CMD="rc-service"
    else
        printf "%b" "${C_RED}错误: 无法识别的包管理器。支持 apt-get (Debian/Ubuntu) 和 apk (Alpine)。${C_NC}\n"
        exit 1
    fi
}

# --- [V15.0 - 新增] ---
# 检查 IP 是否为私有/环回/链接本地地址
is_private_ip() {
    local ip=$1
    
    # IPv4
    case $ip in
        10.*|127.*|169.254.*|192.168.*) return 0 ;; # 0 = true (是私有IP)
        172.16.*|172.17.*|172.18.*|172.19.*) return 0 ;;
        172.2*.*|172.30.*|172.31.*) return 0 ;;
    esac

    # IPv6
    case $ip in
        fe80:*) return 0 ;; # 链接本地
        ::1) return 0 ;;    # 环回
        fc00:*) return 0 ;; # 唯一本地
    esac
    
    return 1 # 1 = false (是公网IP)
}

# --- [V15.0 - 优先Curl / 增加私有IP过滤 / 隐藏成功消息] ---
get_public_ip() {
    IP=""
    IP_TYPE=""
    # 常见的虚拟隧道接口，用于在本地检测时排除它们
    local tunnel_interfaces='(wg-cf|warp|ts-|tailscale|tun)' 

    # (已隐藏) printf "%b" "${C_CYAN}正在检测 Public IP (优先 curl IPv4)...${C_NC}\n"

    # 1. 优先尝试 curl IPv4
    IP=$(curl -s4 icanhazip.com)
    [ -z "$IP" ] && IP=$(curl -s4 ifconfig.me/ip)
    [ -z "$IP" ] && IP=$(curl -s4 api.ipify.org)
    
    if [ -n "$IP" ] && ! is_private_ip "$IP"; then
        IP_TYPE="IPv4"
    else
        IP="" # 丢弃无效IP
    fi
    
    # 2. 其次尝试 curl IPv6
    if [ -z "$IP" ]; then
        IP=$(curl -s6 icanhazip.com)
        [ -z "$IP" ] && IP=$(curl -s6 ifconfig.me/ip)
        [ -z "$IP" ] && IP=$(curl -s6 api.ipify.org)
        
        if [ -n "$IP" ] && ! is_private_ip "$IP"; then
            IP_TYPE="IPv6"
        else
            IP="" # 丢弃无效IP
        fi
    fi

    # 3. 降级: 尝试本地 IPv4 (过滤隧道和私有IP)
    if [ -z "$IP" ] && command -v ip > /dev/null; then
        local local_ips
        local_ips=$(ip -4 addr show scope global | grep -v -E " $tunnel_interfaces" | awk '/inet / {print $2}' | cut -d'/' -f1)
        for local_ip in $local_ips; do
            if ! is_private_ip "$local_ip"; then
                IP="$local_ip"
                IP_TYPE="IPv4"
                break
            fi
        done
    fi

    # 4. 降级: 尝试本地 IPv6 (过滤隧道和私有IP)
    if [ -z "$IP" ] && command -v ip > /dev/null; then
        local local_ips
        local_ips=$(ip -6 addr show scope global | grep -v -E " $tunnel_interfaces" | awk '/inet6/ {print $2}' | cut -d'/' -f1)
        for local_ip in $local_ips; do
            if ! is_private_ip "$local_ip"; then
                IP="$local_ip"
                IP_TYPE="IPv6"
                break
            fi
        done
    fi

    PUBLIC_IP="$IP"
    
    if [ -z "$PUBLIC_IP" ]; then
        printf "%b" "\n${C_RED}错误: 无法获取任何有效的 Public IP (v4 或 v6)。${C_NC}\n"
        printf "%b" "${C_RED}所有 DNS 检查将被跳过。请手动确保您的域名指向正确。${C_NC}\n\n"
    # else
        # (已隐藏) printf "%b" "脚本将使用 ${C_WHITE}$IP_TYPE${C_NC} (${C_WHITE}$PUBLIC_IP${C_NC}) 进行 DNS 检查。\n"
    fi
}


check_caddy_installed() {
    if ! command -v caddy > /dev/null; then
        printf "%b" "\n${C_RED}错误: Caddy 尚未安装。${C_NC}\n"
        printf "%b" "请先在主菜单中选择 ${C_WHITE}'1. 安装Caddy服务'${C_NC}。\n"
        return 1
    fi
    return 0
}

is_cloudflare_ip() {
    local ip="$1"
    # 检查 IPv4 和 IPv6 代理前缀
    case "$ip" in
        104.*|172.*|162.*|188.*) return 0 ;; # 0 = true (是 CF IP)
        2a06:*|2a09:*) return 0 ;;
        *) return 1 ;; # 1 = false
    esac
}

check_dns() {
    domain=$1
    if [ -z "$PUBLIC_IP" ]; then
        printf "%b" "${C_YELLOW}警告: 无法获取 Public IP，跳过 DNS 检查。${C_NC}\n"
        return 0
    fi
    
    local domain_ip=""
    
    # 根据我们获取到的 IP 类型，决定是检查 AAAA 还是 A 记录
    if [ "$IP_TYPE" = "IPv6" ]; then
        # 检查 AAAA 记录
        printf "%b" "${C_CYAN}正在检查 $domain 的 DNS AAAA 记录...${C_NC}\n"
        domain_ip=$(getent hosts "$domain" | awk '/::/ { print $1 }' | head -n 1)
        
        if [ -z "$domain_ip" ]; then
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
            printf "%b" "${C_YELLOW}警告: 无法解析域名 $domain 的 AAAA 记录。${C_NC}\n"
            printf "%b" "请确保您已在 DNS 提供商处创建了 AAAA 记录。\n"
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
        
        elif is_cloudflare_ip "$domain_ip"; then
            printf "%b" "${C_GREEN}DNS 提示: $domain (AAAA) 解析到 Cloudflare 代理 ($domain_ip)。${C_NC}\n"
            printf "%b" "${C_GREEN}已假定 DNS 配置正确。${C_NC}\n"
            return 0
            
        elif [ "$domain_ip" != "$PUBLIC_IP" ]; then
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
            printf "%b" "${C_YELLOW}警告: DNS (AAAA) 记录不匹配！${C_NC}\n"
            printf "%b" "   - 域名 $domain 解析到: ${C_WHITE}$domain_ip${C_NC}\n"
            printf "%b" "  - 本服务器的 Public IP 是: ${C_WHITE}$PUBLIC_IP${C_NC}\n"
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
        else
            printf "%b" "${C_GREEN}DNS 检查通过: $domain (AAAA) 正确指向 $PUBLIC_IP.${C_NC}\n"
            return 0
        fi

    else
        # 检查 A 记录
        printf "%b" "${C_CYAN}正在检查 $domain 的 DNS A 记录...${C_NC}\n"
        domain_ip=$(getent hosts "$domain" | awk '!/::/ { print $1 }' | head -n 1)
        
        if [ -z "$domain_ip" ]; then
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
            printf "%b" "${C_YELLOW}警告: 无法解析域名 $domain 的 A 记录。${C_NC}\n"
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
        
        elif is_cloudflare_ip "$domain_ip"; then
            printf "%b" "${C_GREEN}DNS 提示: $domain (A) 解析到 Cloudflare 代理 ($domain_ip)。${C_NC}\n"
            printf "%b" "${C_GREEN}已假定 DNS 配置正确。${C_NC}\n"
            return 0
            
        elif [ "$domain_ip" != "$PUBLIC_IP" ]; then
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
            printf "%b" "${C_YELLOW}警告: DNS (A) 记录不匹配！${C_NC}\n"
            printf "%b" "   - 域名 $domain 解析到: ${C_WHITE}$domain_ip${C_NC}\n"
            printf "%b" "  - 本服务器的 Public IP 是: ${C_WHITE}$PUBLIC_IP${C_NC}\n"
            printf "%b" "${C_RED}******************************************************${C_NC}\n"
        else
            printf "%b" "${C_GREEN}DNS 检查通过: $domain (A) 正确指向 $PUBLIC_IP.${C_NC}\n"
            return 0
        fi
    fi

    # 如果 DNS 检查失败 (无论是 A 还是 AAAA)
    printf "%b" "${C_YELLOW}是否仍然要创建配置 (y/n)? ${C_NC}"
    read confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || return 1
}


reload_caddy() {
    printf "%b" "${C_CYAN}正在验证并重载 Caddy...${C_NC}"
    
    if ! caddy validate --config "$CADDYFILE_MAIN" --adapter caddyfile > /dev/null 2>&1; then
        printf "%b" "\n${C_RED}******************************************************${C_NC}\n"
        printf "%b" "${C_RED}错误: Caddy 配置验证失败！${C_NC}\n"
        printf "%b" "Caddy 未重载。请手动检查 $CADDYFILE_MAIN 和 $CADDYFILE_CONF_D/ 中的文件。\n"
        printf "%b" "${C_RED}******************************************************${C_NC}\n"
        return 1
    fi
    
    if ! caddy reload --config "$CADDYFILE_MAIN" > /dev/null 2>&1; then
        printf "%b" "\n${C_YELLOW} 'caddy reload' 失败, 正在尝试使用 systemd/rc-service...${C_NC}"
        
        local fallback_ok=1
        if [ "$SERVICE_CMD" = "systemctl" ]; then
            if ! $SERVICE_CMD reload caddy > /dev/null 2>&1; then
                fallback_ok=0
            fi
        elif [ "$SERVICE_CMD" = "rc-service" ]; then
            if ! $SERVICE_CMD caddy reload > /dev/null 2>&1; then
                fallback_ok=0
            fi
        fi
        
        if [ "$fallback_ok" -eq 0 ]; then
             printf "%b" "\n${C_RED}错误: Caddy 重载彻底失败。请检查日志。${C_NC}\n"
             return 1
        fi
    fi
    
    printf "%b" " ${C_GREEN}完成！${C_NC}\n"
}

setup_conf_d() {
    mkdir -p "$CADDYFILE_CONF_D"
    IMPORT_LINE="import $CADDYFILE_CONF_D/*.caddy"
    
    local non_comment_lines
    if [ -f "$CADDYFILE_MAIN" ]; then
        non_comment_lines=$(grep -v '^\s*#' "$CADDYFILE_MAIN" 2>/dev/null | grep -v '^\s*$')
    else
        non_comment_lines=""
    fi
    
    if [ "$non_comment_lines" != "$IMPORT_LINE" ]; then
        
        if [ -n "$non_comment_lines" ]; then
            local backup_file="$CADDYFILE_MAIN.bak.$(date +%s)"
            cp "$CADDYFILE_MAIN" "$backup_file"
        fi

        tee "$CADDYFILE_MAIN" > /dev/null << EOL
# CaddyMan Main Config
# Auto-generated by CaddyMan. Do not edit manually unless you know what you are doing.
# All site configs are imported from conf.d/

$IMPORT_LINE
EOL
        
        if command -v caddy > /dev/null && $SERVICE_CMD status caddy > /dev/null 2>&1; then
             caddy reload --config "$CADDYFILE_MAIN" > /dev/null 2>&1
        fi
    fi
}

setup_launcher() {
    local SCRIPT_DEST="/usr/local/bin/ca"
    local SCRIPT_URL="https://raw.githubusercontent.com/ceocok/c.cococ/main/caddyman.sh"
    
    local needs_creation=0
    
    if [ ! -f "$SCRIPT_DEST" ]; then
        needs_creation=1
    else
        if ! grep -q "$SCRIPT_URL" "$SCRIPT_DEST"; then
            needs_creation=1
        fi
    fi

    if [ "$needs_creation" -eq 1 ]; then
        
        tee "$SCRIPT_DEST" > /dev/null << EOF
#!/bin/bash
# CaddyMan Launcher
# Runs the script from GitHub as root
SCRIPT_URL="$SCRIPT_URL"

if [ "\$(id -u)" -ne 0 ]; then
    echo "此脚本需要 root 权限，正在使用 sudo..."
    exec sudo bash <(curl -sL \$SCRIPT_URL) "\$@"
else
    exec bash <(curl -sL \$SCRIPT_URL) "\$@"
fi
EOF
        chmod +x "$SCRIPT_DEST"
        
    fi
}


install_caddy() {
    export DEBIAN_FRONTEND=noninteractive
    
    local caddy_was_installed=0
    if command -v caddy > /dev/null; then
        caddy_was_installed=1
    fi

    # 检查依赖: curl
    if ! command -v curl > /dev/null; then
        printf "%b" "${C_CYAN}正在安装 'curl' (依赖)...${C_NC}\n"
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            $PKG_MANAGER -qq update > /dev/null 2>&1
            $PKG_MANAGER -qq install -y curl
        elif [ "$PKG_MANAGER" = "apk" ]; then
            apk add curl
        fi
    fi
    
    # 检查依赖: iproute2 (用于 'ip' 命令)
    if ! command -v ip > /dev/null; then
         printf "%b" "${C_CYAN}正在安装 'iproute2' (依赖)...${C_NC}\n"
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            $PKG_MANAGER -qq install -y iproute2
        elif [ "$PKG_MANAGER" = "apk" ]; then
            apk add iproute2
        fi
    fi
    
    # 检查依赖: getent (用于 'getent')
    if ! command -v getent > /dev/null; then
         printf "%b" "${C_CYAN}正在安装 'libc-utils' 或 'dnsutils' (依赖)...${C_NC}\n"
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            $PKG_MANAGER -qq install -y libc-bin
        elif [ "$PKG_MANAGER" = "apk" ]; then
            apk add libc-utils
        fi
    fi


    if [ "$caddy_was_installed" -eq 1 ]; then
        printf "%b" "\n${C_GREEN}Caddy 已经安装。${C_NC}\n"
    else
        printf "%b" "${C_CYAN}正在安装 Caddy (标准版)...${C_NC}\n"
        
        if [ "$PKG_MANAGER" = "apt-get" ];
        then
            $PKG_MANAGER -qq install -y debian-keyring debian-archive-keyring apt-transport-https > /dev/null 2>&1
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
            $PKG_MANAGER -qq update > /dev/null 2>&1
            
            $PKG_MANAGER -q install -y caddy
            
        elif [ "$PKG_MANAGER" = "apk" ]; then
            apk add caddy
        fi
        
        if ! command -v caddy > /dev/null; then 
            printf "%b" "${C_RED}错误: Caddy 安装失败。${C_NC}\n"; 
            exit 1; 
        fi
        
        printf "%b" "${C_GREEN}Caddy 安装成功。您现在可以输入'ca'运行CaddyMan${C_NC}\n"
        
        if [ "$SERVICE_CMD" = "systemctl" ]; then
            $SERVICE_CMD enable --now caddy > /dev/null 2>&1
        elif [ "$SERVICE_CMD" = "rc-service" ]; then
            rc-update add caddy default
            $SERVICE_CMD caddy start
        fi
    fi
    
    setup_conf_d
    
    setup_launcher
    
}

view_logs() {
    printf "%b" "${C_CYAN}正在显示 Caddy 实时日志 (按 Ctrl+C 退出)...${C_NC}\n"
    
    if [ "$SERVICE_CMD" = "systemctl" ]; then
        journalctl -u caddy -f --no-pager
    elif command -v journalctl > /dev/null; then
         journalctl -u caddy -f --no-pager
    elif [ -f "/var/log/caddy/caddy.log" ]; then
        tail -f "/var/log/caddy/caddy.log"
    else
        printf "%b" "${C_RED}未找到 Caddy 日志。请检查 /var/log/caddy/ 或 'rc-service caddy settings'。${C_NC}\n"
    fi
}

check_caddy_status() {
    printf "%b" "\n${C_CYAN}--- 检查 Caddy 服务状态 ---${C_NC}\n"
    if [ "$SERVICE_CMD" = "systemctl" ]; then
        $SERVICE_CMD status caddy --no-pager
    elif [ "$SERVICE_CMD" = "rc-service" ]; then
        $SERVICE_CMD caddy status
    else
         printf "%b" "${C_RED}无法确定的服务管理器。${C_NC}\n"
    fi
    printf "%b" "${C_WHITE}----------------------------${C_NC}\n"
}

restart_caddy() {
    printf "%b" "\n${C_CYAN}--- 正在重启 Caddy 服务 ---${C_NC}\n"
    printf "%b" "正在执行: ${C_WHITE}$SERVICE_CMD ... restart${C_NC} ... "
    
    local restart_ok=1
    if [ "$SERVICE_CMD" = "systemctl" ]; then
        if ! $SERVICE_CMD restart caddy > /dev/null 2>&1; then
            restart_ok=0
        fi
    elif [ "$SERVICE_CMD" = "rc-service" ]; then
        if ! $SERVICE_CMD caddy restart > /dev/null 2>&1; then
            restart_ok=0
        fi
    fi

    if [ "$restart_ok" -eq 1 ]; then
         printf "%b" "${C_GREEN}完成！${C_NC}\n"
         sleep 1
         check_caddy_status
    else
         printf "%b" "${C_RED}失败！${C_NC}\n"
         printf "%b" "${C_RED}请手动检查 Caddy 日志。${C_NC}\n"
    fi
}


uninstall_caddy() {
    export DEBIAN_FRONTEND=noninteractive

    printf "%b" "\n${C_RED}--- 卸载 Caddy ---${C_NC}\n"
    printf "%b" "${C_RED}警告: 这将 ${C_WHITE}彻底停止、卸载并清除 (purge) Caddy${C_RED}！\n"
    printf "%b" "${C_RED}此操作将删除软件包和所有配置文件 (${C_WHITE}/etc/caddy${C_RED})。\n"
    printf "%b" "${C_YELLOW}您确定要继续吗? (y/n): ${C_NC}"
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "%b" "操作取消。\n"; return; }

    printf "%b" "${C_YELLOW}再次确认，您确定要完全卸载 Caddy 吗? (y/n): ${C_NC}"
    read confirm2
    [ "$confirm2" != "y" ] && [ "$confirm2" != "Y" ] && { printf "%b" "操作取消。\n"; return; }

    printf "%b" "${C_CYAN}1. 正在停止并禁用 Caddy 服务...${C_NC}\n"
    if [ "$SERVICE_CMD" = "systemctl" ]; then
        $SERVICE_CMD stop caddy > /dev/null 2>&1
        $SERVICE_CMD disable caddy > /dev/null 2>&1
    elif [ "$SERVICE_CMD" = "rc-service" ]; then
        $SERVICE_CMD caddy stop > /dev/null 2>&1
        rc-update del caddy default > /dev/null 2>&1
    fi

    printf "%b" "${C_CYAN}2. 正在卸载并清除 (purge) Caddy 软件包...${C_NC}\n"
    if [ "$PKG_MANAGER" = "apt-get" ]; then
        $PKG_MANAGER -q remove --purge -y caddy > /dev/null
        printf "%b" "${C_CYAN}   - 正在清理 Caddy (apt) 仓库文件...${C_NC}\n"
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        $PKG_MANAGER -qq update > /dev/null 2>&1
    elif [ "$PKG_MANAGER" = "apk" ]; then
        apk del caddy > /dev/null
    fi

 
    printf "%b" "${C_CYAN}3. 正在清理 'ca' 启动器...${C_NC}\n"
    local launcher_path="/usr/local/bin/ca"
    if [ -f "$launcher_path" ]; then
        rm -f "$launcher_path"
    else
        printf "%b" "   - $launcher_path 未找到，跳过清理。\n"
    fi

    printf "%b" "${C_GREEN}Caddy 已成功卸载。${C_NC}\n"
    printf "%b" "${C_YELLOW}注意: 备份文件 /root/caddyman_backup.tar.gz (如果存在) 未被删除。${C_NC}\n"
    printf "%b" "${C_GREEN}脚本即将退出。${C_NC}\n"
    
    exit 0
}


service_management_menu_5() {
    while true; do
        printf "%b" "\n"
        printf "%b" "${C_WHITE}--- 5. Caddy 服务管理 ---${C_NC}\n"
        printf "%b" " ${C_YELLOW}1. 查看 Caddy 状态${C_NC}\n"
        printf "%b" " ${C_YELLOW}2. 重启 Caddy 服务${C_NC}\n"
        printf "%b" " ${C_RED}3. 卸载 Caddy (危险!)${C_NC}\n"
        printf "%b" " ${C_RED}0. 返回主菜单${C_NC}\n"
        printf "%b" "${C_WHITE}-----------------------------------${C_NC}\n"
        printf "%b" "${C_YELLOW}请输入您的选择 [0-3]: ${C_NC}"
        read choice

        case "$choice" in
            1) check_caddy_status ;;
            2) restart_caddy ;;
            3) uninstall_caddy ;;
            0) break ;;
            *) printf "%b" "${C_RED}无效输入，请输入 0 到 3 之间的数字。${C_NC}\n" ;;
        esac
    done
}

backup_sites() {
    printf "%b" "${C_CYAN}--- 备份所有站点 ---${C_NC}\n"
    local backup_file="/root/caddyman_backup.tar.gz"
    local source_dir_parent
    source_dir_parent=$(dirname "$CADDYFILE_CONF_D") # /etc/caddy
    local source_dir_name
    source_dir_name=$(basename "$CADDYFILE_CONF_D") # conf.d

    local files
    files=$(ls -1 "$CADDYFILE_CONF_D"/*.caddy 2>/dev/null)
    
    if [ -z "$files" ]; then
        printf "%b" "${C_RED}错误: $CADDYFILE_CONF_D 目录为空，没有站点可备份。${C_NC}\n"
        return
    fi

    printf "%b" "${C_YELLOW}这将打包 $CADDYFILE_CONF_D 目录中所有 *.caddy 文件到 ${C_WHITE}$backup_file${C_NC}。\n"
    printf "%b" "${C_RED}如果备份文件已存在，它将被覆盖。${C_NC} 是否继续? (y/n): "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "%b" "操作取消。\n"; return; }

    printf "%b" "${C_CYAN}正在备份 $CADDYFILE_CONF_D ...${C_NC}"
    
    tar -czf "$backup_file" -C "$source_dir_parent" "$source_dir_name" > /dev/null 2>&1
    
    if [ "$?" -eq 0 ]; then
        printf "%b" " ${C_GREEN}完成！${C_NC}\n"
        printf "%b" "${C_GREEN}备份成功！文件已保存到: ${C_WHITE}$backup_file${C_NC}\n"
    else
        printf "%b" " ${C_RED}失败！${C_NC}\n"
        printf "%b" "${C_RED}备份失败。请检查 /root/ 目录的写入权限。${C_NC}\n"
    fi
}

restore_sites() {
    printf "%b" "${C_CYAN}--- 恢复所有站点 ---${C_NC}\n"
    local backup_file="/root/caddyman_backup.tar.gz"
    local restore_dest
    restore_dest=$(dirname "$CADDYFILE_CONF_D") # /etc/caddy

    printf "%b" "${C_YELLOW}此功能将从 ${C_WHITE}$backup_file${C_YELLOW} 恢复配置。\n"
    printf "%b" "请确保备份文件命名为caddyman_backup.tar.gz并放在/root目录下。${C_NC}  (y/n): "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "%b" "操作取消。\n"; return; }

    if [ ! -f "$backup_file" ]; then
        printf "%b" "${C_RED}错误: 未找到备份文件: ${C_WHITE}$backup_file${C_NC}\n"
        return
    fi
    
    printf "%b" "${C_RED}警告: 这将解压备份文件并 ${C_WHITE}覆盖${C_RED} 您在 $CADDYFILE_CONF_D 中的所有现有配置！\n"
    printf "%b" "${C_RED}您确定要继续吗? (y/n): ${C_NC}"
    read confirm2
    [ "$confirm2" != "y" ] && [ "$confirm2" != "Y" ] && { printf "%b" "操作取消。\n"; return; }
    
    printf "%b" "${C_CYAN}正在从 $backup_file 恢复到 $restore_dest ...${C_NC}"
    
    tar -xzf "$backup_file" -C "$restore_dest" > /dev/null 2>&1
    
    if [ "$?" -eq 0 ]; then
        printf "%b" " ${C_GREEN}完成！${C_NC}\n"
        printf "%b" "${C_GREEN}恢复成功！${C_NC} E正在自动重载 Caddy...\n"
        reload_caddy
    else
        printf "%b" " ${C_RED}失败！${C_NC}\n"
        printf "%b" "${C_RED}恢复失败。文件可能已损坏或 $restore_dest 目录权限不足。${C_NC}\n"
    fi
}

backup_restore_menu_7() {
    while true; do
        printf "%b" "\n"
        printf "%b" "${C_WHITE}--- 7. 备份/恢复 Caddy ---${C_NC}\n"
        printf "%b" " ${C_YELLOW}1. 备份所有站点到/root/caddyman_backup.tar.gz${C_NC}\n"
        printf "%b" " ${C_YELLOW}2. 从/root/caddyman_backup.tar.gz 恢复站点${C_NC}\n"
        printf "%b" " ${C_RED}0. 返回主菜单${C_NC}\n"
        printf "%b" "${C_WHITE}-----------------------------------${C_NC}\n"
        printf "%b" "${C_YELLOW}请输入您的选择 [0-2]: ${C_NC}"
        read choice

        case "$choice" in
            1) backup_sites ;;
            2) restore_sites ;;
            0) break ;;
            *) printf "%b" "${C_RED}无效输入，请输入 0 到 2 之间的数字。${C_NC}\n" ;;
        esac
    done
}

add_proxy() {
    printf "%b" "${C_CYAN}--- 2. 添加反向代理 ---${C_NC}\n"
    printf "%b" "循环输入域名和端口。\n"
    local count=0
    
    while true; do
        printf "%b" "\n"
        printf "%b" "${C_YELLOW}请输入域名 (留空则退出): ${C_NC}"
        read domain
        [ -z "$domain" ] && break

        printf "%b" "${C_YELLOW}请输入 ${C_WHITE}$domain${C_YELLOW} 的本地端口: ${C_NC}"
        read proxy_port
        
        if [ -z "$proxy_port" ]; then
             printf "%b" "${C_RED}端口不能为空，已跳过此域名。${C_NC}\n"
             continue
        fi
        
        if ! echo "$proxy_port" | grep -Eq '^[0-9]+$'; then
            printf "%b" "${C_RED}端口 '$proxy_port' 无效 (必须是纯数字)，已跳过。${C_NC}\n"
            continue
        fi

        if ! check_dns "$domain"; then
            printf "%b" "${C_RED}DNS 检查失败或被中止，已跳过 $domain。${C_NC}\n"
            continue
        fi
        
        config_file="$CADDYFILE_CONF_D/$domain.caddy"
        if [ -f "$config_file" ]; then
            printf "%b" "${C_RED}配置 $config_file 已存在，已跳过。${C_NC}\n"
            continue
        fi

        local proxy_address="http://127.0.0.1:$proxy_port"
        printf "%b" "   ${C_CYAN}+ 正在准备: ${C_WHITE}$domain${C_CYAN} -> ${C_WHITE}$proxy_address${C_NC}\n"

        tee "$config_file" > /dev/null << EOL
$domain {
    reverse_proxy $proxy_address
}
EOL
        count=$((count + 1))
    done

    if [ "$count" -gt 0 ]; then
        printf "%b" "\n${C_GREEN}成功添加 $count 个新站点。${C_NC}\n"
        reload_caddy
    else
        printf "%b" "\n操作已取消，未添加任何站点。\n"
    fi
}

add_static_host() {
    printf "%b" "${C_CYAN}--- 3. 添加静态网站 ---${C_NC}\n"

    printf "%b" "${C_YELLOW}请输入您的域名: ${C_NC}"
    read domain
    if [ -z "$domain" ]; then printf "%b" "${C_RED}错误：域名不能为空。${C_NC}\n"; return; fi
    
    if ! check_dns "$domain"; then
        printf "%b" "${C_RED}操作已取消 (DNS 检查失败或用户中止)。${C_NC}\n"
        return
    fi
    
    config_file="$CADDYFILE_CONF_D/$domain.caddy"
    
    if [ -f "$config_file" ]; then
        printf "%b" "${C_RED}错误: 域名 $domain 的配置文件已存在 ($config_file)。${C_NC}\n"
        return
    fi

    default_path="/var/www/$domain"
    printf "%b" "${C_YELLOW}请输入网站根目录 [默认: ${C_WHITE}$default_path${C_YELLOW}]: ${C_NC}"
    read root_dir
    if [ -z "$root_dir" ]; then root_dir="$default_path"; fi

    if [ ! -d "$root_dir" ]; then
        printf "%b" "目录 ${C_WHITE}$root_dir${C_NC} 不存在，正在创建...\n"
        mkdir -p "$root_dir"
        chown -R caddy:caddy "$root_dir"  
        echo "<html><body><h1>CaddyMan Site: $domain</h1></body></html>" > "$root_dir/index.html"
        chown caddy:caddy "$root_dir/index.html"
    else
        printf "%b" "目录 ${C_WHITE}$root_dir${C_NC} 已存在，正在确保 'caddy' 用户权限...\n"
        chown -R caddy:caddy "$root_dir"
    fi
        
    printf "%b" "正在创建配置文件: ${C_WHITE}$config_file${C_NC}\n"
    
    tee "$config_file" > /dev/null << EOL
$domain {
    root * $root_dir
    file_server
}
EOL

    printf "%b" "${C_GREEN}配置已创建。${C_NC}\n"
    reload_caddy
}

manage_sites_menu() {
    printf "%b" "\n${C_CYAN}--- 4. 现有站点管理 ---${C_NC}\n"
    local files
    files=$(ls -1 "$CADDYFILE_CONF_D"/*.caddy 2>/dev/null)
    
    if [ -z "$files" ]; then
        printf "%b" "目前没有配置任何站点。\n"
        return
    fi

    printf "%b" "以下是 CaddyMan 管理的站点:\n"
    
    local count=1
    echo "$files" | sed "s|$CADDYFILE_CONF_D/||" | sed 's/\.caddy$//' | while read -r line; do
        if [ "$count" -lt 10 ]; then
            printf "%b" "    ${C_WHITE} $count.${C_NC} $line\n"
        else
            printf "%b" "    ${C_WHITE}$count.${C_NC} $line\n"
        fi
        count=$((count + 1))
    done
    
    local file_count
    file_count=$(echo "$files" | wc -l)

    printf "%b" "${C_WHITE}---------------------------${C_NC}\n"
    printf "%b" " ${C_YELLOW}1. 删除站点 ${C_NC}\n"
    printf "%b" " ${C_RED}0. 返回主菜单${C_NC}\n"
    printf "%b" "${C_WHITE}---------------------------${C_NC}\n"
    printf "%b" "${C_YELLOW}请输入您的选择 [0-1]: ${C_NC}"
    read choice

    case "$choice" in
        1)
            printf "%b" "${C_YELLOW}请输入您要删除的站点的编号 [1-$file_count] (回车取消): ${C_NC}"
            read number
            
            if [ -z "$number" ] || [ "$number" -eq 0 ]; then
                printf "%b" "操作取消。\n"; return
            fi
            
            if ! echo "$number" | grep -Eq '^[0-9]+$'; then
                 printf "%b" "${C_RED}无效输入: 请输入一个数字。${C_NC}\n"; return
            fi
            
            if [ "$number" -lt 1 ] || [ "$number" -gt "$file_count" ]; then
                printf "%b" "${C_RED}无效编号: 请输入 1 到 $file_count 之间的数字。${C_NC}\n"
                return
            fi

            local file_to_delete
            file_to_delete=$(echo "$files" | sed -n "${number}p")
            
            if [ -z "$file_to_delete" ] || [ ! -f "$file_to_delete" ]; then
                printf "%b" "${C_RED}内部错误: 无法找到文件。${C_NC}\n"; return
            fi

            printf "%b" "${C_RED}您确定要删除 ${C_WHITE}$file_to_delete${C_RED} 吗? 这无法撤销。 (y/n): ${C_NC}"
            read confirm
            
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                printf "%b" "正在删除 ${C_WHITE}$file_to_delete${C_NC} ...\n"
                rm "$file_to_delete"
                printf "%b" "${C_GREEN}文件已删除。${C_NC}\n"
                reload_caddy
            else
                printf "%b" "操作取消。\n"
            fi
            ;;
        0)
            return
            ;;
        *)
            printf "%b" "${C_RED}无效输入。${C_NC}\n"
            ;;
    esac
}


# --- 主菜单 (V15.0 - 修复NAT IP / 隐藏IP消息) ---
main_menu() {
    while true; do
        printf "%b" "\n"
        printf "%b" "${C_WHITE}===================================${C_NC}\n"
        printf "%b" " ${C_WHITE}   CaddyMan V15.0  ${C_NC}\n"
        printf "%b" "${C_WHITE}===================================${C_NC}\n"
        printf "%b" " ${C_GREEN}1. 安装Caddy服务${C_NC}\n"
        printf "%b" " ${C_CYAN}2. 添加反向代理${C_NC}\n"
        printf "%b" " ${C_CYAN}3. 添加静态网站${C_NC}\n"
        printf "%b" " ${C_CYAN}4. 现有站点管理${C_NC}\n"
        printf "%b" " ${C_CYAN}5. Caddy服务管理${C_NC}\n"
        printf "%b" " ${C_CYAN}6. 查看运行日志${C_NC}\n"
        printf "%b" " ${C_CYAN}7. 备份或者恢复${C_NC}\n"
        printf "%b" " ${C_RED}0. 退出${C_NC}\n"
        printf "%b" "${C_WHITE}-----------------------------------${C_NC}\n"
        printf "%b" "${C_YELLOW}请输入您的选择 [0-7]: ${C_NC}"
        read choice
        
        case "$choice" in
            1) install_caddy ;;
            2)
                if check_caddy_installed; then
                    add_proxy
                fi
                ;;
            3)
                if check_caddy_installed; then
                    add_static_host
                fi
                ;;
            4)
                if check_caddy_installed; then
                    manage_sites_menu
                fi
                ;;
            5) 
                if check_caddy_installed; then
                    service_management_menu_5
                fi
                ;;
            6) 
                if check_caddy_installed; then
                    view_logs
                fi
                ;;
            7) 
                if check_caddy_installed; then
                    backup_restore_menu_7
                fi
                ;;
            0) printf "%b" "${C_GREEN}再见！${C_NC}\n"; exit 0 ;;
            *) printf "%b" "${C_RED}无效输入，请输入 0 到 7 之间的数字。${C_NC}\n" ;;
        esac
    done
}

# --- 脚本启动 ---
check_root
detect_os
get_public_ip 
main_menu
