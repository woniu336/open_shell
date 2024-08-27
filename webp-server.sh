#!/bin/bash

# 如果命令以非零状态退出，立即退出脚本
set -e

# 检查Docker是否已安装的函数
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker未安装。请先安装Docker。"
        exit 1
    fi
}

# 检查Docker Compose是否已安装的函数
check_docker_compose() {
    if ! command -v docker compose &> /dev/null; then
        echo "Docker Compose未安装。请先安装Docker Compose。"
        exit 1
    fi
}

# 创建必要目录的函数
create_directories() {
    mkdir -p /opt/docker_data/WebP/exhaust /opt/docker_data/WebP/metadata
    cd /opt/docker_data/WebP
}

# 创建docker-compose.yml的函数
create_docker_compose() {
    cat > docker-compose.yml <<EOL
version: '3'
services:
  webp:
    image: webpsh/webp-server-go
    restart: always
    environment:
      - MALLOC_ARENA_MAX=1
    volumes:
      - ./exhaust:/opt/exhaust
      - ./metadata:/opt/metadata
      - ./config.json:/etc/config.json
    ports:
      - 127.0.0.1:3333:3333
EOL
}

# 交互式配置IMG_MAP的函数
configure_img_map() {
    local img_map=""
    local continue_adding="yes"
    while true; do
        read -p "输入路径（例如，/image 注意带斜杠）: " path
        read -p "输入要代理的图片地址（例如，https://image.example.com）: " address
        
        if [ -n "$img_map" ]; then
            img_map="$img_map,"
        fi
        img_map="$img_map\"$path\": \"$address\""
        
        while true; do
            read -p "是否要添加另一个路径和地址？(yes/y/no/n): " continue_adding
            continue_adding=$(echo "$continue_adding" | tr '[:upper:]' '[:lower:]')
            if [[ "$continue_adding" == "yes" || "$continue_adding" == "y" || "$continue_adding" == "no" || "$continue_adding" == "n" ]]; then
                break
            else
                echo "无效输入，请输入 yes、y、no 或 n。"
            fi
        done
        
        if [[ "$continue_adding" == "no" || "$continue_adding" == "n" ]]; then
            break
        fi
    done
    echo "{$img_map}"
}

# 创建config.json的函数
create_config() {
    echo "让我们配置IMG_MAP："
    local img_map=$(configure_img_map)

    cat > config.json <<EOL
{
  "HOST": "0.0.0.0",
  "PORT": "3333",
  "QUALITY": "80",
  "IMG_PATH": "",
  "EXHAUST_PATH": "./exhaust",
  "IMG_MAP": $img_map,
  "ALLOWED_TYPES": ["jpg", "png", "jpeg", "bmp", "gif", "svg", "heic", "nef", "webp"],
  "CONVERT_TYPES": ["avif"],
  "STRIP_METADATA": true,
  "ENABLE_EXTRA_PARAMS": true,
  "EXTRA_PARAMS_CROP_INTERESTING": "InterestingAttention",
  "READ_BUFFER_SIZE": 4096,
  "CONCURRENCY": 262144,
  "DISABLE_KEEPALIVE": false,
  "CACHE_TTL": 2592000,
  "MAX_CACHE_SIZE": 0
}
EOL
}

# 启动Docker容器的函数
start_container() {
    docker compose up -d
}

# 主执行函数
main() {
    echo "开始WebP服务器设置..."
    
    check_docker
    check_docker_compose
    create_directories
    create_docker_compose
    create_config
    start_container
    
    echo "WebP服务器设置成功完成！"
    echo "记得为3333端口设置反向代理。"
}

# 运行主函数
main
