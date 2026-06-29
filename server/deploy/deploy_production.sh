#!/usr/bin/env bash
# =============================================================
# 非攻云餐 生产部署脚本（Linux）
#
# 用法（在服务器上，需 root 或 sudo）：
#   cd /path/to/feigong-yuncan/server
#   chmod +x deploy/deploy_production.sh
#   sudo ./deploy/deploy_production.sh
#
# 前置条件：
#   - Node.js 18+
#   - pm2 全局安装：npm i -g pm2
#   - 已将 server 代码放到 /opt/feigong-yuncan/server（或修改 DEPLOY_ROOT）
# =============================================================
set -euo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/feigong-yuncan}"
SERVER_DIR="${SERVER_DIR:-$DEPLOY_ROOT/server}"

echo "========== 非攻云餐 生产部署 =========="
echo "DEPLOY_ROOT=$DEPLOY_ROOT"

# 1. 创建目录
for dir in app admin server data uploads backups logs; do
  mkdir -p "$DEPLOY_ROOT/$dir"
  echo "[OK] mkdir $DEPLOY_ROOT/$dir"
done

# 2. 进入 server 目录
if [ ! -f "$SERVER_DIR/package.json" ]; then
  echo "[ERROR] 未找到 $SERVER_DIR/package.json"
  echo "        请先将 server 代码同步到 $SERVER_DIR"
  exit 1
fi
cd "$SERVER_DIR"

# 3. 环境变量
if [ ! -f .env ]; then
  if [ -f .env.production.example ]; then
    cp .env.production.example .env
    echo "[WARN] 已从 .env.production.example 复制 .env，请编辑后再重启"
  else
    echo "[ERROR] 缺少 .env，请先配置"
    exit 1
  fi
fi

# 4. 安装依赖 & 编译
echo "[..] npm install --omit=dev"
npm install --omit=dev
echo "[..] npm run build"
npm run build

# 5. 商用种子数据（幂等）
echo "[..] npm run seed:commercial"
npm run seed:commercial || true

# 6. pm2 启动 / 重启
if pm2 describe feigong-yuncan-server >/dev/null 2>&1; then
  echo "[..] pm2 restart feigong-yuncan-server"
  pm2 restart ecosystem.config.js
else
  echo "[..] pm2 start ecosystem.config.js"
  pm2 start ecosystem.config.js
fi
pm2 save

echo ""
echo "========== 部署完成 =========="
echo "  后端 API : http://127.0.0.1:3000/api"
echo "  静态 App : $DEPLOY_ROOT/app/     （需手动同步 flutter build web）"
echo "  管理后台 : $DEPLOY_ROOT/admin/   （需手动同步 admin-web dist）"
echo "  上传目录 : $DEPLOY_ROOT/uploads/"
echo "  数据库   : $DEPLOY_ROOT/data/feigong-yuncan.db"
echo ""
echo "下一步："
echo "  1. 配置 Nginx: cp deploy/nginx-production.conf /etc/nginx/conf.d/"
echo "  2. 同步前端: rsync build/web/ -> $DEPLOY_ROOT/app/"
echo "  3. 同步后台: rsync admin-web/dist/ -> $DEPLOY_ROOT/admin/"
echo "  4. 验收: npm run check:release"
