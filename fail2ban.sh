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
        echo "21. cloudflare模式"
        echo "------------------------"
        echo "9. 卸载防御程序"
        echo "------------------------"
        echo "0. 退出"
        echo "------------------------"
        read -p "请输入你的选择: " sub_choice

        case $sub_choice in
            1)
                sed -i 's/false/true/g' /etc/fail2ban/jail.d/sshd.local
                systemctl restart fail2ban
                service fail2ban restart
                sleep 1
                fail2ban-client status
                continue
                ;;
            2)
                sed -i 's/true/false/g' /etc/fail2ban/jail.d/sshd.local
                systemctl restart fail2ban
                service fail2ban restart
                sleep 1
                fail2ban-client status
                continue
                ;;
            3)
                sed -i 's/false/true/g' /etc/fail2ban/jail.d/nginx.local
                systemctl restart fail2ban
                service fail2ban restart
                sleep 1
                fail2ban-client status
                continue
                ;;
            4)
                sed -i 's/true/false/g' /etc/fail2ban/jail.d/nginx.local
                systemctl restart fail2ban
                service fail2ban restart
                sleep 1
                fail2ban-client status
                continue
                ;;
            5)
                echo "------------------------"
                fail2ban-client status sshd
                echo "------------------------"
                continue
                ;;
            6)
                echo "------------------------"
                fail2ban-client status fail2ban-nginx-cc
                echo "------------------------"
                fail2ban-client status nginx-bad-request
                echo "------------------------"
                fail2ban-client status nginx-botsearch
                echo "------------------------"
                fail2ban-client status nginx-http-auth
                echo "------------------------"
                fail2ban-client status nginx-limit-req
                echo "------------------------"
                fail2ban-client status php-url-fopen
                echo "------------------------"
                continue
                ;;
            7)
                fail2ban-client status
                continue
                ;;
            8)
                tail -f /var/log/fail2ban.log
                continue
                ;;
            9)
                systemctl disable fail2ban
				systemctl stop fail2ban
				apt remove -y --purge fail2ban
				find / -name "fail2ban" -type d
				rm -rf /etc/fail2ban
                continue
                ;;
            11)
                install nano
                nano /etc/fail2ban/jail.d/nginx.local
                systemctl restart fail2ban
                service fail2ban restart
                continue
                ;;
            21)
                echo "到cf后台右上角我的个人资料，选择左侧API令牌，获取Global API Key"
                echo "https://dash.cloudflare.com/login"
                read -p "输入CF的账号: " cfuser
                read -p "输入CF的Global API Key: " cftoken

                wget -O /www/server/panel/vhost/nginx/default.conf https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/default.conf
				
				mkdir -p /www/server/panel/vhost/cert/default
				
                cd /www/server/panel/vhost/cert/default/
                curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/default_server.crt
				curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/default_server.key
							
                cd /etc/fail2ban/filter.d/
                curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/fail2ban-nginx-cc.conf
				curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/nginx-bad-request.conf
				
				rm -rf /etc/fail2ban/jail.d/*
				
                cd /etc/fail2ban/jail.d/
                curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/nginx.local
				
			    cd /etc/fail2ban/jail.d/
                curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/sshd.local

                cd /etc/fail2ban/action.d/
                curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/fail2ban/cloudflare.conf

                sed -i "s/kejilion@outlook.com/$cfuser/g" /etc/fail2ban/action.d/cloudflare.conf
                sed -i "s/APIKEY00000/$cftoken/g" /etc/fail2ban/action.d/cloudflare.conf

                systemctl restart fail2ban
                service fail2ban restart
                docker restart nginx

                echo "已配置cloudflare模式，可在cf后台，站点-安全性-事件中查看拦截记录"
                continue
                ;;
            0)
                break
                ;;
            *)
                echo "无效的选择,请重试。"
                continue
                ;;
        esac
    done
else
    echo "未检测到 fail2ban 服务,请先安装 fail2ban。"
fi
