#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 输出信息函数
log_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

log_prompt() {
    echo -e "${BLUE}[PROMPT] $1${NC}"
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    log_error "请使用root用户运行此脚本"
    exit 1
fi

# 卸载lssh
uninstall_lssh() {
    log_info "正在卸载lssh..."
    
    # 删除二进制文件
    rm -f /usr/local/bin/lssh
    rm -f /usr/local/bin/lscp
    rm -f /usr/local/bin/lsftp
    
    # 删除源码目录
    rm -rf ~/lssh
    
    # 询问是否删除配置文件
    read -p "是否删除配置文件 ~/.lssh.conf? (y/n): " del_conf
    if [ "$del_conf" = "y" ]; then
        rm -f ~/.lssh.conf
        log_info "配置文件已删除"
    fi
    
    log_info "lssh卸载完成"
}

# 生成SSH密钥
generate_ssh_key() {
    log_info "开始生成SSH密钥..."
    
    # 直接使用ED25519生成密钥
    ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -N ""
    
    # 读取公钥内容，去除主机名部分
    PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub | cut -d' ' -f1,2)
    
    # 显示公钥内容
    log_info "密钥生成完成！"
    log_prompt "这是您的公钥内容，请复制到目标服务器的 ~/.ssh/authorized_keys 文件中："
    echo "-------------------"
    echo "$PUBLIC_KEY"
    echo "-------------------"
    log_prompt "在目标服务器上执行以下命令："
    echo "mkdir -p ~/.ssh"
    echo "chmod 700 ~/.ssh"
    echo "echo '$PUBLIC_KEY' >> ~/.ssh/authorized_keys"
    echo "chmod 600 ~/.ssh/authorized_keys"
}

# 编辑配置文件
edit_config() {
    if [ ! -f ~/.lssh.conf ]; then
        log_error "配置文件不存在，请先安装lssh"
        return 1
    fi
    
    # 使用默认编辑器打开配置文件
    if [ -n "$EDITOR" ]; then
        $EDITOR ~/.lssh.conf
    else
        nano ~/.lssh.conf
    fi
}

# 安装基础依赖
install_dependencies() {
    log_info "正在安装基础依赖..."
    apt update
    apt install -y wget git make build-essential nano
}

# 安装Go
install_golang() {
    log_info "正在安装Go..."
    wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz
    rm go1.22.2.linux-amd64.tar.gz

    # 配置Go环境变量
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    source /etc/profile

    # 验证Go安装
    if ! command -v go &> /dev/null; then
        log_error "Go安装失败"
        return 1
    fi
    log_info "Go安装成功: $(go version)"
}

# 安装lssh
install_lssh() {
    log_info "正在安装lssh..."
    
    # 清理旧目录
    rm -rf ~/lssh
    
    # 克隆仓库
    git clone https://github.com/blacknon/lssh
    cd lssh

    # 设置Go环境变量
    export GO111MODULE=on
    export GOPROXY=https://goproxy.cn,direct

    # 初始化Go模块
    go mod init github.com/blacknon/lssh
    go mod tidy

    # 编译
    log_info "正在编译lssh..."
    go build -v ./cmd/lssh
    go build -v ./cmd/lscp
    go build -v ./cmd/lsftp

    # 安装
    install -m 755 lssh /usr/local/bin/
    install -m 755 lscp /usr/local/bin/
    install -m 755 lsftp /usr/local/bin/

    # 创建配置文件
    if [ ! -f ~/.lssh.conf ]; then
        cp example/config.tml ~/.lssh.conf
    fi

    # 验证安装
    if ! command -v lssh &> /dev/null; then
        log_error "lssh安装失败"
        return 1
    fi
    
    log_info "lssh安装成功: $(lssh -v)"
}

# 显示菜单
show_menu() {
    clear
    echo "================================"
    echo "     LSSH 管理工具"
    echo "================================"
    echo "1. 安装 LSSH"
    echo "2. 卸载 LSSH"
    echo "3. 生成 SSH 密钥"
    echo "4. 编辑配置文件"
    echo "0. 退出"
    echo "================================"
}

# 主菜单循环
while true; do
    show_menu
    read -p "请选择操作 (0-4): " choice
    
    case $choice in
        1)
            install_dependencies
            install_golang
            install_lssh
            read -p "按回车键继续..."
            ;;
        2)
            uninstall_lssh
            read -p "按回车键继续..."
            ;;
        3)
            generate_ssh_key
            read -p "按回车键继续..."
            ;;
        4)
            edit_config
            read -p "按回车键继续..."
            ;;
        0)
            log_info "感谢使用！"
            exit 0
            ;;
        *)
            log_error "无效选择"
            read -p "按回车键继续..."
            ;;
    esac
done 