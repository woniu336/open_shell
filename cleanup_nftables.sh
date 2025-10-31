#!/bin/bash
# ==========================================
# 一键清除 nftables 规则 + systemd + 定时任务
# ==========================================
set -e

echo "=========================================="
echo " 🔥 开始清理 NFTables 规则和相关配置..."
echo "=========================================="

# ---------- 1. 清理 NFTables 规则 ----------
echo " - 清理 NFTables 规则表..."
if nft list tables 2>/dev/null | grep -q "inet filter"; then
    echo "   删除 inet filter 表"
    nft delete table inet filter 2>/dev/null || true
else
    echo "   未发现 inet filter 表，跳过"
fi

# ---------- 2. 清理 systemd 服务 ----------
if systemctl list-unit-files 2>/dev/null | grep -q "nftables-restore.service"; then
    echo " - 停止并删除 systemd 服务：nftables-restore.service"
    systemctl stop nftables-restore.service 2>/dev/null || true
    systemctl disable nftables-restore.service 2>/dev/null || true
    rm -f /etc/systemd/system/nftables-restore.service
    systemctl daemon-reload
else
    echo " - 未发现 nftables-restore.service，跳过"
fi

# ---------- 3. 删除保存文件 ----------
if [ -f /etc/nftables/nftables.rules ]; then
    echo " - 删除保存的 nftables 规则文件"
    rm -f /etc/nftables/nftables.rules
fi

# ---------- 4. 清理定时任务 ----------
echo " - 检查并清理相关定时任务..."
if crontab -l 2>/dev/null | grep -q "update_china_nftables.sh"; then
    crontab -l 2>/dev/null | grep -v "update_china_nftables.sh" | crontab - || true
    echo "   已清理定时任务"
else
    echo "   无定时任务需要清理"
fi

# ---------- 5. 删除更新脚本 ----------
if [ -f /usr/local/bin/update_china_nftables.sh ]; then
    echo " - 删除更新脚本"
    rm -f /usr/local/bin/update_china_nftables.sh
fi

# ---------- 6. 创建空白规则集（允许所有流量）----------
echo " - 创建开放的防火墙规则..."
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0\; policy accept\; }

echo "   ✓ 已创建允许所有流量的规则"

# ---------- 7. 保存当前规则 ----------
mkdir -p /etc/nftables
nft list ruleset > /etc/nftables/nftables.rules

# ---------- 8. 展示最终结果 ----------
echo ""
echo "=========================================="
echo " ✅ 清理完成！最终状态："
echo "=========================================="
echo ""
echo "--- 当前 NFTables 规则 ---"
nft list ruleset
echo ""
echo "=========================================="
echo " ✅ 所有 DROP 规则已彻底删除"
echo " ✅ 防火墙已恢复为允许所有流量"
echo " ✅ 80/443 端口现已完全开放"
echo "=========================================="
echo ""
