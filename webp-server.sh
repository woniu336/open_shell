#!/bin/bash

# 如果命令以非零状态退出，立即退出脚本
# set -e  # 移除此行以防止脚本在检测到未安装时退出

# 定义配置文件路径
CONFIG_FILE="/opt/docker_data/WebP/config.json"
DOCKER_COMPOSE_FILE="/opt/docker_data/WebP/docker-compose.yml"

# 检查Docker是否已安装的函数
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker未安装。请先安装Docker。"
        return 1
    fi
    return 0
}

# 检查Docker Compose是否已安装的函数
check_docker_compose() {
    if ! command -v docker compose &> /dev/null; then
        echo "Docker Compose未安装。请先安装Docker Compose。"
        return 1
    fi
    return 0
}

# 检查jq是否已安装的函数
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq未安装。请先安装jq。"
        echo "Debian/Ubuntu: sudo apt-get install jq"
        echo "CentOS/RHEL: sudo yum install jq"
        return 1
    fi
    return 0
}

# 检查容器是否已安装并运行
check_container() {
    if docker ps -a --format '{{.Names}}' | grep -q "webp-"; then
        if docker ps --format '{{.Names}}' | grep -q "webp-"; then
            echo "WebP容器已安装且正在运行。"
            return 0
        else
            echo "WebP容器已安装但未运行。"
            return 1
        fi
    else
        echo "WebP容器未安装。"
        return 2
    fi
}

# 创建必要目录的函数
create_directories() {
    mkdir -p /opt/docker_data/WebP/exhaust /opt/docker_data/WebP/metadata
    echo "已创建必要的目录。"
}

# 创建docker-compose.yml的函数
create_docker_compose() {
    cat > "$DOCKER_COMPOSE_FILE" <<EOL
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
      - "3333:3333"
EOL
    echo "已创建docker-compose.yml文件。"
}

# 初始化config.json的函数
initialize_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOL
{
  "HOST": "0.0.0.0",
  "PORT": "3333",
  "QUALITY": "80",
  "IMG_PATH": "",
  "EXHAUST_PATH": "./exhaust",
  "IMG_MAP": {},
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
        echo "已创建初始config.json文件。"
    else
        echo "config.json已存在，跳过创建。"
    fi
}

# 显示当前IMG_MAP的函数
list_img_map() {
    echo -e "\033[37m当前的IMG_MAP映射如下：\033[0m"
    if [ -f "$CONFIG_FILE" ]; then
        if [ -s "$CONFIG_FILE" ]; then
            echo -e "\033[34m╔════════════════════════════════════╗\033[0m"
            if jq -r '.IMG_MAP | to_entries[] | "\(.key) -> \(.value)"' "$CONFIG_FILE" 2>/dev/null; then
                echo -e "\033[34m╚════════════════════════════════════╝\033[0m"
            else
                echo -e "\033[37m暂无映射配置\033[0m"
                echo -e "\033[34m╚════════════════════════════════════╝\033[0m"
            fi
        else
            echo -e "\033[37m配置文件为空\033[0m"
        fi
    else
        echo -e "\033[37m配置文件不存在\033[0m"
    fi
}

# 添加新的IMG_MAP映射的函数
add_img_map() {
    local need_restart=false
    while true; do
        read -p "输入路径（例如，/image 注意带斜杠）: " path
        read -p "输入要代理的图片地址（例如，https://image.example.com）: " address

        # 检查路径是否以斜杠开头
        if [[ "$path" != /* ]]; then
            echo "路径必须以斜杠（/）开头。"
            continue
        fi

        # 检查地址是否以http(s)开头
        if [[ "$address" != http://* && "$address" != https://* ]]; then
            echo "地址必须以http://或https://开头。"
            continue
        fi

        # 使用jq添加或更新映射
        if jq --arg path "$path" --arg address "$address" '.IMG_MAP[$path] = $address' "$CONFIG_FILE" > /tmp/config_tmp.json; then
            mv /tmp/config_tmp.json "$CONFIG_FILE"
            echo "映射已添加/更新。"
            need_restart=true
        else
            echo "更新映射时出错。请检查config.json是否有效。"
            rm -f /tmp/config_tmp.json
            return
        fi

        read -p "是否要添加另一个映射？(yes/y/no/n): " continue_adding
        continue_adding=$(echo "$continue_adding" | tr '[:upper:]' '[:lower:]')
        if [[ "$continue_adding" != "yes" && "$continue_adding" != "y" ]]; then
            break
        fi
    done

    if [ "$need_restart" = true ]; then
        echo "正在重启容器以应用新的映射..."
        cd /opt/docker_data/WebP
        docker compose restart
        echo "容器已重启，新的映射已生效。"
    fi
}

# 删除IMG_MAP映射的函数
remove_img_map() {
    echo "当前的IMG_MAP映射如下："
    # 使用数组存储映射
    local mappings=()
    # 使用while循环读取每行映射
    while IFS= read -r line; do
        mappings+=("$line")
    done < <(jq -r '.IMG_MAP | to_entries[] | "\(.key) -> \(.value)"' "$CONFIG_FILE" 2>/dev/null)

    if [ ${#mappings[@]} -eq 0 ]; then
        echo "暂无映射配置可删除"
        return
    fi

    # 显示映射列表
    for i in "${!mappings[@]}"; do
        echo "$((i+1)). ${mappings[$i]}"
    done

    while true; do
        echo "0. 返回上级菜单"
        read -p "请输入要删除的映射编号 [0-${#mappings[@]}]: " del_choice
        if [[ "$del_choice" =~ ^[0-9]+$ ]]; then
            if [ "$del_choice" -gt 0 ] && [ "$del_choice" -le "${#mappings[@]}" ]; then
                local selected_mapping=${mappings[$((del_choice - 1))]}
                local path=$(echo "$selected_mapping" | cut -d' ' -f1)
                
                # 使用jq删除映射
                if jq --arg path "$path" 'del(.IMG_MAP[$path])' "$CONFIG_FILE" > /tmp/config_tmp.json; then
                    mv /tmp/config_tmp.json "$CONFIG_FILE"
                    echo "已删除映射: $selected_mapping"
                    echo "正在重启容器以应用更改..."
                    cd /opt/docker_data/WebP
                    docker compose restart
                    echo "容器已重启，映射变更已生效。"
                else
                    echo "删除映射时出错。请检查config.json是否有效。"
                    rm -f /tmp/config_tmp.json
                fi
                break
            elif [ "$del_choice" -eq 0 ]; then
                break
            else
                echo "无效选择，请输入0到${#mappings[@]}之间的数字。"
            fi
        else
            echo "无效输入，请输入数字。"
        fi
    done
}

# 管理地址映射的函数
manage_address_mapping() {
    while true; do
        clear
        echo -e "\033[34m╔════════════════════════════════════╗"
        echo -e "║\033[37m        地址映射管理菜单           \033[34m║"
        echo -e "╠════════════════════════════════════╣"
        echo -e "║\033[33m 1.\033[37m 添加新的映射                   \033[34m║"
        echo -e "║\033[33m 2.\033[37m 删除现有的映射                 \033[34m║"
        echo -e "║\033[33m 3.\033[37m 查看当前映射                   \033[34m║"
        echo -e "║\033[33m 0.\033[37m 返回主菜单                     \033[34m║"
        echo -e "╚════════════════════════════════════╝\033[0m"
        read -p "请输入您的选择 [0-3]: " sub_choice
        case $sub_choice in
            1)
                add_img_map
                ;;
            2)
                remove_img_map
                ;;
            3)
                list_img_map
                ;;
            0)
                break
                ;;
            *)
                echo "无效选择，请输入0-3之间的数字。"
                ;;
        esac
        echo "按回车键继续..."
        read
    done
}

# 创建config.json并配置
create_config() {
    echo "正在初始化配置文件..."
    initialize_config
    echo "配置文件初始化完成。"
}

# 启动Docker容器的函数
start_container() {
    cd /opt/docker_data/WebP
    if docker compose up -d; then
        echo "Docker容器已启动。"
    else
        echo "启动Docker容器时出错。请检查Docker Compose配置。"
    fi
}

# 安装并启动WebP服务器的函数
install_webp_server() {
    local container_status
    check_container
    container_status=$?
    
    if [ $container_status -eq 0 ]; then
        echo "WebP服务器已安装并正在运行，无需重新安装。"
        return
    elif [ $container_status -eq 1 ]; then
        echo "检测到WebP服务器已安装但未运行，正在启动..."
        start_container
        return
    fi
    
    create_directories
    create_docker_compose
    create_config
    start_container
    echo "WebP服务器已安装并启动。"
    echo "建议为3333端口设置反向代理。"
}

# 显示菜单的函数
show_menu() {
    clear
    echo -e "\033[34m╔════════════════════════════════════╗"
    echo -e "║\033[37m        优雅的图床代理工具         \033[34m║"
    echo -e "╠════════════════════════════════════╣"
    echo -e "║\033[33m 1.\033[37m 安装并启动WebP服务器           \033[34m║"
    echo -e "║\033[33m 2.\033[37m 添加或更新地址映射             \033[34m║"
    echo -e "║\033[33m 3.\033[37m 启动WebP容器                   \033[34m║"
    echo -e "║\033[33m 0.\033[37m 退出                           \033[34m║"
    echo -e "╚════════════════════════════════════╝\033[0m"
}

# 主执行函数
main() {
    local docker_status=0
    local docker_compose_status=0
    local jq_status=0

    check_docker || docker_status=1
    check_docker_compose || docker_compose_status=1
    check_jq || jq_status=1

    if [ $docker_status -ne 0 ] || [ $docker_compose_status -ne 0 ] || [ $jq_status -ne 0 ]; then
        echo "依赖项未满足，请安装缺少的依赖项后重试。"
        exit 1
    fi

    while true; do
        show_menu
        read -p "请输入您的选择 [0-3]: " choice
        case $choice in
            1)
                echo "开始安装并启动WebP服务器..."
                install_webp_server
                ;;
            2)
                echo "进入地址映射管理..."
                manage_address_mapping
                ;;
            3)
                echo "正在启动WebP容器..."
                start_container
                ;;
            0)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选择，请输入0-3之间的数字。"
                ;;
        esac
        echo "按回车键继续..."
        read
    done
}

# 运行主函数
main