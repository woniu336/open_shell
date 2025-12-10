#!/bin/bash

# 封禁 GPTBot 爬虫脚本
# 使用独立的 ipset 集合

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
URL="https://openai.com/gptbot.json"
IPSET_NAME="gptbot_blacklist"
TMP_FILE="/tmp/gptbot_ips.txt"
IPSET_CONF="/etc/ipset.conf"
IPTABLES_RULES="/etc/iptables.rules"

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}  封禁 GPTBot 爬虫${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# 下载 JSON
echo -e "${YELLOW}正在从 OpenAI 下载 GPTBot IP 列表...${NC}"
json=$(curl -s "$URL")

if [ -z "$json" ]; then
    echo -e "${RED}✗ 下载失败，无法访问 $URL${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 下载完成${NC}"

# 提取 IPv4 前缀
echo -e "${YELLOW}正在提取 IPv4 网段...${NC}"
echo "$json" \
    | grep -Eo '"ipv4Prefix"\s*:\s*"[^"]+"' \
    | sed -E 's/"ipv4Prefix"\s*:\s*"([^"]+)"/\1/' > "$TMP_FILE"

# 检查提取结果
if [ ! -s "$TMP_FILE" ]; then
    echo -e "${RED}✗ 未能提取到任何 IP 网段${NC}"
    rm -f "$TMP_FILE"
    exit 1
fi

network_count=$(wc -l < "$TMP_FILE")
echo -e "${GREEN}✓ 提取到 $network_count 个网段${NC}"
echo ""

# 检查 ipset 集合是否存在
if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}创建 ipset 集合: $IPSET_NAME (hash:net)${NC}"
    ipset create "$IPSET_NAME" hash:net timeout 0
    echo -e "${GREEN}✓ 集合创建完成${NC}"
    echo ""
else
    echo -e "${GREEN}✓ 使用现有集合: $IPSET_NAME${NC}"
    echo ""
fi

# 检查 iptables 规则
if ! iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
    echo -e "${YELLOW}添加 iptables 规则...${NC}"
    iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP
    echo -e "${GREEN}✓ iptables 规则已添加${NC}"
    echo ""
fi

# 导入 IPv4 网段
echo -e "${YELLOW}正在导入 GPTBot IPv4 网段...${NC}"
echo ""

success_count=0
skip_count=0
fail_count=0

while read -r ip; do
    # 跳过空行
    [[ -z "$ip" ]] && continue
    
    # 检查是否已存在
    if ipset test "$IPSET_NAME" "$ip" 2>/dev/null; then
        echo -e "${YELLOW}⚠ 已存在: $ip${NC}"
        skip_count=$((skip_count + 1))
        continue
    fi
    
    # 添加到黑名单
    if ipset add "$IPSET_NAME" "$ip" 2>/dev/null; then
        echo -e "${GREEN}✓ 已封禁: $ip${NC}"
        success_count=$((success_count + 1))
    else
        echo -e "${RED}✗ 失败: $ip${NC}"
        fail_count=$((fail_count + 1))
    fi
done < "$TMP_FILE"

# 删除临时文件
rm -f "$TMP_FILE"

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}总计: $network_count 个网段${NC}"
echo -e "${GREEN}✓ 成功封禁: $success_count${NC}"
echo -e "${YELLOW}⚠ 已存在跳过: $skip_count${NC}"
echo -e "${RED}✗ 失败: $fail_count${NC}"
echo -e "${BLUE}================================${NC}"

# 保存规则
if [ $success_count -gt 0 ] || [ $skip_count -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}正在保存规则...${NC}"
    
    # 保存 ipset 规则
    ipset save > "$IPSET_CONF"
    
    # 保存 iptables 规则
    iptables-save > "$IPTABLES_RULES"
    
    echo -e "${GREEN}✓ 规则已保存${NC}"
    echo -e "${GREEN}✓ GPTBot 爬虫已成功屏蔽！${NC}"
fi

echo ""
echo -e "${BLUE}当前封禁统计:${NC}"
gptbot_entries=$(ipset list "$IPSET_NAME" | grep -E "^[0-9]" | wc -l)
echo -e "${GREEN}GPTBot 集合 ($IPSET_NAME): $gptbot_entries 个网段${NC}"

# 如果主黑名单集合存在，也显示其统计
if ipset list "blacklist" >/dev/null 2>&1; then
    blacklist_entries=$(ipset list "blacklist" | grep -E "^[0-9]" | wc -l)
    echo -e "${GREEN}主黑名单 (blacklist): $blacklist_entries 个IP/网段${NC}"
fi

echo ""
echo -e "${BLUE}查看 GPTBot 黑名单: ${NC}ipset list $IPSET_NAME"
echo -e "${BLUE}删除 GPTBot 黑名单: ${NC}ipset destroy $IPSET_NAME"
