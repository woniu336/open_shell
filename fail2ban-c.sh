#!/bin/bash

# 检查是否安装了 fail2ban
if [ -x "$(command -v fail2ban-client)" ] && [ -d "/etc/fail2ban" ]; then
    while true; do
        clear
        echo "服务器防御程序已启动"
        echo "------------------------"
        echo "1. 开启SSH防暴力破解"
        echo "2. 关闭SSH防暴力破解"
        echo "3. 开启网站保护"
        echo "4. 关闭网站保护"
        echo "------------------------"
        echo "5. 查看SSH拦截记录"
        echo "6. 查看网站拦截记录"
        echo "7. 查看防御规则列表"
        echo "8. 查看日志实时监控"
        echo "------------------------"
        echo "11. 配置拦截参数"
        echo "------------------------"
        echo "12. 对接cloudflare防火墙"
        echo "------------------------"
        echo "9. 卸载防御程序"
        echo "------------------------"
        echo "10. 解除被ban的IP"
        echo "------------------------"
        echo "0. 退出"
        echo "------------------------"
        read -p "请输入你的选择: " sub_choice

        case $sub_choice in
            1)
                sed -i 's/false/true/g' /etc/fail2ban/jail.d/sshd.local
                ;;
            2)
                sed -i 's/true/false/g' /etc/fail2ban/jail.d/sshd.local
                ;;
            3)
                sed -i 's/false/true/g' /etc/fail2ban/jail.d/nginx.local
                ;;
            4)
                sed -i 's/true/false/g' /etc/fail2ban/jail.d/nginx.local
                ;;
            5)
                fail2ban-client status sshd
                ;;
            6)
                fail2ban-client status fail2ban-nginx-cc
                fail2ban-client status nginx-bad-request
                fail2ban-client status nginx-botsearch
                fail2ban-client status nginx-http-auth
                fail2ban-client status nginx-limit-req
                fail2ban-client status php-url-fopen
                ;;
            7)
                fail2ban-client status
                ;;
            8)
                tail -f /var/log/fail2ban.log
                ;;
            9)
                systemctl disable fail2ban
                systemctl stop fail2ban
                apt remove -y --purge fail2ban
                find / -name "fail2ban" -type d
                rm -rf /etc/fail2ban
                ;;
            10)
                read -p "请输入被ban的IP地址: " banned_ip
                sudo fail2ban-client unban $banned_ip
                ;;
            11)
                sudo apt install nano
                nano /etc/fail2ban/jail.d/nginx.local
                ;;
            12)
                echo -e "\e[32m到cf后台右上角我的个人资料，选择左侧API令牌，获取Global API Key\e[0m"
                echo -e "\e[32m获取地址: https://dash.cloudflare.com/login\e[0m"
                read -p "输入CF的账号: " cfuser
                read -p "输入CF的Global API Key: " cftoken

                echo -e "\e[33m脚本执行中...\e[0m"
                wget -O /www/server/panel/vhost/nginx/default.conf https://gitee.com/dayu777/open_shell/raw/main/fail2ban/default.conf > /dev/null 2>&1
				
				mkdir -p /www/server/panel/vhost/cert/default
				
                cd /www/server/panel/vhost/cert/default/
                curl -sS -O https://gitee.com/dayu777/open_shell/raw/main/fail2ban/default_server.crt > /dev/null 2>&1
				curl -sS -O https://gitee.com/dayu777/open_shell/raw/main/fail2ban/default_server.key > /dev/null 2>&1
							
                cd /etc/fail2ban/filter.d/
                curl -sS -O https://gitee.com/dayu777/open_shell/raw/main/fail2ban/fail2ban-nginx-cc.conf > /dev/null 2>&1
				curl -sS -O https://gitee.com/dayu777/open_shell/raw/main/fail2ban/nginx-bad-request.conf > /dev/null 2>&1
				
				rm -rf /etc/fail2ban/jail.d/*
				
                cd /etc/fail2ban/jail.d/
                curl -sS -O https://gitee.com/dayu777/open_shell/raw/main/fail2ban/nginx.local > /dev/null 2>&1
				
			    cd /etc/fail2ban/jail.d/
                curl -sS -O https://gitee.com/dayu777/open_shell/raw/main/fail2ban/sshd.local > /dev/null 2>&1

                cd /etc/fail2ban/action.d/
                curl -sS -O https://gitee.com/dayu777/open_shell/raw/main/fail2ban/cloudflare.conf > /dev/null 2>&1

                sed -i "s/kejilion@outlook.com/$cfuser/g" /etc/fail2ban/action.d/cloudflare.conf
                sed -i "s/APIKEY00000/$cftoken/g" /etc/fail2ban/action.d/cloudflare.conf

                systemctl restart fail2ban
                service fail2ban restart
                service nginx restart

                echo -e "\e[32m已对接cloudflare防火墙，可在cf后台，站点-安全性-事件中查看拦截记录\e[0m"
                
                ;;
            0)
                break
                ;;
            *)
                echo "无效的选择,请重试。"
                ;;
        esac

        # 在某些选项执行后不返回主菜单
        if [[ $sub_choice == 1 || $sub_choice == 2 || $sub_choice == 3 || $sub_choice == 4 ]]; then
            systemctl restart fail2ban
            service fail2ban restart
            sleep 1
            fail2ban-client status
        elif [[ $sub_choice == 9 ]]; then
            continue  # 如果选择卸载，则继续循环
        fi

        # 暂停等待用户输入
        read -n 1 -s -r -p "按任意键继续..."
    done
else
    echo "未检测到 fail2ban 服务,请先安装 fail2ban。"
fi
