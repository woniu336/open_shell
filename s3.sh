#!/bin/bash

# 配置文件路径
rclone_config="/root/.config/rclone/rclone.conf"
filter_file="/root/.config/rclone/filter-file.txt"

# 存储名称变量
storage_name=""

# 函数：检测是否已安装rclone
check_rclone_installed() {
    if command -v rclone &>/dev/null; then
        echo -e "\e[32mrclone已安装.\e[0m"
    else
        # 安装rclone
        echo "正在安装rclone..."
        sudo -v
        curl https://rclone.org/install.sh | sudo bash
    fi
}

# 函数：创建rclone配置文件
create_rclone_config() {
    echo "创建rclone配置文件..."
    touch "$rclone_config"
}

# 函数：绑定S3存储
bind_s3_storage() {
    echo "绑定S3存储"
    echo -e "\e[32m请输入云盘配置名称:\e[0m"  # 绿色高亮提示
    read -p "" storage_name
    # 实现绑定S3存储的逻辑
    echo -e "\e[32m请输入access_key_id:\e[0m"  # 绿色高亮提示
    read access_key_id
    echo -e "\e[32m请输入secret_access_key:\e[0m"  # 绿色高亮提示
    read secret_access_key
    echo -e "\e[32m请输入endpoint:\e[0m"  # 绿色高亮提示
    read endpoint

    # 写入配置文件
    echo "[$storage_name]" >> "$rclone_config"
    echo "type = s3" >> "$rclone_config"
    echo "provider = Alibaba" >> "$rclone_config"
    echo "access_key_id = $access_key_id" >> "$rclone_config"
    echo "secret_access_key = $secret_access_key" >> "$rclone_config"
    echo "endpoint = $endpoint" >> "$rclone_config"
    echo "acl = private" >> "$rclone_config"

    # 测试绑定
    if timeout 10s rclone lsf "$storage_name:" >/dev/null 2>&1; then
        echo -e "\e[32m绑定成功.\e[0m"
        sleep 2 # 暂停2秒以便用户看到成功提示
    else
        echo "绑定失败."
        return 1
    fi
}

# 函数：网站备份
website_backup() {
    echo "网站备份"
    echo -e "\e[32m请输入网站备份目录:\e[0m"  # 绿色高亮提示
    read -p "" source_cloud_path
    echo -e "\e[32m请输入云盘配置名称:\e[0m"  # 绿色高亮提示
    read -p "" cloud_name

    # 从rclone配置文件中提取已配置的网盘名称
    configured_clouds=$(grep '\[' ~/.config/rclone/rclone.conf | sed 's/\[\(.*\)\]/\1/')

    # 检查输入的云盘配置是否存在
    if [[ ! $configured_clouds =~ $cloud_name ]]; then
        echo -e "\e[31m错误：未找到配置名称 '$cloud_name'。请检查您的rclone配置文件。\e[0m"
        exit 1
    fi

    # 获取网盘目录列表
    cloud_path_list=$(rclone lsf "$cloud_name:")

    # 检查是否成功获取目录列表
    if [ $? -ne 0 ]; then
        echo -e "\e[31m错误：无法获取云盘目录列表。请检查您的rclone配置和云盘路径。\e[0m"
        exit 1
    fi

    # 显示目录序号
    PS3="请输入数字选择存储桶: "  # 设置提示符
    echo "可用存储桶列表："
    select folder in $cloud_path_list; do
        if [ -n "$folder" ]; then
            selected_folder="$folder"
            echo -e "\e[32m输入备份文件夹名称:\e[0m"  # 绿色高亮提示
            read -p "" backup_folder_name
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    # 提示是否需要排除文件
    echo "是否需要排除文件？"
    echo "1) 是"
    echo "2) 否"
    read -p "请选择 (1/2): " exclude_files_choice

    if [ "$exclude_files_choice" == "1" ]; then
        echo -e "\e[32m请输入要排除的文件（使用逗号分隔,例:/dir/,88.txt）:\e[0m"  # 绿色高亮提示
        read -p "" exclude_files
        # 将排除的内容按逗号分隔并写入规则文件
        IFS=',' read -ra exclude_array <<< "$exclude_files"
        for exclude_item in "${exclude_array[@]}"; do
            echo "- $exclude_item" >> "$filter_file"
        done
    fi

    # 执行备份操作
    if [ -f "$filter_file" ]; then
        rclone copy "$source_cloud_path" "$cloud_name:$selected_folder/$backup_folder_name" -u -v -P --transfers=6 --ignore-errors --buffer-size=16M --check-first --checkers=10 --drive-acknowledge-abuse --filter-from "$filter_file"
        echo -e "\e[32m网站备份成功!\e[0m"
		sleep 2 # 暂停2秒以便用户看到成功提示
        rm "$filter_file" # 删除临时的过滤规则文件
    else
        rclone copy "$source_cloud_path" "$cloud_name:$selected_folder/$backup_folder_name" -u -v -P --transfers=6 --ignore-errors --buffer-size=16M --check-first --checkers=10
        echo -e "\e[32m网站备份成功!\e[0m"
		sleep 2 # 暂停2秒以便用户看到成功提示
    fi


	read -p "按任意键返回主菜单..."
}

# 函数：网站还原
website_restore() {
    echo "网站还原"
    echo -e "\e[32m请输入云盘配置名称:\e[0m"  # 绿色高亮提示
    read -p "" cloud_name
	    # 获取用户输入的还原目录
    echo -e "\e[32m请输入网站还原目录:\e[0m"  # 绿色高亮提示
    read -p "" source_cloud_path

    # 从rclone配置文件中提取已配置的网盘名称
    configured_clouds=$(grep '\[' ~/.config/rclone/rclone.conf | sed 's/\[\(.*\)\]/\1/')

    # 检查输入的云盘配置是否存在
    if [[ ! $configured_clouds =~ $cloud_name ]]; then
        echo -e "\e[31m错误：未找到配置名称 '$cloud_name'。请检查您的rclone配置文件。\e[0m"
        exit 1
    fi

    # 获取网盘目录列表
    cloud_path_list=$(rclone lsf "$cloud_name:")

    # 检查是否成功获取目录列表
    if [ $? -ne 0 ]; then
        echo -e "\e[31m错误：无法获取云盘目录列表。请检查您的rclone配置和云盘路径。\e[0m"
        exit 1
    fi

    # 显示目录序号
    PS3="请输入数字选择存储桶: "  # 设置提示符
    echo "可用存储桶列表："
    select bucket in $cloud_path_list; do
        if [ -n "$bucket" ]; then
            selected_bucket="$bucket"
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    echo -e "\e[32m已选择存储桶 '$selected_bucket'。\e[0m"

    # 获取存储桶内的文件夹列表
    folder_list=$(rclone lsf "$cloud_name:$selected_bucket/")

    # 显示文件夹序号
    PS3="请输入数字选择文件夹进行还原: "  # 设置提示符
    echo "可用文件夹列表："
    select folder in $folder_list; do
        if [ -n "$folder" ]; then
            selected_folder="$folder"
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    echo -e "\e[32m已选择文件夹 '$selected_folder' 进行还原。\e[0m"



    # 执行还原操作
    rclone sync "$cloud_name:$selected_bucket$folder" "$source_cloud_path" --ignore-existing -u -v -P --transfers=6 --ignore-errors --buffer-size=16M --check-first --checkers=10
	echo "正在执行 rclone sync 命令："
echo "源目录：$cloud_name:$selected_bucket$folder"
echo "目标目录：$source_cloud_path"

    echo -e "\e[32m网站还原成功!\e[0m"
    sleep 2 # 暂停2秒以便用户看到成功提示
    read -p "按任意键返回主菜单..."
}



# 函数：添加计划任务
add_schedule_task() {
    echo "添加计划任务"
    echo -e "\e[32m请输入备份时间（24小时制，例如 21:05）:\e[0m"  # 绿色高亮提示
    read -p "" new_backup_time
    echo -e "\e[32m请输入网站目录:\e[0m"  # 绿色高亮提示
    read -p "" source_cloud_path
    echo -e "\e[32m请输入云盘配置名称:\e[0m"  # 绿色高亮提示
    read -p "" cloud_name
 # 从rclone配置文件中提取已配置的网盘名称
    configured_clouds=$(grep '\[' ~/.config/rclone/rclone.conf | sed 's/\[\(.*\)\]/\1/')

    # 检查输入的云盘配置是否存在
    if [[ ! $configured_clouds =~ $cloud_name ]]; then
        echo -e "\e[31m错误：未找到配置名称 '$cloud_name'。请检查您的rclone配置文件。\e[0m"
        exit 1
    fi

    # 获取网盘目录列表
    cloud_path_list=$(rclone lsf "$cloud_name:")

    # 检查是否成功获取目录列表
    if [ $? -ne 0 ]; then
        echo -e "\e[31m错误：无法获取云盘目录列表。请检查您的rclone配置和云盘路径。\e[0m"
        exit 1
    fi

    # 显示目录序号
    PS3="请输入数字选择存储桶: "  # 设置提示符
    echo "可用存储桶列表："
    select bucket in $cloud_path_list; do
        if [ -n "$bucket" ]; then
            selected_bucket="$bucket"
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    echo -e "\e[32m已选择存储桶 '$selected_bucket'。\e[0m"

    # 获取存储桶内的文件夹列表
    folder_list=$(rclone lsf "$cloud_name:$selected_bucket/")

    # 显示文件夹序号
    PS3="请输入数字选择文件夹进行备份: "  # 设置提示符
    echo "可用文件夹列表："
    select folder in $folder_list; do
        if [ -n "$folder" ]; then
            selected_folder="$folder"
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done


    # 提示是否需要排除文件
    echo "是否需要排除文件？"
    echo "1) 是"
    echo "2) 否"
    read -p "请选择 (1/2): " exclude_files_choice

    exclude_files=""

    if [ "$exclude_files_choice" == "1" ]; then
        echo -e "\e[32m请输入要排除的文件（使用逗号分隔,例:/dir/,88.txt）:\e[0m"  # 绿色高亮提示
        read -p "" exclude_files
    fi

    # 解析小时和分钟
    cron_hour=$(echo "$new_backup_time" | cut -d':' -f1)
    cron_minute=$(echo "$new_backup_time" | cut -d':' -f2)

    # 删除旧的计划任务（如果存在）
    crontab -l | grep -v "rclone sync" | crontab -

    # 构建带排除文件的rclone命令
    rclone_command="rclone sync \"$source_cloud_path\" \"$cloud_name:$selected_bucket$folder\" -u -v -P --transfers=6 --ignore-errors --buffer-size=16M --check-first --checkers=10"

    if [ -n "$exclude_files" ]; then
        # 如果存在排除文件，则添加排除参数
        exclude_flags=""
        IFS=',' read -ra exclude_array <<< "$exclude_files"
        for exclude_item in "${exclude_array[@]}"; do
            exclude_flags="$exclude_flags --exclude \"$exclude_item\""
        done
        rclone_command="$rclone_command $exclude_flags"
    fi

    # 添加新的计划任务，设置月份为通配符 *
    (crontab -l ; echo "$cron_minute $cron_hour * * * $rclone_command") | crontab -

    echo -e "\e[32m计划任务已添加.\e[0m"
    sleep 2 # 暂停2秒以便用户看到成功提示
    read -p "按任意键返回主菜单..."
}

# 函数：删除带rclone sync的计划任务
delete_schedule_task() {
    echo "删除带 rclone sync 的计划任务"
    
    # 使用 grep 命令列出包含 "rclone sync" 的计划任务，并将其删除
    crontab -l | grep -v "rclone sync" | crontab -
    
    echo -e "\e[32m带 rclone sync 的计划任务已删除.\e[0m"
    sleep 2 # 暂停2秒以便用户看到成功提示
    read -p "按任意键返回主菜单..."
}

# 函数：数据库备份
backup_database() {

    echo "数据库备份"
    echo -e "\e[32m请输入网站目录:\e[0m"  # 绿色高亮提示
    read -p "" source_cloud_path

    # 检查网站备份目录是否存在，如果不存在则创建
    if [ ! -d "$source_cloud_path" ]; then
        mkdir -p "$source_cloud_path"
        echo -e "\e[32m网站目录已创建: $source_cloud_path\e[0m"
    fi

    # 进入网站备份目录
    cd "$source_cloud_path" || exit 1

    # 创建 backup 目录（如果不存在）
    backup_dir="backup"
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
        echo -e "\e[32m创建备份目录: $backup_dir\e[0m"
    fi

    # 检查是否存在数据库信息文件 info.txt
    info_dir="/root/s3"
    info_file="$info_dir/info.txt"

    if [ ! -d "$info_dir" ]; then
        mkdir -p "$info_dir"
        echo -e "\e[32m创建数据库信息目录: $info_dir\e[0m"
    fi

    if [ -f "$info_file" ]; then
        echo -e "\e[32m已检测到数据库信息文件 info.txt。\e[0m"
        read -p "是否使用原有数据库信息？(yes/no): " use_existing_info
        if [ "$use_existing_info" == "yes" ]; then
            # 从 info.txt 文件读取数据库信息
            db_info=$(cat "$info_file")
        else
            # 提示用户输入数据库信息
            echo -e "\e[32m请输入数据库信息\e[0m"
            read -p "数据库用户名: " db_username
            read -p "数据库密码: " db_password
            read -p "数据库名称: " db_name
            # 将数据库信息写入 info.txt 文件
            echo "$db_username:$db_password:$db_name" > "$info_file"
        fi
    else
        # 创建 info.txt 文件并提示用户输入数据库信息
        touch "$info_file"
        echo -e "\e[32m请输入数据库信息\e[0m"
        read -p "数据库用户名: " db_username
        read -p "数据库密码: " db_password
        read -p "数据库名称: " db_name
        # 将数据库信息写入 info.txt 文件
        echo "$db_username:$db_password:$db_name" > "$info_file"
    fi

    # 备份数据库到 backup.sql 文件
    backup_file="backup.sql"
    if mysqldump -h localhost -u "$db_username" -p"$db_password" "$db_name" > "$backup_dir/$backup_file"; then
        echo -e "\e[32m数据库备份完成，备份文件: $source_cloud_path/$backup_dir/$backup_file\e[0m"
    else
        echo -e "\e[31m数据库备份失败,请检查数据库信息是否有误\e[0m"
        exit 1
    fi

    read -p "按任意键返回主菜单..."
}


# 主菜单
while true; do
    clear
    echo "=== S3存储协议 基于rclone ==="
    echo "请选择一个操作:"
    echo "1) 绑定S3存储"
    echo "2) 网站备份"
    echo "3) 网站还原"
	echo "4) 备份数据库"  # 添加备份数据库选项
    echo "5) 计划任务"
    echo "0) 退出"

    read -p "请输入选项 (1/2/3/4/5): " choice

    case $choice in
        1)
            check_rclone_installed
            create_rclone_config
            bind_s3_storage
            if [ $? -eq 0 ]; then
                # 绑定成功后才返回主菜单
                read -p "按任意键返回主菜单..."
            fi
            ;;
        2)
            website_backup
            ;;
        3)
            website_restore
            ;;
		4)
            backup_database  # 调用备份数据库函数
            ;;

        5)
                        # 进入子菜单
            while true; do
                clear
                echo "=== 计划任务 ==="
                echo "1) 添加计划任务"
                echo "2) 删除计划任务"
                echo "3) 返回主菜单"
                read -p "请选择 (1/2/3): " sub_choice

                case $sub_choice in
                    1)
                        add_schedule_task
                        ;;
                    2)
                        delete_schedule_task
                        ;;
                    3)
                        break
                        ;;
                    *)
                        echo "无效的选择，请重新输入."
                        sleep 2
                        ;;
                esac
            done
            ;;
        0)
            # 退出
            echo "退出脚本."
            exit
            ;;
        *)
            echo "无效的选项，请重新输入."
            ;;
    esac
done
