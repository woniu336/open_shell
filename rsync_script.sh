#!/bin/bash
# rsync管理脚本

# 设置本地源路径和远程目标路径
source_dir="/www/wwwroot/test"
remote_user="root"
remote_host="192.168.1.88"
target_dir="/www/wwwroot/rsyc-test"

# 检查本地源路径是否存在
if [ ! -d "$source_dir" ]; then
    echo "本地源路径不存在！"
    exit 1
fi

# 执行rsync命令，将本地源路径同步到远程目标路径
rsync -avzq --delete --exclude=".user.ini" --exclude="66/" -e "ssh -o StrictHostKeyChecking=no -p 22" "$source_dir/" "$remote_user@$remote_host:$target_dir/"


# 检查rsync命令的执行结果
if [ $? -eq 0 ]; then
    echo "rsync同步成功！"
else
    echo "rsync同步失败！"
    exit 1
fi

# 脚本结束
echo "脚本执行完毕！"