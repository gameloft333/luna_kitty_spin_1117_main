@echo off
chcp 65001
cls

echo ===== 初始化 Git 仓库 =====
git init

echo ===== 添加远程仓库 =====
set /p repo="请输入 GitHub 仓库地址: "
git remote add origin %repo%

echo ===== 添加所有文件 =====
git add .

echo ===== 初始提交 =====
git commit -m "Initial commit"

echo ===== 推送到主分支 =====
git push -u origin main

echo ===== 初始化完成 =====
pause 