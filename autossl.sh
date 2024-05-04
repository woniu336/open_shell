# 定义证书存储目录
certs_directory="/www/server/panel/vhost/cert/"

days_before_expiry=5  # 设置在证书到期前几天触发续签

# 遍历所有证书文件
for cert_dir in ${certs_directory}*; do
    # 忽略 README 目录
    if [ $(basename "$cert_dir") = "README" ]; then
        continue
    fi

    # 获取fullchain.pem文件路径
    cert_file="${cert_dir}/fullchain.pem"

    if [ -f "$cert_file" ]; then
        # 获取证书过期日期
        expiration_date=$(openssl x509 -enddate -noout -in "${cert_file}" | cut -d "=" -f 2-)

        # 使用openssl从证书中获取所有DNS名称
        dns_names=$(openssl x509 -in "${cert_file}" -noout -text | grep DNS | tr ',' '\n' | cut -d ':' -f 2)

        if [ -z "$dns_names" ]; then
            echo "No DNS names found in certificate file: ${cert_file}"
            continue
        fi

        # 打印检查的DNS名称
        # 输出DNS名称，将换行替换为空格
        echo -e "\033[32m检查域名： `echo ${dns_names} | tr '\n' ' '`\033[0m"

        # 输出证书过期日期
        echo -e "\033[32m过期日期： ${expiration_date}\033[0m"

        # 将日期转换为时间戳
        expiration_timestamp=$(date -d "${expiration_date}" +%s)
        current_timestamp=$(date +%s)

        # 计算距离过期还有几天
        days_until_expiry=$(( ($expiration_timestamp - $current_timestamp) / 86400 ))


        # 重启nginx
          sudo killall nginx
          sudo service nginx start

        # 检查是否需要续签（在满足续签条件的情况下）
        if [ $days_until_expiry -le $days_before_expiry ]; then
            echo "证书将在${days_before_expiry}天内过期，正在进行自动续签。"

            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            iptables -F

            ip6tables -P INPUT ACCEPT
            ip6tables -P FORWARD ACCEPT
            ip6tables -P OUTPUT ACCEPT
            ip6tables -F

            # 遍历每个域名并续签证书
            IFS=$'\n' read -rd '' -a dns_array <<< "$dns_names" 

            domains_with_d=''
            for domain in "${dns_array[@]}"; do
                domains_with_d+=" -d $domain"
            done

            # 续签证书
            ~/.acme.sh/acme.sh --issue --dns dns_cf $domains_with_d --force

            ~/.acme.sh/acme.sh --renew $domains_with_d --force

            echo "证书已成功续签。"
        else
            # 若未满足续签条件，则输出证书仍然有效
            echo "证书仍然有效，距离过期还有 ${days_until_expiry} 天。"
        fi

        # 输出分隔线
        echo "--------------------------"
    else
        echo -e "\033[33m跳过不包含有效证书的目录 ${cert_file}\033[0m"
    fi
done