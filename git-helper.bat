@echo off
cd /d %~dp0
chcp 65001 >nul
cls

echo Git Helper v1.0.1
echo.

color 0A
title Git Helper Menu

echo ========================================
echo            Git Helper Menu
echo ========================================
echo.
echo  [1] Init and First Push
echo  [2] Update and Push Changes
echo.
echo ========================================
set /p choice="Please select (1/2): "

if "%choice%"=="1" (
    echo ===== 临时关闭 SSL 验证 =====
    git config --global http.sslVerify false

    echo ===== 初始化 Git 仓库 =====
    git init

    echo ===== 创建 README.md =====
    echo # luna_kitty_spin_1117_main > README.md
    git add README.md
    git commit -m "first commit"

    echo ===== 创建并切换到主分支 =====
    git branch -M main

    echo ===== 检查远程仓库 =====
    git remote -v | findstr "origin" >nul
    if %errorlevel% equ 0 (
        echo [提示] 远程仓库已存在，建议选择选项 2
        pause
        exit /b 1
    )

    echo ===== 添加远程仓库 =====
    git remote add origin https://github.com/gameloft333/luna_kitty_spin_1117_main.git
    if %errorlevel% neq 0 (
        echo [失败] 添加远程仓库失败
        pause
        exit /b %errorlevel%
    )

    echo ===== 添加所有文件 =====
    git add .
    if %errorlevel% neq 0 (
        echo [失败] 添加文件失败
        pause
        exit /b %errorlevel%
    )

    echo ===== 推送到主分支（可能需要一些时间）=====
    echo 正在推送...请稍候...
    git push -u origin main
    if %errorlevel% neq 0 (
        echo [失败] 推送失败，正在重试...
        timeout /t 5
        echo 第二次尝试推送...
        git push -u origin main
        if %errorlevel% neq 0 (
            echo [失败] 推送再次失败
            pause
            exit /b %errorlevel%
        )
    )
) else if "%choice%"=="2" (
    echo ===== 临时关闭 SSL 验证 =====
    git config --global http.sslVerify false

    echo ===== 获取最新更改 =====
    git fetch origin main
    if %errorlevel% neq 0 (
        echo [失败] 获取更新失败
        pause
        exit /b %errorlevel%
    )

    echo ===== 合并远程更改 =====
    git pull origin main
    if %errorlevel% neq 0 (
        echo [失败] 合并更新失败
        pause
        exit /b %errorlevel%
    )

    echo ===== 显示当前状态 =====
    git status

    echo ===== 添加所有更改 =====
    git add .
    if %errorlevel% neq 0 (
        echo [失败] 添加文件失败
        pause
        exit /b %errorlevel%
    )

    echo ===== 提交更改 =====
    set /p "msg=请输入提交信息 (直接回车使用默认信息): "
    if "%msg%"=="" (
        git commit -m "Update files"
    ) else (
        git commit -m "%msg%"
    )
    if %errorlevel% neq 0 (
        echo [失败] 提交更改失败
        pause
        exit /b %errorlevel%
    )

    echo ===== 推送更改 =====
    echo 正在推送...请稍候...
    git push origin main
    if %errorlevel% neq 0 (
        echo [失败] 推送失败，正在重试...
        timeout /t 5
        echo 第二次尝试推送...
        git push origin main
        if %errorlevel% neq 0 (
            echo [失败] 推送再次失败
            pause
            exit /b %errorlevel%
        )
    )
) else (
    echo [错误] 无效的选择
    pause
    exit /b 1
)

echo ===== 重新开启 SSL 验证 =====
git config --global http.sslVerify true

echo [成功] 操作完成！
pause 