#!/usr/bin/env bash
# ===== 流量日报脚本：统计流量并发送到 ntfy =====
# 每天 10:00 由 cron 调用：0 10 * * * /usr/local/bin/traffic-report.sh

# --- 配置（按需修改） ---
NTFY_URL="https://ntfy.sh"   # 你的 ntfy 服务器地址
TOPIC="xxx"                  # 通知主题（每台服务器可不同，如 traffic-<主机名>）
IFACE="eth0"                      # 主网卡接口（ip -o link 查看）
HOST="$(hostname)"
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
# -------------------------

STAT_SRC="vnstat"
if command -v vnstat >/dev/null 2>&1 && LINE=$(vnstat --oneline -i "$IFACE" 2>/dev/null) && [[ "$LINE" == *";"* ]]; then
    # 兼容 vnstat 新旧两种 oneline 格式（每个值单独一行，避免单位空格被拆分）：
    #   旧格式(≤2.6): iface;date;day rx|tx|total;week rx|tx|total;month rx|tx|total;total...
    #   新格式(2.7+): [n;]iface;date;day_rx;day_tx;day_total;rate;month;m_rx;m_tx;m_total;m_rate;...
    { read -r TRX; read -r TTX; read -r TTOTAL; read -r MRX; read -r MTX; read -r MTOTAL; } <<< "$(echo "$LINE" | awk -F';' -v iface="$IFACE" '
        {
            if ($0 ~ /\|/) {
                split($3,d,"|"); split($5,m,"|");
                print d[1]; print d[2]; print d[3]; print m[1]; print m[2]; print m[3]
            } else {
                for (i=1;i<=NF;i++) if ($i==iface) break;
                print $(i+2); print $(i+3); print $(i+4); print $(i+7); print $(i+8); print $(i+9)
            }
        }')"
    # 空值保护（新装 vnstat 可能还没有当月数据）
    [ -z "$MRX" ] && MRX="N/A"; [ -z "$MTX" ] && MTX="N/A"; [ -z "$MTOTAL" ] && MTOTAL="N/A"
    [ -z "$TRX" ] && TRX="N/A"; [ -z "$TTX" ] && TTX="N/A"; [ -z "$TTOTAL" ] && TTOTAL="N/A"
else
    # 备用：/proc/net/dev（开机以来累计，重启清零）
    read -r RX TX <<< "$(awk -v i="$IFACE" -F'[: ]+' '$2==i {print $3, $11}' /proc/net/dev)"
    MRX="$(numfmt --to=iec "${RX:-0}")"
    MTX="$(numfmt --to=iec "${TX:-0}")"
    MTOTAL="$(numfmt --to=iec "$((RX+TX))")"
    TRX="N/A"; TTX="N/A"; TTOTAL="N/A"
    STAT_SRC="/proc/net/dev（重启清零）"
fi

MSG="📊 流量日报 - ${HOST} (${IP})
📥 接收: ${MRX}
📤 发送: ${MTX}
📈 今日合计: ${TTOTAL}（收 ${TRX} / 发 ${TTX}）
🗓 当月合计: ${MTOTAL}（收 ${MRX} / 发 ${MTX}）
⏰ 统计时间: $(date '+%Y-%m-%d %H:%M')（来源: ${STAT_SRC}）"

# 发送到 ntfy（带标题）
curl -s -H "Title: 流量通知" -H "Tags: chart_with_upwards_trend" \
     -d "$MSG" "$NTFY_URL/$TOPIC" >/dev/null && echo "✅ 已发送到主题 $TOPIC"
