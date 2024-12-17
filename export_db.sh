#!/bin/bash

# 提示用户输入数据库主机
read -p "请输入数据库主机地址 (默认: 127.0.0.1): " db_host
db_host=${db_host:-127.0.0.1}

# 提示用户输入数据库用户名
read -p "请输入数据库用户名 (默认: root): " db_user
db_user=${db_user:-root}

# 提示用户输入数据库密码
read -sp "请输入数据库密码: " db_password
echo

# 提示用户确认是否导出所有数据库
read -p "是否导出所有数据库? (y/n, 默认: y): " export_all
export_all=${export_all:-y}

# 确定导出的文件名
read -p "请输入导出文件名 (默认: all_databases.sql.gz): " output_file
output_file=${output_file:-all_databases.sql.gz}

# 构建导出命令
if [ "$export_all" = "y" ]; then
    echo "正在导出所有数据库并压缩为 $output_file..."
    mysqldump -h$db_host -u$db_user -p$db_password --all-databases --events | gzip > $output_file
else
    echo "未选择导出所有数据库，退出操作。"
    exit 1
fi

# 导出完成提示
if [ $? -eq 0 ]; then
    echo "数据库导出成功：$output_file"
else
    echo "数据库导出失败，请检查参数或权限。"
fi
