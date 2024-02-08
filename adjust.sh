#!/bin/bash

# 设置 vm.swappiness 参数为 10
echo "Setting vm.swappiness to 10"
sudo sysctl -w vm.swappiness=10

# 设置 vm.dirty_ratio 参数为 10
echo "Setting vm.dirty_ratio to 10"
sudo sysctl -w vm.dirty_ratio=10

# 设置 vm.dirty_background_ratio 参数为 5
echo "Setting vm.dirty_background_ratio to 5"
sudo sysctl -w vm.dirty_background_ratio=5

# 设置 vm.dirty_expire_centisecs 参数为 500
echo "Setting vm.dirty_expire_centisecs to 500"
sudo sysctl -w vm.dirty_expire_centisecs=500

# 设置 vm.vfs_cache_pressure 参数为 200
echo "Setting vm.vfs_cache_pressure to 200"
sudo sysctl -w vm.vfs_cache_pressure=200

echo "Changes applied successfully."