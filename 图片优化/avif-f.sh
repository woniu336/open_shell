#!/bin/bash

set +e  # 不要在错误时立即退出
trap 'echo "错误发生在第 $LINENO 行" | tee -a "$log_file"' ERR

# 设置路径
magick_path="/d/imagemagick/ImageMagick-7.1.1-Q16-HDRI/magick.exe"
source_dir="/c/Users/Administrator/Desktop/imgs"
log_file="/f/imgback/log/image_process_log.txt"
temp_stats_file="/tmp/image_process_stats.txt"

# 初始化统计文件
echo "0 0 0 0" > "$temp_stats_file"

# 检查必要的路径和程序
if [ ! -f "$magick_path" ]; then
    echo "错误：ImageMagick 未找到，请检查路径: $magick_path" | tee -a "$log_file"
    read -p "按回车键继续..."
fi

if [ ! -d "$source_dir" ]; then
    echo "错误：源目录不存在: $source_dir" | tee -a "$log_file"
    read -p "按回车键继续..."
fi

# 确保日志目录存在
mkdir -p "$(dirname "$log_file")"

# 清空日志文件
> "$log_file"

# 记录日志的函数
log_message() {
    echo "$1" | tee -a "$log_file"
}

process_image() {
    local file="$1"
    local output_file="${file%.*}.avif"
    
    original_size=$(stat -c%s "$file")
    
    # 转换为AVIF格式
    if ! "$magick_path" "$file" -quality 70 -define avif:compression-level=3 -define avif:effort=4 "$output_file"; then
        log_message "错误：无法转换图片为AVIF格式: $file"
        awk '{$4++; print $0}' "$temp_stats_file" > "${temp_stats_file}.tmp" && mv "${temp_stats_file}.tmp" "$temp_stats_file"
        return
    fi
    
    new_size=$(stat -c%s "$output_file")
    
    # 更新统计信息
    awk -v of=$original_size -v nf=$new_size '{$1++; $2+=of; $3+=nf; print $0}' "$temp_stats_file" > "${temp_stats_file}.tmp" && mv "${temp_stats_file}.tmp" "$temp_stats_file"
    
    # 显示处理的文件名，模拟代码流动效果
    echo -e "\e[32m处理: $file (转换为AVIF)\e[0m"
}

# 处理所有图片
echo "开始处理图片..." | tee -a "$log_file"
find "$source_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | while read file; do
    process_image "$file"
    # sleep 0.1  # 添加短暂延迟，使输出看起来更像流动的效果
done

# 读取统计信息
read total_files total_original_size total_new_size error_count < "$temp_stats_file"

# 计算总体统计信息
total_savings=$((total_original_size - total_new_size))
if [ $total_original_size -ne 0 ]; then
    savings_percent=$(awk "BEGIN {printf \"%.2f\", ($total_savings / $total_original_size) * 100}")
else
    savings_percent="0.00"
fi

# 输出总体统计信息
{
    echo -e "\n处理完成。总计："
    echo "处理的文件数：$total_files"
    echo "错误数：$error_count"
    echo "原始总大小：$(numfmt --to=iec-i --suffix=B $total_original_size)"
    echo "压缩后总大小：$(numfmt --to=iec-i --suffix=B $total_new_size)"
    echo "节省空间：$(numfmt --to=iec-i --suffix=B $total_savings) ($savings_percent%)"
} | tee -a "$log_file"

echo -e "\n详细日志保存在: $log_file"
rm -f "$temp_stats_file"  # 清理临时文件
read -p "按回车键退出..."