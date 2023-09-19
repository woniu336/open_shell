#!/bin/bash

while true; do
    clear
    echo "请选择操作:"
    echo "1) 谷歌云一键重装"
	echo "2) Linux开源面板"
    echo "0) 返回上一层"
    read -p "请输入操作编号: " choice

    case $choice in


        2)
		  # Linux开源面板
		  
		  curl -fsSL https://cdn.jsdelivr.net/gh/midoks/mdserver-web@latest/scripts/install.sh | bash
		  ;;


        1)
            # 谷歌云一键重装
            # 提示用户输入谷歌云服务器内网IP
            read -p "请输入谷歌云服务器内网IP地址（例如10.146.0.3）: " google_cloud_ip

            # 提取IP地址的前三位数字
            ip_prefix=$(echo "$google_cloud_ip" | cut -d '.' -f 1-3)

            # 自动计算网关，将第四位数字设置为1
            google_cloud_gateway="$ip_prefix.1"

            # 提示用户确认信息并继续
            echo "您输入的信息如下："
            echo "内网IP地址: $google_cloud_ip"
            echo "自动计算的网关: $google_cloud_gateway"
            echo "密码: 123456"
            echo "SSH端口: 22"
            echo "重装版本: Ubuntu 20.04"
            echo "提醒: 仅在谷歌云(debian11)测试有效"
            read -p "是否要继续执行一键安装操作？(y/n): " confirm

# 在执行一键安装操作之前添加以下代码
if [ "$confirm" == "y" ]; then
    # 防止报错: Error! grub.cfg
    mkdir /boot/grub2 && grub-mkconfig -o /boot/grub2/grub.cfg

    # 更新系统并安装必要的软件
    apt update -y
    apt install -y wget sudo

    # 执行一键安装操作
    bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') --ip-addr $google_cloud_ip --ip-gate $google_cloud_gateway --ip-mask 255.255.255.0 -u 20.04 -v 64 -p 123456 -port 22
else
    echo "已取消操作。"
fi
            ;;
        0)
            # 返回上一层
            break
            ;;
        *)
            echo "无效的操作编号，请重新输入。"
            ;;
    esac

    read -p "按Enter键继续..."
done
