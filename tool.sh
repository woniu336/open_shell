#!/bin/bash

# 显示菜单选项
while true; do
clear
if command -v figlet &> /dev/null; then
    figlet "LUFEI"
else
    echo "LUFEI"
fi

echo -e "\033[96m路飞工具箱 v3.0 （支持 Ubuntu，Debian，Centos系统）\033[0m"
echo "------------------------"
echo "请选择要执行的操作："
echo "1. rclone工具箱"
echo "2. 安装纯净宝塔面板"
echo "3. 科技lion一键脚本工具"
echo "4. 证书SSL申请"
echo "5. docker安装卸载"
echo "6. docker软件应用"
echo -e "\033[33m7. 测试脚本合集 ▶ \033[0m"
echo "8. 系统工具"
echo "9. 其他工具"
echo "10. 网站备份"
echo "11. 一键重装系统(DD)"
echo "12. 设置脚本快捷键"
echo "0. 退出"
echo "------------------------"
# 提示用户选择操作
read -p "请输入操作编号: " choice

# 执行用户选择的操作
case $choice in

	    1)
        # rclone工具箱
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/rclone.sh && chmod +x rclone.sh && ./rclone.sh
        ;;
	    2)
        # 安装纯净宝塔面板
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/bt.sh && chmod +x bt.sh && ./bt.sh
        ;;
	    3)
        # 科技lion一键脚本工具
		clear
        curl -sS -O https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh && chmod +x kejilion.sh && ./kejilion.sh
        ;;
		4)
        # 证书SSL申请
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/ssl.sh && chmod +x ssl.sh && ./ssl.sh
        ;;
	    5)
        # docker安装卸载
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/dockerpro.sh && chmod +x dockerpro.sh && ./dockerpro.sh
        ;;
	    6)
        # docker软件应用      
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/docker666.sh && chmod +x docker666.sh && ./docker666.sh
        ;;
	    7)
        # 测试脚本合集    
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/vps.sh && chmod +x vps.sh && ./vps.sh
        ;;
		8)
        # 系统工具    
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/xitong.sh && chmod +x xitong.sh && ./xitong.sh
        ;;
		9)
        # 其他工具   
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/soso.sh && chmod +x soso.sh && ./soso.sh
        ;;
        10)
        # 执行网站备份
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/s3.sh && chmod +x s3.sh && ./s3.sh
        ;;
        11)
        # 执行一键重装系统(DD)操作
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/vpsnew.sh && chmod +x vpsnew.sh && ./vpsnew.sh
        ;;
	    12)
		# 设置脚本快捷键
        clear
        read -p "请输入你的快捷按键: " kuaijiejian
        echo "alias $kuaijiejian='curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/tool.sh && chmod +x tool.sh && ./tool.sh'" >> ~/.bashrc
        echo "快捷键已添加。请重新启动终端，或运行 'source ~/.bashrc' 以使修改生效。"
        ;;
  0)
    clear
    exit
    ;;

  *)
    echo "无效的输入!"

esac
  echo -e "\033[0;32m操作完成\033[0m"
  echo "按任意键继续..."
  read -n 1 -s -r -p ""
  echo ""
  clear
done