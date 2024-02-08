#!/bin/bash

# 定义参数数组
declare -a parameters=(
    "vm.swappiness=10"
    "vm.dirty_ratio=10"
    "vm.dirty_background_ratio=5"
    "vm.dirty_expire_centisecs=500"
    "vm.vfs_cache_pressure=200"
)

# 检查每个参数是否已存在，如果不存在则应用新参数
for param in "${parameters[@]}"; do
    current_setting=$(sudo sysctl -n "$param" 2>/dev/null)
    if [[ -z "$current_setting" ]]; then
        echo "Setting $param"
        sudo sysctl -w "$param"
    else
        echo "Skipping $param as it is already set to $current_setting"
    fi
done

# 重新加载 sysctl 配置文件以使更改生效
echo "Reloading sysctl configuration"
sudo sysctl -p

echo "Changes applied successfully."
