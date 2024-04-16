#!/bin/bash
clear
# 绿色高亮提示函数
# 空行
echo
green_highlight() {
    echo -e "\033[32m$1\033[0m"
}

# 提示：此脚本仅适用于宝塔面板与cloudflare DNS验证
green_highlight "此脚本仅适用于宝塔面板与cloudflare DNS验证"
while true; do
    # 显示操作列表
    # 空行
echo
    echo "请选择要执行的操作:"
    echo
    echo "1. 安装 acme.sh"
    echo "2. 设置 cloudflare DNS 验证"
    echo "3. 选择默认证书"
    echo "4. 生成并安装证书"
    echo "5. 强制更新证书"
    echo "0. 退出脚本"
echo
    # 读取用户输入
    read -p "请输入选项编号: " choice
    
    # 根据用户选择执行相应操作
    case $choice in
        1)
            # 安装 acme.sh
            echo "请输入您的邮箱:"
            read email
            echo "正在安装 acme.sh..."
            curl https://get.acme.sh | sh -s email="$email"
            echo "acme.sh 安装成功!"
            ;;
        2)
            # 设置 DNS 验证
            echo "请输入 CloudFlare 的 API 密钥:"
            read CF_Key
            echo "请输入 CloudFlare 的登录邮箱:"
            read CF_Email
            export CF_Key="$CF_Key"
            export CF_Email="$CF_Email"
            echo "CloudFlare DNS 自动验证已设置完成。"
            ;;
        3)
            # 选择默认证书
            echo
            echo "请选择默认证书CA:"
            echo
            echo "1. Let's Encrypt (90 天)"
            echo
            echo "2. Buypass (180 天)"
            echo
            echo "3. ZeroSSL (90 天)"
            echo
            echo "4. Google Public CA (90 天)"
            echo
            read -p "请输入选项编号: " ca_choice

            case $ca_choice in
                1)
                    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                    echo -e "\033[32m默认证书服务器已设置为 Let's Encrypt.\033[0m"
                    ;;
                2)
                    ~/.acme.sh/acme.sh --set-default-ca --server buypass
                    echo -e "\033[32m默认证书服务器已设置为 Buypass.\033[0m"
                    ;;
                3)
                    ~/.acme.sh/acme.sh --set-default-ca --server zerossl
                    echo -e "\033[32m默认证书服务器已设置为 ZeroSSL.\033[0m"
                    ;;
                4)
                    # Google Public CA
                    ~/.acme.sh/acme.sh --set-default-ca --server google
                    echo "你选择了 Google Public CA"
                    echo "请按照以下教程获取keyId和b64MacKey："
                    echo -e "\033[32m申请google证书教程: https://woniu336.github.io/post/066/ \033[0m"
                    read -p "是否继续? (Y/N): " continue_choice
                    if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
                        echo "用户取消操作。"
                        exit 1
                    fi

                    read -p "请输入keyId: " keyId
                    read -p "请输入b64MacKey: " b64MacKey

                    # 注册Google Public CA账户
                   ~/.acme.sh/acme.sh --register-account --server google \
                        --eab-kid $keyId \
                        --eab-hmac-key $b64MacKey
                    echo -e "\033[32mGoogle Public CA 默认证书服务器设置完成。\033[0m"
                    ;;
                *)
                    echo "无效的选项，请重新运行脚本并选择正确的默认证书服务器."
                    ;;
            esac
            ;;
        4)
            # 提示用户输入网站名
            read -p "请输入网站名: " site_name

            # 创建证书安装路径
            cert_path="/www/server/panel/vhost/cert/$site_name"
            mkdir -p "$cert_path"

            # 提示用户输入域名列表
            read -p "请输入您的域名列表 (多个以空格分隔): " domain_list

            # 将域名列表转换为带有-d选项的字符串
            domains_with_d=""
            for domain in $domain_list; do
                domains_with_d+=" -d $domain"
            done

            # 生成证书
            echo "正在为以下域名生成证书: $domain_list"
            ~/.acme.sh/acme.sh --issue --dns dns_cf $domains_with_d
            echo "证书生成成功!"

            # 安装证书
            echo "正在为以下网站安装证书: $site_name"
            ~/.acme.sh/acme.sh --install-cert $domains_with_d \
                --key-file "$cert_path/privkey.pem" \
                --fullchain-file "$cert_path/fullchain.pem" \
                --reloadcmd "service nginx force-reload"
            echo "证书安装成功!"
            ;;
        5)
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

        0)
            # 退出脚本
            echo "脚本已退出."
            exit 0
            ;;
        *)
            echo "无效的选项，请重新运行脚本并选择正确的操作."
            ;;
    esac
done
