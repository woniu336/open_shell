#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 输出函数
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "[i] $1"; }

# 1. 安装工具
install_tools() {
    info "安装必要工具..."
    
    # pigz
    if ! command -v pigz &>/dev/null; then
        apt-get update >/dev/null 2>&1 && apt-get install -y pigz >/dev/null 2>&1 || error "pigz安装失败"
    fi
    
    # python3
    if ! command -v python3 &>/dev/null; then
        apt-get install -y python3 >/dev/null 2>&1 || error "python3安装失败"
    fi
    
    # rclone
    if ! command -v rclone &>/dev/null; then
        info "安装rclone..."
        sudo -v && curl -fsSL https://rclone.org/install.sh | sudo bash >/dev/null 2>&1 || error "rclone安装失败"
    fi
}

# 2. 配置rclone
setup_rclone() {
    local config="/root/.config/rclone/rclone.conf"
    mkdir -p /root/.config/rclone
    
    if [ -s "$config" ]; then
        info "rclone配置已存在"
        return 0
    fi
    
    info "配置rclone..."
    
    read -p "密钥ID: " access_key
    read -p "访问密钥: " secret_key
    read -p "终端节点: " endpoint
    
    [ -z "$access_key" ] || [ -z "$secret_key" ] || [ -z "$endpoint" ] && error "输入不能为空"
    
    cat > "$config" << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = $access_key
secret_access_key = $secret_key
region = auto
endpoint = $endpoint
EOF
    
    chmod 600 "$config"
}

# 3. 测试连接
test_rclone() {
    info "测试rclone连接..."
    if timeout 10 rclone lsjson r2: &>/dev/null; then
        success "rclone连接成功"
    else
        error "rclone连接失败"
    fi
}

# 4. 设置备份配置
setup_backup() {
    local script_dir="/root"
    local backup_dir="/root/nginx_backups"
    
    mkdir -p "$backup_dir"
    cd "$script_dir"
    
    # 下载脚本
    if [ ! -f "website_backup.py" ]; then
        wget -q https://raw.githubusercontent.com/woniu336/open_shell/main/website_backup.py || error "下载备份脚本失败"
    fi
    
    if [ ! -f "backup_config.conf" ]; then
        wget -q https://raw.githubusercontent.com/woniu336/open_shell/main/backup_config.conf || error "下载配置文件失败"
    fi
    
    # 获取用户输入
    read -p "备份源目录路径: " source_dir
    read -p "R2存储路径 (如: web/bt/backup): " remote_path
    
    [ -z "$source_dir" ] && error "备份源目录不能为空"
    [ -z "$remote_path" ] && error "R2存储路径不能为空"
    
    # 更新配置文件
    sed -i "s|^source_dir =.*|source_dir = $source_dir|" backup_config.conf
    sed -i "s|^remote_path =.*|remote_path = $remote_path|" backup_config.conf
    
    success "备份配置已更新"
}

# 5. 执行首次备份并验证
run_initial_backup() {
    info "执行首次备份..."
    
    # 执行Python备份脚本
    if /usr/bin/python3 /root/website_backup.py; then
        success "首次备份执行完成"
    else
        error "首次备份执行失败"
    fi
    
    # 等待片刻确保文件上传完成
    sleep 2
    
    # 检查remote_path目录是否有备份文件
    info "验证备份文件..."
    if rclone ls r2:"$remote_path" 2>/dev/null | head -5; then
        success "备份验证成功：R2存储路径($remote_path)中存在备份文件"
    else
        error "备份验证失败：R2存储路径($remote_path)中没有找到备份文件"
    fi
}

# 6. 设置定时任务
setup_cron() {
    if ! crontab -l 2>/dev/null | grep -q "website_backup.py"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/python3 /root/website_backup.py") | crontab -
        success "定时任务已添加"
    else
        info "定时任务已存在"
    fi
}

# 主流程
main() {
    [ "$EUID" -ne 0 ] && error "请使用root用户运行"
    
    install_tools
    setup_rclone
    test_rclone
    setup_backup
    run_initial_backup  # 新增的首次备份验证
    setup_cron
    
    success "设置完成"
}

main "$@"
