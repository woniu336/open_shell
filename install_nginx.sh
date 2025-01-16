#!/bin/bash
# 颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 清屏函数
clear_screen() {
    clear
}

# 显示菜单
show_menu() {
    clear_screen
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}              Nginx 管理脚本${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  1)${NC} 安装 Nginx"
    echo -e "${GREEN}  2)${NC} 卸载 Nginx"
    echo -e "${GREEN}  3)${NC} 重启 Nginx"
    echo -e "${GREEN}  4)${NC} 查看 Nginx 状态"
    echo -e "${GREEN}  0)${NC} 退出脚本"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}请输入选项 [0-4]:${NC} "
}

# 卸载Nginx函数
uninstall_nginx() {
    echo -e "${YELLOW}正在卸载 Nginx...${NC}"
    # 停止服务
    systemctl is-active nginx >/dev/null 2>&1 && sudo systemctl stop nginx
    systemctl is-enabled nginx >/dev/null 2>&1 && sudo systemctl disable nginx
    
    # 删除文件和目录
    sudo rm -f /etc/systemd/system/nginx.service
    sudo rm -rf /etc/systemd/system/nginx.service.d
    sudo rm -f /usr/sbin/nginx
    sudo rm -rf /usr/local/nginx
    sudo rm -rf /etc/nginx
    sudo rm -rf /var/log/nginx
    sudo rm -rf /run/nginx
    sudo rm -rf /usr/share/nginx
    
    # 清理源码目录
    sudo rm -rf /usr/local/src/nginx-*
    
    # 删除用户（如果存在）
    id nginx >/dev/null 2>&1 && sudo userdel nginx
    
    # 重新加载systemd
    sudo systemctl daemon-reload
    
    # 查找并显示可能遗留的nginx相关文件
    echo -e "${YELLOW}检查是否有遗留文件...${NC}"
    remaining_files=$(find / -name "*nginx*" 2>/dev/null)
    if [ ! -z "$remaining_files" ]; then
        echo -e "${YELLOW}发现以下nginx相关文件，建议手动检查并决定是否删除：${NC}"
        echo "$remaining_files"
    fi
    
    echo -e "${GREEN}Nginx 已成功卸载${NC}"
}

# 重启Nginx函数
restart_nginx() {
    echo -e "${YELLOW}正在重启 Nginx...${NC}"
    # 检查配置文件语法
    if ! nginx -t; then
        echo -e "${RED}Nginx配置文件检查失败${NC}"
        return 1
    fi
    
    # 检查80端口
    port_check=$(netstat -tulnp | grep ':80 ')
    if [ ! -z "$port_check" ]; then
        if echo "$port_check" | grep -v nginx >/dev/null 2>&1; then
            echo -e "${RED}警告: 80端口被其他进程占用${NC}"
            echo -e "${YELLOW}占用端口的进程信息：${NC}"
            echo "$port_check" | grep -v nginx
            return 1
        else
            echo -e "${GREEN}80端口被当前Nginx进程占用，继续重启操作...${NC}"
        fi
    fi
    
    sudo systemctl restart nginx
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Nginx 重启成功${NC}"
        # 使用新的验证函数
        if verify_nginx_running; then
            echo -e "${GREEN}Nginx服务已完全恢复${NC}"
        else
            echo -e "${RED}Nginx重启后验证失败，请检查配置和日志${NC}"
            return 1
        fi
    else
        echo -e "${RED}Nginx 重启失败${NC}"
        echo -e "${YELLOW}查看详细错误信息：${NC}"
        sudo systemctl status nginx
        return 1
    fi
}

# 检查Nginx状态函数
check_nginx_status() {
    echo -e "${YELLOW}Nginx 状态:${NC}"
    sudo systemctl status nginx
    echo ""
    read -p "按回车键继续..."
}

ck_ok()
{
        if [ $? -ne 0 ]
        then
                echo "$1 error."
                exit 1
        fi
}

download_ng()
{
    cd  /usr/local/src
    if [ -f nginx-1.27.3.tar.gz ]
    then
        echo "当前目录已经存在nginx-1.27.3.tar.gz"
    else
        sudo curl -O http://nginx.org/download/nginx-1.27.3.tar.gz
        ck_ok "下载Nginx"
    fi

    # 下载 headers-more-nginx-module 模块
    if [ -d "headers-more-nginx-module-0.34" ]
    then
        echo "当前目录已经存在headers-more-nginx-module"
    else
        echo "下载headers-more-nginx-module模块"
        sudo wget https://github.com/openresty/headers-more-nginx-module/archive/v0.34.tar.gz -O headers-more-nginx-module.tar.gz
        ck_ok "下载headers-more-nginx-module模块"
        sudo tar -xzf headers-more-nginx-module.tar.gz
        ck_ok "解压headers-more-nginx-module模块"
        sudo rm -f headers-more-nginx-module.tar.gz
    fi
}

# 验证Nginx是否正常运行
verify_nginx_running() {
    echo -e "${YELLOW}正在验证Nginx服务状态...${NC}"
    
    # 检查进程是否运行
    if ! pgrep nginx >/dev/null; then
        echo -e "${RED}Nginx进程未运行${NC}"
        return 1
    fi
    
    # 检查端口是否正常监听
    if ! netstat -tuln | grep -q ':80 '; then
        echo -e "${RED}Nginx未在80端口监听${NC}"
        return 1
    fi

    # 检查配置文件语法
    if ! nginx -t &>/dev/null; then
        echo -e "${RED}Nginx配置文件检查失败${NC}"
        nginx -t
        return 1
    fi

    # 检查服务状态
    if ! systemctl is-active nginx >/dev/null 2>&1; then
        echo -e "${RED}Nginx服务未处于活动状态${NC}"
        return 1
    fi

    echo -e "${GREEN}Nginx安装成功并正常运行！${NC}"
    echo -e "${GREEN}提示：由于安全配置，直接访问IP将返回444状态码，这是预期行为。${NC}"
    return 0
}

install_ng()
{
    cd /usr/local/src
    echo "解压Nginx"
    sudo tar zxf nginx-1.27.3.tar.gz
    ck_ok "解压Nginx"
    cd nginx-1.27.3

    echo "安装依赖"
    if which yum >/dev/null 2>&1
    then
        ## RHEL/Rocky
        for pkg in gcc make pcre-devel zlib-devel openssl-devel
        do
            if ! rpm -q $pkg >/dev/null 2>&1
            then
                sudo yum install -y $pkg
                ck_ok "yum 安装$pkg"
            else
                echo "$pkg已经安装"
            fi
        done
    fi

    if which apt >/dev/null 2>&1
    then
        ##ubuntu
        for pkg in make libpcre++-dev  libssl-dev  zlib1g-dev
        do
            if ! dpkg -l $pkg >/dev/null 2>&1
            then
                sudo apt install -y $pkg
                ck_ok "apt 安装$pkg"
            else
                echo "$pkg已经安装"
            fi
        done
    fi

    # 创建nginx用户（如果不存在）
    echo "创建nginx用户"
    if ! id -u nginx >/dev/null 2>&1; then
        sudo useradd -r -s /sbin/nologin nginx
        ck_ok "创建nginx用户"
    else
        echo "nginx用户已存在"
    fi

    echo "configure Nginx"
    sudo ./configure --prefix=/usr/local/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_v2_module \
    --with-http_gzip_static_module \
    --with-poll_module \
    --with-http_realip_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-http_sub_module \
    --with-threads \
    --add-module=/usr/local/src/headers-more-nginx-module-0.34
    ck_ok "Configure Nginx"

    echo "编译和安装"
    sudo make && sudo make install
    ck_ok "编译和安装"

    # 创建必要的目录
    echo "创建必要的目录"
    sudo mkdir -p /run/nginx
    sudo mkdir -p /var/log/nginx
    sudo mkdir -p /etc/nginx/conf.d
    sudo mkdir -p /data/wwwlogs/
    sudo mkdir -p /usr/local/nginx/logs
    sudo mkdir -p /usr/share/nginx/html
    sudo mkdir -p /usr/local/nginx/cache/fastcgi
    sudo mkdir -p /usr/local/nginx/cache/proxy
    sudo mkdir -p /etc/nginx/certs
    
    # 设置目录权限
    echo "设置目录权限"
    sudo chown -R nginx:nginx /run/nginx
    sudo chmod 755 /run/nginx
    sudo chown -R nginx:nginx /var/log/nginx
    sudo chown -R nginx:nginx /data/wwwlogs
    sudo chown -R nginx:nginx /usr/local/nginx/logs
    sudo chown -R nginx:nginx /usr/share/nginx/html
    sudo chown -R nginx:nginx /usr/local/nginx/cache
    sudo chown -R nginx:nginx /etc/nginx/certs
    
    # 生成SSL证书和密钥
    echo "生成SSL证书和密钥"
    if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        sudo openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -keyout /etc/nginx/certs/default_server.key -out /etc/nginx/certs/default_server.crt -days 5475 -subj "/C=US/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name"
    else
        sudo openssl genpkey -algorithm Ed25519 -out /etc/nginx/certs/default_server.key
        sudo openssl req -x509 -key /etc/nginx/certs/default_server.key -out /etc/nginx/certs/default_server.crt -days 5475 -subj "/C=US/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name"
    fi
    
    # 生成SSL会话票据密钥
    sudo openssl rand -out /etc/nginx/certs/ticket12.key 48
    sudo openssl rand -out /etc/nginx/certs/ticket13.key 80
    
    # 设置证书权限
    sudo chmod 600 /etc/nginx/certs/*.key
    sudo chmod 644 /etc/nginx/certs/*.crt
    sudo chown nginx:nginx /etc/nginx/certs/*
    
    # 下载默认配置文件
    echo "下载默认配置文件"
    sudo curl -o /etc/nginx/conf.d/default.conf https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/default.conf
    ck_ok "下载default.conf"
    sudo chown nginx:nginx /etc/nginx/conf.d/default.conf
    sudo chmod 644 /etc/nginx/conf.d/default.conf
    
    # 创建并设置日志文件权限
    echo "创建并设置日志文件权限"
    sudo touch /usr/local/nginx/logs/error.log
    sudo touch /usr/local/nginx/logs/access.log
    sudo touch /var/log/nginx/error.log
    sudo touch /var/log/nginx/access.log
    sudo chown nginx:nginx /usr/local/nginx/logs/error.log
    sudo chown nginx:nginx /usr/local/nginx/logs/access.log
    sudo chown nginx:nginx /var/log/nginx/error.log
    sudo chown nginx:nginx /var/log/nginx/access.log
    
    # 创建并设置PID文件权限
    echo "创建并设置PID文件权限"
    sudo touch /run/nginx/nginx.pid
    sudo chown nginx:nginx /run/nginx/nginx.pid
    sudo chmod 644 /run/nginx/nginx.pid
    
    # 创建默认首页
    echo "创建默认首页"
    echo "<h1>Welcome to Nginx!</h1>" | sudo tee /usr/share/nginx/html/index.html > /dev/null
    sudo chown nginx:nginx /usr/share/nginx/html/index.html
    
    # 下载自定义nginx配置文件
    echo "下载自定义nginx配置文件"
    sudo curl -o /etc/nginx/nginx.conf https://raw.githubusercontent.com/woniu336/open_shell/main/nginx/nginx.conf
    ck_ok "下载nginx配置文件"
    
    # 设置配置文件权限
    sudo chown nginx:nginx /etc/nginx/nginx.conf
    sudo chmod 644 /etc/nginx/nginx.conf

    # 检查80端口是否被占用
    if netstat -tuln | grep ':80 ' >/dev/null 2>&1; then
        echo -e "${RED}警告: 80端口已被占用，请检查并释放端口后重试${NC}"
        netstat -tuln | grep ':80 '
        exit 1
    fi

    if [ -f /usr/sbin/nginx ]
    then
        echo "已经存在nginx软连接"
    else
        echo "配置软连接"
        sudo ln -s /usr/local/nginx/sbin/nginx /usr/sbin/nginx
        ck_ok "配置软连接"
    fi
    
    # 编辑systemd服务管理脚本
    echo "编辑systemd服务管理脚本"
    cat > /tmp/nginx.service <<EOF
[Unit]
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network.target remote-fs.target nss-lookup.target
StartLimitIntervalSec=0

[Service]
Type=forking
PIDFile=/run/nginx/nginx.pid
RuntimeDirectory=nginx
RuntimeDirectoryMode=0755

# 确保PID文件目录存在且具有正确的权限
ExecStartPre=/bin/mkdir -p /run/nginx
ExecStartPre=/bin/chown root:root /run/nginx
ExecStartPre=/bin/chmod 755 /run/nginx

# 删除旧的PID文件
ExecStartPre=/bin/rm -f /run/nginx/nginx.pid

# 其他准备工作
ExecStartPre=/bin/mkdir -p /usr/local/nginx/logs
ExecStartPre=/bin/mkdir -p /var/log/nginx
ExecStartPre=/bin/chown -R nginx:nginx /usr/local/nginx/logs
ExecStartPre=/bin/chown -R nginx:nginx /var/log/nginx
ExecStartPre=/usr/local/nginx/sbin/nginx -t -c /etc/nginx/nginx.conf

# 启动Nginx
ExecStart=/usr/local/nginx/sbin/nginx -c /etc/nginx/nginx.conf
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID

# 进程控制
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=mixed
PrivateTmp=true

# 文件描述符限制
LimitNOFILE=1000000
LimitNPROC=1000000
LimitCORE=1000000

# 重启策略
Restart=always
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

    # 移动服务文件到正确位置并设置权限
    sudo mkdir -p /etc/systemd/system
    sudo /bin/mv /tmp/nginx.service /etc/systemd/system/nginx.service
    sudo chmod 644 /etc/systemd/system/nginx.service
    ck_ok "编辑nginx.service"

    # 创建systemd override配置
    echo "创建systemd override配置"
    sudo mkdir -p /etc/systemd/system/nginx.service.d
    echo -e "[Service]\nExecStartPost=/bin/sleep 0.1" | sudo tee /etc/systemd/system/nginx.service.d/override.conf > /dev/null
    sudo chmod 644 /etc/systemd/system/nginx.service.d/override.conf
    ck_ok "创建override.conf"

    echo "加载服务"
    sudo systemctl unmask nginx.service
    sudo systemctl daemon-reload
    
    # 测试nginx配置
    echo "测试Nginx配置"
    if ! sudo nginx -t; then
        echo -e "${RED}Nginx配置测试失败${NC}"
        exit 1
    fi
    
    sudo systemctl enable nginx
    echo "启动Nginx"
    sudo systemctl start nginx
    if [ $? -ne 0 ]; then
        echo -e "${RED}Nginx启动失败，请检查日志：${NC}"
        sudo systemctl status nginx
        sudo journalctl -xe
        exit 1
    fi
    ck_ok "启动Nginx"
    
    # 验证Nginx是否正常运行
    sleep 2
    if verify_nginx_running; then
        echo -e "${GREEN}Nginx部署完成！${NC}"
    else
        echo -e "${RED}Nginx安装完成但验证失败，请查看上述错误信息进行排查${NC}"
        exit 1
    fi
}

# 主循环
while true; do
    show_menu
    read -r choice
    case $choice in
        1)
            if command -v nginx >/dev/null 2>&1; then
                echo -e "${RED}Nginx已经安装，请先卸载再重新安装。${NC}"
                read -p "按回车键继续..."
                continue
            fi
            echo -e "${YELLOW}开始安装 Nginx...${NC}"
            download_ng
            install_ng
            echo -e "${GREEN}Nginx 安装完成！${NC}"
            read -p "按回车键继续..."
            ;;
        2)
            if ! command -v nginx >/dev/null 2>&1; then
                echo -e "${RED}Nginx未安装！${NC}"
                read -p "按回车键继续..."
                continue
            fi
            echo -n -e "${YELLOW}确定要卸载 Nginx 吗？[y/N]:${NC} "
            read -r confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                uninstall_nginx
            fi
            read -p "按回车键继续..."
            ;;
        3)
            if ! command -v nginx >/dev/null 2>&1; then
                echo -e "${RED}Nginx未安装！${NC}"
                read -p "按回车键继续..."
                continue
            fi
            restart_nginx
            read -p "按回车键继续..."
            ;;
        4)
            if ! command -v nginx >/dev/null 2>&1; then
                echo -e "${RED}Nginx未安装！${NC}"
                read -p "按回车键继续..."
                continue
            fi
            check_nginx_status
            ;;
        0)
            clear_screen
            echo -e "${GREEN}感谢使用，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择${NC}"
            read -p "按回车键继续..."
            ;;
    esac
done 