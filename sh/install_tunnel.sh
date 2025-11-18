#!/bin/bash
set -e

# 颜色定义
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

# 默认值
DEFAULT_TUNNEL_NAME="mytunnel"
DEFAULT_LOCAL_SERVICE="http://localhost:8080"

echo -e "${GREEN}==== Cloudflare Tunnel 一键脚本 ====${RESET}"

# 1️⃣ 安装 cloudflared
echo -e "${GREEN}安装 cloudflared...${RESET}"
curl -fsSL -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# 2️⃣ 验证安装
cloudflared -v

# 3️⃣ 登录 Cloudflare
while true; do
  echo -e "${GREEN}请登录 Cloudflare...${RESET}"
  
  LOGIN_OUTPUT=$(cloudflared tunnel login 2>&1)
  
  if echo "$LOGIN_OUTPUT" | grep -q "You have successfully logged in."; then
    echo -e "${GREEN}登录完成 ✔️${RESET}"
    break
  else
    echo -e "${RED}登录失败！${RESET}"
    echo "$LOGIN_OUTPUT"
    echo -e "${YELLOW}请选择操作：${RESET}"
    echo -e "${YELLOW}1) 重试登录${RESET}"
    echo -e "${YELLOW}2) 终止脚本${RESET}"
    read -p "输入 1 或 2: " LOGIN_CHOICE
    if [[ "$LOGIN_CHOICE" == "1" ]]; then
      echo -e "${GREEN}重新尝试登录...${RESET}"
    elif [[ "$LOGIN_CHOICE" == "2" ]]; then
      echo -e "${RED}脚本终止。请确认网络或浏览器可访问 Cloudflare 登录页面。${RESET}"
      exit 1
    else
      echo -e "${RED}无效输入，请选择 1 或 2。${RESET}"
    fi
  fi
done

# 4️⃣ 用户输入
read -p "请输入隧道名称 [默认: $DEFAULT_TUNNEL_NAME]: " TUNNEL_NAME
TUNNEL_NAME=${TUNNEL_NAME:-$DEFAULT_TUNNEL_NAME}

# 5️⃣ 创建隧道
echo -e "${GREEN}创建隧道...${RESET}"
TUNNEL_ID=$(cloudflared tunnel create "$TUNNEL_NAME" | awk '/ID/{print $3}')
echo -e "${GREEN}Tunnel ID: $TUNNEL_ID${RESET}"

while true; do
  read -p "请输入绑定的域名 (example.com) [必填]: " DOMAIN
  if [[ -n "$DOMAIN" ]]; then
    break
  else
    echo -e "${RED}域名不能为空，请重新输入！${RESET}"
  fi
done

read -p "请输入本地服务地址 [默认: $DEFAULT_LOCAL_SERVICE]: " LOCAL_SERVICE
LOCAL_SERVICE=${LOCAL_SERVICE:-$DEFAULT_LOCAL_SERVICE}

# 6️⃣ 配置文件
CREDENTIAL_FILE="/etc/cloudflared/$TUNNEL_ID.json"
sudo mkdir -p /etc/cloudflared
sudo mv "/root/.cloudflared/$TUNNEL_ID.json" "$CREDENTIAL_FILE"
sudo chown root:root "$CREDENTIAL_FILE"
sudo chmod 600 "$CREDENTIAL_FILE"

# 写 config.yml
CONFIG_FILE="/etc/cloudflared/config.yml"
sudo tee "$CONFIG_FILE" > /dev/null <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIAL_FILE

ingress:
  - hostname: $DOMAIN
    service: $LOCAL_SERVICE
  - service: http_status:404
EOF

# 7️⃣ 配置 DNS
while true; do
  if cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"; then
    echo -e "${GREEN}DNS 已成功绑定 ✔️${RESET}"
    break
  else
    echo -e "${RED}DNS 绑定失败，域名可能已被占用。${RESET}"
    echo -e "${YELLOW}请选择操作：${RESET}"
    echo -e "${YELLOW}1) 已手动操作，请重试${RESET}"
    echo -e "${YELLOW}2) 放弃 Tunnel 隧道配置${RESET}"
    read -p "输入 1 或 2: " CHOICE
    if [[ "$CHOICE" == "1" ]]; then
      echo -e "${GREEN}重新尝试绑定 DNS...${RESET}"
    elif [[ "$CHOICE" == "2" ]]; then
      echo -e "${RED}撤销 Tunnel 配置...${RESET}"
      cloudflared tunnel delete "$TUNNEL_NAME" || true
      sudo rm -f "$CREDENTIAL_FILE" "$CONFIG_FILE"
      echo -e "${RED}已撤销隧道及配置文件。脚本终止。${RESET}"
      exit 1
    else
      echo -e "${RED}无效输入，请选择 1 或 2。${RESET}"
    fi
  fi
done

# 8️⃣ 安装为 systemd 服务
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

echo -e "${GREEN}Cloudflare Tunnel 已启动！${RESET}"
echo -e "${GREEN}访问地址: https://$DOMAIN${RESET}"