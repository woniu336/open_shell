#!/bin/bash

# Certimate 自动部署脚本 for Debian
# 版本: v0.4.7

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
GITHUB_REPO="certimate-go/certimate"
INSTALL_DIR="/usr/sbin/certimate"
SERVICE_FILE="/etc/systemd/system/certimate.service"
TEMP_DIR="/tmp/certimate_install"
VERSION=""
DOWNLOAD_URL=""

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用 root 权限运行此脚本"
        log_info "使用命令: sudo bash $0"
        exit 1
    fi
}

# 检查并安装依赖
install_dependencies() {
    log_info "检查并安装必要的依赖..."
    
    # 更新包列表
    apt-get update -qq
    
    # 检查并安装 wget
    if ! command -v wget &> /dev/null; then
        log_info "安装 wget..."
        apt-get install -y wget
    fi
    
    # 检查并安装 unzip
    if ! command -v unzip &> /dev/null; then
        log_info "安装 unzip..."
        apt-get install -y unzip
    fi
    
    # 检查并安装 curl 和 jq (用于获取最新版本)
    if ! command -v curl &> /dev/null; then
        log_info "安装 curl..."
        apt-get install -y curl
    fi
    
    if ! command -v jq &> /dev/null; then
        log_info "安装 jq..."
        apt-get install -y jq
    fi
    
    log_info "依赖检查完成"
}

# 获取最新版本号
get_latest_version() {
    log_info "正在获取最新版本信息..."
    
    # 从 GitHub API 获取最新 release 信息
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    
    VERSION=$(curl -s "${api_url}" | jq -r '.tag_name')
    
    if [ -z "${VERSION}" ] || [ "${VERSION}" == "null" ]; then
        log_error "无法获取最新版本信息"
        log_info "尝试使用备用方法..."
        
        # 备用方法：从 releases 页面解析
        VERSION=$(curl -s "https://github.com/${GITHUB_REPO}/releases/latest" | grep -oP 'tag/\K[^"]+' | head -1)
        
        if [ -z "${VERSION}" ]; then
            log_error "备用方法也失败了，请检查网络连接"
            exit 1
        fi
    fi
    
    log_info "检测到最新版本: ${GREEN}${VERSION}${NC}"
    
    # 构建下载 URL
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/certimate_${VERSION}_linux_amd64.zip"
}

# 创建安装目录
create_directory() {
    log_info "创建安装目录: ${INSTALL_DIR}"
    
    if [ -d "${INSTALL_DIR}" ]; then
        log_warn "目录已存在,将清空现有文件"
        rm -rf "${INSTALL_DIR}"/*
    else
        mkdir -p "${INSTALL_DIR}"
    fi
    
    # 创建临时目录
    mkdir -p "${TEMP_DIR}"
}

# 下载 Certimate
download_certimate() {
    log_info "下载 Certimate ${VERSION}..."
    
    cd "${TEMP_DIR}"
    
    if wget -q --show-progress "${DOWNLOAD_URL}" -O certimate.zip; then
        log_info "下载完成"
    else
        log_error "下载失败,请检查网络连接或 URL 是否正确"
        exit 1
    fi
}

# 解压文件
extract_files() {
    log_info "解压文件到 ${INSTALL_DIR}..."
    
    if unzip -q "${TEMP_DIR}/certimate.zip" -d "${INSTALL_DIR}"; then
        log_info "解压完成"
    else
        log_error "解压失败"
        exit 1
    fi
    
    # 添加执行权限
    chmod +x "${INSTALL_DIR}/certimate"
}

# 创建 systemd 服务
create_service() {
    log_info "创建 systemd 服务文件..."
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  网络访问配置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Certimate 默认仅本地访问 (127.0.0.1:8090)"
    echo ""
    echo "  [1] 允许外网访问 (0.0.0.0:8090)"
    echo "  [2] 仅本地访问 (127.0.0.1:8090) [推荐]"
    echo "  [3] 自定义监听地址"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "  请选择 [1/2/3] (默认: 2): " choice
    
    case ${choice} in
        1)
            HTTP_LISTEN="0.0.0.0:8090"
            echo "  → 已设置为允许外网访问: ${HTTP_LISTEN}"
            ;;
        3)
            echo ""
            read -p "  请输入监听地址 (格式: IP:端口): " custom_listen
            HTTP_LISTEN="${custom_listen}"
            echo "  → 已设置自定义监听: ${HTTP_LISTEN}"
            ;;
        *)
            HTTP_LISTEN="127.0.0.1:8090"
            echo "  → 已设置为仅本地访问: ${HTTP_LISTEN}"
            ;;
    esac
    echo ""
    
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Certimate
After=network.target

[Service]
WorkingDirectory=${INSTALL_DIR}/
ExecStart=${INSTALL_DIR}/certimate serve --http ${HTTP_LISTEN}
Restart=on-failure
User=root
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "服务文件创建完成"
}

# 启动服务
start_service() {
    log_info "重载 systemd 配置..."
    systemctl daemon-reload
    
    log_info "启用 Certimate 服务..."
    systemctl enable certimate.service
    
    log_info "启动 Certimate 服务..."
    systemctl start certimate.service
    
    # 等待服务启动
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet certimate.service; then
        log_info "服务启动成功!"
    else
        log_error "服务启动失败,请检查日志: journalctl -u certimate.service -f"
        exit 1
    fi
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -rf "${TEMP_DIR}"
}

# 显示完成信息
show_completion() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Certimate 安装完成!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  访问信息:"
    if [[ "${HTTP_LISTEN}" == "0.0.0.0"* ]]; then
        local port=$(echo ${HTTP_LISTEN} | cut -d':' -f2)
        echo "  访问地址: http://服务器IP:${port}"
        echo "  ⚠ 警告: 服务已绑定到所有网络接口，请确保配置防火墙！"
    elif [[ "${HTTP_LISTEN}" == "127.0.0.1"* ]]; then
        echo "  访问地址: http://127.0.0.1:8090"
        echo "  注意: 当前仅支持本地访问"
    else
        echo "  访问地址: http://${HTTP_LISTEN}"
    fi
    echo ""
    echo "  管理员登录信息:"
    echo -e "  账号: ${GREEN}admin@certimate.fun${NC}"
    echo -e "  密码: ${GREEN}1234567890${NC}"
    echo ""
    echo "  安全提醒:"
    echo "  请在首次登录后立即修改默认密码！"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 主函数
main() {
    log_info "开始安装 Certimate (自动检测最新版本)"
    echo ""
    
    check_root
    install_dependencies
    get_latest_version
    create_directory
    download_certimate
    extract_files
    create_service
    start_service
    cleanup
    show_completion
}

# 执行主函数
main
