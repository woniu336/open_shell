#!/bin/bash

# 获取用户输入的 API Key、Email 和 Zone ID
read -p "请输入您的 Cloudflare API Key: " api_key
read -p "请输入您的 Cloudflare 登录邮箱: " email
read -p "请输入您的域名对应的 Zone ID: " zone_id

# 使用 Cloudflare API 获取 DNS 记录信息
echo "正在获取 DNS 记录信息..."
response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
     -H "X-Auth-Email: ${email}" \
     -H "X-Auth-Key: ${api_key}" \
     -H "Content-Type: application/json")

# 检查 API 响应是否成功
success=$(echo "${response}" | jq -r '.success')
if [ "$success" != "true" ]; then
    echo "获取 DNS 记录信息失败，请检查您的输入和网络连接。"
    exit 1
fi

# 解析 DNS 记录信息以获取 DNS 记录 ID 和对应的域名
echo "DNS 记录信息获取成功！"
dns_records=$(echo "${response}" | jq -r '.result[] | "\(.name):\(.id)"')
dns_record_ids=""
while IFS= read -r line; do
    domain=$(echo "$line" | cut -d ":" -f 1)
    id=$(echo "$line" | cut -d ":" -f 2)
    dns_record_ids+="\n    '${domain}': '${id}',"
done <<< "$dns_records"
dns_record_ids="${dns_record_ids#\\n}"
dns_record_ids="${dns_record_ids%,}"  # 移除最后一个逗号

# 获取备用 IP
read -p "请输入备用 IP: " backup_ip

# 获取原始 IP
read -p "请输入原始 IP: " server_ip

# 获取检测端口号
read -p "请输入检测的 TCP 端口号: " port

# 自动生成子域名列表
subdomains=$(echo "${response}" | jq -r '.result[].name')
subdomains_arr=(${subdomains// / })
subdomains_str=$(printf "'%s', " "${subdomains_arr[@]}")
subdomains_str="[${subdomains_str%, }]"

# 更新 Python 脚本中的变量
sed -i "s/api_key = '.*'/api_key = '${api_key}'/" dns_update.py
sed -i "s/email = '.*'/email = '${email}'/" dns_update.py
sed -i "s/zone_id = '.*'/zone_id = '${zone_id}'/" dns_update.py

# 删除旧的 dns_record_ids 定义并添加新的
sed -i '/dns_record_ids = {/,/}/d' dns_update.py
sed -i "/zone_id = '${zone_id}'/a\ " dns_update.py
sed -i "/zone_id = '${zone_id}'/a\dns_record_ids = {${dns_record_ids}}" dns_update.py

sed -i "s/server_ip = '.*'/server_ip = '${server_ip}'/" dns_update.py
sed -i "s/backup_ip = '.*'/backup_ip = '${backup_ip}'/" dns_update.py
sed -i "s/port = .*/port = ${port}/" dns_update.py
sed -i "s|subdomains = \[.*\]|subdomains = ${subdomains_str}|" dns_update.py

echo "成功更新 Python 脚本中的变量。"