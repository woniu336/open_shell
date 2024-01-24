#!/bin/bash

# 文件路径
sysctl_conf="/etc/sysctl.d/99-sysctl.conf"

# 添加参数到 sysctl 配置文件
echo "net.core.default_qdisc = fq" >> $sysctl_conf
echo "net.ipv4.tcp_congestion_control = bbr" >> $sysctl_conf
echo "net.ipv4.tcp_rmem = 8192 262144 536870912" >> $sysctl_conf
echo "net.ipv4.tcp_wmem = 4096 16384 536870912" >> $sysctl_conf
echo "net.ipv4.tcp_adv_win_scale = -2" >> $sysctl_conf
echo "net.ipv4.tcp_collapse_max_bytes = 6291456" >> $sysctl_conf
echo "net.ipv4.tcp_notsent_lowat = 131072" >> $sysctl_conf
echo "net.ipv4.ip_local_port_range = 1024 65535" >> $sysctl_conf
echo "net.core.rmem_max = 536870912" >> $sysctl_conf
echo "net.core.wmem_max = 536870912" >> $sysctl_conf
echo "net.core.somaxconn = 32768" >> $sysctl_conf
echo "net.core.netdev_max_backlog = 32768" >> $sysctl_conf
echo "net.ipv4.tcp_max_tw_buckets = 65536" >> $sysctl_conf
echo "net.ipv4.tcp_abort_on_overflow = 1" >> $sysctl_conf
echo "net.ipv4.tcp_slow_start_after_idle = 0" >> $sysctl_conf
echo "net.ipv4.tcp_timestamps = 1" >> $sysctl_conf
echo "net.ipv4.tcp_syncookies = 0" >> $sysctl_conf
echo "net.ipv4.tcp_syn_retries = 3" >> $sysctl_conf
echo "net.ipv4.tcp_synack_retries = 3" >> $sysctl_conf
echo "net.ipv4.tcp_max_syn_backlog = 32768" >> $sysctl_conf
echo "net.ipv4.tcp_fin_timeout = 15" >> $sysctl_conf
echo "net.ipv4.tcp_keepalive_intvl = 3" >> $sysctl_conf
echo "net.ipv4.tcp_keepalive_probes = 5" >> $sysctl_conf
echo "net.ipv4.tcp_keepalive_time = 600" >> $sysctl_conf
echo "net.ipv4.tcp_retries1 = 3" >> $sysctl_conf
echo "net.ipv4.tcp_retries2 = 5" >> $sysctl_conf
echo "net.ipv4.tcp_no_metrics_save = 1" >> $sysctl_conf
echo "net.ipv4.ip_forward = 1" >> $sysctl_conf
echo "fs.file-max = 104857600" >> $sysctl_conf
echo "fs.inotify.max_user_instances = 8192" >> $sysctl_conf
echo "fs.nr_open = 1048576" >> $sysctl_conf

# 使更改生效
sysctl -p $sysctl_conf

echo "BBR 参数已成功添加并生效！"