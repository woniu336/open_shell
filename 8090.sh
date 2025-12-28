#!/bin/bash

# 检查并安装依赖
check_dependencies() {
    local missing=()
    
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        missing+=("wget")
    fi
    
    if ! command -v unzip &> /dev/null; then
        missing+=("unzip")
    fi
    
    if ! command -v sed &> /dev/null; then
        missing+=("sed")
    fi
    
    if ! command -v gzip &> /dev/null; then
        missing+=("gzip")
    fi
    
    if ! command -v brotli &> /dev/null; then
        missing+=("brotli")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "安装依赖: ${missing[*]}"
        if [ -f /etc/debian_version ]; then
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y "${missing[@]}" > /dev/null 2>&1
        else
            echo "请手动安装: ${missing[*]}"
            exit 1
        fi
    fi
}

# 清理目录
clean_directory() {
    local dir="$1"
    
    if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo "清理目录: $dir"
        find "$dir" -mindepth 1 -delete 2>/dev/null || sudo find "$dir" -mindepth 1 -delete 2>/dev/null
    fi
}

# 下载文件
download_file() {
    local url="$1"
    local output="$2"
    
    if command -v wget &> /dev/null; then
        wget -q "$url" -O "$output"
    elif command -v curl &> /dev/null; then
        curl -s -L "$url" -o "$output"
    fi
}

# 主函数
main() {
    # 检查依赖
    check_dependencies
    
    # 输入域名
    read -p "请输入域名 (例如: example.com): " domain
    
    if [ -z "$domain" ]; then
        echo "错误: 域名不能为空"
        exit 1
    fi
    
    # 创建目录路径
    static_path="/var/www/cache/$domain"
    
    # 清理并创建目录
    clean_directory "$static_path"
    mkdir -p "$static_path"
    
    # 输入播放器地址
    read -p "请输入播放器地址 (默认: player.$domain): " player_url
    player_url=${player_url:-player.$domain}
    
    # 下载文件
    zip_file="/tmp/static_$(date +%s).zip"
    download_url="https://github.com/jimugou/jimugou.github.io/releases/download/v1.0.0/8090.zip"
    
    echo "下载文件..."
    download_file "$download_url" "$zip_file"
    
    if [ ! -f "$zip_file" ]; then
        echo "错误: 下载失败"
        exit 1
    fi
    
    # 解压文件
    echo "解压文件..."
    unzip -q "$zip_file" -d "$static_path" 2>/dev/null
    
    # 查找并替换配置文件
    config_file="$static_path/static/js/playerconfig.js"
    
    if [ -f "$config_file" ]; then
        echo "替换播放器地址..."
        sed -i "s|2345\.com|${player_url}|g" "$config_file"
        
        # 压缩文件
        js_dir=$(dirname "$config_file")
        
        echo "压缩文件..."
        for file in "playerconfig.js" "player.js"; do
            source_file="$js_dir/$file"
            if [ -f "$source_file" ]; then
                gzip -9 -c "$source_file" > "${source_file}.gz" 2>/dev/null
                brotli -q 11 -k "$source_file" 2>/dev/null
            fi
        done
    else
        echo "警告: 未找到配置文件"
    fi
    
    # 清理临时文件
    rm -f "$zip_file"
    
    echo "完成!"
    echo "静态文件路径: $static_path"
    echo "播放器地址: $player_url"
}

# 执行
main "$@"
