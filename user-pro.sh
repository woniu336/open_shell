#!/bin/bash

# Linux用户管理脚本 - 支持CentOS、Rocky Linux和Ubuntu系统

# 颜色设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化
init() {
    # 检查root权限
    [ "$(id -u)" -ne 0 ] && echo -e "${RED}错误: 需要root权限${NC}" && exit 1
    
    # 检测Linux发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        if [[ $OS == *"CentOS"* ]] || [[ $OS == *"Rocky"* ]]; then
            PACKAGE_MANAGER="yum"
            USER_ADD_CMD="useradd"
            GROUP_ADD_CMD="groupadd"
        elif [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
            PACKAGE_MANAGER="apt"
            USER_ADD_CMD="adduser"
            GROUP_ADD_CMD="addgroup"
        else
            echo -e "${YELLOW}警告: 未知的Linux发行版: $OS, 使用通用命令${NC}"
            PACKAGE_MANAGER="apt"
            USER_ADD_CMD="useradd"
            GROUP_ADD_CMD="groupadd"
        fi
    else
        echo -e "${RED}错误: 无法检测操作系统${NC}" && exit 1
    fi
    echo -e "${GREEN}检测到: $OS${NC}"
}

# 检查用户是否存在
user_exists() {
    id "$1" &>/dev/null
    return $?
}

# 检查组是否存在
group_exists() {
    grep -q "^$1:" /etc/group
    return $?
}

# 添加用户
add_user() {
    read -p "用户名: " username
    
    user_exists "$username" && echo -e "${RED}用户已存在${NC}" && return 1
    
    read -p "主目录(默认/home/$username): " homedir
    homedir=${homedir:-/home/$username}
    read -p "Shell(默认/bin/bash): " usershell
    usershell=${usershell:-/bin/bash}
    read -p "密码: " userpass
    
    if [[ $PACKAGE_MANAGER == "apt" ]]; then
        $USER_ADD_CMD $username --home $homedir --shell $usershell
        echo "$username:$userpass" | chpasswd
    else
        $USER_ADD_CMD -m -d $homedir -s $usershell $username
        echo "$userpass" | passwd --stdin $username
    fi
    
    [ $? -eq 0 ] && echo -e "${GREEN}用户创建成功${NC}" || echo -e "${RED}创建失败${NC}"
    
    read -p "添加sudo权限? (y/n): " add_sudo
    [[ $add_sudo == [yY] ]] && set_sudo_permission "$username"
}

# 删除用户
delete_user() {
    read -p "要删除的用户名: " username
    user_exists "$username" || { echo -e "${RED}用户不存在${NC}"; return 1; }
    
    read -p "同时删除主目录? (y/n): " del_home
    [[ $del_home == [yY] ]] && userdel -r $username || userdel $username
    
    [ $? -eq 0 ] && echo -e "${GREEN}用户已删除${NC}" || echo -e "${RED}删除失败${NC}"
}

# 修改用户
modify_user() {
    read -p "要修改的用户名: " username
    user_exists "$username" || { echo -e "${RED}用户不存在${NC}"; return 1; }
    
    echo -e "1.修改主目录  2.修改shell  3.修改用户组  4.返回"
    read -p "选择: " choice
    
    case $choice in
        1)
            read -p "新主目录: " new_home
            usermod -d $new_home $username && echo -e "${GREEN}修改成功${NC}" || echo -e "${RED}修改失败${NC}"
            ;;
        2)
            read -p "新shell: " new_shell
            usermod -s $new_shell $username && echo -e "${GREEN}修改成功${NC}" || echo -e "${RED}修改失败${NC}"
            ;;
        3)
            read -p "新用户组: " new_group
            if ! group_exists "$new_group"; then
                read -p "组不存在, 是否创建? (y/n): " create_group
                [[ $create_group == [yY] ]] && $GROUP_ADD_CMD $new_group || return 1
            fi
            usermod -g $new_group $username && echo -e "${GREEN}修改成功${NC}" || echo -e "${RED}修改失败${NC}"
            ;;
        4) return 0 ;;
        *) ;;
    esac
}

# 列出所有用户
list_users() {
    echo -e "${BLUE}系统用户:${NC}"
    echo -e "${YELLOW}UID  用户名  主目录  Shell${NC}"
    echo "-------------------------------"
    
    awk -F: '$3 >= 1000 && $3 < 65534 {print $3, $1, $6, $7}' /etc/passwd | sort -n | 
    while read uid username homedir shell; do
        echo -e "${GREEN}$uid  $username  $homedir  $shell${NC}"
    done
    
    echo -e "\n${BLUE}用户总数: $(awk -F: '$3 >= 1000 && $3 < 65534 {count++} END {print count}' /etc/passwd)${NC}"
}

# 添加/删除用户组
manage_group() {
    local action=$1
    if [ "$action" = "add" ]; then
        read -p "新用户组名: " groupname
        group_exists "$groupname" && echo -e "${RED}组已存在${NC}" && return 1
        $GROUP_ADD_CMD $groupname
    else
        read -p "要删除的用户组: " groupname
        group_exists "$groupname" || { echo -e "${RED}组不存在${NC}"; return 1; }
        groupdel $groupname
    fi
    
    [ $? -eq 0 ] && echo -e "${GREEN}操作成功${NC}" || echo -e "${RED}操作失败${NC}"
}

# 修改用户密码
change_password() {
    read -p "用户名: " username
    user_exists "$username" || { echo -e "${RED}用户不存在${NC}"; return 1; }
    
    read -p "新密码: " userpass
    
    if [[ $PACKAGE_MANAGER == "apt" ]]; then
        echo "$username:$userpass" | chpasswd
    else
        echo "$userpass" | passwd --stdin $username
    fi
    
    [ $? -eq 0 ] && echo -e "${GREEN}密码已修改${NC}" || echo -e "${RED}修改失败${NC}"
}

# 设置sudo权限
set_sudo_permission() {
    local username=$1
    
    if [ -z "$username" ]; then
        read -p "用户名: " username
        user_exists "$username" || { echo -e "${RED}用户不存在${NC}"; return 1; }
    fi
    
    # 安装sudo（如需）
    if ! command -v sudo &> /dev/null; then
        echo -e "${YELLOW}安装sudo...${NC}"
        [[ $PACKAGE_MANAGER == "apt" ]] && { apt update && apt install -y sudo; } || yum install -y sudo
    fi
    
    # 添加权限
    if [[ $PACKAGE_MANAGER == "apt" ]]; then
        usermod -aG sudo $username
        grep -q "^wheel:" /etc/group && usermod -aG wheel $username
    else
        usermod -aG wheel $username
    fi
    
    # 设置无密码sudo
    read -p "允许无密码sudo? (y/n): " nopass
    if [[ $nopass == [yY] ]]; then
        echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$username
        chmod 0440 /etc/sudoers.d/$username
    fi
    
    echo -e "${GREEN}sudo权限已设置${NC}"
}

# 显示用户信息
show_user_info() {
    read -p "用户名(留空显示所有): " username
    
    [ -z "$username" ] && { list_users; return 0; }
    user_exists "$username" || { echo -e "${RED}用户不存在${NC}"; return 1; }
    
    # 获取信息
    uid=$(id -u $username)
    gid=$(id -g $username)
    groups=$(id -nG $username)
    homedir=$(grep "^$username:" /etc/passwd | cut -d: -f6)
    shell=$(grep "^$username:" /etc/passwd | cut -d: -f7)
    
    # 检查sudo权限和账户状态
    groups $username | grep -qE "\b(sudo|wheel)\b" && sudo_status="${GREEN}已授权${NC}" || sudo_status="${RED}未授权${NC}"
    grep -q "^$username:!!" /etc/shadow 2>/dev/null && account_status="${RED}已锁定${NC}" || account_status="${GREEN}正常${NC}"
    
    # 显示信息
    echo -e "${BLUE}用户信息:${NC}"
    echo -e "UID: $uid\nGID: $gid\n主目录: $homedir\nShell: $shell\n组: $groups\nsudo: $sudo_status\n状态: $account_status"
    
    echo -e "\n${BLUE}最后登录:${NC}"
    lastlog -u $username
}

# 主函数
main() {
    init
    
    while true; do
        clear
        echo
        echo -e "${BLUE}╭────────────────────────────────╮${NC}"
        echo -e "${BLUE}│${NC}      ${GREEN}Linux 用户管理系统${NC}      ${BLUE}│${NC}"
        echo -e "${BLUE}╰────────────────────────────────╯${NC}"
        echo
        echo -e " ${GREEN}[1]${NC} 添加用户      ${GREEN}[2]${NC} 删除用户      ${GREEN}[3]${NC} 修改用户"
        echo -e " ${GREEN}[4]${NC} 查看用户      ${GREEN}[5]${NC} 添加用户组    ${GREEN}[6]${NC} 删除用户组"
        echo -e " ${GREEN}[7]${NC} 修改密码      ${GREEN}[8]${NC} 设置sudo      ${GREEN}[9]${NC} 用户信息"
        echo -e " ${RED}[0]${NC} 退出系统"
        echo
        echo -e "${BLUE}──────────────────────────────────────────────${NC}"
        
        read -p " 请选择操作 [0-9]: " choice
        echo
        
        case $choice in
            1) add_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) list_users ;;
            5) manage_group "add" ;;
            6) manage_group "del" ;;
            7) change_password ;;
            8) set_sudo_permission ;;
            9) show_user_info ;;
            0) clear; exit 0 ;;
            *) ;;
        esac
        
        echo
        read -p " 按回车键继续..." dummy
    done
}

# 启动脚本
main 