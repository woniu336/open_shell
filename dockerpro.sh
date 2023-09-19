#!/bin/bash

while true; do
    clear
    echo "欢迎使用 Docker 安装和卸载脚本菜单"
    echo "1. 第三方安装 Docker"
    echo "2. 官网安装 Docker "
    echo "3. 卸载 Docker 和清理"
    echo "0. 退出"
    read -p "请选择操作 (1/2/3/0): " choice

    case $choice in
        1)
            # 第三方安装 Docker
			clear
            bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/DockerInstallation.sh)
            ;;
		2)
            # 官网安装 Docker  
            clear			
            curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/docker.sh && chmod +x docker.sh && ./docker.sh

            ;;
        3)
            # 卸载 Docker 和清理
			clear
if [ -f /etc/redhat-release ]; then
    # CentOS 卸载 Docker
    sudo yum remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-selinux \
    docker-engine-selinux \
    docker-engine
elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
    # Debian / Ubuntu 卸载 Docker
    sudo apt-get remove -y docker docker-engine docker.io containerd runc
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io
else
    echo "不支持的操作系统。"
    exit 1
fi


            # 删除 Docker 数据目录
            sudo rm -rf /var/lib/docker
            sudo rm -rf /var/lib/containerd

            # 进一步清理残留
            sudo apt-get remove -y docker* containerd.io podman* runc && sudo apt-get autoremove -y

            echo "Docker 已成功卸载并清理。"
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效的选择，请重新选择。"
            ;;
    esac

    read -p "按 Enter 键继续..."
done
