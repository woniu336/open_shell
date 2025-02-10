#!/bin/bash

# 提示用户输入落地 IP
read -p "请输入落地 IP: " LANDING_IP

# 更新系统包列表并安装 Haproxy
echo "正在更新系统包列表并安装 Haproxy..."
sudo apt update
sudo apt install haproxy -y

# 备份 Haproxy 配置文件
echo "正在备份 Haproxy 配置文件..."
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

# 下载新的 Haproxy 配置文件
echo "正在下载新的 Haproxy 配置文件..."
sudo curl -sS -o /etc/haproxy/haproxy.cfg https://raw.githubusercontent.com/woniu336/open_shell/main/bt-cf/haproxy/haproxy.cfg

# 替换配置文件中的 IP 地址
echo "正在替换配置文件中的 IP 地址..."
sudo sed -i "s/8\.8\.8\.8/${LANDING_IP}/g" /etc/haproxy/haproxy.cfg

# 检测配置文件是否有效
echo "正在检测配置文件是否有效..."
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# 重启 Haproxy 服务
echo "正在重启 Haproxy 服务..."
sudo systemctl restart haproxy

echo "Haproxy 配置完成并已重启服务。"
sudo systemctl enable haproxy