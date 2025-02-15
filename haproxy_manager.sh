#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用root权限运行此脚本${NC}"
    exit 1
fi

# 检查并安装nano
check_nano() {
    if ! command -v nano &> /dev/null; then
        echo -e "${YELLOW}正在安装 nano 编辑器...${NC}"
        apt update
        apt install nano -y
    fi
}

# 清屏函数
clear_screen() {
    clear
}

# 显示主菜单
show_menu() {
    echo -e "${CYAN}╔════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      ${PURPLE}HAProxy 管理脚本${CYAN}         ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 1. 安装 HAProxy                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 2. 添加端口转发               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 3. 查看现有转发               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 4. 编辑配置文件               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 5. 卸载 HAProxy               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 0. 退出                       ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════╝${NC}"
    echo -e "${CYAN}请输入选项 [0-5]:${NC}"
}

# 安装HAProxy
install_haproxy() {
    echo -e "${GREEN}正在安装 HAProxy...${NC}"
    apt install haproxy -y
    systemctl start haproxy
    systemctl enable haproxy
    echo -e "${GREEN}HAProxy 安装完成并已启动${NC}"
}

# 检查端口是否已被使用
check_port() {
    local port=$1
    local backend_ip=$2
    
    # 检查端口是否被其他程序使用（非HAProxy）
    if netstat -tuln | grep -q ":$port " && ! systemctl is-active haproxy &>/dev/null; then
        return 1
    fi
    
    # 检查是否存在完全相同的配置
    if grep -q "server server_${port} ${backend_ip}:${port}" /etc/haproxy/haproxy.cfg; then
        return 2
    fi
    
    return 0
}

# 检查HAProxy配置
check_config() {
    local output
    output=$(haproxy -c -f /etc/haproxy/haproxy.cfg 2>&1)
    if [ $? -eq 0 ]; then
        return 0
    else
        echo -e "${RED}配置错误：${NC}"
        echo -e "${output}"
        return 1
    fi
}

# 修改HAProxy配置为TCP模式
modify_haproxy_config() {
    # 保存原始配置
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

    sed -i 's/mode\s*http/mode\t\ttcp/g' /etc/haproxy/haproxy.cfg
    sed -i 's/option\s*httplog/option\t\ttcplog/g' /etc/haproxy/haproxy.cfg

    # 检查配置
    if check_config; then
        systemctl restart haproxy
        rm -f /etc/haproxy/haproxy.cfg.bak
        return 0
    else
        echo -e "${RED}配置验证失败，正在回滚更改...${NC}"
        mv /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
        return 1
    fi
}

# 添加端口转发
add_port_forward() {
    echo -e "${YELLOW}请输入前端端口:${NC}"
    read frontend_port
    
    # 验证端口号
    if ! [[ "$frontend_port" =~ ^[0-9]+$ ]] || [ "$frontend_port" -lt 1 ] || [ "$frontend_port" -gt 65535 ]; then
        echo -e "${RED}错误：无效的端口号（应为1-65535之间的数字）${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}请输入后端IP:${NC}"
    read backend_ip
    
    # 验证IP地址格式
    if ! [[ "$backend_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}错误：无效的IP地址格式${NC}"
        return 1
    fi
    
    # 检查端口和后端IP组合
    check_port "$frontend_port" "$backend_ip"
    port_status=$?
    
    if [ $port_status -eq 1 ]; then
        echo -e "${RED}错误：端口 $frontend_port 已被其他程序使用${NC}"
        echo -e "${YELLOW}请使用以下命令查看端口占用情况：${NC}"
        echo -e "netstat -tuln | grep :$frontend_port"
        return 1
    elif [ $port_status -eq 2 ]; then
        echo -e "${RED}错误：该端口转发配置已存在${NC}"
        return 1
    fi
    
    # 保存原始配置
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
    
    # 检查是否已存在相同端口的frontend配置
    if ! grep -q "frontend tcp_front_${frontend_port}" /etc/haproxy/haproxy.cfg; then
        # 如果不存在，添加新的frontend和backend配置
        cat >> /etc/haproxy/haproxy.cfg << EOF

frontend tcp_front_${frontend_port}
    bind *:${frontend_port}
    default_backend servers_${frontend_port}

backend servers_${frontend_port}
    server server_${frontend_port}_$(date +%s) ${backend_ip}:${frontend_port} check
EOF
    else
        # 如果已存在，只添加新的server配置到对应的backend部分
        # 使用awk查找正确的backend部分并添加新的server配置
        awk -v port="${frontend_port}" -v backend_ip="${backend_ip}" -v ts="$(date +%s)" '
        {
            print $0
            if ($0 ~ "^backend servers_" port "$") {
                printf "    server server_%s_%s %s:%s check\n", port, ts, backend_ip, port
            }
        }' /etc/haproxy/haproxy.cfg > /etc/haproxy/haproxy.cfg.new
        
        if [ $? -eq 0 ]; then
            mv /etc/haproxy/haproxy.cfg.new /etc/haproxy/haproxy.cfg
        else
            echo -e "${RED}更新配置文件失败${NC}"
            rm -f /etc/haproxy/haproxy.cfg.new
            mv /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
            return 1
        fi
    fi

    # 检查配置并应用
    if check_config; then
        # 修改配置为TCP模式
        if modify_haproxy_config; then
            echo -e "${GREEN}端口转发添加成功${NC}"
            echo -e "${GREEN}前端端口: ${frontend_port} → 后端: ${backend_ip}:${frontend_port}${NC}"
            rm -f /etc/haproxy/haproxy.cfg.bak
        else
            echo -e "${RED}修改TCP模式失败${NC}"
            mv /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
            systemctl restart haproxy
        fi
    else
        echo -e "${RED}配置验证失败，正在回滚更改...${NC}"
        mv /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
        systemctl restart haproxy
        echo -e "\n${YELLOW}可能的解决方案：${NC}"
        echo -e "1. 确保端口未被其他服务占用"
        echo -e "2. 检查后端IP地址是否可访问"
        echo -e "3. 检查HAProxy配置文件语法"
        echo -e "\n${YELLOW}查看详细错误信息：${NC}"
        echo -e "systemctl status haproxy.service"
        echo -e "journalctl -xe"
    fi
}

# 查看现有转发
view_forwards() {
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            ${PURPLE}当前端口转发配置${CYAN}              ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════╣${NC}"
    
    # 检查是否存在转发规则
    if ! grep -q "frontend tcp_front_" /etc/haproxy/haproxy.cfg; then
        echo -e "${CYAN}║${NC}     ${YELLOW}当前没有配置任何端口转发...${NC}        ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
        return
    fi

    # 提取并显示所有转发规则
    while IFS= read -r line; do
        if [[ $line =~ frontend[[:space:]]+tcp_front_([0-9]+) ]]; then
            port="${BASH_REMATCH[1]}"
            echo -e "${CYAN}║${NC} ➜ 端口: ${GREEN}${port}${NC}"
            
            # 使用awk提取该端口下的所有后端IP
            awk -v port="$port" '
                $0 ~ "backend servers_" port {
                    in_backend = 1
                    next
                }
                in_backend && /^backend/ {
                    in_backend = 0
                }
                in_backend && /server/ {
                    split($3, a, ":")
                    printf "'"${CYAN}║${NC}   └─→ 后端: ${GREEN}%-15s${NC}${CYAN}║${NC}\n"'", a[1]
                }
            ' /etc/haproxy/haproxy.cfg
        fi
    done < <(grep "frontend tcp_front_" /etc/haproxy/haproxy.cfg)
    
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
}

# 编辑配置文件
edit_config() {
    if [ ! -f "/etc/haproxy/haproxy.cfg" ]; then
        echo -e "${RED}HAProxy 配置文件不存在！${NC}"
        return
    fi
    
    # 保存原始配置
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
    
    check_nano
    nano /etc/haproxy/haproxy.cfg
    
    # 检查配置
    if check_config; then
        echo -e "${GREEN}配置文件验证通过，正在重启 HAProxy...${NC}"
        systemctl restart haproxy
        rm -f /etc/haproxy/haproxy.cfg.bak
    else
        echo -e "${RED}配置验证失败，正在回滚更改...${NC}"
        mv /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
        systemctl restart haproxy
        echo -e "${YELLOW}请检查配置文件的语法是否正确${NC}"
    fi
}

# 卸载HAProxy
uninstall_haproxy() {
    echo -e "${RED}正在卸载 HAProxy...${NC}"
    
    # 停止服务
    systemctl stop haproxy 2>/dev/null
    
    # 禁用服务
    systemctl disable haproxy 2>/dev/null
    
    # 删除服务文件
    rm -f /lib/systemd/system/haproxy.service
    systemctl daemon-reload
    
    # 卸载软件包
    apt remove --purge haproxy -y
    apt autoremove -y
    
    # 确保删除haproxy用户和组
    userdel haproxy 2>/dev/null
    groupdel haproxy 2>/dev/null
    
    # 强制删除相关目录及其内容
    rm -rf /etc/haproxy
    rm -rf /var/lib/haproxy
    rm -rf /var/run/haproxy
    rm -rf /var/log/haproxy
    
    # 删除其他可能的残留文件
    find /etc -name "*haproxy*" -exec rm -rf {} +
    find /var -name "*haproxy*" -exec rm -rf {} +
    
    echo -e "${GREEN}HAProxy 已完全卸载，所有相关文件和目录已清理${NC}"
}

# 主循环
while true; do
    clear_screen
    show_menu
    read choice
    case $choice in
        1)
            install_haproxy
            ;;
        2)
            add_port_forward
            ;;
        3)
            view_forwards
            ;;
        4)
            edit_config
            ;;
        5)
            uninstall_haproxy
            ;;
        0)
            echo -e "${GREEN}感谢使用！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重试${NC}"
            ;;
    esac
    echo -e "${CYAN}按回车键继续...${NC}"
    read
done 