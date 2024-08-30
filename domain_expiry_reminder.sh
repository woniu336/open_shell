#!/bin/bash
#监控域名到期发送钉钉消息通知
#原作者：小杨
#博客：https://blog.talimus.eu.org
#更新日期：2024/08/31
#版本：v0.3

#1、监控工具检查
which whois > /dev/null 2> /dev/null
if [ $? -ne 0 ]
then
    apt-get install -y whois
fi
which bc > /dev/null 2> /dev/null
if [ $? -ne 0 ]
then
    apt-get install -y bc
fi
#报警内容
WarnFile=/home/domain/warnfile
>$WarnFile
#全部域名过期时间信息
>/tmp/testdomain.log
#2、域名过期检查 多个域名空格区分
for line in 123.com 234.com 567.org
do
    retry=0
    max_retries=3
    expiry_time=""

    while [ -z "$expiry_time" ] && [ $retry -lt $max_retries ]; do
        # 尝试获取过期日期
        e_d=`whois $line |grep 'Expiry Date' |awk '{print $4}' |cut -d 'T' -f 1`
        if [ -z "$e_d" ]; then
            expiry_time=`whois $line |grep 'Expiration Time' |awk '{print $3}'`
        else
            hms=`whois $line |grep 'Expiry Date' |awk '{print $4}' |cut -d 'T' -f 2`
            e_d_hms=`date -d "$hms" | awk '{print $4}'`
            expiry_time="$e_d"
        fi
        retry=$((retry+1))
        if [ -z "$expiry_time" ]; then
            sleep 3
        fi
    done

    if [ -z "$expiry_time" ]; then
        echo "----------------------------------------" >> $WarnFile
        echo "域名报警信息：" >> $WarnFile
        echo "----------------------------------------" >> $WarnFile
        echo "无法获取域名 $line 的过期日期，请检查域名是否正确或网络连接是否正常。" >> $WarnFile
        echo "----------------------------------------" >> $WarnFile
        echo "" >> $WarnFile
        continue
    fi

    #计算过期时间戳
    e_d_s=`date -d "$expiry_time" +%s`
    echo "域名 $line 的过期时间戳为: ${e_d_s}"
    expiry_date_s=`date -d @${e_d_s}`
    #3、计算今天的时间戳
    today_s=`date +%s`
    #4、计算过期时间戳和今天时间戳的差值，得到剩余天数
    expiry_date=$(($(($e_d_s-$today_s))/(60*60*24)))
    echo "剩余天数: $expiry_date "
    
    expiry_day=`echo $expiry_time | awk '{print $1}'`
    echo "域名:  ${line} 到期日期: ${expiry_time}, 剩余: $expiry_date 天 ！！！！" >> /tmp/testdomain.log
    echo "" >> /tmp/testdomain.log
    
   # 测试时间为30天内过期就发告警
    if [ $expiry_date -lt 30 ]; 
    then
        echo "----------------------------------------" >> $WarnFile
        echo "域名到期提醒：" >> $WarnFile
        echo "----------------------------------------" >> $WarnFile
        echo "域名: ${line}" >> $WarnFile
        echo "到期日期: ${expiry_time}" >> $WarnFile
        echo "剩余天数: $expiry_date 天" >> $WarnFile
        echo "----------------------------------------" >> $WarnFile
        echo "" >> $WarnFile
    fi
	
	# 增加延迟，避免速率限制
    sleep 5
done
## python发报警内容
python3 /home/domain/warnsrc.py /home/domain/warnfile