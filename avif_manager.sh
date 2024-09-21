#!/bin/bash

# 初始化变量
img_dir=""

# 颜色定义
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 输出到控制台（绿色）
output() {
    echo -e "${GREEN}$1${NC}"
}

# 转换Windows路径为Bash兼容路径
convert_path() {
    local input_path="$1"
    if command -v cygpath &> /dev/null; then
        cygpath -u "$input_path"
    elif command -v wslpath &> /dev/null; then
        wslpath -u "$input_path"
    else
        echo "$input_path" | sed -e 's/^\([A-Za-z]\):/\/\L\1/' -e 's/\\/\//g'
    fi
}

# 设置目录
set_directories() {
    while [ -z "$img_dir" ]; do
        read -r -p "请输入图片目录路径: " input_dir
        img_dir=$(convert_path "$input_dir")
        if [ -d "$img_dir" ]; then
            output "图片目录已设置为: $img_dir"
        else
            echo "错误：目录不存在或无法访问，请重新输入。"
            img_dir=""
        fi
    done
}

# 打印统计信息
print_statistics() {
    local total_files=$1
    local total_original_size=$2
    local total_new_size=$3
    local error_count=$4

    local total_savings=$((total_original_size - total_new_size))
    local savings_percent=0

    if [ $total_original_size -ne 0 ]; then
        savings_percent=$(awk "BEGIN {printf \"%.2f\", ($total_savings / $total_original_size) * 100}")
    fi

    echo "----------------------------------------"
    echo "统计信息:"
    echo "处理的文件数：$total_files"
    echo "错误数：$error_count"
    echo "原始总大小：$(numfmt --to=iec-i --suffix=B $total_original_size)"
    echo "压缩后总大小：$(numfmt --to=iec-i --suffix=B $total_new_size)"
    echo "节省空间：$(numfmt --to=iec-i --suffix=B $total_savings) ($savings_percent%)"
    echo "----------------------------------------"
}

# 处理图片的通用函数
process_images() {
    local mode=$1
    output "开始处理图片 - $mode"
    output "当前图片目录: $img_dir"
    
    if [ ! -d "$img_dir" ]; then
        echo "错误：图片目录不存在"
        return
    fi
    
    local total_files=0
    local total_original_size=0
    local total_new_size=0
    local error_count=0

    while IFS= read -r -d '' file; do
        ((total_files++))
        filename=$(basename "$file")
        dir=$(dirname "$file")
        avif_filename="${filename%.*}.avif"
        
        local original_size=$(stat -c%s "$file")
        ((total_original_size += original_size))

        if magick "$file" -quality 70 -define avif:compression-level=3 -define avif:effort=4 "${dir}/${avif_filename}"; then
            local new_size=$(stat -c%s "${dir}/${avif_filename}")
            ((total_new_size += new_size))
            
            if [ "$mode" = "转换并删除原图" ]; then
                if rm "$file"; then
                    output "$filename: 已转换并删除原图"
                else
                    echo "$filename: 转换成功，但无法删除原图"
                    ((error_count++))
                fi
            else
                output "$filename: 已转换"
            fi
        else
            echo "$filename: 转换失败"
            ((error_count++))
        fi
    done < <(find "$img_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

    output "处理完成 - $mode"
    print_statistics $total_files $total_original_size $total_new_size $error_count
}

# 转换并删除原图
convert_and_delete_original() {
    process_images "转换并删除原图"
}

# 转换并保留原图
convert_and_keep_original() {
    process_images "转换并保留原图"
}

# 恢复原图（删除AVIF）
restore_original() {
    output "开始恢复原图 - 删除AVIF"
    output "当前图片目录: $img_dir"
    
    if [ ! -d "$img_dir" ]; then
        echo "错误：图片目录不存在"
        return
    fi
    
    local total_files=0
    local total_size=0
    local error_count=0

    while IFS= read -r -d '' file; do
        ((total_files++))
        filename=$(basename "$file")
        
        local file_size=$(stat -c%s "$file")
        ((total_size += file_size))

        if rm "$file"; then
            output "$filename: 已删除"
        else
            echo "$filename: 删除失败"
            ((error_count++))
        fi
    done < <(find "$img_dir" -type f -iname "*.avif" -print0)

    output "恢复完成 - 删除AVIF"
    print_statistics $total_files $total_size 0 $error_count
}

# 主菜单
show_menu() {
    clear
    echo "========================================="
    echo "            AVIF 图片管理器              "
    echo "========================================="
    echo "1. 设置目录"
    echo "2. 转换为AVIF并删除原图"
    echo "3. 转换为AVIF并保留原图"
    echo "4. 恢复原图（删除AVIF）"
    echo "5. 退出"
    echo "========================================="
    echo
    read -p "请选择操作 (1-5): " choice
    
    case $choice in
        1) set_directories ;;
        2) 
            if [ -z "$img_dir" ]; then
                set_directories
            fi
            convert_and_delete_original 
            ;;
        3) 
            if [ -z "$img_dir" ]; then
                set_directories
            fi
            convert_and_keep_original 
            ;;
        4) 
            if [ -z "$img_dir" ]; then
                set_directories
            fi
            restore_original 
            ;;
        5) exit 0 ;;
        *) echo "无效选择，请重试。" ;;
    esac
    
    echo
    read -p "操作完成，按回车键返回主菜单..."
}

# 主程序
while true; do
    show_menu
done