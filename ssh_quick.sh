#!/usr/bin/env bash
#=============================================================
# SSH 一键配置脚本
#=============================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# 获取用户名
read -p "GitHub 用户名: " GITHUB_USER
if [ -z "$GITHUB_USER" ]; then
    echo -e "${RED}错误: 用户名不能为空${RESET}"
    exit 1
fi

# 获取端口号
read -p "SSH 端口号: " SSH_PORT
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo -e "${RED}错误: 无效端口号${RESET}"
    exit 1
fi

# 检查并配置 UFW
if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${YELLOW}检测到 UFW 已启用，添加端口规则...${RESET}"
        sudo ufw allow ${SSH_PORT}/tcp >/dev/null 2>&1
    else
        echo -e "${YELLOW}UFW 未启用，跳过配置${RESET}"
    fi
else
    echo -e "${YELLOW}未检测到 UFW，安装并配置...${RESET}"
    sudo apt-get update >/dev/null 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ufw >/dev/null 2>&1
    sudo ufw --force enable >/dev/null 2>&1
    sudo ufw allow ${SSH_PORT}/tcp >/dev/null 2>&1
    sudo ufw allow 22/tcp >/dev/null 2>&1  # 确保不锁定
fi

# 执行密钥安装
echo -e "${YELLOW}正在配置 SSH...${RESET}"
bash <(curl -fsSL https://raw.githubusercontent.com/wuzf/SSH_Key_Installer/master/key.sh) -og ${GITHUB_USER} -p ${SSH_PORT} -d

# 获取服务器 IP
SERVER_IP=$(curl -s ip.sb)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}✓ 配置完成！${RESET}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "测试登录: ${YELLOW}ssh root@${SERVER_IP} -p ${SSH_PORT}${RESET}"
echo ""
