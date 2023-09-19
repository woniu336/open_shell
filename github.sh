#!/bin/bash
# 6. 设置定时备份
function set_backup_schedule {
    # 完整的备份脚本路径
    backup_script="$HOME/backup.sh"

    # 检查备份脚本是否已存在
    if [ -e "$backup_script" ]; then
        read -p "备份脚本 $backup_script 已经存在，是否要重命名现有备份脚本并继续设置定时备份？ (Y/N): " rename_response
        if [ "$rename_response" != "Y" ] && [ "$rename_response" != "y" ]; then
            echo "取消设置定时备份。"
            return
        else
            read -p "请输入新的备份脚本名称（例如，new_backup）: " new_backup_script
            # 消耗换行符
            read -n 1 -s
            backup_script="$HOME/$new_backup_script.sh"
        fi
    fi

    echo "设置定时备份"
    read -p "请输入备份的时间（例如，05:15）: " backup_time
    read -p "请输入网站目录路径（例如，/www/wwwroot/judog.cc）: " website_path
    read -p "请输入数据库用户名: " db_username
    read -s -p "请输入数据库密码: " db_password
    echo  # 在密码输入后添加一个换行
    read -p "请输入数据库名称: " db_name
    read -p "请输入备份文件名（例如，backup.sql）: " backup_file

    # 创建备份脚本
    echo "#!/bin/bash" > "$backup_script"
    echo "" >> "$backup_script"
    echo "# 切换到网站目录" >> "$backup_script"
    echo "cd $website_path || exit 1" >> "$backup_script"
    echo "" >> "$backup_script"
    echo "# 备份数据库" >> "$backup_script"
    echo "mysqldump -u$db_username -p$db_password $db_name > $backup_file" >> "$backup_script"
    echo "" >> "$backup_script"
    echo "# 提交更改到Git仓库" >> "$backup_script"
    echo 'git add -A' >> "$backup_script"
    echo 'git commit -m "备份时间：$(date +\%Y\%m\%d\%H\%M)"' >> "$backup_script"
    echo 'git push -f origin master' >> "$backup_script"

    # 添加备份脚本的执行权限
    chmod +x "$backup_script"

    # 输出设置完成的提示（绿色高亮）
    echo -e "\e[32m备份脚本已生成并保存到 $backup_script，设置完成，操作成功！\e[0m"

# 设置定时备份
    echo "设置定时备份任务"
    (crontab -l 2>/dev/null; echo "$backup_time * * * bash $backup_script > ~/siteback.log 2>&1") | crontab -

}


while :
do
    clear
    echo "欢迎使用网站备份工具"
    echo "1. 配置Git SSH密钥"
    echo "2. 创建GitHub私人仓库"
    echo "3. 配置本地仓库"
    echo "4. 备份数据库"
    echo "5. 进行初次备份"
    echo "6. 设置定时备份"
    echo "7. 强制Pull网站数据"
    echo "8. 修改定时计划"
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
  echo -e "\e[32m关联成功\e[0m"  # 验证成功时的绿色高亮提示
else
  echo -e "\e[31m关联失效\e[0m"  # 验证失败时的红色高亮提示
fi


            ;;
        2)
            # 创建GitHub私人仓库
            # 2. 创建GitHub私人仓库
echo "第二步：创建私人GitHub仓库"
echo "请手动创建一个私人GitHub仓库。然后，按回车键继续..."
read
            ;;
        3)
# 3. 配置本地仓库
# 定义 ANSI 转义序列来设置绿色文本
GREEN='\033[0;32m'

# 重置文本样式
RESET='\033[0m'

echo "第三步：配置本地仓库"
# 提示用户输入网站目录路径，并应用绿色高亮
echo -e "${GREEN}请输入你的网站目录路径:${RESET}"
read website_path

# 切换到网站目录
cd "$website_path" || exit 1

# 在这里添加命令以添加例外规则
#echo "为了确保Git忽略 $website_path 目录的权限问题，运行以下命令："
git config --global --add safe.directory "$website_path"

# 检查是否已存在.git目录
if [ -d "$website_path/.git" ]; then
  # .git目录已存在，检查是否已有远程仓库URL
  if git remote -v | grep "origin" > /dev/null; then
    # 如果存在远程仓库别名 "origin"，询问用户是否保留、覆盖或添加新的仓库信息
    echo "已存在的远程仓库别名和URL如下："
    git remote -v
    read -p "请选择操作 (1=保留, 2=覆盖, 3=添加新的): " choice
    if [ "$choice" == "2" ]; then
      read -p "请输入新的GitHub用户名: " github_username
      read -p "请输入新的GitHub私人仓库名称: " github_repo_name
      # 覆盖现有的远程仓库别名 "origin"
      git remote rm origin
      git remote add origin "git@github.com:$github_username/$github_repo_name.git"
    elif [ "$choice" == "3" ]; then
      read -p "请输入新的GitHub用户名: " github_username
      read -p "请输入新的GitHub私人仓库名称: " github_repo_name
      # 添加新的远程仓库别名 "origin"
      git remote set-url --add origin "git@github.com:$github_username/$github_repo_name.git"
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

# 输出配置信息
echo "已配置的远程仓库别名和URL如下："
git remote -v


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
# 5. 初次备份
echo "第五步：初次备份"

# 提示用户输入备份目录
read -p "请输入你的网站备份目录路径: " backup_dir

# 将备份目录路径添加到备份文件名中
backup_file="$backup_dir/$backup_file"

# 切换到备份目录
cd "$backup_dir" || exit 1

# 将更改提交到本地Git仓库
git add -A
git commit -m "初始备份"

# 推送到GitHub
git push -f origin master
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
