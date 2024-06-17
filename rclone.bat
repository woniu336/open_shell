@echo off
setlocal enabledelayedexpansion

:: 设置颜色
color 0A

:: 提示信息
echo ==============================================
echo.
echo   rclone 脚本生成工具
echo   https://d.99bilibili.eu.org/rclone
echo.
echo ==============================================

:: 获取用户输入
echo.
set /p source=请输入源路径:
echo.
set /p destination=请输入目标路径:
echo.
set /p proxy=是否需要代理？(y/n):
if "%proxy%"=="" set proxy=n

:: 提示是否忽略目标目录中已有的文件，默认忽略
echo.
set /p ignore_existing=是否忽略目标目录中已有的文件？(y/n):
if "%ignore_existing%"=="" set ignore_existing=y

:: 提示同时进行的文件传输数量，默认6
echo.
set /p transfers=请输入同时进行的文件传输数量(6-20):
if "%transfers%"=="" set transfers=6

:: 创建并写入新bat脚本内容
(
echo @echo off
if /i "%proxy%"=="y" (
    echo set http_proxy=socks5://127.0.0.1:7890
    echo set https_proxy=socks5://127.0.0.1:7890
) else (
    echo set http_proxy=
    echo set https_proxy=
)
echo cd /d D:\rclone-v1.63.0-windows-amd64
if /i "%ignore_existing%"=="y" (
    echo rclone copy "%source%" "%destination%" --ignore-existing -u -v -P --transfers=%transfers% --ignore-errors --buffer-size=128M --check-first --checkers=10 --drive-acknowledge-abuse
) else (
    echo rclone copy "%source%" "%destination%" -u -v -P --transfers=%transfers% --ignore-errors --buffer-size=128M --check-first --checkers=10 --drive-acknowledge-abuse
)
echo pause
) > work001.bat

:: 提示用户
echo.
echo ==============================================
echo 新的脚本已生成: work001.bat
echo ==============================================
pause
