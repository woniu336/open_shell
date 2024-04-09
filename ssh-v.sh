#!/bin/bash

# 创建SSH目录
mkdir -p ~/.ssh
cd ~/.ssh

# 生成SSH密钥
# 生成SSH密钥
echo -e "\e[32m开始愉快之旅吧\e[0m"
echo -e "\e[32m系统将提示您指定密钥对名称: \e[33m一路回车\e[32m 请按Enter继续\e[0m"
echo
ssh-keygen -t ed25519 -C "注释随意"

# 复制公钥到远程服务器
read -p "请输入SSH端口号（默认22）：" ssh_port
ssh_port=${ssh_port:-22}
read -p "请输入服务器IP地址：" server_ip
read -p "请输入用户名（默认root）：" ssh_user

ssh-copy-id -i ~/.ssh/id_ed25519.pub -p $ssh_port $ssh_user@$server_ip

# 修改远程服务器配置
ssh -p $ssh_port $ssh_user@$server_ip << 'EOF'
if grep -q "^#*PubkeyAuthentication\s*no" /etc/ssh/sshd_config; then
    sudo sed -i 's/^#*PubkeyAuthentication\s*no/ PubkeyAuthentication yes/' /etc/ssh/sshd_config
elif grep -q "^#*PubkeyAuthentication\s*yes" /etc/ssh/sshd_config; then
    sudo sed -i 's/^#*PubkeyAuthentication\s*yes/ PubkeyAuthentication yes/' /etc/ssh/sshd_config
else
    echo "PubkeyAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
fi
sudo service ssh restart
exit
EOF

# 提示用户输入别名和ip
read -p "请输入别名：" alias_name

# 检查~/.ssh/config文件是否存在，如果不存在则创建并添加配置
if [ ! -f ~/.ssh/config ]; then
    touch ~/.ssh/config
fi

# 添加别名和IP到~/.ssh/config文件中
if ! grep -q "Host $alias_name" ~/.ssh/config; then
    echo "Host $alias_name" >> ~/.ssh/config
    echo "    Hostname $server_ip" >> ~/.ssh/config
    echo "    IdentityFile ~/.ssh/id_ed25519" >> ~/.ssh/config
    echo "    User $ssh_user" >> ~/.ssh/config  # 更新User为用户输入的用户名
    echo "    Port $ssh_port" >> ~/.ssh/config  # 添加Port选项
fi

# 使用SSH密钥登录
echo -e "\e[33m输入 ssh $alias_name 愉快登录吧\e[0m"
ssh $alias_name

