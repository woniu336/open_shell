#!/bin/bash

# 备份脚本
# 设置变量
BACKUP_DIR="/root"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.tar.gz"

# 创建临时目录用于组织备份文件
TEMP_DIR=$(mktemp -d)

# 复制需要备份的文件
echo "开始备份..."

# 备份数据库文件
mkdir -p ${TEMP_DIR}/data
cp /opt/om/data/data.db ${TEMP_DIR}/data/

# 备份nginx配置文件
mkdir -p ${TEMP_DIR}/nginx
cp -r /opt/om/nginx/conf ${TEMP_DIR}/nginx/

# 打包
echo "正在打包..."
tar -czf ${BACKUP_FILE} -C ${TEMP_DIR} .

# 清理临时目录
rm -rf ${TEMP_DIR}

echo "备份完成: ${BACKUP_FILE}"
echo ""
echo "=== 恢复命令 ==="
echo "tar --warning=no-timestamp -xzf ${BACKUP_FILE} -C /opt/om && /opt/om/oms -s restart"
