#!/bin/bash

# 全局变量
SITES_FILE="sites.txt"
SEARCH_ENGINE="www.bing.com"

# URL编码函数
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# 从站点地图提取URL的函数
extract_urls_from_sitemap() {
    local sitemap_url="$1"
    curl -s "$sitemap_url" | grep -oP '(?<=<loc>)https?://[^<]+'
}

# 提交单个URL的函数
submit_single_url() {
    local url="$1"
    local key="$2"
    local search_engine="$3"
    encoded_url=$(urlencode "$url")
    response=$(curl -s -o /dev/null -w "%{http_code}" "https://${search_engine}/indexnow?url=${encoded_url}&key=${key}")
    echo $response
}

# 提交多个URL的函数
submit_multiple_urls() {
    local host="$1"
    local key="$2"
    local search_engine="$3"
    shift 3
    local urls=("$@")
    
    local url_json_array=$(printf '%s\n' "${urls[@]}" | jq -R . | jq -s .)
    
    local json_data=$(jq -n \
                  --arg host "$host" \
                  --arg key "$key" \
                  --argjson urlList "$url_json_array" \
                  '{host: $host, key: $key, urlList: $urlList}')
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://${search_engine}/indexnow" \
         -H "Content-Type: application/json; charset=utf-8" \
         -d "$json_data")
    echo $response
}

# 添加站点的函数
add_site() {
    echo "请输入域名:"
    read domain
    echo "请输入密钥:"
    read key
    echo "$domain:$key" >> $SITES_FILE
    echo "站点添加成功。"
}

# 提交站点地图的函数
submit_sitemap() {
    echo "请输入站点地图URL:"
    read sitemap_url
    domain=$(echo $sitemap_url | awk -F[/:] '{print $4}')
    
    if grep -q "^$domain:" $SITES_FILE; then
        key=$(grep "^$domain:" $SITES_FILE | cut -d: -f2)
        echo "正在从站点地图提取URL..."
        urls=($(extract_urls_from_sitemap "$sitemap_url"))
        if [ ${#urls[@]} -eq 0 ]; then
            echo "站点地图中未找到URL。"
            return
        fi
        echo "在站点地图中找到 ${#urls[@]} 个URL。"
        if [ ${#urls[@]} -gt 10000 ]; then
            echo "警告：找到超过10,000个URL。仅提交前10,000个。"
            urls=("${urls[@]:0:10000}")
        fi
        echo "正在向IndexNow提交URL..."
        status_code=$(submit_multiple_urls "$domain" "$key" "$SEARCH_ENGINE" "${urls[@]}")
        interpret_status_code $status_code
    else
        echo "错误：在站点列表中未找到该域名。"
    fi
}


# 优化后的手动提交URL函数
manual_submit() {
    echo "请输入URL（用空格分隔多个URL）:"
    read -a urls

    if [ ${#urls[@]} -eq 0 ]; then
        echo "错误：未输入任何URL。"
        return
    fi

    # 从第一个URL中提取域名
    domain=$(echo "${urls[0]}" | awk -F[/:] '{print $4}')

    if grep -q "^$domain:" $SITES_FILE; then
        key=$(grep "^$domain:" $SITES_FILE | cut -d: -f2)
        echo "找到匹配的域名: $domain"
        echo "使用密钥: $key"
        echo "要提交的URL:"
        printf '%s\n' "${urls[@]}"
        echo "是否确认提交这些URL？(y/n)"
        read confirm
        if [ "$confirm" = "y" ]; then
            if [ ${#urls[@]} -eq 1 ]; then
                echo "正在提交单个URL..."
                status_code=$(submit_single_url "${urls[0]}" "$key" "$SEARCH_ENGINE")
            else
                echo "正在提交多个URL..."
                status_code=$(submit_multiple_urls "$domain" "$key" "$SEARCH_ENGINE" "${urls[@]}")
            fi
            interpret_status_code $status_code
        else
            echo "已取消提交。"
        fi
    else
        echo "错误：在站点列表中未找到域名 $domain。"
        echo "请先使用"添加站点"功能添加此域名。"
    fi
}


# 查看站点的函数
view_sites() {
    if [ -s "$SITES_FILE" ]; then
        echo "当前站点列表:"
        cat $SITES_FILE
        echo "是否要更改站点的密钥？(y/n)"
        read answer
        if [ "$answer" = "y" ]; then
            echo "请输入域名:"
            read domain
            echo "请输入新的密钥:"
            read new_key
            sed -i "s/^$domain:.*/$domain:$new_key/" $SITES_FILE
            echo "密钥更新成功。"
        fi
    else
        echo "还没有添加任何站点。"
    fi
}

# 更换端点的函数
change_endpoint() {
    echo "当前端点: $SEARCH_ENGINE"
    echo "选择新的端点:"
    echo "1. api.indexnow.org"
    echo "2. www.bing.com"
    read choice
    case $choice in
        1) SEARCH_ENGINE="api.indexnow.org";;
        2) SEARCH_ENGINE="www.bing.com";;
        *) echo "无效的选择。保持当前端点。";;
    esac
    echo "当前端点: $SEARCH_ENGINE"
}

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 解释状态码的函数（带颜色）
interpret_status_code() {
    case $1 in
        200) echo -e "${GREEN}200 OK: URL已成功提交。${NC}";;
        202) echo -e "${YELLOW}202 已接受: URL已收到。IndexNow密钥验证待定。${NC}";;
        400) echo -e "${RED}400 错误请求: 无效格式。${NC}";;
        403) echo -e "${RED}403 禁止: 无效的密钥（未找到密钥或密钥不在文件中）。${NC}";;
        422) echo -e "${RED}422 无法处理的实体: URL不属于主机或密钥与协议模式不匹配。${NC}";;
        429) echo -e "${RED}429 请求过多: 请求过多（可能是垃圾邮件）。${NC}";;
        *) echo -e "${RED}未知状态码: $1${NC}";;
    esac
}

# 显示获取密钥指南
show_key_guide() {
    echo -e "${YELLOW}==== IndexNow 密钥获取指南 ==========${NC}"
    echo ""
    echo -e "1. 访问 ${GREEN}https://www.bing.com/indexnow/getstarted${NC}"
    echo "2. 往下滑，找到 Generate API Key"
    echo "3. 下载 API Key 保存到网站根目录(txt格式)"
    echo "4. 确保能打开 http(s)://你的域名/xxx.txt"
	echo ""
    echo -e "${YELLOW}=======================================${NC}"
    echo "按任意键返回主菜单..."
    read -n 1 -s
}


# 显示获取密钥指南
task_mg() {
    clear
	curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/indexnow-task-manager.sh && chmod +x indexnow-task-manager.sh && ./indexnow-task-manager.sh
    echo "按任意键返回主菜单..."
    read -n 1 -s
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${YELLOW}
 ___           _        _   _             
|_ _|_ __   __| | _____| \\ | | _____      __
 | || '_ \\ / _\` |/ _ \\\\|  \\| |/ _ \\ \\ /\\ / /
 | || | | | (_| |  __/| |\\  | (_) \\ V  V / 
|___|_| |_|\\__,_|\\___|_| \\_|\\___/ \\_/\\_/  
    ${NC}"
    echo -e "${GREEN}IndexNow - 快速通知搜索引擎网站内容更新啦${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${CYAN}1.${NC} 添加站点"
    echo -e "${CYAN}2.${NC} 提交站点地图"
    echo -e "${CYAN}3.${NC} 手动提交【单站点】"
    echo -e "${CYAN}4.${NC} 查看站点"
    echo -e "${CYAN}5.${NC} 更换端点"
    echo -e "${CYAN}6.${NC} 获取密钥指南"
    echo -e "${CYAN}7.${NC} 站点地图定时提交"
    echo -e "${CYAN}0.${NC} 退出"
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "当前端点: ${GREEN}$SEARCH_ENGINE${NC}"
    echo
}

# 主程序循环
while true; do
    show_main_menu
    read -p "$(echo -e ${CYAN}"请输入您的选择: "${NC})" choice

    case $choice in
        1) add_site;;
        2) submit_sitemap;;
        3) manual_submit;;
        4) view_sites;;
        5) change_endpoint;;
        6) show_key_guide;;
		7) task_mg;;
        0) echo -e "${YELLOW}感谢使用，再见！${NC}"; exit 0;;
        *) echo -e "${RED}无效的选择。请重试。${NC}";;
    esac

    echo
    read -n 1 -s -r -p "按任意键继续..."
done