#!/usr/bin/env bash
#
# install_postgresql.sh
# 自动识别 CPU 架构(x86_64 / arm64) 与系统版本(Debian 12 及后续版本、Ubuntu 26.04 等)，
# 添加 PostgreSQL 官方 PGDG 仓库并安装指定版本的 PostgreSQL。
#
# 用法:
#   sudo ./install_postgresql.sh            # 默认安装最新版本 (17)
#   sudo ./install_postgresql.sh 16         # 指定安装 16 版本
#
set -euo pipefail

# ---------- 参数 ----------
PG_VERSION="${1:-17}"

# ---------- 权限检查 ----------
if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 或 sudo 运行此脚本。" >&2
    exit 1
fi

# ---------- 架构检测 ----------
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    x86_64|amd64)
        DEB_ARCH="amd64"
        ;;
    aarch64|arm64)
        DEB_ARCH="arm64"
        ;;
    *)
        echo "不支持的架构: $ARCH_RAW" >&2
        exit 1
        ;;
esac
echo "==> 检测到架构: $ARCH_RAW -> $DEB_ARCH"

# ---------- 系统检测 ----------
if [[ ! -f /etc/os-release ]]; then
    echo "无法找到 /etc/os-release，无法识别系统类型。" >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release

OS_ID="${ID:-}"
OS_CODENAME="${VERSION_CODENAME:-}"

echo "==> 检测到系统: $PRETTY_NAME (ID=$OS_ID, CODENAME=$OS_CODENAME)"

case "$OS_ID" in
    debian)
        PGDG_DIST="debian"
        ;;
    ubuntu)
        PGDG_DIST="ubuntu"
        ;;
    *)
        echo "不支持的系统: $OS_ID (仅支持 Debian / Ubuntu)" >&2
        exit 1
        ;;
esac

# ---------- 检查 PGDG 仓库是否已支持该 codename ----------
# 如果太新的发行版(如刚发布不久的 Ubuntu 26.04)PGDG 尚未收录，
# 自动回退到最近的已知可用 codename，保证脚本兼容未来版本。
PGDG_BASE_URL="https://apt.postgresql.org/pub/repos/apt"
FALLBACK_UBUNTU="noble"   # 24.04 LTS，作为找不到新版本仓库时的兜底
FALLBACK_DEBIAN="bookworm" # Debian 12，作为找不到新版本仓库时的兜底

check_codename_supported() {
    local dist="$1" codename="$2"
    curl -fsSL --head "${PGDG_BASE_URL}/dists/${codename}-pgdg/Release" \
        -o /dev/null 2>/dev/null
}

apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg lsb-release >/dev/null

if ! check_codename_supported "$PGDG_DIST" "$OS_CODENAME"; then
    if [[ "$PGDG_DIST" == "ubuntu" ]]; then
        echo "警告: PGDG 仓库尚未收录 $OS_CODENAME，回退使用 $FALLBACK_UBUNTU 的仓库源。"
        OS_CODENAME="$FALLBACK_UBUNTU"
    else
        echo "警告: PGDG 仓库尚未收录 $OS_CODENAME，回退使用 $FALLBACK_DEBIAN 的仓库源。"
        OS_CODENAME="$FALLBACK_DEBIAN"
    fi
fi

echo "==> 使用 PGDG 仓库代号: $OS_CODENAME"

# ---------- 添加官方 GPG Key ----------
install -d /usr/share/postgresql-common/pgdg
curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc

# ---------- 添加软件源(带上架构信息) ----------
echo "deb [arch=${DEB_ARCH} signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] ${PGDG_BASE_URL} ${OS_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list

# ---------- 安装 ----------
apt-get update -qq

echo "==> 正在安装 PostgreSQL ${PG_VERSION} ..."
apt-get install -y \
    "postgresql-${PG_VERSION}" \
    "postgresql-client-${PG_VERSION}" \
    "postgresql-contrib-${PG_VERSION}"

# ---------- 启动并设置开机自启 ----------
systemctl enable --now postgresql

echo "=================================================="
echo "PostgreSQL ${PG_VERSION} 安装完成！"
systemctl status postgresql --no-pager -l | head -n 5
echo "--------------------------------------------------"
echo "使用以下命令进入数据库:"
echo "  sudo -i -u postgres psql"
echo "=================================================="
