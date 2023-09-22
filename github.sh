#!/bin/bash
# 6. 设置定时备份

function set_backup_schedule {
    # 完整的备份脚本路径
    backup_script="$HOME/backup.sh"

    # 检查备份脚本是否已存在
    if [ -e "$backup_script" ]; then
        read -p "备份脚本 $backup_script 已经存在，是否要继续设置定时备份？ (Y/N): " continue_response
        if [ "$continue_response" != "Y" ] && [ "$continue_response" != "y" ]; then
            echo "取消设置定时备份。"
            return
        fi
    fi

    # 提示是否需要修改备份时间
    read -p "是否需要修改备份时间？ (Y/N): " modify_time_response
    if [ "$modify_time_response" == "Y" ] || [ "$modify_time_response" == "y" ]; then
        read -p "请输入新的备份时间（例如，21:20）: " new_backup_time
        # 提示输入备份天数间隔
        read -p "请输入备份间隔的天数: " backup_interval
    else
        # 从备份脚本中提取备份时间和天数间隔
        old_backup_time=$(grep -Po 'backup_time=\K[^ ]+' "$backup_script")
        old_backup_interval=$(grep -Po 'backup_interval=\K[^ ]+' "$backup_script")
        new_backup_time="$old_backup_time"
        backup_interval="$old_backup_interval"
    fi

    # 检查是否需要使用原有信息
    use_existing_info="N"
    if [ -e "$backup_script" ]; then
        read -p "是否使用原有信息设置备份？ (Y/N): " use_existing_info
    fi

    if [ "$use_existing_info" == "Y" ] || [ "$use_existing_info" == "y" ]; then
        # 从备份脚本中提取信息
        if [ -e "$backup_script" ]; then
            website_path=$(grep -Po 'website_path=\K[^ ]+' "$backup_script")
            db_username=$(grep -Po 'db_username=\K[^ ]+' "$backup_script")
            db_password=$(grep -Po 'db_password=\K[^ ]+' "$backup_script")
            db_name=$(grep -Po 'db_name=\K[^ ]+' "$backup_script")
            backup_file=$(grep -Po 'backup_file=\K[^ ]+' "$backup_script")
        else
            echo "备份脚本不存在或内容不正确。请手动输入备份信息。"
        fi
    else
        read -p "请输入网站目录路径（例如，/www/wwwroot/judog.cc）: " website_path
        read -p "请输入数据库用户名: " db_username
        read -s -p "请输入数据库密码: " db_password
        echo  # 在密码输入后添加一个换行
        read -p "请输入数据库名称: " db_name
        read -p "请输入备份文件名（例如，backup.sql）: " backup_file
    fi

    # 创建备份脚本
    echo "#!/bin/bash" > "$backup_script"
    echo "" >> "$backup_script"
    echo "# 切换到网站目录" >> "$backup_script"
    echo "website_path=$website_path" >> "$backup_script"
    echo "cd \$website_path || exit 1" >> "$backup_script"
    echo "" >> "$backup_script"
    echo "# 备份数据库" >> "$backup_script"
    echo "db_username=$db_username" >> "$backup_script"
    echo "db_password=$db_password" >> "$backup_script"
    echo "db_name=$db_name" >> "$backup_script"
    echo "backup_file=$backup_file" >> "$backup_script"
    echo 'mysqldump -u$db_username -p$db_password $db_name > $backup_file' >> "$backup_script"
    echo "" >> "$backup_script"
    echo "# 提交更改到Git仓库" >> "$backup_script"
    echo 'git add -A' >> "$backup_script"
    echo 'git commit -m "备份时间：$(date +\%Y\%m\%d\%H\%M)"' >> "$backup_script"
    
    # 提交更改到Git仓库并设置默认分支为 main
    echo 'git push -f origin main' >> "$backup_script"

    # 添加备份脚本的执行权限
    chmod +x "$backup_script"

    # 输出设置完成的提示（绿色高亮）
    echo -e "\e[32m备份脚本已生成并保存到 $backup_script，设置完成，操作成功！\e[0m"

    # 转换时间格式为cron表达式
    cron_minute=$(echo "$new_backup_time" | cut -d':' -f2)
    cron_hour=$(echo "$new_backup_time" | cut -d':' -f1)
    cron_day_interval="*/$backup_interval"

    # 设置定时备份任务
    echo "设置定时备份任务"
    (crontab -l 2>/dev/null; echo "$cron_minute $cron_hour $cron_day_interval * * bash $backup_script > ~/siteback.log 2>&1") | crontab -
}



while :
do
    clear
    echo -e "\e[32m网站备份到github或gitee 默认main分支\e[0m"
	echo "------------------------"
    echo "1. 配置Git SSH密钥"
    echo "2. 创建GitHub私人仓库"
    echo "3. 配置本地仓库"
    echo "4. 备份数据库"
    echo "5. 进行初次备份"
    echo "6. 设置定时备份"
    echo "7. 强制Pull网站数据"
    echo "8. 修改定时计划"
	echo "9. 删除远程仓库分支"
    echo "0. 退出"
    read -p "请选择操作(1/2/3/4/5/6/7/8/9): " choice

    case $choice in
        1)
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
echo -e "\e[32m第一步：配置Git SSH密钥\e[0m"  # 绿色高亮提示

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
  echo -e "\e[32m连接github成功\e[0m"  # 验证成功时的绿色高亮提示
else
  echo -e "\e[31m连接失效\e[0m"  # 验证失败时的红色高亮提示
fi


            ;;
        2)
            # 创建GitHub私人仓库
            # 2. 创建GitHub私人仓库
echo -e "\e[1;32m第二步：创建私人GitHub仓库\e[0m"
echo -e "\e[1;32m请手动创建一个私人GitHub仓库。然后，按回车键继续...\e[0m"
read
            ;;
        3)


# 3. 配置本地仓库

echo -e "\e[32m第三步：配置本地仓库\e[0m"
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


# 验证远程仓库是否存在
if git ls-remote --exit-code origin; then
  echo -e "\e[32m远程仓库存在\e[0m"
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
            # 备份数据库
           # 4. 备份数据库
echo "第四步：备份数据库"
cd "$website_path" || exit 1
# 输入数据库信息
read -p "请输入你的数据库用户名: " db_username
read -p "请输入你的数据库密码: " db_password
echo  # 在密码输入后添加一个换行
read -p "请输入你的数据库名称: " db_name
read -p "请输入备份文件的名称（例如，backup.sql）: " backup_file
mysqldump -u"$db_username" -p"$db_password" "$db_name" > "$backup_file"
            ;;
        5)
#!/bin/bash

check_github_connectivity() {
  echo -e "\e[32m正在检测与GitHub的连通性...\e[0m"
  if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo -e "\e[32m已连接上GitHub，继续\e[0m"
  else
    echo -e "\e[31m连接GitHub失效，请返回第一步操作，终止后续命令\e[0m"
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

echo -e "\e[32m第五步：网站备份\e[0m"

read -p "请输入网站备份目录: " backup_dir

if [ ! -d "$backup_dir" ]; then
  echo -e "\e[31m目录路径不存在，请检查\e[0m"
  exit 1
fi

cd "$backup_dir" || exit 1

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

    echo -e "\e[32m正在检测远程仓库所有分支...\e[0m"

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

      echo "网站已成功备份到新的GitHub仓库: $github_username/$github_repo，默认分支为main"
      exit 0 # 备份到新的仓库后退出脚本
    fi

    # 获取远程仓库的所有分支
    remote_branches=$(git ls-remote --heads "$remote_url" | cut -f2 | cut -d/ -f3)

    # 打印远程仓库的所有分支供用户选择

    echo "远程仓库的所有分支:"
    branch_options=()
    for branch in $remote_branches; do
      branch_options+=("$branch")
      echo "${#branch_options[@]}) $branch"
    done

    # 询问用户选择分支
    while true; do
      read -p "请选择一个分支 (1-${#branch_options[@]}), 或输入新分支名称: " branch_choice
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



    # 合并远程分支到本地分支并自动解决冲突
    git fetch origin "$selected_branch"
    git checkout "$selected_branch"
    git merge -X theirs "origin/$selected_branch" --no-edit


  # 推送到GitHub的选择的分支
  git push -f origin "$selected_branch"
  
  
    green=$(tput setaf 2)
    reset=$(tput sgr0)

    echo "${green}网站已成功备份到$remote_name仓库。选择的远程分支是: $selected_branch${reset}"

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
        7)
            # 强制Pull网站数据
echo "第七步：强制Pull网站数据"

cd "$website_path" || exit 1

# 检查是否存在未提交的本地更改
if git diff --quiet; then
    git pull --force origin master
    echo "网站数据已成功强制更新。"
else
    echo "警告: 本地有未提交的更改，强制Pull将覆盖这些更改。"
    read -p "是否继续？(y/n): " confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        git reset --hard origin/master
        git pull --force origin master
        echo "网站数据已成功强制更新。"
    else
        echo "操作已取消。"
    fi
fi
            ;;
        8)
            # 修改定时计划
            echo "第八步：修改定时计划"
            read -p "请输入新的备份时间（例如，05:15）: " new_backup_time

            # 编辑现有备份脚本
            sed -i "s/$backup_time/$new_backup_time/g" backup.sh

            # 更新定时任务
            (crontab -l 2>/dev/null | grep -v "$website_path/backup.sh"; echo "$new_backup_time * * * * $website_path/backup.sh") | crontab -
            ;;
		9)
		   # 删除远程仓库分支
		   git push origin --delete test
		   
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
