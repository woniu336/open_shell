#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check and install rsync
if command_exists rsync; then
    echo -e "\033[96mrsync 已经安装\033[0m"
else
    echo -e "\033[33mrsync 正在安装中...\033[0m"
    sudo apt update
    sudo apt install -y rsync
fi

# Check and install rclone
if command_exists rclone; then
    echo -e "\033[96mrclone 已经安装\033[0m"
else
    echo -e "\033[33mrclone 正在安装中...\033[0m"
    sudo -v
    curl https://rclone.org/install.sh | sudo bash
fi

# Check and install lrzsz
if dpkg-query -W -f='${Status}' lrzsz 2>/dev/null | grep -q "installed"; then
    echo -e "\033[96mlrzsz 已经安装\033[0m"
else
    echo -e "\033[33mlrzsz 正在安装中...\033[0m"
    sudo apt install lrzsz -y >/dev/null 2>&1
fi




echo -e "\033[32m脚本执行完毕\033[0m"



