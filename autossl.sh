#!/bin/bash

certs_directory="/www/server/panel/vhost/cert/"
days_before_expiry=5

for cert_dir in "$certs_directory"*/; do
    [ "$(basename "$cert_dir")" = "README" ] && continue

    cert_file="$cert_dir/fullchain.pem"
    [ -f "$cert_file" ] || continue

    expiration_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d "=" -f 2-)
    dns_names=$(openssl x509 -in "$cert_file" -noout -text | grep DNS | tr ',' '\n' | cut -d ':' -f 2-)

    [ -z "$dns_names" ] && { echo "No DNS names found in certificate file: $cert_file"; continue; }

    echo -e "\033[32m检查域名： $(echo "$dns_names" | tr '\n' ' ')\033[0m"
    echo -e "\033[32m过期日期： $expiration_date\033[0m"

    expiration_timestamp=$(date -d "$expiration_date" +%s)
    current_timestamp=$(date +%s)
    days_until_expiry=$(( (expiration_timestamp - current_timestamp) / 86400 ))

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

        IFS=$'\n' read -rd '' -a dns_array <<< "$dns_names"
        domains_with_d=''
        for domain in "${dns_array[@]}"; do
            domains_with_d+=" -d $domain"
        done

        ~/.acme.sh/acme.sh --renew $domains_with_d --force
        echo "证书已成功续签。"
    else
        echo "证书仍然有效，距离过期还有 ${days_until_expiry} 天。"
    fi

    echo "--------------------------"
done