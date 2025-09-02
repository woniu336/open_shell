#================================================================================


# --- 脚本配置 ---
$GithubApiUrl = "https://api.github.com/repos/EasyTier/EasyTier/releases/latest"
$GithubProxy = "ghfast.top" # 可选代理, 留空则不使用

# --- 路径和名称定义 ---
# 使用 Program Files 和 ProgramData 是 Windows 的标准做法
$InstallDir = "$env:ProgramFiles\EasyTier"
$ConfigDir = "$env:ProgramData\EasyTier" # ProgramData 是系统级应用数据的存放位置
$ConfigFile = Join-Path $ConfigDir "easytier.toml"
$CoreBinaryName = "easytier-core.exe"
$CliBinaryName = "easytier-cli.exe"
$CoreBinaryPath = Join-Path $InstallDir $CoreBinaryName
$CliBinaryPath = Join-Path $InstallDir $CliBinaryName

# --- Windows 服务定义 ---
$ServiceName = "EasyTierService"
$ServiceDisplayName = "EasyTier Service"

# --- 颜色定义 ---
$c_green = "Green"
$c_red = "Red"
$c_yellow = "Yellow"
$c_cyan = "Cyan"
$c_normal = "White"

# --- 辅助函数 ---

# 检查是否以管理员身份运行
function Check-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "错误: 此脚本必须以管理员身份运行。" -ForegroundColor $c_red
        Write-Host "请右键点击 PowerShell 窗口标题栏，选择 '以管理员身份运行'，或右键点击脚本文件选择 '使用 PowerShell 运行'。" -ForegroundColor $c_yellow
        Read-Host "按 Enter 键退出..."
        exit 1
    }
}

# 检查 EasyTier 是否已安装
function Check-Installed {
    if (-not (Test-Path $CoreBinaryPath)) {
        Write-Host "EasyTier 尚未安装。请先选择选项 1。" -ForegroundColor $c_yellow
        return $false
    }
    return $true
}

# 修改 toml 文件中的值 (PowerShell 版本)
function Set-TomlValue {
    param(
        [string]$Key,
        [string]$Value,
        [string]$FilePath
    )
    try {
        $content = Get-Content $FilePath -Raw
        $pattern = "(?im)^#*\s*($Key)\s*=.+"
        $replacement = "$Key = $Value"
        $newContent = $content -replace $pattern, $replacement
        Set-Content -Path $FilePath -Value $newContent
    }
    catch {
        Write-Host "错误: 修改配置文件失败: $_" -ForegroundColor $c_red
    }
}


# --- 主功能函数 ---

function Install-EasyTier {
    Write-Host "--- 开始安装或更新 EasyTier ---" -ForegroundColor $c_green

    # 在 Windows 上，我们主要关注 x86_64
    $arch = "x86_64"
    $os_identifier = "windows"

    Write-Host "1. 获取最新版本信息..."
    try {
        $latestInfo = Invoke-RestMethod -Uri $GithubApiUrl
    }
    catch {
        Write-Host "错误: 无法从 GitHub API 获取版本信息。请检查网络连接。" -ForegroundColor $c_red
        return
    }
    
    $search_prefix = "easytier-${os_identifier}-${arch}"
    $asset = $latestInfo.assets | Where-Object { $_.name -like "$search_prefix*.zip" }

    if (-not $asset) {
        Write-Host "错误: 未能找到适用于 Windows (x64) 的包。" -ForegroundColor $c_red
        return
    }

    $downloadUrl = $asset.browser_download_url
    $fileName = $asset.name
    $version = $latestInfo.tag_name

    Write-Host "检测到版本: $version, 架构: $arch, 文件: $fileName"

    if ($GithubProxy) {
        $downloadUrl = "https://$GithubProxy/$downloadUrl"
        Write-Host "2. 使用代理下载: $downloadUrl" -ForegroundColor $c_yellow
    } else {
        Write-Host "2. 直接下载: $downloadUrl"
    }

    $tempFile = Join-Path $env:TEMP $fileName
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -UseBasicParsing
    }
    catch {
        Write-Host "下载失败! $_" -ForegroundColor $c_red
        if (Test-Path $tempFile) { Remove-Item $tempFile }
        return
    }

    Write-Host "3. 解压并安装..."
    # 确保安装目录存在
    if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
    
    try {
        Expand-Archive -Path $tempFile -DestinationPath $InstallDir -Force
    }
    catch {
        Write-Host "解压失败! $_" -ForegroundColor $c_red
        if (Test-Path $tempFile) { Remove-Item $tempFile }
        return
    }

    # ====================【关键修复代码块】====================
    Write-Host "4. 整理文件结构..." -ForegroundColor $c_yellow
    # 查找解压后可能创建的子目录 (例如 easytier-windows-x86_64)
    $subDir = Get-ChildItem -Path $InstallDir -Directory | Select-Object -First 1
    if ($subDir) {
        # 如果找到了子目录，将其中的所有内容移动到上层安装目录
        Write-Host "检测到子目录 $($subDir.FullName)，正在移动文件..." -ForegroundColor $c_cyan
        Move-Item -Path (Join-Path $subDir.FullName "*") -Destination $InstallDir -Force
        # 删除空的子目录
        Remove-Item -Path $subDir.FullName -Force -ErrorAction SilentlyContinue
    }
    # =========================================================

    # 清理工作
    Remove-Item $tempFile

    Write-Host "--- EasyTier $version 安装/更新成功! ---" -ForegroundColor $c_green
    Write-Host "程序已安装到: $InstallDir" -ForegroundColor $c_cyan

    # 如果服务已存在, 重启以应用更新
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Host "检测到现有服务，正在重启以应用更新..." -ForegroundColor $c_yellow
        Restart-Service -Name $ServiceName
    }
}

function Create-DefaultConfig {
    if (-not (Test-Path $ConfigDir)) { New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null }
$configContent = @"
ipv4 = ""
dhcp = false
listeners = ["udp://0.0.0.0:11010", "tcp://0.0.0.0:11010", "wg://0.0.0.0:11011", "ws://0.0.0.0:11011/", "wss://0.0.0.0:11012/"]
[network_identity]
network_name = ""
network_secret = ""
[flags]
default_protocol = "udp"
dev_name = ""
enable_encryption = true
enable_ipv6 = true
mtu = 1380
latency_first = true
enable_exit_node = false
no_tun = false
use_smoltcp = false
foreign_network_whitelist = "*"
disable_p2p = false
relay_all_peer_rpc = false
disable_udp_hole_punching = false
enableKcp_Proxy = true
"@
    Set-Content -Path $ConfigFile -Value $configContent
    Write-Host "已成功创建默认配置文件: $ConfigFile"
}

function Configure-Network {
    if (-not (Check-Installed)) { return }

    $network_name = Read-Host "请输入网络名称"
    $network_secret = Read-Host "请输入网络密钥"
    $virtual_ip = Read-Host "请输入此节点虚拟IP (留空则启用DHCP)"

    Create-DefaultConfig

    Set-TomlValue "network_name" "`"$network_name`"" $ConfigFile
    Set-TomlValue "network_secret" "`"$network_secret`"" $ConfigFile

    if ([string]::IsNullOrWhiteSpace($virtual_ip)) {
        Write-Host "未输入IP，将启用 DHCP 自动获取地址。" -ForegroundColor $c_yellow
        Set-TomlValue "dhcp" "true" $ConfigFile
        Set-TomlValue "ipv4" "`"`"" $ConfigFile
    } else {
        Write-Host "已设置静态IP: $virtual_ip" -ForegroundColor $c_green
        Set-TomlValue "dhcp" "false" $ConfigFile
        Set-TomlValue "ipv4" "`"$virtual_ip`"" $ConfigFile
    }

    # 默认添加公共对端节点
    $peer_address = "tcp://public.easytier.top:11010"
    Write-Host "默认连接到公共对端节点: $peer_address" -ForegroundColor $c_green
    Add-Content -Path $ConfigFile -Value "`n[[peer]]`nuri = `"$peer_address`""

    Write-Host "正在创建并配置 Windows 服务..." -ForegroundColor $c_yellow
    # 如果服务存在, 先删除旧的, 以确保配置更新
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        # 使用 sc.exe delete 比 Remove-Service 更可靠
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }
    
    # 创建服务
    $binaryPathWithArgs = "`"$CoreBinaryPath`" -c `"$ConfigFile`""
    New-Service -Name $ServiceName -BinaryPathName $binaryPathWithArgs -DisplayName $ServiceDisplayName -StartupType Automatic

    # *** 关键：配置服务失败后自动重启，实现进程守护 ***
    # 第一次/第二次/后续失败后, 都在5秒后重启
    sc.exe failure $ServiceName reset=86400 actions=restart/5000/restart/5000/restart/5000 | Out-Null
    
    Write-Host "服务创建成功，正在启动..." -ForegroundColor $c_green
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 2
    Get-Service -Name $ServiceName | Format-List -Property Name, DisplayName, Status, StartType
}

function Manage-Service {
    if (-not (Check-Installed)) { return }
    if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        Write-Host "服务尚未创建。请先配置网络 (选项 2)。" -ForegroundColor $c_yellow
        return
    }

    $menu_title = "管理EasyTier服务"
    $options = @(
        "启动服务",
        "停止服务",
        "重启服务",
        "查看状态",
        "返回主菜单"
    )

    while ($true) {
        Clear-Host
        Write-Host "================ $menu_title ================" -ForegroundColor $c_cyan
        Get-Service -Name $ServiceName | Format-List -Property Name, DisplayName, Status, StartType
        Write-Host "------------------------------------------------" -ForegroundColor $c_cyan
        for ($i = 0; $i -lt $options.Count; $i++) {
            Write-Host ("{0}. {1}" -f ($i+1), $options[$i])
        }
        $choice = Read-Host "请选择操作"
        switch ($choice) {
            '1' { Start-Service -Name $ServiceName; Write-Host "服务已启动。" -ForegroundColor $c_green }
            '2' { Stop-Service -Name $ServiceName; Write-Host "服务已停止。" -ForegroundColor $c_green }
            '3' { Restart-Service -Name $ServiceName; Write-Host "服务已重启。" -ForegroundColor $c_green }
            '4' { # 状态已在顶部显示，这里刷新一次
                  Get-Service -Name $ServiceName | Format-List -Property Name, DisplayName, Status, StartType 
                }
            '5' { return }
            default { Write-Host "无效输入" -ForegroundColor $c_red }
        }
        Read-Host "按 Enter 键继续..."
    }
}

function Uninstall-EasyTier {
    Write-Host "警告: 此操作将停止服务并删除所有相关文件和配置。" -ForegroundColor $c_yellow
    $confirm = Read-Host "确定要卸载吗? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "操作已取消。"
        return
    }

    Write-Host "正在停止并删除服务..."
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2 # 等待服务删除完成
    }

    Write-Host "正在删除文件和目录..."
    if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force }
    if (Test-Path $ConfigDir) { Remove-Item -Path $ConfigDir -Recurse -Force }
    
    Write-Host "EasyTier 已成功卸载。" -ForegroundColor $c_green
}


# --- 主菜单循环 ---
function Show-MainMenu {
    Check-Admin
    while ($true) {
        Clear-Host
        Write-Host "=======================================================" -ForegroundColor $c_cyan
        Write-Host "      EasyTier 跨平台部署脚本 (Windows Edition)" -ForegroundColor $c_green
        Write-Host "=======================================================" -ForegroundColor $c_cyan
        Write-Host " 1. 安装或更新 EasyTier"
        Write-Host " 2. 配置网络并安装服务 (首次设置)"
        Write-Host "-------------------------------------------------------"
        Write-Host " 3. 管理 EasyTier 服务状态"
        Write-Host " 4. 查看 EasyTier 配置文件"
        Write-Host " 5. 查看 EasyTier 网络节点"
        Write-Host "-------------------------------------------------------"
        Write-Host " 6. 卸载 EasyTier"
        Write-Host " 0. 退出脚本"
        Write-Host "=======================================================" -ForegroundColor $c_cyan

        $choice = Read-Host "请输入选项 [0-6]"
        
        switch ($choice) {
            '1' { Install-EasyTier }
            '2' { Configure-Network }
            '3' { Manage-Service }
            '4' {
                if ((Check-Installed) -and (Test-Path $ConfigFile)) {
                    Clear-Host
                    Get-Content $ConfigFile | Write-Host
                } else {
                    Write-Host "配置文件不存在或未安装。" -ForegroundColor $c_yellow
                }
            }
            '5' {
                if (Check-Installed) {
                    Clear-Host
                    & $CliBinaryPath peer
                }
            }
            '6' { Uninstall-EasyTier }
            '0' { exit 0 }
            default { Write-Host "无效输入" -ForegroundColor $c_red }
        }
        Write-Host ""
        Read-Host "按任意键返回主菜单..."
    }
}

# --- 脚本入口 ---
Show-MainMenu