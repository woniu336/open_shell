#!/bin/bash

# 检查是否已经安装acme.sh
if [ -f ~/.acme.sh/acme.sh ]; then
    echo -e "\e[32macme.sh客户端已经安装。\e[0m"
else
    read -p "acme.sh客户端未安装，请输入您的邮箱地址: " user_email
    # 安装acme.sh
    curl https://get.acme.sh | sh -s email=$user_email
    if [ $? -ne 0 ]; then
        # 如果无法安装，尝试使用wget
        wget -O - https://get.acme.sh | sh -s email=$user_email
        if [ $? -ne 0 ]; then
            echo "无法安装acme.sh，请手动安装。"
            exit 1
        fi
    fi
    # 安装完成后重新加载Bash，并将acme.sh添加到PATH
    source ~/.bashrc
    export PATH="$HOME/.acme.sh:$PATH"
fi

# 添加退出菜单
function exit_menu {
    echo -e "\e[32m感谢使用，再见!\e[0m"
}

# 添加三个菜单项：签发证书、安装证书、强制更新证书
while true; do
    clear
    echo "请选择操作："
    echo "------------------------"
    echo "1. 签发证书"
    echo "------------------------"
    echo "2. 安装证书"
    echo "------------------------"
    echo "3. 强制更新证书"
    echo "------------------------"
    echo "0. 退出"
    echo "------------------------"
    read -p "输入选择的数字: " menu_choice

    case $menu_choice in
        0)
            exit_menu
            exit 0
            ;;
        1)
            # 提示用户选择默认CA
            echo "选择默认CA:"
            echo "1. Let's Encrypt (90 天)"
            echo "2. Buypass (180 天)不支持QQ邮箱"
            echo "3. ZeroSSL (90 天)"
            echo "4. SSL.com (需要注册)"
            echo "5. Google Public CA (90 天)"
            read -p "输入选择的数字 (默认选择ZeroSSL证书): " ca_choice
            case $ca_choice in
                1)
                    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                    ;;
                2)
                    ~/.acme.sh/acme.sh --set-default-ca --server buypass
                    ;;
                3)
                    ~/.acme.sh/acme.sh --set-default-ca --server zerossl
                    ;;
                4)
                    ~/.acme.sh/acme.sh --set-default-ca --server ssl.com
                    ;;
                5)
                    ~/.acme.sh/acme.sh --set-default-ca --server google
                    # Google Public CA选择
                    echo "你选择了Google Public CA。"
                    echo "请按照以下教程获取keyId和b64MacKey："
                    echo "申请google证书教程: https://woniu336.github.io/post/066/"
                    read -p "是否继续? (Y/N): " continue_choice
                    if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
                        echo "用户取消操作。"
                        exit 1
                    fi

                    read -p "请输入谷歌账号邮箱: " user_email
                    read -p "请输入keyId: " keyId
                    read -p "请输入b64MacKey: " b64MacKey

                    # 注册Google Public CA账户
                    ~/.acme.sh/acme.sh --register-account -m $user_email --server google \
                        --eab-kid $keyId \
                        --eab-hmac-key $b64MacKey
                    ;;
                *)
                    ~/.acme.sh/acme.sh --set-default-ca --server zerossl
                    ;;
            esac

            # 提示用户是否签发ECC证书
            read -p "是否希望签发 ECC 证书？(Y/N): " ecc_choice
            if [[ $ecc_choice =~ ^[Yy]$ ]]; then
                keylength="ec-256"
            else
                keylength=""
            fi

            # 提示用户输入域名列表
            read -p "输入域名列表 (多个以空格分隔): " domain_list

            # 将域名列表转换为带有-d选项的字符串
            domains_with_d=""
            for domain in $domain_list; do
                domains_with_d+=" -d $domain"
            done

            # 提示用户输入网站根目录
            read -p "输入网站根目录: " webroot

            # 使用HTTP验证签发证书（包括ECC选项）
            if [ -n "$keylength" ]; then
                ~/.acme.sh/acme.sh --issue $domains_with_d --keylength $keylength --webroot $webroot
            else
                ~/.acme.sh/acme.sh --issue $domains_with_d --webroot $webroot
            fi

            # 检查证书签发是否成功
            success=false
            for domain in $domain_list; do
                if [ -d ~/.acme.sh/"$domain"_ecc ]; then
                    if [ -f ~/.acme.sh/"$domain"_ecc/fullchain.cer ] && [ -f ~/.acme.sh/"$domain"_ecc/"$domain".key ]; then
                        echo "域名: $domain"
                        success=true
                    fi
                fi
            done

            if [ "$success" = true ]; then
                # 设置 ANSI 转义序列以启用绿色文本
                GREEN="\033[1;32m"
                RESET="\033[0m"

                # 域名证书目录，自动添加 "_ecc"
                cert_dir="$HOME/.acme.sh/"

                # 提示用户证书签发成功，并以绿色高亮显示
                echo -e "${GREEN}证书签发成功！${RESET}"
                echo -e "${GREEN}域名证书目录: $cert_dir${RESET}"

            else
                echo "证书签发失败，请检查。"
            fi

            # 更新acme.sh
            echo "更新acme.sh..."
            ~/.acme.sh/acme.sh --upgrade --auto-upgrade
            echo "acme.sh已更新."
            ;;
        2)
            # 安装证书
            # 提示用户输入域名列表
            read -p "输入要安装证书的域名 (多个以空格分隔): " domain_list

            # 将域名列表转换为带有-d选项的字符串
            domains_with_d=""
            for domain in $domain_list; do
                domains_with_d+=" -d $domain"
            done

            read -p "请输入key路径: " key_path
            read -p "请输入fullchain路径: " fullchain_path

            # 安装证书
            ~/.acme.sh/acme.sh --install-cert $domains_with_d \
            --key-file $key_path \
            --fullchain-file $fullchain_path \
            --reloadcmd "service nginx force-reload"
            ;;
        3)
            # 强制更新证书
            echo "请输入您要更新的域名列表 (多个以空格分隔): "
            read domain_list

            # 将域名列表转换为带有-d选项的字符串
            domains_with_d=""
            for domain in $domain_list; do
                domains_with_d+=" -d $domain"
            done

            # 强制更新证书
            echo "正在强制更新以下域名的证书: $domain_list"
            ~/.acme.sh/acme.sh --renew $domains_with_d --force
            echo "证书更新成功!"
            ;;
        *)
            echo "无效的选择。"
            ;;
    esac

    # 等待用户按下任意键继续
    read -n 1 -s -r -p "按任意键继续..."
done
