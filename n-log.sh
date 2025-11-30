#!/bin/bash
# nginx_log_analyzer.sh - 改进版

LOG_FILE="/home/web/log/nginx/access.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Nginx访问日志分析 ===${NC}"

# 检查日志文件是否存在
if [[ ! -f "$LOG_FILE" ]]; then
    echo -e "${RED}错误: 日志文件 $LOG_FILE 不存在${NC}"
    exit 1
fi

# 检查文件是否可读
if [[ ! -r "$LOG_FILE" ]]; then
    echo -e "${RED}错误: 没有权限读取日志文件${NC}"
    exit 1
fi

echo -e "\n${YELLOW}1. 总请求数:${NC} $(wc -l < "$LOG_FILE")"

echo -e "\n${YELLOW}2. 状态码统计:${NC}"
awk '{
    # 只处理有效的HTTP状态码（数字）
    if ($9 ~ /^[0-9]+$/) {
        print $9
    }
}' "$LOG_FILE" | sort | uniq -c | sort -rn | head -15

echo -e "\n${YELLOW}3. 最频繁访问IP (Top 10):${NC}"
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -rn | head -10

echo -e "\n${YELLOW}4. 最热门HTML页面 (Top 15):${NC}"
awk '{
    url = $7
    # 只统计HTML页面：包含.html或以/结尾的路径（不包括静态资源）
    if (url ~ /\.html$/ || (url ~ /\/$/ && url !~ /\.(css|js|jpg|jpeg|png|gif|ico|svg|woff|woff2|ttf|eot|mp4|webp|xml|json)$/)) {
        print url
    }
}' "$LOG_FILE" | sort | uniq -c | sort -rn | head -15

echo -e "\n${YELLOW}5. 流量统计:${NC}"
awk '{
    # 只累加有效的数字字节数
    if ($10 ~ /^[0-9]+$/) {
        sum += $10
        count++
    }
} END {
    if (count > 0) {
        printf "总流量: %.2f MB\n", sum/1024/1024
        printf "平均响应大小: %.2f KB\n", sum/count/1024
        printf "有效响应数: %d\n", count
    } else {
        print "无有效流量数据"
    }
}' "$LOG_FILE"

echo -e "\n${YELLOW}6. 异常状态码统计:${NC}"
awk '{
    if ($9 ~ /^[0-9]+$/) {
        code = $9
        if (code >= 400) {
            print code
        }
    }
}' "$LOG_FILE" | sort | uniq -c | sort -rn | head -10

echo -e "\n${YELLOW}7. 请求方法统计:${NC}"
awk '{
    if ($6 ~ /^"[A-Z]+$/) {
        # 提取请求方法 (GET, POST, etc.)
        method = substr($6, 2)
        print method
    }
}' "$LOG_FILE" | sort | uniq -c | sort -rn

echo -e "\n${YELLOW}8. Top 10 爬虫/Bot User-Agent:${NC}"
awk -F'"' '{
    if (NF >= 6) {
        ua = $6
        # 检测常见的爬虫标识
        if (ua ~ /bot|spider|crawl|slurp|scraper|curl|wget|python|java|go-http|axios|okhttp|apache-httpclient/i) {
            print ua
        }
    }
}' "$LOG_FILE" | sort | uniq -c | sort -rn | head -10

echo -e "\n${GREEN}=== 分析完成 ===${NC}"
