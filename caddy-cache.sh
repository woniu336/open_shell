#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Caddy 自定义版本部署脚本${NC}"
echo -e "${GREEN}========================================${NC}\n"

# 下载压缩包
echo -e "${YELLOW}[1/7]${NC} 正在下载 Caddy 安装包..."
cd /tmp
wget -q --show-progress https://github.com/jimugou/jimugou.github.io/releases/download/v1.0.0/caddy-custom-with-cache.tar.gz
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} 下载完成\n"
else
    echo -e "${RED}✗${NC} 下载失败\n"
    exit 1
fi

# 解压
echo -e "${YELLOW}[2/7]${NC} 正在解压文件..."
tar -xzf caddy-custom-with-cache.tar.gz 2>/dev/null
echo -e "${GREEN}✓${NC} 解压完成\n"

# 停止旧服务
echo -e "${YELLOW}[3/7]${NC} 正在停止旧服务..."
sudo systemctl stop caddy 2>/dev/null || true
echo -e "${GREEN}✓${NC} 服务已停止\n"

# 备份原版
echo -e "${YELLOW}[4/7]${NC} 正在备份原版本..."
sudo cp /usr/bin/caddy /usr/bin/caddy.backup 2>/dev/null || true
echo -e "${GREEN}✓${NC} 备份完成\n"

# 替换二进制文件
echo -e "${YELLOW}[5/7]${NC} 正在安装新版本..."
sudo mv /tmp/caddy-custom /usr/bin/caddy
sudo chmod +x /usr/bin/caddy
sudo chown root:root /usr/bin/caddy
echo -e "${GREEN}✓${NC} 安装完成\n"

# 验证
echo -e "${YELLOW}[6/7]${NC} 正在验证安装..."
echo -e "  版本: $(caddy version 2>/dev/null | head -n 1)"
if caddy list-modules 2>/dev/null | grep -q cache; then
    echo -e "  缓存模块: ${GREEN}已安装${NC}\n"
else
    echo -e "  缓存模块: ${RED}未找到${NC}\n"
fi

# 启动服务
echo -e "${YELLOW}[7/7]${NC} 正在启动服务..."
sudo systemctl start caddy
sleep 1

if sudo systemctl is-active --quiet caddy; then
    echo -e "${GREEN}✓${NC} Caddy 服务运行正常\n"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${RED}✗${NC} 服务启动失败，请检查日志:\n"
    sudo systemctl status caddy --no-pager -l
    exit 1
fi
