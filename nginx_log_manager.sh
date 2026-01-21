#!/bin/bash
#===============================================================================
# Nginx 日志中心管理脚本
# 功能：日志中心（服务端）+ 客户端 统一管理
# 支持：菜单化操作、幂等处理、自动化配置
#===============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_LOG_PATH="/data/nginx_logs"
DEFAULT_RSYNC_PORT=8873
DEFAULT_RSYNC_USER="log_sync"
CONFIG_FILE="/etc/nginx_log_manager.conf"

#===============================================================================
# 通用函数
#===============================================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Nginx 日志中心管理脚本 v1.0                        ║"
    echo "║           基于 Rsync 的集中式日志收集方案                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Nginx 日志中心配置文件
# 由脚本自动生成，请勿手动修改

# 角色: server 或 client
ROLE="${ROLE:-}"

# 服务端配置
LOG_PATH="${LOG_PATH:-$DEFAULT_LOG_PATH}"
RSYNC_PORT="${RSYNC_PORT:-$DEFAULT_RSYNC_PORT}"
RSYNC_USER="${RSYNC_USER:-$DEFAULT_RSYNC_USER}"
RSYNC_PASSWORD="${RSYNC_PASSWORD:-}"

# 客户端配置
CENTER_IP="${CENTER_IP:-}"
CLIENT_LOG_BASE="${CLIENT_LOG_BASE:-/var/log/nginx}"
SYNC_LOGS="${SYNC_LOGS:-}"
SYNC_ROTATED="${SYNC_ROTATED:-yes}"
EOF
    chmod 600 "$CONFIG_FILE"
}

# 生成随机密码
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 16
}

# 按任意键继续
press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
    echo ""
}

#===============================================================================
# 日志中心（服务端）功能
#===============================================================================

# 设置日志存储路径
server_set_log_path() {
    print_info "当前日志存储路径: ${LOG_PATH:-$DEFAULT_LOG_PATH}"
    echo ""
    read -p "请输入新的日志存储路径 (直接回车使用默认值): " new_path

    if [ -z "$new_path" ]; then
        LOG_PATH="$DEFAULT_LOG_PATH"
    else
        LOG_PATH="$new_path"
    fi

    # 创建目录
    if [ ! -d "$LOG_PATH" ]; then
        mkdir -p "$LOG_PATH/active"
        chown -R nobody:nogroup "$LOG_PATH"
        chmod -R 750 "$LOG_PATH"
        print_success "目录 $LOG_PATH 创建成功"
    else
        print_warning "目录 $LOG_PATH 已存在，跳过创建"
        # 确保 active 子目录存在
        if [ ! -d "$LOG_PATH/active" ]; then
            mkdir -p "$LOG_PATH/active"
            chown nobody:nogroup "$LOG_PATH/active"
            chmod 750 "$LOG_PATH/active"
        fi
    fi

    save_config
    print_success "日志存储路径已设置为: $LOG_PATH"
}

# 创建客户端目录
server_create_client_dir() {
    echo ""
    read -p "请输入客户端主机名: " hostname

    if [ -z "$hostname" ]; then
        print_error "主机名不能为空"
        return 1
    fi

    local client_dir="${LOG_PATH:-$DEFAULT_LOG_PATH}/active/$hostname"

    if [ -d "$client_dir" ]; then
        print_warning "目录 $client_dir 已存在，跳过创建"
    else
        mkdir -p "$client_dir"
        chown nobody:nogroup "$client_dir"
        chmod 750 "$client_dir"
        print_success "目录 $client_dir 已创建并设置权限"
    fi
}

# 安装/更新 rsync daemon 配置
server_setup_rsync() {
    print_info "正在配置 rsync daemon..."

    # 检查 rsync 是否安装
    if ! command -v rsync &> /dev/null; then
        print_info "正在安装 rsync..."
        apt-get update && apt-get install -y rsync
    fi

    # 生成或使用现有密码
    if [ -z "$RSYNC_PASSWORD" ]; then
        RSYNC_PASSWORD=$(generate_password)
        print_info "已生成新的 rsync 密码"
    fi

    # 确保日志目录存在
    LOG_PATH="${LOG_PATH:-$DEFAULT_LOG_PATH}"
    mkdir -p "$LOG_PATH/active"
    chown -R nobody:nogroup "$LOG_PATH"

    # 创建 rsync 配置文件
    local rsync_conf="/etc/rsyncd.conf"
    local rsync_secrets="/etc/rsyncd.secrets"

    cat > "$rsync_conf" << EOF
# Rsync Daemon 配置 - Nginx 日志中心
# 自动生成，请勿手动修改

uid = nobody
gid = nogroup
use chroot = no
max connections = 100
timeout = 600
read only = no

log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
lock file = /var/run/rsync.lock

[active]
    path = ${LOG_PATH}/active
    comment = Nginx Active Logs
    auth users = ${RSYNC_USER:-$DEFAULT_RSYNC_USER}
    secrets file = ${rsync_secrets}
    hosts allow = *
    list = no
EOF

    # 创建密码文件
    echo "${RSYNC_USER:-$DEFAULT_RSYNC_USER}:${RSYNC_PASSWORD}" > "$rsync_secrets"
    chmod 600 "$rsync_secrets"

    # 创建 systemd 服务文件（如果不存在）
    local service_file="/etc/systemd/system/rsyncd.service"
    if [ ! -f "$service_file" ] || ! grep -q "Port=${RSYNC_PORT:-$DEFAULT_RSYNC_PORT}" "$service_file" 2>/dev/null; then
        cat > "$service_file" << EOF
[Unit]
Description=Rsync Daemon for Nginx Log Center
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/rsync --daemon --port=${RSYNC_PORT:-$DEFAULT_RSYNC_PORT}
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/rsyncd.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    # 启动服务
    systemctl enable rsyncd
    systemctl restart rsyncd

    save_config

    echo ""
    print_success "Rsync daemon 配置完成！"
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}重要信息，请妥善保存：${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "Rsync 端口: ${GREEN}${RSYNC_PORT:-$DEFAULT_RSYNC_PORT}${NC}"
    echo -e "Rsync 用户: ${GREEN}${RSYNC_USER:-$DEFAULT_RSYNC_USER}${NC}"
    echo -e "Rsync 密码: ${GREEN}${RSYNC_PASSWORD}${NC}"
    echo -e "日志路径:   ${GREEN}${LOG_PATH}${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    print_warning "请记录以上密码，客户端配置时需要使用！"
}

# 配置日志轮转
server_setup_logrotate() {
    print_info "正在配置日志轮转..."

    local logrotate_conf="/etc/logrotate.d/nginx-rsync-logs"
    LOG_PATH="${LOG_PATH:-$DEFAULT_LOG_PATH}"

    # 检查是否已存在配置
    if [ -f "$logrotate_conf" ]; then
        print_warning "日志轮转配置已存在"
        read -p "是否覆盖现有配置？(y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_info "跳过日志轮转配置"
            return 0
        fi
    fi

    cat > "$logrotate_conf" << EOF
${LOG_PATH}/active/**/*.log {
    daily
    rotate 14
    maxage 14

    missingok
    notifempty
    copytruncate

    compress
    delaycompress

    dateext
    dateformat -%Y%m%d

    create 640 nobody nogroup
}
EOF

    print_success "日志轮转配置完成！"
    echo ""
    echo "配置说明："
    echo "  - daily: 每天轮转一次"
    echo "  - rotate 14 / maxage 14: 保留 14 天"
    echo "  - copytruncate: 适合 rsync 持续写入场景"
    echo "  - dateext: 使用日期作为后缀"
}

# 查看日志状态
server_view_status() {
    echo ""
    echo -e "${CYAN}========== Rsync 服务状态 ==========${NC}"
    systemctl status rsyncd --no-pager 2>/dev/null || print_warning "rsync 服务未运行"

    echo ""
    echo -e "${CYAN}========== Rsync 进程 ==========${NC}"
    ps -C rsync -o pid,state,cmd 2>/dev/null || print_info "没有运行中的 rsync 进程"

    echo ""
    echo -e "${CYAN}========== 日志目录大小 ==========${NC}"
    LOG_PATH="${LOG_PATH:-$DEFAULT_LOG_PATH}"
    if [ -d "$LOG_PATH/active" ]; then
        du -h "$LOG_PATH/active"/* 2>/dev/null | sort -h || print_info "目录为空"
    else
        print_warning "日志目录不存在"
    fi

    echo ""
    echo -e "${CYAN}========== 最近日志写入 ==========${NC}"
    if [ -f "/var/log/rsyncd.log" ]; then
        tail -20 /var/log/rsyncd.log
    else
        print_info "日志文件不存在"
    fi
}

# 服务端菜单
server_menu() {
    while true; do
        print_banner
        echo -e "${GREEN}>>> 日志中心（服务端）管理 <<<${NC}"
        echo ""
        echo "  1. 设置日志存储路径"
        echo "  2. 创建客户端目录"
        echo "  3. 安装/更新 Rsync Daemon"
        echo "  4. 配置日志轮转"
        echo "  5. 查看日志状态"
        echo "  6. 测试日志轮转 (dry-run)"
        echo "  7. 强制执行日志轮转"
        echo "  8. 显示当前配置"
        echo ""
        echo "  0. 返回主菜单"
        echo ""
        read -p "请选择操作 [0-8]: " choice

        case $choice in
            1) server_set_log_path; press_any_key ;;
            2) server_create_client_dir; press_any_key ;;
            3) server_setup_rsync; press_any_key ;;
            4) server_setup_logrotate; press_any_key ;;
            5) server_view_status; press_any_key ;;
            6)
                print_info "测试日志轮转（不实际执行）..."
                logrotate -d /etc/logrotate.d/nginx-rsync-logs 2>&1 || true
                press_any_key
                ;;
            7)
                print_warning "即将强制执行日志轮转..."
                read -p "确认执行？(y/N): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    logrotate -f /etc/logrotate.d/nginx-rsync-logs
                    print_success "日志轮转执行完成"
                fi
                press_any_key
                ;;
            8)
                echo ""
                echo -e "${CYAN}========== 当前配置 ==========${NC}"
                echo "日志路径: ${LOG_PATH:-$DEFAULT_LOG_PATH}"
                echo "Rsync 端口: ${RSYNC_PORT:-$DEFAULT_RSYNC_PORT}"
                echo "Rsync 用户: ${RSYNC_USER:-$DEFAULT_RSYNC_USER}"
                echo "Rsync 密码: ${RSYNC_PASSWORD:-未设置}"
                press_any_key
                ;;
            0) return ;;
            *) print_error "无效选择"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# 客户端功能
#===============================================================================

# 配置日志中心 IP
client_set_center_ip() {
    echo ""
    print_info "当前日志中心 IP: ${CENTER_IP:-未配置}"
    read -p "请输入日志中心 IP 地址: " new_ip

    if [ -z "$new_ip" ]; then
        print_error "IP 地址不能为空"
        return 1
    fi

    CENTER_IP="$new_ip"
    save_config
    print_success "日志中心 IP 已设置为: $CENTER_IP"
}

# 配置 rsync 密码
client_set_password() {
    echo ""
    read -s -p "请输入 rsync 密码（来自日志中心）: " password
    echo ""

    if [ -z "$password" ]; then
        print_error "密码不能为空"
        return 1
    fi

    local passfile="/root/.rsync_pass"

    # 幂等处理：检查密码是否已存在且相同
    if [ -f "$passfile" ]; then
        existing_pass=$(cat "$passfile")
        if [ "$existing_pass" = "$password" ]; then
            print_warning "密码文件已存在且内容相同，跳过更新"
            return 0
        fi
    fi

    echo "$password" > "$passfile"
    chmod 600 "$passfile"
    RSYNC_PASSWORD="$password"
    save_config
    print_success "rsync 密码已保存到 $passfile"
}

# 配置日志目录
client_set_log_dir() {
    echo ""
    print_info "当前日志目录: ${CLIENT_LOG_BASE:-/var/log/nginx}"
    read -p "请输入 Nginx 日志目录路径 (直接回车使用默认值): " new_dir

    if [ -z "$new_dir" ]; then
        CLIENT_LOG_BASE="/var/log/nginx"
    else
        CLIENT_LOG_BASE="$new_dir"
    fi

    if [ ! -d "$CLIENT_LOG_BASE" ]; then
        print_error "目录 $CLIENT_LOG_BASE 不存在"
        return 1
    fi

    save_config
    print_success "日志目录已设置为: $CLIENT_LOG_BASE"
}

# 配置同步日志文件
client_set_sync_logs() {
    echo ""
    print_info "当前同步的日志文件:"
    if [ -n "$SYNC_LOGS" ]; then
        echo "$SYNC_LOGS" | tr ',' '\n' | while read log; do
            echo "  - $log"
        done
    else
        echo "  (未配置)"
    fi

    echo ""
    echo "请输入要同步的日志文件名（多个文件用逗号或空格分隔）"
    echo "例如: www.example.com-access.log, api.example.com-access.log"
    read -p "日志文件: " logs_input

    if [ -z "$logs_input" ]; then
        print_error "日志文件列表不能为空"
        return 1
    fi

    # 处理输入：去空格、去重
    # 将逗号和空格统一为换行，然后去重
    local cleaned_logs=$(echo "$logs_input" | tr ',' '\n' | tr ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')

    SYNC_LOGS="$cleaned_logs"
    save_config

    echo ""
    print_success "已配置同步以下日志文件（已去重去空格）:"
    echo "$SYNC_LOGS" | tr ',' '\n' | while read log; do
        [ -n "$log" ] && echo "  - $log"
    done
}

# 创建/更新同步脚本
client_create_sync_script() {
    print_info "正在创建同步脚本..."

    # 检查必要配置
    if [ -z "$CENTER_IP" ]; then
        print_error "请先配置日志中心 IP"
        return 1
    fi

    if [ -z "$SYNC_LOGS" ]; then
        print_error "请先配置要同步的日志文件"
        return 1
    fi

    if [ ! -f "/root/.rsync_pass" ]; then
        print_error "请先配置 rsync 密码"
        return 1
    fi

    local script_file="/usr/local/bin/sync_nginx_logs.sh"
    local hostname=$(hostname -s)

    # 构建日志数组
    local logs_array=""
    IFS=',' read -ra LOG_ARRAY <<< "$SYNC_LOGS"
    for log in "${LOG_ARRAY[@]}"; do
        log=$(echo "$log" | xargs)  # trim
        [ -n "$log" ] && logs_array="${logs_array}  \"${log}\"\n"
    done

    cat > "$script_file" << 'SCRIPT_EOF'
#!/bin/bash
# /usr/local/bin/sync_nginx_logs.sh
# 自动生成，请通过管理脚本修改配置

SCRIPT_EOF

    cat >> "$script_file" << EOF
CENTER_IP="${CENTER_IP}"
PORT=${RSYNC_PORT:-$DEFAULT_RSYNC_PORT}
RSYNC_USER="${RSYNC_USER:-$DEFAULT_RSYNC_USER}"
PASSFILE="/root/.rsync_pass"
LOG_BASE="${CLIENT_LOG_BASE:-/var/log/nginx}"
HOSTNAME=\$(hostname -s)
SYNC_ROTATED="${SYNC_ROTATED:-yes}"

# 要同步的日志基名（不含轮转后缀）
LOG_BASES=(
$(echo -e "$logs_array"))
EOF

    cat >> "$script_file" << 'SCRIPT_EOF'

# 同步单个文件的函数
sync_file() {
    local src="$1"
    local dest_name="$2"

    if [ ! -f "$src" ]; then
        return 0
    fi

    echo "[$(date '+%F %T')] 开始同步: $src"
    /usr/bin/rsync -avz \
        --inplace \
        --timeout=180 \
        --bwlimit=2000 \
        --password-file="$PASSFILE" \
        "$src" \
        "rsync://$RSYNC_USER@$CENTER_IP:$PORT/active/$HOSTNAME/$dest_name"

    if [ $? -eq 0 ]; then
        echo "[$(date '+%F %T')] 同步完成: $src"
    else
        echo "[$(date '+%F %T')] 同步失败: $src"
    fi
}

for log_base in "${LOG_BASES[@]}"; do
    # 1. 同步主日志文件
    SRC="$LOG_BASE/$log_base"
    if [ -f "$SRC" ]; then
        sync_file "$SRC" "$log_base"
    else
        echo "[$(date '+%F %T')] 主日志不存在: $SRC"
    fi

    # 2. 同步轮转的日志文件（如果启用）
    if [ "$SYNC_ROTATED" = "yes" ]; then
        # 匹配模式: xxx.log.1, xxx.log.2.gz, xxx.log.3.gz 等
        # 使用 find 查找所有轮转文件
        while IFS= read -r -d '' rotated_file; do
            if [ -f "$rotated_file" ]; then
                # 获取文件名
                file_name=$(basename "$rotated_file")
                sync_file "$rotated_file" "$file_name"
            fi
        done < <(find "$LOG_BASE" -maxdepth 1 -name "${log_base}.*" -print0 2>/dev/null | sort -zV)
    fi
done

echo "[$(date '+%F %T')] ========== 同步任务完成 =========="
SCRIPT_EOF

    chmod +x "$script_file"
    print_success "同步脚本已创建: $script_file"

    echo ""
    echo "脚本内容预览:"
    echo "----------------------------------------"
    head -50 "$script_file"
    echo "----------------------------------------"
}

# 添加/更新定时任务
client_setup_cron() {
    print_info "正在配置定时任务..."

    local cron_cmd="*/5 * * * * flock -n /tmp/sync_nginx_logs.lock /bin/bash /usr/local/bin/sync_nginx_logs.sh >> /var/log/sync_nginx_logs.log 2>&1"
    local cron_marker="sync_nginx_logs.sh"

    # 检查是否已存在相同任务
    if crontab -l 2>/dev/null | grep -q "$cron_marker"; then
        print_warning "定时任务已存在"
        echo ""
        echo "当前任务:"
        crontab -l | grep "$cron_marker"
        echo ""
        read -p "是否更新定时任务？(y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_info "跳过定时任务配置"
            return 0
        fi
        # 删除旧任务
        crontab -l 2>/dev/null | grep -v "$cron_marker" | crontab -
    fi

    # 添加新任务
    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -

    print_success "定时任务配置完成！"
    echo ""
    echo "当前 crontab:"
    crontab -l | grep "$cron_marker" || true
    echo ""
    echo "说明："
    echo "  - 每 5 分钟同步一次"
    echo "  - flock 防止并发执行"
    echo "  - 日志: /var/log/sync_nginx_logs.log"
}

# 测试同步
client_test_sync() {
    print_info "正在测试同步..."

    local script_file="/usr/local/bin/sync_nginx_logs.sh"

    if [ ! -f "$script_file" ]; then
        print_error "同步脚本不存在，请先创建"
        return 1
    fi

    echo ""
    echo "========== 开始测试同步 =========="
    bash "$script_file"
    local result=$?
    echo "========== 测试完成 =========="
    echo ""

    if [ $result -eq 0 ]; then
        print_success "同步测试成功！"
    else
        print_error "同步测试失败，请检查配置"
    fi
}

# 客户端一键配置
client_quick_setup() {
    print_info "开始一键配置客户端..."
    echo ""

    # 1. 配置日志中心 IP
    read -p "请输入日志中心 IP 地址: " CENTER_IP
    if [ -z "$CENTER_IP" ]; then
        print_error "IP 地址不能为空"
        return 1
    fi

    # 2. 配置密码
    read -s -p "请输入 rsync 密码: " password
    echo ""
    if [ -z "$password" ]; then
        print_error "密码不能为空"
        return 1
    fi
    echo "$password" > /root/.rsync_pass
    chmod 600 /root/.rsync_pass
    RSYNC_PASSWORD="$password"

    # 3. 配置日志目录
    read -p "请输入 Nginx 日志目录 [/var/log/nginx]: " CLIENT_LOG_BASE
    CLIENT_LOG_BASE="${CLIENT_LOG_BASE:-/var/log/nginx}"

    # 4. 配置日志文件
    echo "请输入要同步的日志文件（逗号分隔）:"
    read -p "日志文件: " logs_input
    if [ -z "$logs_input" ]; then
        print_error "日志文件列表不能为空"
        return 1
    fi
    SYNC_LOGS=$(echo "$logs_input" | tr ',' '\n' | tr ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')

    # 5. 是否同步轮转日志
    echo ""
    echo "是否同步轮转日志？（如 .log.1, .log.2.gz 等）"
    read -p "同步轮转日志？[Y/n]: " sync_rotated
    if [ "$sync_rotated" = "n" ] || [ "$sync_rotated" = "N" ]; then
        SYNC_ROTATED="no"
    else
        SYNC_ROTATED="yes"
    fi

    # 6. 保存配置
    save_config

    # 7. 创建同步脚本
    client_create_sync_script

    # 8. 配置定时任务
    client_setup_cron

    echo ""
    print_success "客户端配置完成！"
    echo ""
    echo "提示：请确保在日志中心执行以下命令创建客户端目录："
    echo -e "${YELLOW}/usr/local/bin/create_rsync_host_dir.sh $(hostname -s)${NC}"
    echo ""

    read -p "是否立即测试同步？(y/N): " test_now
    if [ "$test_now" = "y" ] || [ "$test_now" = "Y" ]; then
        client_test_sync
    fi
}

# 切换轮转日志同步
client_toggle_rotated() {
    echo ""
    if [ "$SYNC_ROTATED" = "yes" ]; then
        print_info "当前设置: 同步轮转日志 (已启用)"
    else
        print_info "当前设置: 仅同步主日志 (轮转日志已禁用)"
    fi

    echo ""
    echo "轮转日志包括："
    echo "  - xxx-access.log.1"
    echo "  - xxx-access.log.2.gz"
    echo "  - xxx-access.log.3.gz"
    echo "  等..."
    echo ""

    if [ "$SYNC_ROTATED" = "yes" ]; then
        read -p "是否禁用轮转日志同步？(y/N): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            SYNC_ROTATED="no"
            save_config
            print_success "已禁用轮转日志同步"
        fi
    else
        read -p "是否启用轮转日志同步？(Y/n): " confirm
        if [ "$confirm" != "n" ] && [ "$confirm" != "N" ]; then
            SYNC_ROTATED="yes"
            save_config
            print_success "已启用轮转日志同步"
        fi
    fi

    print_warning "请重新创建同步脚本以使配置生效"
}

# 客户端菜单
client_menu() {
    while true; do
        print_banner
        echo -e "${GREEN}>>> 客户端管理 <<<${NC}"
        echo ""
        echo "  1. 配置日志中心 IP"
        echo "  2. 配置 Rsync 密码"
        echo "  3. 配置日志目录"
        echo "  4. 配置同步日志文件"
        echo "  5. 开关轮转日志同步 [当前: ${SYNC_ROTATED:-yes}]"
        echo "  6. 创建/更新同步脚本"
        echo "  7. 添加/更新定时任务"
        echo "  8. 测试同步"
        echo "  9. 查看同步日志"
        echo "  10. 一键配置（推荐首次使用）"
        echo "  11. 显示当前配置"
        echo ""
        echo "  0. 返回主菜单"
        echo ""
        read -p "请选择操作 [0-11]: " choice

        case $choice in
            1) client_set_center_ip; press_any_key ;;
            2) client_set_password; press_any_key ;;
            3) client_set_log_dir; press_any_key ;;
            4) client_set_sync_logs; press_any_key ;;
            5) client_toggle_rotated; press_any_key ;;
            6) client_create_sync_script; press_any_key ;;
            7) client_setup_cron; press_any_key ;;
            8) client_test_sync; press_any_key ;;
            9)
                echo ""
                if [ -f "/var/log/sync_nginx_logs.log" ]; then
                    tail -50 /var/log/sync_nginx_logs.log
                else
                    print_info "同步日志文件不存在"
                fi
                press_any_key
                ;;
            10) client_quick_setup; press_any_key ;;
            11)
                echo ""
                echo -e "${CYAN}========== 客户端当前配置 ==========${NC}"
                echo "日志中心 IP: ${CENTER_IP:-未配置}"
                echo "日志目录: ${CLIENT_LOG_BASE:-/var/log/nginx}"
                echo "同步轮转日志: ${SYNC_ROTATED:-yes}"
                echo "同步的日志文件:"
                if [ -n "$SYNC_LOGS" ]; then
                    echo "$SYNC_LOGS" | tr ',' '\n' | while read log; do
                        [ -n "$log" ] && echo "  - $log"
                    done
                else
                    echo "  (未配置)"
                fi
                press_any_key
                ;;
            0) return ;;
            *) print_error "无效选择"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# 主菜单
#===============================================================================

main_menu() {
    while true; do
        print_banner
        echo "请选择本机角色："
        echo ""
        echo "  1. 日志中心（服务端）"
        echo "  2. 客户端"
        echo ""
        echo "  0. 退出"
        echo ""

        if [ -n "$ROLE" ]; then
            echo -e "当前角色: ${CYAN}$ROLE${NC}"
            echo ""
        fi

        read -p "请选择 [0-2]: " choice

        case $choice in
            1)
                ROLE="server"
                save_config
                server_menu
                ;;
            2)
                ROLE="client"
                save_config
                client_menu
                ;;
            0)
                echo ""
                print_info "感谢使用，再见！"
                exit 0
                ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

#===============================================================================
# 主程序入口
#===============================================================================

main() {
    check_root
    load_config
    main_menu
}

main "$@"
