#!/bin/bash

# 计算TCP内存参数（针对16GB以下内存优化）
memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_pages=$((memory_kb / 4))
min_tcp_mem=$((total_pages * 5 / 100))
pressure_tcp_mem=$((total_pages * 15 / 100))
max_tcp_mem=$((total_pages * 25 / 100))

# 显示当前值和将要设置的值
echo "当前TCP内存配置："
sysctl net.ipv4.tcp_mem

echo -e "\n将要设置的新值："
echo "最小值（5%）：$min_tcp_mem"
echo "压力值（15%）：$pressure_tcp_mem"
echo "最大值（25%）：$max_tcp_mem"

# 确认提示
read -p "是否继续更新配置？(y/n) " confirm
if [[ $confirm != "y" ]]; then
    echo "操作已取消"
    exit 1
fi

# 备份原配置
backup_file="/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"
cp /etc/sysctl.conf "$backup_file"
echo "原配置已备份到：$backup_file"

# 创建新的sysctl配置
cat > /etc/sysctl.conf << EOF
# --------------------------
# 文件描述符与进程限制
# --------------------------
fs.file-max = 6815744

# --------------------------
# TCP 基础优化参数
# --------------------------
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_slow_start_after_idle = 0

# --------------------------
# 网络缓冲区优化（适配低内存）
# --------------------------
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.core.rmem_default = 65536
net.core.wmem_default = 16384

# 默认配置（内存安全）
net.ipv4.tcp_rmem = 4096 65536 1048576
net.ipv4.tcp_wmem = 4096 16384 1048576

# 高吞吐场景
# net.ipv4.tcp_rmem = 4096 131072 2097152
# net.ipv4.tcp_wmem = 4096 65536 2097152

# 高并发场景
# net.ipv4.tcp_rmem = 4096 65536 524288
# net.ipv4.tcp_wmem = 4096 16384 524288

net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# --------------------------
# 连接队列与超时控制（适配低内存）
# --------------------------
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_tw_buckets = 16384
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# --------------------------
# 内存与拥塞控制
# --------------------------
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_mem = $min_tcp_mem $pressure_tcp_mem $max_tcp_mem

# 拥塞控制算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --------------------------
# Keepalive 与安全
# --------------------------
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.route_localnet = 0

# --------------------------
# 网络转发与 IPv6
# --------------------------
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# --------------------------
# 高级加速选项
# --------------------------
net.ipv4.tcp_fastopen = 3
EOF

# 配置 vm.swappiness
find /etc/sysctl.d/ -type f -name "*.conf" -exec sed -i '/^vm.swappiness/d' {} \;
echo "vm.swappiness = 1" > /etc/sysctl.d/99-swap.conf

# 应用所有配置
echo "正在应用新配置..."
sysctl --system

# 验证关键配置
echo -e "\n验证关键配置："
echo "TCP内存配置："
sysctl net.ipv4.tcp_mem
echo "Swappiness配置："
sysctl vm.swappiness