#!/usr/bin/env bash
# =============================================================
# 非攻云餐 —— 重新部署后端的便捷脚本
#
# 适用场景：拉了新代码后，重新 build + 重启 pm2 进程
#
# 用法：
#   cd /opt/feigong-yuncan/server
#   bash deploy/restart.sh
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."   # → /opt/feigong-yuncan/server

echo "==> npm install --omit=dev=false (含 devDependencies，build 时需要 typescript)"
npm install

echo "==> npm run build"
npm run build

if command -v pm2 >/dev/null 2>&1; then
  if pm2 describe feigong-yuncan-server >/dev/null 2>&1; then
    echo "==> pm2 restart feigong-yuncan-server"
    pm2 restart feigong-yuncan-server --update-env
  else
    echo "==> pm2 start ecosystem.config.js"
    pm2 start ecosystem.config.js
    pm2 save
  fi
  pm2 status feigong-yuncan-server
else
  echo "!! pm2 not installed; falling back to: npm start"
  echo "   suggestion: npm install -g pm2"
  npm start
fi
