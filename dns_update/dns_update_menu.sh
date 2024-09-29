#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # 无颜色

# Python 脚本路径
PYTHON_SCRIPT="dns_update.py"

# 服务器备注文件
SERVER_REMARK_FILE="server_remark.txt"

# 函数:设置 Cloudflare 配置
setup_cloudflare() {
    echo -e "${GREEN}正在设置 Cloudflare 配置...${NC}"
    ./dns_update.sh
    echo -e "${GREEN}Cloudflare 配置已完成。${NC}"
    restart_dns_update_process
}

# 函数：设置钉钉机器人配置
setup_dingtalk() {
    echo -e "${GREEN}正在设置钉钉机器人配置...${NC}"
    read -p "请输入钉钉机器人 Access Token: " access_token
    read -p "请输入钉钉机器人 Secret(加签): " secret

    # 更新 Python 脚本中的钉钉配置
    sed -i "s/ACCESS_TOKEN = .*/ACCESS_TOKEN = \"$access_token\"/" $PYTHON_SCRIPT
    sed -i "s/SECRET = .*/SECRET = \"$secret\"/" $PYTHON_SCRIPT

    echo -e "${GREEN}钉钉机器人配置已更新到 $PYTHON_SCRIPT${NC}"
    restart_dns_update_process
}

# 函数：运行 DNS 更新脚本
run_dns_update() {
    echo -e "${GREEN}正在启动 DNS 更新脚本...${NC}"
    nohup python3 $PYTHON_SCRIPT >> nohup.out 2>&1 &
    echo -e "${GREEN}DNS 更新脚本已在后台启动。${NC}"
}

# 函数：查看运行状态
check_status() {
    if pgrep -f "python3 $PYTHON_SCRIPT" > /dev/null
    then
        echo -e "${GREEN}DNS 更新脚本正在运行。${NC}"
    else
        echo -e "${RED}DNS 更新脚本未运行。${NC}"
    fi
}

# 函数：停止 DNS 更新脚本
stop_dns_update() {
    echo -e "${YELLOW}正在停止 DNS 更新脚本...${NC}"
    pkill -f $PYTHON_SCRIPT
    echo -e "${GREEN}DNS 更新脚本已停止。${NC}"
}

# 函数：安装依赖和下载必要文件
install_dependencies() {
    echo -e "${GREEN}正在安装依赖...${NC}"
    apt update
    apt install python3-pip jq wget -y
    pip3 install requests
    echo -e "${GREEN}依赖安装完成。${NC}"

    echo -e "${GREEN}正在检查并下载必要文件...${NC}"
    
    # 下载 dns_update.sh
    if [ ! -f "dns_update.sh" ]; then
        wget https://raw.githubusercontent.com/woniu336/open_shell/main/dns_update/dns_update.sh
        chmod +x dns_update.sh
        echo -e "${GREEN}dns_update.sh 下载完成。${NC}"
    else
        echo -e "${YELLOW}dns_update.sh 已存在,跳过下载。${NC}"
    fi

    # 下载 dns_update.py
    if [ ! -f "dns_update.py" ]; then
        wget https://raw.githubusercontent.com/woniu336/open_shell/main/dns_update/dns_update.py
        chmod +x dns_update.py
        echo -e "${GREEN}dns_update.py 下载完成。${NC}"
    else
        echo -e "${YELLOW}dns_update.py 已存在,跳过下载。${NC}"
    fi

    echo -e "${GREEN}所有必要文件检查和下载完成。${NC}"
}

# 函数：切换 CDN 状态
toggle_cdn_status() {
    echo -e "${GREEN}正在检查当前 IP 和 CDN 状态...${NC}"
    
    # 显示当前两个 IP 的 CDN 状态
    show_cdn_status

    echo -e "${YELLOW}请选择要修改的 IP 的 CDN 状态：${NC}"
    echo "1) 原始 IP"
    echo "2) 备用 IP"
    read -p "请输入选项 (1 或 2): " ip_choice

    case $ip_choice in
        1)
            toggle_ip_cdn "original_ip_cdn_enabled" "原始 IP"
            ;;
        2)
            toggle_ip_cdn "backup_ip_cdn_enabled" "备用 IP"
            ;;
        *)
            echo -e "${RED}无效的选项。操作取消。${NC}"
            return
            ;;
    esac

    if [ "$restart_required" = true ]; then
        restart_dns_update_process
        show_cdn_status
    else
        echo -e "${YELLOW}CDN 状态未改变，无需重启 DNS 更新进程。${NC}"
    fi
}

# 函数：显示 CDN 状态
show_cdn_status() {
    echo -e "${BLUE}当前 CDN 状态：${NC}"
    if grep -q "original_ip_cdn_enabled = True" $PYTHON_SCRIPT; then
        echo -e "${GREEN}原始 IP 的 CDN 状态：已开启${NC}"
    else
        echo -e "${YELLOW}原始 IP 的 CDN 状态：已关闭${NC}"
    fi
    if grep -q "backup_ip_cdn_enabled = True" $PYTHON_SCRIPT; then
        echo -e "${GREEN}备用 IP 的 CDN 状态：已开启${NC}"
    else
        echo -e "${YELLOW}备用 IP 的 CDN 状态：已关闭${NC}"
    fi
}

# 函数：切换指定 IP 的 CDN 状态
toggle_ip_cdn() {
    local var_name=$1
    local ip_type=$2
    
    if grep -q "${var_name} = True" $PYTHON_SCRIPT; then
        read -p "是否要关闭${ip_type}的 CDN？(y/n): " choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            sed -i "s/${var_name} = True/${var_name} = False/g" $PYTHON_SCRIPT
            echo -e "${GREEN}${ip_type}的 CDN 已关闭。${NC}"
            restart_required=true
        else
            echo -e "${YELLOW}操作已取消，${ip_type}的 CDN 状态保持不变。${NC}"
        fi
    else
        read -p "是否要开启${ip_type}的 CDN？(y/n): " choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            sed -i "s/${var_name} = False/${var_name} = True/g" $PYTHON_SCRIPT
            echo -e "${GREEN}${ip_type}的 CDN 已开启。${NC}"
            restart_required=true
        else
            echo -e "${YELLOW}操作已取消，${ip_type}的 CDN 状态保持不变。${NC}"
        fi
    fi
}

# 函数：重启 DNS 更新进程
restart_dns_update_process() {
    echo -e "${GREEN}正在重启 DNS 更新进程...${NC}"
    if ps -ef | grep '[p]ython3 dns_update.py' > /dev/null; then
        pkill -f dns_update.py
        echo -e "${YELLOW}已停止旧的 DNS 更新进程。${NC}"
    fi
    nohup python3 dns_update.py > /dev/null 2>&1 &
    echo -e "${GREEN}DNS 更新进程已重新启动。${NC}"
    
    # 等待几秒钟让 Python 脚本启动
    sleep 2
}

# 函数：设置服务器备注
set_server_remark() {
    echo -e "${GREEN}设置服务器备注${NC}"
    read -p "请输入服务器备注: " remark
    echo "$remark" > $SERVER_REMARK_FILE
    sed -i "s/SERVER_REMARK = .*/SERVER_REMARK = \"$remark\"/" $PYTHON_SCRIPT
    echo -e "${GREEN}服务器备注已设置为: $remark${NC}"
    restart_dns_update_process
}

# 新增函数：设置脚本启动快捷键
set_shortcut() {
    while true; do
        clear
        read -e -p "请输入你想要的快捷按键（输入0退出）: " shortcut
        if [ "$shortcut" == "0" ]; then
            break
        fi

        sed -i '/alias.*dns_update_menu.sh/d' ~/.bashrc

        echo "alias $shortcut='bash $PWD/dns_update_menu.sh'" >> ~/.bashrc
        sleep 1
        source ~/.bashrc

        echo -e "${GREEN}快捷键已设置${NC}"
        break
    done
}

# 函数：显示菜单
show_menu() {
    echo -e "${BLUE}┌─────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│     ${YELLOW}Cloudflare 宕机切换IP脚本${BLUE}        │${NC}"
    echo -e "${BLUE}│     ${YELLOW}博客:https://woniu336.github.io${BLUE}  │${NC}"
    echo -e "${BLUE}├─────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│ ${GREEN}1.${NC} 安装依赖                             ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}2.${NC} 设置 Cloudflare 配置                 ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}3.${NC} 设置钉钉机器人配置                   ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}4.${NC} 启动 DNS 更新脚本                    ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}5.${NC} 查看运行状态                         ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}6.${NC} 停止 DNS 更新脚本                    ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}7.${NC} 切换 CDN 状态                        ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}8.${NC} 设置服务器备注                       ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}9.${NC} 设置脚本启动快捷键                   ${BLUE}│${NC}"
    echo -e "${BLUE}│ ${GREEN}0.${NC} 退出                                 ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────┘${NC}"
}

# 主循环
while true; do
    clear
    show_menu
    read -p "请选择操作 (0-9): " choice
    echo
    case $choice in
        1) install_dependencies ;;
        2) setup_cloudflare ;;
        3) setup_dingtalk ;;
        4) run_dns_update ;;
        5) check_status ;;
        6) stop_dns_update ;;
        7) toggle_cdn_status ;;
        8) set_server_remark ;;
        9) set_shortcut ;;
        0) echo -e "${YELLOW}感谢使用，再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重新输入。${NC}" ;;
    esac
    echo
    read -n 1 -s -r -p "按任意键返回主菜单..."
done