#!/bin/bash
# ============================================
# RClone 实时同步脚本
# 功能：监控本地目录变化，立即同步到远程
# 注意：这是单向同步，远程内容会被本地覆盖！
# ============================================

# ========== 配置区域 - 根据实际情况修改 ==========

# 本地同步目录（源目录）
# 图片托管后端的压缩图片目录
RCLONE_SYNC_PATH="/root/ceshi"

# RClone远程名称
# 配置解释: ovh是rclone.conf配置里的名称，/root/ceshi远程服务器路径
RCLONE_REMOTE="ovh:/root/ceshi"

# 同步命令（-v 显示详细日志）
# 警告：sync 会删除远程目录中本地不存在的文件
RCLONE_CMD="rclone -v sync ${RCLONE_SYNC_PATH} ${RCLONE_REMOTE}"

# 监控的文件事件类型
WATCH_EVENTS="modify,delete,create,move"

# 文件变化后延迟同步的秒数（避免频繁触发）
SYNC_DELAY=5

# 强制同步间隔（秒），即使没有文件变化也会同步
SYNC_INTERVAL=3600

# 是否启用桌面通知（服务器环境建议设为 false）
NOTIFY_ENABLE=false

# 获取当前脚本的完整路径
SYNC_SCRIPT=$(realpath $0)

# ========== 函数定义 ==========

# 发送桌面通知
notify() {
    MESSAGE=$1
    if test ${NOTIFY_ENABLE} = "true"; then
        notify-send "rclone ${RCLONE_REMOTE}" "${MESSAGE}"
    fi
}

# 主同步函数
rclone_sync() {
    set -x
    
    # 启动时立即执行一次完整同步
    notify "Startup"
    ${RCLONE_CMD}
    
    # 进入监控循环
    while [[ true ]] ; do
        # inotifywait 监控文件变化
        # --recursive: 递归监控子目录
        # --timeout: 超时时间（秒）
        # -e: 监控的事件类型
        inotifywait --recursive --timeout ${SYNC_INTERVAL} -e ${WATCH_EVENTS} \
                    ${RCLONE_SYNC_PATH} 2>/dev/null
        
        # 根据 inotifywait 的退出码判断情况
        if [ $? -eq 0 ]; then
            # 退出码 0: 检测到文件变化
            sleep ${SYNC_DELAY} && ${RCLONE_CMD} && \
                notify "Synchronized new file changes"
        elif [ $? -eq 1 ]; then
            # 退出码 1: inotify 发生错误
            notify "inotifywait error exit code 1"
            sleep 10
        elif [ $? -eq 2 ]; then
            # 退出码 2: 超时（达到 SYNC_INTERVAL 时间）
            # 即使没有变化也执行一次同步
            ${RCLONE_CMD}
        fi
    done
}

# systemd 服务设置函数
systemd_setup() {
    set -x
    
    # 检查是否启用了用户 systemd Linger
    if loginctl show-user ${USER} | grep "Linger=no"; then
        echo "错误：用户账户未启用 systemd Linger"
        echo "请以 root 身份运行: sudo loginctl enable-linger $USER"
        echo "然后重新运行此命令"
        exit 1
    fi
    
    # 创建 systemd 用户服务目录
    mkdir -p ${HOME}/.config/systemd/user
    
    # 清理服务名称：将特殊字符替换为下划线
    SERVICE_NAME=$(echo "${RCLONE_REMOTE}" | sed 's/[:/\.]/_/g')
    
    # 服务文件路径（使用清理后的名称）
    SERVICE_FILE=${HOME}/.config/systemd/user/rclone_sync_${SERVICE_NAME}.service
    
    # 检查服务文件是否已存在
    if test -f ${SERVICE_FILE}; then
        echo "服务文件已存在: ${SERVICE_FILE} - 不会覆盖"
    else
        # 创建 systemd 服务文件
        cat <<EOF > ${SERVICE_FILE}
[Unit]
Description=rclone_sync ${RCLONE_REMOTE}

[Service]
ExecStart=${SYNC_SCRIPT}

[Install]
WantedBy=default.target
EOF
    fi
    
    # 重新加载 systemd 配置
    systemctl --user daemon-reload
    
    # 启用并立即启动服务（使用清理后的名称）
    systemctl --user enable --now rclone_sync_${SERVICE_NAME}
    
    # 显示服务状态
    systemctl --user status rclone_sync_${SERVICE_NAME}
    
    echo ""
    echo "=========================================="
    echo "服务安装完成！"
    echo "服务名称: rclone_sync_${SERVICE_NAME}"
    echo "=========================================="
}

# ========== 主程序入口 ==========

if test $# = 0; then
    # 无参数：运行同步功能
    rclone_sync
else
    # 有参数：执行指定的函数
    CMD=$1; shift;
    ${CMD} $@
fi
