@echo off
setlocal enabledelayedexpansion

:menu
cls
@echo off
title rclone工具箱

color 0a
echo.
echo 请选择操作：
echo.
echo 1. 拷贝文件
echo.
echo 2. 同步文件
echo.
echo 3. 挂载网盘
echo.
echo 4. 查看网盘根目录
echo.
echo 5. 查看历史记录
echo.
echo 6. 退出
echo.
echo.


set /p choice=请输入操作编号：
echo.
if "%choice%"=="1" (
    call :copy_files
) else if "%choice%"=="2" (
    call :sync_files
) else if "%choice%"=="3" (
    call :mount_drive
) else if "%choice%"=="4" (
    call :view_drive_root
) else if "%choice%"=="5" (
    call :view_history
) else if "%choice%"=="6" (
    goto :eof
) else (
    echo 无效的选择，请重新输入。
    pause
    goto :menu
)

goto :menu

:copy_files
set /p source=请输入源文件路径：
set /p destination=请输入目标文件路径:

rclone copy "%source%" "%destination%" -u -v -P --transfers=20 --ignore-errors --buffer-size=128M --check-first --checkers=10 --drive-acknowledge-abuse
set /a line_count=0
for /f %%l in (history_commands.txt) do set /a line_count+=1
echo !line_count!. rclone copy "%source%" "%destination%" -u -v -P --transfers=20 --ignore-errors --buffer-size=128M --check-first --checkers=10 --drive-acknowledge-abuse >> history_commands.txt
pause
goto :eof

:sync_files
set /p source=请输入源文件路径：
set /p destination=请输入目标文件路径:

rclone sync "%source%" "%destination%" -u -v -P --transfers=20 --ignore-errors --buffer-size=128M --check-first --checkers=10 --drive-acknowledge-abuse
set /a line_count=0
for /f %%l in (history_commands.txt) do set /a line_count+=1
echo !line_count!. rclone sync "%source%" "%destination%" -u -v -P --transfers=20 --ignore-errors --buffer-size=128M --check-first --checkers=10 --drive-acknowledge-abuse >> history_commands.txt
pause
goto :eof

:mount_drive
set /p source=请输入网盘路径：
set /p drive_letter=请输入挂载盘符：
set /p cache_dir=请输入缓存目录：

rclone mount "%source%" %drive_letter%: --vfs-cache-mode full --vfs-cache-max-size 100G --vfs-cache-max-age 1h --dir-cache-time 1h --poll-interval 10s --buffer-size 128M --vfs-read-ahead 256M --cache-dir "%cache_dir%"
set /a line_count=0
for /f %%l in (history_commands.txt) do set /a line_count+=1
echo !line_count!. rclone mount "%source%" %drive_letter%: --vfs-cache-mode full --vfs-cache-max-size 100G --vfs-cache-max-age 1h --dir-cache-time 1h --poll-interval 10s --buffer-size 128M --vfs-read-ahead 256M --cache-dir "%cache_dir%" >> history_commands.txt
pause
goto :eof

:view_drive_root
set /p source=请输入网盘路径：

rclone lsd "%source%"
pause
goto :eof

:view_history
cls
echo 历史记录：
type history_commands.txt
echo.

set /p execute=请输入要执行的历史记录序号（按Enter跳过）：
if not "%execute%"=="" (
    set "found="
    for /f "tokens=1,* delims=." %%a in (history_commands.txt) do (
        if "%%a"=="%execute%" (
            set "command=%%b"
            set "found=1"
            call :execute_command
            goto :eof
        )
    )
    if not defined found (
        echo 无效的历史记录序号，请重新输入。
        pause
    )
)
goto :menu

:execute_command
cls
echo 正在执行历史记录命令：
echo %command%
%command%
pause
goto :eof

:eof
