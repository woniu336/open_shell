#!/bin/bash

# 步骤 4: 切换到 Cloudflared 的安装目录（假设安装在 /usr/local/bin/cloudflared）
cd /usr/local/bin

# 步骤 2: 列出隧道并提取名称
echo "隧道名称"
TunnelIndex=0
declare -a TunnelName
while read -r line; do
    if [[ $TunnelIndex -ge 2 ]]; then
        TunnelIndex=$((TunnelIndex+1))
        TunnelName[TunnelIndex]=$line
        echo "$TunnelIndex: $line"
    else
        TunnelIndex=$((TunnelIndex+1))
    fi
done < <(cloudflared tunnel list)

# 步骤 3: 提示用户选择隧道
read -p "请选择要启动的隧道（输入数字）: " TunnelChoice

# 步骤 4: 获取选定的隧道名称
if [[ $TunnelChoice -ge 1 ]]; then
    TunnelName="${TunnelName[$TunnelChoice]}"
    StartTunnelPrompt="是否启动隧道 \"$TunnelName\"？（输入Y或N）: "
    read -p "$StartTunnelPrompt" StartTunnel
    if [[ "$StartTunnel" == "Y" || "$StartTunnel" == "y" ]]; then
        # 启动选定的隧道
        cloudflared tunnel --config "$HOME/.cloudflared/$TunnelName.yml" run
    else
        echo "取消启动隧道 \"$TunnelName\""
    fi
else
    echo "无效的选项，请重新选择。"
fi

# 结束
exit 0
