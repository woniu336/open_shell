#!/bin/bash

# 查找并停止正在运行的 dns-server 进程
echo "正在查找并停止正在运行的 dns-server 进程..."
pid=$(pgrep -f "dns-server")
if [ -n "$pid" ]; then
    kill -9 $pid
    echo "已停止 dns-server 进程 (PID: $pid)"
else
    echo "未找到运行中的 dns-server 进程"
fi

# 创建 /opt/cfserver 目录
mkdir -p /opt/cfserver

# 下载 dns-server 和 CFGuard-main
echo "正在下载 dns-server 和 CFGuard-main 目录..."
curl -L -o /opt/cfserver/dns-server https://github.com/woniu336/CFGuard/releases/download/v2.0.3/dns-server
curl -L -o /opt/cfserver/CFGuard-main.zip https://github.com/woniu336/CFGuard/archive/refs/heads/main.zip

# 解压 CFGuard-main 并移动 web 目录
echo "解压 CFGuard-main 并移动 web 目录..."
unzip /opt/cfserver/CFGuard-main.zip -d /opt/cfserver/
rm /opt/cfserver/CFGuard-main.zip  # 删除下载的 zip 文件

# 移动 web 目录到 /opt/cfserver
mv /opt/cfserver/CFGuard-main/web /opt/cfserver/

# 赋予 dns-server 执行权限
echo "赋予 dns-server 执行权限..."
chmod +x /opt/cfserver/dns-server

# 进入 /opt/cfserver 目录并后台启动 dns-server，隐藏输出
echo "正在进入 /opt/cfserver 目录并启动 dns-server..."
cd /opt/cfserver

# 后台启动 dns-server，将输出重定向到 /dev/null 并隐藏任何进程状态输出
nohup ./dns-server > /dev/null 2>&1 &

# 提示用户修改令牌并高亮显示
echo -e "\033[1;32m启动成功！请使用以下命令修改令牌：\033[0m"
echo -e "\033[1;33mcd /opt/cfserver && ./dns-server -reset-token\033[0m"
echo -e "\033[1;32m然后启动 dns-server，请运行以下命令：\033[0m"
echo -e "\033[1;33mcd /opt/cfserver && pkill dns-server && nohup ./dns-server > /dev/null 2>&1 &\033[0m"
