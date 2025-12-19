#!/bin/bash
#==============================================================================
# 中国 IP 白名单自动化部署脚本
# 功能：自动生成并更新中国大陆 IP 段，配置 Nginx 访问控制
# 适用：非 CDN 场景，直接在源站 Nginx 实现地域拦截
#==============================================================================

set -e  # 遇到错误立即退出

# ==================== 配置区域 ====================
NGINX_CONF_DIR="/etc/nginx/conf.d"
SCRIPTS_DIR="/usr/local/bin"
CHINA_IPV4_FILE="$NGINX_CONF_DIR/china-ipv4.conf"
CHINA_IPV6_FILE="$NGINX_CONF_DIR/china-ipv6.conf"
BING_BOT_FILE="$NGINX_CONF_DIR/bing-bot.conf"

# Nginx 重载命令（根据实际情况选择）
# Docker 版本使用：docker exec nginx nginx -s reload
# 系统版本使用：nginx -s reload
NGINX_RELOAD_CMD="nginx -s reload"  # 修改这里以适配你的环境
NGINX_TEST_CMD="nginx -t"

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== 环境检查 ====================
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v wget &> /dev/null; then
        log_error "未找到 wget，请先安装：apt install wget 或 yum install wget"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_warn "未找到 python3，必应爬虫 IP 更新功能将不可用"
    fi
    
    if ! command -v nginx &> /dev/null; then
        log_error "未找到 Nginx 命令，请检查 Nginx 是否已正确安装"
        exit 1
    fi
    
    log_info "✅ Nginx 版本: $(nginx -v 2>&1 | head -1)"
}

# ==================== 创建目录 ====================
setup_directories() {
    log_info "创建必要的目录..."
    mkdir -p "$NGINX_CONF_DIR"
    mkdir -p "$SCRIPTS_DIR"
}

# ==================== 生成中国 IP 白名单脚本 ====================
create_cn_ip_script() {
    log_info "创建中国 IP 白名单生成脚本..."
    
    cat > "$SCRIPTS_DIR/gen-cn-allow.sh" << 'SCRIPT_EOF'
#!/bin/bash
# 从 APNIC 官方数据生成中国 IP 白名单

OUTPUT_DIR="/etc/nginx/conf.d"
TEMP_FILE="/tmp/cn_allow_$$.list"

echo "正在下载 APNIC 最新数据..."

# 下载并解析 IP 数据
if ! wget -qO- http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest | \
awk -F'|' '
  $2 == "CN" && $3 == "ipv4" {
    prefix = $4;
    len = 32 - log($5) / log(2);
    print "allow " prefix "/" len ";";
  }
  $2 == "CN" && $3 == "ipv6" {
    print "allow " $4 "/" $5 ";";
  }
' > "$TEMP_FILE"; then
    echo "❌ 下载失败，请检查网络连接"
    exit 1
fi

# 分离 IPv4 和 IPv6
grep -E 'allow [0-9]+\.' "$TEMP_FILE" > "$OUTPUT_DIR/china-ipv4.conf"
grep -E 'allow [0-9a-fA-F:]+' "$TEMP_FILE" > "$OUTPUT_DIR/china-ipv6.conf"

# 添加注释头
sed -i "1i# Auto-generated from APNIC — $(date '+%Y-%m-%d %H:%M:%S')" "$OUTPUT_DIR/china-ipv4.conf"
sed -i "1i# Auto-generated from APNIC — $(date '+%Y-%m-%d %H:%M:%S')" "$OUTPUT_DIR/china-ipv6.conf"

# 统计规则数量
ipv4_count=$(grep -c "^allow" "$OUTPUT_DIR/china-ipv4.conf")
ipv6_count=$(grep -c "^allow" "$OUTPUT_DIR/china-ipv6.conf")

rm -f "$TEMP_FILE"

echo "✅ 中国 IP 白名单已生成："
echo "   IPv4: $OUTPUT_DIR/china-ipv4.conf ($ipv4_count 条规则)"
echo "   IPv6: $OUTPUT_DIR/china-ipv6.conf ($ipv6_count 条规则)"
SCRIPT_EOF

    chmod +x "$SCRIPTS_DIR/gen-cn-allow.sh"
    log_info "✅ 脚本已创建: $SCRIPTS_DIR/gen-cn-allow.sh"
}

# ==================== 生成必应爬虫 IP 更新脚本 ====================
create_bing_ip_script() {
    log_info "创建必应爬虫 IP 更新脚本..."
    
    cat > "$SCRIPTS_DIR/update-bing-ips.sh" << 'SCRIPT_EOF'
#!/bin/bash
OUTPUT="/etc/nginx/conf.d/bing-bot.conf"

echo "正在从必应官方获取最新 IP 段..."

# 使用 Python 解析 JSON
if ! command -v python3 &> /dev/null; then
    echo "❌ 未找到 python3，无法更新必应 IP"
    exit 1
fi

if ! curl -s "https://www.bing.com/toolbox/bingbot.json" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    print('# Bing Bot IP Ranges - Updated:', '$(date +"%Y-%m-%d %H:%M:%S")')
    print('# Source: https://www.bing.com/toolbox/bingbot.json')
    print()
    
    for prefix in data.get('prefixes', []):
        if 'ipv4Prefix' in prefix:
            print(f\"allow {prefix['ipv4Prefix']};\")
        if 'ipv6Prefix' in prefix:
            print(f\"allow {prefix['ipv6Prefix']};\")
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" > "$OUTPUT"; then
    echo "❌ 必应 IP 更新失败"
    exit 1
fi

# 统计规则数量
count=$(grep -c "^allow" "$OUTPUT")
echo "✅ 必应爬虫 IP 已更新: $OUTPUT"
echo "   共 $count 条规则"

# 验证并重载 Nginx
if nginx -t 2>&1 | grep -q "successful"; then
    nginx -s reload
    echo "✅ Nginx 配置已重载"
else
    echo "❌ Nginx 配置验证失败"
    exit 1
fi
SCRIPT_EOF

    chmod +x "$SCRIPTS_DIR/update-bing-ips.sh"
    log_info "✅ 脚本已创建: $SCRIPTS_DIR/update-bing-ips.sh"
}

# ==================== 初始化 IP 白名单 ====================
initialize_ip_lists() {
    log_info "首次生成 IP 白名单..."
    
    # 生成中国 IP
    "$SCRIPTS_DIR/gen-cn-allow.sh"
    
    # 生成必应 IP（如果 python3 可用）
    if command -v python3 &> /dev/null; then
        "$SCRIPTS_DIR/update-bing-ips.sh" || log_warn "必应 IP 更新失败，已跳过"
    else
        log_warn "跳过必应 IP 更新（需要 python3）"
        # 创建空文件避免 Nginx 配置报错
        touch "$BING_BOT_FILE"
        echo "# Bing Bot placeholder - python3 required for auto-update" > "$BING_BOT_FILE"
    fi
}

# ==================== 设置定时任务 ====================
setup_cron_jobs() {
    log_info "设置定时任务..."
    
    # 删除旧的定时任务
    rm -f /etc/cron.d/update-cn-ip
    
    # 创建新的定时任务文件
    cat > /etc/cron.d/update-cn-ip << 'CRON_EOF'
# 每天凌晨 3 点更新中国 IP 段
0 3 * * * root /usr/local/bin/gen-cn-allow.sh && nginx -t && nginx -s reload >/dev/null 2>&1

# 每月 15 号凌晨 4 点更新必应爬虫 IP
0 4 15 * * root /usr/local/bin/update-bing-ips.sh >/dev/null 2>&1
CRON_EOF

    chmod 644 /etc/cron.d/update-cn-ip
    log_info "✅ 定时任务已创建: /etc/cron.d/update-cn-ip"
}

# ==================== 生成 Nginx 配置示例 ====================
generate_nginx_example() {
    log_info "生成 Nginx 配置示例..."
    
    cat > "$NGINX_CONF_DIR/example-site.conf.sample" << 'NGINX_EOF'
# ====================================================================
# Nginx 站点配置示例 - 中国 IP 白名单
# 使用方法：复制此文件为实际站点配置，修改 server_name 和证书路径
# ====================================================================

server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name example.com www.example.com;
    
    # SSL 证书配置（修改为实际路径）
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # ========== 访问控制规则（顺序很重要！）==========
    # 1. 首先放行必应爬虫（可选，用于 SEO）
    include /etc/nginx/conf.d/bing-bot.conf;
    
    # 2. 然后放行中国大陆 IP
    include /etc/nginx/conf.d/china-ipv4.conf;
    include /etc/nginx/conf.d/china-ipv6.conf;
    
    # 3. 放行本地回环（避免本地测试被拦截）
    allow 127.0.0.1;
    allow ::1;
    
    # 4. ⚠️ 最后拒绝所有未匹配的请求（必须放最后）
    deny all;
    # ==============================================
    
    # HTTP 自动跳转 HTTPS
    if ($scheme = http) {
        return 301 https://$host$request_uri;
    }
    
    # 网站根目录
    root /var/www/html;
    index index.html index.htm;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # 访问日志
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
NGINX_EOF

    log_info "✅ 配置示例已创建: $NGINX_CONF_DIR/example-site.conf.sample"
}

# ==================== 主函数 ====================
main() {
    echo "======================================================================"
    echo "  中国 IP 白名单自动化部署脚本 (Nginx)"
    echo "  配置文件目录: $NGINX_CONF_DIR"
    echo "======================================================================"
    echo ""
    
    check_dependencies
    setup_directories
    create_cn_ip_script
    create_bing_ip_script
    initialize_ip_lists
    setup_cron_jobs
    generate_nginx_example
    
    echo ""
    echo "======================================================================"
    log_info "✅ 部署完成！"
    echo "======================================================================"
    echo ""
    echo "📋 后续步骤："
    echo "  1. 编辑你的 Nginx 站点配置文件"
    echo "     (通常在 /etc/nginx/conf.d/ 目录下)"
    echo ""
    echo "  2. 在 server 块中添加以下配置："
    echo "     (参考 $NGINX_CONF_DIR/example-site.conf.sample)"
    echo ""
    echo "     include /etc/nginx/conf.d/bing-bot.conf;"
    echo "     include /etc/nginx/conf.d/china-ipv4.conf;"
    echo "     include /etc/nginx/conf.d/china-ipv6.conf;"
    echo "     allow 127.0.0.1;"
    echo "     allow ::1;"
    echo "     deny all;"
    echo ""
    echo "  3. 验证配置: nginx -t"
    echo "  4. 重载配置: nginx -s reload"
    echo ""
    echo "📊 生成的文件："
    echo "  - IPv4 规则: $CHINA_IPV4_FILE"
    echo "  - IPv6 规则: $CHINA_IPV6_FILE"
    echo "  - 必应爬虫: $BING_BOT_FILE"
    echo "  - 配置示例: $NGINX_CONF_DIR/example-site.conf.sample"
    echo ""
    echo "⏰ 定时任务："
    echo "  - 每天 03:00 更新中国 IP"
    echo "  - 每月 15 号 04:00 更新必应 IP"
    echo ""
    echo "🧪 测试方法："
    echo "  - 国内访问应正常"
    echo "  - 境外访问应返回 403 Forbidden"
    echo ""
}

main "$@"
