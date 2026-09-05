#!/bin/bash

set -e

echo "=== 检查系统架构 ==="
ARCH=$(dpkg --print-architecture)
echo "检测到架构: $ARCH"

echo "=== 更新系统并安装依赖 ==="
sudo apt update
sudo apt install -y wget lsb-release gnupg

# 获取当前系统发行版信息
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
RELEASE=$(lsb_release -cs)
echo "检测到系统: $DISTRO $RELEASE"

if [[ "$ARCH" == "arm64" ]]; then
    # ========== ARM 分支 ==========
    echo "=== 检测到 arm64 架构，走 ARM 安装逻辑 ==="

    if [[ "$RELEASE" == "resolute" ]]; then
        # Ubuntu 26.04：Oracle 官方源暂不支持 resolute 代号，直接用系统自带仓库（MySQL 8.4）
        echo "=== 检测到 Ubuntu 26.04 (resolute)，Oracle 官方源暂不支持该代号 ==="
        echo "=== 改用 Ubuntu 自带仓库安装 MySQL（版本为 8.4）==="
        sudo apt install -y mysql-server
    else
        # 其他版本（如 24.04/22.04）：走 Oracle 官方 MySQL APT 源，非交互式安装
        echo "=== 使用 Oracle 官方 MySQL APT 源安装（非交互式）==="

        echo "下载 MySQL APT 配置包..."
        wget https://dev.mysql.com/get/mysql-apt-config_0.8.40-1_all.deb -O mysql-apt-config.deb

        echo "预配置 MySQL APT 源选项（默认选 MySQL 8.0）..."
        sudo debconf-set-selections <<EOF
mysql-apt-config mysql-apt-config/select-server select mysql-8.0
mysql-apt-config mysql-apt-config/select-product select Ok
EOF

        echo "安装 MySQL APT 配置包..."
        sudo DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config.deb

        echo "更新软件包列表..."
        sudo apt update

        if ! apt-cache policy mysql-server | grep -q "Candidate:"; then
            echo "警告：未在 MySQL 官方源中找到 arm64 的候选版本，改用系统自带仓库。"
        fi

        sudo apt install -y mysql-server
        sudo rm -rf mysql-apt-config.deb
    fi

else
    # ========== x86_64 分支（原脚本逻辑，交互式）==========
    echo "=== 检测到 $ARCH 架构，走 x86 安装逻辑 ==="

    echo "下载 MySQL APT 配置包..."
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.40-1_all.deb -O mysql-apt-config.deb

    echo "安装 MySQL APT 配置包（请在弹出的界面中选择 MySQL 8.0 或所需版本，然后按 Tab -> Enter）..."
    sudo dpkg -i mysql-apt-config.deb

    echo "更新软件包列表..."
    sudo apt update

    echo "安装 MySQL Server..."
    sudo apt install -y mysql-server

    sudo rm -rf mysql-apt-config.deb
fi

# ========== 通用部分 ==========
echo "=== 启动 MySQL 并设置为开机启动 ==="
sudo systemctl enable mysql
sudo systemctl start mysql

echo "=== MySQL 安装完成，当前状态： ==="
sudo systemctl status mysql --no-pager

echo "=== 验证版本 ==="
mysql --version
