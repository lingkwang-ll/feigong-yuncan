#!/usr/bin/env bash
# 非攻云餐 生产构建脚本（Linux / macOS）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY="$(cd "$(dirname "$0")" && pwd)"

echo "========== 非攻云餐 生产构建 =========="

echo "[1/3] 构建 server..."
cd "$ROOT/server"
npm install
npm run build
test -f dist/db/schema.sql

echo "[2/3] 构建 admin-web..."
cd "$ROOT/admin-web"
export VITE_API_BASE_URL=/api
npm install
npm run build

echo "[3/3] 构建 Flutter Web..."
cd "$ROOT"
flutter pub get
flutter build web --release \
  --base-href "/" \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=/api

RELEASE="$DEPLOY/release"
rm -rf "$RELEASE"
mkdir -p "$RELEASE/admin-web" "$RELEASE/employee-app"
cp -a "$ROOT/admin-web/dist/." "$RELEASE/admin-web/"
cp -a "$ROOT/build/web/." "$RELEASE/employee-app/"

echo "[OK] 构建完成 -> deploy/release/"
