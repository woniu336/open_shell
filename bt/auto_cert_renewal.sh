# 定义证书存储目录
certs_directory="/home/web/certs/"
days_before_expiry=15

# 遍历所有证书文件
for cert_file in $certs_directory*_cert.pem; do
    yuming=$(basename "$cert_file" "_cert.pem")

    echo "检查证书过期日期： ${yuming}"

    expiration_date=$(openssl x509 -enddate -noout -in "${certs_directory}${yuming}_cert.pem" | cut -d "=" -f 2-)
    echo "过期日期： ${expiration_date}"

    expiration_timestamp=$(date -d "${expiration_date}" +%s)
    current_timestamp=$(date +%s)
    days_until_expiry=$(( ($expiration_timestamp - $current_timestamp) / 86400 ))

    if [ $days_until_expiry -le $days_before_expiry ]; then
        echo "证书将在${days_before_expiry}天内过期，正在进行自动续签。"
        
        docker run --rm -v /etc/letsencrypt/:/etc/letsencrypt certbot/certbot delete --cert-name "$yuming" -n

        docker stop nginx > /dev/null 2>&1

        # 保存现有防火墙规则
        iptables-save > /tmp/iptables.rules.backup
        ip6tables-save > /tmp/ip6tables.rules.backup

        # 只开放 certbot 需要的 80 端口，保持其他安全规则
        # 临时允许 80 端口入站
        iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
        ip6tables -I INPUT 1 -p tcp --dport 80 -j ACCEPT

        # 使用 certbot standalone 模式续签
        docker run --rm -p 80:80 -v /etc/letsencrypt/:/etc/letsencrypt certbot/certbot certonly --standalone -d $yuming --email your@email.com --agree-tos --no-eff-email --force-renewal --key-type ecdsa  

        # 移除临时规则
        iptables -D INPUT -p tcp --dport 80 -j ACCEPT
        ip6tables -D INPUT -p tcp --dport 80 -j ACCEPT

        # 恢复原有防火墙规则（如果需要）
        # iptables-restore < /tmp/iptables.rules.backup
        # ip6tables-restore < /tmp/ip6tables.rules.backup

        mkdir -p /home/web/certs/
        cp /etc/letsencrypt/live/$yuming/fullchain.pem /home/web/certs/${yuming}_cert.pem > /dev/null 2>&1
        cp /etc/letsencrypt/live/$yuming/privkey.pem /home/web/certs/${yuming}_key.pem > /dev/null 2>&1

        openssl rand -out /home/web/certs/ticket12.key 48
        openssl rand -out /home/web/certs/ticket13.key 80
        
        docker start nginx > /dev/null 2>&1

        echo "证书已成功续签。"
    else
        echo "证书仍然有效，距离过期还有 ${days_until_expiry} 天。"
    fi

    echo "--------------------------"
done