#!/bin/bash

# 颜色变量定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 清屏函数
clear_screen() {
    clear
}

# 显示横幅
show_banner() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}             系统工具箱 v1.0              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
}

# 获取 IP 地址
ip_address() {
    ipv4_address=$(curl -s ipv4.ip.sb)
    ipv6_address=$(curl -s --max-time 1 ipv6.ip.sb)
}

# 管理定时任务函数
manage_cron_jobs() {
    while true; do
        clear_screen
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}             定时任务管理              ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo ""
        echo -e "${YELLOW}当前定时任务列表：${NC}"
        crontab -l 2>/dev/null || echo "暂无定时任务"
        echo ""
        echo -e "${YELLOW}可用操作：${NC}"
        echo -e "${GREEN}1.${NC} 添加定时任务"
        echo -e "${GREEN}2.${NC} 删除定时任务"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        echo -e "${BLUE}=================================================${NC}"
        
        read -p "请输入选项 [0-2]: " sub_choice

        case $sub_choice in
            1)
                echo ""
                read -p "请输入新任务的执行命令：" new_command
                echo -e "\n${YELLOW}任务类型：${NC}"
                echo -e "${GREEN}1.${NC} 每周任务"
                echo -e "${GREEN}2.${NC} 每天任务"
                read -p "请选择任务类型 [1-2]: " task_type

                case $task_type in
                    1)
                        read -p "选择周几执行任务？（0-6，0代表星期日）：" weekday
                        if [[ $weekday =~ ^[0-6]$ ]]; then
                            (crontab -l 2>/dev/null; echo "0 0 * * $weekday $new_command") | crontab -
                            echo -e "${GREEN}每周定时任务添加成功！${NC}"
                        else
                            echo -e "${RED}无效的星期数！${NC}"
                        fi
                        ;;
                    2)
                        read -p "选择每天几点执行任务？（0-23）：" hour
                        if [[ $hour =~ ^[0-9]|1[0-9]|2[0-3]$ ]]; then
                            (crontab -l 2>/dev/null; echo "0 $hour * * * $new_command") | crontab -
                            echo -e "${GREEN}每天定时任务添加成功！${NC}"
                        else
                            echo -e "${RED}无效的小时数！${NC}"
                        fi
                        ;;
                    *)
                        echo -e "${RED}无效的选项！${NC}"
                        ;;
                esac
                ;;
            2)
                echo ""
                read -p "请输入需要删除任务的关键字：" keyword
                if [ -n "$keyword" ]; then
                    crontab -l | grep -v "$keyword" | crontab -
                    echo -e "${GREEN}包含关键字 '$keyword' 的任务已删除！${NC}"
                else
                    echo -e "${RED}关键字不能为空！${NC}"
                fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选项！${NC}"
                ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 时区设置函数
set_timezone() {
    while true; do
        clear_screen
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}             时区设置              ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo ""
        
        # 获取并显示当前时区和时间
        current_timezone=$(timedatectl show --property=Timezone --value)
        current_time=$(date +"%Y-%m-%d %H:%M:%S")
        echo -e "${YELLOW}当前系统时区：${NC}$current_timezone"
        echo -e "${YELLOW}当前系统时间：${NC}$current_time"
        echo ""
        
        echo -e "${YELLOW}可用时区：${NC}"
        echo -e "${GREEN}1.${NC} 中国上海时间 (Asia/Shanghai)"
        echo -e "${GREEN}2.${NC} 中国香港时间 (Asia/Hong_Kong)"
        echo -e "${GREEN}3.${NC} 日本东京时间 (Asia/Tokyo)"
        echo -e "${GREEN}4.${NC} 韩国首尔时间 (Asia/Seoul)"
        echo -e "${GREEN}5.${NC} 新加坡时间 (Asia/Singapore)"
        echo -e "${GREEN}6.${NC} 印度加尔各答时间 (Asia/Kolkata)"
        echo -e "${GREEN}7.${NC} 阿联酋迪拜时间 (Asia/Dubai)"
        echo -e "${GREEN}8.${NC} 澳大利亚悉尼时间 (Australia/Sydney)"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        echo -e "${BLUE}=================================================${NC}"
        
        read -p "请输入选项 [0-8]: " sub_choice

        case $sub_choice in
            1) timedatectl set-timezone Asia/Shanghai ;;
            2) timedatectl set-timezone Asia/Hong_Kong ;;
            3) timedatectl set-timezone Asia/Tokyo ;;
            4) timedatectl set-timezone Asia/Seoul ;;
            5) timedatectl set-timezone Asia/Singapore ;;
            6) timedatectl set-timezone Asia/Kolkata ;;
            7) timedatectl set-timezone Asia/Dubai ;;
            8) timedatectl set-timezone Australia/Sydney ;;
            0) return ;;
            *) echo -e "${RED}无效的选项！${NC}" ;;
        esac
        
        if [ $sub_choice -ne 0 ]; then
            echo -e "${GREEN}时区已更新！${NC}"
            read -n 1 -s -r -p "按任意键继续..."
        fi
    done
}

# SSH密钥管理函数
generate_ssh_key() {
    clear_screen
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}             SSH密钥管理              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    
    # 生成密钥对
    echo -e "${YELLOW}正在生成ED25519密钥对...${NC}"
    ssh-keygen -t ed25519 -C "xxxx@gmail.com" -f /root/.ssh/sshkey -N ""

    # 确保.ssh目录存在并设置正确权限
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # 存放公钥并设置权限
    cat ~/.ssh/sshkey.pub >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

    # 获取服务器IP地址
    ip_address

    echo -e "\n${YELLOW}私钥信息（请务必保存）：${NC}"
    echo -e "${BLUE}------------------------------------------------${NC}"
    cat ~/.ssh/sshkey
    echo -e "${BLUE}------------------------------------------------${NC}"
    echo -e "${GREEN}建议将私钥保存为：${YELLOW}${ipv4_address}_ssh.key${NC}"
    
    # 等待用户确认是否已保存私钥
    while true; do
        echo -e "\n${YELLOW}请确认您是否已经安全保存了以上私钥信息？${NC}"
        echo -e "${GREEN}1.${NC} 已保存，继续下一步"
        echo -e "${GREEN}2.${NC} 未保存，再给我点时间"
        echo -e "${GREEN}3.${NC} 取消操作"
        read -p "请输入选项 [1-3]: " save_confirm
        
        case $save_confirm in
            1)
                break
                ;;
            2)
                echo -e "\n${YELLOW}请仔细查看并保存私钥信息...${NC}"
                read -n 1 -s -r -p "准备好后，按任意键继续..."
                continue
                ;;
            3)
                echo -e "\n${YELLOW}操作已取消${NC}"
                rm -f /root/.ssh/sshkey /root/.ssh/sshkey.pub
                read -n 1 -s -r -p "按任意键返回主菜单..."
                return
                ;;
            *)
                echo -e "${RED}无效的选项！${NC}"
                continue
                ;;
        esac
    done

    # 配置SSH服务
    echo -e "\n${YELLOW}正在配置SSH服务...${NC}"
    
    # 备份原配置文件
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # 修改SSH配置
    sed -i -e 's/^\s*#\?\s*PermitRootLogin .*/PermitRootLogin prohibit-password/' \
           -e 's/^\s*#\?\s*PasswordAuthentication .*/PasswordAuthentication no/' \
           -e 's/^\s*#\?\s*PubkeyAuthentication .*/PubkeyAuthentication yes/' \
           -e 's/^\s*#\?\s*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

    # 禁止X11图形转发功能
    if grep -q "^X11Forwarding" /etc/ssh/sshd_config; then
        sed -i '/^X11Forwarding/s/yes/no/' /etc/ssh/sshd_config
    else
        echo "X11Forwarding no" >> /etc/ssh/sshd_config
    fi

    # 禁止DNS查询
    if grep -q "^UseDNS" /etc/ssh/sshd_config; then
        sed -i '/^UseDNS/s/yes/no/' /etc/ssh/sshd_config
    else
        echo "UseDNS no" >> /etc/ssh/sshd_config
    fi

    # 清理可能存在的配置文件
    rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*

    # 检查配置文件语法
    if sshd -t; then
        echo -e "${GREEN}SSH配置验证通过${NC}"
        # 重启SSH服务
        if command -v systemctl &>/dev/null; then
            systemctl restart sshd
        else
            service ssh restart
        fi
        echo -e "${GREEN}SSH服务已重启${NC}"
    else
        echo -e "${RED}SSH配置验证失败，已恢复备份配置${NC}"
        mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        if command -v systemctl &>/dev/null; then
            systemctl restart sshd
        else
            service ssh restart
        fi
    fi

    # 询问是否删除密钥文件
    echo -e "\n${YELLOW}是否删除密钥文件？${NC}"
    echo -e "${RED}警告：删除后将无法恢复，请确保已经安全保存了私钥信息${NC}"
    echo -e "${GREEN}1.${NC} 是，立即删除"
    echo -e "${GREEN}2.${NC} 否，暂时保留"
    read -p "请输入选项 [1-2]: " delete_confirm
    
    case $delete_confirm in
        1)
            echo -e "\n${YELLOW}正在清理密钥文件...${NC}"
            rm -f /root/.ssh/sshkey /root/.ssh/sshkey.pub
            echo -e "${GREEN}密钥文件已清理${NC}"
            ;;
        2)
            echo -e "\n${YELLOW}密钥文件已保留在：${NC}"
            echo "私钥：/root/.ssh/sshkey"
            echo "公钥：/root/.ssh/sshkey.pub"
            ;;
        *)
            echo -e "${RED}无效的选项，密钥文件将被保留${NC}"
            ;;
    esac

    echo -e "\n${GREEN}SSH密钥配置完成：${NC}"
    echo "• ROOT密码登录已禁用"
    echo "• 密钥认证已启用"
    echo "• 配置将在下次SSH连接时生效"
    
    read -n 1 -s -r -p "按任意键继续..."
}

# 修改 SSH 端口函数
modify_ssh_port() {
    clear_screen
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}             修改 SSH 端口              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""

    # 检查 UFW 是否安装
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "${YELLOW}系统未安装 UFW 防火墙，正在安装...${NC}"
        apt update && apt install -y ufw || {
            echo -e "${RED}UFW 安装失败！${NC}"
            read -n 1 -s -r -p "按任意键继续..."
            return
        }
    fi

    # 获取当前 SSH 端口
    if [ -e "/etc/ssh/sshd_config" ]; then
        [ -z "$(grep ^Port /etc/ssh/sshd_config)" ] && CURRENT_PORT=22 || CURRENT_PORT=$(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')
        echo -e "${YELLOW}当前 SSH 端口：${NC}$CURRENT_PORT"
        
        # 输入新端口
        while true; do
            echo
            read -p "请输入新的 SSH 端口 (默认: $CURRENT_PORT): " NEW_PORT
            [ -z "$NEW_PORT" ] && NEW_PORT=$CURRENT_PORT
            if [ $NEW_PORT -eq 22 ] || ([ $NEW_PORT -gt 1024 ] && [ $NEW_PORT -lt 65535 ]); then
                break
            else
                echo -e "${RED}错误：端口范围必须是 22 或 1025-65534${NC}"
            fi
        done

        # 显示确认信息
        echo -e "\n${YELLOW}即将修改 SSH 端口：${NC}"
        echo -e "当前端口：${GREEN}$CURRENT_PORT${NC}"
        echo -e "新端口：${GREEN}$NEW_PORT${NC}"
        echo -e "\n${RED}警告：修改 SSH 端口可能导致连接中断！${NC}"
        read -p "是否继续？[y/N]: " CONFIRM
        if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}操作已取消${NC}"
            read -n 1 -s -r -p "按任意键继续..."
            return
        fi

        # 备份配置文件
        echo -e "\n${YELLOW}备份 SSH 配置文件...${NC}"
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak || {
            echo -e "${RED}备份配置文件失败！${NC}"
            read -n 1 -s -r -p "按任意键继续..."
            return
        }

        # 修改 SSH 端口
        if [ -z "$(grep ^Port /etc/ssh/sshd_config)" ] && [ "$NEW_PORT" != '22' ]; then
            sed -i "s@^#Port.*@&\nPort $NEW_PORT@" /etc/ssh/sshd_config
        elif [ -n "$(grep ^Port /etc/ssh/sshd_config)" ]; then
            sed -i "s@^Port.*@Port $NEW_PORT@" /etc/ssh/sshd_config
        fi

        # 配置防火墙
        echo -e "\n${YELLOW}配置防火墙规则...${NC}"
        ufw allow $NEW_PORT/tcp comment 'SSH'
        if ! ufw status | grep -q "Status: active"; then
            echo -e "${YELLOW}启用防火墙...${NC}"
            ufw --force enable
        fi
        ufw reload

        # 重启 SSH 服务
        echo -e "\n${YELLOW}重启 SSH 服务...${NC}"
        service ssh restart

        echo -e "\n${GREEN}SSH 端口修改完成！${NC}"
        echo -e "${YELLOW}新的 SSH 端口：${NC}$NEW_PORT"
        echo -e "\n${RED}重要提示：${NC}"
        echo "1. 请不要关闭当前窗口"
        echo "2. 请在新窗口测试新端口连接："
        echo -e "${GREEN}ssh -p $NEW_PORT root@$(curl -s ipv4.ip.sb)${NC}"
        echo "3. 如果无法连接，请使用以下命令恢复："
        echo "   cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"
        echo "   service ssh restart"
    else
        echo -e "${RED}错误：未找到 SSH 配置文件${NC}"
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}

# 显示主菜单
show_menu() {
    echo -e "${YELLOW}请选择要执行的操作：${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 定时任务管理"
    echo -e "${GREEN}2.${NC} 时区设置"
    echo -e "${GREEN}3.${NC} SSH密钥管理"
    echo -e "${GREEN}4.${NC} 修改SSH端口"
    echo -e "${GREEN}0.${NC} 退出脚本"
    echo ""
    echo -e "${BLUE}=================================================${NC}"
}

# 主程序循环
while true; do
    clear_screen
    show_banner
    show_menu
    
    read -p "请输入选项 [0-4]: " choice
    
    case $choice in
        1)
            manage_cron_jobs
            ;;
        2)
            set_timezone
            ;;
        3)
            generate_ssh_key
            ;;
        4)
            modify_ssh_port
            ;;
        0)
            clear_screen
            echo -e "${GREEN}感谢使用，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择${NC}"
            read -n 1 -s -r -p "按任意键继续..."
            ;;
    esac
done 