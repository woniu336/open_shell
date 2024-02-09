#!/bin/bash

# 设置 vm.swappiness 参数为 10
echo "Setting vm.swappiness to 10"
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.dirty_ratio 参数为 10
echo "Setting vm.dirty_ratio to 10"
echo "vm.dirty_ratio=10" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.dirty_background_ratio 参数为 5
echo "Setting vm.dirty_background_ratio to 5"
echo "vm.dirty_background_ratio=5" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.dirty_expire_centisecs 参数为 500
echo "Setting vm.dirty_expire_centisecs to 500"
echo "vm.dirty_expire_centisecs=500" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.vfs_cache_pressure 参数为 500
echo "Setting vm.vfs_cache_pressure to 500"
echo "vm.vfs_cache_pressure=500" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置网络参数
echo "Setting network parameters"
echo "net.core.rmem_max=16777216" | sudo tee -a /etc/sysctl.conf > /dev/null
echo "net.core.wmem_max=16777216" | sudo tee -a /etc/sysctl.conf > /dev/null
echo "net.ipv4.tcp_rmem=4096 212992 16777216" | sudo tee -a /etc/sysctl.conf > /dev/null
echo "net.ipv4.tcp_wmem=4096 212992 16777216" | sudo tee -a /etc/sysctl.conf > /dev/null

# 重新加载 sysctl 配置文件以使更改生效
echo "Reloading sysctl configuration"
sudo sysctl -p

echo "Changes applied successfully."
