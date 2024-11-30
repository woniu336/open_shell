#!/bin/bash

# 初始化变量
img_dir=""

# 颜色定义
CYAN='\033[0;36m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
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
        output_filename="${filename}"
        temp_file="${dir}/temp_${filename}"
        
        local original_size=$(stat -c%s "$file")
        ((total_original_size += original_size))

        local convert_cmd
        if [[ "$filename" =~ \.(png)$ ]]; then
            convert_cmd="magick '$file' -strip -define png:compression-level=9 '${temp_file}'"
        else
            convert_cmd="magick '$file' -strip -interlace Plane -gaussian-blur 0.05 -quality 85% '${temp_file}'"
        fi

        if eval $convert_cmd; then
            local new_size=$(stat -c%s "${temp_file}")
            if [ $new_size -lt $original_size ]; then
                mv "${temp_file}" "$file"
                ((total_new_size += new_size))
                output "$filename: 已优化 (节省了 $((original_size - new_size)) 字节)"
            else
                rm "${temp_file}"
                ((total_new_size += original_size))
                output "$filename: 保留原图 (压缩后大小大于原图)"
            fi
        else
            echo "$filename: 压缩失败"
            rm -f "${temp_file}"
            ((error_count++))
            ((total_new_size += original_size))
        fi
    done < <(find "$img_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

    output "处理完成 - $mode"
    print_statistics $total_files $total_original_size $total_new_size $error_count
}

# 主菜单
show_menu() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       ${WHITE}图片压缩优化工具 v1.0${CYAN}          ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║                                        ║${NC}"
    echo -e "${CYAN}║  ${YELLOW}1.${WHITE} 设置目录                         ${CYAN}║${NC}"
    echo -e "${CYAN}║  ${YELLOW}2.${WHITE} 压缩优化图片                     ${CYAN}║${NC}"
    echo -e "${CYAN}║  ${YELLOW}3.${WHITE} 退出程序                         ${CYAN}║${NC}"
    echo -e "${CYAN}║                                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo
    echo -e -n "${GREEN}请选择操作 (1-3):${NC} "
    read choice
    
    case $choice in
        1) set_directories ;;
        2) 
            if [ -z "$img_dir" ]; then
                set_directories
            fi
            process_images "压缩优化图片"
            ;;
        3) 
            echo -e "${YELLOW}感谢使用，再见！${NC}"
            exit 0 
            ;;
        *) echo -e "${YELLOW}无效选择，请重试。${NC}" ;;
    esac
    
    echo
    echo -e "${GREEN}操作完成，按回车键返回主菜单...${NC}"
    read
}

# 主程序
while true; do
    show_menu
done

# 添加以下行以防止窗口立即关闭
echo "按任意键退出..."
read -n 1 -s