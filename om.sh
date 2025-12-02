#!/bin/bash

# OpenResty Manager 一键安装脚本
# 支持系统：Debian 11+, Ubuntu 18+, Fedora 32+, etc

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

if [[ $EUID -ne 0 ]]; then
    abort "此脚本必须以root权限运行"
fi

OS_ARCH=$(uname -m)
case "$OS_ARCH" in
    x86_64|arm*|aarch64)
    ;;
    *)
    abort "不支持的 CPU 架构: $OS_ARCH"
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
    abort "无法检测操作系统"
fi

normalize_version() {
    local version=$1
    version=$(echo "$version" | tr -d '[:alpha:]_-' | sed 's/\.\+/./g')
    IFS='.' read -ra segments <<< "$version"

    while [ ${#segments[@]} -lt 4 ]; do
        segments+=(0)
    done

    printf "%04d%04d%04d%04d" \
        "${segments[0]}" \
        "${segments[1]}" \
        "${segments[2]}" \
        "${segments[3]}"
}

NEW_OS_VERSION=$(normalize_version "$OS_VERSION")

install_dependencies() {
    case $OS_NAME in
        ubuntu)
            apt-get update
            apt-get -y install software-properties-common
            add-apt-repository ppa:maxmind/ppa
            apt-get -y install --no-install-recommends wget gnupg ca-certificates lsb-release libmaxminddb0 curl tar logrotate
            ;;
        debian)
            apt-get update
            apt-get -y install --no-install-recommends wget gnupg ca-certificates libmaxminddb0 curl tar logrotate
            ;;
        fedora)
            dnf install -y dnf-plugins-core wget libmaxminddb curl tar logrotate
            ;;
        sles|opensuse*)
            zypper install -y wget libmaxminddb curl tar logrotate
            ;;
        alpine)
            apk add wget libmaxminddb curl tar logrotate
            ;;
        *)
            abort "不支持的Linux发行版: $OS_NAME"
            ;;
    esac
}

check_ports() {
    info "检查端口冲突..."
    
    if command -v ss >/dev/null 2>&1; then
        for port in 80 443 777 34567; do
            if ss -tln "( sport = :${port} )" | grep -q LISTEN; then
                # 显示占用端口的进程信息
                local pid=$(ss -tlnp "( sport = :${port} )" | grep LISTEN | grep -oP 'pid=\K[0-9]+' | head -n1)
                if [ -n "$pid" ]; then
                    local process=$(ps -p $pid -o comm= 2>/dev/null)
                    warning "端口 ${port} 被进程 ${process} (PID: ${pid}) 占用"
                    warning "请运行以下命令停止占用该端口的服务："
                    warning "  sudo systemctl stop ${process} 2>/dev/null || sudo kill -9 ${pid}"
                else
                    warning "端口 ${port} 被占用"
                fi
                abort "请关闭端口 ${port} 后重新安装"
            fi
        done
    elif command -v lsof >/dev/null 2>&1; then
        for port in 80 443 777 34567; do
            if lsof -i:${port} -sTCP:LISTEN >/dev/null 2>&1; then
                local info=$(lsof -i:${port} -sTCP:LISTEN -Fp -Fc 2>/dev/null | tr '\n' ' ')
                warning "端口 ${port} 被占用: ${info}"
                abort "请关闭端口 ${port} 后重新安装"
            fi
        done
    else
        warning "未找到端口检查工具 (ss/lsof)，跳过端口检查"
    fi
    
    info "端口检查通过"
}

add_repository() {
    case $OS_NAME in
        ubuntu)
            local v2=$(normalize_version "22")
            local v3=$(normalize_version "18")
            if [ "$NEW_OS_VERSION" -ge "$v2" ]; then
                wget -O - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
                if [ "$OS_ARCH" = "x86_64" ]; then
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list > /dev/null
                else
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/arm64/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list > /dev/null
                fi
            elif [ "$NEW_OS_VERSION" -lt "$v3" ]; then
                abort "操作系统版本过低，至少需要 Ubuntu 18.04"
            else
                wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
                if [ "$OS_ARCH" = "x86_64" ]; then
                    echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list
                else
                    echo "deb http://openresty.org/package/arm64/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list
                fi
            fi
            apt-get update
            ;;
        debian)
            local v2=$(normalize_version "12")
            local v3=$(normalize_version "11")
            if [ "$NEW_OS_VERSION" -lt "$v3" ]; then
                abort "操作系统版本过低，至少需要 Debian 11"
            fi
            
            if [ "$NEW_OS_VERSION" -ge "$v2" ]; then
                wget -O - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/openresty.gpg
            else
                wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
            fi
            codename=$(grep -Po 'VERSION="[0-9]+ \(\K[^)]+' /etc/os-release)
            if [ "$OS_ARCH" = "x86_64" ]; then                
                echo "deb http://openresty.org/package/debian $codename openresty" | tee /etc/apt/sources.list.d/openresty.list
            else
                echo "deb http://openresty.org/package/arm64/debian $codename openresty" | tee /etc/apt/sources.list.d/openresty.list
            fi
            apt-get update
            ;;
        fedora)
            dnf config-manager --add-repo https://openresty.org/package/fedora/openresty.repo
            ;;
        sles)
            rpm --import https://openresty.org/package/pubkey.gpg
            zypper ar -g --refresh --check "https://openresty.org/package/sles/openresty.repo"
            zypper mr --gpgcheck-allow-unsigned-repo openresty
            ;;
        opensuse*)
            zypper ar -g --refresh --check https://openresty.org/package/opensuse/openresty.repo
            zypper --gpg-auto-import-keys refresh
            ;;
        alpine)
            wget -O '/etc/apk/keys/admin@openresty.com-5ea678a6.rsa.pub' 'http://openresty.org/package/admin@openresty.com-5ea678a6.rsa.pub'
            . /etc/os-release
            MAJOR_VER=$(echo $VERSION_ID | sed 's/\.[0-9]\+$//')
            echo "http://openresty.org/package/alpine/v$MAJOR_VER/main" | tee -a /etc/apk/repositories
            apk update
            ;;
        *)
            abort "不支持的Linux发行版: $OS_NAME"
            ;;
    esac
}

install_openresty() {
    case $OS_NAME in
        debian|ubuntu)
            apt-get install -y openresty
            ;;
        fedora)
            dnf install -y openresty
            ;;
        sles|opensuse*)
            zypper install -y openresty
            ;;
        alpine)
            apk add openresty
            ;;
        *)
            abort "不支持的Linux发行版: $OS_NAME"
            ;;
    esac
    
    if [ $? -ne 0 ]; then
        abort "OpenResty安装失败, 请参考 https://openresty.org/cn/linux-packages.html 查看你的系统版本是否受支持"
    fi
    
    systemctl stop openresty > /dev/null 2>&1
    systemctl disable openresty > /dev/null 2>&1
    info "OpenResty 安装成功"
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        info "Docker 已安装，跳过安装步骤"
        return
    fi
    
    warning "未检测到 Docker 引擎，开始自动安装..."
    warning "这可能需要几分钟时间，请耐心等待..."
    
    # 使用官方 Docker 安装脚本
    if [ -f /tmp/get-docker.sh ]; then
        rm -f /tmp/get-docker.sh
    fi
    
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    
    if [ $? -ne 0 ]; then
        abort "下载 Docker 安装脚本失败，请检查网络连接"
    fi
    
    sh /tmp/get-docker.sh
    
    if [ $? -ne 0 ]; then
        abort "Docker 引擎自动安装失败，请手动安装后重试"
    fi
    
    rm -f /tmp/get-docker.sh
    
    # 配置 Docker 镜像加速
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://doublezonline.cloud"
  ]
}
EOF
    
    # 启动 Docker 服务
    systemctl enable docker
    systemctl daemon-reload
    systemctl restart docker
    
    if [ $? -ne 0 ]; then
        abort "Docker 服务启动失败"
    fi
    
    info "Docker 安装并启动成功"
}

optimize_network() {
    info "优化网络参数..."
    sysctl -w net.ipv4.tcp_mem="3097431 4129911 6194862" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 4194304" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_max_tw_buckets=262144 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_tw_recycle=0 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_tw_reuse=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_syncookies=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=15 > /dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_max_syn_backlog=65535 > /dev/null 2>&1
    sysctl -w net.core.somaxconn=65535 > /dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=200000 > /dev/null 2>&1
    sysctl -p > /dev/null 2>&1
}

install_openresty_manager() {
    warning "下载 OpenResty Manager..."
    
    if [ "$OS_ARCH" = "x86_64" ]; then                
        curl -L https://download.uusec.com/om.tgz -o /tmp/om.tgz
    else
        curl -L https://download.uusec.com/om_arm64.tgz -o /tmp/om.tgz
    fi
    
    if [ $? -ne 0 ]; then
        abort "下载 OpenResty Manager 失败"
    fi
    
    export OM_LANGUAGE=zh
    mkdir -p /opt
    tar -zxf /tmp/om.tgz -C /opt/
    
    if [ $? -ne 0 ]; then
        abort "解压 OpenResty Manager 失败"
    fi
    
    /opt/om/oms -s install && /opt/om/oms -s start
    
    if [ $? -ne 0 ]; then
        abort "OpenResty Manager 安装或启动失败"
    fi
    
    rm -f /tmp/om.tgz
    info "OpenResty Manager 安装成功"
}

allow_firewall_ports() {
    if [ ! -f "/opt/om/.fw" ]; then
        info "配置防火墙规则..."
        echo "" > /opt/om/.fw
        
        if command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port={80,443,34567}/tcp > /dev/null 2>&1
            firewall-cmd --reload > /dev/null 2>&1
            info "firewalld 规则已添加"
        elif command -v ufw >/dev/null 2>&1; then
            for port in 80 443 34567; do 
                ufw allow $port/tcp > /dev/null 2>&1
            done
            ufw reload > /dev/null 2>&1
            info "ufw 规则已添加"
        else
            warning "未检测到防火墙，跳过配置"
        fi
    fi
}

main() {
    info "=========================================="
    info "OpenResty Manager 安装脚本"
    info "=========================================="
    info "检测到系统：${OS_NAME} ${OS_VERSION} ${OS_ARCH}"
    info ""
    
    warning "步骤 1/7: 安装系统依赖..."
    install_dependencies
    
    warning "步骤 2/7: 检查端口冲突..."
    check_ports

    if ! command -v openresty >/dev/null 2>&1; then
        warning "步骤 3/7: 添加 OpenResty 仓库..."
        add_repository
        
        warning "步骤 4/7: 安装 OpenResty..."
        install_openresty
    else
        info "步骤 3-4/7: OpenResty 已安装，跳过"
    fi
    
    warning "步骤 5/7: 检查并安装 Docker..."
    install_docker

    if [ ! -e "/opt/om" ]; then
        warning "步骤 6/7: 安装 OpenResty Manager..."
        optimize_network
        install_openresty_manager
    else
        abort '目录 "/opt/om" 已存在, 请确认删除后再试'
    fi

    warning "步骤 7/7: 配置防火墙..."
    allow_firewall_ports

    info ""
    info "=========================================="
    info "🎉 恭喜！安装成功！"
    info "=========================================="
    info "访问地址: http://YOUR_SERVER_IP:34567"
    info "默认账号: admin"
    info "默认密码: #Passw0rd"
    info "=========================================="
    
    # 重启服务
    /opt/om/oms -s restart > /dev/null 2>&1
}

main
