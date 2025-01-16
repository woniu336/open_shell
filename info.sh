#!/bin/bash

# 定义颜色变量
gl_hui='\e[37m'
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_lan='\033[34m'
gl_bai='\033[0m'
gl_zi='\033[35m'
gl_kjlan='\033[96m'

# 获取主机名
get_hostname() {
  hostname
}

# 获取系统版本
get_os_version() {
  grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"'
}

# 获取 Linux 内核版本
get_linux_version() {
  uname -r
}

# 获取 CPU 架构
get_cpu_arch() {
  uname -m
}

# 获取 CPU 型号
get_cpu_model() {
  grep 'model name' /proc/cpuinfo | head -n 1 | awk -F ': ' '{print $2}'
}

# 获取 CPU 核心数
get_cpu_cores() {
  nproc
}

# 获取 CPU 频率
get_cpu_freq() {
  grep 'cpu MHz' /proc/cpuinfo | head -n 1 | awk -F ': ' '{printf "%.1f", $2/1000}'
}

# 获取 CPU 占用率
get_cpu_usage() {
  top -bn1 | grep '%Cpu(s)' | awk '{print $2}'
}

# 获取系统负载
get_system_load() {
  uptime | awk -F 'load average: ' '{print $2}'
}

# 获取物理内存使用情况
get_physical_memory() {
  free -m | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3, $2, $3/$2*100}'
}

# 获取虚拟内存使用情况
get_swap_memory() {
  free -m | awk 'NR==3{printf "%dMB/%dMB (%.2f%%)", $3, $2, $3/$2*100}'
}

# 获取硬盘占用情况
get_disk_usage() {
  df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}'
}

# 获取网络流量统计
get_network_traffic() {
  awk 'BEGIN { rx_total = 0; tx_total = 0 }
    NR > 2 { rx_total += $2; tx_total += $10 }
    END {
      rx_units = "Bytes";
      tx_units = "Bytes";
      if (rx_total > 1024) { rx_total /= 1024; rx_units = "KB"; }
      if (rx_total > 1024) { rx_total /= 1024; rx_units = "MB"; }
      if (rx_total > 1024) { rx_total /= 1024; rx_units = "GB"; }

      if (tx_total > 1024) { tx_total /= 1024; tx_units = "KB"; }
      if (tx_total > 1024) { tx_total /= 1024; tx_units = "MB"; }
      if (tx_total > 1024) { tx_total /= 1024; tx_units = "GB"; }

      printf("总接收:       %.2f %s\n总发送:       %.2f %s\n", rx_total, rx_units, tx_total, tx_units);
    }' /proc/net/dev
}

# 获取网络算法
get_network_algorithm() {
  sysctl net.ipv4.tcp_congestion_control | awk '{print $3}'
}

# 获取运营商信息
get_isp() {
  curl -s ipinfo.io/org | awk -F' ' '{$1=""; print substr($0,2)}' | sed 's/ Co., Ltd./ Co. Ltd./g'
}

# 获取 IPv4 地址
get_ipv4_address() {
  curl -s ipv4.ip.sb
}

# 获取 DNS 地址
get_dns_address() {
  grep 'nameserver' /etc/resolv.conf | awk '{print $2}' | grep -v "^run$" | paste -sd " " -
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

# 获取系统时间
get_system_time() {
  local timezone=$(timedatectl | grep 'Time zone' | awk '{print $3}')
  local offset=$(timedatectl | grep 'Time zone' | awk '{print $5}')
  local current_time=$(date '+%Y-%m-%d %I:%M %p')
  echo "$timezone ($offset) | $current_time"
}

# 获取运行时长
get_uptime() {
  uptime -p | sed 's/up //g'
}

# 主函数
main() {
  clear
  
  # 预先收集所有信息
  local hostname=$(get_hostname)
  local os_version=$(get_os_version)
  local linux_version=$(get_linux_version)
  
  local cpu_arch=$(get_cpu_arch)
  local cpu_model=$(get_cpu_model)
  local cpu_cores=$(get_cpu_cores)
  local cpu_freq=$(get_cpu_freq)
  
  local cpu_usage=$(get_cpu_usage)
  local system_load=$(get_system_load)
  local physical_memory=$(get_physical_memory)
  local swap_memory=$(get_swap_memory)
  local disk_usage=$(get_disk_usage)
  
  local network_traffic=$(get_network_traffic)
  local network_algorithm=$(get_network_algorithm)
  
  local isp=$(get_isp)
  local ipv4=$(get_ipv4_address)
  local dns=$(get_dns_address)
  local geolocation=$(get_geolocation)
  local system_time=$(get_system_time)
  
  local uptime=$(get_uptime)

  # 一次性显示所有信息
  echo -e "${gl_lv}系统信息查询${gl_bai}"
  echo "-------------"
  echo -e "${gl_lan}基础系统信息${gl_bai}"
  echo -e "主机名:       $hostname"
  echo -e "系统版本:     $os_version"
  echo -e "Linux版本:    $linux_version"
  echo "-------------"
  echo -e "${gl_lan}CPU 信息${gl_bai}"
  echo -e "CPU架构:      $cpu_arch"
  echo -e "CPU型号:      $cpu_model"
  echo -e "CPU核心数:    $cpu_cores"
  echo -e "CPU频率:      $cpu_freq GHz"
  echo "-------------"
  echo -e "${gl_lan}系统资源使用${gl_bai}"
  echo -e "CPU占用:      $cpu_usage"
  echo -e "系统负载:     $system_load"
  echo -e "物理内存:     $physical_memory"
  echo -e "虚拟内存:     $swap_memory"
  echo -e "硬盘占用:     $disk_usage"
  echo "-------------"
  echo -e "${gl_lan}网络流量${gl_bai}"
  echo -e "$network_traffic"
  echo "-------------"
  echo -e "${gl_lan}网络信息${gl_bai}"
  echo -e "网络算法:     $network_algorithm"
  echo -e "运营商:       $isp"
  echo -e "IPv4地址:     $ipv4"
  echo -e "DNS地址:      $dns"
  echo -e "地理位置:     $geolocation"
  echo -e "系统时间:     $system_time"
  echo "-------------"
  echo -e "${gl_lan}运行状态${gl_bai}"
  echo -e "运行时长:     $uptime"
  echo ""
  echo -e "${gl_lv}操作完成${gl_bai}"
  echo "按任意键继续..."
  read -n 1 -s -r -p ""
  echo ""
  clear
}

main