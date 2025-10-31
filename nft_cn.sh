#!/bin/bash
# =========================================================
# firewall_nftables_china_dual_update.sh
# 功能：NFTables 双栈（IPv4 + IPv6）
#       仅允许中国大陆与 Cloudflare 访问 80/443
#       自动每日更新（含动态 Cloudflare IP 段）
# =========================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CN_IP_FILE="/tmp/cn.zone"
HTTP_PORT=80
HTTPS_PORT=443
UPDATE_SCRIPT="/usr/local/bin/update_china_nftables.sh"
CRON_JOB="0 4 * * * $UPDATE_SCRIPT >/dev/null 2>&1"

echo -e "${GREEN}========== 防火墙配置脚本（NFTables 双栈 + 自动更新）==========${NC}"

# === 安装依赖 ===
check_install() {
    local pkg=$1
    local cmd=$2
    [ -z "$cmd" ] && cmd=$pkg
    
    if ! command -v $cmd &>/dev/null; then
        echo -e "${YELLOW}[INFO] 未检测到 $pkg，正在安装...${NC}"
        apt-get update -y && apt-get install -y $pkg
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}[ERROR] 安装 $pkg 失败！${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[OK] 已安装：$pkg${NC}"
    fi
}

check_install nftables nft
check_install curl curl
check_install cron cron

# === 检测 SSH 端口 ===
SSH_PORT=$(grep -E "^[[:space:]]*Port[[:space:]]+[0-9]+" /etc/ssh/sshd_config | awk '{print $2}' | tail -n1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=$(ss -tnlp | grep sshd | awk -F: '{print $2}' | awk '{print $1}' | head -n1)
fi
[ -z "$SSH_PORT" ] && SSH_PORT=22
echo -e "${GREEN}[INFO] 检测到 SSH 端口：$SSH_PORT${NC}"

# === 下载中国 IPv4 段 ===
echo -e "${YELLOW}[INFO] 正在下载中国大陆 IPv4 段数据...${NC}"
curl -s https://www.ipdeny.com/ipblocks/data/countries/cn.zone -o "$CN_IP_FILE"
if [ $? -ne 0 ] || [ ! -s "$CN_IP_FILE" ]; then
    echo -e "${RED}[ERROR] 无法下载中国IP列表！${NC}"
    exit 1
fi

# === 清理旧的 NFTables 规则 ===
echo -e "${YELLOW}[INFO] 清理旧的 NFTables 规则...${NC}"
nft delete table inet filter 2>/dev/null || true

# === 创建 NFTables 表和链 ===
echo -e "${YELLOW}[INFO] 创建 NFTables 表和链...${NC}"
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0\; policy accept\; }

# === 创建 IPv4 集合并批量加载 ===
echo -e "${YELLOW}[INFO] 创建并加载 IPv4 集合...${NC}"
nft add set inet filter china_ipv4 { type ipv4_addr\; flags interval\; }

# 构建批量导入命令
{
    echo "add element inet filter china_ipv4 {"
    cat "$CN_IP_FILE" | sed 's/$/,/' | sed '$ s/,$//'
    echo "}"
} | nft -f -

# 添加 Cloudflare IPv4
{
    echo "add element inet filter china_ipv4 {"
    curl -fsSL https://www.cloudflare.com/ips-v4 | sed 's/$/,/' | sed '$ s/,$//'
    echo "}"
} | nft -f -

echo -e "${GREEN}[OK] IPv4 集合加载完成${NC}"

# === 创建 IPv6 集合并批量加载 ===
echo -e "${YELLOW}[INFO] 创建并加载 IPv6 集合...${NC}"
nft add set inet filter china_ipv6 { type ipv6_addr\; flags interval\; }

# 添加 Cloudflare IPv6
{
    echo "add element inet filter china_ipv6 {"
    curl -fsSL https://www.cloudflare.com/ips-v6 | sed 's/$/,/' | sed '$ s/,$//'
    echo "}"
} | nft -f -

echo -e "${GREEN}[OK] IPv6 集合加载完成 (含 Cloudflare IPv6 段)${NC}"

# === 添加防火墙规则 ===
echo -e "${YELLOW}[INFO] 添加防火墙规则...${NC}"

# 放行 SSH
nft add rule inet filter input tcp dport $SSH_PORT accept

# 放行已建立的连接
nft add rule inet filter input ct state established,related accept

# 放行本地回环
nft add rule inet filter input iif lo accept

# IPv4 规则：放行中国 + Cloudflare 访问 80/443
nft add rule inet filter input ip saddr @china_ipv4 tcp dport $HTTP_PORT accept
nft add rule inet filter input ip saddr @china_ipv4 tcp dport $HTTPS_PORT accept

# IPv6 规则：放行 Cloudflare 访问 80/443
nft add rule inet filter input ip6 saddr @china_ipv6 tcp dport $HTTP_PORT accept
nft add rule inet filter input ip6 saddr @china_ipv6 tcp dport $HTTPS_PORT accept

# 拒绝其他来源访问 80/443
nft add rule inet filter input tcp dport $HTTP_PORT drop
nft add rule inet filter input tcp dport $HTTPS_PORT drop

echo -e "${GREEN}[OK] 防火墙规则添加完成${NC}"

# === 保存规则 ===
echo -e "${YELLOW}[INFO] 保存 NFTables 规则...${NC}"
mkdir -p /etc/nftables
nft list ruleset > /etc/nftables/nftables.rules

# === 配置开机自启 ===
cat >/etc/systemd/system/nftables-restore.service <<'EOF'
[Unit]
Description=Restore nftables firewall rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables/nftables.rules

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nftables-restore.service
echo -e "${GREEN}[OK] NFTables 开机自启已配置${NC}"

# === 创建自动更新脚本 ===
cat >"$UPDATE_SCRIPT" <<'UPDATEEOF'
#!/bin/bash
CN_IP_FILE="/tmp/cn.zone"

# 下载中国 IPv4 段
curl -s https://www.ipdeny.com/ipblocks/data/countries/cn.zone -o "$CN_IP_FILE"
[ $? -ne 0 ] || [ ! -s "$CN_IP_FILE" ] && exit 1

# 清空并批量重新加载 IPv4 集合
nft flush set inet filter china_ipv4

{
    echo "add element inet filter china_ipv4 {"
    cat "$CN_IP_FILE" | sed 's/$/,/' | sed '$ s/,$//'
    echo "}"
} | nft -f -

# 添加 Cloudflare IPv4
{
    echo "add element inet filter china_ipv4 {"
    curl -fsSL https://www.cloudflare.com/ips-v4 | sed 's/$/,/' | sed '$ s/,$//'
    echo "}"
} | nft -f -

# 清空并批量重新加载 IPv6 集合
nft flush set inet filter china_ipv6

# 添加 Cloudflare IPv6
{
    echo "add element inet filter china_ipv6 {"
    curl -fsSL https://www.cloudflare.com/ips-v6 | sed 's/$/,/' | sed '$ s/,$//'
    echo "}"
} | nft -f -

# 保存规则
nft list ruleset > /etc/nftables/nftables.rules
UPDATEEOF

chmod +x "$UPDATE_SCRIPT"
echo -e "${GREEN}[OK] 自动更新脚本已创建：$UPDATE_SCRIPT${NC}"

# === 检查并添加定时任务 ===
if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT"; then
    echo -e "${YELLOW}[INFO] 已存在每日更新任务，跳过添加${NC}"
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}[OK] 已添加每日凌晨4点自动更新任务${NC}"
fi

# === 输出结果 ===
echo -e "\n${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ 防火墙（NFTables IPv4+IPv6 + 自动更新）║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo -e "${GREEN}[✓] SSH 端口：${NC}$SSH_PORT"
echo -e "${GREEN}[✓] 中国 + Cloudflare IPv4：${NC}已加载"
echo -e "${GREEN}[✓] IPv6 Cloudflare 集合：${NC}已加载"
echo -e "${GREEN}[✓] Web端口：${NC}80/443 (仅中国大陆 + Cloudflare 可访问)"
echo -e "${GREEN}[✓] 每日更新任务：${NC}$(crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT" && echo "已启用" || echo "未启用")"
echo ""
echo -e "${YELLOW}[查看规则集]${NC} nft list ruleset"
echo -e "${YELLOW}[查看 IPv4 集合]${NC} nft list set inet filter china_ipv4"
echo -e "${YELLOW}[查看 IPv6 集合]${NC} nft list set inet filter china_ipv6"
echo -e "${YELLOW}[查看计划任务]${NC} crontab -l"
echo -e "${YELLOW}[手动更新]${NC} $UPDATE_SCRIPT"
echo ""
