#!/bin/bash

# 清除之前的设置
sudo sysctl -w vm.swappiness=0
sudo sysctl -w vm.dirty_ratio=0
sudo sysctl -w vm.dirty_background_ratio=0
sudo sysctl -w vm.dirty_expire_centisecs=0
sudo sysctl -w vm.vfs_cache_pressure=0

# 设置新的参数值
sudo sysctl -w vm.swappiness=10
sudo sysctl -w vm.dirty_ratio=10
sudo sysctl -w vm.dirty_background_ratio=5
sudo sysctl -w vm.dirty_expire_centisecs=500
sudo sysctl -w vm.vfs_cache_pressure=200

# 重新加载 sysctl 配置文件以使更改生效
echo "Reloading sysctl configuration"
sudo sysctl -p

echo "Changes applied successfully."
