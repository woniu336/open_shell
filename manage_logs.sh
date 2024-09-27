#!/bin/bash

# 配置文件路径
CONFIG_FILE="/root/logcheck/log_paths.conf"
REPORT_PATH="/root/logcheck"
WHITELIST_FILE="/root/logcheck/ip_whitelist.txt"  # 新增白名单文件路径

# 初始化 LOG_PATHS 数组
LOG_PATHS=()

# 确保报告目录存在
mkdir -p "$REPORT_PATH"

# 从配置文件加载 LOG_PATHS
load_log_paths() {
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r line; do
            # 跳过空行和以 # 开头的注释行
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            LOG_PATHS+=("$line")
        done < "$CONFIG_FILE"
    fi
}

# 保存 LOG_PATHS 到配置文件
save_log_paths() {
    > "$CONFIG_FILE"  # 清空配置文件
    for path in "${LOG_PATHS[@]}"; do
        echo "$path" >> "$CONFIG_FILE"
    done
}

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 清屏并显示标题
clear_and_show_title() {
    clear
    echo -e "${BLUE}┌────────────────────────────────────────────────┐"
    echo -e "│                                                │"
    echo -e "│        ${GREEN}高级日志分析与安全管理系统 v1.0${BLUE}        │"
    echo -e "│                                                │"
    echo -e "│  ${NC}教程: ${YELLOW}https://woniu336.github.io/p/332/${BLUE}           │"
    echo -e "│                                                │"
    echo -e "└────────────────────────────────────────────────┘${NC}"
    echo
}

# 更新菜单函数
show_menu() {
    clear_and_show_title
    echo -e "${GREEN}请选择操作:${NC}"
    echo -e "${BLUE}┌────────────────────────────────────────────────┐"
    echo -e "│  ${BLUE}1.${NC} 安装依赖文件                                 ${BLUE}│"
    echo -e "│  ${BLUE}2.${NC} 添加或更改日志路径⭐                         ${BLUE}│"
    echo -e "│  ${BLUE}3.${NC} 执行网站日志分析                             ${BLUE}│"
    echo -e "│  ${BLUE}4.${NC} 分析IP地区分布                               ${BLUE}│"
    echo -e "│  ${BLUE}5.${NC} 更新地理位置数据                             ${BLUE}│"
    echo -e "│  ${BLUE}6.${NC} 生成汇总报告                                 ${BLUE}│"
    echo -e "│  ${BLUE}7.${NC} 执行可疑IP风险检查⭐                         ${BLUE}│"
    echo -e "│  ${BLUE}8.${NC} 添加IP到白名单                               ${BLUE}│"
    echo -e "│  ${BLUE}9.${NC} 执行风险日志查杀⭐                           ${BLUE}│"
    echo -e "│  ${BLUE}10.${NC} 定时拉黑风险IP                              ${BLUE}│"
    echo -e "│  ${BLUE}11.${NC} 设置脚本启动快捷键                          ${BLUE}│"
    echo -e "│  ${BLUE}0.${NC} 退出                                         ${BLUE}│"
    echo -e "└────────────────────────────────────────────────┘${NC}"
}

install_dependencies() {
    clear_and_show_title
    echo "正在检查并安装依赖文件..."
    
    # 检查并安装 pip3
    if ! command -v pip3 &> /dev/null; then
        echo "正在安装 pip3..."
        sudo apt update
        sudo apt install -y python3-pip
    else
        echo "pip3 已安装,跳过..."
    fi
    
    # 安装 Python 依赖库
    echo "正在检查并安装 Python 依赖库..."
    pip3 install --upgrade ua-parser geoip2 requests
    
    # 创建必要的目录和文件
    echo "正在检查并创建必要的目录和文件..."
    mkdir -p /root/data
    mkdir -p /root/logcheck
    touch /root/logcheck/log_paths.conf
    touch /root/logcheck/ip_whitelist.txt
    
    # 下载必要的 Python 脚本
    echo "正在检查并下载必要的 Python 脚本..."
    cd /root/logcheck
    
    scripts=(
        "geoip_fetch.py"
        "ip_risk_checker.py"
        "log_analysis.py"
        "web_log_monitor.py"
        "logcheck.py"
        "ban_severe_risk_ips.py"
        "run_log_check_and_ban.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            echo "$script 已存在,跳过下载..."
        else
            echo "正在下载 $script..."
            wget https://raw.githubusercontent.com/woniu336/open_shell/main/logcheck/$script
        fi
    done
    
    echo "依赖文件安装和检查完成。"
    echo "按 Enter 键继续..."
    read
}


# 新增函数：设置脚本启动快捷键
set_shortcut() {
    sed -i '/alias.*manage_logs.sh/d' ~/.bashrc
    read -p "请输入你想要的快捷按键 (例如: L): " shortcut
    echo "alias $shortcut='bash $PWD/manage_logs.sh'" >> ~/.bashrc
    source ~/.bashrc
    echo -e "${GREEN}快捷键已添加。请重新启动终端，或运行 'source ~/.bashrc' 以使修改生效。${PLAIN}"
    sleep 5
}

# 新增函数：管理定时任务子菜单
manage_cron_job() {
    while true; do
        clear_and_show_title
        echo -e "${GREEN}定时拉黑风险IP任务管理:${NC}"
        echo -e "${BLUE}┌────────────────────────────────────────────────┐"
        echo -e "│  ${BLUE}1.${NC} 设置定时任务                                  ${BLUE}│"
        echo -e "│  ${BLUE}2.${NC} 删除定时任务                                  ${BLUE}│"
        echo -e "│  ${BLUE}3.${NC} 返回主菜单                                    ${BLUE}│"
        echo -e "└────────────────────────────────────────────────┘${NC}"
        read -p "请选择操作 (1-3): " subchoice

        case $subchoice in
            1) set_cron_job ;;
            2) delete_cron_job ;;
            3) return ;;
            *) echo "无效选择，请重试"; sleep 2 ;;
        esac
    done
}

# 修改函数：设置定时拉黑风险IP
set_cron_job() {
    clear_and_show_title
    echo "正在检查定时拉黑风险IP任务..."
    
    # 检查是否已存在相同的定时任务
    if crontab -l | grep -q 'run_log_check_and_ban.sh'; then
        echo "定时任务已存在。每天凌晨 2:18 执行。"
        echo "风险IP保存在 /root/logcheck/severe_risk_ips.log"
        echo "按 Enter 键继续..."
        read
        return
    fi
    
    (crontab -l ; echo "*/2 * * * * /root/logcheck/run_log_check_and_ban.sh >> /root/logcheck/cron_run.log 2>&1") | crontab -
    #(crontab -l ; echo "18 2 * * * /root/logcheck/run_log_check_and_ban.sh >> /root/logcheck/cron_run.log 2>&1") | crontab -
    echo "定时任务已设置。每天凌晨 2:18 执行。"
    echo "任务将执行 run_log_check_and_ban.sh 脚本"
    echo "风险IP将保存在 /root/logcheck/severe_risk_ips.log"
    echo "按 Enter 键继续..."
    read
}

delete_cron_job() {
    clear_and_show_title
    echo "正在检查定时拉黑风险IP任务..."
    
    # 检查是否存在要删除的定时任务
    if ! crontab -l | grep -q 'run_log_check_and_ban.sh'; then
        echo "未找到相关的定时任务。"
        echo "按 Enter 键继续..."
        read
        return
    fi
    
    echo "正在删除定时拉黑风险IP任务..."
    crontab -l | grep -v 'run_log_check_and_ban.sh' | crontab -
    echo "定时任务已删除。"
    echo "按 Enter 键继续..."
    read
}

# 更新 Python 脚本中的路径
update_python_scripts() {
    # 更新 log_analysis.py
    if [ -f "$REPORT_PATH/log_analysis.py" ]; then
        local log_analysis_paths_string=""
        for path in "${LOG_PATHS[@]}"; do
            log_analysis_paths_string+="    \"$path\",\n"
        done
        sed -i "/LOG_PATHS = \[/,/\]/c\LOG_PATHS = [\n$log_analysis_paths_string    # 在这里添加更多日志文件路径\n]" "$REPORT_PATH/log_analysis.py"
    else
        echo "警告：$REPORT_PATH/log_analysis.py 文件不存在。"
    fi

    # 更新 web_log_monitor.py
    if [ -f "$REPORT_PATH/web_log_monitor.py" ]; then
        local web_log_paths_string=""
        for path in "${LOG_PATHS[@]}"; do
            web_log_paths_string+="            '$path',\n"
        done
        sed -i "/self.log_files = \[/,/\]/c\        self.log_files = [\n$web_log_paths_string            # 在这里添加更多日志文件路径\n        ]" "$REPORT_PATH/web_log_monitor.py"
    else
        echo "警告：$REPORT_PATH/web_log_monitor.py 文件不存在。"
    fi

    # 更新 logcheck.py
    if [ -f "$REPORT_PATH/logcheck.py" ]; then
        local logcheck_paths_string=""
        for path in "${LOG_PATHS[@]}"; do
            logcheck_paths_string+="    \"$path\",\n"
        done
        sed -i "/LOG_PATHS = \[/,/\]/c\LOG_PATHS = [\n$logcheck_paths_string    # 在这里添加更多日志文件路径\n]" "$REPORT_PATH/logcheck.py"
    else
        echo "警告：$REPORT_PATH/logcheck.py 文件不存在。"
    fi
}

# 添加或更改日志路径
change_log_paths() {
    clear_and_show_title
    echo "当前日志路径:"
    if [ ${#LOG_PATHS[@]} -eq 0 ]; then
        echo "未设置任何日志路径。"
    else
        for path in "${LOG_PATHS[@]}"; do
            echo "- $path"
        done
    fi
    echo
    echo "输入新的日志路径 (多个路径用空格分隔, 直接回车完成):"
    read -e -p "> " input
    if [ -n "$input" ]; then
        IFS=' ' read -ra NEW_PATHS <<< "$input"
        LOG_PATHS=("${NEW_PATHS[@]}")
        save_log_paths
        update_python_scripts
        echo
        echo "日志路径已更新"
    else
        echo
        echo "未输入任何路径，日志路径保持不变。"
    fi
    echo "按 Enter 键继续..."
    read
}

# 执行网站日志分析
run_web_log_analysis() {
    clear_and_show_title
    echo "正在执行网站日志分析..."
    # 切换到 REPORT_PATH 目录
    cd "$REPORT_PATH" || exit
    python3 web_log_monitor.py > analyze_logs.txt
    echo "网站日志分析完成，结果保存在 $REPORT_PATH/analyze_logs.txt"
    cat analyze_logs.txt  # 打印文件内容
    # 切回原来的目录
    cd - > /dev/null
    echo "按 Enter 键继续..."
    read
}

# 分析IP地区分布
analyze_ip_distribution() {
    clear_and_show_title
    if [ ${#LOG_PATHS[@]} -eq 0 ]; then
        echo "错误：未设置日志路径。请先添加日志路径。"
    else
        # 将日志路径作为参数传递给 Python 脚本
        python3 "$REPORT_PATH/log_analysis.py" "${LOG_PATHS[@]}"  # 添加 $REPORT_PATH
        if [ -f "$REPORT_PATH/log_analysis.txt" ]; then
            echo "IP地区分布分析完成，结果保存在 $REPORT_PATH/log_analysis.txt"
            cat "$REPORT_PATH/log_analysis.txt"  # 打印文件内容
        else
            echo "分析完成，但未找到生成的文件。"
        fi
    fi
    echo "按 Enter 键继续..."
    read
}

# 更新地理位置数据
update_geoip_data() {
    clear_and_show_title
    echo "当前 MaxMind 许可密钥: $(grep 'LICENSE_KEY =' "$REPORT_PATH/geoip_fetch.py" | cut -d '"' -f 2)"  # 添加 $REPORT_PATH
    read -p "是否需要更新许可密钥？(y/n): " update_key
    if [[ $update_key == "y" || $update_key == "Y" ]]; then
        read -p "请输入新的 MaxMind 许可密钥: " new_key
        sed -i "s/LICENSE_KEY = .*/LICENSE_KEY = \"$new_key\"/" "$REPORT_PATH/geoip_fetch.py"  # 添加 $REPORT_PATH
        echo "许可密钥已更新, 正在下载中，请稍等。。。"
    else
        echo "正在下载中，请稍等。。。"
    fi
    python3 "$REPORT_PATH/geoip_fetch.py" > "$REPORT_PATH/geoip_update.txt"  # 添加 $REPORT_PATH
    echo "地理位置数据更新完成，结果保存在 $REPORT_PATH/geoip_update.txt"
    echo "按 Enter 键继续..."
    read
}

# 生成汇总报告
generate_summary_report() {
    clear_and_show_title
    echo "生成汇总报告..."

    local summary_file="$REPORT_PATH/summary_report.txt"
    echo "汇总报告生成中..."

    {
        echo "=== 网站日志分析结果 ==="
        if [ -f "$REPORT_PATH/analyze_logs.txt" ]; then
            cat "$REPORT_PATH/analyze_logs.txt"
        else
            echo "未找到 analyze_logs.txt 文件。"
        fi

        echo
        echo "=== IP 地区分布分析结果 ==="
        if [ -f "$REPORT_PATH/log_analysis.txt" ]; then
            cat "$REPORT_PATH/log_analysis.txt"
        else
            echo "未找到 log_analysis.txt 文件。"
        fi
    } > "$summary_file"

    echo "汇总报告已生成，保存在 $summary_file"
    cat "$summary_file"  # 打印文件内容
    echo "按 Enter 键继续..."
    read
}

# 添加IP到白名单
add_ip_to_whitelist() {
    clear_and_show_title
    echo "请输入要添加的白名单IP地址:"
    read -p "> " ip

    # 检查IP格式
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "无效的IP地址格式。"
        return
    fi

    # 检查重复
    if grep -q "^$ip$" "$WHITELIST_FILE"; then
        echo "该IP地址已在白名单中。"
    else
        echo "$ip" >> "$WHITELIST_FILE"
        echo "IP地址 $ip 已添加到白名单。"
    fi
    echo "按 Enter 键继续..."
    read
}

# 主循环之前添加这行
load_log_paths

# 主循环中的 case 语句更新
while true; do
    show_menu
    read -p "请输入您的选择 (0-11): " choice
    case $choice in
        1) install_dependencies ;;
        2) change_log_paths ;;
        3) run_web_log_analysis ;;
        4) analyze_ip_distribution ;;
        5) update_geoip_data ;;
        6) generate_summary_report ;;
        7) 
            clear_and_show_title
            echo "正在执行可疑IP风险检查..."
            python3 "$REPORT_PATH/ip_risk_checker.py"
            echo "按 Enter 键继续..."
            read
            ;;
        8) add_ip_to_whitelist ;;
        9) 
            clear_and_show_title
            echo "正在执行日志检查..."
            python3 "$REPORT_PATH/logcheck.py"
            echo "按 Enter 键继续..."
            read
            ;;
        10) manage_cron_job ;;
        11) set_shortcut ;;
        0) clear_and_show_title; echo "感谢使用，再见！"; exit 0 ;;
        *) echo "无效选择,请重试"; sleep 2 ;;
    esac
done