#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请以root权限运行此脚本"
    exit 1
fi

# 定义文件路径
CERTBOT_CRON="/etc/cron.d/certbot"

# 检查文件是否存在
if [ ! -f "$CERTBOT_CRON" ]; then
    echo "错误：$CERTBOT_CRON 文件不存在"
    exit 1
fi

# 备份原文件
cp "$CERTBOT_CRON" "${CERTBOT_CRON}.bak"

# 使用sed命令修改文件
sed -i 's/certbot -q renew/certbot -q renew --deploy-hook "systemctl restart lsws"/' "$CERTBOT_CRON"

# 检查修改是否成功
if grep -q 'certbot -q renew --deploy-hook "systemctl restart lsws"' "$CERTBOT_CRON"; then
    echo "更新成功：certbot cron 任务已更新"
else
    echo "错误：更新失败"
    # 如果失败，恢复备份
    mv "${CERTBOT_CRON}.bak" "$CERTBOT_CRON"
    exit 1
fi

# 删除备份文件
rm "${CERTBOT_CRON}.bak"

echo "操作完成"
