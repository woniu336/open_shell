#!/bin/bash

# 定义颜色代码
huang='\033[33m'
bai='\033[0m'
lv='\033[0;32m'
lan='\033[0;34m'
hong='\033[31m'
kjlan='\033[38;2;0;255;255m'
hui='\e[37m'
greenline() { echo -e "\033[32m\033[01m $1\033[0m"; }
zi='\033[0;35m'

# 定义变量
REMOTE_HOST=""
SSH_PORT=""
REMOTE_USER=""
DB_USER=""
DB_PASSWORD=""
SOURCE_DIR=""
TARGET_DIR=""
REMOTE_BACKUP_DIR=""

# 导入配置文件
source config.sh

# 清屏并显示欢迎信息
clear
greenline "————————————————————————————————————————————————————"
echo '
环境:  (debian/Ubuntu)
脚本作用:主机之间同步目录和数据库'
echo -e "博客：${kjlan}https://blog.taoshuge.eu.org${bai}"
greenline "————————————————————————————————————————————————————"

# 定义菜单选项数组
menu_items=(
    "配置远程主机"
    "配置数据库权限"
    "${kjlan}建立 ssh 连接${bai}"
    "测试 ssh 连接"
    "测试文件同步"
    "测试数据库同步"
    "添加定时任务▶"
    "退出脚本"
)

# 显示菜单函数
display_menu() {
    echo -e "${lv}┌────────────────────────────────────────┐${bai}"
    echo -e "${lv}│${bai}            ${kjlan}系统功能选项${bai}              ${lv}│${bai}"
    echo -e "${lv}├────────────────────────────────────────┤${bai}"
    i=1
    for item in "${menu_items[@]}"; do
        if [ $i -eq ${#menu_items[@]} ]; then
            # 最后一个选项使用0
            echo -e "${lv}│${bai}    0. ${item}    ${lv}│${bai}"
        else
            echo -e "${lv}│${bai}    $i. ${item}    ${lv}│${bai}"
        fi
        ((i++))
    done
    echo -e "${lv}└────────────────────────────────────────┘${bai}"
    echo -e "------------------------------------------------"
}

# 定义变量菜单函数
define_variables() {
    echo -e "${kjlan}配置说明：${bai}"
    echo "------------------------"
    echo "1. 配置远程连接信息"
    echo "2. 配置数据库权限"
    echo "------------------------"
    echo -e "${huang}请先配置数据库权限：${bai}"
    echo "1) 登录到 MySQL："
    echo "   mysql -u root -p"
    echo ""
    echo "2) 执行以下命令授予必要权限："
    echo "   GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;"
    echo "   FLUSH PRIVILEGES;"
    echo ""
    echo "3) 输入 exit 退出 MySQL"
    echo "------------------------"
    read -n 1 -s -p "完成数据库配置后，按任意键继续..."
    echo ""
    
    echo -e "${kjlan}现在开始配置远程连接信息：${bai}"
    echo -n "远程主机地址："
    read REMOTE_HOST
    echo -n "远程服务器 SSH 端口："
    read SSH_PORT
    echo -n "远程用户名："
    read REMOTE_USER
    echo -n "远程数据库用户名："
    read DB_USER
    echo -n "远程数据库密码（注意：与本地数据库密码相同）："
    read -s DB_PASSWORD
    echo
    echo -n "本地同步文件夹："
    read SOURCE_DIR
    echo -n "远程同步文件夹："
    read TARGET_DIR
    echo -n "远程数据库备份文件夹："
    read REMOTE_BACKUP_DIR

    # 创建 config.sh 文件并保存变量
    echo "生成 config.sh 文件..."
    cat > config.sh << EOF
#!/bin/bash
# 定义变量
REMOTE_HOST=$REMOTE_HOST
SSH_PORT=$SSH_PORT
REMOTE_USER=$REMOTE_USER
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
SOURCE_DIR=$SOURCE_DIR
TARGET_DIR=$TARGET_DIR
REMOTE_BACKUP_DIR=$REMOTE_BACKUP_DIR
EOF
    chmod +x config.sh
    echo -e "${kjlan}config.sh 文件已生成，请检查并确认变量值正确。${bai}"
    read -n 1 -s -p "按任意键继续..."
    return_to_main_menu
}

# 建立 SSH 连接
establish_ssh_connection() {
    ssh_dir="$HOME/.ssh"
    key_type="ed25519"
    key_file="$ssh_dir/id_$key_type"

    # 如果密钥不存在则生成
    if [ ! -f "$key_file" ]; then
        echo -e "${huang}未检测到SSH密钥,正在生成...${bai}"
        ssh-keygen -q -t ed25519 -C "阿弥陀佛" -N "" -f "$key_file"
        echo -e "${lv}SSH密钥生成完成${bai}"
    fi

    # 显示公钥内容
    echo -e "${kjlan}以下是你的SSH公钥内容:${bai}"
    echo "--------------------------------"
    cat "$key_file.pub"
    echo "--------------------------------"
    
    echo -e "${huang}请按照以下步骤操作:${bai}"
    echo "1. 复制上面显示的公钥内容"
    echo "2. 登录到远程服务器"
    echo "3. 编辑或创建文件: ~/.ssh/authorized_keys"
    echo "4. 将公钥粘贴到该文件中(如已有其他公钥,另起一行添加)"
    echo "5. 保存文件并设置权限: chmod 600 ~/.ssh/authorized_keys"
    echo ""
    echo -e "${kjlan}完成上述步骤后,你就可以使用SSH密钥登录远程服务器了${bai}"
    echo -e "${huang}提示: 可以使用 '测试 ssh 连接' 选项来验证配置是否成功${bai}"

    read -n 1 -s -p "按任意键继续..."
    return_to_main_menu
}

# 测试 SSH 连接
test_ssh_connection() {
    echo -e "${huang}ssh连接中，稍等片刻...${bai}"

    if ssh -p $SSH_PORT -i ~/.ssh/id_ed25519 -o "StrictHostKeyChecking=no" -o "BatchMode=yes" $REMOTE_USER@$REMOTE_HOST "exit" 2>/dev/null; then
        echo -e "${kjlan}连接成功${bai}\n"
    else
        echo -e "${hong}连接失败${bai}\n"
        echo -e "无法连接到远程服务器，请检查 ${huang}config.sh${bai} 配置信息是否有误。"
        exit 1
    fi

    read -n 1 -s -p "按任意键继续..."
    return_to_main_menu
}

# 同步文件
synchronize_files() {
    echo -e "${huang}正在同步文件...${bai}"
    # 使用 rsync 同步文件
    rsync -avz --delete -e "ssh -o StrictHostKeyChecking=no -p $SSH_PORT -i ~/.ssh/id_ed25519" $SOURCE_DIR/ $REMOTE_USER@$REMOTE_HOST:$TARGET_DIR/
    echo -e "${lv}文件同步成功！${bai}"
    read -n 1 -s -p "按任意键继续..."
    return_to_main_menu
}

# 备份和还原数据库
backup_and_restore_databases() {
    # 备份所有数据库
    echo -e "${huang}同步进行中（请耐心等待）...${bai}"
    mysqldump -h127.0.0.1 -u$DB_USER -p$DB_PASSWORD --all-databases --events | gzip > all_databases.sql.gz
    echo "完成20%"

    # 同步备份文件到远程服务器
    rsync -avz --delete -e "ssh -o StrictHostKeyChecking=no -p $SSH_PORT -i ~/.ssh/id_ed25519" all_databases.sql.gz $REMOTE_USER@$REMOTE_HOST:$REMOTE_BACKUP_DIR/ >/dev/null 2>&1
    echo "完成50%"

    # 还原数据库
    backup_file="all_databases.sql.gz"
    ssh -p $SSH_PORT -i ~/.ssh/id_ed25519 -T $REMOTE_USER@$REMOTE_HOST << EOF >/dev/null 2>&1
    gunzip < $REMOTE_BACKUP_DIR/$backup_file | mysql -h127.0.0.1 -u$DB_USER -p$DB_PASSWORD
EOF
    if [ $? -eq 0 ]; then
        echo -e "${kjlan}数据库同步成功！${bai}"
    else
        echo -e "${hong}数据库同步失败！${bai}"
    fi

    read -n 1 -s -p "按任意键继续..."
    return_to_main_menu
}

# 添加定时任务
add_cron_job() {
    while true; do
        clear
        echo ""
        echo -e "${lv}请选择要添加定时任务的功能：${bai}"
        echo ""
        echo "1) 同步文件"
        echo ""
        echo "2) 同步数据库"
        echo ""
        echo -e "${huang}3) 定时任务管理 ▶ ${bai}"
        echo ""
        echo "0) 返回主菜单"
        echo ""
        read -p "请输入序号回车：" cron_choice

        case $cron_choice in
            1)
                # 生成同步文件脚本
                generate_script synchronize_files "rsync -avz --delete -e \"ssh -o StrictHostKeyChecking=no -p $SSH_PORT -i ~/.ssh/id_ed25519\" $SOURCE_DIR/ $REMOTE_USER@$REMOTE_HOST:$TARGET_DIR/"
                ;;
            2)
                # 生成备份和还原所有数据库脚本
                generate_script backup_and_restore_databases "mysqldump -h127.0.0.1 -u$DB_USER -p$DB_PASSWORD --all-databases --events | gzip > all_databases.sql.gz && rsync -avz --delete -e \"ssh -o StrictHostKeyChecking=no -p $SSH_PORT -i ~/.ssh/id_ed25519\" all_databases.sql.gz $REMOTE_USER@$REMOTE_HOST:$REMOTE_BACKUP_DIR/ && ssh -p $SSH_PORT -i ~/.ssh/id_ed25519 -T $REMOTE_USER@$REMOTE_HOST \"gunzip < $REMOTE_BACKUP_DIR/all_databases.sql.gz | mysql -h127.0.0.1 -u$DB_USER -p$DB_PASSWORD\""
                ;;
            3)
                # 自定义任务
                manage_cron_jobs
                ;;
            0)
                # 返回主菜单
                echo ""
                echo -e "${lv}已返回主菜单。${bai}"
                clear
                break
                ;;
            *)
                echo "无效选择。请再次尝试。"
                ;;
        esac
    done
}

# 管理定时任务函数
manage_cron_jobs() {
    while true; do
        clear
        echo -e "${lv}定时任务列表${bai}"
        crontab -l
        echo ""
        echo "操作"
        echo "------------------------"
        echo "1. 添加定时任务"
        echo "2. 删除定时任务"
        echo "------------------------"
        echo "0. 返回上一级菜单"
        echo "------------------------"
        read -p "请输入你的选择：" sub_choice

        case $sub_choice in
            1)
                # 添加定时任务
                read -p "请输入新任务的执行命令：" new_command
                echo "------------------------"
                echo "1. 每周任务"
                echo "2. 每天任务"
                read -p "请输入你的选择：" task_type

                case $task_type in
                    1)
                        # 每周任务
                        read -p "选择周几执行任务？（0-6，0 代表星期日）：" weekday
                        (crontab -l ; echo "0 0 * * $weekday $new_command") | crontab -
                        ;;
                    2)
                        # 每天任务
                        read -p "选择每天几点执行任务？（小时，0-23）：" hour
                        (crontab -l ; echo "0 $hour * * * $new_command") | crontab -
                        ;;
                    *)
                        break  # 跳出子菜单
                        ;;
                esac
                ;;
            2)
                # 删除除定时任务
                read -p "请输入需要删除任务的关键字：" keyword
                crontab -l | grep -v "$keyword" | crontab -
                ;;
            0)
                # 返回上一级菜单
                break  # 跳出子菜单
                ;;
            *)
                break  # 跳出子菜单
                ;;
        esac
    done
}

# 生成脚本函数
generate_script() {
    local script_name="$1"
    local script_command="$2"

    # 创建脚本目录
    script_dir="$HOME/scripts"
    mkdir -p "$script_dir"

    # 创建脚本文件
    cat > "$script_dir/$script_name.sh" << EOF
#!/bin/bash

# 导入配置文件
source \$HOME/config.sh

# 导入环境变量
source /etc/profile

$script_command
EOF

    # 添加执行权限
    chmod +x "$script_dir/$script_name.sh"
    
    # 添加定时任务
    
echo -e "${kjlan}请输入定时任务的执行时间：${bai}"
while true; do
    read -p "请输入分钟 (0-59)，留空示整点：" minute
    read -p "请输入小时 (0-23)，留空表示每小时：" hour
    read -p "请输入日 (1-31)，留空表示每天：" day
    read -p "请输入月 (1-12)，留空表示每月：" month
    read -p "请输入星期 (0-6)，留空表示任意：" weekday

    # 初始化变量
    minute=${minute:-*}
    hour=${hour:-*}
    day=${day:-*}
    month=${month:-*}
    weekday=${weekday:-*}

    # 如果日、月、星期留空，则设置默认值
    if [ -z "$day" ]; then
        day="*"
    fi
    if [ -z "$month" ]; then
        month="*"
    fi
    if [ -z "$weekday" ]; then
        weekday="*"
    fi

    cron_time="$minute $hour $day $month $weekday"

    # 验证 cron 格式
    if [[ $minute =~ ^[0-9]{1,2}$|^[*]$ ]] &&
       [[ $hour =~ ^[0-9]{1,2}$|^[*]$ ]] &&
       [[ $day =~ ^[0-9]{1,2}$|^[*]$ ]] &&
       [[ $month =~ ^[0-9]{1,2}$|^[*]$ ]] &&
       [[ $weekday =~ ^[0-9]{1,2}$|^[*]$ ]]; then
        break
    else
        echo "格式无效，请试。"
    fi
done

(crontab -l ; echo "$cron_time $script_dir/$script_name.sh >/dev/null 2>&1") | crontab -
echo -e "${kjlan}已添加定时任务。${bai}"
read -n 1 -s -p "按任意键继续..."
return_to_main_menu
}

# 返回主菜单
return_to_main_menu() {
    clear
}

# 退出程序
exit_program() {
    clear
    echo -e "${lv}已退出...${bai}"
    exit 0
}

# 在文件开头的函数定义部分添加
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_rsync() {
    if command_exists rsync; then
        echo -e "\033[96mrsync 已经安装\033[0m"
    else
        echo -e "\033[33mrsync 正在安装中...\033[0m"
        sudo apt update
        sudo apt install -y rsync
    fi
    read -n 1 -s -p "按任意键继续..."
    return_to_main_menu
}

# 在main函数之前添加rsync检测
check_requirements() {
    # 检查rsync是否安装
    if ! command_exists rsync; then
        echo -e "${huang}检测到rsync未安装，正在安装...${bai}"
        install_rsync
    fi
}

# 在主函数之前添加配置文件检测函数
check_config() {
    if [ -f "config.sh" ]; then
        echo -e "${huang}检测到已存在的配置文件。${bai}"
        read -p "是否需要更新配置？(y/n): " update_choice
        if [[ $update_choice =~ ^[Yy]$ ]]; then
            echo -e "${kjlan}现在开始配置远程连接信息：${bai}"
            echo -n "远程主机地址："
            read REMOTE_HOST
            echo -n "远程服务器 SSH 端口："
            read SSH_PORT
            echo -n "远程用户名："
            read REMOTE_USER
            echo -n "远程数据库用户名："
            read DB_USER
            echo -n "远程数据库密码（注意：与本地数据库密码相同）："
            read -s DB_PASSWORD
            echo
            echo -n "本地同步文件夹："
            read SOURCE_DIR
            echo -n "远程同步文件夹："
            read TARGET_DIR
            echo -n "远程数据库备份文件夹："
            read REMOTE_BACKUP_DIR

            # 创建 config.sh 文件并保存变量
            echo "生成 config.sh 文件..."
            cat > config.sh << EOF
#!/bin/bash
# 定义变量
REMOTE_HOST=$REMOTE_HOST
SSH_PORT=$SSH_PORT
REMOTE_USER=$REMOTE_USER
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
SOURCE_DIR=$SOURCE_DIR
TARGET_DIR=$TARGET_DIR
REMOTE_BACKUP_DIR=$REMOTE_BACKUP_DIR
EOF
            chmod +x config.sh
            echo -e "${kjlan}config.sh 文件已生成，请检查并确认变量值正确。${bai}"
            read -n 1 -s -p "按任意键继续..."
            return_to_main_menu
        else
            echo -e "${kjlan}跳过配置更新。${bai}"
            read -n 1 -s -p "按任意键继续..."
            return_to_main_menu
        fi
    else
        echo -e "${huang}未检测到配置文件，请先进行配置。${bai}"
        define_variables
    fi
}

# 添加数据库权限检查函数
check_mysql_privileges() {
    echo -e "${kjlan}提示：可在终端新开一个窗口配置数据库权限${bai}"
    echo "------------------------"
    echo "1) 登录到 MySQL："
    echo -e "   ${zi}mysql -u root -p${bai}"
    echo ""
    echo "2) 执行以下命令授予必要权限："
    echo -e "   ${zi}CREATE USER 'tongbu'@'127.0.0.1' IDENTIFIED BY '123456';${bai}"
    echo -e "   ${zi}GRANT ALL PRIVILEGES ON *.* TO 'tongbu'@'127.0.0.1';${bai}"
	echo -e "   ${zi}FLUSH PRIVILEGES;${bai}"
    echo ""
    echo "3) 输入 exit 退出 MySQL"
    echo "------------------------"
    
    # 验证权限
    echo -e "${huang}正在验证数据库权限...${bai}"
    if mysql -u$DB_USER -p$DB_PASSWORD -e "SHOW GRANTS;" 2>/dev/null | grep -q "ALL PRIVILEGES ON \*\.\* TO"; then
        echo -e "${lv}数据库权限配置正确！${bai}"
    else
        echo -e "${hong}警告：数据库权限可能配置不正确${bai}"
        echo -e "${huang}请按照上述步骤配置数据库权限${bai}"
    fi
    
    read -n 1 -s -p "按任意键继续..."
    return_to_main_menu
}

# 修改主函数
main() {
    # 检查必要的依赖
    check_requirements
    
    while true; do
        # 显示菜单
        display_menu
        echo "------------------------------------------------"
        # 获取用户选择
        read -p "请输入选项的序号(输入q退出): " choice
        if [[ $choice == 'q' ]]; then
            break
        fi

        # 根据选择执行相应函数
        case $choice in
            1) 
                if [ ! -f "config.sh" ]; then
                    echo -e "${huang}未检测到配置文件，请先进行配置。${bai}"
                    define_variables
                else
                    check_config
                fi
                ;;
            2)
                check_mysql_privileges
                ;;
            3) 
                if [ ! -f "config.sh" ]; then
                    echo -e "${hong}请先配置远程主机信息（选项1）${bai}"
                    read -n 1 -s -p "按任意键继续..."
                    continue
                fi
                establish_ssh_connection 
                ;;
            4) 
                if [ ! -f "config.sh" ]; then
                    echo -e "${hong}请先配置远程主机信息（选项1）${bai}"
                    read -n 1 -s -p "按任意键继续..."
                    continue
                fi
                test_ssh_connection 
                ;;
            5) 
                if [ ! -f "config.sh" ]; then
                    echo -e "${hong}请先配置远程主机信息（选项1）${bai}"
                    read -n 1 -s -p "按任意键继续..."
                    continue
                fi
                synchronize_files 
                ;;
            6) 
                if [ ! -f "config.sh" ]; then
                    echo -e "${hong}请先配置远程主机信息（选项1）${bai}"
                    read -n 1 -s -p "按任意键继续..."
                    continue
                fi
                backup_and_restore_databases 
                ;;
            7) 
                if [ ! -f "config.sh" ]; then
                    echo -e "${hong}请先配置远程主机信息（选项1）${bai}"
                    read -n 1 -s -p "按任意键继续..."
                    continue
                fi
                add_cron_job 
                ;;
            0) exit_program ;;
            *) echo "无效的选择。请再次尝试。" ;;
        esac
    done
}

main "$@"

