#!/bin/bash

# 文件路径
sysctl_conf="/etc/sysctl.d/99-sysctl.conf"

# 检查参数是否已存在
check_param() {
    grep -q "^$1" "$sysctl_conf"
}

# 添加参数到 sysctl 配置文件
add_param() {
    if ! check_param "$1"; then
        echo "$1" >> "$sysctl_conf"
    fi
}

add_param "net.core.default_qdisc = fq"
add_param "net.ipv4.tcp_congestion_control = bbr"
add_param "net.ipv4.tcp_rmem = 8192 262144 536870912"
add_param "net.ipv4.tcp_wmem = 4096 16384 536870912"
add_param "net.ipv4.tcp_adv_win_scale = -2"
add_param "net.ipv4.tcp_collapse_max_bytes = 6291456"
add_param "net.ipv4.tcp_notsent_lowat = 131072"
add_param "net.ipv4.ip_local_port_range = 1024 65535"
add_param "net.core.rmem_max = 536870912"
add_param "net.core.wmem_max = 536870912"
add_param "net.core.somaxconn = 32768"
add_param "net.core.netdev_max_backlog = 32768"
add_param "net.ipv4.tcp_max_tw_buckets = 65536"
add_param "net.ipv4.tcp_abort_on_overflow = 1"
add_param "net.ipv4.tcp_slow_start_after_idle = 0"
add_param "net.ipv4.tcp_timestamps = 1"
add_param "net.ipv4.tcp_syncookies = 0"
add_param "net.ipv4.tcp_syn_retries = 3"
add_param "net.ipv4.tcp_synack_retries = 3"
add_param "net.ipv4.tcp_max_syn_backlog = 32768"
add_param "net.ipv4.tcp_fin_timeout = 15"
add_param "net.ipv4.tcp_keepalive_intvl = 3"
add_param "net.ipv4.tcp_keepalive_probes = 5"
add_param "net.ipv4.tcp_keepalive_time = 600"
add_param "net.ipv4.tcp_retries1 = 3"
add_param "net.ipv4.tcp_retries2 = 5"
add_param "net.ipv4.tcp_no_metrics_save = 1"
add_param "net.ipv4.ip_forward = 1"
add_param "fs.file-max = 104857600"
add_param "fs.inotify.max_user_instances = 8192"
add_param "fs.nr_open = 1048576"

# 使更改生效
sysctl -p "$sysctl_conf"

echo "BBR 参数已成功添加并生效！"
