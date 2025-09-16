#!/bin/bash

# --- 定义颜色输出 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- 全局变量和系统检测 ---
OS_TYPE=""
HTTP_SERVER_PID=""
HTTP_PORT=8889
TEMP_SERVE_DIR=""

# --- 基础工具函数 ---

detect_os() {
	case "$(uname -s)" in
		Linux*)  OS_TYPE="linux";;
		Darwin*) OS_TYPE="macos";;
		*)       echo -e "${RED}错误: 不支持的操作系统: $(uname -s)${NC}" >&2; exit 1;;
	esac
	echo -e "${GREEN}检测到操作系统: $OS_TYPE${NC}"
}

check_privileges() {
	# 在Linux上, 脚本必须以root权限运行以避免各种文件权限问题
	if [[ "$OS_TYPE" == "linux" && "$(id -u)" -ne 0 ]]; then
		echo -e "${RED}错误: 在 Linux 上, 此脚本必须以 root 权限运行。${NC}" >&2
		echo -e "${YELLOW}请尝试使用: sudo $0${NC}"
		exit 1
	fi
}

ensure_packages() {
	local pkgs_to_install=()
	for pkg in "$@"; do
		if ! command -v "$pkg" &> /dev/null; then
			[[ "$OS_TYPE" == "macos" && "$pkg" == "docker" ]] && { echo -e "${RED}错误: Docker Desktop for Mac 未安装。请先从官网安装。${NC}" >&2; return 1; }
			pkgs_to_install+=("$pkg")
		fi
	done

	if [ ${#pkgs_to_install[@]} -eq 0 ]; then return 0; fi

	echo -e "${YELLOW}以下依赖需要安装: ${pkgs_to_install[*]}${NC}"
	read -p "是否继续安装? (Y/N): " confirm_install
	[[ ! "$confirm_install" =~ ^[Yy]$ ]] && { echo "安装取消。"; return 1; }

	if [[ "$OS_TYPE" == "linux" ]]; then
		PKG_MANAGER=""
		if grep -qE 'ubuntu|debian' /etc/os-release; then
			PKG_MANAGER="apt-get"
			echo "正在更新包列表..."; sudo $PKG_MANAGER update -y >/dev/null
		elif grep -qE 'centos|rhel|fedora' /etc/os-release; then
			PKG_MANAGER="yum"
			command -v dnf &>/dev/null && PKG_MANAGER="dnf"
		else
			echo -e "${RED}错误: 不支持的 Linux 发行版。${NC}"; return 1
		fi
		sudo $PKG_MANAGER install -y "${pkgs_to_install[@]}" || { echo -e "${RED}依赖安装失败。${NC}"; return 1; }
	elif [[ "$OS_TYPE" == "macos" ]]; then
		command -v brew &> /dev/null || { echo -e "${RED}错误: Homebrew 未安装 (brew.sh)。${NC}"; return 1; }
		brew install "${pkgs_to_install[@]}" || { echo -e "${RED}依赖安装失败。${NC}"; return 1; }
	fi
}

# --- 轻量级HTTP服务器相关函数 ---

get_server_ip() {
	local ip_addr
	if [[ "$OS_TYPE" == "linux" ]]; then
		ip_addr=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -n 1)
	else
		ip_addr=$(ifconfig | grep -E "inet ([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
	fi
	
	if [ -z "$ip_addr" ]; then
		ip_addr=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null) || ip_addr="[无法获取公网IP]"
	fi
	echo "$ip_addr"
}

find_available_port() {
	local port=$1
	local max_tries=10
	local current_try=0
	
	while [ $current_try -lt $max_tries ]; do
		if ! netstat -tuln 2>/dev/null | grep -q ":$port " && ! ss -tuln 2>/dev/null | grep -q ":$port "; then
			echo "$port"
			return 0
		fi
		((port++))
		((current_try++))
	done
	
	echo ""
	return 1
}

setup_http_server() {
	local serve_dir="$1"
	
	# 检查Python是否可用
	local python_cmd=""
	if command -v python3 &>/dev/null; then
		python_cmd="python3"
	elif command -v python &>/dev/null && python --version 2>&1 | grep -q "Python 3"; then
		python_cmd="python"
	else
		echo -e "${RED}错误: 需要 Python 3 来启动内置HTTP服务器${NC}"
		return 1
	fi
	
	# 用户输入端口或使用默认值
	read -p "请输入HTTP服务器端口 (默认 $HTTP_PORT): " user_port
	if [[ -n "$user_port" && "$user_port" =~ ^[0-9]+$ && "$user_port" -ge 1024 && "$user_port" -le 65535 ]]; then
		HTTP_PORT="$user_port"
	fi
	
	# 检查端口可用性
	local available_port
	available_port=$(find_available_port "$HTTP_PORT")
	if [ -z "$available_port" ]; then
		echo -e "${RED}错误: 端口 $HTTP_PORT 及后续端口都被占用，请手动指定其他端口${NC}"
		return 1
	fi
	
	if [ "$available_port" != "$HTTP_PORT" ]; then
		echo -e "${YELLOW}端口 $HTTP_PORT 被占用，自动使用端口 $available_port${NC}"
		HTTP_PORT="$available_port"
	fi
	
	echo -e "${YELLOW}正在启动内置HTTP服务器 (端口 $HTTP_PORT)...${NC}"
	
	# 启动Python HTTP服务器
	cd "$serve_dir"
	nohup $python_cmd -m http.server "$HTTP_PORT" --bind 0.0.0.0 >/dev/null 2>&1 &
	HTTP_SERVER_PID=$!
	
	# 等待服务器启动
	sleep 2
	
	# 验证服务器是否成功启动
	if ! kill -0 "$HTTP_SERVER_PID" 2>/dev/null; then
		echo -e "${RED}HTTP服务器启动失败${NC}"
		return 1
	fi
	
	# 测试服务器是否可访问
	if ! curl -s --connect-timeout 2 "http://localhost:$HTTP_PORT" >/dev/null; then
		echo -e "${RED}HTTP服务器无法访问，可能端口被占用${NC}"
		stop_http_server
		return 1
	fi
	
	echo -e "${GREEN}HTTP服务器已在端口 $HTTP_PORT 启动 (PID: $HTTP_SERVER_PID)${NC}"
	return 0
}

stop_http_server() {
	if [ -n "$HTTP_SERVER_PID" ] && kill -0 "$HTTP_SERVER_PID" 2>/dev/null; then
		echo -e "${YELLOW}正在停止HTTP服务器...${NC}"
		kill "$HTTP_SERVER_PID" 2>/dev/null
		wait "$HTTP_SERVER_PID" 2>/dev/null
		echo -e "${GREEN}HTTP服务器已停止${NC}"
	fi
	HTTP_SERVER_PID=""
}

# --- Docker 核心功能函数 ---

check_runlike() {
	if ! docker image inspect assaflavie/runlike:latest &>/dev/null; then
		echo -e "${YELLOW}迁移工具 'runlike' 未安装，正在拉取镜像...${NC}"
		docker pull assaflavie/runlike:latest || { echo -e "${RED}拉取 'runlike' 镜像失败。请检查网络和 Docker 环境。${NC}"; return 1; }
	fi
	return 0
}

### ========================================================= ###
###           ★ 功能1: Docker 迁移备份 ★
### ========================================================= ###
migration_backup() {
	echo -e "\n${BLUE}--- 1. Docker 迁移备份 (源服务器) ---${NC}"
	ensure_packages "docker" "tar" "gzip" "curl" "python3" || return 1
	check_runlike || return 1

	local ALL_CONTAINERS; ALL_CONTAINERS=$(docker ps --format '{{.Names}}')
	[ -z "$ALL_CONTAINERS" ] && { echo -e "${RED}错误: 未找到任何正在运行的容器。${NC}"; return 1; }

	echo "当前正在运行的容器:"; echo -e "${GREEN}${ALL_CONTAINERS}${NC}"
	read -p "请输入要备份的容器名称 (用空格分隔, 回车备份所有): " -r user_input
	
	local TARGET_CONTAINERS=()
	if [ -z "$user_input" ]; then
		TARGET_CONTAINERS=($ALL_CONTAINERS)
	else
		read -ra TARGET_CONTAINERS <<< "$user_input"
	fi

	local DATA_ARCHIVE_NAME="docker_data.tar.gz"
	local START_SCRIPT_NAME="docker_run.sh"
	
	# 创建临时服务目录
	TEMP_SERVE_DIR=$(mktemp -d)
	local TEMP_DIR; TEMP_DIR=$(mktemp -d)

	echo "#!/bin/bash" > "${TEMP_DIR}/${START_SCRIPT_NAME}"
	echo "set -e" >> "${TEMP_DIR}/${START_SCRIPT_NAME}"
	echo "# Auto-generated by Docker Migration Tool. Run this script after restoring data." >> "${TEMP_DIR}/${START_SCRIPT_NAME}"

	local volume_paths_file="${TEMP_DIR}/volume_paths.txt"
	
	for c in "${TARGET_CONTAINERS[@]}"; do
		if ! docker ps -q --filter "name=^/${c}$" | grep -q .; then
			echo -e "${RED}错误: 容器 '$c' 不存在或未运行，已跳过。${NC}"; continue
		fi
		echo -e "\n${YELLOW}正在备份容器文件并生成安装命令: $c ...${NC}"
		
		# 1. 记录数据卷的绝对路径
		docker inspect "$c" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' >> "${volume_paths_file}"
		
		# 2. 生成原始的、干净的 docker run 命令
		local run_cmd; run_cmd=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock assaflavie/runlike "$c")
		local clean_cmd; clean_cmd=$(echo "$run_cmd" | sed -E 's/--hostname=[^ ]+ //g; s/--mac-address=[^ ]+ //g')
		
		echo "" >> "${TEMP_DIR}/${START_SCRIPT_NAME}"
		echo "echo -e \"\n${GREEN}>>> 正在启动容器: $c${NC}\"" >> "${TEMP_DIR}/${START_SCRIPT_NAME}"
		echo "$clean_cmd" >> "${TEMP_DIR}/${START_SCRIPT_NAME}"
	done
	
	# 去重并检查是否有数据卷
	sort -u "${volume_paths_file}" -o "${volume_paths_file}"
	if [ ! -s "${volume_paths_file}" ]; then
		echo -e "${YELLOW}警告: 所选容器没有发现任何挂载的数据卷。只生成启动脚本。${NC}"
		sudo touch "${TEMP_DIR}/${DATA_ARCHIVE_NAME}" # 创建空包
	else
		echo -e "\n${YELLOW}正在打包所有数据卷...${NC}"
		# 显示即将备份的路径
		echo "即将备份以下数据卷路径:"
		cat "${volume_paths_file}" | sed 's/^/  - /'
		
		# 检查是否包含数据库相关容器
		local has_database=false
		for c in "${TARGET_CONTAINERS[@]}"; do
			if docker ps --format '{{.Image}}' --filter "name=^/${c}$" | grep -qE "(mysql|postgres|clickhouse|mongo|redis|mariadb|elasticsearch)"; then
				has_database=true
				break
			fi
		done
		
		if [ "$has_database" = true ]; then
			echo -e "\n${YELLOW}检测到数据库容器，建议选择备份策略:${NC}"
			echo "1. 停止容器后备份 (数据一致性最好，但会短暂中断服务)"
			echo "2. 在线备份 (服务不中断，但可能有少量数据不一致)"
			echo "3. 忽略变化继续备份 (最快，适合测试环境)"
			read -p "请选择策略 (1/2/3，默认为2): " backup_strategy
			
			case "${backup_strategy:-2}" in
				1)
					echo -e "${YELLOW}正在停止相关容器...${NC}"
					for c in "${TARGET_CONTAINERS[@]}"; do
						if docker ps -q --filter "name=^/${c}$" | grep -q .; then
							echo "停止容器: $c"
							docker stop "$c"
						fi
					done
					sleep 3
					echo -e "${GREEN}容器已停止，开始备份...${NC}"
					;;
				2)
					echo -e "${YELLOW}使用在线备份模式...${NC}"
					;;
				3)
					echo -e "${YELLOW}使用强制备份模式...${NC}"
					;;
			esac
		fi
		
		# 根据选择的策略执行备份
		local tar_options="-czpf"
		local tar_extra_options=""
		
		case "${backup_strategy:-2}" in
			1|2)
				# 对于停止备份或在线备份，使用相对温和的选项
				tar_extra_options="--ignore-failed-read --warning=no-file-changed --warning=no-file-removed"
				;;
			3)
				# 强制备份模式，忽略所有变化
				tar_extra_options="--ignore-failed-read --ignore-zeros --warning=none"
				;;
		esac
		
		echo "开始打包数据卷 (这可能需要一些时间)..."
		# 使用 -P (或 --absolute-names) 来保留绝对路径，-C / 从根目录开始打包
		if ! sudo tar $tar_options "${TEMP_DIR}/${DATA_ARCHIVE_NAME}" -P -C / $tar_extra_options -T "${volume_paths_file}" 2>/tmp/tar_backup.log; then
			# 检查是否是致命错误还是可以忽略的警告
			if grep -qE "(No space left on device|Permission denied|Cannot open)" /tmp/tar_backup.log; then
				echo -e "${RED}打包过程中发生致命错误:${NC}"
				cat /tmp/tar_backup.log
				sudo rm -f /tmp/tar_backup.log
				sudo rm -rf "$TEMP_DIR" "$TEMP_SERVE_DIR"
				return 1
			else
				echo -e "${YELLOW}打包过程中有一些警告，但备份已完成:${NC}"
				cat /tmp/tar_backup.log | head -10
				echo -e "${GREEN}备份文件已生成，这些警告通常不影响恢复。${NC}"
			fi
		else
			echo -e "${GREEN}数据卷打包完成！${NC}"
		fi
		sudo rm -f /tmp/tar_backup.log
		
		# 如果之前停止了容器，现在重新启动
		if [ "${backup_strategy:-2}" = "1" ]; then
			echo -e "\n${YELLOW}正在重新启动容器...${NC}"
			for c in "${TARGET_CONTAINERS[@]}"; do
				echo "启动容器: $c"
				docker start "$c"
			done
			echo -e "${GREEN}容器已重新启动${NC}"
		fi
		
		# 显示备份文件大小
		local backup_size; backup_size=$(du -h "${TEMP_DIR}/${DATA_ARCHIVE_NAME}" | cut -f1)
		echo -e "${GREEN}备份文件大小: $backup_size${NC}"
	fi

	# 移动文件到服务目录
	sudo mv "${TEMP_DIR}"/* "${TEMP_SERVE_DIR}/"
	sudo rm -rf "$TEMP_DIR"
	
	# 启动HTTP服务器
	if ! setup_http_server "$TEMP_SERVE_DIR"; then
		sudo rm -rf "$TEMP_SERVE_DIR"
		return 1
	fi
	
	local server_ip; server_ip=$(get_server_ip)
	echo -e "\n${GREEN}--- ✅  备份完成！【请在新服务器恢复完后再退出脚本】！！ ---${NC}"
	echo -e "在新服务器上，输入源服务器的IP或域名将会自动下载以下备份文件:"
	echo -e "1. 数据包:   ${BLUE}http://${server_ip}:${HTTP_PORT}/${DATA_ARCHIVE_NAME}${NC}"
	echo -e "2. 启动脚本: ${BLUE}http://${server_ip}:${HTTP_PORT}/${START_SCRIPT_NAME}${NC}"
	echo -e "\n${YELLOW}提示: HTTP服务器将持续运行直到您退出脚本或按 Ctrl+C${NC}"
}

### ========================================================= ###
###           ★ 功能2: Docker 备份恢复 ★
### ========================================================= ###
migration_restore() {
	echo -e "\n${BLUE}--- 2. Docker 备份恢复 (新服务器) ---${NC}"
	ensure_packages "wget" "tar" "gzip" "docker" || return 1
	
	local DATA_ARCHIVE_NAME="docker_data.tar.gz"
	local START_SCRIPT_NAME="docker_run.sh"

	read -p "请输入源服务器的 IP 地址或域名: " source_ip
	[ -z "$source_ip" ] && { echo -e "${RED}IP 地址不能为空。${NC}"; return 1; }
	
	read -p "请输入源服务器的端口 (默认 8889): " source_port
	if [[ -z "$source_port" || ! "$source_port" =~ ^[0-9]+$ ]]; then
		source_port=8889
	fi

	local data_url="http://${source_ip}:${source_port}/${DATA_ARCHIVE_NAME}"
	local script_url="http://${source_ip}:${source_port}/${START_SCRIPT_NAME}"

	echo "正在测试连接到源服务器..."
	if ! curl -s --connect-timeout 5 --head "$script_url" >/dev/null; then
		echo -e "${RED}无法连接到源服务器 ${source_ip}:${source_port}，请检查:${NC}"
		echo "1. 源服务器IP地址是否正确"
		echo "2. 端口是否正确"
		echo "3. 网络连通性"
		echo "4. 源服务器的HTTP服务是否正在运行"
		return 1
	fi

	echo "正在下载启动脚本..."
	if ! wget -q --show-progress --timeout=30 "$script_url" -O "$START_SCRIPT_NAME"; then
		echo -e "${RED}下载启动脚本失败! 请检查网络连接和源服务器状态${NC}"
		return 1
	fi
	
	echo "正在下载备份数据包..."
	if ! wget -q --show-progress --timeout=300 "$data_url" -O "$DATA_ARCHIVE_NAME"; then
		echo -e "${RED}下载备份数据包失败! 请检查网络连接和磁盘空间${NC}"
		rm -f "$START_SCRIPT_NAME"
		return 1
	fi
	
	# 检查下载的文件大小
	local data_size; data_size=$(du -h "$DATA_ARCHIVE_NAME" | cut -f1)
	local script_size; script_size=$(du -h "$START_SCRIPT_NAME" | cut -f1)
	echo "已下载: 数据包 ($data_size), 启动脚本 ($script_size)"
	
	echo -e "\n${YELLOW}正在解压数据到容器指定路径...${NC}"
	# 使用 -P 来处理绝对路径, -p 保留权限, -C / 在根目录解压
	if ! sudo tar -xzpf "$DATA_ARCHIVE_NAME" -P -C /; then
		echo -e "${RED}解压数据失败！请检查文件是否损坏或磁盘空间。${NC}"
		return 1
	fi
	sudo chmod +x "$START_SCRIPT_NAME"

	echo -e "\n${GREEN}--- 数据已恢复完毕，准备启动容器... ---${NC}"
	echo "正在执行启动脚本..."
	if sudo ./"$START_SCRIPT_NAME"; then
		echo -e "\n${GREEN}--- ✅ 容器启动脚本执行完毕！---${NC}"
		echo -e "\n当前容器状态:"
		docker ps -a
		
		echo -e "\n正在自动清理临时文件..."
		sudo rm -f "$DATA_ARCHIVE_NAME" "$START_SCRIPT_NAME"
		echo "临时文件已清理。"
	else
		echo -e "\n${RED}容器启动脚本执行时发生错误！请检查上面的日志输出。${NC}"
		echo "临时文件保留以供调试: $DATA_ARCHIVE_NAME, $START_SCRIPT_NAME"
	fi
}

# --- 清理函数 ---
cleanup() {
	echo -e "\n${YELLOW}正在清理资源...${NC}"
	stop_http_server
	if [ -n "$TEMP_SERVE_DIR" ] && [ -d "$TEMP_SERVE_DIR" ]; then
		sudo rm -rf "$TEMP_SERVE_DIR"
		echo "临时文件已清理"
	fi
}

# ==================================================
#                     程序主菜单
# ==================================================
main_menu() {
	while true; do
		echo -e "\n${BLUE}=============================================${NC}"
		echo -e "      Docker 迁移与备份工具 v5.0 (改进版)"
		echo -e "${BLUE}=============================================${NC}"
		echo -e "  --- 请选择操作 ---"
		echo -e "  ${GREEN}1.${NC}  Docker 迁移备份 (在源服务器运行)"
		echo -e "  ${GREEN}2.${NC}  Docker 备份恢复 (在新服务器运行)"
		echo ""
		echo -e "  ${RED}3.${NC}  退出"
		echo -e "${BLUE}=============================================${NC}"
		echo -e "  ${YELLOW}改进特性:${NC}"
		echo -e "  • 内置Python HTTP服务器，无需依赖Nginx"
		echo -e "  • 支持自定义端口，自动检测端口冲突"
		echo -e "  • 增强的错误处理和连接测试"
		echo -e "  • 更好的跨平台兼容性"
		echo -e "${BLUE}=============================================${NC}"
		read -p "请输入选项 (1-3): " choice

		case $choice in
			1) migration_backup ;;
			2) migration_restore ;;
			3) cleanup; echo -e "\n${GREEN}脚本执行完毕，感谢使用！${NC}"; exit 0 ;;
			*) echo -e "${RED}无效选项。${NC}" ;;
		esac
	done
}

# --- 脚本主入口 ---
trap "echo -e '\n捕获到退出信号，正在清理...'; cleanup; exit 1" INT TERM
clear
detect_os
check_privileges
main_menu
