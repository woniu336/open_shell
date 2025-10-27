#!/bin/bash
# ============================================
# RClone 同步服务管理脚本
# 用于查看、启动、停止、重启、查看日志
# ============================================

# 检查输入参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <RCLONE_REMOTE>"
    echo "例如: $0 vmrack:/www/wwwroot/blog"
    exit 1
fi

RCLONE_REMOTE="$1"

# 生成服务名称（与主同步脚本一致）
SERVICE_NAME=$(echo "${RCLONE_REMOTE}" | sed 's/[:/\.]/_/g')
UNIT_NAME="rclone_sync_${SERVICE_NAME}.service"

# 菜单
echo "=========================================="
echo "  RClone 服务管理"
echo "=========================================="
echo "1) 查看状态"
echo "2) 启动服务"
echo "3) 停止服务"
echo "4) 重启服务"
echo "5) 查看日志 (实时)"
echo "6) 退出"
echo "=========================================="
read -p "请输入操作编号: " CHOICE

case $CHOICE in
    1)
        systemctl --user status ${UNIT_NAME}
        ;;
    2)
        systemctl --user start ${UNIT_NAME}
        echo "✅ 已启动 ${UNIT_NAME}"
        ;;
    3)
        systemctl --user stop ${UNIT_NAME}
        echo "🛑 已停止 ${UNIT_NAME}"
        ;;
    4)
        systemctl --user restart ${UNIT_NAME}
        echo "🔁 已重启 ${UNIT_NAME}"
        ;;
    5)
        echo "📜 正在实时查看日志（Ctrl+C 退出）..."
        journalctl --user -u ${UNIT_NAME} -f
        ;;
    6)
        echo "已退出。"
        ;;
    *)
        echo "无效输入。"
        ;;
esac
