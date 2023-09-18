#!/bin/bash

# 执行一键开启BBR脚本操作
while true; do
    clear
    echo "请选择要执行的BBR脚本："
    echo "1. 安装原版bbr"
    echo "2. 安装魔改bbr"
    echo "0. 退出"
    read -p "请输入脚本编号: " bbr_choice

    if [ "$bbr_choice" == "1" ]; then
        echo "net.core.default_qdisc=fq"  >>  /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr"  >>  /etc/sysctl.conf
        sysctl -p
        lsmod | grep bbr
    elif [ "$bbr_choice" == "2" ]; then
        wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
    elif [ "$bbr_choice" == "0" ]; then
        echo "退出脚本。"
        exit 0
    else
        echo "无效的脚本选择。"
    fi

    read -p "按 Enter 键继续..."
done
