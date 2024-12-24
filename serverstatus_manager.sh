#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
PURPLE='\033[0;35m'

# 默认安装目录
DEFAULT_INSTALL_DIR="/root/tzserve/serverstatus"

# 获取系统信息函数
get_system_info() {
    # 获取主机名
    HOSTNAME=$(hostname)
    
    # 获取操作系统类型
    if [ -f /etc/os-release ]; then
        OS=$(grep -w "ID" /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    else
        OS="linux"
    fi
    
    # 获取CPU信息
    CPU_CORES=$(grep -c processor /proc/cpuinfo)
    
    # 获取内存信息（以KB为单位）
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    
    # 转换为MB和GB并保留一位小数
    TOTAL_MEM_MB=$(awk "BEGIN {printf \"%.0f\", ${TOTAL_MEM_KB}/1024}")
    TOTAL_MEM_GB=$(awk "BEGIN {printf \"%.1f\", ${TOTAL_MEM_KB}/1024/1024}")
    
    # 如果小于1GB，使用MB作为单位
    if [ $(echo "$TOTAL_MEM_GB < 1" | bc -l) -eq 1 ]; then
        MEMORY_GB="${TOTAL_MEM_MB}M"
    else
        MEMORY_GB="${TOTAL_MEM_GB}G"
    fi
    
    # 获取硬盘大小
    DISK_GB=$(df -h / | awk 'NR==2 {print $2}' | tr -d 'G')
    
    # 获取虚拟化类型
    VIRT_TYPE=$(systemd-detect-virt || echo "KVM")
    
    # 获取国家代码
    COUNTRY_CODE=$(curl -s https://ipapi.co/country || echo "us")
}

# 更新配置文件函数
update_config() {
    local name=$1
    local password=$2
    local alias=$3
    local config_file="${DEFAULT_INSTALL_DIR}/config.toml"
    
    # 确保在添加新主机前获取系统信息
    get_system_info
    
    # 如果配置文件不存在，创建一个
    if [ ! -f "$config_file" ]; then
        # 创建基本配置
        cat > "$config_file" <<EOF
# 侦听地址
grpc_addr = "0.0.0.0:9394"
http_addr = "0.0.0.0:8080"
offline_threshold = 30

# 管理员账号
admin_user = "admin"
admin_pass = "admin"

EOF
    fi
    
    # 读取现有的 hosts 配置
    local current_hosts=""
    if [ -f "$config_file" ]; then
        current_hosts=$(awk '/^hosts = \[/,/^\]/ {print}' "$config_file" | grep -v "^hosts = \[" | grep -v "^\]")
    fi
    
    # 从粘贴的配置中提取系统信息
    local host_os=$(echo "$host_config" | grep -o 'os=[^;]*' | cut -d'=' -f2)
    local host_spec=$(echo "$host_config" | grep -o 'spec=[^;]*' | cut -d'=' -f2)
    local host_location=$(echo "$host_config" | grep -o 'location = "[^"]*"' | cut -d'"' -f2)
    local host_type=$(echo "$host_config" | grep -o 'type = "[^"]*"' | cut -d'"' -f2)
    
    # 如果粘贴的配置中包含硬盘信息，使用它；否则使用系统检测到的值
    local disk_size
    if [[ $host_spec =~ ([0-9]+)G$ ]]; then
        disk_size="${BASH_REMATCH[1]}"
    else
        disk_size="$DISK_GB"
    fi
    
    # 使用提取的信息或默认系统信息
    local final_os=${host_os:-$OS}
    local memory_value=${MEMORY_GB%G}
    local final_spec=${host_spec:-"${CPU_CORES}C/${memory_value}G/${disk_size}G"}
    local final_location=${host_location:-$COUNTRY_CODE}
    local final_type=${host_type:-$VIRT_TYPE}
    
    # 准备新的 host 配置，使用从粘贴配置中提取的硬盘大小
    local new_host="  {name = \"${name}\", password = \"${password}\", alias = \"${alias}\", location = \"${final_location}\", type = \"${final_type}\", labels = \"os=${final_os};spec=${final_spec};\"},"
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 将文件开头到 hosts = [ 的部分复制到临时文件
    awk '/^hosts = \[/{exit} {print}' "$config_file" > "$temp_file"
    
    # 添加 hosts 数组开始
    echo "hosts = [" >> "$temp_file"
    
    # 添加现有的 hosts（如果有的话）
    if [ ! -z "$current_hosts" ]; then
        echo "$current_hosts" >> "$temp_file"
    fi
    
    # 添加新的 host
    echo "$new_host" >> "$temp_file"
    
    # 添加 hosts 数组结束
    echo "]" >> "$temp_file"
    
    # 将文件剩余部分（hosts 数组之后的内容）复制到临时文件
    awk 'BEGIN{found=0} /^hosts = \[/{found=1} /^\]/{if(found==1){found=2;next}} found==2{print}' "$config_file" >> "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$config_file"
    
    echo -e "${GREEN}配置文件已更新${NC}"
    echo -e "${YELLOW}新添加的主机配置：${NC}"
    echo -e "${BLUE}$new_host${NC}"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}┌───────────────────────────────────────────────┐"
    echo -e "│                                                   │"
    echo -e "│            ${BLUE}ServerStatus-Rust 探针${BLUE}               │"
    echo -e "│            ${NC}github.com/zdz/ServerStatus-Rust${BLUE}        │"
    echo -e "│                                                   │"
    echo -e "├───────────────────────────────────────────────┤"
    echo -e "│                 ${PURPLE}基础工具${BLUE}                        │"
    echo -e "│  ${NC}[1] 安装必要工具        [2] 编辑配置文件        ${BLUE}│"
    echo -e "├───────────────────────────────────────────────┤"
    echo -e "│                 ${PURPLE}服务端管理${BLUE}                      │"
    echo -e "│  ${NC}[3] 安装服务端          [4] 重启服务端          ${BLUE}│"
    echo -e "│  ${NC}[5] 开启世界地图        [6] 配置告警通知        ${BLUE}│"
    echo -e "│  ${NC}[7] 添加监控小鸡        [8] 卸载服务端          ${BLUE}│"
    echo -e "├───────────────────────────────────────────────┤"
    echo -e "│                 ${PURPLE}客户端管理${BLUE}                      │"
    echo -e "│  ${NC}[9] 安装客户端          [10] 开启vnstat        ${BLUE}│"
    echo -e "│  ${NC}[11] 卸载客户端         [0] 退出程序           ${BLUE}│"
    echo -e "└───────────────────────────────────────────────┘${NC}"
}

# 安装服务端
install_server() {
    echo -e "${YELLOW}开始安装服务端...${NC}"
    bash install-rust_serverstatus.sh "http://127.0.0.1:8080/report" "${DEFAULT_INSTALL_DIR}" "root" "$(hostname)" "$(openssl rand -base64 12)" "yes"
    
    # 获取本机IP
    local SERVER_IP=$(curl -s ip.sb || wget -qO- ip.sb)
    
    echo -e "\n${GREEN}服务端安装完成！${NC}"
    echo -e "${YELLOW}访问地址：${NC}${GREEN}http://${SERVER_IP}:8080${NC}"
    echo -e "\n${YELLOW}提示：${NC}可以通过菜单的'开启世界地图'选项来配置管理员账号"
}

# 编辑配置文件
edit_config() {
    echo -e "${YELLOW}正在打开配置文件...${NC}"
    if [ ! -f "${DEFAULT_INSTALL_DIR}/config.toml" ]; then
        echo -e "${RED}错误：配置文件不存在${NC}"
        return 1
    fi
    nano "${DEFAULT_INSTALL_DIR}/config.toml"
    
    # 重启服务端以应用更改
    echo -e "${YELLOW}正在重启服务端以应用更改...${NC}"
    systemctl restart stat_server
    echo -e "${GREEN}配置已更新并重启服务端${NC}"
}

# 安装客户端
install_client() {
    echo -e "${YELLOW}开始安装客户端...${NC}"
    
    # 检查客户端是否已安装
    if [ -f "/etc/systemd/system/stat_client.service" ]; then
        echo -e "${YELLOW}提示：检测到客户端已安装${NC}"
        read -p "是否重新安装？(y/n): " reinstall_choice
        if [[ ! $reinstall_choice =~ ^[Yy]$ ]]; then
            return
        fi
        # 停止现有客户端服务
        echo -e "${YELLOW}停止现有客户端服务...${NC}"
        systemctl stop stat_client
    fi
    
    read -p "请输入服务端地址 (例如: http://IP:8080/report): " server_addr
    
    # 检查地址格式
    if [[ ! $server_addr =~ ^http[s]?://.*[0-9]+/report$ ]]; then
        echo -e "${YELLOW}提示：服务端地址应以 /report 结尾${NC}"
        if [[ ! $server_addr =~ /report$ ]]; then
            server_addr="${server_addr}/report"
        fi
    fi
    
    # 获取系统信息并生成配置
    get_system_info
    read -p "请输入展示名称 (例如：OVh杜甫): " display_name
    read -p "请输入连接密码: " password
    
    # 从 MEMORY_GB 中移除 'G' 后缀用于显示
    local memory_value=${MEMORY_GB%G}
    
    echo -e "${YELLOW}正在安装客户端...${NC}"
    # 安装客户端
    bash install-rust_serverstatus.sh "$server_addr" "${DEFAULT_INSTALL_DIR}" "root" "$(hostname)" "$password"
    
    # 清屏并显示配置信息
    clear
    echo -e "${GREEN}=== 系统信息 ===${NC}"
    echo -e "主机名: ${YELLOW}${HOSTNAME}${NC}"
    echo -e "系统: ${YELLOW}${OS}${NC}"
    echo -e "配置: ${YELLOW}${CPU_CORES}C/${memory_value}G/${DISK_GB}G${NC}"
    echo -e "虚拟化: ${YELLOW}${VIRT_TYPE}${NC}"
    echo -e "国家: ${YELLOW}${COUNTRY_CODE}${NC}"
    
    echo -e "\n${GREEN}=== 配置信息（请复制以下内容） ===${NC}"
    echo -e "${YELLOW}{name = \"${HOSTNAME}\", password = \"${password}\", alias = \"${display_name}\", location = \"${COUNTRY_CODE}\", type = \"${VIRT_TYPE}\", labels = \"os=${OS};spec=${CPU_CORES}C/${memory_value}G/${DISK_GB}G;\"}${NC}"
    
    echo -e "\n${YELLOW}后续步骤：${NC}"
    echo -e "1. 客户端已安装完成"
    echo -e "2. 请复制上面的配置信息"
    echo -e "3. 在服务端执行脚本"
    echo -e "4. 选择'添加监控小鸡'选项"
    echo -e "5. 将配置信息粘贴到服务端"
}

# 开启世界地图
enable_map() {
    echo -e "${YELLOW}配置世界地图访问凭据...${NC}"
    local config_file="${DEFAULT_INSTALL_DIR}/config.toml"
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}错误：配置文件不存在${NC}"
        return 1
    fi
    
    # 获取新的用户名和密码
    read -p "请输入管理员用户名: " admin_user
    read -p "请输入管理员密码: " admin_pass
    
    # 生成随机 JWT secret
    local jwt_secret=$(openssl rand -base64 16)
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 更新配置文件
    while IFS= read -r line; do
        if [[ $line =~ ^jwt_secret[[:space:]]*= ]]; then
            echo "jwt_secret = \"$jwt_secret\"" >> "$temp_file"
        elif [[ $line =~ ^admin_user[[:space:]]*= ]]; then
            echo "admin_user = \"$admin_user\"" >> "$temp_file"
        elif [[ $line =~ ^admin_pass[[:space:]]*= ]]; then
            echo "admin_pass = \"$admin_pass\"" >> "$temp_file"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$config_file"
    
    # 替换原文件
    mv "$temp_file" "$config_file"
    
    # 重启服务端以应用更改
    systemctl restart stat_server
    
    echo -e "${GREEN}世界地图配置已更新${NC}"
    echo -e "${YELLOW}访问方式：${NC}"
    echo -e "1. 直接访问：${GREEN}https://你的域名/map${NC}"
    echo -e "${YELLOW}管理员账号：${NC}"
    echo -e "用户名：${GREEN}${admin_user}${NC}"
    echo -e "密码：${GREEN}${admin_pass}${NC}"
}

# 开启 vnstat 支持
enable_vnstat() {
    echo -e "${YELLOW}正在安装和配置 vnstat...${NC}"
    apt-get install -y vnstat
    
    # 配置 vnstat
    sed -i 's/^Interface.*$/Interface ""/' /etc/vnstat.conf
    sed -i 's/^BandwidthDetection.*$/BandwidthDetection 0/' /etc/vnstat.conf
    sed -i 's/^MaxBandwidth.*$/MaxBandwidth 0/' /etc/vnstat.conf
    
    # 重启服务
    systemctl restart vnstat
    
    # 修改客户端服务配置
    sed -i 's/ExecStart=\(.*\)$/ExecStart=\1 -n/' /etc/systemd/system/stat_client.service
    
    systemctl daemon-reload
    systemctl restart stat_client
    
    echo -e "${GREEN}vnstat 已安装并配置完成${NC}"
}

# 添加卸载服务端函数
uninstall_server() {
    echo -e "${YELLOW}正在卸载服务端...${NC}"
    
    # 先卸载客户端（如果存在）
    if [ -f "/etc/systemd/system/stat_client.service" ]; then
        uninstall_client
    fi
    
    # 停止并禁用服务
    systemctl stop stat_server
    systemctl disable stat_server
    
    # 删除服务文件
    rm -f /etc/systemd/system/stat_server.service
    
    # 删除安装目录
    rm -rf "${DEFAULT_INSTALL_DIR}"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    echo -e "${GREEN}服务端已完全卸载${NC}"
}

# 添加卸载客户端函数
uninstall_client() {
    echo -e "${YELLOW}正在卸载客户端...${NC}"
    
    # 停止并禁用服务
    systemctl stop stat_client
    systemctl disable stat_client
    
    # 删除服务文件
    rm -f /etc/systemd/system/stat_client.service
    
    # 删除客户端文件
    rm -f "${DEFAULT_INSTALL_DIR}/stat_client"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    echo -e "${GREEN}客户端已完全卸载${NC}"
}

# 添加新函数：添加监控小鸡
add_monitoring_host() {
    echo -e "${YELLOW}添加新的监控主机${NC}"
    echo -e "请粘贴从客户端获取的配置信息（格式如：{name = \"hostname\", ...}）"
    echo -e "提示：在客户端执行脚本,选择'安装客户端'选项\n"
    
    # 读取用户输入的配置
    read -p "请粘贴配置: " host_config
    
    # 验证输入格式
    if [[ ! $host_config =~ ^\{.*\}$ ]]; then
        echo -e "${RED}错误：配置格式不正确${NC}"
        return 1
    fi
    
    # 从配置中提取信息
    name=$(echo "$host_config" | grep -o 'name = "[^"]*"' | cut -d'"' -f2)
    password=$(echo "$host_config" | grep -o 'password = "[^"]*"' | cut -d'"' -f2)
    alias=$(echo "$host_config" | grep -o 'alias = "[^"]*"' | cut -d'"' -f2)
    
    if [ -z "$name" ] || [ -z "$password" ] || [ -z "$alias" ]; then
        echo -e "${RED}错误：无法从配置中提取必要信息${NC}"
        return 1
    fi
    
    # 重新配置文件
    update_config "$name" "$password" "$alias"
    
    # 重启服务端以应用新配置
    echo -e "${YELLOW}正在重启服务端以应用新配置...${NC}"
    systemctl restart stat_server
    
    echo -e "\n${GREEN}监控主机添加成功！${NC}"
    echo -e "${YELLOW}提示：${NC}"
    echo -e "1. 服务端已重启，新配置已生效"
    echo -e "2. 请确保客户端已正确安装并配置"
}

# 添加配置告警通知的函数
configure_notifications() {
    while true; do
        echo -e "${BLUE}=== 告警通知配置 ===${NC}"
        echo "1. 配置 Telegram 通知"
        echo "2. 配置邮件告警通知"
        echo "0. 返回主菜单"
        echo -e "${BLUE}===================${NC}"
        
        read -p "请选择操作 [0-2]: " choice
        
        case $choice in
            1) configure_telegram ;;
            2) configure_email ;;
            0) return ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        
        echo
        read -p "按回车键继续..."
    done
}

# 配置 Telegram 通知
configure_telegram() {
    echo -e "${YELLOW}配置 Telegram 通知${NC}"
    read -p "请输入 Bot Token: " bot_token
    read -p "请输入 Chat ID: " chat_id
    
    local config_file="${DEFAULT_INSTALL_DIR}/config.toml"
    
    # 先启用通知功能
    sed -i 's/enabled = false/enabled = true/' "$config_file" 2>/dev/null
    
    # 更新 Telegram 配置
    sed -i "/^\[tgbot\]/,/^\[/ {
        s/^enabled = .*/enabled = true/
        s/^bot_token = .*/bot_token = \"$bot_token\"/
        s/^chat_id = .*/chat_id = \"$chat_id\"/
        s/{{host\.location}}/{{host\.alias}}/g
        s/0\.5/0.8/g
        s/50%/80%/g
    }" "$config_file" 2>/dev/null
    
    # 重启服务以应用新配置
    systemctl restart stat_server
    
    echo -e "${GREEN}Telegram 通知配置已更新${NC}"
    echo -e "${YELLOW}提示：通知消息中将使用别名(alias)代替位置(location)显示${NC}"
}

# 配置邮件通知
configure_email() {
    echo -e "${YELLOW}配置邮件通知${NC}"
    read -p "请输入 SMTP 服务器地址: " smtp_server
    read -p "请输入邮箱用户名: " email_user
    read -p "请输入邮箱密码: " email_pass
    read -p "请输入接收通知的邮箱(多个邮箱用分号;分隔): " email_to
    
    local config_file="${DEFAULT_INSTALL_DIR}/config.toml"
    
    # 先启用通知功能
    sed -i 's/enabled = false/enabled = true/' "$config_file" 2>/dev/null
    
    # 更新邮件配置
    sed -i "/^\[email\]/,/^\[/ {
        s/^enabled = .*/enabled = true/
        s/^server = .*/server = \"$smtp_server\"/
        s/^username = .*/username = \"$email_user\"/
        s/^password = .*/password = \"$email_pass\"/
        s/^to = .*/to = \"$email_to\"/
        s/{{host\.location}}/{{host\.alias}}/g
        s/0\.5/0.8/g
        s/50%/80%/g
    }" "$config_file" 2>/dev/null
    
    # 重启服务以应用新配置
    systemctl restart stat_server
    
    echo -e "${GREEN}邮件通知配置已更新${NC}"
    echo -e "${YELLOW}提示：通知消息中将使用别名(alias)代替位置(location)显示${NC}"
}

# 添加重启服务端函数
restart_server() {
    echo -e "${YELLOW}正在重启服务端...${NC}"
    systemctl restart stat_server
    echo -e "${GREEN}服务端已重启${NC}"
}

# 添加安装必要工具的函数
install_requirements() {
    echo -e "${YELLOW}正在安装必要工具...${NC}"
    
    # 更新软件包列表
    apt-get update
    
    # 安装必要工具
    apt-get install -y nano curl wget
    
    # 检查安装结果
    local tools=("nano" "curl" "wget")
    local all_installed=true
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}$tool 安装失败${NC}"
            all_installed=false
        fi
    done
    
    if $all_installed; then
        echo -e "${GREEN}所有工具安装完成！${NC}"
        echo -e "\n${YELLOW}已安装的工具：${NC}"
        echo -e "1. nano  - 文本编辑器"
        echo -e "2. curl  - 文件传输工具"
        echo -e "3. wget  - 网络下载工具"
    else
        echo -e "${RED}部分工具安装失败，请检查系统环境后重试${NC}"
    fi
}

# 修改主循环更新选项处理
while true; do
    show_menu
    read -p $'\n'"请输入选项 [0-11]: " choice
    echo
    
    case $choice in
        1) install_requirements ;;
        2) edit_config ;;
        3) install_server ;;
        4) restart_server ;;
        5) enable_map ;;
        6) configure_notifications ;;
        7) add_monitoring_host ;;
        8) uninstall_server ;;
        9) install_client ;;
        10) enable_vnstat ;;
        11) uninstall_client ;;
        0) 
            clear
            echo -e "${GREEN}感谢使用 ServerStatus 探针脚本！${NC}"
            echo -e "${YELLOW}项目地址：${NC}github.com/zdz/ServerStatus-Rust"
            echo
            exit 0 
            ;;
        *) echo -e "${RED}无效的选择${NC}" ;;
    esac
    
    echo
    read -p "按回车键继续..."
done 