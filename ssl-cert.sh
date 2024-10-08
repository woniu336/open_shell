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

    # 检查 webroot 目录
    if [ ! -d "/www/wwwroot/$yuming" ]; then
        echo -e "${RED}错误: Webroot 目录 /www/wwwroot/$yuming 不存在${NC}"
        return 1
    fi

    # 将域名列表转换为带有-d选项的字符串
    domains_with_d=""
    for domain in $domain_list; do
        domains_with_d+=" -d $domain"
    done

    echo -e "${YELLOW}正在申请证书...${NC}"
    sudo certbot certonly --non-interactive --agree-tos -m demo@gmail.com --webroot -w /www/wwwroot/$yuming $domains_with_d --no-eff-email --key-type ecdsa --force-renewal

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}证书申请成功${NC}"
        move_certificate $yuming
    else
        echo -e "${RED}证书申请失败${NC}"
        echo -e "${YELLOW}正在检查 Certbot 日志...${NC}"
        sudo tail -n 50 /var/log/letsencrypt/letsencrypt.log
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
    cat > ~/autossl.sh << 'EOL'
#!/bin/bash

# 复制证书到指定目录
for domain in /etc/letsencrypt/archive/*/; do
    domain_name=$(basename "$domain")
    
    # 检查 /etc/letsencrypt/live/${domain_name} 是否存在
    if [ -d "/etc/letsencrypt/live/${domain_name}" ]; then
        echo "目录 /etc/letsencrypt/live/${domain_name} 已存在。"
    else
        # 如果不存在，创建目录并创建软链接
        mkdir -p "/etc/letsencrypt/live/${domain_name}"
        ln -s "/etc/letsencrypt/archive/${domain_name}/fullchain1.pem" "/etc/letsencrypt/live/${domain_name}/fullchain.pem"
        ln -s "/etc/letsencrypt/archive/${domain_name}/privkey1.pem" "/etc/letsencrypt/live/${domain_name}/privkey.pem"
        ln -s "/etc/letsencrypt/archive/${domain_name}/cert1.pem" "/etc/letsencrypt/live/${domain_name}/cert.pem"
        ln -s "/etc/letsencrypt/archive/${domain_name}/chain1.pem" "/etc/letsencrypt/live/${domain_name}/chain.pem"
        echo "已为域名 ${domain_name} 创建软链接。"
    fi

    mkdir -p "/www/server/panel/vhost/cert/$domain_name"
    cp "/etc/letsencrypt/live/$domain_name/fullchain.pem" "/www/server/panel/vhost/cert/$domain_name/fullchain.pem"
    cp "/etc/letsencrypt/live/$domain_name/privkey.pem" "/www/server/panel/vhost/cert/$domain_name/privkey.pem"
done

# 重启Nginx并捕获输出
restart_output=$(/etc/init.d/nginx restart 2>&1)

# 提取警告信息
warnings=$(echo "$restart_output" | grep -E 'nginx: \[warn\]')

# 如果有警告信息，则输出简洁提醒
if [ -n "$warnings" ]; then
    echo "Nginx 重启时检测到警告信息，请检查配置。"
    echo "$warnings"
else
    echo "Nginx 重启成功，未检测到警告信息。"
fi
EOL

    # 设置脚本权限
    chmod +x ~/autossl.sh

    # 检查并添加新的cron任务
    if ! crontab -l | grep -q "20 2 \* \* \* cd ~ && ./autossl.sh >/dev/null 2>&1"; then
        (crontab -l ; echo "20 2 * * * cd ~ && ./autossl.sh >/dev/null 2>&1") | crontab -
        echo -e "${GREEN}定时任务添加成功${NC}"
    else
        echo -e "${GREEN}定时任务已存在，跳过添加${NC}"
    fi
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

list_certificate_names() {
    echo -e "${YELLOW}当前存在的证书名称:${NC}"
    echo -e "${GREEN}+----------------------+${NC}"
    printf "${GREEN}| %-20s |${NC}\n" "证书名称"
    echo -e "${GREEN}+----------------------+${NC}"
    
    for cert in /etc/letsencrypt/live/*; do
        cert_name=$(basename $cert)
        if [ "$cert_name" != "README" ]; then
            printf "| %-20s |\n" "$cert_name"
        fi
    done
    
    echo -e "${GREEN}+----------------------+${NC}"
}

manual_renewal() {
    list_certificate_names
    read -p "请输入要手动续签的证书名称: " cert_name
    read -p "请输入站点目录 (例如 /www/wwwroot/example.com): " webroot_path

    read -p "是否需要强制续签证书？(y/n): " force_renew
    if [[ "$force_renew" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}正在强制续签证书...${NC}"
        sudo certbot renew --cert-name $cert_name --key-type ecdsa --webroot-path $webroot_path --force-renewal --reuse-key
        status=$?
    else
        echo -e "${YELLOW}正在手动续签证书...${NC}"
        sudo certbot renew --cert-name $cert_name --key-type ecdsa --webroot-path $webroot_path --reuse-key
        status=$?
    fi

    if [ $status -eq 0 ]; then
        echo -e "${GREEN}手动续签成功${NC}"

        # 获取最新的证书文件后缀
        latest_cert=$(ls -v "/etc/letsencrypt/archive/${cert_name}/cert"* | tail -n 1)
        latest_chain=$(ls -v "/etc/letsencrypt/archive/${cert_name}/chain"* | tail -n 1)
        latest_fullchain=$(ls -v "/etc/letsencrypt/archive/${cert_name}/fullchain"* | tail -n 1)
        latest_privkey=$(ls -v "/etc/letsencrypt/archive/${cert_name}/privkey"* | tail -n 1)

        # 重命名最新的证书文件
        sudo mv "$latest_cert" "/etc/letsencrypt/archive/${cert_name}/cert1.pem"
        sudo mv "$latest_chain" "/etc/letsencrypt/archive/${cert_name}/chain1.pem"
        sudo mv "$latest_fullchain" "/etc/letsencrypt/archive/${cert_name}/fullchain1.pem"
        sudo mv "$latest_privkey" "/etc/letsencrypt/archive/${cert_name}/privkey1.pem"

        # 更新符号链接
        sudo ln -sf "/etc/letsencrypt/archive/${cert_name}/cert1.pem" "/etc/letsencrypt/live/${cert_name}/cert.pem"
        sudo ln -sf "/etc/letsencrypt/archive/${cert_name}/chain1.pem" "/etc/letsencrypt/live/${cert_name}/chain.pem"
        sudo ln -sf "/etc/letsencrypt/archive/${cert_name}/fullchain1.pem" "/etc/letsencrypt/live/${cert_name}/fullchain.pem"
        sudo ln -sf "/etc/letsencrypt/archive/${cert_name}/privkey1.pem" "/etc/letsencrypt/live/${cert_name}/privkey.pem"

        # 复制证书文件
        if [ -f "/etc/letsencrypt/live/${cert_name}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${cert_name}/privkey.pem" ]; then
            sudo cp "/etc/letsencrypt/live/${cert_name}/fullchain.pem" "/www/server/panel/vhost/cert/${cert_name}/fullchain.pem"
            sudo cp "/etc/letsencrypt/live/${cert_name}/privkey.pem" "/www/server/panel/vhost/cert/${cert_name}/privkey.pem"
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
    else
        echo -e "${RED}手动续签失败${NC}"
    fi
}

test_renewal_manual() {
    list_certificate_names
    read -p "请输入要测试续签的证书名称: " cert_name
    read -p "请输入站点目录 (例如 /www/wwwroot/example.com): " webroot_path

    echo -e "${YELLOW}正在进行续签测试...${NC}"
    sudo certbot renew --cert-name $cert_name --key-type ecdsa --webroot-path $webroot_path --dry-run
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}续签测试成功${NC}"
    else
        echo -e "${RED}续签测试失败${NC}"
    fi
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
    echo -e "${GREEN}2.${NC} ${RED}申请新证书 ★${NC}"
    echo -e "${GREEN}3.${NC} 添加定时任务"
    echo -e "${GREEN}4.${NC} 全部续签测试"
    echo -e "${GREEN}5.${NC} 吊销证书"
    echo -e "${GREEN}6.${NC} 列出现有证书"
    echo -e "${GREEN}7.${NC} ${RED}手动续签证书 ★${NC}"
    echo -e "${GREEN}8.${NC} 续签有效测试"
    echo -e "${RED}0.${NC} 退出"
    echo -e "${TECH_BLUE}======================================${NC}"
}
# 主循环
while true; do
    show_menu
    read -p "$(echo -e ${TECH_BLUE}"请选择操作 (1-9): "${NC})" choice
    
    case $choice in
        1) install_certbot ;;
        2) apply_certificate ;;
        3) modify_cron_job ;;
        4) test_renewal ;;
        5) revoke_certificate ;;
        6) list_certificates ;;
        7) manual_renewal ;;
        8) test_renewal_manual ;;
        0) echo -e "${RED}退出程序${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重试${NC}"; sleep 2 ;;
    esac
    
    echo -e "\n${TECH_BLUE}按Enter键返回主菜单...${NC}"
    read
done