#!/bin/bash

while true; do
    echo "请选择要执行的操作:"
    echo "1) 更新系统组件"
    echo "2) 查看系统现有内核"
    echo "3) 更改时区为中国上海"
    echo "4) 优化DNS地址"
    echo "5) 修改SSH端口"
    echo "0) 退出"

    read -p "输入选项的数字: " option

    case $option in
        1)
            # 更新系统组件
            clear
            if [[ -f /etc/redhat-release ]]; then
                sudo yum update -y && sudo yum install -y wget curl socat sudo vim git
            elif [[ -f /etc/lsb-release ]]; then
                sudo apt update -y && sudo apt upgrade -y && sudo apt install -y wget curl socat sudo vim git
            else
                echo "未知的系统类型，无法执行更新操作。"
            fi
            ;;
        2)
            # 查看系统现有内核
            clear
            dpkg -l | grep linux-image
            ;;
3)
    # 更改时区为中国上海
    clear
    sudo timedatectl set-timezone Asia/Shanghai && sudo hwclock --systohc
    echo "已更改为中国时区"
    echo "当前日期和时间为：$(date)"
    ;;


        4)
            # 优化DNS地址
            clear
            clear
            echo "当前DNS地址"
            echo "------------------------"
            cat /etc/resolv.conf
            echo "------------------------"
            echo ""
            # 询问用户是否要优化DNS设置
            read -p "是否要设置为Cloudflare和Google的DNS地址？(y/n): " choice

            if [ "$choice" == "y" ]; then
                # 定义DNS地址
                cloudflare_ipv4="1.1.1.1"
                google_ipv4="8.8.8.8"
                cloudflare_ipv6="2606:4700:4700::1111"
                google_ipv6="2001:4860:4860::8888"

                # 检查机器是否有IPv6地址
                ipv6_available=0
                if [[ $(ip -6 addr | grep -c "inet6") -gt 0 ]]; then
                    ipv6_available=1
                fi

                # 设置DNS地址为Cloudflare和Google（IPv4和IPv6）
                echo "设置DNS为Cloudflare和Google"

                # 设置IPv4地址
                echo "nameserver $cloudflare_ipv4" > /etc/resolv.conf
                echo "nameserver $google_ipv4" >> /etc/resolv.conf

                # 如果有IPv6地址，则设置IPv6地址
                if [[ $ipv6_available -eq 1 ]]; then
                    echo "nameserver $cloudflare_ipv6" >> /etc/resolv.conf
                    echo "nameserver $google_ipv6" >> /etc/resolv.conf
                fi

                echo "DNS地址已更新"
                echo "------------------------"
                cat /etc/resolv.conf
                echo "------------------------"
            else
                echo "DNS设置未更改"
            fi
            ;;
        5)
            # 修改SSH端口
            clear
            curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/change_ssh_port.sh && chmod +x change_ssh_port.sh && ./change_ssh_port.sh
            ;;
        0)
            # 退出脚本
            exit 0
            ;;
        *)
            echo "无效的选项，请选择0到5之间的数字。"
            ;;
    esac
done
