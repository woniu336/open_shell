#!/bin/bash

# 默认$PATH环境变量
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

#「验证是否ROOT权限安装面板」
if [ $(whoami) != "root" ]; then
  echo "请使用Root权限执行安装命令！"
  exit 1
fi

#「验证是否为64位系统」
is64bit=$(getconf LONG_BIT)
if [ "${is64bit}" != '64' ]; then
  Red_Error "抱歉, 当前面板版本不支持32位系统。"
fi

#「验证是否为Centos6系统」
Centos6Check=$(cat /etc/redhat-release | grep ' 6.' | grep -iE 'centos|Red Hat')
if [ "${Centos6Check}" ]; then
  echo "Centos6不支持安装面板，请更换Centos7/8安装面板"
  exit 1
fi

#「验证是否小于Ubuntu16」
UbuntuCheck=$(cat /etc/issue | grep Ubuntu | awk '{print $2}' | cut -f 1 -d '.')
if [ "${UbuntuCheck}" ] && [ "${UbuntuCheck}" -lt "16" ]; then
  echo "Ubuntu ${UbuntuCheck}不支持安装面板，建议更换Ubuntu18/20安装面板"
  exit 1
fi

#「绑定安装目录、Python目录、获取服务器CPU核心」
cd ~
setup_path="/www"
python_bin=$setup_path/server/panel/pyenv/bin/python
cpu_cpunt=$(cat /proc/cpuinfo | grep processor | wc -l)

if [ "$1" ]; then
  IDC_CODE=$1
fi

GetSysInfo() {
  if [ -s "/etc/redhat-release" ]; then
    SYS_VERSION=$(cat /etc/redhat-release)
  elif [ -s "/etc/issue" ]; then
    SYS_VERSION=$(cat /etc/issue)
  fi
  SYS_INFO=$(uname -a)
  SYS_BIT=$(getconf LONG_BIT)
  MEM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
  CPU_INFO=$(getconf _NPROCESSORS_ONLN)

  echo -e ${SYS_VERSION}
  echo -e Bit:${SYS_BIT} Mem:${MEM_TOTAL}M Core:${CPU_INFO}
  echo -e ${SYS_INFO}
  echo -e "请截图以上报错信息发帖至论坛求助"
}

Red_Error() {
  echo '================================================='
  printf '\033[1;31;40m%b\033[0m\n' "$@"
  GetSysInfo
  exit 1
}

# 锁删除
Lock_Clear() {
  if [ -f "/etc/bt_crack.pl" ]; then
    chattr -R -ia /www
    chattr -ia /etc/init.d/bt
    \cp -rpa /www/backup/panel/vhost/* /www/server/panel/vhost/
    mv /www/server/panel/BTPanel/__init__.bak /www/server/panel/BTPanel/__init__.py
    rm -f /etc/bt_crack.pl
  fi
}
#「安装检查」
Install_Check() {
  if [ "${INSTALL_FORCE}" ]; then
    return
  fi
  echo -e "----------------------------------------------------"
  echo -e "检查已有其他Web/mysql环境，安装可能影响现有站点及数据"
  echo -e "Web/mysql service is alreday installed,Can't install panel"
  echo -e "----------------------------------------------------"
  echo -e "已知风险/Enter yes to force installation"
  read -p "输入yes强制安装: " yes
  if [ "$yes" != "yes" ]; then
    echo -e "------------"
    echo "取消安装"
    exit
  fi
  INSTALL_FORCE="true"
}
#「系统检查Mysql、Php、Nginx、Apache如果存在推出提示是否强制安装」
System_Check() {
  MYSQLD_CHECK=$(ps -ef | grep mysqld | grep -v grep | grep -v /www/server/mysql)
  PHP_CHECK=$(ps -ef | grep php-fpm | grep master | grep -v /www/server/php)
  NGINX_CHECK=$(ps -ef | grep nginx | grep master | grep -v /www/server/nginx)
  HTTPD_CHECK=$(ps -ef | grep -E 'httpd|apache' | grep -v /www/server/apache | grep -v grep)
  if [ "${PHP_CHECK}" ] || [ "${MYSQLD_CHECK}" ] || [ "${NGINX_CHECK}" ] || [ "${HTTPD_CHECK}" ]; then
    Install_Check
  fi
}
#「设置面板打开SSL」
Set_Ssl() {
  echo -e ""
  echo -e "----------------------------------------------------------------------"
  echo -e "为了您的面板使用安全，建议您开启面板SSL，开启后请使用https访问面板"
  echo -e "输入y回车即开启面板SSL并进行下一步安装"
  echo -e "输入n回车跳过面板SSL配置，直接进行安装"
  echo -e "面板SSL将在10秒钟后自动开启"
  echo -e "----------------------------------------------------------------------"
  echo -e ""
  read -t 10 -p "是否确定开启面板SSL ? (y/n): " yes

  if [ $? != 0 ]; then
    SET_SSL=true
  else
    case "$yes" in
    y)
      SET_SSL=true
      ;;
    n)
      SET_SSL=false
      rm -f /www/server/panel/data/ssl.pl
      ;;
    *)
      Set_Ssl
      ;;
    esac
  fi
}
#「系统包管理器兼容」
Get_Pack_Manager() {
  if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
    PM="yum"
  elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
    PM="apt-get"
  fi
}
#「获取节点链接」
get_node_url() {
  #「判断Curl是否存在，否则安装」
  if [ ! -f /bin/curl ]; then
    if [ "${PM}" = "yum" ]; then
      yum install curl -y
    elif [ "${PM}" = "apt-get" ]; then
      apt-get install curl -y
    fi
  fi

  echo '---------------------------------------------'
  echo "Selected download node..."

  download_Url='https://gitee.com/dayu777/btpanel-v7.7.0/raw/main'
  echo "Download node: $download_Url"
  echo '---------------------------------------------'
}
#「检测是否需要设置Swap」
Auto_Swap() {
  swap=$(free | grep Swap | awk '{print $2}')
  #「如果Swap交换内存大于1则返回」
  if [ "${swap}" -gt 1 ]; then
    echo "Swap total sizse: $swap"
    return
  fi

  #「判断【www】根目录不存在则创建」
  if [ ! -d /www ]; then
    mkdir /www
  fi
  swapFile="/www/swap"
  dd if=/dev/zero of=$swapFile bs=1M count=1025                    #「测试磁盘写能力」
  mkswap -f $swapFile                                              #「设置SWAP交换分区」
  swapon $swapFile                                                 #「设置SWAP交换分区」
  echo "$swapFile    swap    swap    defaults    0 0" >>/etc/fstab #「设置开机自动挂载swap分区」
  swap=$(free | grep Swap | awk '{print $2}')
  if [ $swap -gt 1 ]; then
    echo "Swap total sizse: $swap"
    return
  fi

  sed -i "/\/www\/swap/d" /etc/fstab
  rm -f $swapFile
}
#「Centos8相关系统兼容」
Set_Centos_Repo() {
  HUAWEI_CHECK=$(cat /etc/motd | grep "Huawei Cloud")
  if [ "${HUAWEI_CHECK}" ] && [ "${is64bit}" == "64" ]; then
    \cp -rpa /etc/yum.repos.d/ /etc/yumBak
    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.epel.cloud|g' /etc/yum.repos.d/CentOS-*.repo
    rm -f /etc/yum.repos.d/epel.repo
    rm -f /etc/yum.repos.d/epel-*
  fi
  ALIYUN_CHECK=$(cat /etc/motd | grep "Alibaba Cloud ")
  if [ "${ALIYUN_CHECK}" ] && [ "${is64bit}" == "64" ] && [ ! -f "/etc/yum.repos.d/Centos-vault-8.5.2111.repo" ]; then
    rename '.repo' '.repo.bak' /etc/yum.repos.d/*.repo
    wget https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo -O /etc/yum.repos.d/Centos-vault-8.5.2111.repo
    wget https://mirrors.aliyun.com/repo/epel-archive-8.repo -O /etc/yum.repos.d/epel-archive-8.repo
    sed -i 's/mirrors.cloud.aliyuncs.com/url_tmp/g' /etc/yum.repos.d/Centos-vault-8.5.2111.repo && sed -i 's/mirrors.aliyun.com/mirrors.cloud.aliyuncs.com/g' /etc/yum.repos.d/Centos-vault-8.5.2111.repo && sed -i 's/url_tmp/mirrors.aliyun.com/g' /etc/yum.repos.d/Centos-vault-8.5.2111.repo
    sed -i 's/mirrors.aliyun.com/mirrors.cloud.aliyuncs.com/g' /etc/yum.repos.d/epel-archive-8.repo
  fi
  MIRROR_CHECK=$(cat /etc/yum.repos.d/CentOS-Linux-AppStream.repo | grep "[^#]mirror.centos.org")
  if [ "${MIRROR_CHECK}" ] && [ "${is64bit}" == "64" ]; then
    \cp -rpa /etc/yum.repos.d/ /etc/yumBak
    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.epel.cloud|g' /etc/yum.repos.d/CentOS-*.repo
  fi
}
#「yum包安装」
Install_RPM_Pack() {
  yumPath=/etc/yum.conf
  Centos8Check=$(cat /etc/redhat-release | grep ' 8.' | grep -iE 'centos|Red Hat')
  if [ "${Centos8Check}" ]; then
    Set_Centos_Repo
  fi
  isExc=$(cat $yumPath | grep httpd)
  if [ "$isExc" = "" ]; then
    echo "exclude=httpd nginx php mysql mairadb python-psutil python2-psutil" >>$yumPath
  fi

  #尝试同步时间
  echo 'Synchronizing system time...'
  getBtTime=$(curl -s api.bilibili.com/x/report/click/now | grep "now\":" | awk -F':' '{print $6}' | awk -F'}' '{print $1}')
  if [ "${getBtTime}" ]; then
    date -s "$(date -d @$getBtTime +"%Y-%m-%d %H:%M:%S")"
  fi

  if [ -z "${Centos8Check}" ]; then #「如果不等于Centos8」
    yum install ntp -y
    rm -rf /etc/localtime
    ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    #尝试同步国际时间(从ntp服务器)
    ntpdate 0.asia.pool.ntp.org
    setenforce 0
  fi

  startTime=$(date +%s)

  #关闭安全模式
  sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

  yumPacks="libcurl-devel wget tar gcc make zip unzip openssl openssl-devel gcc libxml2 libxml2-devel libxslt* zlib zlib-devel libjpeg-devel libpng-devel libwebp libwebp-devel freetype freetype-devel lsof pcre pcre-devel vixie-cron crontabs icu libicu-devel c-ares libffi-devel bzip2-devel ncurses-devel sqlite-devel readline-devel tk-devel gdbm-devel db4-devel libpcap-devel xz-devel qrencode"

  yum install -y ${yumPacks}

  for yumPack in ${yumPacks}; do
    rpmPack=$(rpm -q ${yumPack})
    packCheck=$(echo ${rpmPack} | grep not)
    if [ "${packCheck}" ]; then #「如果没有安装则重新安装」
      yum install ${yumPack} -y
    fi
  done

  if [ -f "/usr/bin/dnf" ]; then
    dnf install -y redhat-rpm-config
  fi

  ALI_OS=$(cat /etc/redhat-release | grep "Alibaba Cloud Linux release 3")
  if [ -z "${ALI_OS}" ]; then
    yum install epel-release -y
  fi
}
#「apt-get包安装」
Install_Deb_Pack() {
  ln -sf bash /bin/sh
  # 兼容
  UBUNTU_22=$(cat /etc/issue | grep "Ubuntu 22")
  if [ "${UBUNTU_22}" ]; then
    apt-get remove needrestart -y
  fi
  ALIYUN_CHECK=$(cat /etc/motd | grep "Alibaba Cloud ")
  if [ "${ALIYUN_CHECK}" ] && [ "${UBUNTU_22}" ]; then
    apt-get remove libicu70 -y
  fi

  apt-get update -y
  apt-get install bash -y
  if [ -f "/usr/bin/bash" ]; then
    ln -sf /usr/bin/bash /bin/sh
  fi
  apt-get install ruby -y
  apt-get install lsb-release -y

  LIBCURL_VER=$(dpkg -l | grep libcurl4 | awk '{print $3}')
  if [ "${LIBCURL_VER}" == "7.68.0-1ubuntu2.8" ]; then
    apt-get remove libcurl4 -y
    apt-get install curl -y
  fi

  debPacks="wget curl libcurl4-openssl-dev gcc make zip unzip tar openssl libssl-dev gcc libxml2 libxml2-dev zlib1g zlib1g-dev libjpeg-dev libpng-dev lsof libpcre3 libpcre3-dev cron net-tools swig build-essential libffi-dev libbz2-dev libncurses-dev libsqlite3-dev libreadline-dev tk-dev libgdbm-dev libdb-dev libdb++-dev libpcap-dev xz-utils git qrencode"
  apt-get install -y $debPacks --force-yes
  #「循环安装」
  for debPack in ${debPacks}; do
    packCheck=$(dpkg -l | grep ${debPack})
    if [ "$?" -ne "0" ]; then
      apt-get install -y $debPack
    fi
  done

  #「如果证书文件夹不存在,创建」
  if [ ! -d '/etc/letsencrypt' ]; then
    mkdir -p /etc/letsencryp
    mkdir -p /var/spool/cron
    if [ ! -f '/var/spool/cron/crontabs/root' ]; then
      echo '' >/var/spool/cron/crontabs/root
      chmod 600 /var/spool/cron/crontabs/root
    fi
  fi
}

Service_Add() {
  if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
    chkconfig --add bt
    chkconfig --level 2345 bt on
    Centos9Check=$(cat /etc/redhat-release | grep ' 9')
    if [ "${Centos9Check}" ]; then
      wget -O /usr/lib/systemd/system/btpanel.service ${download_Url}/init/systemd/btpanel.service
      systemctl enable btpanel
    fi
  elif [ "${PM}" == "apt-get" ]; then
    update-rc.d bt defaults
  fi
}

Remove_Package() {
  local PackageNmae=$1
  if [ "${PM}" == "yum" ]; then
    isPackage=$(rpm -q ${PackageNmae} | grep "not installed")
    if [ -z "${isPackage}" ]; then
      yum remove ${PackageNmae} -y
    fi
  elif [ "${PM}" == "apt-get" ]; then
    isPackage=$(dpkg -l | grep ${PackageNmae})
    if [ "${PackageNmae}" ]; then
      apt-get remove ${PackageNmae} -y
    fi
  fi
}
#「获取版本」
Get_Versions() {
  redhat_version_file="/etc/redhat-release"
  deb_version_file="/etc/issue"
  if [ -f $redhat_version_file ]; then
    os_type='el'
    is_aliyunos=$(cat $redhat_version_file | grep Aliyun)
    if [ "$is_aliyunos" != "" ]; then
      return
    fi
    os_version=$(cat $redhat_version_file | grep CentOS | grep -Eo '([0-9]+\.)+[0-9]+' | grep -Eo '^[0-9]')
    if [ "${os_version}" = "5" ]; then
      os_version=""
    fi
    if [ -z "${os_version}" ]; then
      os_version=$(cat /etc/redhat-release | grep Stream | grep -oE 8)
    fi
  else
    os_type='ubuntu'
    os_version=$(cat $deb_version_file | grep Ubuntu | grep -Eo '([0-9]+\.)+[0-9]+' | grep -Eo '^[0-9]+')
    if [ "${os_version}" = "" ]; then
      os_type='debian'
      os_version=$(cat $deb_version_file | grep Debian | grep -Eo '([0-9]+\.)+[0-9]+' | grep -Eo '[0-9]+')
      if [ "${os_version}" = "" ]; then
        os_version=$(cat $deb_version_file | grep Debian | grep -Eo '[0-9]+')
      fi
      if [ "${os_version}" = "8" ]; then
        os_version=""
      fi
      if [ "${is64bit}" = '32' ]; then
        os_version=""
      fi
    else
      if [ "$os_version" = "14" ]; then
        os_version=""
      fi
      if [ "$os_version" = "12" ]; then
        os_version=""
      fi
      if [ "$os_version" = "19" ]; then
        os_version=""
      fi
      if [ "$os_version" = "21" ]; then
        os_version=""
      fi
      if [ "$os_version" = "20" ]; then
        os_version2004=$(cat /etc/issue | grep 20.04)
        if [ -z "${os_version2004}" ]; then
          os_version=""
        fi
      fi
    fi
  fi
}
#「安装Python模块」
Install_Python_Lib() {
  curl -Ss --connect-timeout 3 -m 60 $download_Url/install/pip_select.sh | bash
  pyenv_path="/www/server/panel"
  if [ -f $pyenv_path/pyenv/bin/python ]; then
    is_ssl=$($python_bin -c "import ssl" 2>&1 | grep cannot)
    $pyenv_path/pyenv/bin/python3.7 -V
    if [ $? -eq 0 ] && [ -z "${is_ssl}" ]; then
      chmod -R 700 $pyenv_path/pyenv/bin
      is_package=$($python_bin -m psutil 2>&1 | grep package)
      if [ "$is_package" = "" ]; then
        wget -O $pyenv_path/pyenv/pip.txt $download_Url/install/pyenv/pip.txt -T 5
        $pyenv_path/pyenv/bin/pip install -U pip
        $pyenv_path/pyenv/bin/pip install -U setuptools==65.5.0
        $pyenv_path/pyenv/bin/pip install -r $pyenv_path/pyenv/pip.txt
      fi
      source $pyenv_path/pyenv/bin/activate
      chmod -R 700 $pyenv_path/pyenv/bin
      return
    else
      rm -rf $pyenv_path/pyenv
    fi
  fi

  is_loongarch64=$(uname -a | grep loongarch64)
  if [ "$is_loongarch64" != "" ] && [ -f "/usr/bin/yum" ]; then
    yumPacks="python3-devel python3-pip python3-psutil python3-gevent python3-pyOpenSSL python3-paramiko python3-flask python3-rsa python3-requests python3-six python3-websocket-client"
    yum install -y ${yumPacks}
    for yumPack in ${yumPacks}; do
      rpmPack=$(rpm -q ${yumPack})
      packCheck=$(echo ${rpmPack} | grep not)
      if [ "${packCheck}" ]; then
        yum install ${yumPack} -y
      fi
    done

    pip3 install -U pip
    pip3 install Pillow psutil pyinotify pycryptodome upyun oss2 pymysql qrcode qiniu redis pymongo Cython configparser cos-python-sdk-v5 supervisor gevent-websocket pyopenssl
    pip3 install flask==2.1.2
    pip3 install Pillow -U

    pyenv_bin=/www/server/panel/pyenv/bin
    mkdir -p $pyenv_bin
    ln -sf /usr/local/bin/pip3 $pyenv_bin/pip
    ln -sf /usr/local/bin/pip3 $pyenv_bin/pip3
    ln -sf /usr/local/bin/pip3 $pyenv_bin/pip3.7

    if [ -f "/usr/bin/python3.7" ]; then
      ln -sf /usr/bin/python3.7 $pyenv_bin/python
      ln -sf /usr/bin/python3.7 $pyenv_bin/python3
      ln -sf /usr/bin/python3.7 $pyenv_bin/python3.7
    elif [ -f "/usr/bin/python3.6" ]; then
      ln -sf /usr/bin/python3.6 $pyenv_bin/python
      ln -sf /usr/bin/python3.6 $pyenv_bin/python3
      ln -sf /usr/bin/python3.6 $pyenv_bin/python3.7
    fi

    echo >$pyenv_bin/activate

    return
  fi

  py_version="3.7.8"
  mkdir -p $pyenv_path
  echo "True" >/www/disk.pl
  if [ ! -w /www/disk.pl ]; then
    Red_Error "ERROR: Install python env fielded." "ERROR: /www目录无法写入，请检查目录/用户/磁盘权限！"
  fi
  os_type='el'
  os_version='7'
  is_export_openssl=0
  Get_Versions

  echo "OS: $os_type - $os_version"
  is_aarch64=$(uname -a | grep aarch64)
  if [ "$is_aarch64" != "" ]; then
    is64bit="aarch64"
  fi

  if [ -f "/www/server/panel/pymake.pl" ]; then
    os_version=""
    rm -f /www/server/panel/pymake.pl
  fi

  if [ "${os_version}" != "" ]; then
    pyenv_file="/www/pyenv.tar.gz"
    wget -O $pyenv_file $download_Url/install/pyenv/pyenv-${os_type}${os_version}-x${is64bit}.tar.gz -T 10
    if [ "$?" != "0" ]; then
      get_node_url $download_Url
      wget -O $pyenv_file $download_Url/install/pyenv/pyenv-${os_type}${os_version}-x${is64bit}.tar.gz -T 10
    fi
    tmp_size=$(du -b $pyenv_file | awk '{print $1}')
    if [ $tmp_size -lt 703460 ]; then
      rm -f $pyenv_file
      echo "ERROR: Download python env fielded."
    else
      echo "Install python env..."
      tar zxvf $pyenv_file -C $pyenv_path/ >/dev/null
      chmod -R 700 $pyenv_path/pyenv/bin
      if [ ! -f $pyenv_path/pyenv/bin/python ]; then
        rm -f $pyenv_file
        Red_Error "ERROR: Install python env fielded." "ERROR: 下载运行环境失败，请尝试重新安装！"
      fi
      $pyenv_path/pyenv/bin/python3.7 -V
      if [ $? -eq 0 ]; then
        rm -f $pyenv_file
        ln -sf $pyenv_path/pyenv/bin/pip3.7 /usr/bin/btpip
        ln -sf $pyenv_path/pyenv/bin/python3.7 /usr/bin/btpython
        source $pyenv_path/pyenv/bin/activate
        return
      else
        rm -f $pyenv_file
        rm -rf $pyenv_path/pyenv
      fi
    fi
  fi

  cd /www
  python_src='/www/python_src.tar.xz'
  python_src_path="/www/Python-${py_version}"
  wget -O $python_src $download_Url/src/Python-${py_version}.tar.xz -T 5
  tmp_size=$(du -b $python_src | awk '{print $1}')
  if [ $tmp_size -lt 10703460 ]; then
    rm -f $python_src
    Red_Error "ERROR: Download python source code fielded." "ERROR: 下载运行环境失败，请尝试重新安装！"
  fi
  tar xvf $python_src
  rm -f $python_src
  cd $python_src_path
  ./configure --prefix=$pyenv_path/pyenv
  make -j$cpu_cpunt
  make install
  if [ ! -f $pyenv_path/pyenv/bin/python3.7 ]; then
    rm -rf $python_src_path
    Red_Error "ERROR: Make python env fielded." "ERROR: 编译运行环境失败！"
  fi
  cd ~
  rm -rf $python_src_path
  wget -O $pyenv_path/pyenv/bin/activate $download_Url/install/pyenv/activate.panel -T 5
  wget -O $pyenv_path/pyenv/pip.txt $download_Url/install/pyenv/pip-3.7.8.txt -T 5
  ln -sf $pyenv_path/pyenv/bin/pip3.7 $pyenv_path/pyenv/bin/pip
  ln -sf $pyenv_path/pyenv/bin/python3.7 $pyenv_path/pyenv/bin/python
  ln -sf $pyenv_path/pyenv/bin/pip3.7 /usr/bin/btpip
  ln -sf $pyenv_path/pyenv/bin/python3.7 /usr/bin/btpython
  chmod -R 700 $pyenv_path/pyenv/bin
  $pyenv_path/pyenv/bin/pip install -U pip
  $pyenv_path/pyenv/bin/pip install -U setuptools==65.5.0
  $pyenv_path/pyenv/bin/pip install -U wheel==0.34.2
  $pyenv_path/pyenv/bin/pip install -r $pyenv_path/pyenv/pip.txt
  source $pyenv_path/pyenv/bin/activate

  is_gevent=$($python_bin -m gevent 2>&1 | grep -oE package)
  is_psutil=$($python_bin -m psutil 2>&1 | grep -oE package)
  if [ "${is_gevent}" != "${is_psutil}" ]; then
    Red_Error "ERROR: psutil/gevent install failed!"
  fi
}
#「安装面板」
Install_Bt() {
  panelPort="8888"
  if [ -f ${setup_path}/server/panel/data/port.pl ]; then
    panelPort=$(cat ${setup_path}/server/panel/data/port.pl)
  else
    panelPort=$(expr $RANDOM % 55535 + 10000)
  fi
  if [ "${PANEL_PORT}" ]; then
    panelPort=$PANEL_PORT
  fi
  mkdir -p ${setup_path}/server/panel/logs
  mkdir -p ${setup_path}/server/panel/vhost/apache
  mkdir -p ${setup_path}/server/panel/vhost/nginx
  mkdir -p ${setup_path}/server/panel/vhost/rewrite
  mkdir -p ${setup_path}/server/panel/install
  mkdir -p /www/server
  mkdir -p /www/wwwroot
  mkdir -p /www/wwwlogs
  mkdir -p /www/backup/database
  mkdir -p /www/backup/site

  if [ ! -d "/etc/init.d" ]; then
    mkdir -p /etc/init.d
  fi

  if [ -f "/etc/init.d/bt" ]; then
    /etc/init.d/bt stop
    sleep 1
  fi

  wget -O /etc/init.d/bt ${download_Url}/install/src/bt6.init -T 10
  wget -O /www/server/panel/install/public.sh ${download_Url}/install/public.sh -T 10
  wget -O panel.zip ${download_Url}/install/src/panel6.zip -T 10

  if [ -f "${setup_path}/server/panel/data/default.db" ]; then
    if [ -d "/${setup_path}/server/panel/old_data" ]; then
      rm -rf ${setup_path}/server/panel/old_data
    fi
    mkdir -p ${setup_path}/server/panel/old_data
    d_format=$(date +"%Y%m%d_%H%M%S")
    \cp -arf ${setup_path}/server/panel/data/default.db ${setup_path}/server/panel/data/default_backup_${d_format}.db
    mv -f ${setup_path}/server/panel/data/default.db ${setup_path}/server/panel/old_data/default.db
    mv -f ${setup_path}/server/panel/data/system.db ${setup_path}/server/panel/old_data/system.db
    mv -f ${setup_path}/server/panel/data/port.pl ${setup_path}/server/panel/old_data/port.pl
    mv -f ${setup_path}/server/panel/data/admin_path.pl ${setup_path}/server/panel/old_data/admin_path.pl
  fi

  if [ ! -f "/usr/bin/unzip" ]; then
    if [ "${PM}" = "yum" ]; then
      yum install unzip -y
    elif [ "${PM}" = "apt-get" ]; then
      apt-get update
      apt-get install unzip -y
    fi
  fi

  unzip -o panel.zip -d ${setup_path}/server/ >/dev/null

  if [ -d "${setup_path}/server/panel/old_data" ]; then
    mv -f ${setup_path}/server/panel/old_data/default.db ${setup_path}/server/panel/data/default.db
    mv -f ${setup_path}/server/panel/old_data/system.db ${setup_path}/server/panel/data/system.db
    mv -f ${setup_path}/server/panel/old_data/port.pl ${setup_path}/server/panel/data/port.pl
    mv -f ${setup_path}/server/panel/old_data/admin_path.pl ${setup_path}/server/panel/data/admin_path.pl
    if [ -d "/${setup_path}/server/panel/old_data" ]; then
      rm -rf ${setup_path}/server/panel/old_data
    fi
  fi

  if [ ! -f ${setup_path}/server/panel/tools.py ] || [ ! -f ${setup_path}/server/panel/BT-Panel ]; then
    ls -lh panel.zip
    Red_Error "ERROR: Failed to download, please try install again!" "ERROR: 下载失败，请尝试重新安装！"
  fi

  rm -f panel.zip
  rm -f ${setup_path}/server/panel/class/*.pyc
  rm -f ${setup_path}/server/panel/*.pyc

  chmod +x /etc/init.d/bt
  chmod -R 600 ${setup_path}/server/panel
  chmod -R +x ${setup_path}/server/panel/script
  ln -sf /etc/init.d/bt /usr/bin/bt
  echo "${panelPort}" >${setup_path}/server/panel/data/port.pl
  wget -O /etc/init.d/bt ${download_Url}/install/src/bt7.init -T 10
  wget -O /www/server/panel/init.sh ${download_Url}/install/src/bt7.init -T 10
  wget -O /www/server/panel/data/softList.conf ${download_Url}/install/conf/softList.conf

  if [ ! -f "${setup_path}/server/panel/data/installCount.pl" ]; then
    echo "1 $(date)" >${setup_path}/server/panel/data/installCount.pl
  elif [ -f "${setup_path}/server/panel/data/installCount.pl" ]; then
    INSTALL_COUNT=$(cat ${setup_path}/server/panel/data/installCount.pl | awk '{last=$1} END {print last}')
    echo "$((INSTALL_COUNT + 1)) $(date)" >>${setup_path}/server/panel/data/installCount.pl
  fi

}
#「设置面板」
Set_Bt_Panel() {
  Run_User="www"
  wwwUser=$(cat /etc/passwd | cut -d ":" -f 1 | grep ^www$)
  if [ "${wwwUser}" != "www" ]; then
    groupadd ${Run_User}
    useradd -s /sbin/nologin -g ${Run_User} ${Run_User}
  fi

  password=$(cat /dev/urandom | head -n 16 | md5sum | head -c 8)
  if [ "$PANEL_PASSWORD" ]; then
    password=$PANEL_PASSWORD
  fi
  sleep 1
  admin_auth="/www/server/panel/data/admin_path.pl"
  if [ "${SAFE_PATH}" ]; then
    auth_path=$SAFE_PATH
    echo "/${auth_path}" >${admin_auth}
  fi
  if [ ! -f ${admin_auth} ]; then
    auth_path=$(cat /dev/urandom | head -n 16 | md5sum | head -c 8)
    echo "/${auth_path}" >${admin_auth}
  fi
  auth_path=$(cat /dev/urandom | head -n 16 | md5sum | head -c 8)
  echo "/${auth_path}" >${admin_auth}
  chmod -R 700 $pyenv_path/pyenv/bin
  auth_path=$(cat ${admin_auth})
  cd ${setup_path}/server/panel/
  if [ "$SET_SSL" == true ]; then
    btpip install -I pyOpenSSl
    btpython /www/server/panel/tools.py ssl
  fi
  /etc/init.d/bt start
  $python_bin -m py_compile tools.py
  $python_bin tools.py username
  username=$($python_bin tools.py panel ${password})
  if [ "$PANEL_USER" ]; then
    username=$PANEL_USER
  fi
  cd ~
  echo "${password}" >${setup_path}/server/panel/default.pl
  chmod 600 ${setup_path}/server/panel/default.pl
  sleep 3
  /etc/init.d/bt restart
  sleep 3
  isStart=$(ps aux | grep 'BT-Panel' | grep -v grep | awk '{print $2}')
  LOCAL_CURL=$(curl 127.0.0.1:${panelPort}/login 2>&1 | grep -i html)
  if [ -z "${isStart}" ] && [ -z "${LOCAL_CURL}" ]; then
    /etc/init.d/bt 22
    cd /www/server/panel/pyenv/bin
    touch t.pl
    ls -al python3.7 python
    lsattr python3.7 python
    Red_Error "ERROR: The BT-Panel service startup failed." "ERROR: 启动失败"
  fi

  if [ "$PANEL_USER" ]; then
    cd ${setup_path}/server/panel/
    btpython -c 'import tools;tools.set_panel_username("'$PANEL_USER'")'
    cd ~
  fi
}
#「设置防火墙」
Set_Firewall() {
  sshPort=$(cat /etc/ssh/sshd_config | grep 'Port ' | awk '{print $2}')
  if [ "${PM}" = "apt-get" ]; then
    apt-get install -y ufw
    if [ -f "/usr/sbin/ufw" ]; then
      ufw allow 20/tcp
      ufw allow 21/tcp
      ufw allow 22/tcp
      ufw allow 80/tcp
      ufw allow 443/tcp
      ufw allow 888/tcp
      ufw allow ${panelPort}/tcp
      ufw allow ${sshPort}/tcp
      ufw allow 39000:40000/tcp
      ufw_status=$(ufw status)
      echo y | ufw enable
      ufw default deny
      ufw reload
    fi
  else
    if [ -f "/etc/init.d/iptables" ]; then
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 20 -j ACCEPT
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 21 -j ACCEPT
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport ${panelPort} -j ACCEPT
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport ${sshPort} -j ACCEPT
      iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 39000:40000 -j ACCEPT
      #iptables -I INPUT -p tcp -m state --state NEW -m udp --dport 39000:40000 -j ACCEPT
      iptables -A INPUT -p icmp --icmp-type any -j ACCEPT
      iptables -A INPUT -s localhost -d localhost -j ACCEPT
      iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -P INPUT DROP
      service iptables save
      sed -i "s#IPTABLES_MODULES=\"\"#IPTABLES_MODULES=\"ip_conntrack_netbios_ns ip_conntrack_ftp ip_nat_ftp\"#" /etc/sysconfig/iptables-config
      iptables_status=$(service iptables status | grep 'not running')
      if [ "${iptables_status}" == '' ]; then
        service iptables restart
      fi
    else
      AliyunCheck=$(cat /etc/redhat-release | grep "Aliyun Linux")
      [ "${AliyunCheck}" ] && return
      yum install firewalld -y
      [ "${Centos8Check}" ] && yum reinstall python3-six -y
      systemctl enable firewalld
      systemctl start firewalld
      firewall-cmd --set-default-zone=public >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=20/tcp >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=21/tcp >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=22/tcp >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=80/tcp >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=443/tcp >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=${panelPort}/tcp >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=${sshPort}/tcp >/dev/null 2>&1
      firewall-cmd --permanent --zone=public --add-port=39000-40000/tcp >/dev/null 2>&1
      #firewall-cmd --permanent --zone=public --add-port=39000-40000/udp > /dev/null 2>&1
      firewall-cmd --reload
    fi
  fi
}
#「获取服务器地址」
Get_Ip_Address() {
  getIpAddress=""
  getIpAddress=$(curl -s myip.ipip.net | grep "IP：" | awk -F' ' '{print $2}' | awk -F'：' '{print $2}')

  ipv4Check=$($python_bin -c "import re; print(re.match('^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$','${getIpAddress}'))")
  if [ "${ipv4Check}" == "None" ]; then
    ipv6Address=$(echo ${getIpAddress} | tr -d "[]")
    ipv6Check=$($python_bin -c "import re; print(re.match('^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$','${ipv6Address}'))")
    if [ "${ipv6Check}" == "None" ]; then
      getIpAddress="SERVER_IP"
    else
      echo "True" >${setup_path}/server/panel/data/ipv6.pl
      sleep 1
      /etc/init.d/bt restart
    fi
  fi

  if [ "${getIpAddress}" != "SERVER_IP" ]; then
    echo "${getIpAddress}" >${setup_path}/server/panel/data/iplist.txt
  fi
  LOCAL_IP=$(ip addr | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -E -v "^127\.|^255\.|^0\." | head -n 1)
}


# 安装程序
Install_Main() {
  Set_Ssl
  startTime=$(date +%s)
  Lock_Clear
  System_Check
  Get_Pack_Manager
  get_node_url

  MEM_TOTAL=$(free -g | grep Mem | awk '{print $2}')
  #判断如果内存交换的总量 小于或等于 1GB 则设置Swap
  if [ "${MEM_TOTAL}" -le "1" ]; then
    Auto_Swap
  fi

  if [ "${PM}" = "yum" ]; then
    Install_RPM_Pack
  elif [ "${PM}" = "apt-get" ]; then
    Install_Deb_Pack
  fi

  Install_Python_Lib
  Install_Bt

  Set_Bt_Panel
  Service_Add
  Set_Firewall

  Get_Ip_Address
}

echo "
+----------------------------------------------------------------------
| QQ-WebPanel FOR CentOS/Ubuntu/Debian
+----------------------------------------------------------------------
| Copyright © 2015-2099 BT-SOFT(https://www.bt.cn) All rights reserved.
+----------------------------------------------------------------------
| The WebPanel URL will be http://SERVER_IP:8888 when installed.
+----------------------------------------------------------------------
| 为了您的正常使用，请确保使用全新或纯净的系统安装面板，不支持已部署项目/环境的系统安装
+----------------------------------------------------------------------
"

# 「接收用户参数：--user[-u]:用户名 --password[-p]:密码 --port[-p]:端口 --safe-path:安全入口码 -y:全部同意 其他:未知」
while [ ${#} -gt 0 ]; do
  echo {$1}
  case $1 in
  -u | --user)
    PANEL_USER=$2
    shift 1
    ;;
  -p | --password)
    PANEL_PASSWORD=$2
    shift 1
    ;;
  -P | --port)
    PANEL_PORT=$2
    shift 1
    ;;
  --safe-path)
    SAFE_PATH=$2
    shift 1
    ;;
  -y)
    go="y"
    ;;
  *)
    IDC_CODE=$1
    ;;
  esac
  shift 1
done

#「判断是否允许接下来的操作」
while [ "$go" != 'y' ] && [ "$go" != 'n' ]; do
  read -p "您想把面板安装到 $setup_path 目录吗?(y/n): " go
done

if [ "$go" == 'n' ]; then
  exit
fi

#「判断是否位 Arch Linux 系统 如果是更新包」
ARCH_LINUX=$(cat /etc/os-release | grep "Arch Linux")
if [ "${ARCH_LINUX}" ] && [ -f "/usr/bin/pacman" ]; then
  pacman -Sy
  pacman -S curl wget unzip firewalld openssl pkg-config make gcc cmake libxml2 libxslt libvpx gd libsodium oniguruma sqlite libzip autoconf inetutils sudo --noconfirm
fi
# 「开始执行安装程序」
Install_Main

PANEL_SSL=$(cat /www/server/panel/data/ssl.pl 2>/dev/null)
if [ "${PANEL_SSL}" == "True" ]; then
  HTTP_S="https"
else
  HTTP_S="http"
fi

echo >/www/server/panel/data/bind.pl
echo -e "=================================================================="
echo -e "\033[32mCongratulations! Installed successfully!\033[0m"
echo -e "=================================================================="
echo "外网面板地址: ${HTTP_S}://${getIpAddress}:${panelPort}${auth_path}"
echo "内网面板地址: ${HTTP_S}://${LOCAL_IP}:${panelPort}${auth_path}"
echo -e "username: $username"
echo -e "password: $password"
echo -e "\033[33mIf you cannot access the panel,\033[0m"
echo -e "\033[33mrelease the following panel port [${panelPort}] in the security group\033[0m"
echo -e "\033[33m若无法访问面板，请检查防火墙/安全组是否有放行面板[${panelPort}]端口\033[0m"
if [ "${HTTP_S}" == "https" ]; then
  echo -e "\033[33m因已开启面板自签证书，访问面板会提示不匹配证书，请参考以下链接配置证书\033[0m"
fi
echo -e "=================================================================="

endTime=$(date +%s)
((outTime = ($endTime - $startTime) / 60))
echo -e "Time consumed:\033[32m $outTime \033[0mMinute!"
sed -i "s|bind_user == 'True'|bind_user == 'XXXX'|" /www/server/panel/BTPanel/static/js/index.js && rm -f /www/server/panel/data/bind.pl
echo -e "绑定手机去除完成！！"


sed -i "/p = threading.Thread(target=check_panel_msg)/, /p.start()/d" /www/server/panel/task.py
sed -i '/\"check_panel_msg\":/d' /www/server/panel/task.py
echo -e "去除消息推送完成！！"

#这个功能会每隔10分钟执行一次，用途是获取新面板文件替换本地旧面板文件
sed -i "/p = threading.Thread(target=check_files_panel)/, /p.start()/d" /www/server/panel/task.py
sed -i '/\"check_files_panel\":/d' /www/server/panel/task.py
#删除接口文件防止其他加密文件调用（可能会改为内置）
rm -f /www/server/panel/script/check_files.py
echo -e "去除文件校验完成！！"

sed -i "/p = threading.Thread(target=update_software_list)/, /p.start()/d" /www/server/panel/task.py
sed -i '/\"update_software_list\":/d' /www/server/panel/task.py
sed -i '/self.get_cloud_list_status/d' /www/server/panel/class/panelPlugin.py
sed -i '/PluginLoader.daemon_task()/d' /www/server/panel/task.py
#sed -i '/PluginLoader.daemon_panel()/d' /www/server/panel/task.py
echo -e "去除云端验证！！"

echo "True" > /www/server/panel/data/not_recommend.pl
echo "True" > /www/server/panel/data/not_workorder.pl
echo -e "关闭活动推荐与在线客服"

sed -i '/def get_pay_type(self,get):/a \ \ \ \ \ \ \ \ return [];' /www/server/panel/class/ajax.py
echo -e "关闭首页软件推荐与广告"

Layout_file="/www/server/panel/BTPanel/templates/default/layout.html";
JS_file="/www/server/panel/BTPanel/static/bt.js";
if [ `grep -c "<script src=\"/static/bt.js\"></script>" $Layout_file` -eq '0' ];then
	sed -i '/{% block scripts %} {% endblock %}/a <script src="/static/bt.js"></script>' $Layout_file;
fi;
wget -q https://gitee.com/dayu777/open_shell/raw/main/bt/bt.js -O $JS_file;
echo -e "已去除各种计算题与延时等待"

#每隔10分钟执行一次，用于检测是不是破解版，该命令直接删除链接，使返回为空，输出False
#该接口返回False 与True均不影响面板，返回True后续代码还会对返回的其他字段数据做处理。
#直接返回False类似于无法访问宝塔的接口，因此不会执行后面的一大堆代码。
#锁面板我记得是接口直接返回文本，然后代码输出文本提示锁面板。
sed -i '/self._check_url/d' /www/server/panel/class/panelPlugin.py
echo -e "关闭拉黑检测与提示"

sed -i "/^logs_analysis()/d" /www/server/panel/script/site_task.py
sed -i "s/run_thread(cloud_check_domain,(domain,))/return/" /www/server/panel/class/public.py
echo -e "关闭面板日志与绑定域名上报"

# #宝塔接口返回force = 1的时候会强制更新你的面板 7.7.0版本的用户推荐处理一下
# sed -i "/#是否执行升级程序/a \ \ \ \ \ \ \ \ \ \ \ \ updateInfo[\'force\'] = False;" /www/server/panel/class/ajax.py
# rm -f /www/server/panel/data/autoUpdate.pl
# echo -e "关闭面板强制更新"

# 设置本地列表文件不过期

sed -i "/plugin_timeout = 86400/d" /www/server/panel/class/public.py

sed -i "/list_body = None/a\    plugin_timeout = 0;" /www/server/panel/class/public.py

chattr +i /www/server/panel/data/plugin.json


#重启面板命令
/etc/init.d/bt restart
