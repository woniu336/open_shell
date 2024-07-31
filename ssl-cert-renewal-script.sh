#!/bin/bash

# 定义证书存储目录
certs_directory="/etc/letsencrypt/live/"
days_before_expiry=30  # 设置在证书到期前30天内都可能触发续签

# 随机等待时间，最长12小时
sleep_time=$((RANDOM % 43200))
sleep $sleep_time

# 检查certbot是否存在且可执行，同时确保不在systemd环境中
if [ ! -x /usr/bin/certbot ] || [ -d /run/systemd/system ]; then
    echo "Certbot不可用或在systemd环境中，退出脚本。"
    exit 1
fi

# 遍历所有证书文件
for cert_dir in $certs_directory*; do
    # 获取域名
    yuming=$(basename "$cert_dir")
    # 忽略 README 目录
    if [ "$yuming" = "README" ]; then
        continue
    fi
    # 输出正在检查的证书信息
    echo "检查证书过期日期： ${yuming}"
    # 获取fullchain.pem文件路径
    cert_file="${cert_dir}/fullchain.pem"
    # 获取证书过期日期
    expiration_date=$(openssl x509 -enddate -noout -in "${cert_file}" | cut -d "=" -f 2-)
    # 输出证书过期日期
    echo "过期日期： ${expiration_date}"
    # 将日期转换为时间戳
    expiration_timestamp=$(date -d "${expiration_date}" +%s)
    current_timestamp=$(date +%s)
    # 计算距离过期还有几天
    days_until_expiry=$(( ($expiration_timestamp - $current_timestamp) / 86400 ))
    # 检查是否需要续签（在满足续签条件的情况下）
    if [ $days_until_expiry -le $days_before_expiry ]; then
        echo "证书将在${days_until_expiry}天后过期，正在进行自动续签。"
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -F
        ip6tables -P INPUT ACCEPT
        ip6tables -P FORWARD ACCEPT
        ip6tables -P OUTPUT ACCEPT
        ip6tables -F
        cd ~
        certbot -q renew --deploy-hook "systemctl restart lsws"
        if [ $? -eq 0 ]; then
            systemctl restart lsws
            echo "证书已成功续签并安装。"
        else
            echo "证书续签失败，请检查日志以获取更多信息。"
        fi
    else
        # 若未满足续签条件，则输出证书仍然有效
        echo "证书仍然有效，距离过期还有 ${days_until_expiry} 天。"
    fi
    # 输出分隔线
    echo "--------------------------"
done
