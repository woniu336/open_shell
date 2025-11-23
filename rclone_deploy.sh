#!/bin/bash

# ===========================================
# Rclone 单向实时同步 - 一键部署脚本
# ===========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 配置变量
REMOTE_NAME="ovh"
SYNC_SCRIPT="rclone-sync.sh"
MANAGE_SCRIPT="rclone_manage.sh"

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════╗"
    echo "║   Rclone 实时同步 - 自动化部署工具        ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 成功提示
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 错误提示
error() {
    echo -e "${RED}✗ $1${NC}"
}

# 警告提示
warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 信息提示
info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# 分隔线
separator() {
    echo -e "${PURPLE}═══════════════════════════════════════════════════${NC}"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要root权限运行"
        exit 1
    fi
}

# 显示主菜单
show_menu() {
    show_banner
    separator
    echo -e "${CYAN}请选择操作:${NC}"
    echo
    echo -e "  ${GREEN}1)${NC} 完整安装 (A服务器)"
    echo -e "  ${GREEN}2)${NC} 配置B服务器公钥"
    echo -e "  ${GREEN}3)${NC} 安装 Rclone"
    echo -e "  ${GREEN}4)${NC} 生成SSH密钥对"
    echo -e "  ${GREEN}5)${NC} 创建Rclone配置"
    echo -e "  ${GREEN}6)${NC} 编辑同步脚本"
    echo -e "  ${GREEN}7)${NC} 编辑Rclone配置"
    echo -e "  ${GREEN}8)${NC} 测试同步并设置后台运行"
    echo -e "  ${GREEN}9)${NC} 管理同步服务"
    echo -e "  ${YELLOW}10)${NC} 文件拷贝"
    echo -e "  ${RED}0)${NC} 退出"
    echo
    separator
}

# 安装 Rclone
install_rclone() {
    info "正在安装 Rclone..."
    if command -v rclone &> /dev/null; then
        success "Rclone 已安装"
    else
        curl https://rclone.org/install.sh | bash
        success "Rclone 安装完成"
    fi
}

# 安装依赖
install_dependencies() {
    info "正在安装依赖..."
    apt update -qq
    apt install -y rclone inotify-tools
    success "依赖安装完成"
}

# 生成SSH密钥对
generate_ssh_key() {
    info "正在生成SSH密钥对..."
    mkdir -p ~/.ssh
    if [[ -f ~/.ssh/id_ed25519 ]]; then
        warning "密钥已存在,跳过生成"
    else
        ssh-keygen -t ed25519 -C "rclone-copy" -f ~/.ssh/id_ed25519 -N ""
        success "密钥生成完成"
    fi
    
    echo
    separator
    echo -e "${YELLOW}公钥内容 (请复制到B服务器):${NC}"
    separator
    cat ~/.ssh/id_ed25519.pub
    separator
    echo
    read -p "按回车键继续..."
}

# 配置B服务器公钥
configure_remote_server() {
    info "配置B服务器 - 添加公钥"
    echo
    warning "请在B服务器上运行以下命令:"
    echo
    echo -e "${CYAN}read -p \"请输入你的公钥内容: \" PUBKEY && mkdir -p /root/.ssh && touch /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && grep -qxF \"\$PUBKEY\" /root/.ssh/authorized_keys || echo \"\$PUBKEY\" >> /root/.ssh/authorized_keys && echo \"✅ 公钥已添加\"${NC}"
    echo
    read -p "完成后按回车键继续..."
}

# 创建Rclone配置
create_rclone_config() {
    info "创建 Rclone 配置..."
    
    read -p "$(echo -e ${CYAN}请输入B服务器IP地址: ${NC})" remote_host
    read -p "$(echo -e ${CYAN}请输入B服务器SSH端口 [22]: ${NC})" remote_port
    remote_port=${remote_port:-22}
    read -p "$(echo -e ${CYAN}请输入远程名称 [ovh]: ${NC})" remote_name
    remote_name=${remote_name:-ovh}
    REMOTE_NAME=$remote_name
    
    mkdir -p ~/.config/rclone
    
    cat > ~/.config/rclone/rclone.conf << EOF
[$REMOTE_NAME]
type = sftp
host = $remote_host
user = root
port = $remote_port
key_file = ~/.ssh/id_ed25519
shell_type = unix
md5sum_command = md5sum
sha1sum_command = sha1sum
EOF
    
    success "Rclone 配置文件创建完成"
    info "配置文件路径: ~/.config/rclone/rclone.conf"
}

# 编辑Rclone配置
edit_rclone_config() {
    separator
    echo -e "${CYAN}Rclone 配置管理:${NC}"
    echo
    
    local config_file="$HOME/.config/rclone/rclone.conf"
    
    # 检查配置文件是否存在
    if [[ -f "$config_file" ]]; then
        success "配置文件已存在: $config_file"
        echo
        info "当前配置的远程:"
        rclone listremotes 2>/dev/null || warning "无法列出远程配置"
        echo
        echo -e "  ${GREEN}1)${NC} 编辑配置文件"
        echo -e "  ${GREEN}2)${NC} 查看配置文件"
        echo -e "  ${GREEN}3)${NC} 测试远程连接"
        echo -e "  ${GREEN}4)${NC} 添加新的远程"
        echo -e "  ${GREEN}5)${NC} 删除配置文件"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        separator
        read -p "请选择: " config_choice
        
        case $config_choice in
            1) 
                info "打开配置编辑器..."
                ${EDITOR:-nano} "$config_file"
                success "编辑完成"
                sleep 1
                ;;
            2) 
                echo
                info "配置文件内容:"
                separator
                cat "$config_file"
                separator
                echo
                read -p "按回车键继续..."
                ;;
            3) 
                test_remote_connection
                ;;
            4) 
                create_rclone_config
                ;;
            5) 
                delete_rclone_config "$config_file"
                ;;
            0) 
                return
                ;;
            *)
                error "无效选择"
                sleep 1
                ;;
        esac
    else
        warning "配置文件不存在"
        echo
        echo -e "  ${GREEN}1)${NC} 创建新配置"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        separator
        read -p "请选择: " create_choice
        
        case $create_choice in
            1) 
                create_rclone_config
                ;;
            0) 
                return
                ;;
            *)
                error "无效选择"
                sleep 1
                ;;
        esac
    fi
}

# 测试远程连接
test_remote_connection() {
    echo
    read -p "$(echo -e ${CYAN}请输入要测试的远程名称: ${NC})" test_remote
    
    info "测试连接到: $test_remote"
    echo
    
    if rclone lsd "$test_remote:" 2>/dev/null; then
        success "连接成功!"
    else
        error "连接失败,请检查配置"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 删除配置文件
delete_rclone_config() {
    local config_file=$1
    echo
    warning "确定要删除配置文件吗? 此操作不可恢复!"
    read -p "输入 'yes' 确认删除: " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        # 创建备份
        cp "$config_file" "$config_file.bak.$(date +%Y%m%d_%H%M%S)"
        success "已创建备份"
        
        rm -f "$config_file"
        success "配置文件已删除"
    else
        info "已取消删除"
    fi
    
    sleep 2
}

# 编辑同步脚本
edit_sync_script() {
    separator
    echo -e "${CYAN}同步脚本编辑:${NC}"
    echo
    
    # 检查脚本是否存在
    if [[ -f "./rclone-sync.sh" ]]; then
        success "同步脚本已存在: ./rclone-sync.sh"
        echo
        echo -e "  ${GREEN}1)${NC} 直接编辑脚本"
        echo -e "  ${GREEN}2)${NC} 重新下载脚本"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        separator
        read -p "请选择: " edit_choice
        
        case $edit_choice in
            1) 
                info "打开编辑器..."
                ${EDITOR:-nano} rclone-sync.sh
                success "编辑完成"
                sleep 1
                ;;
            2) 
                warning "将重新下载脚本,是否继续? (y/n)"
                read -p "> " confirm
                if [[ $confirm == "y" ]]; then
                    download_sync_script
                else
                    info "已取消"
                    sleep 1
                fi
                ;;
            0) 
                return
                ;;
            *)
                error "无效选择"
                sleep 1
                ;;
        esac
    else
        warning "同步脚本不存在"
        echo
        echo -e "  ${GREEN}1)${NC} 下载同步脚本"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        separator
        read -p "请选择: " download_choice
        
        case $download_choice in
            1) 
                download_sync_script
                ;;
            0) 
                return
                ;;
            *)
                error "无效选择"
                sleep 1
                ;;
        esac
    fi
}

# 下载同步脚本
download_sync_script() {
    info "下载同步脚本..."
    curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/rclone-sync.sh
    chmod +x rclone-sync.sh
    success "同步脚本下载完成"
    
    echo
    warning "请编辑 rclone-sync.sh 修改同步目录"
    read -p "是否现在编辑? (y/n): " edit_choice
    if [[ $edit_choice == "y" ]]; then
        ${EDITOR:-nano} rclone-sync.sh
    fi
}

# 测试同步并设置后台运行
test_sync_and_setup() {
    if [[ ! -f "./rclone-sync.sh" ]]; then
        error "未找到同步脚本,请先下载"
        return 1
    fi
    
    separator
    echo -e "${CYAN}测试同步并设置后台运行${NC}"
    echo
    
    # 提取配置信息
    LOCAL_PATH=$(grep "^RCLONE_SYNC_PATH=" rclone-sync.sh | cut -d'"' -f2 | cut -d"'" -f2)
    REMOTE_PATH=$(grep "^RCLONE_REMOTE=" rclone-sync.sh | cut -d'"' -f2 | cut -d"'" -f2)
    
    if [[ -z "$LOCAL_PATH" || -z "$REMOTE_PATH" ]]; then
        error "无法提取同步路径配置"
        warning "请确保 rclone-sync.sh 中已正确配置 RCLONE_SYNC_PATH 和 RCLONE_REMOTE"
        sleep 2
        return 1
    fi
    
    info "同步配置:"
    echo -e "  本地目录: ${BLUE}$LOCAL_PATH${NC}"
    echo -e "  远程目录: ${BLUE}$REMOTE_PATH${NC}"
    echo
    
    # 检查本地目录是否存在
    if [[ ! -d "$LOCAL_PATH" ]]; then
        warning "本地目录不存在: $LOCAL_PATH"
        read -p "是否创建该目录? (y/n): " create_dir
        if [[ $create_dir == "y" ]]; then
            mkdir -p "$LOCAL_PATH"
            chmod 755 "$LOCAL_PATH"
            success "目录已创建"
        else
            error "请先创建目录后再继续"
            return 1
        fi
    fi
    
    echo -e "${YELLOW}开始测试同步...${NC}"
    echo -e "${YELLOW}提示: 按 Ctrl+C 可随时停止测试${NC}"
    echo
    read -p "按回车键开始测试 (或输入 n 跳过测试): " skip_test
    
    if [[ $skip_test != "n" ]]; then
        info "执行首次同步测试 (30秒)..."
        if timeout 30 ./rclone-sync.sh 2>&1 | head -20; then
            success "同步测试完成"
        else
            exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                success "同步测试通过 (已自动停止)"
            else
                warning "同步测试中断,这可能是正常的"
            fi
        fi
    fi
    
    echo
    separator
    echo -e "${CYAN}是否设置后台运行?${NC}"
    echo
    echo -e "  ${GREEN}y)${NC} 是,设置为系统服务自动运行"
    echo -e "  ${RED}n)${NC} 否,稍后手动设置"
    echo
    read -p "请选择 (y/n): " setup_service
    
    if [[ $setup_service == "y" ]]; then
        echo
        info "配置 systemd 服务..."
        
        # 启用 linger
        loginctl enable-linger root 2>/dev/null
        
        # 设置 systemd 服务
        if ./rclone-sync.sh systemd_setup; then
            success "后台服务设置完成"
            echo
            
            # 获取服务名称
            SERVICE_NAME=$(echo "$REMOTE_PATH" | sed 's/[:/\.]/_/g')
            
            sleep 2
            
            # 静默执行修复脚本
            info "正在优化服务配置..."
            if curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fix_rclone.sh &>/dev/null; then
                chmod +x fix_rclone.sh &>/dev/null
                # 静默执行修复脚本，自动输入 'y' 确认
                echo "y" | ./fix_rclone.sh &>/dev/null
                rm -f fix_rclone.sh &>/dev/null
                success "服务优化完成"
            fi
            
            sleep 1
            
            # 显示服务状态
            info "服务状态:"
            systemctl --user status "rclone_sync_${SERVICE_NAME}.service" --no-pager | head -15
            
            echo
            success "设置完成!"
            echo
            info "常用命令:"
            echo -e "  查看状态: ${CYAN}systemctl --user status rclone_sync_${SERVICE_NAME}.service${NC}"
            echo -e "  查看日志: ${CYAN}journalctl --user -u rclone_sync_${SERVICE_NAME}.service -f${NC}"
            echo -e "  重启服务: ${CYAN}systemctl --user restart rclone_sync_${SERVICE_NAME}.service${NC}"
            echo -e "  停止服务: ${CYAN}systemctl --user stop rclone_sync_${SERVICE_NAME}.service${NC}"
        else
            error "服务设置失败"
            warning "请检查错误信息或手动执行: ./rclone-sync.sh systemd_setup"
        fi
    else
        info "已跳过后台服务设置"
        echo
        info "稍后可运行以下命令设置:"
        echo -e "  ${CYAN}./rclone-sync.sh systemd_setup${NC}"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 获取服务名称
get_service_name() {
    local services=(~/.config/systemd/user/rclone_sync_*.service)
    if [[ -f "${services[0]}" ]]; then
        basename "${services[0]}"
    else
        echo ""
    fi
}

# 管理同步服务
manage_sync_service() {
    local service_name=$(get_service_name)
    
    if [[ -z "$service_name" ]]; then
        error "未找到同步服务,请先设置后台运行"
        sleep 2
        return
    fi
    
    while true; do
        separator
        echo -e "${CYAN}同步服务管理:${NC}"
        echo -e "${YELLOW}当前服务: ${service_name}${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} 查看服务状态"
        echo -e "  ${GREEN}2)${NC} 启动服务"
        echo -e "  ${GREEN}3)${NC} 停止服务"
        echo -e "  ${GREEN}4)${NC} 重启服务"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        separator
        read -p "请选择: " manage_choice
        
        case $manage_choice in
            1) service_status "$service_name" ;;
            2) service_start "$service_name" ;;
            3) service_stop "$service_name" ;;
            4) service_restart "$service_name" ;;
            0) return ;;
            *) 
                error "无效选择"
                sleep 1
                ;;
        esac
    done
}

# 查看服务状态
service_status() {
    local service_name=$1
    echo
    info "查看服务状态..."
    echo
    systemctl --user status "$service_name" --no-pager
    echo
    read -p "按回车键继续..."
}

# 启动服务
service_start() {
    local service_name=$1
    echo
    info "启动同步服务..."
    if systemctl --user start "$service_name"; then
        success "服务启动成功"
    else
        error "服务启动失败"
    fi
    sleep 1
}

# 停止服务
service_stop() {
    local service_name=$1
    echo
    warning "停止同步服务..."
    if systemctl --user stop "$service_name"; then
        success "服务停止成功"
    else
        error "服务停止失败"
    fi
    sleep 1
}

# 重启服务
service_restart() {
    local service_name=$1
    echo
    info "重启同步服务..."
    if systemctl --user restart "$service_name"; then
        success "服务重启成功"
    else
        error "服务重启失败"
    fi
    sleep 1
}

# 查看实时日志
service_logs_follow() {
    local service_name=$1
    echo
    info "查看实时日志 (按 Ctrl+C 退出)..."
    sleep 2
    journalctl --user -u "$service_name" -f
}

# 查看最近日志
service_logs_recent() {
    local service_name=$1
    echo
    info "最近50行日志:"
    echo
    journalctl --user -u "$service_name" -n 50 --no-pager
    echo
    read -p "按回车键继续..."
}

# 文件操作菜单
file_operations() {
    separator
    echo -e "${CYAN}文件拷贝:${NC}"
    echo
    
    read -p "$(echo -e ${CYAN}rclone名称: ${NC})" remote_name_input
    
    read -p "$(echo -e ${CYAN}本地目录: ${NC})" local_path
    read -p "$(echo -e ${CYAN}远程目录: ${NC})" remote_path
    
    echo
    info "开始拷贝文件..."
    echo -e "${YELLOW}命令: rclone copy $local_path $remote_name_input:$remote_path -P --transfers=16 --multi-thread-streams=4${NC}"
    echo
    
    rclone copy "$local_path" "$remote_name_input:$remote_path" \
        -P \
        --transfers=16 \
        --multi-thread-streams=4
    
    echo
    success "文件拷贝完成"
    read -p "按回车键继续..."
}

# 完整安装
full_install() {
    info "开始完整安装流程..."
    sleep 2
    
    install_dependencies
    sleep 1
    
    generate_ssh_key
    
    echo
    warning "请在B服务器配置公钥后继续..."
    read -p "按回车键继续..."
    
    create_rclone_config
    sleep 1
    
    download_sync_script
    sleep 1
    
    success "完整安装完成!"
    echo
    info "下一步:"
    echo "  1. 编辑 rclone-sync.sh 修改同步目录"
    echo "  2. 选择菜单 [8] 测试同步并设置后台运行"
    echo
    read -p "按回车键继续..."
}

# 主循环
main() {
    check_root
    
    while true; do
        show_menu
        read -p "请选择 [0-10]: " choice
        
        case $choice in
            1) full_install ;;
            2) configure_remote_server ;;
            3) install_rclone ;;
            4) generate_ssh_key ;;
            5) create_rclone_config ;;
            6) edit_sync_script ;;
            7) edit_rclone_config ;;
            8) test_sync_and_setup ;;
            9) manage_sync_service ;;
            10) file_operations ;;
            0) 
                echo
                success "感谢使用!"
                exit 0
                ;;
            *)
                error "无效选择,请重试"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main
