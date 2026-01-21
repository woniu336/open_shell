#!/bin/bash
#===============================================================================
# 日志站点配置生成器
# 功能：自动扫描日志中心目录，生成站点配置 JSON 数组
#===============================================================================

# 默认配置
LOG_BASE_PATH="${LOG_BASE_PATH:-/data/nginx_logs/active}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
PRETTY_PRINT="${PRETTY_PRINT:-true}"

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

# 显示帮助
show_help() {
    cat << EOF
用法: $0 [选项]

选项:
  -p, --path PATH      日志基础路径 (默认: /data/nginx_logs/active)
  -o, --output FILE    输出到文件 (默认: 标准输出)
  -c, --compact        紧凑 JSON 格式 (不换行)
  -h, --help           显示帮助信息

示例:
  $0                           # 扫描默认路径，输出到终端
  $0 -p /var/log/nginx         # 指定自定义路径
  $0 -o sites.json             # 输出到文件
  $0 -c                        # 紧凑格式输出

输出格式:
  [
    {
      "name": "1234",
      "logPath": "/data/nginx_logs/active/DMIT-npuynZY6S0/www.1234.com-access.log*",
      "domains": ["1234.com", "www.1234.com"]
    },
    ...
  ]
EOF
}

# 从日志文件名提取站点信息
# 输入: www.1234.com-access.log
# 输出: name=1234, domain=www.1234.com, root_domain=1234.com
extract_site_info() {
    local filename="$1"
    local base_name

    # 去除 -access.log 或 -error.log 后缀
    base_name=$(echo "$filename" | sed -E 's/-(access|error)\.log.*$//')

    # 提取域名
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

# 检查是否为有效的日志文件
is_valid_log_file() {
    local filename="$1"
    # 只处理 access.log 文件，排除轮转的 .gz 文件和 error.log
    [[ "$filename" =~ -access\.log$ ]]
}

# 扫描单个主机目录
scan_host_dir() {
    local host_dir="$1"
    local host_name
    host_name=$(basename "$host_dir")

    # 用于去重的关联数组
    declare -A seen_sites

    # 遍历日志文件
    for log_file in "$host_dir"/*-access.log; do
        [ -f "$log_file" ] || continue

        local filename
        filename=$(basename "$log_file")

        if ! is_valid_log_file "$filename"; then
            continue
        fi

        local site_info
        site_info=$(extract_site_info "$filename")

        local site_name domain root_domain
        IFS='|' read -r site_name domain root_domain <<< "$site_info"

        # 跳过已处理的站点（基于根域名去重）
        if [[ -n "${seen_sites[$root_domain]}" ]]; then
            continue
        fi
        seen_sites[$root_domain]=1

        # 构建 logPath
        local log_path="${LOG_BASE_PATH}/${host_name}/${filename}*"

        # 构建 domains 数组
        local domains_json
        if [[ "$domain" == "$root_domain" ]]; then
            # 没有 www 前缀，只有一个域名
            domains_json="[\"${root_domain}\"]"
        else
            # 有 www 前缀，包含两个域名
            domains_json="[\"${root_domain}\", \"${domain}\"]"
        fi

        # 输出站点信息（内部格式）
        echo "${site_name}|${log_path}|${domains_json}|${host_name}"
    done
}

# 生成 JSON 输出
generate_json() {
    local sites=()
    local first=true

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
    if [ "$PRETTY_PRINT" = "true" ]; then
        echo "["
        for i in "${!sorted_sites[@]}"; do
            IFS='|' read -r site_name log_path domains_json host_name <<< "${sorted_sites[$i]}"

            # 格式化 domains 数组
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
        echo "]"
    else
        # 紧凑格式
        local json_output="["
        for i in "${!sorted_sites[@]}"; do
            IFS='|' read -r site_name log_path domains_json host_name <<< "${sorted_sites[$i]}"

            json_output+="{\"name\":\"${site_name}\",\"logPath\":\"${log_path}\",\"domains\":${domains_json}}"

            if [ $i -lt $((${#sorted_sites[@]} - 1)) ]; then
                json_output+=","
            fi
        done
        json_output+="]"
        echo "$json_output"
    fi
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
            -c|--compact)
                PRETTY_PRINT="false"
                shift
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

    print_info "扫描日志目录: $LOG_BASE_PATH"

    # 统计主机数量
    local host_count=0
    for host_dir in "$LOG_BASE_PATH"/*/; do
        [ -d "$host_dir" ] && ((host_count++))
    done
    print_info "发现 $host_count 个主机目录"

    # 生成 JSON
    local json_output
    json_output=$(generate_json)

    # 统计站点数量
    local site_count
    site_count=$(echo "$json_output" | grep -c '"name"' || echo 0)
    print_info "共生成 $site_count 个站点配置"

    # 输出结果
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$json_output" > "$OUTPUT_FILE"
        print_success "配置已保存到: $OUTPUT_FILE"
    else
        echo ""
        echo "$json_output"
    fi
}

main "$@"
