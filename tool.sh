#!/bin/bash

# 显示菜单选项
echo "请选择要执行的操作："
echo "1. rclone工具箱"
echo "2. 安装纯净宝塔面板"
echo "3. 科技lion一键脚本工具"
echo "4. 证书SSL申请"
echo "5. docker安装卸载"
echo "6. docker软件应用"
echo "7. 测试脚本合集"
echo "8. 系统工具"
echo "9. 其他工具"
echo "10. 一键开启BBR"
echo "11. 一键重装系统(DD)"
echo "12. 设置脚本快捷键"
echo "0. 退出"

# 提示用户选择操作
read -p "请输入操作编号: " choice

# 执行用户选择的操作
case $choice in

	    1)
        # rclone工具箱
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/rclone.sh && chmod +x rclone.sh && ./rclone.sh
        ;;
	    2)
        # 安装纯净宝塔面板
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/bt.sh && chmod +x bt.sh && ./bt.sh
        ;;
	    3)
        # 科技lion一键脚本工具
		clear
        curl -sS -O https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh && chmod +x kejilion.sh && ./kejilion.sh
        ;;
		4)
        # 证书SSL申请
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/ssl.sh && chmod +x ssl.sh && ./ssl.sh
        ;;
	    5)
        # docker安装卸载
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/dockerpro.sh && chmod +x dockerpro.sh && ./dockerpro.sh
        ;;
	    6)
        # docker软件应用      
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/docker666.sh && chmod +x docker666.sh && ./docker666.sh
        ;;
	    7)
        # 测试脚本合集    
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/vps.sh && chmod +x vps.sh && ./vps.sh
        ;;
		8)
        # 系统工具    
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/xitong.sh && chmod +x xitong.sh && ./xitong.sh
        ;;
		9)
        # 其他工具   
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/soso.sh && chmod +x soso.sh && ./soso.sh
        ;;
        10)
        # 执行一键开启BBR脚本操作
		clear
        echo "请选择要执行的BBR脚本："
        echo "1. 脚本1"
        echo "2. 脚本2"
        read -p "请输入脚本编号: " bbr_choice
        if [ "$bbr_choice" == "1" ]; then
            echo "net.core.default_qdisc=fq"  >>  /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr"  >>  /etc/sysctl.conf
            sysctl -p
            lsmod | grep bbr
        elif [ "$bbr_choice" == "2" ]; then
            wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
        else
            echo "无效的脚本选择。"
        fi
        ;;
        11)
        # 执行一键重装系统(DD)操作
		clear
        echo "请选择要执行的系统重装脚本："
        echo "1. 脚本1"
        echo "2. 脚本2"
        echo "3. 脚本3"
        read -p "请输入脚本编号: " reinstall_choice
        if [ "$reinstall_choice" == "1" ]; then
            wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
            echo "请选择要重装的系统："
            echo "a. Debian 11"
            echo "b. Ubuntu 20.04"
            echo "c. CentOS 7"
            read -p "请输入系统编号: " os_choice
            if [ "$os_choice" == "a" ]; then
                # 提示用户名、密码和SSH端口
                echo "您选择了执行 Debian 11 重装操作。"
                echo "用户名: root"
                echo "密码: LeitboGi0ro"
                echo "SSH端口: 22"
                read -p "是否确定要继续执行？(y/n): " confirm
                if [ "$confirm" == "y" ]; then
                    bash InstallNET.sh -debian 11
                else
                    echo "已取消操作。"
                fi
            elif [ "$os_choice" == "b" ]; then
                # 提示用户名、密码和SSH端口
                echo "您选择了执行 Ubuntu 20.04 重装操作。"
                echo "用户名: root"
                echo "密码: LeitboGi0ro"
                echo "SSH端口: 22"
                read -p "是否确定要继续执行？(y/n): " confirm
                if [ "$confirm" == "y" ]; then
                    bash InstallNET.sh -ubuntu 20.04
                else
                    echo "已取消操作。"
                fi
            elif [ "$os_choice" == "c" ]; then
                # 提示用户名、密码和SSH端口
                echo "您选择了执行 CentOS 7 重装操作。"
                echo "用户名: root"
                echo "密码: LeitboGi0ro"
                echo "SSH端口: 22"
                read -p "是否确定要继续执行？(y/n): " confirm
                if [ "$confirm" == "y" ]; then
                    bash InstallNET.sh -centos 7
                else
                    echo "已取消操作。"
                fi
            else
                echo "无效的系统选择。"
            fi
elif [ "$reinstall_choice" == "2" ]; then
            # 提示用户选择系统
            echo "请选择要执行的系统重装脚本："
            echo "a. Debian 11"
            echo "b. Ubuntu 20.04"
            read -p "请输入系统编号: " os_choice
            if [ "$os_choice" == "a" ]; then
                # 提示用户名、密码和SSH端口
                echo "您选择了执行 Debian 11 重装操作。"
                echo "用户名: root"
                echo "密码: 123456"
                echo "SSH端口: 22"
                read -p "是否确定要继续执行？(y/n): " confirm
                if [ "$confirm" == "y" ]; then
                    bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') -d 11 -v 64 -p 123456 -port 22
                else
                    echo "已取消操作。"
                fi
            elif [ "$os_choice" == "b" ]; then
                # 提示用户名、密码和SSH端口
                echo "您选择了执行 Ubuntu 20.04 重装操作。"
                echo "用户名: root"
                echo "密码: 123456"
                echo "SSH端口: 22"
                read -p "是否确定要继续执行？(y/n): " confirm
                if [ "$confirm" == "y" ]; then
                    bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') -u 20.04 -v 64 -p 123456 -port 22
                else
                    echo "已取消操作。"
                fi
            else
                echo "无效的系统选择。"
            fi
        elif [ "$reinstall_choice" == "3" ]; then
            # 提示默认密码
            echo "正在执行脚本3的操作..."
            echo "默认密码: Pwd@CentOS 或 Pwd@Linux"
            wget --no-check-certificate -O AutoReinstall.sh https://git.io/AutoReinstall.sh && bash AutoReinstall.sh
        else
            echo "无效的脚本选择。"
        fi
        ;;
	    12)
		# 设置脚本快捷键
        clear
        read -p "请输入你的快捷按键: " kuaijiejian
        echo "alias $kuaijiejian='curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/tool.sh && chmod +x tool.sh && ./tool.sh'" >> ~/.bashrc
        echo "快捷键已添加。请重新启动终端，或运行 'source ~/.bashrc' 以使修改生效。"
        ;;
    0)
        # 退出
        echo "退出脚本。"
        exit 0
        ;;
    *)
        echo "无效的操作选择。"
        ;;
esac