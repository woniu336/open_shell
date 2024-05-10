#!/bin/bash

# 更新软件源并安装所需软件包
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release sudo

# 添加 Docker GPG 密钥
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 添加 Docker 软件源
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新软件包列表并安装 Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# 启动并启用 Docker 服务
systemctl start docker
systemctl enable docker

# 创建 Docker 用户组并添加当前用户
groupadd docker
usermod -aG docker $USER

# 创建 Docker 配置目录并添加镜像加速器
mkdir -p /etc/docker
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://oyac73nr.mirror.aliyuncs.com"]
}
EOF

# 重载并重启 Docker 服务
systemctl daemon-reload
systemctl restart docker
