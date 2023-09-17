#!/bin/bash

# 检查操作系统类型
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
elif [ -f /etc/lsb-release ]; then
    # Debian / Ubuntu 卸载 Docker
    sudo apt-get remove -y docker docker-engine docker.io containerd runc
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io
else
    # 其他方式卸载 Docker
    echo "Unsupported operating system."
    exit 1
fi

# 删除 Docker 数据目录
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

# 进一步清理残留
sudo apt-get remove -y docker* containerd.io podman* runc && sudo apt-get autoremove -y


echo "Docker 已成功卸载。"
