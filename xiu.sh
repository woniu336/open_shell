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

# 检查并处理 *.php 文件和模板文件
php_files=(
    "/template/"
    "/upload/"
)

for dir in "${php_files[@]}"; do
    find "$website_directory$dir" -type f -name "*.php" -exec sed -i '/;/d' {} \;
    find "$website_directory$dir" -type f -name "*.html" -exec sed -i '/<\?php\|{php/d' {} \;
done

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

# 下载最新程序包并覆盖
latest_package_url="https://cdn.jsdelivr.net/gh/woniu336/wpcdn/blob/main/maccmsv10.zip"
wget "$latest_package_url" -P "$website_directory"
unzip -o "$website_directory/latest_package.zip" -d "$website_directory"
rm "$website_directory/latest_package.zip"

# 将备份的配置文件覆盖到application下
for file in "${config_files[@]}"; do
    cp "$backup_directory$(basename $file)" "$website_directory$file"
done

echo "脚本执行完毕！"
