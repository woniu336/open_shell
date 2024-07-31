#!/bin/bash

# 定义证书存储目录
certs_directory="/etc/letsencrypt/live/"
days_before_expiry=30

# 检查certbot是否存在且可执行
certbot_path=$(which certbot)
if [ -z "$certbot_path" ]; then
    echo "错误：Certbot 未找到。请确保已安装 Certbot。"
    exit 1
fi

# 检查证书目录是否存在
if [ ! -d "$certs_directory" ]; then
    echo "错误：证书目录 $certs_directory 不存在。"
    exit 1
fi

echo "域名                 过期时间                  剩余天数"
echo "------------------------------------------------------"

total_certs=0
certs_to_renew=0

# 遍历所有证书文件
for cert_dir in $certs_directory*; do
    yuming=$(basename "$cert_dir")
    if [ "$yuming" = "README" ]; then
        continue
    fi

    cert_file="${cert_dir}/fullchain.pem"
    if [ ! -f "$cert_file" ]; then
        continue
    fi

    total_certs=$((total_certs + 1))
    
    expiration_date=$(openssl x509 -enddate -noout -in "${cert_file}" | cut -d "=" -f 2-)
    expiration_timestamp=$(date -d "${expiration_date}" +%s)
    current_timestamp=$(date +%s)
    days_until_expiry=$(( ($expiration_timestamp - $current_timestamp) / 86400 ))

    printf "%-20s %-25s %3d 天\n" "$yuming" "$expiration_date" "$days_until_expiry"

    if [ $days_until_expiry -le $days_before_expiry ]; then
        certs_to_renew=$((certs_to_renew + 1))
        $certbot_path -q renew --cert-name "$yuming" --deploy-hook "systemctl restart lsws"
    fi
done

echo "------------------------------------------------------"
echo "总结：检测到 $total_certs 个证书，$certs_to_renew 个需要续签。"

if [ $certs_to_renew -gt 0 ]; then
    echo "已尝试续签 $certs_to_renew 个证书。请检查上面的输出以确认续签状态。"
fi