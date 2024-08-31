#!/bin/bash
# 检测https证书有效期
# 官方参考文档：https://developers.dingtalk.com/document/app/custom-robot-access
TOKEN=""
dir="/home/domain"
log_file="/home/domain/logssl"

# 确保日志文件存在,并清空旧内容
> "$log_file"

for host in `cat ${dir}/check_ssl.txt` #读取存储了需要监控的域名文件
do
 end_data=`date +%s -d "$(echo |openssl s_client -servername $host  -connect $host:443 2>/dev/null | openssl x509 -noout -dates|awk -F '=' '/notAfter/{print $2}')"`
 #当前时间戳
 
 new_date=$(date +%s) #计算SSL证书截止到现在的过期天数
 
 days=$(expr $(expr $end_data - $new_date) / 86400) #计算SSL正式到期时间和当前时间的差值
 
 if [ $days -lt 7 ]; #当到期时间小于n天时，发钉钉群告警并写入日志
 
 then
    alert_message="告警域名：$host    ssl证书即将到期，剩余：$days 天"
    
    # 写入日志文件(简化格式)
    echo "$alert_message" >> "$log_file"
    
    # 发送钉钉告警
    curl ${TOKEN} -H 'Content-Type: application/json' -X POST --data '{"msgtype":"text","text":{"content":"'"$alert_message"'"} , "at": {"isAtAll": true}}'
    
 fi
 
done