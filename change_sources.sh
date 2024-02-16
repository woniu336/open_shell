#!/bin/bash

# 备份原始源列表
sudo cp /etc/apt/sources.list /etc/apt/old_sources.list

# 创建一个临时文件来保存新的源列表内容
tmp_file=$(mktemp)

# 清空源列表文件
sudo truncate -s 0 /etc/apt/sources.list

# 将新的源列表内容写入临时文件
cat <<EOF > "$tmp_file"
deb https://mirrors.ustc.edu.cn/ubuntu/ focal main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ focal-updates main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ focal-backports main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ focal-security main restricted universe multiverse
EOF

# 使用临时文件替换源列表文件
sudo mv "$tmp_file" /etc/apt/sources.list

# 更新软件包
sudo apt update
