#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 函数定义
install_certbot() {
    echo -e "${YELLOW}正在安装Certbot...${NC}"
    apt update -y && apt install -y certbot
    echo -e "${GREEN}Certbot安装完成${NC}"
}

apply_certificate() {
    read -p "请输入所有域名（用空格分隔，第一个将作为主域名）: " domain_list

    # 提取主域名
    yuming=$(echo $domain_list | awk '{print $1}')

   # 赋予权限	
    sudo mkdir -p /etc/letsencrypt/live/${yuming}
	sudo chmod 0755 /etc/letsencrypt/live
	
    # 将域名列表转换为带有-d选项的字符串
    domains_with_d=""
    for domain in $domain_list; do
        domains_with_d+=" -d $domain"
    done

    echo -e "${YELLOW}正在申请证书...${NC}"
    certbot certonly --non-interactive --agree-tos -m demo@gmail.com --webroot -w /www/wwwroot/$yuming $domains_with_d --no-eff-email --key-type ecdsa --force-renewal

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}证书申请成功${NC}"
        move_certificate $yuming
    else
        echo -e "${RED}证书申请失败${NC}"
    fi
}

move_certificate() {
    local yuming=$1
    echo -e "${YELLOW}正在移动证书...${NC}"
    
    # 创建必要的目录
    sudo mkdir -p /www/server/panel/vhost/cert/${yuming}
    
    # 复制证书文件
    if [ -f "/etc/letsencrypt/live/${yuming}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${yuming}/privkey.pem" ]; then
        sudo cp "/etc/letsencrypt/live/${yuming}/fullchain.pem" "/www/server/panel/vhost/cert/${yuming}/fullchain.pem"
        sudo cp "/etc/letsencrypt/live/${yuming}/privkey.pem" "/www/server/panel/vhost/cert/${yuming}/privkey.pem"
        echo -e "${GREEN}证书文件已复制${NC}"
    else
        echo -e "${RED}错误: 无法找到证书文件${NC}"
    fi
    
    # 重启 Nginx
    if sudo /etc/init.d/nginx restart; then
        echo -e "${GREEN}证书移动完成，Nginx已重启${NC}"
    else
        echo -e "${RED}Nginx重启失败${NC}"
    fi
}

modify_cron_job() {
    echo -e "${YELLOW}正在修改续签定时任务...${NC}"
    echo "0 */12 * * * root test -x /usr/bin/certbot -a \! -d /run/systemd/system && perl -e 'sleep int(rand(43200))' && certbot -q renew --deploy-hook \"/etc/init.d/nginx restart\"" > /etc/cron.d/certbot
    
    # 创建新的自动复制证书脚本
    cat > ~/autossl.sh << EOL
#!/bin/bash

# 复制证书到指定目录
for domain in /etc/letsencrypt/live/*/; do
    domain_name=\$(basename "\$domain")
    mkdir -p "/www/server/panel/vhost/cert/\$domain_name"
    cp "/etc/letsencrypt/live/\$domain_name/fullchain.pem" "/www/server/panel/vhost/cert/\$domain_name/fullchain.pem"
    cp "/etc/letsencrypt/live/\$domain_name/privkey.pem" "/www/server/panel/vhost/cert/\$domain_name/privkey.pem"
done

# 重启Nginx
/etc/init.d/nginx restart
EOL

    # 设置脚本权限
    chmod +x ~/autossl.sh

    # 添加新的cron任务
    (crontab -l ; echo "20 2 * * * cd ~ && ./autossl.sh >/dev/null 2>&1") | crontab -

    echo -e "${GREEN}续签定时任务已更新，并添加了自动复制证书的任务${NC}"
}

test_renewal() {
    echo -e "${YELLOW}正在进行续签测试...${NC}"
    sudo certbot renew --dry-run
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}续签测试成功${NC}"
    else
        echo -e "${RED}续签测试失败${NC}"
    fi
}

revoke_certificate() {
    read -p "请输入要吊销证书的域名: " domain
    echo -e "${YELLOW}正在吊销证书...${NC}"
    sudo certbot revoke --cert-name $domain
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}证书吊销成功${NC}"
        # 删除相关文件
        sudo rm -rf /etc/letsencrypt/live/$domain
        sudo rm -rf /etc/letsencrypt/archive/$domain
        sudo rm -rf /etc/letsencrypt/renewal/$domain.conf
        echo -e "${GREEN}相关证书文件已删除${NC}"
    else
        echo -e "${RED}证书吊销失败${NC}"
    fi
}

list_certificates() {
    echo -e "${YELLOW}当前存在的域名证书:${NC}"
    echo -e "${GREEN}+----------------------+---------------------+---------------------+${NC}"
    printf "${GREEN}| %-20s | %-19s | %-19s |${NC}\n" "域名" "颁发日期" "到期日期"
    echo -e "${GREEN}+----------------------+---------------------+---------------------+${NC}"
    
    for cert in /etc/letsencrypt/live/*/cert.pem; do
        domain=$(basename $(dirname $cert))
        expiry=$(openssl x509 -in $cert -noout -enddate | cut -d= -f2)
        start=$(openssl x509 -in $cert -noout -startdate | cut -d= -f2)
        expiry_date=$(date -d "$expiry" '+%Y-%m-%d %H:%M:%S')
        start_date=$(date -d "$start" '+%Y-%m-%d %H:%M:%S')
        printf "| %-20s | %-19s | %-19s |\n" "$domain" "$start_date" "$expiry_date"
    done
    
    echo -e "${GREEN}+----------------------+---------------------+---------------------+${NC}"
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
TECH_BLUE='\033[38;2;0;255;255m'  # 使用科技蓝替换黄色
NC='\033[0m' # No Color

# 主菜单
show_menu() {
    clear
    echo -e "\n${TECH_BLUE}======================================${NC}"
    echo -e "${TECH_BLUE}         SSL证书管理工具${NC}"
    echo -e "${TECH_BLUE}         提醒：仅支持宝塔面板使用${NC}"
    echo -e "${GREEN}         blog: woniu336.github.io${NC}"
    echo -e "${TECH_BLUE}======================================${NC}"
    echo -e "${GREEN}1.${NC} 安装Certbot"
    echo -e "${GREEN}2.${NC} 申请新证书"
    echo -e "${GREEN}3.${NC} 添加定时任务"
    echo -e "${GREEN}4.${NC} 测试证书续签"
    echo -e "${GREEN}5.${NC} 吊销证书"
    echo -e "${GREEN}6.${NC} 列出现有证书"
    echo -e "${RED}7.${NC} 退出"
    echo -e "${TECH_BLUE}======================================${NC}"
}

# 主循环
while true; do
    show_menu
    read -p "$(echo -e ${TECH_BLUE}"请选择操作 (1-7): "${NC})" choice
    
    case $choice in
        1) install_certbot ;;
        2) apply_certificate ;;
        3) modify_cron_job ;;
        4) test_renewal ;;
        5) revoke_certificate ;;
        6) list_certificates ;;
        7) echo -e "${RED}退出程序${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重试${NC}"; sleep 2 ;;
    esac
    
    echo -e "\n${TECH_BLUE}按Enter键返回主菜单...${NC}"
    read
done
