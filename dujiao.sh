mkdir -p dujiao
cd dujiao

mkdir storage uploads

chmod 777 storage uploads

mkdir data redis

chmod 777 data redis

function checkStr()
{
s=$1 
if [ ${#s} -lt 5 ] ; then
   echo 域名输入失败
   exit 1
fi

}


read -p "输入IP:8087" domain

echo ${domain}

checkStr ${domain}

mysql_pwd=`echo ${domain}"mysql" | md5sum | awk '{print $1}' `
app_key=`echo ${domain}"app" | md5sum | awk ' {print $1} '`

echo $mysql_pwd
echo $app_key

cat <<EOF >docker-compose.yaml
version: "3"
services:
  faka:
    image: ghcr.io/apocalypsor/dujiaoka:latest
    container_name: faka
    environment:
        # - INSTALL=false
        - INSTALL=true
        # - MODIFY=true
    volumes:
      - ./env.conf:/dujiaoka/.env:rw
      - ./uploads:/dujiaoka/public/uploads:rw
      - ./storage:/dujiaoka/storage:rw
      # - ./favicon.ico:/dujiaoka/public/favicon.ico
    ports:
      - 8087:80
    restart: always
 
  db:
    image: mariadb:focal
    container_name: faka-data
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=${mysql_pwd}
      - MYSQL_DATABASE=dujiaoka
      - MYSQL_USER=dujiaoka
      - MYSQL_PASSWORD=${mysql_pwd}
    volumes:
      - ./data:/var/lib/mysql:rw

  redis:
    image: redis:alpine
    container_name: faka-redis
    restart: always
    volumes:
      - ./redis:/data:rw

touch env.conf
chmod 777 env.conf
cat <<EOF > env.conf

APP_NAME=${app_name}
APP_ENV=local
APP_KEY=${app_key}
APP_DEBUG=false
APP_URL=${app_url}
#ADMIN_HTTPS=true

LOG_CHANNEL=stack

# 数据库配置
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dujiaoka
DB_USERNAME=dujiaoka
DB_PASSWORD=${mysql_pwd}

# redis 配置
REDIS_HOST=redis
REDIS_PASSWORD=
REDIS_PORT=6379

BROADCAST_DRIVER=log
SESSION_DRIVER=file
SESSION_LIFETIME=120


# 缓存配置
# file 为磁盘文件  redis 为内存级别
# redis 为内存需要安装好 redis 服务端并配置
CACHE_DRIVER=redis

# 异步消息队列
# sync 为同步  redis 为异步
# 使用 redis 异步需要安装好 redis 服务端并配置
QUEUE_CONNECTION=redis

# 后台语言
## zh_CN 简体中文
## zh_TW 繁体中文
## en    英文
DUJIAO_ADMIN_LANGUAGE=zh_CN

# 后台登录地址
ADMIN_ROUTE_PREFIX=/admin

EOF

sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

docker-compose up -d 

echo "
   请访问 ${app_url}

   数据库地址: db
   数据库密码: ${mysql_pwd}

   redis地址: redis

   网站url: ${app_url}
   
"