#!/bin/bash

# 步骤 1: 下载并安装 cloudflared
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# 步骤 2: 将文件夹路径从 Windows 格式更改为 Linux 格式
mkdir -p "$HOME/.cloudflared"

# 步骤 6: 登录并验证 cloudflared
cloudflared tunnel login

# 提示用户验证成功
echo "Cloudflared 验证成功。"

# 步骤 7: 创建隧道名称
read -p "请输入隧道名称: " TunnelName

# 步骤 8: 运行 cloudflared tunnel create 命令
cloudflared tunnel create "$TunnelName"

# 步骤 9: 提示输入域名
read -p "请输入你的域名: " DomainName

# 步骤 10: 创建 yml 配置文件
read -p "请输入端口号: " PortNumber

cat <<EOF > "$HOME/.cloudflared/$TunnelName.yml"
tunnel: $TunnelName
credentials-file: $HOME/.cloudflared/$TunnelName.json

ingress:
  - hostname: $DomainName
    service: http://localhost:$PortNumber
  - service: http_status:404

logfile: /var/log/cloudflared.log
EOF

# 步骤 11: 重命名最新生成的 JSON 文件为隧道名称
LatestJsonFile=$(ls -t "$HOME/.cloudflared/" | grep -E '\.json$' | head -1)
mv "$HOME/.cloudflared/$LatestJsonFile" "$HOME/.cloudflared/$TunnelName.json"

# 步骤 12: 创建路由
cloudflared tunnel route dns "$TunnelName" "$DomainName"

# 步骤 13: 启动隧道
cloudflared tunnel --config "$HOME/.cloudflared/$TunnelName.yml" run

# 结束
exit 0
