#!/bin/bash

# 定义要处理的目录列表
DIRECTORIES=("/www/wwwroot/a.cc")

# 定义备份根目录
BACKUP_ROOT="/opt/backup"

# 定义恶意代码模式
MALICIOUS_PATTERN='stristr|httpGet|char\(|jsc20244|jschl\.nn02\.cc'

# 创建日期时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 创建感染文件列表
INFECTED_LIST="${BACKUP_ROOT}/infected_files_${TIMESTAMP}.txt"
touch "$INFECTED_LIST"

# 遍历每个目录
for DIR in "${DIRECTORIES[@]}"; do
    echo "正在处理目录: $DIR"

    # 为每个目录创建独立的备份目录
    BACKUP_DIR="${BACKUP_ROOT}/$(basename "$DIR")_${TIMESTAMP}"
    mkdir -p "$BACKUP_DIR"

    # 遍历当前目录中的所有PHP文件
    find "$DIR" -type f -name "*.php" | while read -r file; do
        # 创建文件的备份
        relative_path=${file#$DIR/}
        backup_file="${BACKUP_DIR}/${relative_path}"
        mkdir -p "$(dirname "$backup_file")"
        cp "$file" "$backup_file"
        
        # 检查文件是否包含恶意代码
        if grep -qE "$MALICIOUS_PATTERN" "$file"; then
            echo "正在处理文件: $file"
            
            # 将感染文件路径添加到列表中
            echo "$file" >> "$INFECTED_LIST"
            
            # 创建临时文件
            temp_file=$(mktemp)
            
            # 移除恶意代码并保存到临时文件
            sed -E "/$MALICIOUS_PATTERN/d" "$file" > "$temp_file"
            
            # 将临时文件内容移回原文件
            mv "$temp_file" "$file"
            
            echo "已从 $file 中移除恶意代码"
        else
            echo "文件 $file 未发现恶意代码"
        fi
    done

    echo "目录 $DIR 处理完成"
done

echo "所有目录处理完成。原始文件的备份保存在 $BACKUP_ROOT"
echo "感染文件列表保存在 $INFECTED_LIST"

# 显示感染文件数量
INFECTED_COUNT=$(wc -l < "$INFECTED_LIST")
echo "共发现 $INFECTED_COUNT 个感染文件"