#!/usr/bin/env bash
# =============================================================
# 安装/更新三系统统一入口 Nginx 网关（宿主机）
# 可由 deploy.sh 调用，也可单独执行：
#   sudo ./deploy/setup-gateway.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env.production}"
TEMPLATE="$SCRIPT_DIR/nginx-gateway.conf"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] [WARN] $*" >&2; }
die()  { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; exit 1; }

load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
  FEIGONG_RELEASE_ROOT="${FEIGONG_RELEASE_ROOT:-$SCRIPT_DIR/release}"
  FEIGONG_API_PORT="${PORT:-${FEIGONG_API_PORT:-3003}}"
  ATTENDANCE_UPSTREAM="${ATTENDANCE_UPSTREAM:-127.0.0.1:3001}"
  PRICING_UPSTREAM="${PRICING_UPSTREAM:-127.0.0.1:3002}"
  GATEWAY_SITE_NAME="${GATEWAY_SITE_NAME:-unified-gateway}"
}

ensure_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    return 0
  fi
  log "安装 nginx..."
  sudo apt-get update -qq
  sudo apt-get install -y nginx
}

port80_process() {
  ss -tlnp 2>/dev/null | grep ':80 ' || true
}

detect_nginx_conflict() {
  log "检测 nginx / 80 端口冲突..."
  local listeners enabled_count backup_dir
  listeners="$(port80_process)"
  if [ -n "$listeners" ]; then
    log "当前 :80 监听："
    echo "$listeners" | sed 's/^/  /'
  fi

  enabled_count=0
  if [ -d /etc/nginx/sites-enabled ]; then
    enabled_count="$(find /etc/nginx/sites-enabled -maxdepth 1 -type f -o -type l 2>/dev/null | wc -l)"
  fi
  log "sites-enabled 站点数: ${enabled_count}"

  backup_dir="/etc/nginx/sites-enabled.backup.$(date +%Y%m%d%H%M%S)"
  if [ -d /etc/nginx/sites-enabled ] && [ "$enabled_count" -gt 0 ]; then
    log "备份现有 sites-enabled → ${backup_dir}"
    sudo mkdir -p "$backup_dir"
    sudo cp -a /etc/nginx/sites-enabled/. "$backup_dir/" 2>/dev/null || true
  fi

  # 禁用其它占用 80 的站点（保留即将安装的统一网关）
  local site dest
  dest="/etc/nginx/sites-available/${GATEWAY_SITE_NAME}"
  if [ -d /etc/nginx/sites-enabled ]; then
    for site in /etc/nginx/sites-enabled/*; do
      [ -e "$site" ] || continue
      local base resolved
      base="$(basename "$site")"
      resolved="$(readlink -f "$site" 2>/dev/null || echo "$site")"
      if [ "$resolved" = "$dest" ]; then
        continue
      fi
      if grep -qE 'listen\s+(\[::\]:)?80(\s+default_server)?' "$site" 2>/dev/null || \
         grep -qE 'listen\s+(\[::\]:)?80(\s+default_server)?' "$resolved" 2>/dev/null; then
        warn "禁用旧 80 站点: ${base}（已备份）"
        sudo rm -f "$site"
      fi
    done
  fi

  # 若 Docker 云餐 nginx 仍占用 80，停止它
  if docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -q 'feigong-nginx.*0.0.0.0:80->'; then
    warn "检测到 feigong-nginx 占用 80，停止 Docker nginx（改由宿主机网关）"
    docker stop feigong-nginx 2>/dev/null || true
    docker rm feigong-nginx 2>/dev/null || true
  fi
}

render_config() {
  [ -f "$TEMPLATE" ] || die "缺少模板: $TEMPLATE"
  [ -d "$FEIGONG_RELEASE_ROOT/admin-web" ] || die "admin-web 未构建: $FEIGONG_RELEASE_ROOT/admin-web"
  [ -d "$FEIGONG_RELEASE_ROOT/employee-app" ] || die "employee-app 未构建: $FEIGONG_RELEASE_ROOT/employee-app"

  local dest="/etc/nginx/sites-available/${GATEWAY_SITE_NAME}"
  log "渲染网关配置 → ${dest}"
  sed \
    -e "s|@FEIGONG_RELEASE_ROOT@|${FEIGONG_RELEASE_ROOT}|g" \
    -e "s|@FEIGONG_API_PORT@|${FEIGONG_API_PORT}|g" \
    -e "s|@ATTENDANCE_UPSTREAM@|${ATTENDANCE_UPSTREAM}|g" \
    -e "s|@PRICING_UPSTREAM@|${PRICING_UPSTREAM}|g" \
    "$TEMPLATE" | sudo tee "$dest" >/dev/null

  sudo ln -sf "$dest" "/etc/nginx/sites-enabled/${GATEWAY_SITE_NAME}"
}

reload_nginx() {
  log "校验并重载 nginx..."
  sudo nginx -t
  sudo systemctl enable nginx 2>/dev/null || true
  sudo systemctl reload nginx
  log "nginx reload 成功"
}

verify_routes() {
  log "验证路由..."
  local ok=0
  curl -fsS -o /dev/null "http://127.0.0.1/api/health" && log "  ✓ /api/health" || { warn "  ✗ /api/health"; ok=1; }
  curl -fsS -o /dev/null -I "http://127.0.0.1/admin/" && log "  ✓ /admin/" || warn "  ✗ /admin/"
  curl -fsS -o /dev/null -I "http://127.0.0.1/" && log "  ✓ /" || warn "  ✗ /"
  curl -fsS -o /dev/null -I "http://127.0.0.1/attendance/" && log "  ✓ /attendance/" || warn "  ✗ /attendance/（考勤 upstream 可能未启动）"
  curl -fsS -o /dev/null -I "http://127.0.0.1/pricing/" && log "  ✓ /pricing/" || warn "  ✗ /pricing/（报价 upstream 可能未启动）"
  return "$ok"
}

print_urls() {
  local ip url
  ip="$(curl -fsS --max-time 5 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(curl -fsS --max-time 5 ifconfig.me 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  url="http://${ip:-127.0.0.1}"

  echo ""
  echo "============================================================"
  echo "  三系统统一入口（宿主机 nginx :80）"
  echo "============================================================"
  echo "  非攻云餐 员工端   : ${url}/"
  echo "  非攻云餐 管理后台 : ${url}/admin/"
  echo "  非攻云餐 API     : ${url}/api/health"
  echo "  考勤系统         : ${url}/attendance/"
  echo "  报价系统         : ${url}/pricing/"
  echo ""
  echo "  后端端口：云餐 ${FEIGONG_API_PORT} | 考勤 3001 | 报价 3002"
  echo "  重载网关：sudo ./deploy/setup-gateway.sh"
  echo "============================================================"
}

main() {
  load_env
  ensure_nginx
  detect_nginx_conflict
  render_config
  reload_nginx
  verify_routes || true
  if [ "${SKIP_URL_PRINT:-0}" != "1" ]; then
    print_urls
  fi
}

main "$@"
