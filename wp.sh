#!/bin/bash

# 输入WordPress目录路径
read -p "请输入WordPress目录路径: " wordpress_dir

# 输入新的后台地址
read -p "请输入新的后台地址（例如：myadmin，如果已包含 .php 则直接回车）: " new_admin_slug

# 在新的后台地址中添加 .php 扩展名（如果用户输入时没有添加的话）
new_admin_slug_with_extension="$new_admin_slug"
if [[ "$new_admin_slug" != *".php" ]]; then
    new_admin_slug_with_extension="$new_admin_slug.php"
fi

# 检查目录是否存在
if [ ! -d "$wordpress_dir" ]; then
  echo "错误：目录不存在！"
  exit 1
fi

# 备份原始文件
cp "$wordpress_dir/wp-login.php" "$wordpress_dir/wp-login.php.bak"
cp "$wordpress_dir/wp-includes/general-template.php" "$wordpress_dir/wp-includes/general-template.php.bak"

# 输入新的后台地址
mv "$wordpress_dir/wp-login.php" "$wordpress_dir/$new_admin_slug_with_extension"
sed -i "s/wp-login/$new_admin_slug/g" "$wordpress_dir/$new_admin_slug_with_extension"

# 修改 $login_url 变量
sed -i "s/\$login_url = site_url( 'wp-login.php', 'login' );/\$login_url = site_url( 'index.php', 'login' );/g" "$wordpress_dir/wp-includes/general-template.php"

# 修改 general-template.php
sed -i "s/wp-login/$new_admin_slug/g" "$wordpress_dir/wp-includes/general-template.php"


echo "WordPress后台地址修改成功！新地址为 http://域名/$new_admin_slug_with_extension"