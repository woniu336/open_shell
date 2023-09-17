#!/bin/bash

# 检查是否具有管理员权限
if [[ $EUID -ne 0 ]]; then
    echo "请以管理员权限运行此脚本。"
    exit 1
fi

# 提示用户输入新的SSH端口
read -p "请输入新的SSH端口号: " new_ssh_port

# 验证输入是否为整数
if ! [[ "$new_ssh_port" =~ ^[0-9]+$ ]]; then
    echo "输入的端口号无效，请输入一个有效的整数端口号。"
    exit 1
fi

# 修改SSH配置文件
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "s/^Port [0-9]*/Port $new_ssh_port/" /etc/ssh/sshd_config
else
    echo "SSH配置文件未找到，请手动修改SSH端口号。"
    exit 1
fi

# 重启SSH服务
if [ -f /etc/redhat-release ]; then
    # CentOS系统
    service sshd restart
elif [ -f /etc/lsb-release ]; then
    # Debian/Ubuntu系统
    service ssh restart
else
    echo "无法确定操作系统类型，请手动重启SSH服务以使更改生效。"
    exit 1
fi

echo "SSH端口已成功修改为 $new_ssh_port。"