#!/bin/bash

# 显示菜单选项
echo "请选择要执行的操作："
echo "1. rclone工具箱"
echo "2. 安装纯净宝塔面板"
echo "3. 科技lion一键脚本工具"
echo "4. 证书SSL申请"
echo "5. docker安装卸载"
echo "6. docker软件应用"
echo "7. 测试脚本合集"
echo "8. 系统工具"
echo "9. 其他工具"
echo "10. 一键开启BBR"
echo "11. 一键重装系统(DD)"
echo "12. 设置脚本快捷键"
echo "0. 退出"

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
        # 执行一键开启BBR脚本操作
		clear
        curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/bbr.sh && chmod +x bbr.sh && ./bbr.sh
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
        # 退出
        echo "退出脚本。"
        exit 0
        ;;
    *)
        echo "无效的操作选择。"
        ;;
esac