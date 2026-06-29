#!/usr/bin/env bash
# =============================================================
# 非攻云餐 ECS 生产部署（独立路径，不影响考勤/报价）
#
# 参考「报价 App 稳定线上版」：
#   - 宿主机 nginx 仅新增 location（/yuncan/ /yuncan-admin/ /yuncan-api/ /downloads/）
#   - 后端 systemd :3003
#   - APK 静态下载
#
# 用法（在 ECS Ubuntu 上）：
#   cd /opt/feigong-yuncan
#   chmod +x deploy/deploy-production-ecs.sh deploy/install-nginx-yuncan.sh
#   sudo ./deploy/deploy-production-ecs.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/feigong-yuncan}"
PUBLIC_IP="${PUBLIC_IP:-118.31.188.176}"
API_PORT="${API_PORT:-3003}"
SKIP_GIT_PULL="${SKIP_GIT_PULL:-0}"
SKIP_FLUTTER="${SKIP_FLUTTER:-0}"
SKIP_APK="${SKIP_APK:-0}"

API_BASE_URL="http://${PUBLIC_IP}/yuncan-api"
WEB_BASE="/yuncan/"
ADMIN_BASE="/yuncan-admin/"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] [WARN] $*" >&2; }
die()  { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

ensure_node() {
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed 's/v//' | cut -d. -f1)"
    [ "$major" -ge 18 ] && return 0
  fi
  log "安装 Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
}

ensure_dirs() {
  log "创建部署目录..."
  sudo mkdir -p \
    "$DEPLOY_ROOT"/{web/yuncan,web/yuncan-admin,downloads,data,uploads,logs,server}
  sudo chown -R "$USER:$USER" "$DEPLOY_ROOT" 2>/dev/null || true
}

sync_code() {
  if [ "$SKIP_GIT_PULL" = "1" ]; then
    warn "SKIP_GIT_PULL=1"
    return 0
  fi
  if [ -d "$PROJECT_ROOT/.git" ]; then
    log "git pull..."
    cd "$PROJECT_ROOT"
    git pull --ff-only || warn "git pull 失败，继续"
  fi
}

check_ports() {
  log "检测端口（云餐 ${API_PORT}；不占用 3001/3002）..."
  for p in 3001 3002; do
    if ss -tln 2>/dev/null | grep -q ":${p} "; then
      log "  端口 ${p} 已占用（其它系统，保留）"
    fi
  done
  if ss -tln 2>/dev/null | grep -q ":${API_PORT} "; then
    if systemctl is-active --quiet feigong-yuncan-api 2>/dev/null; then
      log "  端口 ${API_PORT} 由 feigong-yuncan-api 占用，将重启"
    else
      warn "  端口 ${API_PORT} 已被占用，请确认"
    fi
  fi
}

install_server_env() {
  local env_dest="$DEPLOY_ROOT/server/.env"
  if [ ! -f "$env_dest" ]; then
    log "写入 server/.env"
    cp "$SCRIPT_DIR/env.server.production" "$env_dest"
    sed -i "s|PUBLIC_BASE_URL=.*|PUBLIC_BASE_URL=http://${PUBLIC_IP}/yuncan|" "$env_dest"
    sed -i "s|CORS_ORIGIN=.*|CORS_ORIGIN=http://${PUBLIC_IP}|" "$env_dest"
    warn "请编辑 $env_dest 修改 JWT_SECRET"
  fi
}

build_server() {
  log "[1/4] 构建 server..."
  rsync -a --delete \
    --exclude node_modules \
    --exclude data \
    --exclude uploads \
    "$PROJECT_ROOT/server/" "$DEPLOY_ROOT/server/"
  cd "$DEPLOY_ROOT/server"
  npm install
  npm run build
  test -f dist/db/schema.sql || die "dist/db/schema.sql 缺失"
}

build_admin_web() {
  log "[2/4] 构建 admin-web..."
  cd "$PROJECT_ROOT/admin-web"
  if [ -f .env.production.ecs ]; then
    cp .env.production.ecs .env.production.local
  fi
  export VITE_BASE_PATH="/yuncan-admin/"
  export VITE_API_BASE_URL="$API_BASE_URL"
  npm ci
  npm run build
  rsync -a --delete "$PROJECT_ROOT/admin-web/dist/" "$DEPLOY_ROOT/web/yuncan-admin/"
}

build_flutter_web() {
  if [ "$SKIP_FLUTTER" = "1" ]; then
    warn "SKIP_FLUTTER=1"
    return 0
  fi
  require_cmd flutter
  log "[3/4] 构建 Flutter Web..."
  cd "$PROJECT_ROOT"
  flutter pub get
  flutter build web --release \
    --base-href "$WEB_BASE" \
    --dart-define=ENV=prod \
    --dart-define=API_BASE_URL="$API_BASE_URL"
  rsync -a --delete "$PROJECT_ROOT/build/web/" "$DEPLOY_ROOT/web/yuncan/"
}

build_apk() {
  if [ "$SKIP_APK" = "1" ]; then
    warn "SKIP_APK=1，跳过 APK"
    return 0
  fi
  if ! command -v flutter >/dev/null 2>&1; then
    warn "无 Flutter，跳过 APK；Web 不受影响"
    cp "$SCRIPT_DIR/downloads/README.md" "$DEPLOY_ROOT/downloads/README.txt" 2>/dev/null || true
    return 0
  fi
  log "[4/4] 构建 APK..."
  cd "$PROJECT_ROOT"
  if flutter build apk --release \
    --dart-define=ENV=prod \
    --dart-define=API_BASE_URL="$API_BASE_URL"; then
    cp -f build/app/outputs/flutter-apk/app-release.apk \
      "$DEPLOY_ROOT/downloads/pheako-yuncan.apk"
    log "APK → $DEPLOY_ROOT/downloads/pheako-yuncan.apk"
  else
    warn "APK 构建失败，Web 仍可用"
    cp "$SCRIPT_DIR/downloads/README.md" "$DEPLOY_ROOT/downloads/README.txt" 2>/dev/null || true
  fi
}

install_systemd() {
  log "安装 systemd 服务 feigong-yuncan-api..."
  sudo cp "$SCRIPT_DIR/systemd/feigong-yuncan-api.service" /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable feigong-yuncan-api
  sudo systemctl restart feigong-yuncan-api
  sleep 2
  curl -fsS "http://127.0.0.1:${API_PORT}/api/health" >/dev/null \
    || die "API 健康检查失败: curl http://127.0.0.1:${API_PORT}/api/health"
  log "API :${API_PORT} 运行正常"
}

install_nginx() {
  log "安装 nginx 独立路径..."
  PUBLIC_IP="$PUBLIC_IP" sudo bash "$SCRIPT_DIR/install-nginx-yuncan.sh"
}

print_final() {
  local base="http://${PUBLIC_IP}"
  echo ""
  echo "============================================================"
  echo "  非攻云餐 生产部署完成"
  echo "============================================================"
  echo "  1. nginx snippet : /etc/nginx/snippets/feigong-yuncan-locations.conf"
  echo "  2. nginx 备份    : $(cat /tmp/feigong-yuncan-nginx-backup.path 2>/dev/null || echo '见 install 输出')"
  echo "  3. API 端口      : ${API_PORT} (systemd feigong-yuncan-api)"
  echo ""
  echo "  员工/商家端  : ${base}/yuncan/"
  echo "  管理后台     : ${base}/yuncan-admin/"
  echo "  API 健康     : ${base}/yuncan-api/health"
  echo "  APK 下载     : ${base}/downloads/pheako-yuncan.apk"
  echo ""
  echo "  域名（DNS 指向 ECS 后启用 nginx-yuncan-domain.conf + SSL）:"
  echo "    https://yuncan.pheako.com/"
  echo "    https://yuncan.pheako.com/admin/"
  echo "    https://yuncan.pheako.com/api/health"
  echo "    https://yuncan.pheako.com/downloads/pheako-yuncan.apk"
  echo ""
  echo "  考勤系统 / 报价系统 : 未修改默认 /"
  echo "============================================================"
}

main() {
  log "========== 非攻云餐 ECS 生产部署 =========="
  ensure_node
  ensure_dirs
  sync_code
  check_ports
  install_server_env
  build_server
  build_admin_web
  build_flutter_web
  build_apk
  install_systemd
  install_nginx
  print_final
}

main "$@"
