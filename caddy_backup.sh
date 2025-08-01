#!/bin/bash

# Caddy证书备份和恢复脚本
# 作者: Assistant
# 版本: 1.0
# 用法: ./caddy_backup.sh [backup|restore] [options]

set -e

# 配置变量
CADDY_DATA_DIR="/var/lib/caddy/.local/share/caddy"
CADDY_CONFIG_DIR="/etc/caddy"
CADDY_AUTOSAVE_CONFIG="/var/lib/caddy/.config/caddy/autosave.json"
BACKUP_BASE_DIR="/opt/caddy-backups"
CADDY_USER="caddy"
CADDY_SERVICE="caddy"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查必要的命令
check_dependencies() {
    local deps=("tar" "rsync" "systemctl")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "缺少必要命令: $cmd"
            exit 1
        fi
    done
}

# 检查Caddy是否运行
check_caddy_status() {
    if systemctl is-active --quiet "$CADDY_SERVICE"; then
        return 0
    else
        return 1
    fi
}

# 创建备份目录
create_backup_dir() {
    local backup_dir="$1"
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir"
        log_info "创建备份目录: $backup_dir"
    fi
}

# 备份函数
backup_caddy() {
    local backup_name="${1:-caddy-backup-$(date +%Y%m%d-%H%M%S)}"
    local backup_dir="$BACKUP_BASE_DIR/$backup_name"
    
    log_info "开始备份Caddy证书和配置..."
    log_info "备份目录: $backup_dir"
    
    # 创建备份目录
    create_backup_dir "$backup_dir"
    
    # 检查Caddy状态
    if check_caddy_status; then
        log_info "Caddy正在运行，使用在线备份模式"
        local online_backup=true
    else
        log_warning "Caddy未运行，使用离线备份模式"
        local online_backup=false
    fi
    
    # 备份证书数据目录（使用rsync确保文件一致性）
    if [[ -d "$CADDY_DATA_DIR" ]]; then
        log_info "备份证书数据目录..."
        if $online_backup; then
            # 在线备份，使用rsync
            rsync -av --exclude='locks/*' "$CADDY_DATA_DIR/" "$backup_dir/data/"
        else
            # 离线备份，直接复制
            cp -r "$CADDY_DATA_DIR" "$backup_dir/data"
        fi
        log_success "证书数据备份完成"
    else
        log_warning "证书数据目录不存在: $CADDY_DATA_DIR"
    fi
    
    # 备份配置文件
    if [[ -f "$CADDY_CONFIG_DIR/Caddyfile" ]]; then
        log_info "备份Caddyfile配置..."
        mkdir -p "$backup_dir/config"
        cp "$CADDY_CONFIG_DIR/Caddyfile" "$backup_dir/config/"
        log_success "Caddyfile备份完成"
    else
        log_warning "Caddyfile不存在: $CADDY_CONFIG_DIR/Caddyfile"
    fi
    
    # 备份自动保存的配置
    if [[ -f "$CADDY_AUTOSAVE_CONFIG" ]]; then
        log_info "备份自动保存配置..."
        cp "$CADDY_AUTOSAVE_CONFIG" "$backup_dir/config/"
        log_success "自动保存配置备份完成"
    fi
    
    # 创建备份信息文件
    cat > "$backup_dir/backup_info.txt" << EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器主机名: $(hostname)
Caddy版本: $(caddy version 2>/dev/null || echo "未知")
Caddy状态: $(systemctl is-active $CADDY_SERVICE 2>/dev/null || echo "未知")
备份模式: $(if $online_backup; then echo "在线备份"; else echo "离线备份"; fi)
源数据目录: $CADDY_DATA_DIR
源配置目录: $CADDY_CONFIG_DIR
EOF
    
    # 创建压缩包
    log_info "创建压缩备份包..."
    cd "$BACKUP_BASE_DIR"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    
    # 验证备份
    if [[ -f "${backup_name}.tar.gz" ]]; then
        local backup_size=$(du -h "${backup_name}.tar.gz" | cut -f1)
        log_success "备份完成! 文件: $BACKUP_BASE_DIR/${backup_name}.tar.gz (大小: $backup_size)"
        
        # 清理临时目录
        rm -rf "$backup_name"
        
        # 显示备份内容摘要
        echo ""
        echo "=== 备份摘要 ==="
        tar -tzf "${backup_name}.tar.gz" | head -20
        if [[ $(tar -tzf "${backup_name}.tar.gz" | wc -l) -gt 20 ]]; then
            echo "... 还有更多文件"
        fi
    else
        log_error "备份失败!"
        exit 1
    fi
}

# 恢复函数
restore_caddy() {
    local backup_file="$1"
    local force_restore="$2"
    
    if [[ -z "$backup_file" ]]; then
        log_error "请指定备份文件路径"
        echo "用法: $0 restore <backup_file.tar.gz> [--force]"
        exit 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi
    
    log_info "开始恢复Caddy证书和配置..."
    log_info "备份文件: $backup_file"
    
    # 检查Caddy状态
    local caddy_was_running=false
    if check_caddy_status; then
        caddy_was_running=true
        if [[ "$force_restore" != "--force" ]]; then
            log_warning "Caddy正在运行，恢复可能会影响服务"
            read -p "是否继续? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "恢复操作已取消"
                exit 0
            fi
        fi
        
        log_info "停止Caddy服务..."
        systemctl stop "$CADDY_SERVICE"
        sleep 2
    fi
    
    # 创建临时恢复目录
    local temp_restore_dir="/tmp/caddy-restore-$(date +%s)"
    mkdir -p "$temp_restore_dir"
    
    # 解压备份文件
    log_info "解压备份文件..."
    tar -xzf "$backup_file" -C "$temp_restore_dir"
    
    # 查找备份内容
    local backup_content_dir=$(find "$temp_restore_dir" -maxdepth 1 -type d -name "caddy-backup-*" | head -1)
    if [[ -z "$backup_content_dir" ]]; then
        log_error "备份文件格式不正确"
        rm -rf "$temp_restore_dir"
        exit 1
    fi
    
    # 显示备份信息
    if [[ -f "$backup_content_dir/backup_info.txt" ]]; then
        echo ""
        echo "=== 备份信息 ==="
        cat "$backup_content_dir/backup_info.txt"
        echo ""
    fi
    
    # 备份当前配置（以防恢复失败）
    local current_backup="/tmp/caddy-current-$(date +%s)"
    log_info "备份当前配置到: $current_backup"
    mkdir -p "$current_backup"
    if [[ -d "$CADDY_DATA_DIR" ]]; then
        cp -r "$CADDY_DATA_DIR" "$current_backup/data" 2>/dev/null || true
    fi
    if [[ -f "$CADDY_CONFIG_DIR/Caddyfile" ]]; then
        mkdir -p "$current_backup/config"
        cp "$CADDY_CONFIG_DIR/Caddyfile" "$current_backup/config/" 2>/dev/null || true
    fi
    
    # 恢复证书数据
    if [[ -d "$backup_content_dir/data" ]]; then
        log_info "恢复证书数据..."
        mkdir -p "$(dirname "$CADDY_DATA_DIR")"
        rm -rf "$CADDY_DATA_DIR"
        cp -r "$backup_content_dir/data" "$CADDY_DATA_DIR"
        chown -R "$CADDY_USER:$CADDY_USER" "$CADDY_DATA_DIR"
        chmod -R 755 "$CADDY_DATA_DIR"
        log_success "证书数据恢复完成"
    else
        log_warning "备份中没有证书数据"
    fi
    
    # 恢复配置文件
    if [[ -f "$backup_content_dir/config/Caddyfile" ]]; then
        log_info "恢复Caddyfile配置..."
        cp "$backup_content_dir/config/Caddyfile" "$CADDY_CONFIG_DIR/"
        chown "$CADDY_USER:$CADDY_USER" "$CADDY_CONFIG_DIR/Caddyfile"
        log_success "Caddyfile恢复完成"
    else
        log_warning "备份中没有Caddyfile配置"
    fi
    
    # 恢复自动保存配置
    if [[ -f "$backup_content_dir/config/autosave.json" ]]; then
        log_info "恢复自动保存配置..."
        mkdir -p "$(dirname "$CADDY_AUTOSAVE_CONFIG")"
        cp "$backup_content_dir/config/autosave.json" "$CADDY_AUTOSAVE_CONFIG"
        chown "$CADDY_USER:$CADDY_USER" "$CADDY_AUTOSAVE_CONFIG"
        log_success "自动保存配置恢复完成"
    fi
    
    # 启动Caddy服务
    if $caddy_was_running; then
        log_info "启动Caddy服务..."
        if systemctl start "$CADDY_SERVICE"; then
            sleep 3
            if check_caddy_status; then
                log_success "Caddy服务启动成功"
            else
                log_error "Caddy服务启动失败，请检查配置"
                log_info "尝试恢复之前的配置..."
                systemctl stop "$CADDY_SERVICE"
                if [[ -d "$current_backup/data" ]]; then
                    rm -rf "$CADDY_DATA_DIR"
                    cp -r "$current_backup/data" "$CADDY_DATA_DIR"
                    chown -R "$CADDY_USER:$CADDY_USER" "$CADDY_DATA_DIR"
                fi
                if [[ -f "$current_backup/config/Caddyfile" ]]; then
                    cp "$current_backup/config/Caddyfile" "$CADDY_CONFIG_DIR/"
                fi
                systemctl start "$CADDY_SERVICE"
                exit 1
            fi
        else
            log_error "Caddy服务启动失败"
            exit 1
        fi
    fi
    
    # 清理临时文件
    rm -rf "$temp_restore_dir"
    rm -rf "$current_backup"
    
    log_success "恢复完成!"
    
    # 显示服务状态
    echo ""
    echo "=== Caddy服务状态 ==="
    systemctl status "$CADDY_SERVICE" --no-pager -l
}

# 列出备份文件
list_backups() {
    log_info "备份文件列表:"
    if [[ -d "$BACKUP_BASE_DIR" ]]; then
        find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f -exec ls -lh {} \; | while read -r line; do
            echo "  $line"
        done
    else
        log_warning "备份目录不存在: $BACKUP_BASE_DIR"
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
Caddy证书备份恢复脚本

用法:
  $0 backup [backup_name]          - 备份Caddy证书和配置
  $0 restore <backup_file> [--force] - 恢复Caddy证书和配置
  $0 list                          - 列出所有备份文件
  $0 help                          - 显示此帮助信息

示例:
  $0 backup                        - 创建自动命名的备份
  $0 backup my-backup              - 创建名为my-backup的备份
  $0 restore /opt/caddy-backups/caddy-backup-20231201-120000.tar.gz
  $0 restore backup.tar.gz --force - 强制恢复，不询问确认

备份目录: $BACKUP_BASE_DIR
配置目录: $CADDY_CONFIG_DIR
数据目录: $CADDY_DATA_DIR

注意:
- 备份时不会停止Caddy服务，确保服务持续运行
- 恢复时会提示是否停止服务（除非使用--force参数）
- 恢复前会自动备份当前配置以防失败
EOF
}

# 主函数
main() {
    case "$1" in
        backup)
            check_root
            check_dependencies
            backup_caddy "$2"
            ;;
        restore)
            check_root
            check_dependencies
            restore_caddy "$2" "$3"
            ;;
        list)
            list_backups
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
