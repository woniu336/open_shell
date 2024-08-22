#!/bin/bash

# 下载并赋予执行权限
wget -O convert_to_avif.sh https://raw.githubusercontent.com/woniu336/open_shell/main/convert_to_avif.sh && chmod +x convert_to_avif.sh

# 提示用户输入要处理的目录
read -p "请输入要处理的图像目录路径: " image_directory

# 检查目录是否存在
if [ ! -d "$image_directory" ]; then
  echo "目录不存在，请检查路径是否正确。"
  exit 1
fi

# 运行脚本，指定要处理的目录
./convert_to_avif.sh "$image_directory"