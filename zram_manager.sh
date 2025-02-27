#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取物理内存大小（以KB为单位）
get_memory_size() {
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $mem_kb
}

# 计算推荐的zRAM大小（返回字节数）
calculate_zram_size() {
    local mem_kb=$(get_memory_size)
    local mem_mb=$((mem_kb / 1024))
    local zram_mb

    # 根据物理内存大小设置zRAM大小
    if [ $mem_mb -lt 1024 ]; then
        zram_mb=$mem_mb
    elif [ $mem_mb -lt 2048 ]; then
        zram_mb=$mem_mb
    elif [ $mem_mb -lt 4096 ]; then
        zram_mb=$((mem_mb * 3 / 4))
    else
        zram_mb=$((mem_mb / 2))
    fi

    # 转换为字节数
    echo $((zram_mb * 1024 * 1024))
}

# 显示人类可读的大小
human_readable_size() {
    local bytes=$1
    if [ $bytes -gt $((1024*1024*1024)) ]; then
        echo "$((bytes / 1024 / 1024 / 1024))GB"
    else
        echo "$((bytes / 1024 / 1024))MB"
    fi
}

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}此脚本需要root权限运行。${NC}"
        exit 1
    fi
}

# 显示状态信息
show_status() {
    echo -e "\n${YELLOW}===== 系统状态 =====${NC}"
    
    # 显示物理内存信息
    local mem_kb=$(get_memory_size)
    local mem_mb=$((mem_kb / 1024))
    echo -e "\n${GREEN}>> 物理内存大小：${NC}$((mem_mb / 1024))GB"
    
    echo -e "\n${GREEN}>> SWAP状态：${NC}"
    swapon --show
    
    echo -e "\n${GREEN}>> 块设备信息：${NC}"
    lsblk
    
    echo -e "\n${GREEN}>> zRAM压缩算法：${NC}"
    cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "zRAM未加载"
    
    echo -e "\n${GREEN}>> zRAM大小：${NC}"
    if [ -f /sys/block/zram0/disksize ]; then
        size_bytes=$(cat /sys/block/zram0/disksize)
        echo "$(human_readable_size $size_bytes)"
    else
        echo "zRAM未加载"
    fi
    
    echo -e "\n${GREEN}>> 内存使用情况：${NC}"
    free -h
    echo
    read -p "按回车键继续..."
}

# 安装zRAM
install_zram() {
    echo -e "\n${YELLOW}正在配置zRAM...${NC}"
    
    # 获取用户输入的zRAM大小
    local default_size=$(calculate_zram_size)
    local default_size_human=$(human_readable_size $default_size)
    
    echo -e "\n${GREEN}系统推荐的zRAM大小为：${NC}${default_size_human}"
    read -p "请输入期望的zRAM大小（例如：1G, 2G, 512M），直接回车使用推荐值：" input_size
    
    # 如果用户直接回车，使用默认大小
    local zram_size=${input_size:-$default_size_human}
    
    # 确保完全清理现有的zRAM配置
    swapoff /dev/zram0 2>/dev/null
    if [ -e /sys/block/zram0 ]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null
    fi
    rmmod zram 2>/dev/null
    
    # 等待设备完全释放
    sleep 1
    
    # 加载模块并创建一个zRAM设备
    modprobe zram num_devices=1
    
    # 验证是否加载成功
    if ! lsmod | grep -q zram; then
        echo -e "${RED}zRAM模块加载失败${NC}"
        return 1
    fi
    
    # 创建模块加载配置
    echo "zram" > /etc/modules-load.d/zram.conf
    echo "options zram num_devices=1" > /etc/modprobe.d/zram.conf
    
    # 等待设备就绪
    sleep 2
    
    # 设置压缩算法
    if ! echo "zstd" > /sys/block/zram0/comp_algorithm; then
        echo -e "${RED}设置压缩算法失败${NC}"
        return 1
    fi
    
    # 设置用户指定的大小（替换原来的固定1G）
    if ! echo "$zram_size" > /sys/block/zram0/disksize; then
        echo -e "${RED}设置设备大小失败${NC}"
        return 1
    fi
    
    # 创建udev规则（使用用户指定的大小）
    cat > /etc/udev/rules.d/99-zram.rules << EOF
KERNEL=="zram0", ATTR{comp_algorithm}="zstd", ATTR{disksize}="$zram_size", TAG+="systemd"
EOF
    
    # 创建并启用swap
    sudo mkswap /dev/zram0
    sudo swapon /dev/zram0
    
    # 创建systemd服务
    cat > /etc/systemd/system/zram.service << EOF
[Unit]
Description=Swap with zram
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStartPre=/sbin/mkswap /dev/zram0
ExecStart=/sbin/swapon -p 100 /dev/zram0
ExecStop=/sbin/swapoff /dev/zram0

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 停止当前可能运行的zram
    swapoff /dev/zram0 2>/dev/null
    
    # 启动并启用服务
    if ! systemctl start zram.service; then
        echo -e "${RED}服务启动失败，请检查日志：${NC}"
        systemctl status zram.service
        return 1
    fi
    
    systemctl enable zram.service
    
    echo -e "${GREEN}zRAM配置完成！${NC}"
    read -p "按回车键继续..."
}

# 卸载zRAM
uninstall_zram() {
    echo -e "\n${YELLOW}正在卸载zRAM...${NC}"
    
    # 停止并禁用服务
    systemctl stop zram.service
    systemctl disable zram.service
    
    # 删除配置文件
    rm -f /etc/systemd/system/zram.service
    rm -f /etc/modules-load.d/zram.conf
    rm -f /etc/modprobe.d/zram.conf
    rm -f /etc/udev/rules.d/99-zram.rules
    
    # 卸载zRAM
    swapoff /dev/zram0 2>/dev/null
    echo 1 > /sys/block/zram0/reset 2>/dev/null
    rmmod zram 2>/dev/null
    
    echo -e "${GREEN}zRAM已完全卸载！${NC}"
    read -p "按回车键继续..."
}

# 验证zRAM运行状态
verify_zram() {
    echo -e "\n${YELLOW}正在验证zRAM状态...${NC}"
    
    # 检查模块是否加载
    if lsmod | grep -q "^zram"; then
        echo -e "${GREEN}zRAM模块已加载${NC}"
    else
        echo -e "${RED}zRAM模块未加载${NC}"
        return 1
    fi
    
    # 检查设备是否存在
    if [ -e /sys/block/zram0 ]; then
        echo -e "${GREEN}zRAM设备已创建${NC}"
    else
        echo -e "${RED}zRAM设备未创建${NC}"
        return 1
    fi
    
    # 检查swap状态
    if grep -q /dev/zram0 /proc/swaps; then
        echo -e "${GREEN}zRAM swap已启用${NC}"
        echo -e "\nSwap详情："
        grep /dev/zram0 /proc/swaps
    else
        echo -e "${RED}zRAM swap未启用${NC}"
        return 1
    fi
    
    # 检查服务状态
    echo -e "\n${GREEN}服务状态：${NC}"
    systemctl status zram.service
    
    # 显示压缩信息
    if [ -f /sys/block/zram0/comp_algorithm ]; then
        echo -e "\n${GREEN}当前压缩算法：${NC}"
        cat /sys/block/zram0/comp_algorithm | grep -o '\[.*\]'
    fi
    
    read -p "按回车键继续..."
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${YELLOW}===== zRAM 管理工具 =====${NC}"
        echo "1. 安装并配置zRAM"
        echo "2. 卸载zRAM"
        echo "3. 查看系统状态"
        echo "4. 验证zRAM运行状态"
        echo "0. 退出"
        
        read -p "请选择操作 [0-4]: " choice
        
        case $choice in
            1) install_zram ;;
            2) uninstall_zram ;;
            3) show_status ;;
            4) verify_zram ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ; sleep 2 ;;
        esac
    done
}

# 检查root权限并启动主菜单
check_root
main_menu 