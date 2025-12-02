#!/bin/bash
# OpenResty Manager one click uninstallation script (Improved)
# Supported system: CentOS/RHEL 7+, Debian 11+, Ubuntu 18+, Fedora 32+, etc

info() {
    echo -e "\033[32m[OpenResty Manager] $*\033[0m"
}

warning() {
    echo -e "\033[33m[OpenResty Manager] $*\033[0m"
}

abort() {
    echo -e "\033[31m[OpenResty Manager] $*\033[0m"
    exit 1
}

# 检查并释放端口
release_port() {
    local port=$1
    local service_name=$2
    
    info "检查端口 ${port} 占用情况..."
    
    # 查找占用端口的进程
    if command -v lsof >/dev/null 2>&1; then
        local pids=$(lsof -ti:${port} 2>/dev/null)
    elif command -v ss >/dev/null 2>&1; then
        local pids=$(ss -tlnp | grep ":${port}" | awk '{print $6}' | grep -o 'pid=[0-9]*' | cut -d= -f2)
    elif command -v netstat >/dev/null 2>&1; then
        local pids=$(netstat -tlnp 2>/dev/null | grep ":${port}" | awk '{print $7}' | cut -d/ -f1)
    else
        warning "未找到端口检查工具 (lsof/ss/netstat)，跳过端口检查"
        return
    fi
    
    if [ -z "$pids" ]; then
        info "端口 ${port} 未被占用"
        return
    fi
    
    # 处理占用端口的进程
    for pid in $pids; do
        if [ -n "$pid" ] && [ "$pid" != "-" ]; then
            local process_name=$(ps -p $pid -o comm= 2>/dev/null)
            warning "发现进程 ${process_name} (PID: ${pid}) 占用端口 ${port}"
            
            # 尝试优雅停止
            info "尝试停止进程 ${pid}..."
            kill $pid 2>/dev/null
            sleep 2
            
            # 检查进程是否还在运行
            if ps -p $pid > /dev/null 2>&1; then
                warning "进程仍在运行，强制终止..."
                kill -9 $pid 2>/dev/null
                sleep 1
            fi
            
            # 验证进程已终止
            if ps -p $pid > /dev/null 2>&1; then
                warning "无法终止进程 ${pid}"
            else
                info "成功终止进程 ${pid}"
            fi
        fi
    done
    
    # 再次检查端口
    sleep 1
    if command -v lsof >/dev/null 2>&1; then
        local check_pids=$(lsof -ti:${port} 2>/dev/null)
        if [ -n "$check_pids" ]; then
            warning "端口 ${port} 仍被占用，可能需要手动处理"
        else
            info "端口 ${port} 已成功释放"
        fi
    fi
}

# 停止相关服务
stop_services() {
    info "停止相关服务..."
    
    # 停止可能的 systemd 服务
    for service in openresty-manager om x-ui; do
        if systemctl list-units --full -all | grep -q "${service}.service"; then
            info "停止 ${service} 服务..."
            systemctl stop ${service} 2>/dev/null
            systemctl disable ${service} 2>/dev/null
        fi
    done
    
    # 释放常用端口
    release_port 34567 "OpenResty Manager"
    release_port 80 "HTTP"
    release_port 443 "HTTPS"
}

if [[ $EUID -ne 0 ]]; then
    abort "This script must be run with root privileges"
fi

OS_ARCH=$(uname -m)
case "$OS_ARCH" in
    x86_64|arm*|aarch64)
    ;;
    *)
    abort "Unsupported CPU arch: $OS_ARCH"
    ;;
esac

if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    OS_NAME=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    OS_VERSION=$(lsb_release -sr)
else
    abort "Unable to detect operating system"
fi

main() {
    info "Detected system: ${OS_NAME} ${OS_VERSION} ${OS_ARCH}"
    warning "Uninstall OpenResty Manager ..."
    
    # 先停止服务和释放端口
    stop_services
    
    if [ -f "/opt/om/oms" ]; then
        info "卸载标准安装..."
        /opt/om/oms -s stop > /dev/null 2>&1
        /opt/om/oms -s uninstall > /dev/null 2>&1
        rm -rf /opt/om
    elif [ -f "/opt/om/om.sh" ]; then
        info "卸载 Docker 安装..."
        SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
        cd  "$SCRIPT_PATH"
        docker compose down > /dev/null 2>&1
        docker rm -f openresty-manager > /dev/null 2>&1
        docker images|grep openresty-manager|awk '{print $3}'|xargs docker rmi -f > /dev/null 2>&1
        docker volume ls|grep _om_|awk '{print $2}'|xargs docker volume rm -f > /dev/null 2>&1
        rm -rf /opt/om
    else
        abort 'Not found OpenResty Manager in directory "/opt/om"'
    fi
    
    # 最终检查端口
    info "最终检查端口占用..."
    release_port 34567 "OpenResty Manager"
    
    info "Congratulations on the successful uninstallation"
    info "端口 34567 现已可用，可以重新安装 OpenResty Manager"
}

main
