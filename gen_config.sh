#!/bin/bash
#===============================================================================
# NginxPulse 配置生成器
# 功能：自动扫描日志中心目录，生成完整的 nginxpulse_config.json 配置文件
#===============================================================================

# 默认配置
LOG_BASE_PATH="${LOG_BASE_PATH:-/data/nginx_logs/active}"
OUTPUT_FILE="${OUTPUT_FILE:-nginxpulse_config.json}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

# 显示帮助
show_help() {
    cat << EOF
用法: $0 [选项]

选项:
  -p, --path PATH      日志基础路径 (默认: /data/nginx_logs/active)
  -o, --output FILE    输出文件名 (默认: nginxpulse_config.json)
  -h, --help           显示帮助信息

示例:
  $0                              # 使用默认配置
  $0 -p /var/log/nginx            # 指定自定义日志路径
  $0 -o /etc/nginxpulse/config.json  # 指定输出文件

EOF
}

# 从日志文件名提取站点信息
extract_site_info() {
    local filename="$1"
    local base_name

    # 去除 -access.log 或 -error.log 后缀
    base_name=$(echo "$filename" | sed -E 's/-(access|error)\.log.*$//')

    local domain="$base_name"

    # 提取根域名（去除 www. 前缀）
    local root_domain
    if [[ "$domain" =~ ^www\. ]]; then
        root_domain="${domain#www.}"
    else
        root_domain="$domain"
    fi

    # 提取站点名称（根域名的第一部分）
    local site_name
    site_name=$(echo "$root_domain" | cut -d. -f1)

    echo "$site_name|$domain|$root_domain"
}

# 扫描单个主机目录
scan_host_dir() {
    local host_dir="$1"
    local host_name
    host_name=$(basename "$host_dir")

    declare -A seen_sites

    for log_file in "$host_dir"/*-access.log; do
        [ -f "$log_file" ] || continue

        local filename
        filename=$(basename "$log_file")

        # 只处理 access.log 文件
        [[ "$filename" =~ -access\.log$ ]] || continue

        local site_info
        site_info=$(extract_site_info "$filename")

        local site_name domain root_domain
        IFS='|' read -r site_name domain root_domain <<< "$site_info"

        # 基于根域名去重
        if [[ -n "${seen_sites[$root_domain]}" ]]; then
            continue
        fi
        seen_sites[$root_domain]=1

        local log_path="${LOG_BASE_PATH}/${host_name}/${filename}*"

        # 构建 domains 数组
        local domains_json
        if [[ "$domain" == "$root_domain" ]]; then
            domains_json="[\"${root_domain}\"]"
        else
            domains_json="[\"${root_domain}\", \"${domain}\"]"
        fi

        echo "${site_name}|${log_path}|${domains_json}|${host_name}"
    done
}

# 生成站点 JSON 数组
generate_websites_json() {
    local sites=()

    # 扫描所有主机目录
    for host_dir in "$LOG_BASE_PATH"/*/; do
        [ -d "$host_dir" ] || continue

        while IFS='|' read -r site_name log_path domains_json host_name; do
            [ -n "$site_name" ] || continue
            sites+=("${site_name}|${log_path}|${domains_json}|${host_name}")
        done < <(scan_host_dir "$host_dir")
    done

    # 按站点名称排序
    IFS=$'\n' sorted_sites=($(sort -t'|' -k1 <<< "${sites[*]}"))
    unset IFS

    # 生成 JSON
    local first=true
    for i in "${!sorted_sites[@]}"; do
        IFS='|' read -r site_name log_path domains_json host_name <<< "${sorted_sites[$i]}"

        local formatted_domains
        formatted_domains=$(echo "$domains_json" | sed 's/,/, /g')

        if [ $i -lt $((${#sorted_sites[@]} - 1)) ]; then
            cat << EOF
    {
      "name": "${site_name}",
      "logPath": "${log_path}",
      "domains": ${formatted_domains}
    },
EOF
        else
            cat << EOF
    {
      "name": "${site_name}",
      "logPath": "${log_path}",
      "domains": ${formatted_domains}
    }
EOF
        fi
    done

    # 返回站点数量
    echo "${#sorted_sites[@]}" >&2
}

# 生成完整配置文件
generate_full_config() {
    local access_keys="$1"
    local websites_json
    local site_count

    # 捕获站点数量（从 stderr）和 JSON（从 stdout）
    websites_json=$(generate_websites_json 2>/tmp/site_count.tmp)
    site_count=$(cat /tmp/site_count.tmp 2>/dev/null || echo 0)
    rm -f /tmp/site_count.tmp

    # 格式化 accessKeys 数组
    local access_keys_json=""
    local first_key=true
    IFS=',' read -ra KEYS <<< "$access_keys"
    for key in "${KEYS[@]}"; do
        key=$(echo "$key" | xargs)
        if [ -n "$key" ]; then
            if [ "$first_key" = true ]; then
                access_keys_json="\"${key}\""
                first_key=false
            else
                access_keys_json="${access_keys_json}, \"${key}\""
            fi
        fi
    done

    # 生成完整配置 (适配最新模板)
    cat << EOF
{
  "websites": [
${websites_json}
  ],
  "system": {
    "logDestination": "file",
    "taskInterval": "1m",
    "logRetentionDays": 30,
    "parseBatchSize": 100,
    "ipGeoCacheLimit": 1000000,
    "ipGeoApiUrl": "http://ip-api.com/batch",
    "demoMode": false,
    "accessKeys": [${access_keys_json}],
    "language": "zh-CN"
  },
  "database": {
    "driver": "postgres",
    "dsn": "postgres://nginxpulse:nginxpulse@127.0.0.1:5432/nginxpulse?sslmode=disable",
    "maxOpenConns": 10,
    "maxIdleConns": 5,
    "connMaxLifetime": "30m"
  },
  "server": {
    "Port": ":8089"
  },
  "pvFilter": {
    "statusCodeInclude": [
      200
    ],
    "excludePatterns": [
      "favicon.ico$",
      "robots.txt$",
      "sitemap.xml$",
      "^/health$",
      "^/_(?:nuxt|next)/",
      "rss.xml$",
      "feed.xml$",
      "atom.xml$"
    ],
    "excludeIPs": [
      "127.0.0.1", 
      "::1", 
      "10.10.0.1", 
      "192.168.30.21"
    ]
  }
}
EOF
}

# 主函数
main() {
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--path)
                LOG_BASE_PATH="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 检查目录是否存在
    if [ ! -d "$LOG_BASE_PATH" ]; then
        print_error "日志目录不存在: $LOG_BASE_PATH"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           NginxPulse 配置生成器                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_info "日志扫描路径: $LOG_BASE_PATH"
    print_info "输出文件: $OUTPUT_FILE"

    # 统计主机数量
    local host_count=0
    for host_dir in "$LOG_BASE_PATH"/*/; do
        [ -d "$host_dir" ] && ((host_count++))
    done
    print_info "发现 $host_count 个主机目录"
    echo ""

    # 提示用户输入访问密钥
    echo -e "${YELLOW}请输入访问密钥 (accessKeys)${NC}"
    echo -e "${YELLOW}多个密钥用逗号分隔，例如: key1, key2, key3${NC}"
    echo ""
    read -p "访问密钥: " access_keys

    if [ -z "$access_keys" ]; then
        print_warning "未输入访问密钥，将使用默认值"
        access_keys="changeme"
    fi

    echo ""
    print_info "正在生成配置文件..."

    # 生成配置文件
    local config_content
    config_content=$(generate_full_config "$access_keys")

    # 统计站点数量
    local site_count
    site_count=$(echo "$config_content" | grep -c '"name":' || echo 0)

    # 保存到文件
    echo "$config_content" > "$OUTPUT_FILE"

    echo ""
    print_success "配置文件已生成: $OUTPUT_FILE"
    print_info "共配置 $site_count 个站点"
    echo ""

    # 显示生成的配置预览
    echo -e "${CYAN}========== 配置文件预览 ==========${NC}"
    echo ""
    cat "$OUTPUT_FILE"
    echo ""
    echo -e "${CYAN}==================================${NC}"
}

main "$@"
