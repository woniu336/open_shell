#!/bin/bash

# Caddy管理脚本
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
CADDY_CONFIG="/etc/caddy/Caddyfile"
LOG_DIR="/var/log/caddy"

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

# 显示标题
show_title() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}      Caddy 管理脚本 v1.0      ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

# 检查Caddy是否已安装
check_caddy_installed() {
    if command -v caddy &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 安装Caddy
install_caddy() {
    echo -e "${YELLOW}开始安装Caddy...${NC}"
    
    # 安装依赖
    apt update
    apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    
    # 添加Caddy官方仓库
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    
    # 设置权限
    chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    chmod o+r /etc/apt/sources.list.d/caddy-stable.list
    
    # 更新并安装Caddy
    apt update
    apt install -y caddy
    
    # 检查安装是否成功
    if check_caddy_installed; then
        echo -e "${GREEN}Caddy安装成功！${NC}"
        caddy version
        
        # 启用开机自启
        systemctl enable caddy
        echo -e "${GREEN}已设置Caddy开机自启${NC}"
        
        # 创建日志目录
        mkdir -p "$LOG_DIR"
        chown caddy:caddy "$LOG_DIR"
        
        return 0
    else
        echo -e "${RED}Caddy安装失败！${NC}"
        return 1
    fi
}

# 检查Caddy状态
check_caddy_status() {
    echo -e "${BLUE}Caddy服务状态：${NC}"
    systemctl status caddy --no-pager -l
    echo ""
    echo -e "${BLUE}Caddy版本信息：${NC}"
    caddy version
}

# 初始化Caddyfile
init_caddyfile() {
    if [[ ! -f "$CADDY_CONFIG" ]]; then
        echo -e "${YELLOW}创建初始Caddyfile...${NC}"
        cat > "$CADDY_CONFIG" << 'EOF'
# Caddy配置文件

# 定义可复用的配置片段
(common_config) {
    reverse_proxy {args.0}
    tls {
        protocols tls1.2 tls1.3
    }
    header {
        Permissions-Policy interest-cohort=()
        Strict-Transport-Security max-age=31536000;
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy no-referrer-when-downgrade
        -Via
        -Alt-Svc
    }
}
EOF
        chown caddy:caddy "$CADDY_CONFIG"
        echo -e "${GREEN}初始Caddyfile创建完成${NC}"
    fi
}

# 编辑配置文件
edit_config() {
    echo -e "${BLUE}编辑Caddyfile配置${NC}"
    echo ""
    
    # 检查配置文件是否存在
    if [[ ! -f "$CADDY_CONFIG" ]]; then
        echo -e "${YELLOW}配置文件不存在，正在创建初始配置...${NC}"
        init_caddyfile
    fi
    
    # 创建备份
    backup_file="${CADDY_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CADDY_CONFIG" "$backup_file"
    echo -e "${GREEN}已创建配置文件备份：$backup_file${NC}"
    echo ""
    
    # 检查可用的编辑器
    if command -v nano &> /dev/null; then
        editor="nano"
    elif command -v vim &> /dev/null; then
        editor="vim"
    elif command -v vi &> /dev/null; then
        editor="vi"
    else
        echo -e "${RED}未找到可用的文本编辑器（nano、vim或vi）${NC}"
        return 1
    fi
    
    echo -e "${BLUE}使用 $editor 编辑器打开配置文件...${NC}"
    echo -e "${YELLOW}提示：编辑完成后，脚本将自动验证配置文件语法${NC}"
    echo ""
    read -p "按回车键继续..."
    
    # 打开编辑器
    $editor "$CADDY_CONFIG"
    
    echo ""
    echo -e "${BLUE}配置文件编辑完成，正在验证语法...${NC}"
    
    # 验证配置文件语法
    if caddy validate --config "$CADDY_CONFIG" --adapter caddyfile; then
        echo -e "${GREEN}配置文件语法验证通过！${NC}"
        
        # 询问是否重启Caddy
        echo ""
        read -p "是否立即重启Caddy服务以应用新配置？(y/n): " restart_choice
        
        if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
            if systemctl restart caddy; then
                echo -e "${GREEN}Caddy重启成功！新配置已生效${NC}"
            else
                echo -e "${RED}Caddy重启失败！请检查配置和系统状态${NC}"
                systemctl status caddy --no-pager -l
            fi
        else
            echo -e "${BLUE}配置文件已保存，请手动重启Caddy服务以应用新配置${NC}"
        fi
    else
        echo -e "${RED}配置文件语法错误！${NC}"
        echo ""
        read -p "是否恢复备份文件？(y/n): " restore_choice
        
        if [[ "$restore_choice" == "y" || "$restore_choice" == "Y" ]]; then
            cp "$backup_file" "$CADDY_CONFIG"
            chown caddy:caddy "$CADDY_CONFIG"
            echo -e "${GREEN}已恢复备份文件${NC}"
        else
            echo -e "${YELLOW}保留当前配置文件，请手动修复语法错误${NC}"
        fi
        
        return 1
    fi
}

# 列出当前站点
list_sites() {
    echo -e "${BLUE}当前配置的站点：${NC}"
    echo ""
    
    if [[ -f "$CADDY_CONFIG" ]]; then
        # 提取域名（去除花括号和空行）
        grep -E "^[a-zA-Z0-9.-]+\s*{" "$CADDY_CONFIG" | sed 's/\s*{.*$//' | while read -r site; do
            if [[ -n "$site" ]]; then
                echo -e "${GREEN}• $site${NC}"
            fi
        done
    else
        echo -e "${YELLOW}未找到配置文件${NC}"
    fi
}

# 查看配置文件
view_config() {
    echo -e "${BLUE}当前Caddyfile配置：${NC}"
    echo ""
    
    if [[ -f "$CADDY_CONFIG" ]]; then
        cat "$CADDY_CONFIG"
    else
        echo -e "${YELLOW}配置文件不存在${NC}"
    fi
}

# 重启Caddy服务
restart_caddy() {
    echo -e "${YELLOW}正在重启Caddy服务...${NC}"
    
    if systemctl restart caddy; then
        echo -e "${GREEN}Caddy重启成功！${NC}"
        systemctl status caddy --no-pager -l
    else
        echo -e "${RED}Caddy重启失败！${NC}"
        systemctl status caddy --no-pager -l
    fi
}

# 显示主菜单
show_menu() {
    echo -e "${BLUE}请选择操作：${NC}"
    echo -e "${GREEN}1.${NC} 检查/安装Caddy"
    echo -e "${GREEN}2.${NC} 查看Caddy状态"
    echo -e "${GREEN}3.${NC} 编辑配置文件"
    echo -e "${GREEN}4.${NC} 列出站点"
    echo -e "${GREEN}5.${NC} 查看配置文件"
    echo -e "${GREEN}6.${NC} 重启Caddy服务"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
}

# 主程序
main() {
    check_root
    
    while true; do
        show_title
        show_menu
        
        read -p "请输入选项 [0-6]: " choice
        
        case $choice in
            1)
                echo ""
                if check_caddy_installed; then
                    echo -e "${GREEN}Caddy已安装${NC}"
                    caddy version
                else
                    echo -e "${YELLOW}Caddy未安装，开始安装...${NC}"
                    if install_caddy; then
                        init_caddyfile
                    fi
                fi
                ;;
            2)
                echo ""
                if check_caddy_installed; then
                    check_caddy_status
                else
                    echo -e "${RED}Caddy未安装，请先安装Caddy${NC}"
                fi
                ;;
            3)
                echo ""
                if check_caddy_installed; then
                    edit_config
                else
                    echo -e "${RED}Caddy未安装，请先安装Caddy${NC}"
                fi
                ;;
            4)
                echo ""
                list_sites
                ;;
            5)
                echo ""
                view_config
                ;;
            6)
                echo ""
                if check_caddy_installed; then
                    restart_caddy
                else
                    echo -e "${RED}Caddy未安装，请先安装Caddy${NC}"
                fi
                ;;
            0)
                echo -e "${GREEN}感谢使用Caddy管理脚本！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 运行主程序
main