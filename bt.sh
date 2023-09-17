#!/bin/bash

# 一键安装7.7版本
curl -sSO https://raw.githubusercontent.com/woniu336/btpanel-v7.7.0/main/install/install_panel.sh && bash install_panel.sh

# 删除进入面板需要账号密码
rm -f /www/server/panel/data/bind.pl

# 避免官方搞小动作
echo '127.0.0.1 bt.cn' >> /etc/hosts

# 手动解锁宝塔所有付费插件为永不过期
sed -i 's/"endtime": -1/"endtime": 999999999999/g' /www/server/panel/data/plugin.json

# 给plugin.json文件上锁防止自动修复为免费版
chattr +i /www/server/panel/data/plugin.json

# 净化面板
# 下载文件
wget -O /tmp/bt.zip https://github.com/woniu336/btpanel-v7.7.0/raw/main/bt/bt.zip

# 解压文件并合并到目标目录
unzip -uo /tmp/bt.zip -d /www/server/panel/BTPanel/templates/default

# 删除下载的压缩文件
rm /tmp/bt.zip

# 重启宝塔面板
bt restart

echo "操作完成"