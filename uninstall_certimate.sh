#!/bin/bash

# Certimate 完全卸载脚本 for Debian

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="/usr/sbin/certimate"
SERVICE_FILE="/etc/systemd/system/certimate.service"
DATA_DIR="${INSTALL_DIR}/data"

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

log_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用 root 权限运行此脚本"
        log_info "使用命令: sudo bash $0"
        exit 1
    fi
}

# 确认卸载
confirm_uninstall() {
    echo ""
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}         警告：即将卸载 Certimate${NC}"
    echo -e "${RED}============================================${NC}"
    echo ""
    echo -e "${YELLOW}此操作将会：${NC}"
    echo -e "  1. 停止 Certimate 服务"
    echo -e "  2. 禁用服务自启动"
    echo -e "  3. 删除服务配置文件"
    echo -e "  4. 删除程序文件"
    echo ""
    
    # 检查是否有数据
    if [ -d "${DATA_DIR}" ]; then
        log_warn "检测到数据目录: ${DATA_DIR}"
        echo ""
        echo -e "${YELLOW}是否同时删除数据？${NC}"
        echo -e "  ${GREEN}1)${NC} 是 - 删除所有数据（包括证书、配置等）"
        echo -e "  ${GREEN}2)${NC} 否 - 保留数据目录"
        echo ""
        read -p "请选择 [1/2] (默认: 2): " data_choice
        
        if [ "${data_choice}" = "1" ]; then
            DELETE_DATA=true
            log_warn "将删除所有数据！"
        else
            DELETE_DATA=false
            log_info "将保留数据目录"
        fi
    else
        DELETE_DATA=true
    fi
    
    echo ""
    read -p "确认要继续卸载吗？[y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "已取消卸载操作"
        exit 0
    fi
}

# 停止服务
stop_service() {
    log_info "停止 Certimate 服务..."
    
    if systemctl is-active --quiet certimate.service; then
        systemctl stop certimate.service
        log_success "服务已停止"
    else
        log_info "服务未运行，跳过"
    fi
}

# 禁用服务
disable_service() {
    log_info "禁用 Certimate 服务..."
    
    if systemctl is-enabled --quiet certimate.service 2>/dev/null; then
        systemctl disable certimate.service
        log_success "服务已禁用"
    else
        log_info "服务未启用，跳过"
    fi
}

# 删除服务文件
remove_service_file() {
    log_info "删除服务配置文件..."
    
    if [ -f "${SERVICE_FILE}" ]; then
        rm -f "${SERVICE_FILE}"
        systemctl daemon-reload
        log_success "服务配置文件已删除"
    else
        log_info "服务配置文件不存在，跳过"
    fi
}

# 删除程序文件
remove_program_files() {
    log_info "删除程序文件..."
    
    if [ -d "${INSTALL_DIR}" ]; then
        if [ "${DELETE_DATA}" = true ]; then
            # 删除整个目录
            rm -rf "${INSTALL_DIR}"
            log_success "程序文件和数据已全部删除"
        else
            # 只删除程序文件，保留数据
            find "${INSTALL_DIR}" -maxdepth 1 -type f -delete
            find "${INSTALL_DIR}" -maxdepth 1 -type d ! -name "data" ! -path "${INSTALL_DIR}" -exec rm -rf {} +
            log_success "程序文件已删除，数据已保留在: ${DATA_DIR}"
        fi
    else
        log_info "程序目录不存在，跳过"
    fi
}

# 检查残留进程
check_remaining_process() {
    log_info "检查残留进程..."
    
    local pids=$(pgrep -f "certimate" || true)
    
    if [ -n "$pids" ]; then
        log_warn "发现残留进程: $pids"
        read -p "是否强制终止这些进程？[y/N]: " kill_confirm
        
        if [[ "$kill_confirm" =~ ^[Yy]$ ]]; then
            kill -9 $pids
            log_success "残留进程已终止"
        fi
    else
        log_info "没有发现残留进程"
    fi
}

# 检查端口占用
check_port() {
    log_info "检查端口占用..."
    
    if command -v netstat &> /dev/null; then
        local port_check=$(netstat -tlnp | grep ":8090" || true)
    elif command -v ss &> /dev/null; then
        local port_check=$(ss -tlnp | grep ":8090" || true)
    else
        log_info "未安装 netstat 或 ss，跳过端口检查"
        return
    fi
    
    if [ -n "$port_check" ]; then
        log_warn "端口 8090 仍被占用："
        echo "$port_check"
    else
        log_info "端口 8090 已释放"
    fi
}

# 显示卸载结果
show_result() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}         Certimate 卸载完成!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    
    if [ "${DELETE_DATA}" = false ] && [ -d "${DATA_DIR}" ]; then
        echo -e "${YELLOW}数据保留信息：${NC}"
        echo -e "  数据目录: ${GREEN}${DATA_DIR}${NC}"
        echo -e "  如需删除: ${GREEN}rm -rf ${INSTALL_DIR}${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}已删除的内容：${NC}"
    echo -e "  ✓ Certimate 服务"
    echo -e "  ✓ 服务配置文件"
    echo -e "  ✓ 程序二进制文件"
    if [ "${DELETE_DATA}" = true ]; then
        echo -e "  ✓ 所有数据文件"
    fi
    echo ""
    
    echo -e "${YELLOW}如需重新安装：${NC}"
    echo -e "  运行部署脚本即可"
    echo ""
    echo -e "${GREEN}============================================${NC}"
}

# 主函数
main() {
    echo ""
    log_info "Certimate 卸载程序"
    
    check_root
    confirm_uninstall
    
    echo ""
    log_info "开始卸载..."
    echo ""
    
    stop_service
    disable_service
    remove_service_file
    remove_program_files
    check_remaining_process
    check_port
    
    show_result
}

# 执行主函数
main
