#!/bin/bash

# 检查当前用户是否具有足够的权限
if [ "$EUID" -ne 0 ]; then
  echo "请以管理员身份运行此脚本。"
  exit 1
fi

# 添加参数到 /etc/sysctl.conf
echo "vm.swappiness=1" >> /etc/sysctl.conf

# 应用新的设置
sysctl -p

# 提示用户重启系统
echo "已经成功添加参数到 /etc/sysctl.conf。为了使更改生效，请重启系统。"
