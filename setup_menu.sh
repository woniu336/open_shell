#!/bin/bash

# 服务器设置与管理菜单 v1.2

# 颜色定义
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
PURPLE='\033[0;95m'
CYAN='\033[0;96m'
WHITE='\033[0;97m'
GRAY='\033[0;90m'
NC='\033[0m'

# 显示函数
show_title() { echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"; }
show_header() { echo -e "${PURPLE}║ $1${NC}"; }
show_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
show_success() { echo -e "${GREEN}[✓]${NC} $1"; }
show_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
show_error() { echo -e "${RED}[✗]${NC} $1"; }
show_menu_item() { echo -e "${WHITE}  $1${NC}"; }
show_separator() { echo -e "${GRAY}────────────────────────────────────────────${NC}"; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_error "此脚本需要root权限运行！"
        show_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统类型
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        show_error "无法检测操作系统类型"
        exit 1
    fi
}

# 设置快捷启动
setup_shortcut() {
    local script_path="/root/server_setup.sh"
    local bashrc_file="$HOME/.bashrc"
    
    # 检查脚本是否存在，如果不存在，使用当前脚本路径
    if [[ ! -f "$script_path" ]]; then
        # 获取当前脚本的绝对路径
        if [[ -n "$BASH_SOURCE" ]]; then
            script_path=$(realpath "$BASH_SOURCE" 2>/dev/null || echo "$BASH_SOURCE")
        elif [[ -n "$0" ]]; then
            script_path=$(realpath "$0" 2>/dev/null || echo "$0")
        fi
    fi
    
    # 检查alias是否已存在
    if grep -q "alias mm=" "$bashrc_file" 2>/dev/null; then
        # 更新现有的alias
        sed -i "s|alias mm=.*|alias mm='$script_path'|" "$bashrc_file"
        show_info "快捷启动已更新: mm -> $script_path"
    else
        # 添加新的alias
        echo "alias mm='$script_path'" >> "$bashrc_file"
        show_info "快捷启动已添加: mm -> $script_path"
    fi
    
    # 应用更改
    if [[ -f "$bashrc_file" ]]; then
        source "$bashrc_file" 2>/dev/null || true
    fi
}

# 安装基础工具
install_basic_tools() {
    show_header "安装基础工具"
    apt update
    apt install sudo lrzsz wget curl -y
    [[ $? -eq 0 ]] && show_success "基础工具安装完成！" || show_error "基础工具安装失败！"
}

# SSH密钥登录设置
setup_ssh_keys() {
    show_header "SSH密钥登录设置"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/ssh_quick.sh
    if [[ -f ssh_quick.sh ]]; then
        chmod +x ssh_quick.sh
        ./ssh_quick.sh
    else
        show_error "SSH快速设置脚本下载失败！"
    fi
}

# 命令行补全安装
install_bash_completion() {
    show_header "安装命令行补全"
    apt update
    apt install bash-completion -y
    if [[ $? -eq 0 ]]; then
        source /etc/bash_completion
        type _completion_loader 2>/dev/null && show_success "命令行补全已安装并启用！" || show_warning "需要重新登录以启用补全"
    else
        show_error "命令行补全安装失败！"
    fi
}

# 开启BBR加速
enable_bbr() {
    show_header "开启BBR网络加速"
    current_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    current_qdisc=$(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $3}')
    
    if [[ "$current_cc" == "bbr" ]] && [[ "$current_qdisc" == "fq" ]]; then
        show_success "BBR已经启用，无需重复配置！"
        return 0
    fi
    
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d)
    
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    
    sysctl -p
    lsmod | grep bbr && show_success "BBR已成功启用！" || show_warning "BBR模块未加载，可能需要重启系统"
}

# 设置时区
set_timezone() {
    show_header "设置时区为Asia/Shanghai"
    timedatectl set-timezone Asia/Shanghai
    [[ $(timedatectl show --property=Timezone --value) == "Asia/Shanghai" ]] && show_success "时区已成功设置！" || show_error "时区设置失败！"
}

# 配置DNS
configure_dns() {
    show_header "配置DNS服务器"
    
    if [[ -L /etc/resolv.conf ]]; then
        RESOLV_FILE=$(readlink -f /etc/resolv.conf)
    else
        RESOLV_FILE="/etc/resolv.conf"
    fi
    
    if command -v chattr >/dev/null 2>&1; then
        chattr -i "$RESOLV_FILE" 2>/dev/null && show_info "DNS配置文件已解锁"
    fi
    
    cp "$RESOLV_FILE" "$RESOLV_FILE.backup.$(date +%Y%m%d)"
    
    cat > /tmp/resolv.conf.tmp << EOF
nameserver 8.8.8.8
nameserver 1.0.0.1
nameserver 2001:4860:4860::8888
EOF
    
    mv /tmp/resolv.conf.tmp "$RESOLV_FILE"
    chmod 644 "$RESOLV_FILE"
    
    if command -v chattr >/dev/null 2>&1; then
        chattr +i "$RESOLV_FILE" 2>/dev/null && show_info "DNS配置已锁定"
    fi
    
    nslookup google.com >/dev/null 2>&1 && show_success "DNS配置完成且工作正常！" || show_warning "DNS配置完成，但解析测试失败"
}

# 安装fail2ban
install_fail2ban() {
    show_header "安装fail2ban入侵防御"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/f2.sh
    if [[ -f f2.sh ]]; then
        chmod +x f2.sh
        ./f2.sh
    else
        apt update
        apt install fail2ban -y
        [[ $? -eq 0 ]] && systemctl enable fail2ban && systemctl start fail2ban && show_success "fail2ban安装完成！"
    fi
}

# 配置UFW防火墙
configure_ufw() {
    show_header "配置UFW防火墙"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/block_censys_ips.sh
    if [[ -f block_censys_ips.sh ]]; then
        chmod +x block_censys_ips.sh
        ./block_censys_ips.sh
    fi
    
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw reload
    ufw --force enable
    show_success "UFW防火墙配置完成！"
}

# IP黑名单管理
setup_ip_blacklist() {
    show_header "设置IP黑名单管理"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/ip_blacklist.sh
    [[ -f ip_blacklist.sh ]] && chmod +x ip_blacklist.sh && ./ip_blacklist.sh || show_error "IP黑名单脚本下载失败！"
}

# Nginx反向代理设置
setup_nginx_proxy() {
    show_header "设置Nginx反向代理"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/nginx-acme.sh
    [[ -f nginx-acme.sh ]] && chmod +x nginx-acme.sh && ./nginx-acme.sh || show_error "Nginx反向代理脚本下载失败！"
}

# 安装Nginx UI
install_nginx_ui() {
    show_header "安装Nginx UI管理界面"
    bash -c "$(curl -L https://cloud.nginxui.com/install.sh)" @ install -r https://cloud.nginxui.com/
    [[ $? -eq 0 ]] && show_success "Nginx UI安装完成！" || show_error "Nginx UI安装失败！"
}

# 常用工具集合
install_common_tools() {
    show_header "安装常用工具集合"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/menu.sh
    [[ -f menu.sh ]] && chmod +x menu.sh && ./menu.sh || show_error "常用工具菜单脚本下载失败！"
}

# 安装Docker
install_docker() {
    show_header "安装Docker"
    curl -fsSL https://get.docker.com -o get-docker.sh
    if [[ -f get-docker.sh ]]; then
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        usermod -aG docker $SUDO_USER
        show_success "Docker安装完成！需要重新登录以使用docker命令"
    else
        show_error "Docker安装脚本下载失败！"
    fi
}

# 端口访问限制
setup_port_restriction() {
    show_header "设置端口访问限制"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/ipwl.sh
    [[ -f ipwl.sh ]] && chmod +x ipwl.sh && ./ipwl.sh || show_error "端口限制脚本下载失败！"
}

# Docker端口白名单
setup_docker_whitelist() {
    show_header "设置Docker端口白名单"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/docker_whitelist.sh
    [[ -f docker_whitelist.sh ]] && chmod +x docker_whitelist.sh && ./docker_whitelist.sh || show_error "Docker白名单脚本下载失败！"
}

# 回源限制
setup_origin_restriction() {
    show_header "设置回源限制（仅允许Cloudflare）"
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/cloudflare-only.sh
    [[ -f cloudflare-only.sh ]] && chmod +x cloudflare-only.sh && ./cloudflare-only.sh || show_error "回源限制脚本下载失败！"
}

# SSH连接优化
optimize_ssh() {
    show_header "优化SSH连接"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)
    
    if grep -q "^UsePAM" /etc/ssh/sshd_config; then
        sed -i 's/^UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
    else
        echo "UsePAM yes" >> /etc/ssh/sshd_config
    fi
    
    if grep -q "^X11Forwarding" /etc/ssh/sshd_config; then
        sed -i 's/^X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
    else
        echo "X11Forwarding no" >> /etc/ssh/sshd_config
    fi
    
    if grep -q "^UseDNS" /etc/ssh/sshd_config; then
        sed -i 's/^UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
    else
        echo "UseDNS no" >> /etc/ssh/sshd_config
    fi
    
    if sshd -t; then
        systemctl restart sshd
        show_success "SSH连接优化完成！"
    else
        show_error "SSH配置有错误，请检查！"
    fi
}

# 调整SWAP使用策略
adjust_swap_policy() {
    show_header "调整SWAP使用策略"
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    sudo sed -i '/^vm.swappiness/d' /etc/sysctl.conf
    sudo find /etc/sysctl.d/ -type f -name "*.conf" -exec sed -i '/^vm.swappiness/d' {} \;
    echo "vm.swappiness = 5" | sudo tee /etc/sysctl.d/99-swap.conf
    sudo sysctl --system
    show_success "SWAP使用策略调整完成！"
}

# 设置SWAP分区
setup_swap() {
    show_header "设置SWAP分区"
    
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    total_mem_mb=$((total_mem_kb / 1024))
    
    # 检查是否已有SWAP分区
    if swapon --show | grep -q .; then
        show_warning "系统已有SWAP分区"
        swapon --show
        echo ""
        read -e -p "是否继续设置新的SWAP？(y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    fi
    
    # 检查/swapfile是否已存在且已挂载
    if [[ -f /swapfile ]] && swapon --show | grep -q "/swapfile"; then
        show_warning "/swapfile已存在且已作为SWAP使用"
        read -e -p "是否重新创建SWAP文件？(y/N): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            swapoff /swapfile 2>/dev/null
            rm -f /swapfile
        else
            return
        fi
    elif [[ -f /swapfile ]]; then
        show_warning "/swapfile文件已存在但未作为SWAP使用"
        read -e -p "是否使用现有文件作为SWAP？(y/N): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            chmod 600 /swapfile
            mkswap -f /swapfile
            swapon /swapfile
            grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
            show_success "已使用现有文件作为SWAP分区！"
            return
        else
            rm -f /swapfile
        fi
    fi
    
    if [[ $total_mem_mb -le 2048 ]]; then
        swap_size="1G"
        show_info "内存≤2GB，自动设置SWAP大小为: ${swap_size}"
    else
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        echo -e "${WHITE}推荐设置:${NC}"
        echo -e "${WHITE}  • 内存≤2GB: 设置1GB SWAP${NC}"
        echo -e "${WHITE}  • 内存2-4GB: 设置2GB SWAP${NC}"
        echo -e "${WHITE}  • 内存4-8GB: 设置4GB SWAP${NC}"
        echo -e "${WHITE}  • 内存8-16GB: 设置8GB SWAP${NC}"
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        
        while true; do
            read -e -p "请输入SWAP大小 (例如: 1G, 2G, 4G): " swap_size
            [[ "$swap_size" =~ ^[0-9]+[GgMm]$ ]] && break || show_error "请输入有效的SWAP大小"
        done
    fi
    
    show_info "正在创建SWAP文件..."
    if ! fallocate -l "$swap_size" /swapfile 2>/dev/null; then
        show_warning "fallocate失败，使用dd创建文件..."
        dd if=/dev/zero of=/swapfile bs=1M count=$(( ${swap_size%[GgMm]} * 1024 )) 2>/dev/null
    fi
    
    if [[ ! -f /swapfile ]] || [[ $(stat -c%s /swapfile 2>/dev/null) -lt $(( ${swap_size%[GgMm]} * 1024 * 1024 )) ]]; then
        show_error "SWAP文件创建失败！"
        return 1
    fi
    
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
    
    show_success "SWAP分区设置完成！大小为: ${swap_size}"
    show_info "当前SWAP状态:"
    swapon --show
}

# 节点搭建
setup_node() {
    show_header "节点搭建 (sing-box)"
    show_warning "此操作将安装sing-box节点服务"
    read -e -p "是否继续？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    
    bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh)
    [[ $? -eq 0 ]] && show_success "节点搭建完成！" || show_error "节点搭建失败！"
}

# 字节格式化函数（不依赖bc命令）
format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1099511627776 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes / 1099511627776}") TB"
    elif [[ $bytes -ge 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes / 1073741824}") GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes / 1048576}") MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes / 1024}") KB"
    else
        echo "${bytes} B"
    fi
}

# 获取地理位置
get_geolocation() {
  local city=$(curl -s ipinfo.io/city)
  local region=$(curl -s ipinfo.io/region)
  local country=$(curl -s ipinfo.io/country)
  if [ "$city" = "$region" ]; then
    echo "$city $country"
  else
    echo "$city $region $country"
  fi
}

# 获取 DNS 地址
get_dns_address() {
  grep 'nameserver' /etc/resolv.conf | awk '{print $2}' | grep -v "^run$" | paste -sd " " -
}

# 获取运营商信息
get_isp() {
  curl -s ipinfo.io/org | awk -F' ' '{$1=""; print substr($0,2)}' | sed 's/ Co., Ltd./ Co. Ltd./g'
}

# 获取 IPv4 地址
get_ipv4_address() {
  curl -s ipv4.ip.sb
}

# 系统信息显示
show_system_info() {
    clear
    show_title
    echo -e "${PURPLE}║            📊 系统信息仪表板           ║${NC}"
    show_title
    echo ""
    
    echo -e "${CYAN}系统信息查询${NC}"
    echo -e "${GRAY}-------------${NC}"
    
    # 基础系统信息
    echo -e "${WHITE}基础系统信息${NC}"
    echo -e "${WHITE}主机名: ${GREEN}$(hostname)${NC}"
    
    # 系统版本
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e "${WHITE}系统版本: ${GREEN}$PRETTY_NAME${NC}"
    else
        echo -e "${WHITE}系统版本: ${GREEN}$(uname -s)${NC}"
    fi
    
    # Linux内核版本
    echo -e "${WHITE}Linux版本: ${GREEN}$(uname -r)${NC}"
    
    echo -e "${GRAY}-------------${NC}"
    
    # CPU信息
    echo -e "${WHITE}CPU 信息${NC}"
    
    # CPU架构
    echo -e "${WHITE}CPU架构: ${GREEN}$(uname -m)${NC}"
    
    # CPU型号
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
    echo -e "${WHITE}CPU型号: ${GREEN}${cpu_model:-未知}${NC}"
    
    # CPU核心数
    cpu_cores=$(nproc)
    echo -e "${WHITE}CPU核心数: ${GREEN}${cpu_cores}${NC}"
    
    # CPU频率
    cpu_freq=$(grep -m1 "cpu MHz" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
    if [[ -n "$cpu_freq" ]]; then
        echo -e "${WHITE}CPU频率: ${GREEN}${cpu_freq} MHz${NC}"
    else
        echo -e "${WHITE}CPU频率: ${GREEN}未知${NC}"
    fi
    
    echo -e "${GRAY}-------------${NC}"
    
    # 系统资源使用
    echo -e "${WHITE}系统资源使用${NC}"
    
    # CPU占用率
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "${WHITE}CPU占用: ${GREEN}${cpu_usage}%${NC}"
    
    # 系统负载
    loadavg=$(cat /proc/loadavg)
    load1=$(echo $loadavg | awk '{print $1}')
    load5=$(echo $loadavg | awk '{print $2}')
    load15=$(echo $loadavg | awk '{print $3}')
    echo -e "${WHITE}系统负载: ${GREEN}${load1} ${load5} ${load15}${NC}"
    
    # 物理内存
    mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    mem_usage=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2*100}')
    echo -e "${WHITE}物理内存: ${GREEN}${mem_used} / ${mem_total} (${mem_usage}%)${NC}"
    
    # 虚拟内存
    swap_total=$(free -h | awk '/^Swap:/ {print $2}')
    swap_used=$(free -h | awk '/^Swap:/ {print $3}')
    if [[ "$swap_total" != "0B" ]]; then
        swap_usage=$(free | awk '/^Swap:/ {printf "%.1f", $3/$2*100}')
        echo -e "${WHITE}虚拟内存: ${GREEN}${swap_used} / ${swap_total} (${swap_usage}%)${NC}"
    else
        echo -e "${WHITE}虚拟内存: ${GREEN}未启用${NC}"
    fi
    
    # 硬盘占用
    disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    disk_used=$(df -h / | awk 'NR==2 {print $3}')
    disk_total=$(df -h / | awk 'NR==2 {print $2}')
    echo -e "${WHITE}硬盘占用: ${GREEN}${disk_used} / ${disk_total} (${disk_usage})${NC}"
    
    echo -e "${GRAY}-------------${NC}"
    
    # 网络流量
    echo -e "${WHITE}网络流量${NC}"
    
    # 网络流量统计
    rx_bytes=0
    tx_bytes=0
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        if [[ -f "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
            rx_bytes=$((rx_bytes + $(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)))
            tx_bytes=$((tx_bytes + $(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)))
        fi
    done
    
    # 格式化网络流量
    rx_formatted=$(format_bytes $rx_bytes)
    tx_formatted=$(format_bytes $tx_bytes)
    
    echo -e "${WHITE}总接收: ${GREEN}${rx_formatted}${NC}"
    echo -e "${WHITE}总发送: ${GREEN}${tx_formatted}${NC}"
    
    echo -e "${GRAY}-------------${NC}"
    
    # 网络信息
    echo -e "${WHITE}网络信息${NC}"
    
    # 网络算法 (检查BBR是否启用)
    current_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${WHITE}网络算法: ${GREEN}BBR${NC}"
    else
        echo -e "${WHITE}网络算法: ${GREEN}${current_cc:-默认}${NC}"
    fi
    
    # 运营商信息
    isp_info=$(get_isp)
    if [[ -n "$isp_info" ]]; then
        echo -e "${WHITE}运营商: ${GREEN}${isp_info}${NC}"
    else
        echo -e "${WHITE}运营商: ${GREEN}未知${NC}"
    fi
    
    # IPv4地址
    ipv4_address=$(get_ipv4_address 2>/dev/null || echo "获取失败")
    echo -e "${WHITE}IPv4地址: ${GREEN}${ipv4_address}${NC}"
    
    # DNS地址
    dns_address=$(get_dns_address)
    if [[ -n "$dns_address" ]]; then
        echo -e "${WHITE}DNS地址: ${GREEN}${dns_address}${NC}"
    else
        echo -e "${WHITE}DNS地址: ${GREEN}未知${NC}"
    fi
    
    # 地理位置信息
    if [[ "$ipv4_address" != "获取失败" ]]; then
        geo_info=$(get_geolocation)
        if [[ -n "$geo_info" ]]; then
            echo -e "${WHITE}地理位置: ${GREEN}${geo_info}${NC}"
        else
            echo -e "${WHITE}地理位置: ${GREEN}未知${NC}"
        fi
    else
        echo -e "${WHITE}地理位置: ${GREEN}未知${NC}"
    fi
    
    # 系统时间
    current_time=$(date "+%Y-%m-%d %H:%M:%S %Z")
    echo -e "${WHITE}系统时间: ${GREEN}${current_time}${NC}"
    
    echo -e "${GRAY}-------------${NC}"
    
    # 运行状态
    echo -e "${WHITE}运行状态${NC}"
    
    # 系统运行时间（以天数、小时、分钟显示）
    runtime=$(cat /proc/uptime | awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分", run_minutes)}')
    echo -e "${WHITE}运行时长: ${GREEN}${runtime}${NC}"
    
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════${NC}"
    echo -e "${WHITE}  按任意键返回主菜单...${NC}"
    read -n 1 -s
}


# 主菜单
main_menu() {
    while true; do
        clear
        show_title
        echo -e "${PURPLE}║        🚀 服务器设置与管理菜单 v1.2      ║${NC}"
        show_title
        echo ""
        
        echo -e "${CYAN}📋 系统设置${NC}"
        show_separator
        show_menu_item " 1. 显示系统信息"
        show_menu_item " 2. 安装基础工具"
        show_menu_item " 3. SSH密钥登录设置"
        show_menu_item " 4. 安装命令行补全"
        show_menu_item " 5. 开启BBR网络加速"
        show_menu_item " 6. 设置时区为Asia/Shanghai"
        show_menu_item " 7. 配置DNS服务器"
        show_menu_item " 8. 安装fail2ban入侵防御"
        show_menu_item " 9. 配置UFW防火墙"
        show_menu_item "10. 设置IP黑名单管理"
        show_menu_item "11. 优化SSH连接"
        show_menu_item "12. 调整SWAP使用策略"
        show_menu_item "13. 设置SWAP分区"
        
        echo ""
        echo -e "${CYAN}🌐 网络服务${NC}"
        show_separator
        show_menu_item "14. 设置Nginx反向代理"
        show_menu_item "15. 安装Nginx UI管理界面"
        show_menu_item "16. 安装常用工具集合"
        show_menu_item "17. 安装Docker"
        show_menu_item "18. 设置端口访问限制"
        show_menu_item "19. 设置Docker端口白名单"
        show_menu_item "20. 设置回源限制（仅允许Cloudflare）"
        show_menu_item "21. 节点搭建 (sing-box)"
        
        echo ""
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        show_menu_item " 0. 退出脚本"
        
        echo ""
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        read -e -p "请选择操作 (0-21): " choice
        
        case $choice in
            1) show_system_info ;;
            2) install_basic_tools; read -e -p "按回车键继续..." ;;
            3) setup_ssh_keys; read -e -p "按回车键继续..." ;;
            4) install_bash_completion; read -e -p "按回车键继续..." ;;
            5) enable_bbr; read -e -p "按回车键继续..." ;;
            6) set_timezone; read -e -p "按回车键继续..." ;;
            7) configure_dns; read -e -p "按回车键继续..." ;;
            8) install_fail2ban; read -e -p "按回车键继续..." ;;
            9) configure_ufw; read -e -p "按回车键继续..." ;;
            10) setup_ip_blacklist; read -e -p "按回车键继续..." ;;
            11) optimize_ssh; read -e -p "按回车键继续..." ;;
            12) adjust_swap_policy; read -e -p "按回车键继续..." ;;
            13) setup_swap; read -e -p "按回车键继续..." ;;
            14) setup_nginx_proxy; read -e -p "按回车键继续..." ;;
            15) install_nginx_ui; read -e -p "按回车键继续..." ;;
            16) install_common_tools; read -e -p "按回车键继续..." ;;
            17) install_docker; read -e -p "按回车键继续..." ;;
            18) setup_port_restriction; read -e -p "按回车键继续..." ;;
            19) setup_docker_whitelist; read -e -p "按回车键继续..." ;;
            20) setup_origin_restriction; read -e -p "按回车键继续..." ;;
            21) setup_node; read -e -p "按回车键继续..." ;;
            0) 
                clear
                show_title
                echo -e "${PURPLE}║            👋 感谢使用！              ║${NC}"
                show_title
                echo ""
                show_success "脚本执行完成！"
                exit 0
                ;;
            *) 
                show_error "无效的选择，请重新输入！"
                sleep 2
                ;;
        esac
    done
}

# 脚本入口点
check_root
check_os
setup_shortcut
main_menu
