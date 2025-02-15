#!/bin/bash

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以root权限运行" 
   exit 1
fi

echo "开始系统优化..."

# 系统内核参数优化
cat > /etc/sysctl.conf << 'EOF'
# 文件描述符限制
fs.file-max = 6815744

# TCP 基础优化参数
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1

# 网络缓冲区优化
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 网络转发设置
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# TCP keepalive 参数
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 连接队列优化
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# TIME_WAIT 优化
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# TCP 性能优化
net.ipv4.tcp_slow_start_after_idle = 0
EOF

echo "应用系统内核参数..."
sysctl -p && sysctl --system

# 修改 systemd 限制
echo "配置 HAProxy systemd 限制..."
mkdir -p /etc/systemd/system/haproxy.service.d/
echo -e "[Service]\nLimitNOFILE=200000" > /etc/systemd/system/haproxy.service.d/limits.conf

# 配置系统限制
echo "配置系统限制..."
cat > /etc/security/limits.conf << 'EOF'
* soft nofile 200000
* hard nofile 200000
root soft nofile 200000
root hard nofile 200000
haproxy soft nofile 200000
haproxy hard nofile 200000
EOF


# 修改 profile
echo "配置 profile..."
echo "ulimit -n 200000" >> /etc/profile

# 配置 SSH
echo "配置 SSH..."
sed -i 's/#UsePAM yes/UsePAM yes/' /etc/ssh/sshd_config

# 重启服务
echo "重启服务..."
systemctl daemon-reload
systemctl restart sshd
systemctl restart haproxy

# 使配置生效
source /etc/profile

echo "优化完成！当前文件描述符限制："
ulimit -n

echo "请重新登录终端以使所有更改生效" 