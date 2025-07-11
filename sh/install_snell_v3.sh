#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # 重置颜色

set -e

# 随机端口（建议使用高位端口）
PORT=$((RANDOM % 10000 + 40000))

# 随机生成 22 位 PSK（包含大小写和数字）
PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 22)

# Snell 版本
VERSION="v3.0.1"
ARCH="linux-amd64"
ZIP_NAME="snell-server-${VERSION}-${ARCH}.zip"
DOWNLOAD_URL="https://raw.githubusercontent.com/callett/toolbox/main/surge/snell/${VERSION}/${ZIP_NAME}"

echo -e "${GREEN}正在安装必要工具...${NC}"
apt update
apt install -y wget unzip vim

# 下载 Snell
echo -e "${GREEN}正在下载 Snell Server ${VERSION}...${NC}"
cd /tmp
wget -O ${ZIP_NAME} ${DOWNLOAD_URL}

# 解压并移动执行文件
unzip -o ${ZIP_NAME}
mv snell-server /usr/local/bin/
chmod +x /usr/local/bin/snell-server

# 清理临时文件
rm -f ${ZIP_NAME}

# 创建配置目录
mkdir -p /etc/snell

# 生成配置文件
cat > /etc/snell/snell-server.conf <<EOF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
ipv6 = false
obfs = tls
EOF

# 创建 systemd 服务文件
cat > /lib/systemd/system/snell.service <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable --now snell

# 获取服务器公网IP
IP=$(curl -s https://api.ipify.org)

# 显示配置信息
echo
echo -e "${GREEN}✅ Snell 安装完成！${NC}"
echo -e "${GREEN}监听地址：${IP}:${PORT}${NC}"
echo -e "${GREEN}密钥（PSK）：${PSK}${NC}"