#!/bin/bash

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

# 从sitemap提取URL的函数
extract_urls_from_sitemap() {
    curl -s "$1" | grep -oP '(?<=<loc>)https?://[^<]+'
}

# 提交多个URL的函数
submit_multiple_urls() {
    local host="$1"
    local key="$2"
    local search_engine="$3"
    shift 3
    local urls=("$@")
    
    # 将URL列表转换为JSON数组
    local url_json_array=$(printf '%s\n' "${urls[@]}" | jq -R . | jq -s .)
    
    # 准备JSON数据
    local json_data=$(jq -n \
                  --arg host "$host" \
                  --arg key "$key" \
                  --argjson urlList "$url_json_array" \
                  '{host: $host, key: $key, urlList: $urlList}')
    
    # 提交URL并获取状态码
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://${search_engine}/indexnow" \
         -H "Content-Type: application/json; charset=utf-8" \
         -d "$json_data")
    
    # 根据状态码输出结果
    case $status_code in
        200) echo "成功：URL已成功提交。" ;;
        202) echo "已接受：URL将稍后处理。" ;;
        400) echo "错误：无效请求。请检查您的参数。" ;;
        403) echo "错误：未授权。请验证您的API密钥。" ;;
        422) echo "错误：无法处理的实体。请检查您的JSON格式。" ;;
        429) echo "错误：请求过多。请稍后再试。" ;;
        *)   echo "意外的状态码：$status_code" ;;
    esac
}

# 检查必需的命令
for cmd in curl grep jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误：未找到必需的命令 '$cmd'。请安装它并重试。"
        exit 1
    fi
done

# 检查参数数量
if [ "$#" -ne 4 ]; then
    echo "用法: $0 <搜索引擎> <密钥> <主机> <sitemap_url>"
    exit 1
fi

search_engine="$1"
key="$2"
host="$3"
sitemap_url="$4"

# 提取URL
urls=($(extract_urls_from_sitemap "$sitemap_url"))
if [ ${#urls[@]} -eq 0 ]; then
    echo "在sitemap中未找到URL。"
    exit 1
fi

# 检查URL数量是否超过10000
if [ ${#urls[@]} -gt 10000 ]; then
    echo "警告：发现超过10,000个URL。仅提交前10,000个。"
    urls=("${urls[@]:0:10000}")
fi

# 提交URL
submit_multiple_urls "$host" "$key" "$search_engine" "${urls[@]}"