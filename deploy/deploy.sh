#!/usr/bin/env bash
# =============================================================
# 非攻云餐 一键生产部署脚本
# 目标环境：阿里云 ECS Ubuntu 24.04
#
# 用法：
#   chmod +x deploy/deploy.sh
#   ./deploy/deploy.sh
#
# 架构：
#   多系统：宿主机 nginx :80 统一入口 → / /admin /api /attendance /pricing
#   api    :3003（127.0.0.1，避开 3001/3002）
# =============================================================
set -euo pipefail

API_PORT="${API_PORT:-3003}"
HTTP_PORT="${HTTP_PORT:-80}"
SKIP_GIT_PULL="${SKIP_GIT_PULL:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_DIR="$SCRIPT_DIR/release"
ENV_FILE="$SCRIPT_DIR/.env.production"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] [WARN] $*" >&2; }
die()  { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tln | grep -q ":${port} "
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -tln | grep -q ":${port} "
    return $?
  fi
  return 1
}

port_used_by_docker_nginx() {
  docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -q 'feigong-nginx.*:80->' && return 0
  return 1
}

host_nginx_on_80() {
  if command -v nginx >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ':80 '; then
    ss -tlnp 2>/dev/null | grep ':80 ' | grep -qv 'docker' && return 0
    # nginx 进程监听 80 也算
    ss -tlnp 2>/dev/null | grep ':80 ' | grep -q 'nginx' && return 0
  fi
  return 1
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return 0
  fi
  log "安装 Docker（Ubuntu）..."
  require_cmd curl
  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  log "Docker 已安装；如首次加入 docker 组，请重新登录后再执行本脚本"
}

ensure_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    local major
    major="$(node -v | sed 's/v//' | cut -d. -f1)"
    if [ "$major" -ge 18 ]; then
      return 0
    fi
  fi
  log "安装 Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
}

ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi
  die "未检测到 Flutter SDK。请先安装 Flutter 或将 SKIP_FLUTTER=1 且手动同步 deploy/release/employee-app"
}

check_ports() {
  log "检测端口（云餐 API ${API_PORT}；考勤 3001 / 报价 3002 保留）..."
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
  for p in 3001 3002; do
    if port_in_use "$p"; then
      log "端口 ${p} 已占用（其它系统，保留）"
    fi
  done
  if port_in_use "$API_PORT"; then
    if docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep feigong-api | grep -q ":${API_PORT}->"; then
      log "端口 ${API_PORT} 由 feigong-api 占用，将重启"
    else
      die "端口 ${API_PORT} 已被非云餐进程占用"
    fi
  fi

  if [ "${GATEWAY_ENABLED:-1}" = "1" ]; then
    if port_in_use "$HTTP_PORT"; then
      if host_nginx_on_80; then
        log "端口 ${HTTP_PORT} 由宿主机 nginx 占用（统一网关模式，将更新配置并 reload）"
      elif port_used_by_docker_nginx; then
        warn "端口 ${HTTP_PORT} 由 feigong-nginx 占用，将停止 Docker nginx 并改用宿主机网关"
      else
        die "端口 ${HTTP_PORT} 被未知进程占用，请先释放或调整 GATEWAY_ENABLED"
      fi
    fi
  else
    if port_in_use "$HTTP_PORT"; then
      die "standalone 模式需要空闲的 ${HTTP_PORT} 端口"
    fi
  fi
}

stop_old_stack() {
  log "停止旧容器..."
  cd "$SCRIPT_DIR"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans 2>/dev/null || true
  docker rm -f feigong-api feigong-web feigong-nginx 2>/dev/null || true
}

git_pull() {
  if [ "$SKIP_GIT_PULL" = "1" ]; then
    warn "SKIP_GIT_PULL=1，跳过 git pull"
    return 0
  fi
  if [ -d "$PROJECT_ROOT/.git" ]; then
    log "git pull..."
    cd "$PROJECT_ROOT"
    git pull --ff-only || warn "git pull 失败，继续使用当前代码"
  else
    warn "非 git 仓库，跳过 git pull"
  fi
}

load_env() {
  if [ ! -f "$ENV_FILE" ]; then
    die "缺少 $ENV_FILE"
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  export DATABASE_PATH="${DATABASE_PATH:-${DB_PATH:-/data/feigong.db}}"
}

detect_public_url() {
  local ip=""
  ip="$(curl -fsS --max-time 5 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    ip="$(curl -fsS --max-time 5 ifconfig.me 2>/dev/null || true)"
  fi
  if [ -z "$ip" ]; then
    ip="$(curl -fsS --max-time 5 icanhazip.com 2>/dev/null || true)"
  fi
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  echo "$ip"
}

build_server() {
  log "[1/3] 构建 server..."
  cd "$PROJECT_ROOT/server"
  npm ci
  npm run build
  test -f dist/db/schema.sql || die "dist/db/schema.sql 缺失，请检查 copy-static.js"
}

build_admin_web() {
  log "[2/3] 构建 admin-web..."
  cd "$PROJECT_ROOT/admin-web"
  export VITE_API_BASE_URL=/api
  npm ci
  npm run build
}

build_employee_web() {
  if [ "${SKIP_FLUTTER:-0}" = "1" ]; then
    warn "SKIP_FLUTTER=1，跳过 Flutter 构建（需已有 deploy/release/employee-app）"
    return 0
  fi
  log "[3/3] 构建 Flutter Web..."
  ensure_flutter
  cd "$PROJECT_ROOT"
  flutter pub get
  flutter build web --release \
    --base-href "/" \
    --dart-define=ENV=prod \
    --dart-define=API_BASE_URL=/api
}

stage_release() {
  log "汇总静态资源到 deploy/release..."
  rm -rf "$RELEASE_DIR"
  mkdir -p "$RELEASE_DIR/admin-web" "$RELEASE_DIR/employee-app"
  cp -a "$PROJECT_ROOT/admin-web/dist/." "$RELEASE_DIR/admin-web/"
  if [ "${SKIP_FLUTTER:-0}" != "1" ]; then
    cp -a "$PROJECT_ROOT/build/web/." "$RELEASE_DIR/employee-app/"
  elif [ ! -f "$RELEASE_DIR/employee-app/index.html" ]; then
    die "employee-app 构建产物不存在"
  fi
  test -f "$RELEASE_DIR/admin-web/index.html" || die "admin-web index.html 缺失"
}

docker_up() {
  log "启动 Docker Compose..."
  cd "$SCRIPT_DIR"
  if [ "${GATEWAY_ENABLED:-1}" = "1" ]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build --remove-orphans api
    docker rm -f feigong-nginx 2>/dev/null || true
  else
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile standalone up -d --build --remove-orphans
  fi
}

setup_gateway() {
  if [ "${GATEWAY_ENABLED:-1}" != "1" ]; then
    warn "GATEWAY_ENABLED!=1，跳过宿主机统一网关"
    return 0
  fi
  export FEIGONG_RELEASE_ROOT="${FEIGONG_RELEASE_ROOT:-$RELEASE_DIR}"
  if [ -z "$FEIGONG_RELEASE_ROOT" ] || [ "$FEIGONG_RELEASE_ROOT" = "$SCRIPT_DIR/release" ]; then
    export FEIGONG_RELEASE_ROOT="$RELEASE_DIR"
  fi
  log "安装宿主机统一 nginx 网关..."
  SKIP_URL_PRINT=1 bash "$SCRIPT_DIR/setup-gateway.sh"
}

wait_healthy() {
  log "等待 API 健康检查..."
  local i
  for i in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${API_PORT}/api/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  die "API 健康检查超时，请执行: docker compose -f deploy/docker-compose.yml logs api"
}

print_summary() {
  local ip url
  ip="$(detect_public_url)"
  url="http://${ip}"

  if grep -q 'PUBLIC_BASE_URL=http://127.0.0.1' "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^PUBLIC_BASE_URL=.*|PUBLIC_BASE_URL=${url}|" "$ENV_FILE" || true
  fi

  echo ""
  echo "============================================================"
  echo "  非攻云餐 部署完成"
  echo "============================================================"
  if [ "${GATEWAY_ENABLED:-1}" = "1" ]; then
    echo "  统一入口   : ${url} （宿主机 nginx :80）"
    echo "  员工/商家端 : ${url}/"
    echo "  管理后台   : ${url}/admin/"
    echo "  API 健康   : ${url}/api/health"
    echo "  考勤系统   : ${url}/attendance/"
    echo "  报价系统   : ${url}/pricing/"
  else
    echo "  员工/商家端 : ${url}/"
    echo "  管理后台   : ${url}/admin/"
    echo "  API 健康   : ${url}/api/health"
  fi
  echo "  API 本机   : http://127.0.0.1:${API_PORT}/api/health"
  echo ""
  echo "  容器状态   : docker compose -f deploy/docker-compose.yml ps"
  echo "  查看日志   : docker compose -f deploy/docker-compose.yml logs -f api"
  echo "  网关重载   : sudo ./deploy/setup-gateway.sh"
  echo "  网关日志   : sudo tail -f /var/log/nginx/unified-gateway-access.log"
  echo "============================================================"
}

main() {
  log "========== 非攻云餐 生产部署开始 =========="
  ensure_docker
  ensure_node
  check_ports
  stop_old_stack
  git_pull
  load_env
  build_server
  build_admin_web
  build_employee_web
  stage_release
  docker_up
  wait_healthy
  setup_gateway
  print_summary
}

main "$@"
