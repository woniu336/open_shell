#!/bin/bash

while true; do
    echo "1) 安装rclone"
    echo "2) 添加网盘"
    echo "3) 挂载网盘"
    echo "4) 网盘操作"
    echo "5) 退出"
	echo "6) 手动配置 (rclone config)"

    read -p "请选择要执行的操作: " choice

    case $choice in

6)
    # 执行手动配置命令
    rclone config
    ;;


        1)
            if command -v rclone &>/dev/null; then
                echo "rclone已安装."
            else
                if [ -f /etc/os-release ]; then
                    source /etc/os-release
                    if [[ $ID == "ubuntu" ]]; then
                        sudo apt-get install curl unzip && sudo apt-get install fuse3 &&
                        curl https://rclone.org/install.sh | sudo bash
                    elif [[ $ID == "centos" ]]; then
                        sudo yum install curl unzip fuse3 -y &&
                        curl https://rclone.org/install.sh | sudo bash
                    else
                        echo "不支持的操作系统."
                    fi
                else
                    echo "不支持的操作系统."
                fi
                echo "rclone安装完成."
            fi
            ;;
        2)
            # 添加网盘的操作
            echo "1) 阿里云盘"
            echo "2) 腾讯COS"
            echo "3) Cloudflare R2"
            echo "4) Backblaze B2"
            echo "5) 阿里云oss"
            echo "6) Sharepoint(onedrive)"
            echo "7) 七牛Kodo(洛杉矶区域)"
            read -p "请选择要添加的网盘: " cloud_choice

            case $cloud_choice in
                1)
                    # 检查docker是否安装
                    if ! command -v docker &>/dev/null; then
                        curl -fsSL https://get.docker.com | sh
                        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                        chmod +x /usr/local/bin/docker-compose
                    fi

                    # 获取服务器公网IP
                    public_ip=$(curl -s https://api.ipify.org)

                    # 提示用户输入用户名
                    read -p "请输入用户名: " username

                    # 提示用户输入密码并进行密码混淆
                    read -p "请输入密码: " plain_password
                    obscured_password=$(rclone obscure "$plain_password")

                    # 提示用户获取refresh token
                    echo "请在https://messense-aliyundrive-webdav-backendrefresh-token-ucs0wn.streamlit.app/获取refresh token"
                    read -p "请输入refresh token: " refresh_token

                    # 创建rclone配置文件
                    mkdir -p /root/.config/rclone/
                    cat >> /root/.config/rclone/rclone.conf <<EOL
[aliyun]
type = webdav
url = http://${public_ip}:8080
vendor = other
user = $username
pass = $obscured_password
EOL

                    # 使用docker运行aliyundrive-webdav
                    docker run -d --name=aliyundrive-webdav --restart=unless-stopped -p 8080:8080 \
                      -v /etc/aliyundrive-webdav/:/etc/aliyundrive-webdav/ \
                      -e REFRESH_TOKEN=$refresh_token \
                      -e WEBDAV_AUTH_USER=$username \
                      -e WEBDAV_AUTH_PASSWORD=$plain_password \
                      messense/aliyundrive-webdav

                    echo "阿里云盘添加完成."
                    ;;
                2)
                    # 检查rclone是否安装
                    if ! command -v rclone &>/dev/null; then
                        echo "rclone未安装，请先安装rclone."
                    else
                        read -p "请输入腾讯COS的Access Key ID: " cos_access_key_id
                        read -p "请输入腾讯COS的Secret Access Key: " cos_secret_access_key
                        read -p "请输入腾讯COS的Endpoint: " cos_endpoint

                        # 添加腾讯COS的配置到rclone.conf
                        cat >> /root/.config/rclone/rclone.conf <<EOL
[cos]
type = s3
provider = TencentCOS
access_key_id = $cos_access_key_id
secret_access_key = $cos_secret_access_key
endpoint = $cos_endpoint
acl = default
storage_class = STANDARD
EOL
                        echo "腾讯COS添加完成."
                    fi
                    ;;
                3)
                    # 提示用户输入Cloudflare R2的Access Key ID、Secret Access Key和Endpoint
                    read -p "请输入Cloudflare R2的Access Key ID: " r2_access_key_id
                    read -p "请输入Cloudflare R2的Secret Access Key: " r2_secret_access_key
                    read -p "请输入Cloudflare R2的Endpoint: " r2_endpoint

                    # 添加Cloudflare R2的配置到rclone.conf
                    cat >> /root/.config/rclone/rclone.conf <<EOL
[r2]
type = s3
provider = Cloudflare
access_key_id = $r2_access_key_id
secret_access_key = $r2_secret_access_key
region = auto
endpoint = $r2_endpoint
EOL
                    echo "Cloudflare R2添加完成."
                    ;;
                4)
                    # 提示用户输入Backblaze B2的Account和Key
                    read -p "请输入Backblaze B2的Account: " b2_account
                    read -p "请输入Backblaze B2的Key: " b2_key

                    # 添加Backblaze B2的配置到rclone.conf
                    cat >> /root/.config/rclone/rclone.conf <<EOL
[b2]
type = b2
account = $b2_account
key = $b2_key
hard_delete = true
EOL
                    echo "Backblaze B2添加完成."
                    ;;
                5)
                    # 提示用户输入阿里云oss的Access Key ID、Secret Access Key和Endpoint
                    read -p "请输入阿里云oss的Access Key ID: " oss_access_key_id
                    read -p "请输入阿里云oss的Secret Access Key: " oss_secret_access_key
                    read -p "请输入阿里云oss的Endpoint: " oss_endpoint

                    # 添加阿里云oss的配置到rclone.conf
                    cat >> /root/.config/rclone/rclone.conf <<EOL
[oss]
type = s3
provider = Alibaba
access_key_id = $oss_access_key_id
secret_access_key = $oss_secret_access_key
endpoint = $oss_endpoint
acl = private
EOL
                    echo "阿里云oss添加完成."
                    ;;
                6)
                    # Sharepoint(onedrive)的配置
                    read -p "请输入url: " onedrive_url
                    read -p "请输入用户名(user): " onedrive_user
                   # 提示用户输入密码并进行密码混淆
                    read -p "请输入Sharepoint(onedrive)密码: " sp_password
                    obscured_password=$(rclone obscure "$sp_password")

                    # 添加配置到rclone.conf
                    cat >> /root/.config/rclone/rclone.conf <<EOL
[sp]
type = webdav
url = $onedrive_url/Shared Documents
vendor = sharepoint
user = $onedrive_user
pass = $obscured_password
EOL

                   echo "Sharepoint(onedrive)配置已添加完成."
                   ;;
                7)
                    # 七牛Kodo(洛杉矶区域)的配置
                    read -p "请输入access_key_id: " qiniu_access_key_id
                    read -p "请输入secret_access_key: " qiniu_secret_access_key

                    # 添加配置到rclone.conf，不覆盖原有配置
                    cat >> /root/.config/rclone/rclone.conf <<EOL
[niu]
type = s3
provider = Qiniu
access_key_id = $qiniu_access_key_id
secret_access_key = $qiniu_secret_access_key
region = us-north-1
endpoint = s3-us-north-1.qiniucs.com
acl = private
storage_class = STANDARD
EOL

                    echo "七牛Kodo(洛杉矶区域)配置已添加完成."
                    ;;
                *)
                    echo "无效的选择，请重新选择."
                    ;;
            esac
            ;;
        3)
            # 挂载网盘的操作
            echo "请选择要挂载的网盘："
            if grep -q "\[aliyun\]" /root/.config/rclone/rclone.conf; then
                echo "1) 挂载阿里云盘"
            fi
            if grep -q "\[cos\]" /root/.config/rclone/rclone.conf; then
                echo "2) 挂载腾讯云COS"
            fi
            if grep -q "\[r2\]" /root/.config/rclone/rclone.conf; then
                echo "3) 挂载Cloudflare R2"
            fi
            if grep -q "\[b2\]" /root/.config/rclone/rclone.conf; then
                echo "4) 挂载Backblaze B2"
            fi
            if grep -q "\[oss\]" /root/.config/rclone/rclone.conf; then
                echo "5) 挂载阿里云oss"
            fi
            if grep -q "\[sp\]" /root/.config/rclone/rclone.conf; then
                echo "6) 挂载Sharepoint(onedrive)"
            fi
            if grep -q "\[niu\]" /root/.config/rclone/rclone.conf; then
                echo "7) 挂载七牛Kodo(洛杉矶区域)"
			fi
            if grep -q "\[gd\]" /root/.config/rclone/rclone.conf; then
                echo "8) 挂载谷歌云盘"
			fi
            if grep -q "\[od\]" /root/.config/rclone/rclone.conf; then
                echo "9) 挂载OneDrive"
            fi

            read -p "请选择要挂载的网盘: " mount_choice

            case $mount_choice in
                1)
                    if grep -q "\[aliyun\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/aliyun
                        rclone mount aliyun: /home/aliyun --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "阿里云盘已挂载到 /home/aliyun。"
                    else
                        echo "阿里云盘配置不存在，请先添加网盘。"
                    fi
                    ;;
                2)
                    if grep -q "\[cos\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/cos
                        rclone mount cos: /home/cos --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "腾讯云COS已挂载到 /home/cos。"
                    else
                        echo "腾讯云COS配置不存在，请先添加网盘。"
                    fi
                    ;;
                3)
                    if grep -q "\[r2\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/r2
                        rclone mount r2: /home/r2 --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "Cloudflare R2已挂载到 /home/r2。"
                    else
                        echo "Cloudflare R2配置不存在，请先添加网盘。"
                    fi
                    ;;
                4)
                    if grep -q "\[b2\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/b2
                        rclone mount b2: /home/b2 --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "Backblaze B2已挂载到 /home/b2。"
                    else
                        echo "Backblaze B2配置不存在，请先添加网盘。"
                    fi
                    ;;
                5)
                    if grep -q "\[oss\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/oss
                        rclone mount oss: /home/oss --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "阿里云oss已挂载到 /home/oss。"
                    else
                        echo "阿里云oss配置不存在，请先添加网盘。"
                    fi
                    ;;
                6)
                    if grep -q "\[sp\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/sp
                        rclone mount sp: /home/sp --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "Sharepoint(onedrive)已挂载到 /home/sp。"
                    else
                        echo "Sharepoint(onedrive)配置不存在，请先添加网盘。"
                    fi
                    ;;
                7)
                    if grep -q "\[niu\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/niu
                        rclone mount niu: /home/niu --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "七牛Kodo(洛杉矶区域)已挂载到 /home/niu。"
                    else
                        echo "七牛Kodo(洛杉矶区域)配置不存在，请先添加网盘。"
                    fi
                    ;;
				8)
                    if grep -q "\[gd\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/gd
                        rclone mount gd: /home/gd --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "谷歌云盘已挂载到 /home/gd。"
                    else
                        echo "谷歌云盘配置不存在，请先添加网盘。"
                    fi
                    ;;
				9)
                    if grep -q "\[od\]" /root/.config/rclone/rclone.conf; then
                        mkdir -p /home/od
                        rclone mount od: /home/od --allow-other --vfs-cache-mode writes --allow-non-empty --no-modtime &
                        echo "OneDrive国际版已挂载到 /home/od。"
                    else
                        echo "OneDrive国际版配置不存在，请先添加网盘。"
                    fi
                    ;;
                *)
                    echo "无效的选择，请重新选择."
                    ;;
            esac
            ;;
 4)
    while true; do
        echo "1) 卸载挂载"
        echo "2) 文件操作"
		echo "3) 网盘检测"
        echo "4) 返回上一层"
        
        read -p "请选择网盘操作: " disk_operation
        
        case $disk_operation in
            1)
                # 检查已挂载的网盘并列出
                mounted_disks=()
                if mount | grep -q '/home/aliyun'; then
                    mounted_disks+=("阿里云盘")
                fi
                if mount | grep -q '/home/cos'; then
                    mounted_disks+=("腾讯云COS")
                fi
                if mount | grep -q '/home/r2'; then
                    mounted_disks+=("Cloudflare R2")
                fi
                if mount | grep -q '/home/b2'; then
                    mounted_disks+=("Backblaze B2")
				fi
                if mount | grep -q '/home/oss'; then
                    mounted_disks+=("阿里云oss")
				fi
                if mount | grep -q '/home/sp'; then
                    mounted_disks+=("Sharepoint")
				fi
                if mount | grep -q '/home/niu'; then
                    mounted_disks+=("七牛Kodo")
				fi
                if mount | grep -q '/home/gd'; then
                    mounted_disks+=("谷歌云盘")
				fi
                if mount | grep -q '/home/od'; then
                    mounted_disks+=("OneDrive国际版")
				
                fi
                
                if [ ${#mounted_disks[@]} -eq 0 ]; then
                    echo "没有已挂载的网盘."
                else
                    # 列出已挂载的网盘并允许用户选择卸载
                    echo "请选择要卸载的网盘："
                    for ((i=0; i<${#mounted_disks[@]}; i++)); do
                        echo "$((i+1))) ${mounted_disks[i]}"
                    done
                    echo "$((i+2))) 返回上一层"
                    
                    read -p "请选择要卸载的网盘: " unmount_choice
                    
                    case $unmount_choice in
                        [1-$((i+1))])
                            if [ $unmount_choice -eq $((i+1)) ]; then
                                break
                            fi
                            unmount_index=$((unmount_choice-1))
                            unmount_disk="${mounted_disks[$unmount_index]}"
                            
                            # 根据用户选择卸载对应的网盘
                            case $unmount_disk in
                                "阿里云盘")
                                    fusermount -qzu /home/aliyun
                                    echo "阿里云盘已卸载."
                                    ;;
                                "腾讯云COS")
                                    fusermount -qzu /home/cos
                                    echo "腾讯云COS已卸载."
                                    ;;
                                "Cloudflare R2")
                                    fusermount -qzu /home/r2
                                    echo "Cloudflare R2已卸载."
                                    ;;
                                "Backblaze B2")
                                    fusermount -qzu /home/b2
                                    echo "Backblaze B2已卸载."
                                    ;;
                                "阿里云oss")
                                    fusermount -qzu /home/oss
                                    echo "阿里云oss已卸载."
                                    ;;
                                "Sharepoint")
                                    fusermount -qzu /home/sp
                                    echo "sharepoint已卸载."
                                    ;;
                                "七牛Kodo")
                                    fusermount -qzu /home/niu
                                    echo "七牛Kodo已卸载."
                                    ;;
								"谷歌云盘")
                                    fusermount -qzu /home/gd
                                    echo "谷歌云盘已卸载."
                                    ;;
								"OneDrive国际版")
                                    fusermount -qzu /home/od
                                    echo "OneDrive国际版已卸载."
                                    ;;
                                *)
                                    echo "无效的选择，请重新选择."
                                    ;;
                            esac
                            ;;
                        *)
                            echo "无效的选择，请重新选择."
                            ;;
                    esac
                fi
                ;;
2)
    
    while true; do
        echo "1) 拷贝文件"
        echo "2) 同步文件"
        echo "3) 新建文件夹"
        echo "4) 删除文件"
        echo "5) 网盘互拷"
        echo "6) 目录查询"
        echo "7) 返回上一层"

        read -p "请选择文件操作: " file_operation

        case $file_operation in
            1)
                # 拷贝文件操作
                read -p "请输入源路径: " source_path
                read -p "请输入目标路径: " destination_path

                # 执行拷贝操作
                rclone copy "$source_path" "$destination_path" --ignore-existing -u -v -P --transfers=15 --ignore-errors --buffer-size=64M --check-first --checkers=10 --drive-acknowledge-abuse
                echo "拷贝操作已完成."
                ;;
            2)
                # 同步文件操作
                read -p "请输入源路径: " source_path
                read -p "请输入目标路径: " destination_path

                # 执行同步操作
                rclone sync "$source_path" "$destination_path" --ignore-existing -u -v -P --transfers=15 --ignore-errors --buffer-size=64M --check-first --checkers=10 --drive-acknowledge-abuse
                echo "同步操作已完成."
                ;;
            3)
                # 新建文件夹操作
                read -p "请输入网盘路径: " cloud_path
                read -p "请输入文件夹名称: " folder_name

                # 执行新建文件夹操作
                rclone touch "$cloud_path/$folder_name/emptyfile.txt"
                echo "新建文件夹操作已完成."
                ;;
            4)
                # 删除文件操作
                read -p "请输入网盘路径: " cloud_path

                # 执行删除文件操作
                rclone delete "$cloud_path" --include "*"
                echo "删除文件操作已完成."
                ;;
5)
                                    # 网盘互拷操作
                                    read -p "请输入源网盘路径: " source_cloud_path
                                    read -p "请输入目标网盘路径: " destination_cloud_path

                                    # 提示用户是否需要排除文件
                                    echo "是否需要排除文件？"
                                    echo "1) 是"
                                    echo "2) 否"
                                    read -p "请选择 (1/2): " exclude_files_choice

    if [ "$exclude_files_choice" == "1" ]; then
        read -p "请输入要排除的文件或文件夹（使用逗号分隔）: " exclude_files
        # 将排除的内容按逗号分隔并写入规则文件
        IFS=',' read -ra exclude_array <<< "$exclude_files"
        for exclude_item in "${exclude_array[@]}"; do
            echo "- $exclude_item" >> /root/.config/rclone/filter-file.txt
        done
    fi

                                    # 执行拷贝操作，根据是否有排除规则来选择是否使用过滤规则文件
                                    if [ -f /root/.config/rclone/filter-file.txt ]; then
                                        rclone copy "$source_cloud_path" "$destination_cloud_path" --ignore-existing -u -v -P --transfers=10 --ignore-errors --buffer-size=64M --check-first --checkers=10 --drive-acknowledge-abuse --filter-from /root/.config/rclone/filter-file.txt
                                        echo "网盘互拷操作已完成."
                                        rm /root/.config/rclone/filter-file.txt # 删除临时的过滤规则文件
                                    else
                                        rclone copy "$source_cloud_path" "$destination_cloud_path" --ignore-existing -u -v -P --transfers=10 --ignore-errors --buffer-size=64M --check-first --checkers=10 --drive-acknowledge-abuse
                                        echo "网盘互拷操作已完成."
                                    fi
                                    ;;
6)
PS3=""  # 清除select结构的提示符
    echo "已配置的网盘："
    # 从rclone配置文件中提取已配置的网盘名称
    configured_clouds=$(grep '\[' ~/.config/rclone/rclone.conf | sed 's/\[\(.*\)\]/\1/')
    
    select cloud in $configured_clouds; do
        # 使用rclone lsf命令获取网盘目录
        cloud_directories=($(rclone lsf ${cloud}:))
        echo "已选择网盘: ${cloud}"
        echo "目录列表："
        
        # 显示目录的序号和格式化的名称
        for ((i=1; i<=${#cloud_directories[@]}; i++)); do
            echo "$i) ${cloud}:${cloud_directories[i-1]}"
        done

        read -p "请选择目录序号: " directory_choice
        selected_directory="${cloud}:${cloud_directories[$((directory_choice-1))]}"
        
        echo "你选择的目录是：${selected_directory}"
                            # 提示用户是否要复制到本地路径
                            
                                echo "是否要复制到本地路径？"
                                echo "1) 是"
                                echo "2) 否"
                                read -p "请选择 (1/2): " copy_to_local

                                case $copy_to_local in
                                    1)
                                        read -p "请输入本地路径: " local_path
                                        # 执行文件复制操作
                                        rclone copy "$selected_directory" "$local_path" --ignore-existing -u -v -P --transfers=15 --ignore-errors --buffer-size=64M --check-first --checkers=10 --drive-acknowledge-abuse
                                        echo "文件已复制到本地路径：$local_path"
                                        ;;
                                    2)
                                        echo "未执行复制操作."
                                        ;;
                                    *)
                                        echo "无效的选择，请重新选择 (1/2)."
                                        ;;
                                esac

                                # 提示是否查看子目录内容
                               
                                    echo "是否查看 ${selected_directory} 下子目录所有内容？"
                                    echo "1) 是"
                                    echo "2) 否"
                                    read -p "请选择 (1/2): " view_subdirectory

                                    case $view_subdirectory in
                                        1)
                                            echo "子目录内容如下："
                                            rclone ls "$selected_directory"
                                            ;;
                                        2)
                                            echo "未查看子目录内容."
                                            ;;
                                        *)
                                            echo "无效的选择，请重新选择 (1/2)."
                                            ;;
                                   
                              
     esac
            done
            ;;
                     

            7)
                break
                ;;
            *)
                echo "无效的选择，请重新选择文件操作."
                ;;
        esac
    done
    ;;
3)
    # 网盘检测
    echo "正在检查已配置的网盘..."

    # 从rclone配置文件中获取所有已配置的网盘名称
    configured_clouds=$(grep '\[' ~/.config/rclone/rclone.conf | sed 's/\[\(.*\)\]/\1/')

    # 添加一组新的网盘名称和路径
    declare -A cloud_paths=(
        ["aliyun"]="阿里云盘"
        ["cos"]="腾讯云cos"
        ["r2"]="Cloudflare R2"
        ["b2"]="Backblaze B2"
        ["oss"]="阿里云oss"
        ["sp"]="Sharepoint"
        ["niu"]="七牛kodo"
        ["your_cloud"]="你的网盘路径" # 添加的新映射关系
    )

    # 使用Markdown格式输出网盘检测结果
    echo "| 网盘名称 | 状态     |"
    echo "|----------|----------|"

    for cloud in $configured_clouds; do
        # 获取网盘路径
        cloud_path="${cloud_paths[$cloud]:-$cloud}"
        
        # 使用 rclone lsf 命令检测网盘是否可用，超时时间设置为 10 秒
        if timeout 10s rclone lsf "$cloud:" >/dev/null 2>&1; then
            status="正常"
        else
            status="失效"
        fi
        # 获取网盘名称
        cloud_name="${cloud_paths[$cloud]:-$cloud}"
        echo "| $cloud_name   | $status     |"
    done
    ;;
                    4)
                        break
                        ;;
                    *)
                        echo "无效的选择，请重新选择网盘操作."
                        ;;
                esac
            done
            ;;
        5)
            exit 0
            ;;
        *)
            echo "无效的选择，请重新选择操作."
            ;;
    esac
done