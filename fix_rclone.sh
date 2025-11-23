#!/bin/bash

# 修复 Rclone 同步路径识别问题

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== 修复 Rclone 同步服务 ===${NC}\n"

# 1. 检查同步脚本并提取正确的路径
if [[ ! -f "./rclone-sync.sh" ]]; then
    echo -e "${RED}✗ 未找到 rclone-sync.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}[1] 提取配置路径...${NC}"

# 提取本地路径
LOCAL_PATH=$(grep "^RCLONE_SYNC_PATH=" rclone-sync.sh | cut -d'"' -f2 | cut -d"'" -f2)
# 提取远程路径
REMOTE_PATH=$(grep "^RCLONE_REMOTE=" rclone-sync.sh | cut -d'"' -f2 | cut -d"'" -f2)

if [[ -z "$LOCAL_PATH" || -z "$REMOTE_PATH" ]]; then
    echo -e "${RED}✗ 无法提取路径配置${NC}"
    echo "请检查 rclone-sync.sh 中的配置"
    exit 1
fi

echo -e "${GREEN}✓ 本地路径: ${BLUE}$LOCAL_PATH${NC}"
echo -e "${GREEN}✓ 远程路径: ${BLUE}$REMOTE_PATH${NC}"

# 2. 检查本地目录
echo -e "\n${YELLOW}[2] 检查本地目录...${NC}"
if [[ -d "$LOCAL_PATH" ]]; then
    echo -e "${GREEN}✓ 目录存在: $LOCAL_PATH${NC}"
    ls -ld "$LOCAL_PATH"
else
    echo -e "${RED}✗ 目录不存在: $LOCAL_PATH${NC}"
    read -p "是否创建该目录? (y/n): " create
    if [[ $create == "y" ]]; then
        mkdir -p "$LOCAL_PATH"
        chmod 755 "$LOCAL_PATH"
        echo -e "${GREEN}✓ 目录已创建${NC}"
    else
        echo -e "${RED}需要先创建目录: $LOCAL_PATH${NC}"
        exit 1
    fi
fi

# 3. 增加 inotify 限制
echo -e "\n${YELLOW}[3] 配置 inotify 限制...${NC}"
if ! grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf 2>/dev/null; then
    echo 'fs.inotify.max_user_watches=524288' >> /etc/sysctl.conf
    sysctl -p &>/dev/null
    echo -e "${GREEN}✓ inotify 限制已增加${NC}"
else
    echo -e "${GREEN}✓ inotify 限制已存在${NC}"
fi

# 4. 停止所有现有服务
echo -e "\n${YELLOW}[4] 停止现有服务...${NC}"
systemctl --user stop rclone_sync_*.service 2>/dev/null
echo -e "${GREEN}✓ 所有服务已停止${NC}"

# 5. 清理错误的服务文件
echo -e "\n${YELLOW}[5] 清理错误的服务文件...${NC}"
rm -f ~/.config/systemd/user/rclone_sync_king__home_op.service
rm -f ~/.config/systemd/user/rclone_sync_king__home_domain.service
echo -e "${GREEN}✓ 旧服务文件已删除${NC}"

# 6. 生成正确的服务名称
SERVICE_NAME=$(echo "$REMOTE_PATH" | sed 's/[:/\.]/_/g')
SERVICE_FILE="$HOME/.config/systemd/user/rclone_sync_${SERVICE_NAME}.service"

echo -e "\n${YELLOW}[6] 创建新的服务文件...${NC}"
echo -e "服务名称: ${BLUE}rclone_sync_${SERVICE_NAME}.service${NC}"

# 创建服务文件
mkdir -p ~/.config/systemd/user

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=rclone_sync $REMOTE_PATH
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$(pwd)/rclone-sync.sh
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=default.target
EOF

echo -e "${GREEN}✓ 服务文件已创建: $SERVICE_FILE${NC}"

# 7. 重新加载并启动服务
echo -e "\n${YELLOW}[7] 启动服务...${NC}"
systemctl --user daemon-reload
systemctl --user enable "rclone_sync_${SERVICE_NAME}.service"
systemctl --user start "rclone_sync_${SERVICE_NAME}.service"

sleep 3

# 8. 检查服务状态
echo -e "\n${YELLOW}[8] 检查服务状态...${NC}"
if systemctl --user is-active "rclone_sync_${SERVICE_NAME}.service" &>/dev/null; then
    echo -e "${GREEN}✓ 服务运行正常${NC}\n"
    systemctl --user status "rclone_sync_${SERVICE_NAME}.service" --no-pager
else
    echo -e "${RED}✗ 服务启动失败${NC}\n"
    echo -e "${YELLOW}查看详细日志:${NC}"
    journalctl --user -u "rclone_sync_${SERVICE_NAME}.service" -n 50 --no-pager
fi

# 9. 总结
echo -e "\n${BLUE}=== 修复完成 ===${NC}\n"
echo -e "${GREEN}配置信息:${NC}"
echo -e "  本地目录: ${BLUE}$LOCAL_PATH${NC}"
echo -e "  远程目录: ${BLUE}$REMOTE_PATH${NC}"
echo -e "  服务名称: ${BLUE}rclone_sync_${SERVICE_NAME}.service${NC}"

echo -e "\n${GREEN}常用命令:${NC}"
echo -e "  查看状态: ${CYAN}systemctl --user status rclone_sync_${SERVICE_NAME}.service${NC}"
echo -e "  查看日志: ${CYAN}journalctl --user -u rclone_sync_${SERVICE_NAME}.service -f${NC}"
echo -e "  重启服务: ${CYAN}systemctl --user restart rclone_sync_${SERVICE_NAME}.service${NC}"
echo -e "  停止服务: ${CYAN}systemctl --user stop rclone_sync_${SERVICE_NAME}.service${NC}"
