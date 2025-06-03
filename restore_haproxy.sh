#!/bin/bash
set -e

# 检查 HAProxy 是否安装
check_haproxy_installed() {
    if ! command -v haproxy >/dev/null 2>&1; then
        echo "haproxy 未安装，正在安装..."
        apt update && apt install haproxy -y
        systemctl start haproxy
        systemctl enable haproxy
    fi
}

# 备份 HAProxy 配置
backup_haproxy() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="./haproxy_backup_${TIMESTAMP}.tar.gz"
    echo "📦 正在备份当前配置到：${BACKUP_FILE##*/}"
    tar -czf "$BACKUP_FILE" /etc/haproxy/certs /etc/haproxy/haproxy.cfg >/dev/null 2>&1
    echo "✅ 备份完成：${BACKUP_FILE##*/}"
}

# 恢复 HAProxy 配置
restore_haproxy() {
    BACKUPS=($(ls ./haproxy_backup_*.tar.gz 2>/dev/null))
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "❌ 未找到任何备份文件。"
        return
    fi
    
    echo ""
    echo "📁 可用的备份文件："
    echo "┌─────────────────────────────────────────┐"
    for i in "${!BACKUPS[@]}"; do
        echo "│ $((i + 1))) ${BACKUPS[$i]##*/}"
    done
    echo "│ 0) 返回主菜单                          │"
    echo "└─────────────────────────────────────────┘"
    echo ""
    read -p "🔢 请输入你要恢复的编号: " CHOICE
    
    if [[ "$CHOICE" == "0" ]]; then
        echo "🔙 返回主菜单"
        return
    elif [[ "$CHOICE" -ge 1 && "$CHOICE" -le ${#BACKUPS[@]} ]]; then
        SELECTED_BACKUP="${BACKUPS[$((CHOICE - 1))]}"
        echo "✅ 已选择备份：${SELECTED_BACKUP##*/}"
        
        # 解压前确保路径存在
        mkdir -p /etc/haproxy/certs
        echo "🔄 正在恢复备份..."
        tar -xzf "$SELECTED_BACKUP" -C /
        chmod 644 /etc/haproxy/haproxy.cfg
        chmod -R 644 /etc/haproxy/certs/*
        chmod -R 755 /etc/haproxy/certs
        
        echo "🚀 正在重启 haproxy..."
        systemctl restart haproxy
        
        if systemctl is-active --quiet haproxy; then
            echo "✅ 恢复并重启成功！"
        else
            echo "❌ haproxy 重启失败，请检查配置。"
        fi
    else
        echo "❌ 无效选择。"
    fi
}

# 删除所有备份
delete_backups() {
    FILES=$(ls ./haproxy_backup_*.tar.gz 2>/dev/null || true)
    if [[ -z "$FILES" ]]; then
        echo "⚠️  没有可删除的备份文件。"
        return
    fi
    
    echo ""
    echo "🗑️  将删除以下备份文件："
    echo "┌─────────────────────────────────────────┐"
    for file in $FILES; do
        echo "│ • ${file##*/}"
    done
    echo "└─────────────────────────────────────────┘"
    echo ""
    read -p "⚠️  确认删除所有备份？(y/n): " CONFIRM
    
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        rm -f ./haproxy_backup_*.tar.gz
        echo "✅ 所有备份文件已删除。"
    else
        echo "🔙 操作已取消。"
    fi
}

# 主菜单
main_menu() {
    check_haproxy_installed
    
    while true; do
        clear  # 清屏
        echo ""
        echo "╔═══════════════════════════════════════════╗"
        echo "║            🛠️  HAProxy 管理工具             ║"
        echo "╠═══════════════════════════════════════════╣"
        echo "║                                           ║"
        echo "║  💾 1) 备份当前配置                        ║"
        echo "║                                           ║"
        echo "║  📤 2) 恢复历史备份                        ║"
        echo "║                                           ║"
        echo "║  🗑️  3) 删除所有备份                        ║"
        echo "║                                           ║"
        echo "║  🚪 0) 退出程序                           ║"
        echo "║                                           ║"
        echo "╚═══════════════════════════════════════════╝"
        echo ""
        read -p "🔢 请输入你的选择: " OPTION
        
        case "$OPTION" in
            1) backup_haproxy ;;
            2) restore_haproxy ;;
            3) delete_backups ;;
            0) 
                clear
                echo ""
                echo "👋 感谢使用 HAProxy 管理工具！"
                echo ""
                exit 0 
                ;;
            *) 
                echo "❌ 无效选项，请重新输入。"
                sleep 2
                ;;
        esac
        
        if [[ "$OPTION" != "0" ]]; then
            echo ""
            read -p "按任意键继续..." -n 1
        fi
    done
}

main_menu