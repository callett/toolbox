#!/bin/bash

set -e

echo "=== 检查系统架构 ==="
ARCH=$(dpkg --print-architecture)
echo "检测到架构: $ARCH"

echo "=== 更新系统 ==="
sudo apt update

echo "=== 安装依赖 ==="
sudo apt install -y gnupg2 lsb-release

RELEASE=$(lsb_release -cs)
echo "检测到系统代号: $RELEASE"

if [[ "$ARCH" == "arm64" && "$RELEASE" == "resolute" ]]; then
    # ========== ARM + Ubuntu 26.04 分支 ==========
    # 系统自带仓库已提供 Redis 8.0.x，直接装，不用加第三方源
    echo "=== 检测到 arm64 + Ubuntu 26.04 (resolute) ==="
    echo "=== 系统自带仓库已提供 Redis 8.0.x，直接安装 ==="
    sudo apt install -y redis-server

else
    # ========== 其他情况：走 Redis 官方源（原脚本逻辑）==========
    echo "=== 使用 Redis 官方源安装 ==="

    echo "添加 Redis 官方源..."
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $RELEASE main" | sudo tee /etc/apt/sources.list.d/redis.list

    echo "更新软件源..."
    sudo apt update

    if ! apt-cache policy redis | grep -q "Candidate:"; then
        echo "警告：官方源暂未提供 $RELEASE / $ARCH 的候选包，改用系统自带仓库。"
        sudo rm -f /etc/apt/sources.list.d/redis.list
        sudo apt update
        sudo apt install -y redis-server
    else
        sudo apt install -y redis
    fi
fi

# ========== 通用部分 ==========
echo "=== 启动并设置开机自启 ==="
sudo systemctl enable redis-server
sudo systemctl start redis-server

echo "=== 查看 Redis 状态 ==="
sudo systemctl status redis-server --no-pager

echo "=== 验证 Redis 安装 ==="
redis-server --version
redis-cli --version
