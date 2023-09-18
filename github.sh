#!/bin/bash

# 1. 配置Git SSH密钥
echo "第一步：配置Git SSH密钥"
read -p "请输入你的GitHub用户名: " github_username
read -p "请输入你的GitHub邮箱: " github_email

git config --global user.name "$github_username"
git config --global user.email "$github_email"

# 生成SSH密钥
ssh-keygen -t rsa -b 4096 -C "$github_email"

# 输出公钥以供用户复制并添加到GitHub SSH Keys
echo "请复制以下公钥内容并添加到GitHub SSH Keys:"
cat ~/.ssh/id_rsa.pub

echo ""

echo "添加公钥地址: https://github.com/settings/ssh/new"


# 2. 建立私人仓库
echo "第二步：创建私人GitHub仓库"
echo "请手动创建一个私人GitHub仓库。然后，按回车键继续..."
read

# 3. 配置本地仓库
echo "第三步：配置本地仓库"
read -p "请输入你的网站目录路径: " website_path

# 在这里添加命令以添加例外规则
echo "为了确保Git忽略 $website_path 目录的权限问题，运行以下命令："
git config --global --add safe.directory "$website_path"

# 输入数据库信息
read -p "请输入你的数据库用户名: " db_username
read -s -p "请输入你的数据库密码: " db_password
echo  # 在密码输入后添加一个换行
read -p "请输入你的数据库名称: " db_name
read -p "请输入备份文件的名称（例如，backup.sql）: " backup_file

# 输入GitHub仓库信息
read -p "请输入你的GitHub用户名: " github_username
read -p "请输入你的GitHub私人仓库名称: " github_repo_name

# 初始化本地Git仓库
cd "$website_path" || exit 1
git init
git remote add origin "git@github.com:$github_username/$github_repo_name.git"

# 4. 备份数据库
echo "第四步：备份数据库"
cd "$website_path" || exit 1
mysqldump -u"$db_username" -p"$db_password" "$db_name" > "$backup_file"

# 5. 初次备份
echo "第五步：初次备份"
# 将更改提交到本地Git仓库
git add -A
git commit -m "初始备份"

# 推送到GitHub
git push -f origin master

# 6. 设置定时备份
echo "第六步：设置定时备份"
read -p "请输入备份的时间（例如，05:15）: " backup_time

# 创建备份脚本
echo "$backup_time * * * * cd $website_path && mysqldump -u$db_username -p$db_password $db_name > $backup_file && git add -A && git commit -m '备份时间：\$(date +\%Y\%m\%d\%H\%M)' && git push -f origin master" > backup.sh

# 添加备份脚本的执行权限
chmod +x backup.sh

# 将备份脚本添加为定时任务
(crontab -l 2>/dev/null; echo "$backup_time * * * * $website_path/backup.sh") | crontab -

echo "设置完成，操作成功！"
