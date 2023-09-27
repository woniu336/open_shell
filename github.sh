#!/bin/bash
# 设置定时备份

# 检查SSH与GitHub服务器的连接状态
check_github_connectivity() {
    echo -e "\e[32m正在检测与GitHub的连通性...\e[0m"

    # 尝试SSH连接到GitHub
    github_status=$(ssh -T git@github.com 2>&1)

    if echo "$github_status" | grep -q "successfully authenticated"; then
        github_message="\e[32m已连接上GitHub，继续\e[0m"
    else
        github_message="\e[31mSSH连接到GitHub服务器失败，请检查SSH密钥和GitHub配置。\e[0m"
        echo "$github_message"
        exit 1
    fi

    echo -e "$github_message"
}

# 添加检查本地仓库与远程仓库的关联函数
check_remote_association() {
    local git_dir="$1/.git"
    
    if [ -d "$git_dir" ]; then
        # 本地仓库存在，检查是否关联了远程仓库
        remote_url=$(git -C "$1" config --get remote.origin.url)
        if [ -n "$remote_url" ]; then
            echo -e "\e[32m本地仓库已关联远程仓库：$remote_url\e[0m"
        else
            echo -e "\e[31m本地仓库未关联远程仓库，请关联后再继续\e[0m"
            exit 1
        fi
    else
        echo -e "\e[31m本地仓库目录不存在，请检查路径\e[0m"
        exit 1
    fi
}

function set_backup_schedule {

    # 提示输入网站备份目录
    read -p "请输入网站备份目录: " website_path

    # 在这里嵌入检查GitHub连接的函数
    check_github_connectivity
	
   # 检查本地仓库与远程仓库的关联
    check_remote_association "$website_path"

    # 备份脚本路径
    backup_script="$HOME/backup.sh"
    
    # 创建备份目录
    backup_dir="$website_path/lufei/backup"
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi

    # 检查备份脚本是否已存在
    if [ -e "$backup_script" ]; then
        read -p "备份脚本 $backup_script 已经存在，是否要继续设置定时备份？ (Y/N): " continue_response
        if [ "$continue_response" != "Y" ] && [ "$continue_response" != "y" ]; then
            echo "取消设置定时备份。"
            return
        fi
    fi

    # 提示请修改备份时间
    echo "请修改备份时间"
    read -p "请输入新的备份时间（例如，21:20）: " new_backup_time
    # 提示输入备份天数间隔
    read -p "请输入备份间隔的天数: " backup_interval

    # 检查是否需要使用原有信息
    use_existing_info="N"
    if [ -e "$backup_script" ]; then
        read -p "是否使用原有信息设置备份？ (Y/N): " use_existing_info
    fi

    if [ "$use_existing_info" != "Y" ] && [ "$use_existing_info" != "y" ]; then
        read -p "请输入网站备份目录: " website_path
    fi

    # 添加选择备份到哪个分支的功能
    echo -e "\e[32m正在检测远程仓库所有分支...\e[0m"
    branches=$(git -C "$website_path" ls-remote --heads "$remote_url" | cut -f2 | sed 's/refs\/heads\///')
    PS3=""  # 清除select结构的提示符
    echo "输入序号选择备份到哪个分支:"
    select branch in $branches; do
        if [ -n "$branch" ]; then
            echo "已选择备份到分支: $branch"
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    # 在备份脚本中使用用户选择的分支进行推送
    if [ "$branch" != "$(git -C "$website_path" symbolic-ref --short HEAD)" ]; then
        # 如果用户选择的分支与当前分支不同，切换到用户选择的分支
        git -C "$website_path" checkout "$branch"
    fi

    # 创建备份脚本
    echo "#!/bin/bash" > "$backup_script"
    echo "" >> "$backup_script"
    echo "# 切换到网站目录" >> "$backup_script"
    echo "website_path=\"$website_path\"" >> "$backup_script"
    echo "cd \"\$website_path\" || exit 1" >> "$backup_script"

    echo "" >> "$backup_script"
    echo "# 提交更改到Git仓库" >> "$backup_script"
    echo 'git add -A' >> "$backup_script"
    echo 'git commit -m "备份时间：$(date +\%Y\%m\%d\%H\%M)"' >> "$backup_script"
    echo "git push -f origin $branch" >> "$backup_script"  # 推送更改到用户选择的分支

    # 添加备份脚本的执行权限
    chmod +x "$backup_script"

    # 输出设置完成的提示（绿色高亮）
    echo -e "\e[32m设置完成,备份脚本路径: $backup_script\e[0m"

    # 转换时间格式为cron表达式
    cron_minute=$(echo "$new_backup_time" | cut -d':' -f2)
    cron_hour=$(echo "$new_backup_time" | cut -d':' -f1)
    cron_day_interval="*/$backup_interval"

    # 检查是否已存在包含backup.sh的定时任务
    existing_cronjob=$(crontab -l 2>/dev/null | grep -F "backup.sh")
    if [ -n "$existing_cronjob" ]; then
        # 移除包含backup.sh的旧定时任务
        (crontab -l 2>/dev/null | grep -vF "backup.sh") | crontab -
    fi

    # 设置新的定时备份任务
    (crontab -l 2>/dev/null; echo "$cron_minute $cron_hour $cron_day_interval * * bash $backup_script > ~/siteback.log 2>&1") | crontab -
}



while :
do
    clear
    echo -e "\e[32m网站备份到github 默认main分支\e[0m"
	echo "------------------------"
    echo "1. 创建GitHub仓库"
    echo "2. 连接GitHub服务器"
    echo "3. 关联GitHub仓库"
    echo "4. 推送到github"
    echo "5. 拉取到本地"
    echo "6. 设置定时备份"
    echo "7. 修改定时计划"
    echo "0. 退出"
    read -p "请选择操作(1/2/3/4/5/6/7/0): " choice

    case $choice in
        2)
# 检查是否存在~/.gitconfig文件
if [ -f ~/.gitconfig ]; then
  # 读取~/.gitconfig中的用户名和邮箱
  existing_username=$(git config --global user.name)
  existing_email=$(git config --global user.email)
  
# 显示已存在的配置并询问是否使用
echo -e "\e[32m已存在的用户名: $existing_username\e[0m"  # 绿色高亮提示
echo -e "\e[32m已存在的邮箱: $existing_email\e[0m"  # 绿色高亮提示

  read -p "是否使用默认配置 (y/n)? " use_default
  if [ "$use_default" == "n" ]; then
    read -p "请输入新的GitHub用户名: " github_username
    read -p "请输入新的GitHub邮箱: " github_email
    git config --global user.name "$github_username"
    git config --global user.email "$github_email"
  else
    github_email="$existing_email"  # 使用已存在的邮箱
  fi
else
  # .gitconfig文件不存在，提示输入用户名和邮箱
echo -e "\e[32m请输入GitHub用户名: \e[0m"  # 绿色高亮提示
read -p "" github_username
echo -e "\e[32m请输入GitHub邮箱: \e[0m"  # 绿色高亮提示
read -p "" github_email
  git config --global user.name "$github_username"
  git config --global user.email "$github_email"
fi

# 生成SSH密钥
echo -e "\e[32m第 2 步：连接GitHub服务器\e[0m"  # 绿色高亮提示

ssh-keygen -t rsa -b 4096 -C "$github_email" -N "" -f ~/.ssh/id_rsa

# 添加GitHub的主机密钥到known_hosts
ssh-keyscan github.com >> ~/.ssh/known_hosts

# 输出公钥以供用户复制并添加到GitHub SSH Keys
echo -e "\e[32m请复制以下公钥内容并添加到GitHub SSH Keys:\e[0m"  # 绿色高亮提示
echo  # 添加一个换行
cat ~/.ssh/id_rsa.pub
echo -e "\e[32m添加公钥地址: https://github.com/settings/ssh/new\e[0m"  # 绿色高亮提示

# 验证关联
echo -e "\e[32m验证关联中...\e[0m"  # 绿色高亮提示

# 尝试SSH连接GitHub
if ssh -T git@github.com 2>&1 | grep "successfully authenticated" > /dev/null; then
  echo -e "\e[32m连接github成功!\e[0m"  # 验证成功时的绿色高亮提示
else
  echo -e "\e[31m连接github失效\e[0m"  # 验证失败时的红色高亮提示
fi


            ;;
        1)
            # 创建GitHub私人仓库
            # 2. 创建GitHub私人仓库
echo -e "\e[1;32m第 1 步：创建私人GitHub仓库\e[0m"
echo -e "\e[1;32m请手动创建一个私人GitHub仓库。然后，按回车键继续...\e[0m"
read
            ;;
        3)
# 检测SSH连接到GitHub服务器是否正常
echo -e "\e[32m检测SSH连接到GitHub服务器是否正常...\e[0m"
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo -e "\e[32m成功连接上github服务器\e[0m"
else
  echo -e "\e[31mSSH连接失败，请检查您的SSH配置\e[0m"
  exit 1
fi

# 3. 配置本地仓库

echo -e "\e[32m第 3 步：关联GitHub仓库\e[0m"
# 提示用户输入网站目录路径，并应用绿色高亮
echo "请输入你的网站目录路径:"
read website_path

# 检查目录是否存在
if [ ! -d "$website_path" ]; then
  echo -e "\e[31m目录路径不存在，请检查\e[0m"
  exit 1
fi

# 切换到网站目录
cd "$website_path" || exit 1

git config --global --add safe.directory "$website_path"

# 检查是否已存在.git目录
if [ -d "$website_path/.git" ]; then
  # .git目录已存在，检查是否已有远程仓库URL
  if git remote -v | grep "origin" > /dev/null; then
    # 如果存在远程仓库别名 "origin"，询问用户是否保留、覆盖或添加新的仓库信息
    echo "已存在的远程仓库别名和URL如下："
    echo -e "\e[32m$(git remote -v)\e[0m"
    read -p "请选择操作 (1=默认, 2=覆盖): " choice
    if [ "$choice" == "2" ]; then
      read -p "请输入新的GitHub用户名: " github_username
      read -p "请输入新的GitHub私人仓库名称: " github_repo_name
      # 覆盖现有的远程仓库别名 "origin"
      git remote rm origin
      git remote add origin "git@github.com:$github_username/$github_repo_name.git"
    fi
  else
    # 不存在远程仓库别名 "origin"，要求用户输入GitHub仓库信息
    read -p "请输入你的GitHub用户名: " github_username
    read -p "请输入你的GitHub私人仓库名称: " github_repo_name
    # 添加新的远程仓库别名 "origin"
    git remote add origin "git@github.com:$github_username/$github_repo_name.git"
  fi
else
  # .git目录不存在，要求用户输入GitHub仓库信息
  read -p "请输入你的GitHub用户名: " github_username
  read -p "请输入你的GitHub私人仓库名称: " github_repo_name
  # 初始化本地Git仓库
  git init
  # 添加新的远程仓库别名 "origin"
  git remote add origin "git@github.com:$github_username/$github_repo_name.git"
fi

# 提示检测

echo -e "\e[32m远程仓库检查中...\e[0m"

  # 检查是否已关联远程仓库URL
  if git remote -v | grep -q "origin"; then
    echo -e "\e[32m已关联远程仓库: $remote_name\e[0m"
else
  echo -e "\e[31m远程仓库不存在\e[0m"
  exit 1
fi

# 提示用户输入GitHub用户名
read -p "再次验证你的GitHub用户名: " input_username

# 输出配置信息
echo -e "已配置的远程仓库别名和URL如下："
echo -e "\e[32m$(git remote -v)\e[0m"

# 检查是否已经成功关联
if git remote -v | grep -q "origin.*git@github.com:$input_username/"; then
  echo -e "\e[32m已成功关联远程仓库\e[0m"
else
  echo -e "\e[31m未关联到自己的GitHub仓库\e[0m"
  exit 1
fi


exit 0

            ;;
        4)
#!/bin/bash

check_github_connectivity() {
  echo -e "\e[32m正在检测与GitHub的连通性...\e[0m"
  if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo -e "\e[32m已连接上GitHub，继续\e[0m"
  else
    echo -e "\e[31m连接GitHub失效，请返回第 2 步操作，终止后续命令\e[0m"
    exit 1
  fi
}

get_database_info() {
  read -p "请输入数据库用户名: " db_username
  read -s -p "请输入数据库密码: " db_password
  echo # 在密码输入后添加一个换行
  read -p "请输入数据库名称: " db_name

  # 统一使用backup.txt和backup.sql作为默认值
  backup_name="backup.txt"
  backup_file="backup.sql"

  # 自动创建datainfo目录，如果不存在
  datainfo_dir="/root/lufei/datainfo"
  if [ ! -d "$datainfo_dir" ]; then
    mkdir -p "$datainfo_dir"
  fi

  # 将信息写入.txt文件，存储在/root/lufei/datainfo/目录中
  echo "db_username=$db_username" > "$datainfo_dir/$backup_name"
  echo "db_password=$db_password" >> "$datainfo_dir/$backup_name"
  echo "db_name=$db_name" >> "$datainfo_dir/$backup_name"
  echo "backup_file=$backup_file" >> "$datainfo_dir/$backup_name"
}

backup_database() {
  if mysqldump -h localhost -u "$db_username" -p"$db_password" "$db_name" > "$back_dir/$backup_file"; then
    echo -e "\e[32m数据库备份完成，存放目录: $back_dir/\e[0m"
  else
    echo -e "\e[31m数据库备份失败,请检查数据库信息是否有误\e[0m"
    exit 1
  fi
}

echo -e "\e[32m第 4 步：推送到github\e[0m"

read -p "请输入网站备份目录: " backup_dir

if [ ! -d "$backup_dir" ]; then
  echo -e "\e[31m目录路径不存在，请检查\e[0m"
  exit 1
fi

# 切换到备份目录，如果切换失败，则退出
cd "$backup_dir" || exit 1

# 提示用户是否需要排除文件或文件夹
read -p "是否需要排除文件或文件夹 (y/n)? " answer

if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    # 提示用户输入要排除的文件或文件夹名称
    read -p "请输入要排除的文件或文件夹名称: " exclude_name

    # 检查是否存在该名称的文件
    if [ -f "$exclude_name" ]; then
        echo "$exclude_name" >> .gitignore
    fi

    # 检查是否存在该名称的文件夹
    if [ -d "$exclude_name" ]; then
        echo "$exclude_name/" >> .gitignore
    fi

    # 提示用户 .gitignore 文件已更新
    echo "已将以下内容添加到 .gitignore 文件:"
    echo "$exclude_name 或 $exclude_name/（取决于存在的类型）"
else
    echo "没有添加任何排除规则到 .gitignore 文件。"
fi

check_github_connectivity

back_dir="$backup_dir/lufei/backup"
if [ ! -d "$back_dir" ]; then
  mkdir -p "$back_dir"
fi

echo "请确认是否需要备份数据库 (y/n): "
read -r need_backup_db

if [ "$need_backup_db" = "y" ]; then
  if [ -f "/root/lufei/datainfo/backup.txt" ]; then
    read -p "发现已有数据库信息，是否要使用原有信息？(y/n): " use_existing_info
    if [ "$use_existing_info" = "y" ]; then
      source "/root/lufei/datainfo/backup.txt"
      backup_database
    elif [ "$use_existing_info" = "n" ]; then
      get_database_info
      backup_database
    else
      echo "无效的输入，请输入 'y' 或 'n' 来确认是否使用原有数据库信息。"
      exit 1
    fi
  else
    get_database_info
    backup_database
  fi
elif [ "$need_backup_db" = "n" ]; then
  echo -e "\e[32m不需要备份数据库，继续后续操作\e[0m"
else
  echo "无效的输入，请输入 'y' 或 'n' 来确认是否需要备份数据库。"
  exit 1
fi


# 获取当前日期并将其格式化为所需的形式
backup_time=$(date +'%Y-%m-%d')

# 获取远程仓库名
remote_name=$(git remote get-url origin | grep -oE 'github\.com[:/][^/]+/[^/]+\.git' | cut -d '/' -f 2 | cut -d '.' -f 1)

# 检查是否已存在.git目录
if [ -d ".git" ]; then
  # 检查是否已关联远程仓库URL
  if git remote -v | grep -q "origin"; then
    echo -e "\e[32m已关联远程仓库: $remote_name\e[0m"

    echo "正在检测远程仓库所有分支..."

# 添加所有更改到暂存区，将输出重定向到 /dev/null
git add . > /dev/null 2>&1

# 提交所有更改，包括备份时间，将输出重定向到 /dev/null
git commit -m "备份时间:$backup_time" > /dev/null 2>&1


    # 获取远程仓库 URL
    remote_url=$(git config --get remote.origin.url)

    # 获取远程仓库的默认分支
    default_branch=$(git ls-remote --symref "$remote_url" HEAD | grep "refs/heads/" | cut -d/ -f3)

    # 如果无法获取默认分支，提示用户输入GitHub用户名和仓库名
    if [ -z "$default_branch" ]; then
      echo "检测到一个空的远程仓库，请手动输入GitHub用户名和仓库名："
      read -p "GitHub用户名: " github_username
      read -p "GitHub仓库名: " github_repo

      if [ -z "$github_username" ] || [ -z "$github_repo" ]; then
        echo "GitHub用户名和仓库名不能为空。"
        exit 1
      fi

      # 添加远程仓库，并将默认分支设置为 "main"
      git remote add origin "git@github.com:$github_username/$github_repo.git"
      git branch -M main
      git push -u origin main

      GREEN='\033[32m'
RESET='\033[0m'

echo -e "${GREEN}推送成功!${RESET}"

      exit 0 # 备份到新的仓库后退出脚本
    fi

# 列出远程分支并以数字序号方式提示选择

echo -e "\e[32m远程分支列表：\e[0m"
git fetch --all
branch_options=($(git branch -r | grep -v '\->' | sed 's/origin\///'))
for i in "${!branch_options[@]}"; do
    echo "$((i + 1)): ${branch_options[$i]}"
done

    # 询问用户选择分支
    while true; do
      read -p "输入序号选择分支: " branch_choice
      if [[ "$branch_choice" =~ ^[0-9]+$ ]] && [ "$branch_choice" -ge 1 ] && [ "$branch_choice" -le "${#branch_options[@]}" ]; then
        selected_branch="${branch_options[$branch_choice-1]}"
        break
      elif [ -n "$branch_choice" ]; then
        # 用户选择了添加新的分支
        selected_branch="$branch_choice"
        # 注意: 这里不要使用 selected_branch，因为用户输入的是新分支名称
        break
      else
        echo "请选择一个分支或输入新分支名称。"
      fi
    done


    echo -e "\e[32m正在同步到所选分支中...\e[0m"

# 分支合并操作 - 只在选择的分支与默认分支不同时执行
if [ "$selected_branch" != "$default_branch" ]; then
  git branch -M "$selected_branch"     # 创建新的选择的分支
  git push -u origin "$selected_branch" # 推送新创建的分支到远程仓库
fi



    # 合并远程分支到本地分支并自动解决冲突,theirs策略会优先选择远程仓库的更改，忽略本地的更改
    git fetch origin "$selected_branch"
    git checkout "$selected_branch"
    git merge -X theirs "origin/$selected_branch" --no-edit


  # 推送到GitHub的选择的分支
  git push -f origin "$selected_branch"
  
  
    green=$(tput setaf 2)
    reset=$(tput sgr0)

    echo "${green}推送成功!"

  else
    echo -e "\e[31m未关联远程仓库URL，请返回第三步操作,终止后续命令\e[0m"
    exit 1
  fi
else
  echo -e "\e[31m没有关联远程仓库,请先执行第三步操作\e[0m"
  exit 1
 fi


            ;;
        6)
# 设置定时备份
            set_backup_schedule

            ;;
        5)
#!/bin/bash
# 检测SSH连接到GitHub服务器是否正常
echo -e "\e[32m正在检测与GitHub的连通性...\e[0m"
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo -e "\e[32m成功连接上GitHub!\e[0m"
else
  echo -e "\e[31m连接GitHub失败，请检查您的SSH配置\e[0m"
  exit 1
fi

echo -e "\e[32m第 5 步：拉取到本地\e[0m"

# 提示输入网站还原目录
read -p "请输入网站还原目录: " website_path
cd "$website_path" || exit 1
git config --global --add safe.directory "$website_path"

# 检查是否是一个有效的本地仓库
if [ -d .git ]; then
    echo "本地仓库存在。"
else
    echo -e "\e[32m本地仓库不存在，正在初始化...\e[0m"
    git init  # 初始化本地仓库
    read -p "请输入GitHub用户名: " github_username
	# 设置 Git 的用户名
    read -p "请输入GitHub仓库名: " github_repo_name
	git remote add origin "git@github.com:$github_username/$github_repo_name.git"
    echo "远程仓库已关联到本地仓库。"
fi

# 列出远程分支并以数字序号方式提示选择
echo -e "\e[32m正在检测远程仓库所有分支...\e[0m"
echo -e "\e[32m远程分支列表：\e[0m"
git fetch --all
branches=($(git branch -r | grep -v '\->' | sed 's/origin\///'))
for i in "${!branches[@]}"; do
    echo "$((i + 1)): ${branches[$i]}"
done

read -p $'\e[32m输入序号选择从哪个分支还原: \e[0m' branch_number

if [[ "$branch_number" =~ ^[0-9]+$ ]]; then
    if [ "$branch_number" -ge 1 ] && [ "$branch_number" -le "${#branches[@]}" ]; then
        selected_branch="${branches[$branch_number - 1]}"
        # 在执行 pull 前提示本地数据将被覆盖，并确认是否继续
        read -p $'\e[32m警告：本地数据将被覆盖，是否继续？(y/n): \e[0m' confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            git fetch origin "$selected_branch"
            git reset --hard "origin/$selected_branch"
            echo -e "\e[32m拉取成功!\e[0m"

            # 检查并删除多出文件和文件夹
            echo "检查本地多余文件和文件夹..."
            clean_output=$(git clean -nd | sed 's/^Would remove //' | sed 's/^Removing //')  # 存储并处理输出
            if echo "$clean_output" | grep -q "[a-zA-Z0-9]"; then
                echo "$clean_output"  # 打印多余文件和文件夹列表
                read -p $'\e[32m是否删除多余文件和文件夹？(y/n): \e[0m' clean_confirm
                if [ "$clean_confirm" = "y" ] || [ "$clean_confirm" = "Y" ]; then
                    git clean -df  # 实际删除多出文件和文件夹
                    echo -e "\e[32m多余文件和文件夹已删除。\e[0m"
                else
                    echo -e "\e[32m未删除多余文件和文件夹。\e[0m"
                fi
            else
                echo -e "\e[32m没有多余文件和文件夹。\e[0m"
            fi
        else
            echo "操作已取消。"
        fi
    else
        echo "无效的选择。"
    fi
else
    echo "无效的选择。"
fi
            ;;
        7)
clear
# 备份脚本的路径
backup_script="/root/backup.sh"

# 日志文件路径
log_file="~/siteback.log"

# 显示菜单
function display_menu() {
    echo "请选择操作:"
    echo "1. 设置新的备份时间"
    echo "2. 删除现有定时任务"
    echo "3. 退出"
}

# 获取用户选择
function get_choice() {
    read -p "请输入选项 (1/2/3): " choice
    case "$choice" in
        1) set_new_backup_time ;;
        2) remove_existing_cronjob ;;
        3) exit 0 ;;
        *) echo "无效的选项，请重新选择。" ; get_choice ;;
    esac
}

# 设置新的备份时间
function set_new_backup_time() {
    read -p "请输入新的备份时间（格式：HH:MM，例如：21:09）: " new_backup_time
    # 解析小时和分钟
    cron_hour=$(echo "$new_backup_time" | cut -d':' -f1)
    cron_minute=$(echo "$new_backup_time" | cut -d':' -f2)

    read -p "请输入备份间隔（每隔几天执行一次，例如：1表示每天，2表示每隔两天）: " backup_interval
    
    # 生成cron表达式
    cron_day_interval="*/$backup_interval"

    # 移除旧的定时任务
    (crontab -l 2>/dev/null | grep -vF "backup.sh") | crontab -
    
    # 设置新的定时备份任务
    (crontab -l 2>/dev/null; echo "$cron_minute $cron_hour * * $cron_day_interval bash $backup_script > $log_file 2>&1") | crontab -
    
    echo -e "\e[32m新的备份时间已设置。\e[0m"
}

# 删除现有的定时任务
function remove_existing_cronjob() {
    existing_cronjob=$(crontab -l 2>/dev/null | grep -F "backup.sh")
    if [ -n "$existing_cronjob" ]; then
        (crontab -l 2>/dev/null | grep -vF "backup.sh") | crontab -
        echo -e "\e[32m现有的定时任务已删除。\e[0m"
    else
        echo "没有找到包含备份脚本的定时任务。"
    fi
}

# 主菜单循环
while true; do
    display_menu
    get_choice
done

            ;;
        0)
            # 退出脚本
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效的选择，请重新选择"
            ;;
    esac

    read -p "按任意键继续..."
done
