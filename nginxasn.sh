#!/bin/bash

# 检查dos2unix是否安装
if ! command -v dos2unix &> /dev/null; then
    echo "正在安装dos2unix..."
    apt-get update &> /dev/null
    apt-get install -y dos2unix &> /dev/null
    if [ $? -ne 0 ]; then
        echo "dos2unix安装失败，请手动安装"
        exit 1
    fi
fi

# 转换当前脚本为Unix格式
dos2unix "$0" &> /dev/null

origfold=$PWD
baseurl="https://asn.ipinfo.app/api/download/nginx/AS"

asnlist="135377
14061
202306
9318
12737"

if [ "$1" == "--delall" ]; then
    for i in $asnlist;
    do
        echo "" >/www/server/nginx/conf/asnblock$i.conf
    done
elif [ "$1" == "-d" ]; then
    echo "" >/www/server/nginx/conf/asnblock$2.conf
    /usr/bin/nginx -s reload
elif [ "$1" == "-a" ]; then
    wget -qO "/www/server/nginx/conf/asnblock$2.conf" "$baseurl$2"
    /usr/bin/nginx -s reload
else
    rm -rf /www/server/nginx/conf/asnblock*.conf
    for i in $asnlist;
    do
        wget -qO "/www/server/nginx/conf/asnblock$i.conf" "$baseurl$i"
        echo "AS$i has been banned!"
    done
fi

/usr/bin/nginx -s reload
cd $origfold
exit 0