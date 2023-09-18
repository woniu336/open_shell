#!/bin/bash

while true; do
    clear
    echo "请选择要执行的系统重装脚本："
    echo "1. leitbogioro脚本"
    echo "2. 萌咖脚本"
    echo "3. 综合脚本"
    echo "0. 退出"
    read -p "请输入选项: " reinstall_choice

    case $reinstall_choice in
        1)
            wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
            echo "请选择要重装的系统："
            echo "a. Debian 11"
            echo "b. Ubuntu 20.04"
            echo "c. CentOS 7"
            read -p "请输入系统编号: " os_choice

            case $os_choice in
                a)
                    # 提示用户名、密码和SSH端口
                    echo "您选择了执行 Debian 11 重装操作。"
                    echo "用户名: root"
                    echo "密码: LeitboGi0ro"
                    echo "SSH端口: 22"
                    read -p "是否确定要继续执行？(y/n): " confirm

                    if [ "$confirm" == "y" ]; then
                        bash InstallNET.sh -debian 11
                    else
                        echo "已取消操作。"
                    fi
                    ;;
                b)
                    # 提示用户名、密码和SSH端口
                    echo "您选择了执行 Ubuntu 20.04 重装操作。"
                    echo "用户名: root"
                    echo "密码: LeitboGi0ro"
                    echo "SSH端口: 22"
                    read -p "是否确定要继续执行？(y/n): " confirm

                    if [ "$confirm" == "y" ]; then
                        bash InstallNET.sh -ubuntu 20.04
                    else
                        echo "已取消操作。"
                    fi
                    ;;
                c)
                    # 提示用户名、密码和SSH端口
                    echo "您选择了执行 CentOS 7 重装操作。"
                    echo "用户名: root"
                    echo "密码: LeitboGi0ro"
                    echo "SSH端口: 22"
                    read -p "是否确定要继续执行？(y/n): " confirm

                    if [ "$confirm" == "y" ]; then
                        bash InstallNET.sh -centos 7
                    else
                        echo "已取消操作。"
                    fi
                    ;;
                *)
                    echo "无效的系统选择。"
                    ;;
            esac
            ;;
        2)
            # 提示用户选择系统
            echo "请选择要执行的系统重装脚本："
            echo "a. Debian 11"
            echo "b. Ubuntu 20.04"
            echo "c. 退出"
            read -p "请输入系统编号: " os_choice

            case $os_choice in
                a)
                    # 提示用户名、密码和SSH端口
                    echo "您选择了执行 Debian 11 重装操作。"
                    echo "用户名: root"
                    echo "密码: 123456"
                    echo "SSH端口: 22"
                    read -p "是否确定要继续执行？(y/n): " confirm

                    if [ "$confirm" == "y" ]; then
                        bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') -d 11 -v 64 -p 123456 -port 22
                    else
                        echo "已取消操作。"
                    fi
                    ;;
                b)
                    # 提示用户名、密码和SSH端口
                    echo "您选择了执行 Ubuntu 20.04 重装操作。"
                    echo "用户名: root"
                    echo "密码: 123456"
                    echo "SSH端口: 22"
                    read -p "是否确定要继续执行？(y/n): " confirm

                    if [ "$confirm" == "y" ]; then
                        bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') -u 20.04 -v 64 -p 123456 -port 22
                    else
                        echo "已取消操作。"
                    fi
                    ;;
                c)
                    break
                    ;;
                *)
                    echo "无效的系统选择。"
                    ;;
            esac
            ;;
        3)
            # 提示默认密码
            echo "正在执行脚本3的操作..."
            echo "默认密码: Pwd@CentOS 或 Pwd@Linux"
            wget --no-check-certificate -O AutoReinstall.sh https://git.io/AutoReinstall.sh && bash AutoReinstall.sh
            ;;
        0)
            break
            ;;
        *)
            echo "无效的选项，请重新输入。"
            ;;
    esac
done