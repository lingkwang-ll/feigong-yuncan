#!/usr/bin/env bash
# =============================================================
# 安装非攻云餐 nginx 独立路径（不覆盖考勤/报价默认站点）
#
# 用法：
#   sudo ./deploy/install-nginx-yuncan.sh
#
# 行为：
#   1. 备份 /etc/nginx
#   2. 安装 snippets/feigong-yuncan-locations.conf
#   3. 在 default_server 内注入 include（若尚未注入）
#   4. 安装域名 server block（yuncan.pheako.com）
#   5. nginx -t && systemctl reload nginx
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIPPET_SRC="$SCRIPT_DIR/snippets/feigong-yuncan-locations.conf"
DOMAIN_SRC="$SCRIPT_DIR/nginx-yuncan-domain.conf"
SNIPPET_DEST="/etc/nginx/snippets/feigong-yuncan-locations.conf"
DOMAIN_DEST="/etc/nginx/sites-available/feigong-yuncan-domain.conf"
INCLUDE_MARKER="feigong-yuncan-locations.conf"
BACKUP_ROOT="/etc/nginx.backup.$(date +%Y%m%d%H%M%S)"

PUBLIC_IP="${PUBLIC_IP:-118.31.188.176}"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] [WARN] $*" >&2; }
die()  { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; exit 1; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 sudo 运行: sudo $0"
  fi
}

backup_nginx() {
  log "备份 nginx 配置 → ${BACKUP_ROOT}"
  cp -a /etc/nginx "$BACKUP_ROOT"
  echo "$BACKUP_ROOT" > /tmp/feigong-yuncan-nginx-backup.path
  log "备份路径已记录: /tmp/feigong-yuncan-nginx-backup.path"
}

detect_nginx_conflict() {
  log "检测 nginx 冲突..."
  if ! command -v nginx >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y nginx
  fi
  local listeners
  listeners="$(ss -tlnp 2>/dev/null | grep ':80 ' || true)"
  if [ -n "$listeners" ]; then
    log "当前 :80 监听："
    echo "$listeners" | sed 's/^/  /'
  fi
  if docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -q 'feigong-nginx.*0.0.0.0:80'; then
    warn "feigong-nginx Docker 占用 80，正在停止..."
    docker stop feigong-nginx 2>/dev/null || true
    docker rm feigong-nginx 2>/dev/null || true
  fi
}

install_snippet_file() {
  [ -f "$SNIPPET_SRC" ] || die "缺少 $SNIPPET_SRC"
  mkdir -p /etc/nginx/snippets
  cp "$SNIPPET_SRC" "$SNIPPET_DEST"
  log "已安装 snippet: $SNIPPET_DEST"
}

find_default_site() {
  local f
  for f in /etc/nginx/sites-enabled/*; do
    [ -e "$f" ] || continue
    if grep -qE 'listen\s+(\[::\]:)?80.*default_server' "$f" 2>/dev/null; then
      echo "$f"
      return 0
    fi
  done
  for f in /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf; do
    [ -f "$f" ] && echo "$f" && return 0
  done
  for f in /etc/nginx/sites-enabled/*; do
    [ -e "$f" ] || continue
    if grep -qE 'listen\s+(\[::\]:)?80' "$f" 2>/dev/null; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

inject_include() {
  local site include_line
  site="$(find_default_site || true)"
  if [ -z "$site" ]; then
    warn "未找到 default 站点，创建 /etc/nginx/sites-available/feigong-yuncan-ip.conf"
    cat > /etc/nginx/sites-available/feigong-yuncan-ip.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    include /etc/nginx/snippets/feigong-yuncan-locations.conf;
}
EOF
    ln -sf /etc/nginx/sites-available/feigong-yuncan-ip.conf /etc/nginx/sites-enabled/feigong-yuncan-ip.conf
    return 0
  fi

  if grep -q "$INCLUDE_MARKER" "$site" 2>/dev/null; then
    log "default 站点已包含云餐 include: $site"
    return 0
  fi

  log "向 default 站点注入 include（不删除原有 location）: $site"
  cp -a "$site" "${site}.before-feigong-yuncan.$(date +%Y%m%d%H%M%S)"

  include_line="    include /etc/nginx/snippets/feigong-yuncan-locations.conf; # feigong-yuncan"

  awk -v inc="$include_line" '
    /^[[:space:]]*server[[:space:]]*\{/ { in_server=1 }
    in_server && /^[[:space:]]*server_name/ && !done {
      print
      print inc
      done=1
      next
    }
    { print }
  ' "$site" > "${site}.tmp" && mv "${site}.tmp" "$site"
}

install_domain_site() {
  [ -f "$DOMAIN_SRC" ] || return 0
  cp "$DOMAIN_SRC" "$DOMAIN_DEST"
  ln -sf "$DOMAIN_DEST" /etc/nginx/sites-enabled/feigong-yuncan-domain.conf
  log "已安装域名站点: $DOMAIN_DEST"
}

reload_nginx() {
  log "nginx -t"
  nginx -t
  systemctl enable nginx 2>/dev/null || true
  systemctl reload nginx
  log "nginx reload 完成"
}

verify_routes() {
  log "验证路由..."
  curl -fsS -o /dev/null -I "http://127.0.0.1/yuncan/" && log "  ✓ /yuncan/" || warn "  ✗ /yuncan/（需先部署 web 静态文件）"
  curl -fsS -o /dev/null -I "http://127.0.0.1/yuncan-admin/" && log "  ✓ /yuncan-admin/" || warn "  ✗ /yuncan-admin/"
  curl -fsS "http://127.0.0.1/yuncan-api/health" >/dev/null 2>&1 && log "  ✓ /yuncan-api/health" || warn "  ✗ /yuncan-api/health（需先启动 API :3013）"
  curl -fsS -o /dev/null -I "http://127.0.0.1/downloads/pheako-yuncan.apk" && log "  ✓ /downloads/pheako-yuncan.apk" || warn "  ✗ APK 未就绪（可稍后 cp apk）"
}

print_summary() {
  local base="http://${PUBLIC_IP}"
  echo ""
  echo "============================================================"
  echo "  非攻云餐 nginx 独立路径已安装"
  echo "============================================================"
  echo "  nginx 备份   : ${BACKUP_ROOT}"
  echo "  snippet      : ${SNIPPET_DEST}"
  echo "  域名配置     : ${DOMAIN_DEST}"
  echo ""
  echo "  员工/商家端  : ${base}/yuncan/"
  echo "  管理后台     : ${base}/yuncan-admin/"
  echo "  API 健康     : ${base}/yuncan-api/health"
  echo "  APK 下载     : ${base}/downloads/pheako-yuncan.apk"
  echo ""
  echo "  域名（需 DNS + SSL）:"
  echo "    https://yuncan.pheako.com/"
  echo "    https://yuncan.pheako.com/admin/"
  echo "    https://yuncan.pheako.com/api/health"
  echo "    https://yuncan.pheako.com/downloads/pheako-yuncan.apk"
  echo ""
  echo "  考勤/报价默认 / 未改动"
  echo "============================================================"
}

main() {
  require_root
  detect_nginx_conflict
  backup_nginx
  install_snippet_file
  inject_include
  install_domain_site
  reload_nginx
  verify_routes || true
  print_summary
}

main "$@"
