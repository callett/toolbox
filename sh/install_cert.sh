#!/bin/bash

GREEN="\e[32m"
RED="\e[31m"
NC="\033[0m"

echo -e "${GREEN}===== ACME 自动申请证书脚本 =====${NC}"

# -------------------------------
# 0. 检查 80 端口是否被占用
# -------------------------------
if lsof -i:80 >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 80 端口被占用，请先停止占用服务（如 nginx/xray）${NC}"
    exit 1
fi


# -------------------------------
# 1. 检查并安装 socat 和 cron（只执行一次 apt update）
# -------------------------------
apt update -y

check_install() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${GREEN}[INFO] $1 未安装，正在安装...${NC}"
        apt install -y "$1"
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ERROR] $1 安装失败，请检查网络！${NC}"
            exit 1
        fi
    fi
}

check_install socat
check_install cron


# -------------------------------
# 2. 检查 acme.sh
# -------------------------------
if ! command -v acme.sh >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO] acme.sh 未安装，正在安装...${NC}"
    curl https://get.acme.sh | sh
fi

# 添加软链接（如果不存在）
if [ ! -f /usr/local/bin/acme.sh ]; then
    ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
fi

# 设置默认证书机构
acme.sh --set-default-ca --server letsencrypt


# -------------------------------
# 3. 用户选择证书类型
# -------------------------------
echo -e "${GREEN}请选择证书类型：${NC}"
echo -e "${GREEN}1) 单域名证书${NC}"
echo -e "${GREEN}2) 泛域名证书${NC}"
read -p "请输入选项 (1/2): " certType

if [ "$certType" != "1" ] && [ "$certType" != "2" ]; then
    echo -e "${RED}[ERROR] 选项无效，请输入 1 或 2${NC}"
    exit 1
fi


# 输入主域名
read -p $'\e[32m请输入你的域名（例如 example.com）：\e[0m' DOMAIN
DOMAIN_DIR="/cert/$DOMAIN"


# -------------------------------
# 4. 泛域名需要 CF_Token
# -------------------------------
if [ "$certType" = "2" ]; then
    read -p $'\e[32m请输入 Cloudflare CF_Token：\e[0m' CF_Token

    # acme.sh 官方推荐方式（不会污染 bashrc）
    export CF_Token="$CF_Token"
fi


# -------------------------------
# 5. 开始申请证书
# -------------------------------
echo -e "${GREEN}===== 正在申请证书... =====${NC}"

if [ "$certType" = "1" ]; then
    acme.sh --issue -d "$DOMAIN" --standalone
else
    acme.sh --issue --dns dns_cf -d "*.$DOMAIN" -d "$DOMAIN"
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] 证书申请失败，请检查域名解析或 DNS 配置。${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] 证书申请成功！${NC}"


# -------------------------------
# 6. 安装证书
# -------------------------------
mkdir -p "$DOMAIN_DIR"

echo -e "${GREEN}===== 正在安装证书到 $DOMAIN_DIR =====${NC}"

if [ "$certType" = "1" ]; then
    acme.sh --install-cert -d "$DOMAIN" \
        --key-file       "$DOMAIN_DIR/privkey.pem" \
        --fullchain-file "$DOMAIN_DIR/fullchain.pem"
else
    acme.sh --install-cert -d "*.$DOMAIN" \
        --key-file       "$DOMAIN_DIR/privkey.pem" \
        --fullchain-file "$DOMAIN_DIR/fullchain.pem"
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] 证书安装失败。${NC}"
    exit 1
fi


# -------------------------------
# 完成
# -------------------------------
echo -e "${GREEN}===== 证书安装完成 =====${NC}"
echo -e "${GREEN}私钥路径：$DOMAIN_DIR/privkey.pem${NC}"
echo -e "${GREEN}证书路径：$DOMAIN_DIR/fullchain.pem${NC}"
echo -e "${GREEN}=====================================${NC}"