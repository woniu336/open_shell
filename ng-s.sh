#!/bin/bash

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 路径定义
SITES_AVAILABLE="/etc/nginx/sites-available"

# 显示标题函数
show_title() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Nginx 站点管理工具             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo
}

# 检查nginx目录是否存在
check_nginx_dir() {
    if [ ! -d "$SITES_AVAILABLE" ]; then
        echo -e "${RED}✗ 错误: 目录 $SITES_AVAILABLE 不存在！${NC}"
        exit 1
    fi
}

# 列出并选择编辑站点
list_and_edit_sites() {
    local sites=($(ls -1 "$SITES_AVAILABLE" 2>/dev/null))
    
    if [ ${#sites[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠ 没有找到任何站点配置文件${NC}"
        echo
        read -p "按Enter键返回菜单..."
        return 1
    fi
    
    echo -e "${CYAN}可用的站点配置文件:${NC}"
    echo -e "${PURPLE}┌─────┬────────────────────────────┐${NC}"
    echo -e "${PURPLE}│ ${BLUE}序号${PURPLE} │ ${BLUE}站点配置${NC}${PURPLE}                    │${NC}"
    echo -e "${PURPLE}├─────┼────────────────────────────┤${NC}"
    
    for i in "${!sites[@]}"; do
        printf "${PURPLE}│ ${GREEN}%3d${PURPLE} │ ${YELLOW}%-26s${PURPLE} │${NC}\n" $((i+1)) "${sites[$i]}"
    done
    
    echo -e "${PURPLE}└─────┴────────────────────────────┘${NC}"
    echo
    echo -e "${CYAN}请选择要编辑的站点:${NC}"
    echo -e "${YELLOW}  输入序号 (1-${#sites[@]}) 编辑对应站点${NC}"
    echo -e "${YELLOW}  输入 0 返回主菜单${NC}"
    echo -e "${YELLOW}  输入 't' 测试并重载Nginx${NC}"
    echo
    
    read -p "请输入选择: " choice
    
    case "$choice" in
        0)
            return 0
            ;;
        [tT])
            test_and_reload
            list_and_edit_sites
            ;;
        *)
            if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}✗ 请输入有效的数字！${NC}"
                sleep 2
                list_and_edit_sites
                return 1
            fi
            
            if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#sites[@]} ]; then
                echo -e "${RED}✗ 序号超出范围！${NC}"
                sleep 2
                list_and_edit_sites
                return 1
            fi
            
            local site_file="${sites[$((choice-1))]}"
            local full_path="$SITES_AVAILABLE/$site_file"
            
            # 检查文件是否存在
            if [ ! -f "$full_path" ]; then
                echo -e "${RED}✗ 文件不存在: $full_path${NC}"
                sleep 2
                list_and_edit_sites
                return 1
            fi
            
            echo -e "${GREEN}✓ 正在编辑: ${CYAN}$site_file${NC}"
            echo -e "${BLUE}────────────────────────────────────────${NC}"
            
            # 显示文件基本信息
            echo -e "${YELLOW}文件信息:${NC}"
            echo -e "  大小: $(du -h "$full_path" | cut -f1)"
            echo -e "  修改时间: $(stat -c %y "$full_path" | cut -d. -f1)"
            echo -e "${BLUE}────────────────────────────────────────${NC}"
            
            # 使用用户喜欢的编辑器，默认使用nano
            ${EDITOR:-nano} "$full_path"
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 文件编辑完成${NC}"
                
                # 询问是否立即测试并重载
                echo
                read -p "是否立即测试并重载Nginx配置？(y/N): " test_now
                if [[ "$test_now" =~ ^[Yy]$ ]]; then
                    test_and_reload
                else
                    echo -e "${YELLOW}⚠ 跳过立即重载，您稍后可以在主菜单选择测试${NC}"
                    read -p "按Enter键继续..."
                fi
            else
                echo -e "${RED}✗ 编辑过程中出现错误${NC}"
                read -p "按Enter键继续..."
            fi
            
            # 返回站点列表
            list_and_edit_sites
            ;;
    esac
}

# 测试nginx配置并重载
test_and_reload() {
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    echo -e "${CYAN}正在测试Nginx配置...${NC}"
    echo
    
    # 测试配置
    echo -e "${YELLOW}[执行] sudo nginx -t${NC}"
    if sudo nginx -t; then
        echo
        echo -e "${GREEN}✓ 配置测试成功！${NC}"
        
        read -p "是否重新加载Nginx配置？(y/N): " reload_choice
        if [[ "$reload_choice" =~ ^[Yy]$ ]]; then
            echo
            echo -e "${YELLOW}[执行] sudo systemctl reload nginx${NC}"
            if sudo systemctl reload nginx; then
                echo
                echo -e "${GREEN}✓ Nginx配置重载成功！${NC}"
            else
                echo
                echo -e "${RED}✗ Nginx配置重载失败！${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ 跳过重载Nginx配置${NC}"
        fi
    else
        echo
        echo -e "${RED}✗ 配置测试失败！请检查配置文件。${NC}"
    fi
    
    echo
    read -p "按Enter键继续..."
}

# 显示主菜单
show_main_menu() {
    echo -e "${CYAN}请选择操作:${NC}"
    echo
    echo -e "${GREEN}[1] ${YELLOW}列出并编辑站点${NC}"
    echo -e "${GREEN}[2] ${YELLOW}测试并重载Nginx${NC}"
    echo -e "${RED}[0] ${YELLOW}退出程序${NC}"
    echo
}

# 主函数
main() {
    check_nginx_dir
    
    while true; do
        show_title
        show_main_menu
        
        read -p "请输入选择 (0-2): " choice
        echo
        
        case $choice in
            1)
                show_title
                list_and_edit_sites
                ;;
            2)
                show_title
                test_and_reload
                ;;
            0)
                echo -e "${GREEN}✓ 感谢使用，再见！${NC}"
                echo
                exit 0
                ;;
            *)
                echo -e "${RED}✗ 无效的选择，请重新输入！${NC}"
                sleep 1
                ;;
        esac
    done
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}⚠ 提示: 某些操作可能需要sudo权限${NC}"
    echo
fi

# 运行主程序
main
