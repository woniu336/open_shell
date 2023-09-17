#!/bin/bash

# 显示菜单选项
echo "请选择要执行的操作："
echo "1. rclone工具箱"
echo "2. 安装纯净宝塔面板"
echo "3. 科技lion一键脚本工具"
echo "4. docker工具软件"
echo "5. 谷歌云一键重装"
echo "6. 安装docker"
echo "7. 卸载docker"
echo "8. 解锁状态查看"
echo "9. 流媒体解锁测试脚本"
echo "10. 解锁tiktok状态"
echo "11. 三网回程测试脚本"
echo "12. 三网测速脚本"
echo "13. 三网回程延迟测试脚本"
echo "14. 一键开启BBR"
echo "15. 一键重装系统(DD)"
echo "16. VPS系统信息"
echo "17. 测试CPU性能"
echo "18. 修改SSH端口"
echo "19. 更改时区为中国"
echo "20. 优化DNS地址"
echo "21. 磁盘真实性能读写测试"
echo "22. 更新组件"
echo "23. 升级packages"
echo "24. 查看系统现有内核"
echo "25. 退出"

# 提示用户选择操作
read -p "请输入操作编号: " choice

# 执行用户选择的操作
case $choice in
    17)
        # 执行测试CPU性能操作
        apt update -y && apt install -y curl wget sudo
        curl -sL yabs.sh | bash -s -- -i -5
        ;;
    16)
        # 执行VPS检测操作
        echo "请选择要执行的VPS检测脚本："
        echo "1. 脚本1"
        echo "2. 脚本2"
        read -p "请输入脚本编号: " vps_choice
        if [ "$vps_choice" == "1" ]; then
            wget -q https://github.com/Aniverse/A/raw/i/a && bash a
        elif [ "$vps_choice" == "2" ]; then
            wget -qO- bench.sh | bash
        else
            echo "无效的脚本选择。"
        fi
        ;;
    21)
        # 执行磁盘真实性能读写测试操作
        echo "开始进行磁盘真实性能读写测试..."
        dd bs=64k count=4k if=/dev/zero of=/tmp/test oflag=dsync
        echo "测试完成。"
        ;;
    12)
        # 执行三网测速脚本操作
        bash <(curl -Lso- https://git.io/superspeed_uxh)
        ;;
    11)
        # 执行三网回程测试脚本操作
        echo "请选择要执行的三网回程测试脚本："
        echo "1. 脚本1"
        echo "2. 脚本2"
        read -p "请输入脚本编号: " mtr_choice
        if [ "$mtr_choice" == "1" ]; then
            curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh|bash
        elif [ "$mtr_choice" == "2" ]; then
            curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh
        else
            echo "无效的脚本选择。"
        fi
        ;;
    13)
        # 执行三网回程延迟测试脚本操作
        wget -qO- git.io/besttrace | bash
        ;;
    8)
        # 执行解锁状态查看操作
        bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh)
        ;;
    9)
        # 执行流媒体解锁测试脚本操作
        bash <(curl -L -s check.unlock.media)
        ;;
    10)
        # 执行解锁tiktok状态操作
        wget -qO- https://github.com/yeahwu/check/raw/main/check.sh | bash
        ;;
    14)
        # 执行一键开启BBR脚本操作
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
    15)
        # 执行一键重装系统(DD)操作
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
    22)
        # 执行更新组件操作
        apt update -y && apt install -y curl && apt install -y socat && apt install wget -y
        ;;
    23)
        # 执行升级packages操作
        sudo bash -c "apt update -y && apt install wget curl sudo vim git -y"
        ;;
    24)
        # 查看系统现有内核
        dpkg  -l|grep linux-image
        ;;
    5)
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

if [ "$confirm" == "y" ]; then
    # 更新系统并安装必要的软件
    apt update -y
    apt install -y wget sudo

    # 执行一键安装操作
    bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') --ip-addr $google_cloud_ip --ip-gate $google_cloud_gateway --ip-mask 255.255.255.0 -u 20.04 -v 64 -p 123456 -port 22
else
    echo "已取消操作。"
fi
;;
        1)
        # rclone工具箱
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/rclone.sh && chmod +x rclone.sh && ./rclone.sh
        ;;
	    2)
        # 安装宝塔面板
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/bt.sh && chmod +x bt.sh && ./bt.sh
        ;;
	    6)
        # 安装docker
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/docker.sh && chmod +x docker.sh && ./docker.sh
        ;;
		7)
        # 卸载docker
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/uninstall_docker.sh && chmod +x uninstall_docker.sh && ./uninstall_docker.sh
        ;;
	    18)
        # 修改SSH端口
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/change_ssh_port.sh && chmod +x change_ssh_port.sh && ./change_ssh_port.sh
        ;;
	    3)
        # 科技lion一键脚本工具      
        curl -sS -O https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh && chmod +x kejilion.sh && ./kejilion.sh
        ;;
	    4)
        # docker工具软件     
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/docker666.sh && chmod +x docker666.sh && ./docker666.sh
        ;;
		19)
        # 更改时区为中国    
        timedatectl set-timezone Asia/Shanghai && hwclock --systohc
        ;;
		20)
        # 优化DNS地址    
        echo -e "options timeout:1 attempts:1 rotate\nnameserver 1.1.1.1\nnameserver 8.8.8.8" >/etc/resolv.conf;
        ;;
    25)
        # 退出
        echo "退出脚本。"
        exit 0
        ;;
    *)
        echo "无效的操作选择。"
        ;;
esac