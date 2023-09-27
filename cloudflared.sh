#!/bin/bash
PS3="请输入数字选择: "  # 设置提示符
while true; do
    clear
    echo "=== Cloudflare Tunnel 管理脚本 ==="
    options=("创建隧道" "启动隧道" "删除隧道" "退出")
    select opt in "${options[@]}"; do
        case $REPLY in
            1)
                # 脚本一: 创建隧道
                source <(wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && sudo dpkg -i cloudflared-linux-amd64.deb)
                mkdir -p "$HOME/.cloudflared"
                echo -e "\e[32m请复制以下网址到浏览器中，然后选择域名完成验证，如已验证成功请忽略~\e[0m"
                cloudflared tunnel login
                echo "Cloudflared 验证成功。"
                read -p "请输入隧道名称: " TunnelName
                cloudflared tunnel create "$TunnelName"
                read -p "请输入你的域名: " DomainName
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
                LatestJsonFile=$(ls -t "$HOME/.cloudflared/" | grep -E '\.json$' | head -1)
                mv "$HOME/.cloudflared/$LatestJsonFile" "$HOME/.cloudflared/$TunnelName.json"
                cloudflared tunnel route dns "$TunnelName" "$DomainName"
                apt install screen
                screen -R $TunnelName -d -m cloudflared tunnel --config "$HOME/.cloudflared/$TunnelName.yml" run
                echo "隧道已创建并启动。"
                read -p "按任意键继续..."
                ;;
            2)
cd /usr/local/bin

# 步骤 2: 列出隧道并提取名称
echo "隧道名称"
TunnelIndex=0
declare -a TunnelName
while read -r line; do
    if [[ $TunnelIndex -ge 2 ]]; then
        TunnelIndex=$((TunnelIndex+1))
        TunnelName[TunnelIndex]=$(echo "$line" | awk '{print $2}')
        echo "$TunnelIndex: ${TunnelName[TunnelIndex]}"
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
        # 启动选定的隧道（不指定配置文件，使用默认配置）
        screen -R $TunnelName -d cloudflared tunnel --config "$HOME/.cloudflared/$TunnelName.yml" run
    else
        echo "取消启动隧道 \"$TunnelName\""
    fi
else
    echo "无效的选项，请重新选择。"
fi

# 结束
read -p "按任意键继续..."
exit 0
                ;;
            3)
                # 脚本三: 删除隧道
# 步骤 4: 切换到 Cloudflared 的安装目录（假设安装在 /usr/local/bin/cloudflared）
cd /usr/local/bin

# 步骤 2: 列出隧道并提取名称
echo "隧道名称"
TunnelIndex=0
declare -a TunnelName
while read -r line; do
    if [[ $TunnelIndex -ge 2 ]]; then
        TunnelIndex=$((TunnelIndex+1))
        TunnelName[TunnelIndex]=$(echo "$line" | awk '{print $2}')
        echo "$TunnelIndex: ${TunnelName[TunnelIndex]}"
    else
        TunnelIndex=$((TunnelIndex+1))
    fi
done < <(cloudflared tunnel list)

# 步骤 3: 提示用户选择隧道
read -p "请选择要删除的隧道（输入数字）: " TunnelChoice

# 获取用户选择的隧道名称
SelectedTunnelName=${TunnelName[TunnelChoice]}

# 检查是否存在活动连接
cloudflared tunnel cleanup $SelectedTunnelName

# 删除隧道
read -p "确定要删除隧道 \"$SelectedTunnelName\" 吗？(Y/N): " DeleteTunnel
if [ "$DeleteTunnel" == "Y" ] || [ "$DeleteTunnel" == "y" ]; then
    cloudflared tunnel delete "$SelectedTunnelName"
    echo "隧道 \"$SelectedTunnelName\" 已删除。"
    
    # 删除相关的.json和.yml文件
    rm -f "$HOME/.cloudflared/$SelectedTunnelName.json"
    rm -f "$HOME/.cloudflared/$SelectedTunnelName.yml"
    echo "隧道文件 \"$SelectedTunnelName.json\" 和 \"$SelectedTunnelName.yml\" 已删除。"
else
    echo "取消删除隧道 \"$SelectedTunnelName\""
fi

# 结束
read -p "按任意键继续..."
exit 0

                ;;
            4)
                # 退出脚本
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效的选项，请重新选择。"
                ;;
        esac
        break
    done
done
