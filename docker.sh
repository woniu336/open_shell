#!/bin/bash

# 检查是否已经安装 Docker
if command -v docker &>/dev/null; then
    echo "Docker 已经安装。"
else
    # 安装 Docker
    curl -fsSL https://get.docker.com | sh
    echo "Docker 安装完成。"
fi

# 检查是否已经安装 Docker Compose
if command -v docker-compose &>/dev/null; then
    echo "Docker Compose 已经安装。"
else
    # 安装 Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose 安装完成。"
fi

# 显示 Docker 和 Docker Compose 版本
docker --version
docker-compose --version
