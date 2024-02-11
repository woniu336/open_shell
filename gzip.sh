#!/bin/bash

# 获取用户输入的目录路径
read -p "请输入目录路径: " directory_path

# 获取目录下的所有css和js文件
css_js_files=$(find "$directory_path" -type f \( -name "*.css" -o -name "*.js" \))

# 压缩每个文件
for file in $css_js_files; do
    gzip -9 -c "$file" > "$file.gz"
done


echo "操作完成。"
