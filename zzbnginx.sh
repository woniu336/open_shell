#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

public_file=/www/server/panel/install/public.sh
. $public_file
publicFileMd5=$(md5sum ${public_file} 2>/dev/null|awk '{print $1}')
md5check="3a4b75cd48e16fcdf2945e41598da6bd"
if [ "${publicFileMd5}" != "${md5check}"  ] && [ -z "${NODE_URL}" ]; then
	wget -O Tpublic.sh https://download.bt.cn/install/public.sh -T 20;
	publicFileMd5=$(md5sum Tpublic.sh 2>/dev/null|awk '{print $1}')
	if [ "${publicFileMd5}" == "${md5check}"  ]; then
		\cp -rpa Tpublic.sh $public_file
	fi
	rm -f Tpublic.sh
	. $public_file
fi

download_Url=$NODE_URL

tengine='3.1.0'
nginx_108='1.8.1'
nginx_112='1.12.2'
nginx_114='1.14.2'
nginx_115='1.15.10'
nginx_116='1.16.1'
nginx_117='1.17.10'
nginx_118='1.18.0'
nginx_119='1.19.8'
nginx_120='1.20.2'
nginx_121='1.21.4'
nginx_122='1.22.1'
nginx_123='1.23.4'
nginx_124='1.24.0'
nginx_125='1.25.5'
nginx_126='1.26.1'
openresty='1.25.3.1'

Root_Path=$(cat /var/bt_setupPath.conf)
Setup_Path=$Root_Path/server/nginx
run_path="/root"
Is_64bit=$(getconf LONG_BIT)

ARM_CHECK=$(uname -a | grep -E 'aarch64|arm|ARM')
if [ "$2" == "1.24" ];then
    ARM_CHECK=""
    JEM_CHECK="disable"
fi
LUAJIT_VER="2.0.4"
LUAJIT_INC_PATH="luajit-2.0"

if [ "${ARM_CHECK}" ]; then
    LUAJIT_VER="2.1.0-beta3"
    LUAJIT_INC_PATH="luajit-2.1"
fi

loongarch64Check=$(uname -a | grep loongarch64)
if [ "${loongarch64Check}" ]; then
    wget -O nginx.sh ${download_Url}/install/0/loongarch64/nginx.sh && sh nginx.sh $1 $2
    exit
fi

# if [ "$2" == "1.25" ];then
#     ulimit -n 10240
#     wget -O nginx.sh ${download_Url}/install/0/nginx5.sh 
#     . nginx.sh $1 $2
#     exit
# fi

#HUAWEI_CLOUD_EULER=$(cat /etc/os-release |grep '"Huawei Cloud EulerOS 1')
#EULER_OS=$(cat /etc/os-release |grep "EulerOS 2.0 ")
#if [ "${HUAWEI_CLOUD_EULER}" ] || [ "${EULER_OS}" ];then
#        wget -O nginx.sh ${download_Url}/install/1/nginx.sh && sh nginx.sh $1 $2
#        exit
#fi

if [ -z "${cpuCore}" ]; then
    cpuCore="1"
fi

Error_Send(){
    MIN_O=$(date +%M)
    if [ $((MIN_O % 2)) -eq 0 ]; then
        exit 1
    fi
    if [ ! -f "/tmp/nginx_i.pl" ];then
        touch /tmp/nginx_i.pl
        TIME=$(date "+%Y-%m-%d %H:%M:%S")
        P_VERSION=$(cat /www/server/panel/class/common.py|grep g.version|grep -oE 8.0.[0-9]+)
        ls /etc/init.d/ | xargs -n 5 | pr -t -5 > /tmp/nginx_err.pl
        cat /tmp/pack_i.pl >> /tmp/nginx_err.pl
        cat /tmp/gd_i.pl >> /tmp/nginx_err.pl
        tail -n 15 /tmp/nginx_config.pl /tmp/nginx_make.pl /tmp/nginx_install.pl >> /tmp/nginx_err.pl
        echo  Bit:${SYS_BIT} Mem:${MEM_TOTAL}M Core:${CPU_INFO} gcc:${GCC_VER} cmake:${CMAKE_VER} >> /tmp/nginx_err.pl
        echo ${SYS_VERSION} ${SYS_INFO} >> /tmp/nginx_err.pl
        echo "$nginxVersion install Failed" >> /tmp/nginx_err.pl
        ERR_MSG=$(cat /tmp/nginx_err.pl)
        rm -f /tmp/nginx_config.pl /tmp/nginx_make.pl /tmp/nginx_install.pl /tmp/nginx_err.pl /tmp/pack_i.pl /tmp/gd_i.pl
        curl --request POST \
          --url "http://api.bt.cn/bt_error/index.php" \
          --data "UID=89045" \
          --data "PANEL_VERSION=${P_VERSION}"\
          --data "REQUEST_DATE=${TIME}" \
          --data "OS_VERSION=${SYS_VERSION}" \
          --data "REMOTE_ADDR=192.168.168.1641" \
          --data "REQUEST_URI=nginx" \
          --data "USER_AGENT=${SYS_INFO}" \
          --data "ERROR_INFO=${ERR_MSG}" \
          --data "PACK_TIME=${TIME}" \
          --data "TYPE=3"
    fi
    exit 1
}
System_Lib() {
    if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
        Pack="gcc gcc-c++ curl curl-devel libtermcap-devel ncurses-devel libevent-devel readline-devel libuuid-devel gd-devel libxml2-devel libxslt-devel"
        ${PM} install ${Pack} -y
        yum install zlib-devel -y
        yum -y reinstall gcc gcc-c++ autoconf automake
        yum reinstall gd gd-devel -y 2>&1 >> /tmp/pack_i.pl
        ls /usr/include/gd.h /usr/lib64/libgd.so.3  2>&1 |tee /tmp/gd_i.pl
        wget -O fix_install.sh $download_Url/tools/fix_install.sh
        nohup bash fix_install.sh > /www/server/panel/install/fix.log 2>&1 &
    elif [ "${PM}" == "apt-get" ]; then
        apt-get update
        LIBCURL_VER=$(dpkg -l | grep libx11-6 | awk '{print $3}')
        if [ "${LIBCURL_VER}" == "2:1.6.9-2ubuntu1.3" ]; then
            apt remove libx11* -y
            apt install libx11-6 libx11-dev libx11-data -y
        fi
        apt-get update -y
        Pack="gcc g++ libgd3 libgd-dev libevent-dev libncurses5-dev libreadline-dev uuid-dev"
        ${PM} install ${Pack} -y
        apt-get install libxslt1-dev -y 2>&1 >> /tmp/pack_i.pl
        apt-get install libgd-dev -y 2>&1 >> /tmp/pack_i.pl
        apt-get install libxml2-dev -y 2>&1 >> /tmp/pack_i.pl
        apt-get install zlib1g-dev -y 
    fi

}

Service_Add() {
    if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
        chkconfig --add nginx
        chkconfig --level 2345 nginx on
    elif [ "${PM}" == "apt-get" ]; then
        update-rc.d nginx defaults
    fi
	if [ "$?" == "127" ];then
		wget -O /usr/lib/systemd/system/nginx.service ${download_Url}/init/systemd/nginx.service
		systemctl enable nginx.service
	fi
}
Service_Del() {
    if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
        chkconfig --del nginx
        chkconfig --level 2345 nginx off
    elif [ "${PM}" == "apt-get" ]; then
        update-rc.d nginx remove
    fi
}
Set_Time() {
    BASH_DATE=$(stat nginx.sh | grep Modify | awk '{print $2}' | tr -d '-')
    SYS_DATE=$(date +%Y%m%d)
    [ "${SYS_DATE}" -lt "${BASH_DATE}" ] && date -s "$(curl https://www.bt.cn//api/index/get_date)"
}
Install_Jemalloc() {
    if [ ! -f '/usr/local/lib/libjemalloc.so' ]; then
        wget -O jemalloc-5.0.1.tar.bz2 ${download_Url}/src/jemalloc-5.0.1.tar.bz2
        tar -xvf jemalloc-5.0.1.tar.bz2
        cd jemalloc-5.0.1
        ./configure
        make && make install
        ldconfig
        cd ..
        rm -rf jemalloc*
    fi
}
Install_LuaJIT2(){
    LUAJIT_INC_PATH="luajit-2.1"
    wget -c -O luajit2-2.1-20230410.zip ${download_Url}/src/luajit2-2.1-20230410.zip
    unzip -o luajit2-2.1-20230410.zip
    cd luajit2-2.1-20230410
    make -j${cpuCore}
    make install
    cd .. 
    rm -rf luajit2-2.1-20230410*
    ln -sf /usr/local/lib/libluajit-5.1.so.2 /usr/local/lib64/libluajit-5.1.so.2
    LD_SO_CHECK=$(cat /etc/ld.so.conf|grep /usr/local/lib)
    if [ -z "${LD_SO_CHECK}" ];then
         echo "/usr/local/lib" >>/etc/ld.so.conf
    fi
    ldconfig
}
Install_LuaJIT() {
    if [ "${version}" == "1.23" ] || [ "${version}" == "1.24" ] || [ "${version}" == "tengine" ] || [ "${version}" == "1.25" ] || [ "${version}" == "1.26" ];then
        Install_LuaJIT2
        return
    fi
    OEPN_LUAJIT=$(cat /usr/local/include/luajit-2.1/luajit.h|grep 2022)
    if [ ! -f '/usr/local/lib/libluajit-5.1.so' ] || [ ! -f "/usr/local/include/${LUAJIT_INC_PATH}/luajit.h" ] || [ "${OEPN_LUAJIT}" ]; then
        wget -c -O LuaJIT-${LUAJIT_VER}.tar.gz ${download_Url}/install/src/LuaJIT-${LUAJIT_VER}.tar.gz -T 10
        tar xvf LuaJIT-${LUAJIT_VER}.tar.gz
        cd LuaJIT-${LUAJIT_VER}
        make linux
        make install
        cd ..
        rm -rf LuaJIT-*
        export LUAJIT_LIB=/usr/local/lib
        export LUAJIT_INC=/usr/local/include/${LUAJIT_INC_PATH}/
        ln -sf /usr/local/lib/libluajit-5.1.so.2 /usr/local/lib64/libluajit-5.1.so.2
        LD_SO_CHECK=$(cat /etc/ld.so.conf|grep /usr/local/lib)
        if [ -z "${LD_SO_CHECK}" ];then
             echo "/usr/local/lib" >>/etc/ld.so.conf
        fi
        ldconfig
    fi
}
Install_cjson() {
    if [ ! -f /usr/local/lib/lua/5.1/cjson.so ]; then
        wget -O lua-cjson-2.1.0.tar.gz $download_Url/install/src/lua-cjson-2.1.0.tar.gz -T 20
        tar xvf lua-cjson-2.1.0.tar.gz
        rm -f lua-cjson-2.1.0.tar.gz
        cd lua-cjson-2.1.0
        make
        make install
        cd ..
        rm -rf lua-cjson-2.1.0
    fi
}
Download_Src() {
    mkdir -p ${Setup_Path}
    cd ${Setup_Path}
    rm -rf ${Setup_Path}/src
    if [ "${version}" == "tengine" ] || [ "${version}" == "openresty" ]; then
        wget -O ${Setup_Path}/src.tar.gz ${download_Url}/src/${version}-${nginxVersion}.tar.gz -T20
        tar -xvf src.tar.gz
        mv ${version}-${nginxVersion} src
    else
        wget -O ${Setup_Path}/src.tar.gz ${download_Url}/src/nginx-${nginxVersion}.tar.gz -T20
        tar -xvf src.tar.gz
        tar -xvf src.tar.gz
        mv nginx-${nginxVersion} src
    fi

    cd src

if [ -z "${GMSSL}" ]; then
	cp -r /www/server/openssl .
	cd openssl
	./config
	make
	cd ..
else
        wget -O GmSSL-master.zip ${download_Url}/src/GmSSL-master.zip
        unzip GmSSL-master.zip
        mv GmSSL-master openssl
        rm -f GmSSL-master.zip
    fi

    pcre_version="8.43"
    wget -O pcre-$pcre_version.tar.gz ${download_Url}/src/pcre-$pcre_version.tar.gz
    tar zxf pcre-$pcre_version.tar.gz

    wget -O ngx_cache_purge.tar.gz ${download_Url}/src/ngx_cache_purge-2.3.tar.gz
    tar -zxvf ngx_cache_purge.tar.gz
    mv ngx_cache_purge-2.3 ngx_cache_purge
    rm -f ngx_cache_purge.tar.gz

    wget -O nginx-sticky-module.zip ${download_Url}/src/nginx-sticky-module.zip
    unzip -o nginx-sticky-module.zip
    rm -f nginx-sticky-module.zip

    wget -O nginx-http-concat.zip ${download_Url}/src/nginx-http-concat-1.2.2.zip
    unzip -o nginx-http-concat.zip
    mv nginx-http-concat-1.2.2 nginx-http-concat
    rm -f nginx-http-concat.zip

    #lua_nginx_module
    LuaModVer="0.10.13"
    if [ "${version}" == "1.23" ] || [ "${version}" == "1.24" ] || [ "${version}" == "tengine" ] ||  [ "${version}" == "1.25" ] || [ "${version}" == "1.26" ];then
        LuaModVer="0.10.24"
    fi
    wget -c -O lua-nginx-module-${LuaModVer}.zip ${download_Url}/src/lua-nginx-module-${LuaModVer}.zip
    unzip -o lua-nginx-module-${LuaModVer}.zip
    mv lua-nginx-module-${LuaModVer} lua_nginx_module
    rm -f lua-nginx-module-${LuaModVer}.zip

    #ngx_devel_kit
    NgxDevelKitVer="0.3.1"
    wget -c -O ngx_devel_kit-${NgxDevelKitVer}.zip ${download_Url}/src/ngx_devel_kit-${NgxDevelKitVer}.zip
    unzip -o ngx_devel_kit-${NgxDevelKitVer}.zip
    mv ngx_devel_kit-${NgxDevelKitVer} ngx_devel_kit
    rm -f ngx_devel_kit-${NgxDevelKitVer}.zip

    #nginx-dav-ext-module
    NgxDavVer="3.0.0"
    wget -c -O nginx-dav-ext-module-${NgxDavVer}.tar.gz ${download_Url}/src/nginx-dav-ext-module-${NgxDavVer}.tar.gz
    tar -xvf nginx-dav-ext-module-${NgxDavVer}.tar.gz
    mv nginx-dav-ext-module-${NgxDavVer} nginx-dav-ext-module
    rm -f nginx-dav-ext-module-${NgxDavVer}.tar.gz
    
    wget -c -O ngx_http_substitutions_filter_module-master.zip ${download_Url}/src/ngx_http_substitutions_filter_module-master.zip
    unzip -o ngx_http_substitutions_filter_module-master.zip
    rm -f ngx_http_substitutions_filter_module-master.zip


    if [ "${Is_64bit}" = "64" ]; then
        if [ "${version}" == "1.15" ] || [ "${version}" == "1.17" ] || [ "${version}" == "tengine" ]; then
            NGX_PAGESPEED_VAR="1.13.35.2"
            wget -O ngx-pagespeed-${NGX_PAGESPEED_VAR}.tar.gz ${download_Url}/src/ngx-pagespeed-${NGX_PAGESPEED_VAR}.tar.gz
            tar -xvf ngx-pagespeed-${NGX_PAGESPEED_VAR}.tar.gz
            mv ngx-pagespeed-${NGX_PAGESPEED_VAR} ngx-pagespeed
            rm -f ngx-pagespeed-${NGX_PAGESPEED_VAR}.tar.gz
        fi
    fi
}
Install_Configure() {
    Run_User="www"
    wwwUser=$(cat /etc/passwd | grep www)
    if [ "${wwwUser}" == "" ]; then
        groupadd ${Run_User}
        useradd -s /sbin/nologin -g ${Run_User} ${Run_User}
    fi

    [ -f "/www/server/panel/install/nginx_prepare.sh" ] && . /www/server/panel/install/nginx_prepare.sh
    [ -f "/www/server/panel/install/nginx_configure.pl" ] && ADD_EXTENSION=$(cat /www/server/panel/install/nginx_configure.pl)
    if [ -f "/usr/local/lib/libjemalloc.so" ] && [ -z "${ARM_CHECK}" ] && [ -z "${JEM_CHECK}" ]; then
        jemallocLD="--with-ld-opt="-ljemalloc""
    fi

    if [ "${version}" == "1.8" ]; then
        ENABLE_HTTP2="--with-http_spdy_module"
    else
        ENABLE_HTTP2="--with-http_v2_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module"
    fi

    WebDav_NGINX=$(echo ${nginxVersion} | tr -d '.' | cut -c 1-3)
    if [ "${WebDav_NGINX}" -ge "114" ] && [ "${WebDav_NGINX}" != "181" ]; then
        ENABLE_WEBDAV="--with-http_dav_module --add-module=${Setup_Path}/src/nginx-dav-ext-module"
    fi

    if [ "${version}" == "openresty" ]; then
        ENABLE_LUA="--with-luajit"
    elif [ -z "${ARM_CHECK}" ] && [ -f "/usr/local/include/${LUAJIT_INC_PATH}/luajit.h" ]; then
        ENABLE_LUA="--add-module=${Setup_Path}/src/ngx_devel_kit --add-module=${Setup_Path}/src/lua_nginx_module"
    fi
	
    ENABLE_STICKY="--add-module=${Setup_Path}/src/nginx-sticky-module"
	if [ "$version" == "1.23" ] || [ "$version" == "1.24" ] || [ "${version}" == "tengine" ] || [ "${version}" == "openresty" ] || [ "$version" == "1.25" ] || [ "${version}" == "1.26" ];then
        ENABLE_STICKY=""
	fi

    if [ "$version" == "1.25" ] || [ "${version}" == "1.26" ];then
        ENABLE_HTTP3="--with-http_v3_module"
    fi

    name=nginx
    i_path=/www/server/panel/install/$name

    i_args=$(cat $i_path/config.pl | xargs)
    i_make_args=""
    for i_name in $i_args; do
        init_file=$i_path/$i_name/init.sh
        if [ -f $init_file ]; then
            bash $init_file
        fi

        args_file=$i_path/$i_name/args.pl
        if [ -f $args_file ]; then
            args_string=$(cat $args_file)
            i_make_args="$i_make_args $args_string"
        fi
    done

    cd ${Setup_Path}/src

    # if [ "${GMSSL}" ];then
    # 	sed -i "s/$OPENSSL\/.openssl\//$OPENSSL\//g" auto/lib/openssl/conf
    # fi

    export LUAJIT_LIB=/usr/local/lib
    export LUAJIT_INC=/usr/local/include/${LUAJIT_INC_PATH}/
    export LD_LIBRARY_PATH=/usr/local/lib/:$LD_LIBRARY_PATH

    ./configure --user=www --group=www --prefix=${Setup_Path} ${ENABLE_LUA} --add-module=${Setup_Path}/src/ngx_cache_purge ${ENABLE_STICKY} --with-openssl=${Setup_Path}/src/openssl --with-pcre=pcre-${pcre_version} ${ENABLE_HTTP2} --with-http_stub_status_module --with-http_ssl_module --with-http_image_filter_module --with-http_gzip_static_module --with-http_gunzip_module --with-ipv6 --with-http_sub_module --with-http_flv_module --with-http_addition_module --with-http_realip_module --with-http_mp4_module --add-module=${Setup_Path}/src/ngx_http_substitutions_filter_module-master --with-ld-opt="-Wl,-E" --with-cc-opt="-Wno-error" ${jemallocLD} ${ENABLE_WEBDAV} ${ENABLE_NGX_PAGESPEED} ${ENABLE_HTTP3} ${ADD_EXTENSION} ${i_make_args} 2>&1|tee /tmp/nginx_config.pl
    make -j${cpuCore} 2>&1|tee /tmp/nginx_make.pl
}
Install_Nginx() {
    make install 2>&1|tee /tmp/nginx_install.pl
    if [ "${version}" == "openresty" ]; then
        ln -sf /www/server/nginx/nginx/html /www/server/nginx/html
        ln -sf /www/server/nginx/nginx/conf /www/server/nginx/conf
        ln -sf /www/server/nginx/nginx/logs /www/server/nginx/logs
        ln -sf /www/server/nginx/nginx/sbin /www/server/nginx/sbin
        if [ -d "/www/server/btwaf" ]; then
            \cp -rpa /www/server/nginx/lualib/* /www/server/btwaf
        elif [ -d "/www/server/free_waf" ];then
            \cp -rpa /www/server/nginx/lualib/* /www/server/free_waf
        fi
    fi

    if [ ! -f "${Setup_Path}/sbin/nginx" ]; then
        echo '========================================================'
        GetSysInfo
        echo -e "ERROR: nginx-${nginxVersion} installation failed."
        if [ -z "${SYS_VERSION}" ];then
            echo -e "============================================"
            echo -e "检测到为非常用系统安装"
            echo -e "如无法正常安装，建议更换至Centos-7或Debian-10+或Ubuntu-20+系统安装宝塔面板"
            echo -e "详情请查看系统兼容表：https://docs.qq.com/sheet/DUm54VUtyTVNlc21H?tab=BB08J2"
            echo -e "特殊情况可通过以下联系方式寻求安装协助情况"
            echo -e "============================================"
        fi
        echo -e "安装失败，请截图以上报错信息发帖至论坛www.bt.cn/bbs求助"
        rm -rf ${Setup_Path}
        
        if [ ! -f "/www/server/panel/install/nginx_down.pl" ];then
            FILE_KEY=("./configure: error: no /www/server/nginx/src/ngx_devel_kit/config was found" "./configure: No such file or directory" "./configure: error: no /www/server/nginx/src/ngx_http_substitutions_filter_module-master/config was found" "./configure: error: no /www/server/nginx/src/nginx-dav-ext-module/config was found" "auto/options: No such file or directory" "./configure: error: no /www/server/nginx/src/ngx_cache_purge/config was found" "/www/server/nginx/src/lua_nginx_module/config was found")
            for key in "${FILE_KEY[@]}"; do
            	if grep -q "$key" /tmp/nginx_config.pl; then
            		echo -e "检测到文件下载不完整导致安装失败，请尝试重新安装nginx看是否正常"
            		echo -e "或使用极速安装看是否正常"
            		touch /www/server/panel/install/nginx_down.pl
            		exit 1
            	fi
            done
        fi
        
        if [ "${i_make_args}" ];then
            echo -e "检测到使用自定义编译参数进行安装nginx"
            echo -e "请根据报错自行排查问题，或取消自定义编译参数重新安装"
            exit 1
        fi
        
        Centos8Check=$(cat /etc/redhat-release | grep ' 8.' | grep -iE 'centos')
        if [ "${Centos8Check}" ];then
            echo -e "Centos8官方已经停止支持"
            echo -e "如是新安装系统服务器建议更换至Centos-7/Debian-11/Ubuntu-22系统安装宝塔面板"
            exit 1
        fi
        
        WSL_CHECK=$(uname -a|grep Microsoft)
        if [ "${WSL_CHECK}" ];then
            echo -e "宝塔未兼容测试过Microsoft WSL子系统进行安装"
            echo -e "建议使用虚拟机安装ubuntu-22安装宝塔面板"
            exit 1
        fi
        VELINUX_CHECK=$(uname -a|grep velinux1)
        if [ "$VELINUX_CHECK" ];then
            echo -e "宝塔未兼容测试过velinux系统进行安装"
            echo -e "建议更换至Centos-7或Debian-10+或Ubuntu-20+系统安装宝塔面板板"
            exit 1
        fi
        rockchip64_CHECK=$(uname -a|grep rockchip64)
        if [ "$VELINUX_CHECK" ];then
            echo -e "宝塔未兼容测试过rockchip64系统进行安装"
            echo -e "建议更换至Centos-7或Debian-10+或Ubuntu-20+服务器系统安装宝塔面板板"
            exit 1
        fi
        KALI_CHECK=$(uname -a|grep Kali)
        if [ "${WSL_CHECK}" ];then
            echo -e "宝塔未兼容测试过Kali系统进行安装"
            echo -e "建议更换至Centos-7或Debian-10+或Ubuntu-20+系统安装宝塔面板板"
            exit 1
        fi
        ARMBIAN_CHECK=$(uname -a|grep Armbian)
        if [ "${ARMBIAN_CHECK}" ];then
            echo -e "宝塔未详细兼容测试过Armbian系统进行安装"
            echo -e "建议更换至Centos-7或Debian-10+或Ubuntu-20+系统安装宝塔面板板"
            exit 1
        fi
        RJ3328_CHECK=$(uname -a|grep rk3328)
        if [ "${RJ3328_CHECK}" ];then
            echo -e "宝塔未兼容测试过电视盒子进行安装"
            echo -e "建议更换至Centos-7或Debian-10+或Ubuntu-20+系统安装宝塔面板板"
            exit 1
        fi
        XIAOMI_CHECK=$(uname -a|grep xiaomi)
        if [ "${XIAOMI_CHECK}" ];then
            echo -e "宝塔未兼容测试过安卓手机进行安装"
            echo -e "建议更换至Centos-7或Debian-10+或Ubuntu-20+服务器系统安装宝塔面板板"
            exit 1
        fi
        if [ -f "/etc/redhat-release" ];then
            LINUX_KIT_CHECK=$(uname -a|grep linuxkit)
            if [ "${LINUX_KIT_CHECK}" ];then
                echo -e "宝塔未兼容测试过linuxkit(docker)环境下进行安装"
                echo -e "建议更换至服务器系统Centos-7或Debian-10+或Ubuntu-20+系统安装宝塔面板板"
                exit 1
            fi
            BBR_CHECK=$(uname -a|grep bbrplus)
            if [ "${BBR_CHECK}" ];then
                echo -e "检测已使用bbr更新过内核，建议更新完内核在安装宝塔面板然后再安装软件"
                echo -e "或如需高版本内核，可使用Ubuntu-22/Debian-12进行安装宝塔面板"
                exit 1
            fi
            ELREPO_CHECK=$(uname -a|grep elrepo)
            if [ "${ELREPO_CHECK}" ];then
                echo -e "检测更新过内核，建议更新完内核在安装宝塔面板然后再安装软件"
                echo -e "或如需高版本内核，可使用Ubuntu-22/Debian-12进行安装宝塔面板"
                exit 1
            fi
        fi
        
        if [ "${PM}" == "apt-get" ];then
            UBUNTU_23_CHECK=$(cat /etc/issue|grep Ubuntu|grep 23)
            if [ "${UBUNTU_23_CHECK}" ];then
                echo -e "宝塔未兼容测试过Ubuntu-23（预览版）环境下进行安装"
                echo -e "建议更换至服务器系统Centos-7或Debian-12或Ubuntu-22系统安装宝塔面板板"
                exit 1
            fi
            DEBIAN_9_CHECK=$(cat /etc/issue|grep Debian|grep 9)
            if [ "${UBUNTU_23_CHECK}" ];then
                echo -e "Debian-9官方已经不在支持"
                echo -e "建议更换至服务器系统Centos-7或Debian-12或Ubuntu-22系统安装宝塔面板板"
                exit 1
            fi
        fi
        
        Error_Send
    fi

    if [ "${version}" == "1.23" ] || [ "${version}" == "1.24" ] || [ "${version}" == "tengine" ] || [ "${version}" == "1.25" ] || [ "${version}" == "1.26" ];then
        wget -c -O lua-resty-core-0.1.26.zip ${download_Url}/src/lua-resty-core-0.1.26.zip
        unzip lua-resty-core-0.1.26.zip
        cd lua-resty-core-0.1.26
        make install PREFIX=/www/server/nginx
        cd ..
        rm -rf lua-resty-core-0.1.26*

        wget -c -O lua-resty-lrucache-0.13.zip ${download_Url}/src/lua-resty-lrucache-0.13.zip
        unzip lua-resty-lrucache-0.13.zip
        cd lua-resty-lrucache-0.13
        make install PREFIX=/www/server/nginx
        cd ..
        rm -rf lua-resty-core-0.1.26*

    fi
	
    \cp -rpa ${Setup_Path}/sbin/nginx /www/backup/nginxBak
	chmod -x /www/backup/nginxBak
	md5sum ${Setup_Path}/sbin/nginx > /www/server/panel/data/nginx_md5.pl
	ln -sf ${Setup_Path}/sbin/nginx /usr/bin/nginx
    rm -f ${Setup_Path}/conf/nginx.conf

    cd ${Setup_Path}
    rm -f src.tar.gz
}
Update_Nginx() {
    if [ "${nginxVersion}" = "openresty" ]; then
        make install
        echo -e "done"
        nginx -v
        echo "${nginxVersion}" >${Setup_Path}/version.pl
        rm -f ${Setup_Path}/version_check.pl
        exit
    fi
    if [ ! -f ${Setup_Path}/src/objs/nginx ]; then
        echo '========================================================'
        GetSysInfo
        echo -e "ERROR: nginx-${nginxVersion} installation failed."
        echo -e "升级失败，请截图以上报错信息发帖至论坛www.bt.cn/bbs求助"
        exit 1
    fi
    sleep 1
    /etc/init.d/nginx stop
    mv -f ${Setup_Path}/sbin/nginx ${Setup_Path}/sbin/nginxBak
    \cp -rfp ${Setup_Path}/src/objs/nginx ${Setup_Path}/sbin/
    if [ "${version}" == "1.25" ] || [ "${version}" == "1.26" ];then
        if [ "${version}" == "1.23" ] || [ "${version}" == "1.24" ] || [ "${version}" == "tengine" ] || [ "${version}" == "1.25" ] ||  [ "${version}" == "1.26" ];then
            wget -c -O lua-resty-core-0.1.26.zip ${download_Url}/src/lua-resty-core-0.1.26.zip
            unzip lua-resty-core-0.1.26.zip
            cd lua-resty-core-0.1.26
            make install PREFIX=/www/server/nginx
            cd ..
            rm -rf lua-resty-core-0.1.26*
    
            wget -c -O lua-resty-lrucache-0.13.zip ${download_Url}/src/lua-resty-lrucache-0.13.zip
            unzip lua-resty-lrucache-0.13.zip
            cd lua-resty-lrucache-0.13
            make install PREFIX=/www/server/nginx
            cd ..
            rm -rf lua-resty-core-0.1.26*
        fi
        wget -O /etc/init.d/nginx ${download_Url}/init/124nginx.init
    fi
    sleep 1
    /etc/init.d/nginx start
    rm -rf ${Setup_Path}/src
    nginx -v

    echo "${nginxVersion}" >${Setup_Path}/version.pl
    rm -f ${Setup_Path}/version_check.pl
    if [ "${version}" == "tengine" ]; then
        echo "2.2.4(${tengine})" >${Setup_Path}/version_check.pl
    fi
    exit
}
Set_Conf() {
    Default_Website_Dir=$Root_Path'/wwwroot/default'
    mkdir -p ${Default_Website_Dir}
    mkdir -p ${Root_Path}/wwwlogs
    mkdir -p ${Setup_Path}/conf/vhost
    mkdir -p /usr/local/nginx/logs
    mkdir -p ${Setup_Path}/conf/rewrite

    mkdir -p /www/wwwlogs/load_balancing/tcp
    mkdir -p /www/server/panel/vhost/nginx/tcp

    wget -O ${Setup_Path}/conf/nginx.conf ${download_Url}/conf/nginx1.conf -T20
    wget -O ${Setup_Path}/conf/pathinfo.conf ${download_Url}/conf/pathinfo.conf -T20
    wget -O ${Setup_Path}/conf/enable-php.conf ${download_Url}/conf/enable-php.conf -T20
    wget -O ${Setup_Path}/html/index.html ${download_Url}/error/index.html -T 20

    chmod 755 /www/server/nginx/
    chmod 755 /www/server/nginx/html/
    chmod 755 /www/wwwroot/
    chmod 644 /www/server/nginx/html/*

    cat >${Root_Path}/server/panel/vhost/nginx/phpfpm_status.conf <<EOF
server {
    listen 80;
    server_name 127.0.0.1;
    allow 127.0.0.1;
    location /nginx_status {
        stub_status on;
        access_log off;
    }
EOF
    echo "" >/www/server/nginx/conf/enable-php-00.conf
    for phpV in 52 53 54 55 56 70 71 72 73 74 75 80 81 82 83; do
        cat >${Setup_Path}/conf/enable-php-${phpV}.conf <<EOF
    location ~ [^/]\.php(/|$)
    {
        try_files \$uri =404;
        fastcgi_pass  unix:/tmp/php-cgi-${phpV}.sock;
        fastcgi_index index.php;
        include fastcgi.conf;
        include pathinfo.conf;
    }
EOF
        cat >>${Root_Path}/server/panel/vhost/nginx/phpfpm_status.conf <<EOF
    location /phpfpm_${phpV}_status {
        fastcgi_pass unix:/tmp/php-cgi-${phpV}.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$fastcgi_script_name;
    }
EOF
    done
    echo \} >>${Root_Path}/server/panel/vhost/nginx/phpfpm_status.conf

    cat >${Setup_Path}/conf/proxy.conf <<EOF
proxy_temp_path ${Setup_Path}/proxy_temp_dir;
proxy_cache_path ${Setup_Path}/proxy_cache_dir levels=1:2 keys_zone=cache_one:20m inactive=1d max_size=5g;
client_body_buffer_size 512k;
proxy_connect_timeout 60;
proxy_read_timeout 60;
proxy_send_timeout 60;
proxy_buffer_size 32k;
proxy_buffers 4 64k;
proxy_busy_buffers_size 128k;
proxy_temp_file_write_size 128k;
proxy_next_upstream error timeout invalid_header http_500 http_503 http_404;
proxy_cache cache_one;
EOF

    cat >${Setup_Path}/conf/luawaf.conf <<EOF
lua_shared_dict limit 10m;
lua_package_path "/www/server/nginx/waf/?.lua";
init_by_lua_file  /www/server/nginx/waf/init.lua;
access_by_lua_file /www/server/nginx/waf/waf.lua;
EOF

    mkdir -p /www/wwwlogs/waf
    chown www.www /www/wwwlogs/waf
    chmod 744 /www/wwwlogs/waf
    mkdir -p /www/server/panel/vhost
    #wget -O waf.zip ${download_Url}/install/waf/waf.zip
    #unzip -o waf.zip -d $Setup_Path/ >/dev/null
    if [ ! -d "/www/server/panel/vhost/wafconf" ]; then
        mv $Setup_Path/waf/wafconf /www/server/panel/vhost/wafconf
    fi

    sed -i "s#include vhost/\*.conf;#include /www/server/panel/vhost/nginx/\*.conf;#" ${Setup_Path}/conf/nginx.conf
    sed -i "s#/www/wwwroot/default#/www/server/phpmyadmin#" ${Setup_Path}/conf/nginx.conf
    sed -i "/pathinfo/d" ${Setup_Path}/conf/enable-php.conf
    sed -i "s/#limit_conn_zone.*/limit_conn_zone \$binary_remote_addr zone=perip:10m;\n\tlimit_conn_zone \$server_name zone=perserver:10m;/" ${Setup_Path}/conf/nginx.conf
    sed -i "s/mime.types;/mime.types;\n\t\tinclude proxy.conf;\n/" ${Setup_Path}/conf/nginx.conf
    #if [ "${nginx_version}" == "1.12.2" ] || [ "${nginx_version}" == "openresty" ] || [ "${nginx_version}" == "1.14.2" ];then
    sed -i "s/mime.types;/mime.types;\n\t\t#include luawaf.conf;\n/" ${Setup_Path}/conf/nginx.conf
    #fi

    PHPVersion=""
    for phpVer in 52 53 54 55 56 70 71 72 73 74 80; do
        if [ -d "/www/server/php/${phpVer}/bin" ]; then
            PHPVersion=${phpVer}
        fi
    done

    if [ "${PHPVersion}" ]; then
        \cp -r -a ${Setup_Path}/conf/enable-php-${PHPVersion}.conf ${Setup_Path}/conf/enable-php.conf
    fi
    
    if [ ! -f "${Setup_Path}/conf/enable-php.conf" ];then
        touch ${Setup_Path}/conf/enable-php.conf
    fi

    AA_PANEL_CHECK=$(cat /www/server/panel/config/config.json | grep "English")
    if [ "${AA_PANEL_CHECK}" ]; then
        #\cp -rf /www/server/panel/data/empty.html /www/server/nginx/html/index.html
        wget -O /www/server/nginx/html/index.html ${download_Url}/error/index_en_nginx.html -T 20
        chmod 644 /www/server/nginx/html/index.html
        wget -O /www/server/panel/vhost/nginx/0.default.conf ${download_Url}/conf/nginx/en.0.default.conf
        for phpV in 52 53 54 55 56 70 71 72 73 74 75 80 81 82 83; do
            wget -O ${Setup_Path}/conf/enable-php-${phpV}-wpfastcgi.conf ${download_Url}/install/wordpress_conf/nginx/enable-php-${phpV}-wpfastcgi.conf
        done
    fi
    
    wget -O /etc/init.d/nginx ${download_Url}/init/nginx.init -T 20
    if [ "${version}" == "1.23" ] || [ "${version}" == "1.24" ] || [ "${version}" == "tengine" ] || [ "${version}" == "1.25" ] || [ "${version}" == "1.26" ];then
        if [ -d "/www/server/btwaf" ];then
            rm -rf /www/server/btwaf/ngx
            rm -rf /www/server/btwaf/resty
            \cp -rpa /www/server/nginx/lib/lua/* /www/server/btwaf
        elif [ -d "/www/server/free_waf" ];then
            rm -rf /www/server/btwaf/ngx
            rm -rf /www/server/btwaf/resty
            \cp -rpa /www/server/nginx/lib/lua/* /www/server/free_waf
        else
            sed -i "/lua_package_path/d" /www/server/nginx/conf/nginx.conf
            sed -i '/include proxy\.conf;/a \        lua_package_path "/www/server/nginx/lib/lua/?.lua;;";' /www/server/nginx/conf/nginx.conf
        fi
        wget -O /etc/init.d/nginx ${download_Url}/init/124nginx.init -T 20
    fi
    if [ "${version}" == "1.25" ] || [ "${version}" == "1.26" ];then
        HTTP_POST_CHECK=$(cat /www/server/nginx/conf/fastcgi.conf|grep "HTTP_HOST")
        if [ -z "${HTTP_POST_CHECK}" ];then
            echo "fastcgi_param  HTTP_HOST          \$host;" >> /www/server/nginx/conf/fastcgi.conf
        fi
    fi

    chmod +x /etc/init.d/nginx
}
Set_Version() {
    if [ "${version}" == "tengine" ]; then
        echo "-Tengine2.2.3" >${Setup_Path}/version.pl
        echo "2.2.4(${tengine})" >${Setup_Path}/version_check.pl
    elif [ "${version}" == "openresty" ]; then
        echo "openresty" >${Setup_Path}/version.pl
        echo "openresty-${openresty}" >${Setup_Path}/version_check.pl
    else
        echo "${nginxVersion}" >${Setup_Path}/version.pl
    fi

    if [ "${GMSSL}" ]; then
        echo "1.18国密版" >${Setup_Path}/version_check.pl
    fi
}

Uninstall_Nginx() {
    if [ -f "/etc/init.d/nginx" ]; then
        Service_Del
        /etc/init.d/nginx stop
        rm -f /etc/init.d/nginx
    fi
    [ -f "${Setup_Path}/rpm.pl" ] && yum remove bt-$(cat ${Setup_Path}/rpm.pl) -y
    [ -f "${Setup_Path}/deb.pl" ] && apt-get remove bt-$(cat ${Setup_Path}/deb.pl) -y
    pkill -9 nginx
    rm -rf ${Setup_Path}
    rm -rf /www/server/btwaf/ngx
    rm -rf /www/server/btwaf/resty
    rm -rf /www/server/btwaf/librestysignal.so
    rm -rf /www/server/btwaf/rds
    rm -rf /www/server/btwaf/redis
    rm -rf /www/server/btwaf/tablepool.lua
}

actionType=$1
version=$2

if [ "${actionType}" == "uninstall" ]; then
    Service_Del
    Uninstall_Nginx
else
    case "${version}" in
    '1.10')
        nginxVersion=${nginx_112}
        ;;
    '1.12')
        nginxVersion=${nginx_112}
        ;;
    '1.14')
        nginxVersion=${nginx_114}
        ;;
    '1.15')
        nginxVersion=${nginx_115}
        ;;
    '1.16')
        nginxVersion=${nginx_116}
        ;;
    '1.17')
        nginxVersion=${nginx_117}
        ;;
    '1.18')
        nginxVersion=${nginx_118}
        ;;
    '1.18.gmssl')
        nginxVersion=${nginx_118}
        GMSSL="True"
        ;;
    '1.19')
        nginxVersion=${nginx_119}
        ;;
    '1.20')
        nginxVersion=${nginx_120}
        ;;
    '1.21')
        nginxVersion=${nginx_121}
        ;;
    '1.22')
        nginxVersion=${nginx_122}
        ;;
    '1.23')
        nginxVersion=${nginx_123}
        ;;
    '1.24')
        nginxVersion=${nginx_124}
        ;;
    '1.25')
        nginxVersion=${nginx_125}
        ;;
    '1.26')
        nginxVersion=${nginx_126}
        ;;
    '1.8')
        nginxVersion=${nginx_108}
        ;;
    'openresty')
        nginxVersion=${openresty}
        ;;
    *)
        nginxVersion=${tengine}
        version="tengine"
        ;;
    esac
    if [ "${actionType}" == "install" ]; then
        if [ -f "/www/server/nginx/sbin/nginx" ]; then
            Uninstall_Nginx
        fi
        System_Lib
        if [ -z "${ARM_CHECK}" ]; then
            Install_Jemalloc
            Install_LuaJIT
            Install_cjson
        fi
        Download_Src
        Install_Configure
        Install_Nginx
        Set_Conf
        Set_Version
        Service_Add
        /etc/init.d/nginx start
    elif [ "${actionType}" == "update" ]; then
        if [ "${version}" == "1.25" ];then
            Install_LuaJIT
        fi
        Download_Src
        Install_Configure
        Update_Nginx
    fi
fi

