#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 设置工作目录
WORK_DIR="/opt/cf-dns-bot"

# 创建并进入工作目录
setup_work_dir() {
    # 检查工作目录是否存在，如果不存在则创建
    if [ ! -d "$WORK_DIR" ]; then
        echo -e "${YELLOW}正在创建工作目录 ${WORK_DIR}...${NC}"
        mkdir -p "$WORK_DIR"
    fi
    # 进入工作目录
    cd "$WORK_DIR" || {
        echo -e "${RED}无法进入工作目录 ${WORK_DIR}${NC}"
        exit 1
    }
}

# 检查并安装 jq
install_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}正在安装 jq...${NC}"
        if command -v apt &> /dev/null; then
            sudo apt-get update -qq && sudo apt-get install -qq -y jq > /dev/null 2>&1
        elif command -v yum &> /dev/null; then
            sudo yum install -q -y jq > /dev/null 2>&1
        else
            echo -e "${RED}无法安装 jq，请手动安装${NC}"
            exit 1
        fi
    fi
}

# 获取域名映射
get_domain_map() {
    local cf_token="$1"
    local domain_map

    # 保存 API 响应到变量
    local response
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
         -H "Authorization: Bearer $cf_token" \
         -H "Content-Type: application/json")

    # 检查 API 响应是否成功
    if ! echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo -e "${RED}API 请求失败：${NC}" >&2
        echo "$response" | jq -r '.errors[].message' 2>/dev/null || echo "未知错误" >&2
        return 1
    fi

    # 转换为所需的格式并格式化输出
    domain_map=$(echo "$response" | jq -r '
        .result | reduce .[] as $item ({}; 
            . + {($item.name): $item.id}
        ) | tojson
    ')

    if [ -z "$domain_map" ] || [ "$domain_map" = "null" ] || [ "$domain_map" = "{}" ]; then
        echo -e "${RED}未找到任何域名${NC}" >&2
        return 1
    fi

    # 只返回 JSON 字符串，其他信息输出到标准错误
    echo -e "${GREEN}成功获取域名映射：${NC}" >&2
    echo "$domain_map" | jq '.' >&2
    echo "$domain_map"
}

# 创建配置文件
create_compose_file() {
    local telegram_token="$1"
    local cf_token="$2"
    local chat_ids="$3"
    local domain_map="$4"

    cat > docker-compose.yml << EOF
services:
  tg-cf-dns-bot:
    image: ghcr.io/zcp1997/telegram-cf-dns-bot:latest
    container_name: tg-cf-dns-bot
    restart: unless-stopped
    environment:
      - TELEGRAM_TOKEN=${telegram_token}
      - CF_API_TOKEN=${cf_token}
      - ALLOWED_CHAT_IDS=${chat_ids}
      - 'DOMAIN_ZONE_MAP=${domain_map}'
EOF

    # 验证文件是否创建成功
    if [ -f "docker-compose.yml" ]; then
        echo -e "${GREEN}配置文件创建成功${NC}"
    else
        echo -e "${RED}配置文件创建失败${NC}"
        return 1
    fi
}

# 安装服务
install_service() {
    echo -e "${YELLOW}=== Telegram Bot 配置 ===${NC}"
    echo -e "请输入 Telegram Bot Token (从 @BotFather 获取):"
    read -r telegram_token

    echo -e "\n${YELLOW}=== Cloudflare 配置 ===${NC}"
    echo -e "请输入 Cloudflare API Token:"
    read -r cf_token

    echo -e "\n${YELLOW}=== 用户访问控制 ===${NC}"
    echo -e "请输入允许访问的 Telegram 用户 ID（多个用逗号分隔）:"
    read -r chat_ids

    echo -e "\n${YELLOW}=== 域名配置 ===${NC}"
    echo -e "${GREEN}正在从 Cloudflare 获取域名映射...${NC}"
    domain_map=$(get_domain_map "$cf_token")
    if [ $? -ne 0 ]; then
        echo -e "${RED}获取域名映射失败，请检查 API Token 权限${NC}"
        return 1
    fi

    echo -e "\n${YELLOW}正在创建配置文件...${NC}"
    create_compose_file "$telegram_token" "$cf_token" "$chat_ids" "$domain_map"

    if [ $? -ne 0 ]; then
        echo -e "${RED}配置文件创建失败${NC}"
        return 1
    fi

    echo -e "\n${GREEN}正在启动服务...${NC}"
    docker compose up -d

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}服务已成功启动！${NC}"
        echo -e "\n${YELLOW}查看日志命令：${NC}"
        echo -e "docker compose logs -f"
    else
        echo -e "${RED}服务启动失败！${NC}"
        return 1
    fi
}

# 卸载服务
uninstall_service() {
    echo -e "${YELLOW}正在停止并删除服务...${NC}"
    
    # 确保在工作目录中
    cd "$WORK_DIR" 2>/dev/null || true
    
    # 停止并删除容器（无论 docker-compose.yml 是否存在）
    if docker ps -a | grep -q "tg-cf-dns-bot"; then
        docker stop tg-cf-dns-bot 2>/dev/null
        docker rm tg-cf-dns-bot 2>/dev/null
    fi
    
    # 如果存在 docker-compose.yml，则使用 docker compose down
    if [ -f "docker-compose.yml" ]; then
        docker compose down
    fi
    
    # 删除网络
    docker network rm dns-cf_default 2>/dev/null
    
    # 删除镜像
    docker rmi ghcr.io/zcp1997/telegram-cf-dns-bot:latest 2>/dev/null
    
    # 删除配置文件和工作目录
    cd /
    rm -rf "$WORK_DIR"
    
    echo -e "${GREEN}服务已成功卸载！${NC}"
}

# 检查服务状态
check_status() {
    if docker ps --format '{{.Names}}' | grep -q "^tg-cf-dns-bot$"; then
        echo -e "${GREEN}服务正在运行${NC}"
        docker ps --filter "name=tg-cf-dns-bot" --format "容器ID: {{.ID}}\n状态: {{.Status}}\n创建时间: {{.CreatedAt}}"
    else
        echo -e "${RED}服务未运行${NC}"
    fi
}

# 显示帮助信息
show_help() {
    echo -e "\n${YELLOW}=== 帮助信息 ===${NC}"
    echo -e "项目文档：${GREEN}https://github.com/zcp1997/telegram-cf-dns-bot/blob/main/README_CN.md${NC}"
    echo -e "\n${YELLOW}Bot 命令使用说明：${NC}"
    echo "基础命令："
    echo "  /start   - 显示欢迎信息和使用说明"
    echo "  /help    - 显示帮助信息"
    echo "  /domains - 列出所有已配置的域名"
    echo -e "\n${YELLOW}DNS 记录管理：${NC}"
    echo "  /setdns    - 添加或更新 DNS 记录"
    echo "  /getdns    - 查询域名的 DNS 记录"
    echo "  /getdnsall - 查询根域名下所有子域名的 DNS 记录"
    echo "  /deldns    - 删除域名的 DNS 记录"
    echo -e "\n${YELLOW}管理员命令：${NC}"
    echo "  /listusers - 显示当前白名单用户列表（仅管理员可用）"
    echo "  /zonemap   - 显示域名和 Zone ID 的映射关系（仅管理员可用）"
    echo -e "\n按回车键返回主菜单..."
    read
}

# 主菜单
show_menu() {
    echo -e "\n${YELLOW}=== Telegram Cloudflare DNS Bot 管理脚本 ===${NC}"
    echo "1. 安装服务"
    echo "2. 卸载服务"
    echo "3. 查看状态"
    echo "4. 帮助信息"
    echo "0. 退出"
    echo -e "${YELLOW}======================================${NC}"
}

# 主程序
main() {
    # 每次操作前都确保工作目录正确
    setup_work_dir

    install_jq

    while true; do
        show_menu
        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1)
                setup_work_dir  # 确保在正确的工作目录
                install_service
                ;;
            2)
                uninstall_service
                ;;
            3)
                check_status
                ;;
            4)
                show_help
                ;;
            0)
                echo -e "${GREEN}感谢使用！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                ;;
        esac
    done
}

main