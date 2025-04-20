#!/bin/bash

# 颜色定义
GREEN='\e[32m'
NC='\e[0m' # 重置颜色

# 检查是否为 root 用户
if [ $(id -u) -ne 0 ]; then
    echo -e "${GREEN}请使用 sudo 执行该脚本！${NC}"
    exit 1
fi

# 更新系统源并升级
echo -e "${GREEN}更新系统源并升级...${NC}"
apt update && apt upgrade -y

# 安装所需软件包
echo -e "${GREEN}安装软件包...${NC}"
apt install -y unzip curl wget sudo fail2ban rsyslog systemd-timesyncd ufw htop

# 修改 hostname
echo -e "${GREEN}是否修改 hostname？(y/N)${NC}"
read -p "请输入 y 继续，否则默认不修改: " modify_hostname
if [[ "$modify_hostname" =~ ^[Yy]$ ]]; then
    read -p "请输入新的 hostname: " new_hostname
    if [ -n "$new_hostname" ]; then
        hostnamectl set-hostname "$new_hostname"
        if ! grep -q "$new_hostname" /etc/hosts; then
            sed -i "1s/127.0.0.1\tlocalhost/127.0.0.1\tlocalhost/" /etc/hosts
            sed -i "2i127.0.1.1\t$new_hostname" /etc/hosts
        fi
    fi
fi

# 修改 SSH 端口
echo -e "${GREEN}修改 SSH 端口...${NC}"
read -p "请输入新的 SSH 端口（默认 22）: " ssh_port
if [ -z "$ssh_port" ]; then
    ssh_port=22
fi

# 修改 SSH 配置
sed -i "s/^#\?Port .*/Port $ssh_port/" /etc/ssh/sshd_config
sed -i "s/^#\?X11Forwarding .*/X11Forwarding no/" /etc/ssh/sshd_config
systemctl restart sshd

# 配置 fail2ban
echo -e "${GREEN}配置 fail2ban...${NC}"
tee /etc/fail2ban/jail.local > /dev/null << EOF
[sshd]
ignoreip = 127.0.0.1/8
enabled = true
filter = sshd
port = $ssh_port
maxretry = 3
findtime = 300
bantime = -1
banaction = ufw
logpath = /var/log/auth.log
EOF

# 配置 ufw
echo -e "${GREEN}配置 ufw...${NC}"
ufw allow "$ssh_port"

# 修改 DNS 配置
echo -e "${GREEN}是否修改 DNS 配置？(y/N)${NC}"
read -p "请输入 y 继续，否则默认不修改: " modify_dns
if [[ "$modify_dns" =~ ^[Yy]$ ]]; then
    read -p "请输入新的 DNS 服务器（多个用空格分隔）: " dns_servers
    if [ -n "$dns_servers" ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak
        chattr -i /etc/resolv.conf
        > /etc/resolv.conf
        for dns in $dns_servers; do
            echo "nameserver $dns" >> /etc/resolv.conf
        done
        chattr +i /etc/resolv.conf
    fi
fi

# 启动服务
echo -e "${GREEN}启动服务...${NC}"
systemctl restart fail2ban
systemctl enable fail2ban
systemctl start systemd-timesyncd
systemctl enable systemd-timesyncd

# 启用 ufw
echo -e "${GREEN}启用 ufw...${NC}"
ufw enable

# 交互式确认是否修改 Swap
echo -e "${GREEN}是否修改 Swap 设置？(y/N)${NC}"
read -p "请输入 y 继续，否则默认不修改: " modify_swap
if [[ "$modify_swap" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}请输入 Swap 大小 (单位 MB): ${NC}"
    read SWAP_SIZE
    if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
        echo -e "${GREEN}无效输入，请输入一个正整数。${NC}"
        exit 1
    fi
    echo -e "${GREEN}请输入 Swappiness 值 (1-100, 默认 60): ${NC}"
    read SWAPPINESS
    SWAPPINESS=${SWAPPINESS:-60}
    if ! [[ "$SWAPPINESS" =~ ^[0-9]+$ ]] || [ "$SWAPPINESS" -lt 1 ] || [ "$SWAPPINESS" -gt 100 ]; then
        echo -e "${GREEN}无效输入，请输入 1 到 100 之间的整数。${NC}"
        exit 1
    fi
    EXISTING_SWAP=$(swapon --show=NAME --noheadings)
    if [ -n "$EXISTING_SWAP" ]; then
        swapoff "$EXISTING_SWAP"
        rm -f "$EXISTING_SWAP"
        sed -i "\|$EXISTING_SWAP|d" /etc/fstab
    fi
    echo -e "${GREEN}请输入新的 Swap 文件路径 (默认: /swapfile): ${NC}"
    read SWAP_FILE
    SWAP_FILE=${SWAP_FILE:-/swapfile}
    fallocate -l ${SWAP_SIZE}M "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$SWAP_SIZE
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    fi
    if grep -q "vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness=.*/vm.swappiness=$SWAPPINESS/" /etc/sysctl.conf
    else
        echo "vm.swappiness=$SWAPPINESS" >> /etc/sysctl.conf
    fi
    sysctl -p
    swapon --show
fi

echo -e "${GREEN}配置完成！${NC}"
