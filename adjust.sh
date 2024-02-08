#!/bin/bash

# 设置 vm.swappiness 参数为 10
echo "Setting vm.swappiness to 10"
sudo sed -i '/^vm.swappiness=/d' /etc/sysctl.conf
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.dirty_ratio 参数为 10
echo "Setting vm.dirty_ratio to 10"
sudo sed -i '/^vm.dirty_ratio=/d' /etc/sysctl.conf
echo "vm.dirty_ratio=10" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.dirty_background_ratio 参数为 5
echo "Setting vm.dirty_background_ratio to 5"
sudo sed -i '/^vm.dirty_background_ratio=/d' /etc/sysctl.conf
echo "vm.dirty_background_ratio=5" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.dirty_expire_centisecs 参数为 500
echo "Setting vm.dirty_expire_centisecs to 500"
sudo sed -i '/^vm.dirty_expire_centisecs=/d' /etc/sysctl.conf
echo "vm.dirty_expire_centisecs=500" | sudo tee -a /etc/sysctl.conf > /dev/null

# 设置 vm.vfs_cache_pressure 参数为 200
echo "Setting vm.vfs_cache_pressure to 200"
sudo sed -i '/^vm.vfs_cache_pressure=/d' /etc/sysctl.conf
echo "vm.vfs_cache_pressure=200" | sudo tee -a /etc/sysctl.conf > /dev/null

# 重新加载 sysctl 配置文件以使更改生效
echo "Reloading sysctl configuration"
sudo sysctl -p

echo "Changes applied successfully."
