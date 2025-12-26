#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
NC='\033[0m' # 没颜色

set -e

# 更新系统并安装必要工具
echo -e "${GREEN}正在安装必要工具...${NC}"
apt update
apt install -y wget unzip curl

# 可选版本
echo -e "${GREEN}请选择要安装的 Snell Server 版本："
echo -e "1. v3.0.1"
echo -e "2. v4.0.1"
echo -e "3. v4.1.1"
echo -e "4. v5.0.0b1${NC}"
read -p "请输入数字 (1-4): " CHOICE

# 根据选择设置版本号
case "$CHOICE" in
  1) VERSION="v3.0.1"; VERSION_MAJOR="3" ;;
  2) VERSION="v4.0.1"; VERSION_MAJOR="4" ;;
  3) VERSION="v4.1.1"; VERSION_MAJOR="4" ;;
  4) VERSION="v5.0.0b1"; VERSION_MAJOR="5" ;;
  *)
    echo "无效选择，退出。"
    exit 1
    ;;
esac

# 设置文件名
FILENAME="snell-server-${VERSION}-linux-amd64.zip"

# 下载
echo -e "${GREEN}正在下载 Snell Server ${VERSION}...${NC}"

# 下载并安装 Snell Server
wget "https://dl.nssurge.com/snell/${FILENAME}"
unzip ${FILENAME} -d /usr/local/bin
rm -f ${FILENAME}
chmod +x /usr/local/bin/snell-server

# 创建配置目录
mkdir -p /etc/snell

# 启动 Snell Server 配置向导（用户需手动输入 Y 并配置）
/usr/local/bin/snell-server --wizard -c /etc/snell/snell-server.conf

# 创建 systemd 服务文件
cat > /lib/systemd/system/snell.service << EOF
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
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

# 启动并启用服务
systemctl daemon-reload
systemctl restart snell
systemctl enable snell

# 获取服务器公网IP
IP=$(curl -s https://api.ipify.org)

# 配置文件路径
CONFIG_FILE="/etc/snell/snell-server.conf"

# 提取 listen 和 psk 的值
PORT=$(grep '^listen' "$CONFIG_FILE" | awk -F ':' '{print $2}')
PSK=$(grep '^psk' "$CONFIG_FILE" | awk -F '=' '{print $2}' | tr -d ' ')

# 输出配置信息
echo
echo -e "${GREEN}Snell 配置信息：${NC}"
echo -e "${GREEN}监听地址：0.0.0.0:${PORT}${NC}"
echo -e "${GREEN}PSK：${PSK}${NC}"
echo
echo -e "${GREEN}Surge 配置：${NC}"
echo -e "${GREEN}snell, ${IP}, ${PORT}, psk=${PSK}, version=${VERSION_MAJOR}, tfo=true${NC}"