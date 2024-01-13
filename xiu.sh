#!/bin/bash

# 提示用户输入网站目录
read -p "请输入网站目录: " website_directory

# 创建备份目录
backup_directory="/home/back"
mkdir -p "$backup_directory"

# 备份原网站配置文件
config_files=(
    "/application/database.php"
    "/application/route.php"
    "/application/extra/maccms.php"
    "/application/extra/bind.php"
    "/application/extra/timming.php"
    "/application/extra/vodplayer.php"
    "/application/extra/voddowner.php"
    "/application/extra/vodserver.php"
)

for file in "${config_files[@]}"; do
    cp "$website_directory$file" "$backup_directory"
done

# 删除指定目录内的所有 .php 文件
find "$website_directory/template/" "$website_directory/upload/" -type f -name "*.php" -exec rm -f {} \;
echo "已删除所有 .php 文件"

# 检查并处理 template 文件夹内的文件
template_directory="$website_directory/template/"
check_template_files=$(find "$template_directory" -type f -exec grep -q -E '<\?php|{php' {} \; -print)

if [ -n "$check_template_files" ]; then
    echo "已删除 template 文件夹内包含 <?php 或 {php 代码段的文件"
else
    echo "template 文件夹内没有包含 <?php 或 {php 代码段的文件"
fi

# 检查并处理 upload 文件夹内的文件
upload_directory="$website_directory/upload/"
check_upload_files=$(find "$upload_directory" -type f -exec grep -q -E '<\?php|{php' {} \; -print)

if [ -n "$check_upload_files" ]; then
    echo "已删除 upload 文件夹内包含 <?php 或 {php 代码段的文件"
else
    echo "upload 文件夹内没有包含 <?php 或 {php 代码段的文件"
fi

# 删除原有目录及所有文件
delete_directories=(
    "/addons/"
    "/application/"
    "/extend/"
    "/static/"
    "/runtime/"
    "/thinkphp/"
    "/vendor/"
    "/说明文档/"
)

for dir in "${delete_directories[@]}"; do
    rm -rf "$website_directory$dir"
done

# 忽略掉 .user.ini 文件的删除错误
rm -f "$website_directory/.user.ini" 2>/dev/null

# 下载最新程序包并覆盖
latest_package_url="https://github.com/jimugou/siteback/releases/download/3026/maccmsv10.zip"
wget "$latest_package_url" -P "$website_directory"
unzip -o "$website_directory/maccmsv10.zip" -d "$website_directory"
rm "$website_directory/maccmsv10.zip"

# 将备份的配置文件覆盖到application下
for file in "${config_files[@]}"; do
    cp "$backup_directory/$(basename $file)" "$website_directory$file"
done


echo "脚本执行完毕！"
