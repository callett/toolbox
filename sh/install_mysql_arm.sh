#!/bin/bash

set -e

echo "=== 检查系统架构 ==="
ARCH=$(dpkg --print-architecture)

if [[ "$ARCH" != "arm64" ]]; then
    echo "警告：当前系统架构为 $ARCH，本脚本适用于 arm64(aarch64) 架构。"
    exit 1
fi

echo "检测到架构: $ARCH"

echo "=== 更新系统并安装依赖 ==="
sudo apt update
sudo apt install -y wget lsb-release gnupg

RELEASE=$(lsb_release -cs)
echo "检测到系统代号: $RELEASE"

# Oracle 官方 MySQL APT 源目前仅支持 noble(24.04) / jammy(22.04)，
# 尚未提供 resolute(26.04) 的仓库路径，所以 26.04 直接走 Ubuntu 自带仓库（MySQL 8.4）
if [[ "$RELEASE" == "resolute" ]]; then
    echo "=== 检测到 Ubuntu 26.04 (resolute)，Oracle 官方源暂不支持该代号 ==="
    echo "=== 改用 Ubuntu 自带仓库安装 MySQL（版本为 8.4）==="

    sudo apt install -y mysql-server

else
    echo "=== 非 26.04 系统，使用 Oracle 官方 MySQL APT 源安装 ==="

    echo "下载 MySQL APT 配置包..."
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.40-1_all.deb -O mysql-apt-config.deb

    echo "预配置 MySQL APT 源选项（非交互式，默认选 MySQL 8.0）..."
    sudo debconf-set-selections <<EOF
mysql-apt-config mysql-apt-config/select-server select mysql-8.0
mysql-apt-config mysql-apt-config/select-product select Ok
EOF

    echo "安装 MySQL APT 配置包..."
    sudo DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config.deb

    echo "更新软件包列表..."
    sudo apt update

    if ! apt-cache policy mysql-server | grep -q "Candidate:"; then
        echo "警告：未在 MySQL 官方源中找到 arm64 的 mysql-server 候选版本，改用系统自带仓库。"
        sudo apt install -y mysql-server
    else
        sudo apt install -y mysql-server
    fi

    sudo rm -rf mysql-apt-config.deb
fi

echo "=== 启动 MySQL 并设置为开机启动 ==="
sudo systemctl enable mysql
sudo systemctl start mysql

echo "=== MySQL 安装完成，当前状态： ==="
sudo systemctl status mysql --no-pager

echo "=== 验证版本 ==="
mysql --version
