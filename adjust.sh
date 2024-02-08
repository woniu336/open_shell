#!/bin/bash

# 设置 vm.swappiness 参数为 10
echo "Setting vm.swappiness to 10"
sudo sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf

# 设置 vm.dirty_ratio 参数为 10
echo "Setting vm.dirty_ratio to 10"
sudo sed -i 's/^vm.dirty_ratio=.*/vm.dirty_ratio=10/' /etc/sysctl.conf

# 设置 vm.dirty_background_ratio 参数为 5
echo "Setting vm.dirty_background_ratio to 5"
sudo sed -i 's/^vm.dirty_background_ratio=.*/vm.dirty_background_ratio=5/' /etc/sysctl.conf

# 设置 vm.dirty_expire_centisecs 参数为 500
echo "Setting vm.dirty_expire_centisecs to 500"
sudo sed -i 's/^vm.dirty_expire_centisecs=.*/vm.dirty_expire_centisecs=500/' /etc/sysctl.conf

# 设置 vm.vfs_cache_pressure 参数为 200
echo "Setting vm.vfs_cache_pressure to 200"
sudo sed -i 's/^vm.vfs_cache_pressure=.*/vm.vfs_cache_pressure=200/' /etc/sysctl.conf

# 重新加载 sysctl 配置文件以使更改生效
echo "Reloading sysctl configuration"
sudo sysctl -p

echo "Changes applied successfully."
