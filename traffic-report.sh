#!/usr/bin/env bash
# ===== 流量日报脚本：统计流量并发送到 ntfy =====
# 每天 10:00 由 cron 调用：0 10 * * * /usr/local/bin/traffic-report.sh

# --- 配置 ---
NTFY_URL="https://ntfy.sh"   # ntfy 服务器地址
TOPIC="xxx"                  # 通知主题
IFACE="eth0"                 # 主网卡接口
HOST="$(hostname)"
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
# -------------

STAT_SRC="vnstat"
if command -v vnstat >/dev/null 2>&1 && vnstat --oneline -i "$IFACE" 2>/dev/null | grep -q '|'; then
    # 当月 rx|tx|total
    read -r MRX MTX MTOTAL <<< "$(vnstat --oneline -i "$IFACE" | awk -F';' '{split($5,a,"|"); print a[1], a[2], a[3]}')"
    # 今日 rx|tx|total
    read -r TRX TTX TTOTAL <<< "$(vnstat --oneline -i "$IFACE" | awk -F';' '{split($3,a,"|"); print a[1], a[2], a[3]}')"
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
