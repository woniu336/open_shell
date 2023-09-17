#!/bin/bash

# Function to check if Docker is installed
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker没有安装."
    return 1
  else
    echo "Docker已安装."
    return 0
  fi
}

# Function to check if Docker Compose is installed
check_docker_compose() {
  if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose is not installed."
    return 1
  else
    echo "Docker Compose is installed."
    return 0
  fi
}

# Function to confirm an action
confirm_action() {
  read -p "是否继续安装？ (y/n): " answer
  if [ "$answer" != "y" ]; then
    echo "操作已取消."
    return 1
  fi
  return 0
}

# Menu for user to select options
echo "说明【长期更新整合优秀Docker项目】"
echo "1. 更新环境"
echo "2. 安装 Docker"
echo "3. 安装 npm 反向代理"
echo "4. 安装 docker可视化面板"
echo "5. 安装 Uptime Kuma 监控"
echo "0. 退出"

while true; do
  read -p "请选择一个数字序号： " choice
  case $choice in
    1)
      # 更新环境
      sudo apt update -y && sudo apt install -y curl socat wget sudo
      ;;
    2)
      # 安装 Docker
      if check_docker; then
        echo "Docker已安装，跳过安装步骤。"
      else
        curl -fsSL https://get.docker.com | sudo sh
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
      fi
      ;;
    3)
      # 安装 Nginx Proxy Manager
      if check_docker; then
        echo "在安装 npm 反向代理前，请确保端口号: 81, 用户名: admin@example.com 密码: changeme "
        confirm_action
        sudo docker run -d \
          --name=npm \
          -p 80:80 \
          -p 81:81 \
          -p 443:443 \
          -v /home/npm/data:/data \
          -v /home/npm/letsencrypt:/etc/letsencrypt \
          --restart=always \
          jc21/nginx-proxy-manager:latest
      else
        echo "请先安装Docker，然后再安装Nginx Proxy Manager。"
      fi
      ;;
    4)
      # 安装 Portainer-ce
	  if check_docker; then
      echo "在安装 docker可视化面板前，请确保端口号: 9000 "
      confirm_action
      sudo docker run -d --restart=always --name="portainer" -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data 6053537/portainer-ce
	 else
      echo "请先安装Docker，然后再安装 docker可视化面板。"
      fi
      ;;
    5)
      # 安装 Uptime Kuma
	  if check_docker; then
      echo "在安装 Uptime Kuma 前，请确保端口号: 3001 "
      confirm_action
      sudo docker run -d --restart=always -p 3001:3001 -v uptime-kuma:/app/data --name uptime-kuma louislam/uptime-kuma:1
	 else
        echo "请先安装Docker，然后再安装 Uptime Kuma。"
      fi
      ;;
    0)
      # 退出脚本
      exit 0
      ;;
    *)
      echo "无效的选择，请重新输入数字序号。"
      ;;
  esac
done
