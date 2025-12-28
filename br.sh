#!/bin/bash

# 获取用户输入的目录路径
read -p "请输入目录路径: " directory_path

# 检查目录是否存在
if [ ! -d "$directory_path" ]; then
    echo "错误：目录 '$directory_path' 不存在"
    exit 1
fi

# 检查brotli命令是否可用
if ! command -v brotli &> /dev/null; then
    echo "错误：brotli命令未找到，请先安装brotli"
    echo "安装方法："
    echo "  Ubuntu/Debian: sudo apt install brotli"
    echo "  CentOS/RHEL: sudo yum install brotli"
    echo "  macOS: brew install brotli"
    exit 1
fi

# 获取目录下的所有css和js文件
css_js_files=$(find "$directory_path" -type f \( -name "*.css" -o -name "*.js" \))

# 压缩统计
total_files=0
compressed_files=0

echo "开始压缩文件..."
for file in $css_js_files; do
    # 检查文件是否可读
    if [ ! -r "$file" ]; then
        echo "警告：无法读取文件 '$file'，跳过"
        continue
    fi
    
    # 检查文件大小，跳过空文件
    if [ ! -s "$file" ]; then
        echo "警告：文件 '$file' 为空，跳过"
        continue
    fi
    
    # 检查是否已存在.br文件且比源文件新
    if [ -f "${file}.br" ] && [ "${file}.br" -nt "$file" ]; then
        echo "跳过：'$file' 的.br文件已存在且更新"
        continue
    fi
    
    total_files=$((total_files + 1))
    
    echo "正在压缩: $file"
    
    # 使用brotli压缩，-k保留源文件，-q 11最高压缩级别
    if brotli -q 11 -k -f "$file"; then
        compressed_files=$((compressed_files + 1))
        
        # 显示压缩率
        original_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        compressed_size=$(stat -f%z "${file}.br" 2>/dev/null || stat -c%s "${file}.br" 2>/dev/null)
        
        if [ "$original_size" -gt 0 ]; then
            ratio=$(echo "scale=2; $compressed_size * 100 / $original_size" | bc)
            echo "  压缩率: ${ratio}% (${original_size} → ${compressed_size} bytes)"
        fi
    else
        echo "错误：压缩 '$file' 失败"
    fi
done

echo ""
echo "操作完成。"
echo "统计："
echo "  总文件数: $total_files"
echo "  成功压缩: $compressed_files"
