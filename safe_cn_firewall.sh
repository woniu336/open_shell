#!/bin/bash
# firewall_reverse_proxy_no_cdn.sh
# 功能：反代服务器防火墙（无CDN），仅允许中国大陆访问

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# === 检测工具 ===
if ! command -v ipset &> /dev/null; then
    echo -e "${RED}[ERROR] 未安装 ipset，正在自动安装...${NC}"
    apt-get update && apt-get install -y ipset || yum install -y ipset
fi

# === 自动检测 SSH 端口 ===
SSH_PORT=$(grep -E "^[[:space:]]*Port[[:space:]]+[0-9]+" /etc/ssh/sshd_config | awk '{print $2}' | tail -n1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=$(ss -tnlp | grep sshd | awk -F: '{print $2}' | awk '{print $1}' | head -n1)
fi
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi

HTTP_PORT=80
HTTPS_PORT=443

echo -e "${GREEN}[INFO] 检测到 SSH 端口：$SSH_PORT${NC}"

# === 清空旧规则 ===
echo -e "${YELLOW}[INFO] 清空旧防火墙规则...${NC}"
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 删除旧 ipset
ipset destroy china 2>/dev/null
ipset destroy cloudflare 2>/dev/null  # 删除不需要的CDN规则

# === 基础安全规则 ===
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT

# === 下载中国大陆IP段 ===
CN_IP_FILE="/tmp/china_ip.txt"
echo -e "${YELLOW}[INFO] 正在下载中国大陆IP段...${NC}"
curl -s https://ispip.clang.cn/all_cn.txt -o "$CN_IP_FILE"

if [ $? -ne 0 ] || [ ! -s "$CN_IP_FILE" ]; then
    echo -e "${RED}[ERROR] 无法下载中国IP列表！${NC}"
    ipset destroy china 2>/dev/null
    exit 1
fi

# === 创建并加载 ipset ===
echo -e "${YELLOW}[INFO] 创建 ipset 集合...${NC}"
ipset create china hash:net maxelem 10000

echo -e "${YELLOW}[INFO] 加载中国IP段到 ipset ($(wc -l < $CN_IP_FILE) 条)...${NC}"
while read ip; do
    ipset add china "$ip" 2>/dev/null
done < "$CN_IP_FILE"

# === 应用防火墙规则 ===
echo -e "${YELLOW}[INFO] 应用防火墙规则...${NC}"

# 仅允许中国IP访问 80/443
iptables -A INPUT -p tcp -m set --match-set china src --dport $HTTP_PORT -j ACCEPT
iptables -A INPUT -p tcp -m set --match-set china src --dport $HTTPS_PORT -j ACCEPT

# === 放行3x-ui端口（全球访问）===
iptables -A INPUT -p tcp --dport 33333 -j ACCEPT
iptables -A INPUT -p udp --dport 33333 -j ACCEPT
iptables -A INPUT -p tcp --dport 66666 -j ACCEPT
iptables -A INPUT -p udp --dport 66666 -j ACCEPT

# === 默认拒绝策略 ===
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# === 保存规则 ===
echo -e "${YELLOW}[INFO] 保存防火墙规则...${NC}"
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
ipset save > /etc/iptables/ipset.rules

# 创建开机自动加载
cat > /etc/network/if-pre-up.d/iptables-restore <<'EOF'
#!/bin/bash
ipset restore -f /etc/iptables/ipset.rules 2>/dev/null
iptables-restore < /etc/iptables/rules.v4 2>/dev/null
EOF
chmod +x /etc/network/if-pre-up.d/iptables-restore

# === 输出统计 ===
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       防火墙配置完成！                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo -e "${GREEN}[✓] SSH 端口：${NC}$SSH_PORT (全球可访问)"
echo -e "${GREEN}[✓] 中国IP段：${NC}$(ipset list china | wc -l) 条"
echo -e "${GREEN}[✓] Web端口：${NC}80/443 (仅中国大陆可访问)"
echo ""
echo -e "${YELLOW}[查看规则]${NC}"
echo "  iptables -L -n -v"
echo "  ipset list china"
echo ""
