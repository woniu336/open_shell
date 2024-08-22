#!/bin/bash

# 检查输入目录是否提供
if [ $# -eq 0 ]; then
    echo "请提供一个输入目录"
    echo "用法: $0 <输入目录>"
    exit 1
fi

input_dir="$1"

# 检查输入目录是否存在
if [ ! -d "$input_dir" ]; then
    echo "错误: 目录 '$input_dir' 不存在"
    exit 1
fi

# 递归函数来处理目录
process_directory() {
    local dir="$1"
    
    # 遍历目录中的所有文件和子目录
    for file in "$dir"/*; do
        if [ -d "$file" ]; then
            # 如果是目录，递归处理
            process_directory "$file"
        elif [ -f "$file" ]; then
            # 如果是文件，检查是否为图片文件
            case "${file,,}" in
                *.png|*.jpg|*.jpeg|*.gif|*.bmp)
                    # 构建输出文件名
                    output_file="${file%.*}.avif"
                    
                    echo "正在转换: $file"
                    ffmpeg -i "$file" -c:v libaom-av1 -crf 30 -b:v 0 "$output_file"
                    ;;
            esac
        fi
    done
}

# 开始处理输入目录
process_directory "$input_dir"

echo "转换完成"
