#!/bin/bash

check_domain() {
    local domain=$1
    cert_info=$(echo | timeout 5 openssl s_client -connect $domain:443 -servername $domain 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$cert_info" ]; then
        subject=$(echo "$cert_info" | grep "subject=" | sed 's/subject=//')
        issuer=$(echo "$cert_info" | grep "issuer=" | sed 's/issuer=//')
        
        cn=$(echo "$subject" | grep -o 'CN = [^,]*' | sed 's/CN = //')
        issuer_cn=$(echo "$issuer" | grep -o 'CN = [^,]*' | sed 's/CN = //')
        
        if [[ "$cn" == "$domain" ]] || [[ "$cn" == "*."*"$domain"* ]]; then
            status="✅ 匹配"
        else
            status="❌ 不匹配"
        fi
        
        printf "%-20s %-20s %-15s %s\n" "$domain" "$cn" "$status" "$issuer_cn"
    else
        printf "%-20s %-20s %-15s %s\n" "$domain" "N/A" "❌ 连接失败" "N/A"
    fi
}

echo "=== SNI 检测工具 ==="
echo

while true; do
    echo -n "请输入域名 (输入 'q' 退出): "
    read domain
    
    # 检查是否退出
    if [[ "$domain" == "q" ]] || [[ "$domain" == "quit" ]] || [[ "$domain" == "exit" ]]; then
        echo "再见!"
        break
    fi
    
    # 检查输入是否为空
    if [[ -z "$domain" ]]; then
        echo "域名不能为空，请重新输入"
        continue
    fi
    
    # 显示表头
    echo
    printf "%-20s %-20s %-15s %s\n" "域名" "证书CN" "SNI状态" "颁发者"
    printf "%-20s %-20s %-15s %s\n" "----" "--------" "------" "----"
    
    # 检测域名
    check_domain "$domain"
    echo
done
