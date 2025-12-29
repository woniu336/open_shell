#!/bin/bash

# 颜色定义（可选）
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 简洁的输出函数
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_error() { echo -e "${RED}[失败]${NC} $1"; exit 1; }
print_info() { echo -e "[信息] $1"; }

# 1. 检测并安装 rclone
check_install_rclone() {
    if command -v rclone &>/dev/null; then
        print_info "rclone 已安装"
    else
        print_info "正在安装 rclone..."
        sudo -v && curl -fsSL https://rclone.org/install.sh | sudo bash || print_error "rclone 安装失败"
    fi
    
    # 创建配置目录
    mkdir -p /root/.config/rclone || print_error "创建配置目录失败"
}

# 2. 检查并创建配置文件
create_rclone_config() {
    local config_file="/root/.config/rclone/rclone.conf"
    
    if [ -s "$config_file" ]; then
        print_info "rclone 配置文件已存在且非空"
        return 0
    fi
    
    print_info "创建 rclone 配置文件..."
    
    # 获取用户输入
    read -p "请输入密钥ID: " access_key
    read -p "请输入访问密钥: " secret_key
    read -p "请输入终端节点: " endpoint
    
    # 验证输入
    [ -z "$access_key" ] || [ -z "$secret_key" ] || [ -z "$endpoint" ] && print_error "输入不能为空"
    
    # 创建配置文件
    cat > "$config_file" << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = $access_key
secret_access_key = $secret_key
region = auto
endpoint = $endpoint
EOF
    
    chmod 600 "$config_file"
    print_success "配置文件已创建"
}

# 3. 测试配置
test_rclone_config() {
    print_info "测试 rclone 连接..."
    if timeout 10 rclone lsjson r2: &>/dev/null; then
        print_success "连接测试成功"
    else
        print_error "连接测试失败，请检查配置信息"
    fi
}

# 4. 下载并恢复最新备份
restore_nginx_config() {
    # 获取存储桶目录
    read -p "请输入存储桶目录 (例如: r2:blog/bt/www): " bucket_path
    [ -z "$bucket_path" ] && print_error "存储桶目录不能为空"
    
    # 查找最新的 .tar.gz 文件
    print_info "查找最新备份文件..."
    local latest_file=$(rclone lsf "$bucket_path" --files-only | grep '\.tar\.gz$' | sort -r | head -1)
    [ -z "$latest_file" ] && print_error "未找到 .tar.gz 备份文件"
    
    local remote_file="${bucket_path%/}/$latest_file"
    local temp_dir=$(mktemp -d)
    local local_file="$temp_dir/$latest_file"
    
    # 下载文件
    print_info "下载文件: $latest_file"
    rclone copyto "$remote_file" "$local_file" || print_error "文件下载失败"
    
    # 停止 nginx
    print_info "停止 Nginx..."
    systemctl stop nginx 2>/dev/null || pkill -9 nginx 2>/dev/null
    sleep 2
    
    # 恢复配置 - 修复：确保恢复到 /etc/nginx 目录
    print_info "恢复 Nginx 配置到 /etc/nginx..."
    
    # 方法1：先解压到临时目录检查结构
    local extract_dir="$temp_dir/extract"
    mkdir -p "$extract_dir"
    tar -xzf "$local_file" -C "$extract_dir" || print_error "解压失败"
    
    # 检查解压后的内容
    if [ -d "$extract_dir/etc/nginx" ]; then
        # 如果包含完整的 /etc/nginx 路径结构
        print_info "检测到完整路径结构，复制文件..."
        cp -rf "$extract_dir/etc/nginx/"* /etc/nginx/ || print_error "复制文件失败"
    elif [ -d "$extract_dir/nginx" ]; then
        # 如果只包含 nginx 目录
        print_info "检测到 nginx 目录，复制文件..."
        cp -rf "$extract_dir/nginx/"* /etc/nginx/ || print_error "复制文件失败"
    else
        # 如果直接是nginx配置文件
        print_info "检测到直接文件，复制所有内容..."
        cp -rf "$extract_dir/"* /etc/nginx/ || print_error "复制文件失败"
    fi
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    # 检查是否真的有文件被复制到 /etc/nginx
    if [ -f "/etc/nginx/nginx.conf" ] || [ -d "/etc/nginx/conf.d" ] || [ -d "/etc/nginx/sites-available" ]; then
        print_success "Nginx 配置文件已恢复"
    else
        print_error "未找到 Nginx 配置文件，请检查备份文件内容"
    fi
    
    # 启动 nginx
    print_info "启动 Nginx..."
    systemctl start nginx &>/dev/null
    sleep 2
    
    if systemctl is-active nginx &>/dev/null; then
        print_success "Nginx 启动成功"
    else
        print_error "Nginx 启动失败"
    fi
}

# 主函数
main() {
    # 检查是否为root用户
    [ "$EUID" -ne 0 ] && print_error "请使用root用户运行此脚本"
    
    check_install_rclone
    create_rclone_config
    test_rclone_config
    restore_nginx_config
    
    print_success "所有操作完成"
}

# 执行主函数
main "$@"
