#!/usr/bin/env bash
# Ubuntu 26.04 (resolute)：将 nginx / PostgreSQL / Redis 切换为官方源，并只安装主体
# 用法：sudo bash install_official_stack.sh
# 可选环境变量：PG_VERSION=18  NGINX_BRANCH=stable|mainline  FALLBACK_CODENAME=noble
set -euo pipefail

PG_VERSION="${PG_VERSION:-18}"
NGINX_BRANCH="${NGINX_BRANCH:-stable}"       # stable 或 mainline
FALLBACK_CODENAME="${FALLBACK_CODENAME:-noble}"

[[ $EUID -eq 0 ]] || { echo "请使用 root 或 sudo 运行"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
echo ">>> 系统代号: ${CODENAME}"

apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release

KEYRING=/usr/share/keyrings
install -d -m 0755 "$KEYRING" /etc/apt/preferences.d

# 检查官方源是否已支持当前代号，不支持则回退到上一个 LTS 代号
pick_codename() {
  local url_tpl="$1" suffix="${2:-}"
  local url="${url_tpl//@C@/${CODENAME}${suffix}}"
  if curl -fsI --max-time 15 "$url" >/dev/null 2>&1; then
    echo "$CODENAME"
  else
    echo "!!! 官方源暂无 ${CODENAME}，回退使用 ${FALLBACK_CODENAME}" >&2
    echo "$FALLBACK_CODENAME"
  fi
}

# ---------------- nginx ----------------
echo ">>> 配置 nginx 官方源 (${NGINX_BRANCH})"
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor --yes -o "$KEYRING/nginx-archive-keyring.gpg"
NGX_C="$(pick_codename 'http://nginx.org/packages/ubuntu/dists/@C@/Release')"
if [[ "$NGINX_BRANCH" == "mainline" ]]; then
  NGX_URL="http://nginx.org/packages/mainline/ubuntu"
  NGX_CHECK="http://nginx.org/packages/mainline/ubuntu/dists/${NGX_C}/Release"
  curl -fsI --max-time 15 "$NGX_CHECK" >/dev/null 2>&1 || NGX_C="$FALLBACK_CODENAME"
else
  NGX_URL="http://nginx.org/packages/ubuntu"
fi
echo "deb [signed-by=$KEYRING/nginx-archive-keyring.gpg] ${NGX_URL} ${NGX_C} nginx" \
  > /etc/apt/sources.list.d/nginx.list
cat > /etc/apt/preferences.d/99nginx <<'EOF'
Package: *
Pin: origin nginx.org
Pin-Priority: 900
EOF

# ---------------- PostgreSQL ----------------
echo ">>> 配置 PostgreSQL 官方源 (PGDG)"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --yes -o "$KEYRING/postgresql-archive-keyring.gpg"
PG_C="$(pick_codename 'https://apt.postgresql.org/pub/repos/apt/dists/@C@-pgdg/Release')"
echo "deb [signed-by=$KEYRING/postgresql-archive-keyring.gpg] https://apt.postgresql.org/pub/repos/apt ${PG_C}-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
cat > /etc/apt/preferences.d/99pgdg <<'EOF'
Package: *
Pin: release o=apt.postgresql.org
Pin-Priority: 900
EOF

# ---------------- Redis ----------------
echo ">>> 配置 Redis 官方源"
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o "$KEYRING/redis-archive-keyring.gpg"
chmod 644 "$KEYRING/redis-archive-keyring.gpg"
RD_C="$(pick_codename 'https://packages.redis.io/deb/dists/@C@/Release')"
echo "deb [signed-by=$KEYRING/redis-archive-keyring.gpg] https://packages.redis.io/deb ${RD_C} main" \
  > /etc/apt/sources.list.d/redis.list
cat > /etc/apt/preferences.d/99redis <<'EOF'
Package: *
Pin: origin packages.redis.io
Pin-Priority: 900
EOF

# ---------------- 安装（仅主体，不装推荐包/扩展/contrib） ----------------
echo ">>> 更新索引并安装"
apt-get update
apt-get install -y --no-install-recommends \
  nginx \
  "postgresql-${PG_VERSION}" \
  redis-server

systemctl enable --now nginx postgresql redis-server 2>/dev/null || true

echo
echo "================ 安装完成 ================"
nginx -v 2>&1 || true
psql --version || true
redis-server --version || true
echo "来源核对: apt-cache policy nginx postgresql-${PG_VERSION} redis-server"
