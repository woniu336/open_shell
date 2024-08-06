#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
TECH_BLUE='\033[38;2;0;255;255m'  # 使用科技蓝
NC='\033[0m' # No Color

# 显示菜单
show_menu() {
    clear
    echo -e "\n${TECH_BLUE}======================================${NC}"
    echo -e "${TECH_BLUE}           LUFEI TOOL BOX${NC}"
    echo -e "${GREEN}         blog: woniu336.github.io${NC}"
    echo -e "${TECH_BLUE}======================================${NC}"
    echo -e "${GREEN}1.${NC} rclone工具箱"
    echo -e "${GREEN}2.${NC} 安装纯净宝塔面板"
    echo -e "${GREEN}3.${NC} 科技lion一键脚本工具"
    echo -e "${GREEN}4.${NC} 证书SSL申请"
    echo -e "${GREEN}5.${NC} docker安装卸载"
    echo -e "${GREEN}6.${NC} docker软件应用"
    echo -e "${GREEN}7.${NC} 测试脚本合集"
    echo -e "${GREEN}8.${NC} 系统工具"
    echo -e "${GREEN}9.${NC} 其他工具"
    echo -e "${GREEN}10.${NC} 网站备份"
    echo -e "${GREEN}11.${NC} 一键重装系统(DD)"
    echo -e "${GREEN}12.${NC} 设置脚本快捷键"
    echo -e "${RED}0.${NC} 退出脚本"
    echo -e "${TECH_BLUE}======================================${NC}"
}

# SSL证书申请子菜单
ssl_submenu() {
    clear
    echo -e "${TECH_BLUE}证书SSL申请${NC}"
    echo -e "${TECH_BLUE}---------------------------------------------${NC}"
    echo -e "${GREEN}1.${NC} 使用acme.sh申请"
    echo -e "${GREEN}2.${NC} 使用certbot申请"
    echo -e "${RED}0.${NC} 返回主菜单"
    echo -e "${TECH_BLUE}---------------------------------------------${NC}"
    
    read -p "$(echo -e ${TECH_BLUE}"请选择申请方式 [0-2]: "${NC})" ssl_choice
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
            echo -e "${RED}无效的选择，请重新输入！${NC}"
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
        read -p "$(echo -e ${TECH_BLUE}"请输入操作编号 [0-12]: "${NC})" choice
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
                echo -e "${RED}退出程序${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的输入，请重新选择！${NC}"
                sleep 2
                ;;
        esac
        
        echo -e "\n${TECH_BLUE}按Enter键返回主菜单...${NC}"
        read
    done
}

main