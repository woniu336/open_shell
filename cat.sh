#!/bin/bash

# 输入域名
read -p "请输入域名: " domain

# 创建目录
cache_dir="/var/www/cache/$domain"
mkdir -p "$cache_dir"

# 下载文件
zip_file="/tmp/cat_$(date +%s).zip"
download_url="https://github.com/jimugou/jimugou.github.io/releases/download/v1.0.0/cat.zip"

if command -v wget &> /dev/null; then
    wget -q "$download_url" -O "$zip_file"
elif command -v curl &> /dev/null; then
    curl -s -L "$download_url" -o "$zip_file"
fi

# 解压文件
if [ -f "$zip_file" ]; then
    unzip -q -o "$zip_file" -d "$cache_dir" 2>/dev/null
    rm -f "$zip_file"
fi

echo "完成: $cache_dir"
