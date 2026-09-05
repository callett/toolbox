#!/bin/bash
#
# RabbitMQ 一键安装脚本 (Ubuntu, 区分 amd64 / arm64)
#
# 修复说明:
# 1. 原脚本用的 dl.bintray.com 源已于2021年关停，任何架构下都会 404，与 arm/amd 无关。
# 2. RabbitMQ 官方 Cloudsmith/deb1/deb2 仓库目前只提供 amd64 的 Erlang 包，
#    arm64 没有对应源，因此 arm64 改用 Ubuntu 自带仓库(版本可能略旧，但稳定可用)。
# 3. RabbitMQ 新版本默认 guest/guest 只能本机(loopback)登录管理页面，
#    远程访问需要额外创建一个管理员账号，原脚本没处理这一点，这里补上。
#
set -e

IP=$(curl -s https://api.ipify.org)
ARCH="$(dpkg --print-architecture)"   # amd64 / arm64
CODENAME="$(lsb_release -cs)"

echo "🟡 检测到系统架构: ${ARCH}, 发行代号: ${CODENAME}"

echo "🟡 正在更新系统软件包..."
sudo apt update && sudo apt upgrade -y

echo "🟡 安装基础依赖..."
sudo apt install -y curl gnupg apt-transport-https

if [[ "$ARCH" == "amd64" ]]; then
  echo "🟡 [amd64] 使用 RabbitMQ 官方最新源安装 Erlang + RabbitMQ..."

  ## RabbitMQ 官方签名密钥
  curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" \
    | sudo gpg --dearmor | sudo tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null

  sudo tee /etc/apt/sources.list.d/rabbitmq.list > /dev/null <<EOF
## Provides RabbitMQ (官方 amd64 仓库，含 Erlang 依赖)
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/ubuntu/${CODENAME} ${CODENAME} main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/ubuntu/${CODENAME} ${CODENAME} main
EOF

  sudo apt update
  sudo apt install -y erlang-base erlang-asn1 erlang-crypto erlang-eldap erlang-ftp \
    erlang-inets erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
    erlang-runtime-tools erlang-snmp erlang-ssl erlang-syntax-tools erlang-tftp \
    erlang-tools erlang-xmerl
  sudo apt install -y rabbitmq-server --fix-missing

else
  echo "🟡 [arm64] RabbitMQ 官方源不提供 arm64 的 Erlang 包，改用 Ubuntu 自带仓库安装..."
  echo "    (版本可能不是最新，但对 arm64 更稳定，无需额外配置第三方源)"

  sudo apt install -y erlang rabbitmq-server
fi

echo "🟢 启动 RabbitMQ 服务并设置开机自启..."
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server

echo "🟢 启用 RabbitMQ Web 管理插件..."
sudo rabbitmq-plugins enable rabbitmq_management

echo "🟡 配置 RabbitMQ 监听所有 IP 地址..."
sudo bash -c 'echo "listeners.tcp.default = 0.0.0.0:5672" > /etc/rabbitmq/rabbitmq.conf'

echo "🟡 创建可远程登录管理界面的管理员账号..."
# 新版 RabbitMQ 默认 guest 账号只允许本机(127.0.0.1)登录管理页面，
# 要在浏览器远程访问 15672 管理界面，需要单独创建一个有 administrator 权限的账号。
ADMIN_USER="admin"
ADMIN_PASS="$(openssl rand -base64 12)"

if sudo rabbitmqctl list_users | grep -q "^${ADMIN_USER}"; then
  echo "    用户 ${ADMIN_USER} 已存在，跳过创建"
else
  sudo rabbitmqctl add_user "${ADMIN_USER}" "${ADMIN_PASS}"
  sudo rabbitmqctl set_user_tags "${ADMIN_USER}" administrator
  sudo rabbitmqctl set_permissions -p / "${ADMIN_USER}" ".*" ".*" ".*"
fi

echo "🔁 重启 RabbitMQ 服务以应用配置..."
sudo systemctl restart rabbitmq-server

echo "✅ 安装与配置完成！"
echo "=================================================="
echo "🌐 管理界面地址：http://${IP}:15672"
echo "🔐 远程登录账号：${ADMIN_USER} / ${ADMIN_PASS}"
echo "   (guest/guest 默认只能通过 127.0.0.1 本机登录，远程请用上面这个账号)"
echo "   请务必记下这个密码，脚本不会再次显示"
echo "=================================================="
