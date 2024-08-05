#!/bin/bash

# 颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 请使用root用户运行此脚本${PLAIN}" 
        exit 1
    fi
}

# 显示菜单
show_menu() {
    clear
    echo ""
    if command -v figlet &> /dev/null; then
        figlet -f slant "LUFEI TOOL BOX" | lolcat
    else
        echo -e "${PURPLE}=====================================${PLAIN}"
        echo -e "${CYAN}            LUFEI TOOL BOX            ${PLAIN}"
        echo -e "${PURPLE}=====================================${PLAIN}"
    fi
    echo ""
    echo -e "${CYAN}路飞工具箱 v3.1 （支持 Ubuntu，Debian，CentOS系统）${PLAIN}"
    echo -e "${YELLOW}---------------------------------------------${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} ${BLUE}rclone工具箱${PLAIN}"
    echo -e "${GREEN}2.${PLAIN} ${BLUE}安装纯净宝塔面板${PLAIN}"
    echo -e "${GREEN}3.${PLAIN} ${BLUE}科技lion一键脚本工具${PLAIN}"
    echo -e "${GREEN}4.${PLAIN} ${BLUE}证书SSL申请${PLAIN}"
    echo -e "${GREEN}5.${PLAIN} ${BLUE}docker安装卸载${PLAIN}"
    echo -e "${GREEN}6.${PLAIN} ${BLUE}docker软件应用${PLAIN}"
    echo -e "${GREEN}7.${PLAIN} ${YELLOW}测试脚本合集 ▶${PLAIN}"
    echo -e "${GREEN}8.${PLAIN} ${BLUE}系统工具${PLAIN}"
    echo -e "${GREEN}9.${PLAIN} ${BLUE}其他工具${PLAIN}"
    echo -e "${GREEN}10.${PLAIN} ${BLUE}网站备份${PLAIN}"
    echo -e "${GREEN}11.${PLAIN} ${BLUE}一键重装系统(DD)${PLAIN}"
    echo -e "${GREEN}12.${PLAIN} ${BLUE}设置脚本快捷键${PLAIN}"
    echo -e "${GREEN}0.${PLAIN} ${RED}退出脚本${PLAIN}"
    echo -e "${YELLOW}---------------------------------------------${PLAIN}"
}

# SSL证书申请子菜单
ssl_submenu() {
    clear
    echo -e "${CYAN}证书SSL申请${PLAIN}"
    echo -e "${YELLOW}---------------------------------------------${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} ${BLUE}使用acme.sh申请${PLAIN}"
    echo -e "${GREEN}2.${PLAIN} ${BLUE}使用certbot申请${PLAIN}"
    echo -e "${GREEN}0.${PLAIN} ${RED}返回主菜单${PLAIN}"
    echo -e "${YELLOW}---------------------------------------------${PLAIN}"
    
    read -p "请选择申请方式 [0-2]: " ssl_choice
    case $ssl_choice in
        1)
            run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/ssl.sh"
            ;;
        2)
            run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/ssl-cert.sh"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效的选择，请重新输入！${PLAIN}"
            sleep 2
            ssl_submenu
            ;;
    esac
}

# 运行脚本函数
run_script() {
    local script_url=$1
    clear
    curl -sS -O $script_url && chmod +x ${script_url##*/} && ./${script_url##*/}
}

# 设置快捷键
set_shortcut() {
    read -p "请输入你想要的快捷键命令 (例如: lufei): " shortcut
    echo "alias $shortcut='bash $PWD/tool.sh'" >> ~/.bashrc
    source ~/.bashrc
    echo -e "${GREEN}快捷键已添加。请重新启动终端，或运行 'source ~/.bashrc' 以使修改生效。${PLAIN}"
    sleep 3
}

# 主程序
main() {
    check_root
    while true; do
        show_menu
        read -p "请输入操作编号 [0-12]: " choice
        case $choice in
            1) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/rclone.sh" ;;
            2) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/bt.sh" ;;
            3) run_script "https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh" ;;
            4) ssl_submenu ;;
            5) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/dockerpro.sh" ;;
            6) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/docker666.sh" ;;
            7) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/vps.sh" ;;
            8) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/xitong.sh" ;;
            9) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/soso.sh" ;;
            10) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/s3.sh" ;;
            11) run_script "https://raw.githubusercontent.com/woniu336/open_shell/main/vpsnew.sh" ;;
            12) set_shortcut ;;
            0) 
                echo -e "${YELLOW}感谢使用LUFEI工具箱，再见！${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的输入，请重新选择！${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

main
