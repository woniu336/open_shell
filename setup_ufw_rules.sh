#!/bin/bash

# 确保脚本以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本。"
  exit
fi

# 备份现有UFW规则
BACKUP_FILE="ufw_backup_$(date +%F_%T).txt"
sudo ufw status numbered > "$BACKUP_FILE"
echo "已备份当前UFW规则到 $BACKUP_FILE"

# 自动获取SSH端口
SSH_PORTS=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')

# 如果未找到自定义端口，则默认使用22
if [ -z "$SSH_PORTS" ]; then
  SSH_PORTS=22
fi

# 允许所有检测到的SSH端口
for PORT in $SSH_PORTS; do
  sudo ufw allow "$PORT/tcp"
  echo "已允许SSH端口: $PORT"
done

# 启用UFW（如果尚未启用）
sudo ufw --force enable

# 屏蔽 Censys 的 IPv4 段
CENSYS_IPV4=(
  "162.142.125.0/24"
  "167.94.138.0/24"
  "167.94.145.0/24"
  "167.94.146.0/24"
  "167.248.133.0/24"
  "199.45.154.0/24"
  "199.45.155.0/24"
  "206.168.34.0/24"
)

# 按逆序插入IPv4 DENY规则，确保顺序正确
for (( idx=${#CENSYS_IPV4[@]}-1 ; idx>=0 ; idx-- )) ; do
  CIDR=${CENSYS_IPV4[idx]}
  sudo ufw insert 1 deny from "$CIDR" to any
  echo "已插入规则: deny from $CIDR at position 1"
done

# 屏蔽单独的风险IP地址
RISK_IPS=(
  "94.154.33.153"
  "185.220.101.29"
  "138.197.191.87"
  "152.42.217.201"
  "149.88.106.138"
  "179.43.191.19"
  "146.190.111.4"
  "185.220.101.190"
  "192.42.116.178"
)

# 按逆序插入RISK IP DENY规则
for (( idx=${#RISK_IPS[@]}-1 ; idx>=0 ; idx-- )) ; do
  IP=${RISK_IPS[idx]}
  sudo ufw insert 1 deny from "$IP" to any
  echo "已插入规则: deny from $IP at position 1"
done

# 屏蔽IP范围
IP_RANGES=(
  "20.171.206.0/24"
  "52.230.152.0/24"
  "52.233.106.0/24"
  "152.32.128.0/17"
  "103.218.243.0/24"
)

# 按逆序插入IP范围DENY规则
for (( idx=${#IP_RANGES[@]}-1 ; idx>=0 ; idx-- )) ; do
  RANGE=${IP_RANGES[idx]}
  sudo ufw insert 1 deny from "$RANGE" to any
  echo "已插入规则: deny from $RANGE at position 1"
done

# 确定IPv6规则的插入位置
# 查找第一个包含(v6)的规则位置
FIRST_V6_RULE=$(sudo ufw status numbered | grep '(v6)' | head -n1 | awk -F'[][]' '{print $2}')

# 如果未找到v6规则，则设置为当前规则总数加1
if [ -z "$FIRST_V6_RULE" ]; then
  TOTAL_RULES=$(sudo ufw status numbered | grep -c '^\[')
  FIRST_V6_RULE=$((TOTAL_RULES + 1))
fi

echo "IPv6规则将从位置 $FIRST_V6_RULE 插入"

# 屏蔽 Censys 的 IPv6 段
CENSYS_IPV6=(
  "2602:80d:1000:b0cc:e::/80"
  "2620:96:e000:b0cc:e::/80"
  "2602:80d:1003::/112"
  "2602:80d:1004::/112"
)

# 插入IPv6 DENY规则，顺序插入确保顺序正确
CURRENT_POSITION=$FIRST_V6_RULE
for CIDR in "${CENSYS_IPV6[@]}"; do
  sudo ufw insert "$CURRENT_POSITION" deny from "$CIDR" to any
  echo "已插入IPv6规则: deny from $CIDR at position $CURRENT_POSITION"
  CURRENT_POSITION=$((CURRENT_POSITION + 1))
done

# 重新加载UFW以应用规则
sudo ufw reload

echo "UFW规则已成功更新。"