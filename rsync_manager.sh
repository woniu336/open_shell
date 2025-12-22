#!/bin/bash

# ============================================
# RSYNC 远程同步管理工具
# 功能：任务管理、双向同步、定时任务、密钥管理
# ============================================

# 配置变量
CONFIG_DIR="$HOME/.rsync_manager"
CONFIG_FILE="$CONFIG_DIR/tasks.conf"
KEY_DIR="$CONFIG_DIR/keys"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/rsync_$(date +%Y%m%d).log"
MONITOR_DIR="$CONFIG_DIR/monitors"
MONITOR_PID_FILE="$MONITOR_DIR/monitor.pid"

# 初始化目录结构
init_dirs() {
    mkdir -p "$CONFIG_DIR" "$KEY_DIR" "$LOG_DIR" "$MONITOR_DIR"
    touch "$CONFIG_FILE"
    chmod 700 "$CONFIG_DIR"
    chmod 600 "$CONFIG_FILE"
    chmod 700 "$KEY_DIR"
    chmod 700 "$MONITOR_DIR"
}

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示消息函数
show_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
show_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
show_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# 核心功能函数
# ============================================

# 显示任务列表
list_tasks() {
    if [[ ! -s "$CONFIG_FILE" ]]; then
        show_warning "暂无同步任务"
        return
    fi
    
    echo "已保存的同步任务:"
    echo "========================================="
    printf "%-4s %-20s %-30s %-30s\n" "编号" "任务名称" "本地目录" "远程目录"
    echo "-----------------------------------------"
    
    local count=1
    while IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key; do
        printf "%-4s %-20s %-30s %-30s\n" "$count" "$name" "$local_path" "$remote:$remote_path"
        ((count++))
    done < "$CONFIG_FILE"
    
    echo "========================================="
}

# 添加新任务
add_task() {
    log "INFO" "开始添加新任务"
    
    echo "创建新同步任务："
    echo "---------------------------------"
    
    # 输入验证函数
    validate_input() {
        local prompt="$1"
        local var_name="$2"
        local required="${3:-true}"
        
        while true; do
            read -e -p "$prompt: " input
            
            if [[ "$required" == "true" && -z "$input" ]]; then
                show_error "此项为必填项！"
                continue
            fi
            
            if [[ -z "$input" && "$required" == "false" ]]; then
                break
            fi
            
            eval "$var_name=\"$input\""
            break
        done
    }
    
    # 收集任务信息
    validate_input "请输入任务名称" "name"
    validate_input "请输入本地目录" "local_path"
    validate_input "请输入远程用户@IP (如: user@192.168.1.100)" "remote"
    validate_input "请输入远程目录" "remote_path"
    
    read -e -p "请输入 SSH 端口 (默认 22): " port
    port=${port:-22}
    
    # 选择身份验证方式
    echo "请选择身份验证方式:"
    echo "1. 密码认证"
    echo "2. 密钥认证"
    
    while true; do
        read -e -p "请选择 (1/2): " auth_choice
        case $auth_choice in
            1)
                read -s -p "请输入密码: " password
                echo
                auth_method="password"
                password_or_key="$password"
                break
                ;;
            2)
                echo "请选择密钥来源:"
                echo "1. 粘贴密钥内容"
                echo "2. 指定密钥文件路径"
                read -e -p "请选择 (1/2): " key_source
                
                case $key_source in
                    1)
                        echo "请粘贴私钥内容 (以空行结束):"
                        local key_content=""
                        while IFS= read -r line; do
                            if [[ -z "$line" && "$key_content" == *"-----BEGIN"* ]]; then
                                break
                            fi
                            if [[ -n "$line" || "$key_content" == *"-----BEGIN"* ]]; then
                                key_content+="${line}"$'\n'
                            fi
                        done
                        
                        if [[ "$key_content" == *"-----BEGIN"* && "$key_content" == *"PRIVATE KEY-----"* ]]; then
                            local key_file="$KEY_DIR/${name}_$(date +%s).key"
                            echo -n "$key_content" > "$key_file"
                            chmod 600 "$key_file"
                            password_or_key="$key_file"
                            auth_method="key"
                            show_success "密钥已保存到: $key_file"
                        else
                            show_error "无效的密钥格式！"
                            return
                        fi
                        ;;
                    2)
                        read -e -p "请输入密钥文件路径: " key_path
                        if [[ -f "$key_path" ]]; then
                            # 复制密钥到安全目录
                            local key_file="$KEY_DIR/${name}_$(basename "$key_path")"
                            cp "$key_path" "$key_file"
                            chmod 600 "$key_file"
                            password_or_key="$key_file"
                            auth_method="key"
                            show_success "密钥已复制到: $key_file"
                        else
                            show_error "密钥文件不存在: $key_path"
                            return
                        fi
                        ;;
                    *)
                        show_error "无效的选择！"
                        return
                        ;;
                esac
                break
                ;;
            *)
                show_error "无效的选择！"
                ;;
        esac
    done
    
    # 选择同步模式
    echo "请选择同步模式:"
    echo "1. 标准模式 (-avz)"
    echo "2. 归档模式 (-a)"
    echo "3. 带删除的模式 (-avz --delete)"
    echo "4. 自定义选项"
    
    read -e -p "请选择 (1-4): " mode_choice
    case $mode_choice in
        1) options="-avz" ;;
        2) options="-a" ;;
        3) options="-avz --delete" ;;
        4)
            read -e -p "请输入自定义rsync选项: " custom_options
            options="$custom_options"
            ;;
        *)
            show_warning "无效选择，使用默认选项 -avz"
            options="-avz"
            ;;
    esac
    
    # 保存任务
    echo "$name|$local_path|$remote|$remote_path|$port|$options|$auth_method|$password_or_key" >> "$CONFIG_FILE"
    
    # 检查依赖
    check_dependencies
    
    show_success "任务 '$name' 已保存！"
    log "INFO" "添加新任务: $name"
}

# 删除任务
delete_task() {
    log "INFO" "开始删除任务"
    
    if [[ ! -s "$CONFIG_FILE" ]]; then
        show_warning "暂无同步任务可删除"
        return
    fi
    
    list_tasks
    read -e -p "请输入要删除的任务编号: " num
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        show_error "请输入有效的数字编号！"
        return
    fi
    
    local task=$(sed -n "${num}p" "$CONFIG_FILE")
    if [[ -z "$task" ]]; then
        show_error "未找到对应的任务！"
        return
    fi
    
    IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"
    
    # 确认删除
    read -e -p "确认删除任务 '$name' 吗？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        show_info "取消删除"
        return
    fi
    
    # 如果任务使用的是密钥文件，则删除该密钥文件
    if [[ "$auth_method" == "key" && -f "$password_or_key" ]]; then
        rm -f "$password_or_key"
        show_info "已删除密钥文件: $password_or_key"
    fi
    
    # 清理定时任务相关文件
    local wrapper_script="$CONFIG_DIR/rsync_wrapper_$num.sh"
    if [[ -f "$wrapper_script" ]]; then
        # 从crontab中删除定时任务
        crontab -l 2>/dev/null | grep -v "$wrapper_script" | crontab -
        # 删除包装脚本
        rm -f "$wrapper_script"
        show_info "已删除定时任务包装脚本: $wrapper_script"
    fi
    
    # 清理监控相关文件
    local monitor_script="$MONITOR_DIR/monitor_$num.sh"
    if [[ -f "$monitor_script" ]]; then
        rm -f "$monitor_script"
        show_info "已删除监控脚本: $monitor_script"
    fi
    
    # 清理监控日志文件
    local monitor_log="$LOG_DIR/monitor_$num.log"
    if [[ -f "$monitor_log" ]]; then
        rm -f "$monitor_log"
        show_info "已删除监控日志: $monitor_log"
    fi
    
    # 清理监控PID文件（如果这个任务正在被监控）
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        local pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
        local task_file="$MONITOR_DIR/monitor_task_$pid"
        if [[ -f "$task_file" ]]; then
            local monitored_task_num=$(cat "$task_file" 2>/dev/null)
            if [[ "$monitored_task_num" == "$num" ]]; then
                # 停止监控进程
                if kill -0 "$pid" 2>/dev/null; then
                    kill -TERM "$pid" 2>/dev/null
                    show_info "已停止监控进程 (PID: $pid)"
                fi
                rm -f "$MONITOR_PID_FILE" "$task_file"
            fi
        fi
    fi
    
    # 从配置文件中删除任务
    sed -i "${num}d" "$CONFIG_FILE"
    
    show_success "任务 '$name' 已删除！"
    log "INFO" "删除任务: $name，并清理了相关文件"
}

# 执行同步任务
run_task() {
    local direction="$1"
    local num="$2"
    
    if [[ ! -s "$CONFIG_FILE" ]]; then
        show_error "暂无同步任务可执行"
        return
    fi
    
    # 如果没有传入任务编号，提示用户输入
    if [[ -z "$num" ]]; then
        list_tasks
        read -e -p "请输入要执行的任务编号: " num
    fi
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        show_error "请输入有效的数字编号！"
        return
    fi
    
    local task=$(sed -n "${num}p" "$CONFIG_FILE")
    if [[ -z "$task" ]]; then
        show_error "未找到对应的任务！"
        return
    fi
    
    IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"
    
    # 根据同步方向调整源和目标路径
    local source=""
    local destination=""
    
    if [[ "$direction" == "pull" ]]; then
        show_info "执行拉取同步: 从远程到本地"
        source="$remote:$local_path"
        destination="$remote_path"
        log "INFO" "开始拉取任务: $name (远程 -> 本地)"
    else
        show_info "执行推送同步: 从本地到远程"
        source="$local_path"
        destination="$remote:$remote_path"
        log "INFO" "开始推送任务: $name (本地 -> 远程)"
    fi
    
    # 检查目录是否存在
    if [[ "$direction" != "pull" && ! -d "$local_path" ]]; then
        show_error "本地目录不存在: $local_path"
        return
    fi
    
    # SSH 连接选项
    local ssh_options="-p $port -o StrictHostKeyChecking=no -o ConnectTimeout=30"
    
    # 执行同步
    show_info "开始同步任务: $name"
    show_info "选项: $options"
    show_info "源: $source"
    show_info "目标: $destination"
    
    echo "---------------------------------"
    
    local rsync_cmd=""
    
    if [[ "$auth_method" == "password" ]]; then
        # 检查 sshpass
        if ! command -v sshpass &> /dev/null; then
            show_error "未安装 sshpass，请先安装:"
            show_info "Ubuntu/Debian: sudo apt install sshpass"
            show_info "CentOS/RHEL: sudo yum install sshpass"
            return
        fi
        
        rsync_cmd="sshpass -p '$password_or_key' rsync $options -e 'ssh $ssh_options' \"$source\" \"$destination\""
    else
        # 密钥认证
        if [[ ! -f "$password_or_key" ]]; then
            show_error "密钥文件不存在: $password_or_key"
            return
        fi
        
        # 检查密钥权限
        if [[ "$(stat -c %a "$password_or_key" 2>/dev/null)" != "600" ]]; then
            show_warning "修复密钥文件权限..."
            chmod 600 "$password_or_key"
        fi
        
        rsync_cmd="rsync $options -e 'ssh -i \"$password_or_key\" $ssh_options' \"$source\" \"$destination\""
    fi
    
    # 显示执行的命令
    show_info "执行命令:"
    echo "$rsync_cmd"
    echo "---------------------------------"
    
    # 执行命令
    eval $rsync_cmd
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        show_success "同步完成！"
        log "INFO" "任务 $name 同步成功"
    else
        show_error "同步失败！退出码: $exit_code"
        log "ERROR" "任务 $name 同步失败，退出码: $exit_code"
        
        # 提供故障排除建议
        echo ""
        show_warning "故障排除建议:"
        echo "1. 检查网络连接"
        echo "2. 验证远程主机可访问性"
        echo "3. 检查认证信息"
        echo "4. 确认目录权限"
        echo "5. 查看详细日志: $LOG_FILE"
    fi
}

# 创建定时任务
schedule_task() {
    log "INFO" "开始创建定时任务"
    
    if [[ ! -s "$CONFIG_FILE" ]]; then
        show_error "暂无同步任务可定时"
        return
    fi
    
    list_tasks
    read -e -p "请输入要定时同步的任务编号: " num
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        show_error "请输入有效的数字编号！"
        return
    fi
    
    # 验证任务存在
    local task=$(sed -n "${num}p" "$CONFIG_FILE")
    if [[ -z "$task" ]]; then
        show_error "未找到对应的任务！"
        return
    fi
    
    IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"
    
    echo "请选择定时执行间隔："
    echo "1) 每小时执行一次"
    echo "2) 每天执行一次"
    echo "3) 每周执行一次"
    echo "4) 每月执行一次"
    echo "5) 自定义cron表达式"
    
    read -e -p "请输入选项 (1-5): " interval
    
    local cron_time=""
    local random_minute=$(shuf -i 0-59 -n 1)
    
    case "$interval" in
        1)
            cron_time="$random_minute * * * *"
            show_info "设置为每小时的第 $random_minute 分钟执行"
            ;;
        2)
            local random_hour=$(shuf -i 0-23 -n 1)
            cron_time="$random_minute $random_hour * * *"
            show_info "设置为每天 $random_hour:$random_minute 执行"
            ;;
        3)
            cron_time="$random_minute 0 * * 1"
            show_info "设置为每周一 00:$random_minute 执行"
            ;;
        4)
            cron_time="$random_minute 0 1 * *"
            show_info "设置为每月1日 00:$random_minute 执行"
            ;;
        5)
            read -e -p "请输入cron表达式 (分 时 日 月 周): " custom_cron
            cron_time="$custom_cron"
            ;;
        *)
            show_error "无效的选项！"
            return
            ;;
    esac
    
    # 创建包装脚本
    local wrapper_script="$CONFIG_DIR/rsync_wrapper_$num.sh"
    
    cat > "$wrapper_script" << EOF
#!/bin/bash
# 自动生成的rsync定时任务包装脚本
# 任务编号: $num
# 任务名称: $name

CONFIG_FILE="$CONFIG_FILE"
LOG_FILE="$LOG_DIR/rsync_cron_\$(date +%Y%m%d).log"

# 通过任务名称查找任务配置
task=\$(grep "^$name|" "\$CONFIG_FILE" | head -1)
if [[ -z "\$task" ]]; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [ERROR] 任务不存在: $name" >> "\$LOG_FILE"
    exit 1
fi

IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "\$task"

# 检查密钥文件是否存在（如果是密钥认证）
if [[ "\$auth_method" == "key" && ! -f "\$password_or_key" ]]; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [ERROR] 密钥文件不存在: \$password_or_key" >> "\$LOG_FILE"
    exit 1
fi

# 执行同步
if [[ "\$auth_method" == "password" ]]; then
    sshpass -p "\$password_or_key" rsync $options -e "ssh -p $port -o StrictHostKeyChecking=no" "\$local_path" "\$remote:\$remote_path"
else
    rsync $options -e "ssh -i \"\$password_or_key\" -p $port -o StrictHostKeyChecking=no" "\$local_path" "\$remote:\$remote_path"
fi

exit_code=\$?
if [[ \$exit_code -eq 0 ]]; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [INFO] 任务执行成功: $name" >> "\$LOG_FILE"
else
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [ERROR] 任务执行失败: $name (退出码: \$exit_code)" >> "\$LOG_FILE"
fi
EOF
    
    chmod +x "$wrapper_script"
    
    # 创建cron任务
    local cron_job="$cron_time $wrapper_script >> $LOG_DIR/cron.log 2>&1"
    
    # 检查是否已存在相同任务
    if crontab -l 2>/dev/null | grep -q "$wrapper_script"; then
        show_warning "该任务已存在定时任务，是否更新？(y/N): "
        read -e confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            # 删除旧的定时任务
            crontab -l 2>/dev/null | grep -v "$wrapper_script" | crontab -
        else
            show_info "取消创建定时任务"
            return
        fi
    fi
    
    # 添加到crontab
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    if [[ $? -eq 0 ]]; then
        show_success "定时任务创建成功！"
        show_info "Cron表达式: $cron_time"
        show_info "包装脚本: $wrapper_script"
        log "INFO" "创建定时任务: $name (cron: $cron_time)"
    else
        show_error "定时任务创建失败！"
        log "ERROR" "创建定时任务失败: $name"
    fi
}

# 查看定时任务
view_schedules() {
    echo "当前的定时任务:"
    echo "========================================="
    
    local cron_list=$(crontab -l 2>/dev/null)
    if [[ -z "$cron_list" ]]; then
        show_warning "暂无定时任务"
        return
    fi
    
    # 显示所有rsync相关的定时任务
    echo "$cron_list" | grep -E "(rsync_wrapper_|rsync.*\.sh)" | while read -r line; do
        echo "$line"
    done
    
    echo "========================================="
    
    # 显示包装脚本列表
    echo "包装脚本列表:"
    echo "-----------------------------------------"
    ls -la "$CONFIG_DIR"/rsync_wrapper_*.sh 2>/dev/null | while read -r file; do
        echo "$file"
    done
    echo "========================================="
}

# 删除定时任务
delete_schedule() {
    log "INFO" "开始删除定时任务"
    
    view_schedules
    
    read -e -p "请输入要删除的定时任务对应的任务编号: " num
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        show_error "请输入有效的数字编号！"
        return
    fi
    
    local wrapper_script="$CONFIG_DIR/rsync_wrapper_$num.sh"
    
    if [[ ! -f "$wrapper_script" ]]; then
        show_error "未找到对应的包装脚本: $wrapper_script"
        return
    fi
    
    # 从crontab中删除
    crontab -l 2>/dev/null | grep -v "$wrapper_script" | crontab -
    
    # 删除包装脚本
    rm -f "$wrapper_script"
    
    show_success "定时任务已删除！"
    log "INFO" "删除定时任务: 任务编号 $num"
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查rsync
    if ! command -v rsync &> /dev/null; then
        missing_deps+=("rsync")
    fi
    
    # 检查sshpass（如果使用密码认证）
    if grep -q "password" "$CONFIG_FILE" 2>/dev/null; then
        if ! command -v sshpass &> /dev/null; then
            missing_deps+=("sshpass")
        fi
    fi
    
    # 检查inotifywait（如果用户要使用监控功能）
    if ! command -v inotifywait &> /dev/null; then
        missing_deps+=("inotify-tools")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        show_warning "缺少以下依赖: ${missing_deps[*]}"
        echo "安装命令:"
        
        for dep in "${missing_deps[@]}"; do
            case $dep in
                rsync)
                    echo "  Ubuntu/Debian: sudo apt install rsync"
                    echo "  CentOS/RHEL: sudo yum install rsync"
                    ;;
                sshpass)
                    echo "  Ubuntu/Debian: sudo apt install sshpass"
                    echo "  CentOS/RHEL: sudo yum install sshpass"
                    ;;
                inotify-tools)
                    echo "  Ubuntu/Debian: sudo apt install inotify-tools"
                    echo "  CentOS/RHEL: sudo yum install inotify-tools"
                    ;;
            esac
        done
        
        read -e -p "是否立即安装？(y/N): " install_choice
        if [[ "$install_choice" == "y" || "$install_choice" == "Y" ]]; then
            for dep in "${missing_deps[@]}"; do
                show_info "正在安装 $dep..."
                if command -v apt &> /dev/null; then
                    sudo apt update && sudo apt install -y "$dep"
                elif command -v yum &> /dev/null; then
                    sudo yum install -y "$dep"
                else
                    show_error "无法确定包管理器，请手动安装 $dep"
                fi
            done
        fi
    fi
}

# 显示系统信息
show_system_info() {
    echo "系统信息:"
    echo "-----------------------------------------"
    echo "主机名: $(hostname)"
    echo "系统: $(uname -s) $(uname -r)"
    echo "用户: $(whoami)"
    echo "家目录: $HOME"
    echo "配置目录: $CONFIG_DIR"
    echo "密钥目录: $KEY_DIR"
    echo "日志目录: $LOG_DIR"
    echo "-----------------------------------------"
}

# 清理旧日志
cleanup_logs() {
    local days_to_keep=30
    show_info "清理 $days_to_keep 天前的日志文件..."
    
    find "$LOG_DIR" -name "rsync_*.log" -type f -mtime +$days_to_keep -delete 2>/dev/null
    find "$LOG_DIR" -name "rsync_cron_*.log" -type f -mtime +$days_to_keep -delete 2>/dev/null
    
    show_success "日志清理完成！"
    log "INFO" "清理旧日志文件"
}

# 备份配置
backup_config() {
    local backup_dir="$CONFIG_DIR/backups"
    local backup_file="$backup_dir/rsync_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    mkdir -p "$backup_dir"
    
    tar -czf "$backup_file" -C "$CONFIG_DIR" . 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        show_success "配置备份完成: $backup_file"
        log "INFO" "配置备份: $backup_file"
    else
        show_error "配置备份失败！"
    fi
}

# 恢复配置
restore_config() {
    local backup_dir="$CONFIG_DIR/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        show_error "备份目录不存在: $backup_dir"
        return
    fi
    
    echo "可用的备份文件:"
    echo "-----------------------------------------"
    ls -la "$backup_dir"/*.tar.gz 2>/dev/null | while read -r file; do
        echo "$file"
    done
    echo "-----------------------------------------"
    
    read -e -p "请输入要恢复的备份文件路径: " backup_file
    
    if [[ ! -f "$backup_file" ]]; then
        show_error "备份文件不存在: $backup_file"
        return
    fi
    
    read -e -p "确认恢复配置吗？这将覆盖当前配置。(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        show_info "取消恢复"
        return
    fi
    
    # 备份当前配置
    local temp_backup="$CONFIG_DIR/temp_backup_$(date +%s).tar.gz"
    tar -czf "$temp_backup" -C "$CONFIG_DIR" . 2>/dev/null
    
    # 恢复配置
    tar -xzf "$backup_file" -C "$CONFIG_DIR" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        show_success "配置恢复完成！"
        log "INFO" "配置恢复: $backup_file"
    else
        show_error "配置恢复失败！"
        # 尝试恢复备份
        tar -xzf "$temp_backup" -C "$CONFIG_DIR" 2>/dev/null
        show_info "已恢复原始配置"
    fi
    
    rm -f "$temp_backup"
}

# ============================================
# 实时监控功能
# ============================================

# 检查inotifywait依赖
check_inotify_dependency() {
    if ! command -v inotifywait &> /dev/null; then
        show_error "未安装 inotify-tools，请先安装:"
        show_info "Ubuntu/Debian: sudo apt install inotify-tools"
        show_info "CentOS/RHEL: sudo yum install inotify-tools"
        return 1
    fi
    return 0
}

# 启动实时监控
start_monitor() {
    log "INFO" "开始启动实时监控"
    
    if [[ ! -s "$CONFIG_FILE" ]]; then
        show_error "暂无同步任务可监控"
        return
    fi
    
    # 检查依赖
    if ! check_inotify_dependency; then
        return
    fi
    
    list_tasks
    read -e -p "请输入要监控的任务编号: " num
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        show_error "请输入有效的数字编号！"
        return
    fi
    
    local task=$(sed -n "${num}p" "$CONFIG_FILE")
    if [[ -z "$task" ]]; then
        show_error "未找到对应的任务！"
        return
    fi
    
    IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"
    
    # 检查本地目录是否存在
    if [[ ! -d "$local_path" ]]; then
        show_error "本地目录不存在: $local_path"
        return
    fi
    
    # 检查是否已经在监控
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        local pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            show_warning "监控进程已在运行 (PID: $pid)"
            read -e -p "是否停止现有监控并启动新的？(y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                show_info "取消操作"
                return
            fi
            stop_monitor
        fi
    fi
    
    # 创建监控脚本
    local monitor_script="$MONITOR_DIR/monitor_$num.sh"
    
    cat > "$monitor_script" << EOF
#!/bin/bash
# 实时监控脚本
# 任务编号: $num
# 任务名称: $name
# 监控目录: $local_path

CONFIG_FILE="$CONFIG_FILE"
LOG_FILE="$LOG_DIR/rsync_monitor_\$(date +%Y%m%d).log"
DELAY_SECONDS=10

log_monitor() {
    local level="\$1"
    local message="\$2"
    local timestamp=\$(date '+%Y-%m-%d %H:%M:%S')
    echo "[\$timestamp] [\$level] \$message" | tee -a "\$LOG_FILE"
}

log_monitor "INFO" "启动实时监控: 任务 '$name', 目录: $local_path"

# 通过任务名称查找任务配置
task=\$(grep "^$name|" "\$CONFIG_FILE" | head -1)
if [[ -z "\$task" ]]; then
    log_monitor "ERROR" "任务不存在: $name"
    exit 1
fi

IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "\$task"

# 检查密钥文件是否存在（如果是密钥认证）
if [[ "\$auth_method" == "key" && ! -f "\$password_or_key" ]]; then
    log_monitor "ERROR" "密钥文件不存在: \$password_or_key"
    exit 1
fi

# 构建rsync命令
build_rsync_cmd() {
    local ssh_options="-p $port -o StrictHostKeyChecking=no -o ConnectTimeout=30"
    
    if [[ "\$auth_method" == "password" ]]; then
        echo "sshpass -p '\$password_or_key' rsync $options -e 'ssh \$ssh_options' \"\$local_path\" \"\$remote:\$remote_path\""
    else
        echo "rsync $options -e 'ssh -i \"\$password_or_key\" \$ssh_options' \"\$local_path\" \"\$remote:\$remote_path\""
    fi
}

# 执行同步函数（带延迟）
perform_sync() {
    local event="\$1"
    local file="\$2"
    
    log_monitor "INFO" "检测到变化: \$event - \$file，等待 \${DELAY_SECONDS}秒后同步..."
    sleep \$DELAY_SECONDS
    
    local rsync_cmd=\$(build_rsync_cmd)
    log_monitor "INFO" "开始同步: \$rsync_cmd"
    
    eval \$rsync_cmd
    local exit_code=\$?
    
    if [[ \$exit_code -eq 0 ]]; then
        log_monitor "INFO" "同步成功"
    else
        log_monitor "ERROR" "同步失败，退出码: \$exit_code"
    fi
}

# 设置退出信号处理
trap 'log_monitor "INFO" "监控进程停止"; exit 0' INT TERM

# 开始监控
log_monitor "INFO" "开始监控目录: \$local_path"
log_monitor "INFO" "监控事件: 创建、修改、移动、删除"
log_monitor "INFO" "延迟时间: \${DELAY_SECONDS}秒"

# 使用inotifywait监控目录
inotifywait -m -r "\$local_path" \
    -e create \
    -e modify \
    -e moved_to \
    -e moved_from \
    -e delete \
    --format '%e %w%f' \
    --timefmt '%Y-%m-%d %H:%M:%S' | \
while read -r event file
do
    # 过滤掉一些不需要同步的文件（如临时文件）
    if [[ "\$file" =~ \.(swp|swx|tmp|temp)$ ]] || [[ "\$file" =~ ~\$ ]]; then
        continue
    fi
    
    # 记录事件但不立即同步（用于调试）
    log_monitor "DEBUG" "事件: \$event - \$file"
    
    # 在后台执行同步（避免阻塞监控）
    perform_sync "\$event" "\$file" &
done

log_monitor "INFO" "监控进程异常退出"
EOF
    
    chmod +x "$monitor_script"
    
    # 启动监控进程（后台运行）
    nohup bash "$monitor_script" > "$LOG_DIR/monitor_$num.log" 2>&1 &
    local monitor_pid=$!
    
    # 保存PID
    echo "$monitor_pid" > "$MONITOR_PID_FILE"
    echo "$num" > "$MONITOR_DIR/monitor_task_$monitor_pid"
    
    show_success "实时监控已启动！"
    show_info "监控进程 PID: $monitor_pid"
    show_info "监控目录: $local_path"
    show_info "延迟时间: 10秒"
    show_info "日志文件: $LOG_DIR/monitor_$num.log"
    show_info "监控脚本: $monitor_script"
    
    log "INFO" "启动实时监控: 任务 $name (PID: $monitor_pid)"
}

# 停止实时监控
stop_monitor() {
    log "INFO" "开始停止实时监控"
    
    if [[ ! -f "$MONITOR_PID_FILE" ]]; then
        show_warning "没有正在运行的监控进程"
        return
    fi
    
    local pid=$(cat "$MONITOR_PID_FILE")
    
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid"
        
        # 等待进程结束
        local wait_count=0
        while kill -0 "$pid" 2>/dev/null && [[ $wait_count -lt 10 ]]; do
            sleep 1
            ((wait_count++))
        done
        
        if kill -0 "$pid" 2>/dev/null; then
            show_warning "监控进程未正常退出，强制终止..."
            kill -9 "$pid"
        fi
        
        rm -f "$MONITOR_PID_FILE"
        rm -f "$MONITOR_DIR/monitor_task_$pid"
        
        show_success "监控进程已停止 (PID: $pid)"
        log "INFO" "停止实时监控: PID $pid"
    else
        show_warning "监控进程不存在或已停止 (PID: $pid)"
        rm -f "$MONITOR_PID_FILE"
        rm -f "$MONITOR_DIR/monitor_task_$pid"
    fi
}

# 查看监控状态
view_monitor_status() {
    echo "实时监控状态:"
    echo "========================================="
    
    if [[ ! -f "$MONITOR_PID_FILE" ]]; then
        show_warning "没有正在运行的监控进程"
        return
    fi
    
    local pid=$(cat "$MONITOR_PID_FILE")
    local task_file="$MONITOR_DIR/monitor_task_$pid"
    
    if [[ -f "$task_file" ]]; then
        local task_num=$(cat "$task_file")
        
        # 尝试通过行号查找任务（向后兼容）
        local task=$(sed -n "${task_num}p" "$CONFIG_FILE" 2>/dev/null)
        
        # 如果通过行号找不到，尝试查找所有任务并匹配
        if [[ -z "$task" ]]; then
            # 读取所有任务，查找可能匹配的任务
            while IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key; do
                # 检查是否有监控脚本存在
                local monitor_script="$MONITOR_DIR/monitor_$task_num.sh"
                if [[ -f "$monitor_script" ]]; then
                    # 从监控脚本中提取任务名称
                    local script_name=$(grep -o "任务名称: [^ ]*" "$monitor_script" 2>/dev/null | head -1 | cut -d' ' -f2)
                    if [[ -n "$script_name" && "$script_name" == "$name" ]]; then
                        task="$name|$local_path|$remote|$remote_path|$port|$options|$auth_method|$password_or_key"
                        break
                    fi
                fi
            done < "$CONFIG_FILE"
        fi
        
        if [[ -n "$task" ]]; then
            IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"
            
            echo "监控进程信息:"
            echo "-----------------------------------------"
            echo "进程 PID: $pid"
            echo "任务编号: $task_num"
            echo "任务名称: $name"
            echo "监控目录: $local_path"
            echo "远程目标: $remote:$remote_path"
            echo "-----------------------------------------"
            
            # 检查进程是否在运行
            if kill -0 "$pid" 2>/dev/null; then
                show_success "监控进程正在运行"
                
                # 显示最近的日志
                local monitor_log="$LOG_DIR/monitor_$task_num.log"
                if [[ -f "$monitor_log" ]]; then
                    echo ""
                    echo "最近日志 (最后10行):"
                    echo "-----------------------------------------"
                    tail -10 "$monitor_log"
                    echo "-----------------------------------------"
                    echo "完整日志: $monitor_log"
                fi
            else
                show_warning "监控进程已停止 (PID: $pid)"
                # 清理残留文件
                rm -f "$MONITOR_PID_FILE" "$task_file"
            fi
        else
            show_error "任务配置不存在或已被删除"
            # 尝试从监控脚本获取任务名称
            local monitor_script="$MONITOR_DIR/monitor_$task_num.sh"
            if [[ -f "$monitor_script" ]]; then
                local script_name=$(grep -o "任务名称: [^ ]*" "$monitor_script" 2>/dev/null | head -1 | cut -d' ' -f2)
                if [[ -n "$script_name" ]]; then
                    echo "监控脚本中的任务名称: $script_name"
                fi
            fi
            rm -f "$MONITOR_PID_FILE" "$task_file"
        fi
    else
        show_error "监控任务文件不存在"
        rm -f "$MONITOR_PID_FILE"
    fi
    
    echo "========================================="
}

# 主菜单
main_menu() {
    init_dirs
    
    while true; do
        clear
        echo "========================================="
        echo "      RSYNC 远程同步管理工具 v1.1"
        echo "      新增：实时监控同步功能"
        echo "========================================="
        echo ""
        
        show_system_info
        
        echo ""
        echo "任务管理:"
        echo "  1. 查看所有任务"
        echo "  2. 添加新任务"
        echo "  3. 删除任务"
        echo ""
        echo "同步执行:"
        echo "  4. 执行推送同步 (本地 → 远程)"
        echo "  5. 执行拉取同步 (远程 → 本地)"
        echo ""
        echo "定时任务:"
        echo "  6. 创建定时任务"
        echo "  7. 查看定时任务"
        echo "  8. 删除定时任务"
        echo ""
        echo "实时监控:"
        echo "  9. 启动实时监控"
        echo "  10. 停止实时监控"
        echo "  11. 查看监控状态"
        echo ""
        echo "系统管理:"
        echo "  12. 检查依赖"
        echo "  13. 清理旧日志"
        echo "  14. 备份配置"
        echo "  15. 恢复配置"
        echo ""
        echo "  0. 退出"
        echo "========================================="
        
        read -e -p "请选择操作 (0-15): " choice
        
        case $choice in
            1) list_tasks ;;
            2) add_task ;;
            3) delete_task ;;
            4) 
                list_tasks
                if [[ -s "$CONFIG_FILE" ]]; then
                    read -e -p "请输入任务编号: " num
                    run_task "push" "$num"
                fi
                ;;
            5)
                list_tasks
                if [[ -s "$CONFIG_FILE" ]]; then
                    read -e -p "请输入任务编号: " num
                    run_task "pull" "$num"
                fi
                ;;
            6) schedule_task ;;
            7) view_schedules ;;
            8) delete_schedule ;;
            9) start_monitor ;;
            10) stop_monitor ;;
            11) view_monitor_status ;;
            12) check_dependencies ;;
            13) cleanup_logs ;;
            14) backup_config ;;
            15) restore_config ;;
            0)
                echo ""
                show_info "感谢使用 RSYNC 管理工具！"
                echo ""
                exit 0
                ;;
            *)
                show_error "无效的选择，请重试！"
                ;;
        esac
        
        echo ""
        read -e -p "按回车键继续..."
    done
}

# 脚本入口点
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "RSYNC 远程同步管理工具 v1.1"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help         显示帮助信息"
    echo "  -v, --version      显示版本信息"
    echo "  --run-task N       执行指定编号的任务 (push)"
    echo "  --pull-task N      执行指定编号的任务 (pull)"
    echo "  --list             列出所有任务"
    echo "  --add              添加新任务"
    echo "  --start-monitor N  启动指定任务的实时监控"
    echo "  --stop-monitor     停止实时监控"
    echo "  --monitor-status   查看监控状态"
    echo ""
    echo "示例:"
    echo "  $0                      # 启动交互式菜单"
    echo "  $0 --list               # 列出所有任务"
    echo "  $0 --run-task 1         # 执行任务1的推送同步"
    echo "  $0 --start-monitor 1    # 启动任务1的实时监控"
    echo "  $0 --stop-monitor       # 停止实时监控"
    exit 0
elif [[ "$1" == "--version" || "$1" == "-v" ]]; then
    echo "RSYNC 远程同步管理工具 v1.1"
    echo "新增功能：基于inotifywait的实时监控同步"
    exit 0
elif [[ "$1" == "--list" ]]; then
    init_dirs
    list_tasks
    exit 0
elif [[ "$1" == "--run-task" && -n "$2" ]]; then
    init_dirs
    run_task "push" "$2"
    exit $?
elif [[ "$1" == "--pull-task" && -n "$2" ]]; then
    init_dirs
    run_task "pull" "$2"
    exit $?
elif [[ "$1" == "--add" ]]; then
    init_dirs
    add_task
    exit 0
elif [[ "$1" == "--start-monitor" && -n "$2" ]]; then
    init_dirs
    # 检查inotifywait依赖
    if ! command -v inotifywait &> /dev/null; then
        echo "错误：未安装 inotify-tools"
        echo "安装命令:"
        echo "  Ubuntu/Debian: sudo apt install inotify-tools"
        echo "  CentOS/RHEL: sudo yum install inotify-tools"
        exit 1
    fi
    start_monitor "$2"
    exit $?
elif [[ "$1" == "--stop-monitor" ]]; then
    init_dirs
    stop_monitor
    exit $?
elif [[ "$1" == "--monitor-status" ]]; then
    init_dirs
    view_monitor_status
    exit $?
else
    # 启动主菜单
    main_menu
fi
