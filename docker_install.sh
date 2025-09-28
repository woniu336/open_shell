#!/usr/bin/env bash
set -e

# 判断是否在国内环境（通过 ping docker hub）
is_china() {
    if ping -c 1 -W 1 registry-1.docker.io >/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

# 检查系统类型
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo "无法检测系统版本"
        exit 1
    fi
}

# 更新 apt 源（国内环境）
use_china_mirrors() {
    echo "检测到国内环境，使用国内 apt 源..."
    if [[ $OS == "ubuntu" ]]; then
        sed -i 's|http://.*.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
        sed -i 's|http://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
    elif [[ $OS == "debian" ]]; then
        sed -i 's|http://deb.debian.org|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
        sed -i 's|http://security.debian.org|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
    fi
}

# 配置国内镜像加速
setup_china_mirror() {
    echo "配置 Docker 国内镜像加速..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://hub-mirror.c.163.com",
    "https://mirror.iscas.ac.cn",
    "https://ccr.ccs.tencentyun.com"
  ]
}
EOF
    systemctl daemon-reexec
    systemctl restart docker
}

# 安装 docker
install_docker() {
    echo "更新 apt 包索引..."
    apt-get update -y

    echo "安装必要依赖..."
    apt-get install -y ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings

    if is_china; then
        echo "检测到国内环境，使用阿里云 Docker CE 源..."
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | gpg --dearmor --yes --batch -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        echo "使用官方 Docker CE 源..."
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor --yes --batch -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    echo "更新 apt 包索引..."
    apt-get update -y

    echo "安装 Docker..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    if is_china; then
        setup_china_mirror
    fi

    systemctl enable docker --now

    echo
    echo "✅ Docker 安装完成!"
    docker --version
    docker compose version
}

main() {
    check_os
    if is_china; then
        use_china_mirrors
    fi
    install_docker
}

main "$@"
