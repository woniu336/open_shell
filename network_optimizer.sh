#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置文件路径
TARGET_DIR="/app/tcp"
SCRIPT_NAME="setup_traffic_control.sh"
CONFIG_FILE="/app/tcp/bandwidth.conf"

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 配置系统参数
setup_sysctl() {
    # 只在第一次运行时备份原始配置文件
    if [ -f "/etc/sysctl.conf" ] && [ ! -f "/etc/sysctl.conf.bak" ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak
    fi

    # 定义 TCP 缓冲区参数
    TCP_WMEM="4096 16384 67108864"
    TCP_RMEM="4096 87380 67108864"

    # 更新配置文件
    sed -i '/^net.ipv4.tcp_[wr]mem/d' /etc/sysctl.conf
    echo "net.ipv4.tcp_wmem = $TCP_WMEM" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem = $TCP_RMEM" >> /etc/sysctl.conf

    # 应用更改
    sysctl -p
}

# 创建带宽控制脚本
create_tc_script() {
    # 如果脚本已存在且内容正确，则跳过
    if [ -f "$TARGET_DIR/$SCRIPT_NAME" ]; then
        return
    fi

    mkdir -p $TARGET_DIR 2>/dev/null
    touch $CONFIG_FILE 2>/dev/null

    cat > $TARGET_DIR/$SCRIPT_NAME << 'EOF'
#!/bin/bash
# 获取第一个以太网接口名称
INTERFACE=$(ip -o link show | grep 'link/ether' | awk -F': ' '{print $2}' | head -n 1)
echo "网络接口名称: $INTERFACE"

# 检查参数
if [ "$1" != "-y" ] && [ "$1" != "-n" ]; then
    echo "无效的参数。请使用 -y 或 -n。"
    exit 1
fi

# 系统自动执行或用户执行
if [ "$1" = "-n" ]; then
    if [ -f "/app/tcp/bandwidth.conf" ]; then
        source /app/tcp/bandwidth.conf
    else
        echo "配置文件不存在，请手动执行脚本并输入带宽值。"
        exit 1
    fi
elif [ "$1" = "-y" ]; then
    read -e -p "请输入瓶颈带宽值 (单位 Mbit/s): " BANDWIDTH
    echo "瓶颈带宽值: $BANDWIDTH Mbit/s"
    echo "BANDWIDTH=$BANDWIDTH" > /app/tcp/bandwidth.conf
fi

# 检查变量
if [ -z "$INTERFACE" ] || [ -z "$BANDWIDTH" ]; then
    echo "网络接口名称或瓶颈带宽值不能为空"
    exit 1
fi

# 配置带宽控制
tc qdisc del dev $INTERFACE root 2>/dev/null || true
tc qdisc add dev $INTERFACE root handle 1:0 htb default 10
tc class add dev $INTERFACE parent 1:0 classid 1:1 htb rate ${BANDWIDTH}mbit ceil ${BANDWIDTH}mbit
tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:1
tc class add dev $INTERFACE parent 1:0 classid 1:2 htb rate ${BANDWIDTH}mbit ceil ${BANDWIDTH}mbit
tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:2

# 显示配置
tc qdisc show dev $INTERFACE
tc class show dev $INTERFACE
tc -s filter show dev $INTERFACE
EOF

    chmod +x $TARGET_DIR/$SCRIPT_NAME 2>/dev/null
}

# 创建系统服务
create_service() {
    # 如果服务已存在且内容正确，则跳过
    if [ -f "/etc/systemd/system/tcp_traffic_control.service" ]; then
        systemctl is-enabled tcp_traffic_control.service >/dev/null 2>&1 || systemctl enable tcp_traffic_control.service >/dev/null 2>&1
        return
    fi

    cat > /etc/systemd/system/tcp_traffic_control.service << EOF
[Unit]
Description=TCP Traffic Control Setup
After=network.target

[Service]
Type=oneshot
ExecStart=/app/tcp/setup_traffic_control.sh -n
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable tcp_traffic_control.service >/dev/null 2>&1
}

# 删除配置函数
remove_configuration() {
    echo -e "${YELLOW}正在删除网络优化配置...${NC}"
    
    # 1. 停止并删除系统服务
    echo -e "${YELLOW}停止并删除系统服务...${NC}"
    systemctl stop tcp_traffic_control.service 2>/dev/null
    systemctl disable tcp_traffic_control.service 2>/dev/null
    rm -f /etc/systemd/system/tcp_traffic_control.service
    systemctl daemon-reload
    
    # 2. 删除带宽控制配置
    echo -e "${YELLOW}删除带宽控制配置...${NC}"
    INTERFACE=$(ip -o link show | grep 'link/ether' | awk -F': ' '{print $2}' | head -n 1)
    tc qdisc del dev $INTERFACE root 2>/dev/null
    
    # 3. 删除创建的文件和目录
    echo -e "${YELLOW}删除配置文件和目录...${NC}"
    rm -rf $TARGET_DIR
    
    # 4. 恢复备份的配置文件（如果存在）并应用原始配置
    echo -e "${YELLOW}恢复配置文件备份...${NC}"
    if [ -f "/etc/sysctl.conf.bak" ]; then
        # 直接恢复原始配置文件
        cp /etc/sysctl.conf.bak /etc/sysctl.conf
        echo "已恢复 /etc/sysctl.conf 的备份"
        
        # 重新加载系统参数以应用原始配置
        sysctl --system >/dev/null
        
        # 删除备份文件
        rm -f /etc/sysctl.conf.bak
    else
        echo -e "${YELLOW}未找到配置文件备份，无法恢复原始设置${NC}"
    fi
    
    echo -e "${GREEN}所有网络优化配置已成功删除并恢复原始设置${NC}"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${YELLOW}=== 网络优化配置工具 ===${NC}"
    echo "1. 设置带宽限制"
    echo "2. 查看当前配置"
    echo "3. 恢复原始设置"
    echo "0. 退出"
}

# 查看当前配置
show_current_config() {
    echo -e "${YELLOW}当前系统参数配置：${NC}"
    sysctl -a | grep -E "net.core.default_qdisc|net.ipv4.tcp_congestion_control|net.ipv4.tcp_rmem|net.ipv4.tcp_wmem"
    
    echo -e "\n${YELLOW}当前带宽控制配置：${NC}"
    INTERFACE=$(ip -o link show | grep 'link/ether' | awk -F': ' '{print $2}' | head -n 1)
    tc qdisc show dev $INTERFACE
    tc class show dev $INTERFACE
}

# 主程序
main() {
    check_root
    
    # 首次运行时静默安装必要组件
    setup_sysctl
    create_tc_script
    create_service
    
    while true; do
        show_menu
        read -p "请选择操作 [1-3]: " choice
        case $choice in
            1) $TARGET_DIR/$SCRIPT_NAME -y ;;
            2) show_current_config ;;
            3)
                read -p "确定要删除所有配置吗？这将恢复系统默认设置 [y/N]: " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    remove_configuration
                else
                    echo -e "${YELLOW}取消删除操作${NC}"
                fi
                ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        read -p "按回车键继续..."
    done
}

main 