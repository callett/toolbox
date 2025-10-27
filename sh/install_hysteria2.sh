#!/usr/bin/env bash
set -e

# 颜色定义
GREEN='\033[0;32m'
NC='\033[0m' # 没颜色

# 安装依赖
echo "${GREEN}安装必要依赖${NC}"
apt update -y && apt install -y curl sudo nano

echo "${GREEN}======================"
echo "HY2 一键安装配置脚本"
echo "======================${NC}"

IP=$(curl -s https://api.ipify.org)

# 输入端口
read -p "${GREEN}请输入 HY2 监听端口（默认 443）: ${NC}" PORT
PORT=${PORT:-443}

# 输入域名
read -p "${GREEN}请输入你的域名（用于 ACME 证书）: ${NC}" DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "域名不能为空"
  exit 1
fi

# 输入邮箱
read -p "${GREEN}请输入你的邮箱（ACME 注册用）: ${NC}" EMAIL
if [[ -z "$EMAIL" ]]; then
  echo "邮箱不能为空"
  exit 1
fi

# 输入伪装 URL，可选
read -p "${GREEN}请输入伪装 URL（默认 https://bing.com）: ${NC}" MASQ_URL
MASQ_URL=${MASQ_URL:-https://bing.com}
if [[ ! "$MASQ_URL" =~ ^https?:// ]]; then
    MASQ_URL="https://$MASQ_URL"
fi

# 生成随机 22 位复杂密码
PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9+/#!()' | head -c22)

echo "生成的 HY2 密码为: ${GREEN}$PASSWORD${NC}"

# 安装 HY2
bash <(curl -fsSL https://get.hy2.sh/)

# 创建配置目录
mkdir -p /etc/hysteria

# 写入配置文件
cat >/etc/hysteria/config.yaml <<EOF
listen: :$PORT

acme:
  domains:
    - $DOMAIN
  email: $EMAIL

auth:
  type: password
  password: "$PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL
    rewriteHost: true
EOF

# 设置 systemd 服务开机启动并启动
systemctl daemon-reload
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service

echo "${GREEN}======================"
echo "HY2 安装完成！"
echo "端口: $PORT"
echo "域名: $DOMAIN"
echo "密码: $PASSWORD"
echo "伪装 URL: $MASQ_URL"
echo ""
echo "Surge 配置示例:"
echo "hysteria2 = hysteria2, $IP, $PORT, password=$PASSWORD, ecn=true, sni=$DOMAIN"
echo "======================${NC}"