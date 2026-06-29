#!/usr/bin/env bash
# =============================================================
# 非攻云餐 —— 服务器首次部署脚本
#
# 假设：
#   - 已 ssh 登录服务器（CentOS 7+ / Ubuntu 20+）
#   - 已 yum install -y git nodejs npm  /  apt install -y git nodejs npm
#   - Node.js >= 18
#
# 用法：
#   sudo bash install_server.sh
#
# 执行后形成：
#   /opt/feigong-yuncan/
#   ├── app/        （等你把 build/web 上传到这里）
#   ├── server/     （git 仓库 server 目录的副本，外面手动放）
#   ├── data/       （SQLite）
#   ├── uploads/    （上传文件）
#   ├── backups/    （数据库备份）
#   └── logs/       （pm2 / nginx 日志）
# =============================================================
set -euo pipefail

ROOT=/opt/feigong-yuncan

echo "==> create dirs under $ROOT"
sudo mkdir -p "$ROOT"/{app,server,data,uploads,backups,logs}

# 把 uploads / data / backups / logs 写权限交给当前用户
USER_NAME="${SUDO_USER:-$USER}"
sudo chown -R "$USER_NAME":"$USER_NAME" "$ROOT"/{app,data,uploads,backups,logs}

echo "==> ensure pm2"
if ! command -v pm2 >/dev/null 2>&1; then
  echo "   installing pm2 globally..."
  sudo npm install -g pm2
fi

echo "==> done. next steps:"
cat <<EOF

  1) 上传 server 代码：
     rsync -av --exclude node_modules --exclude dist \\
       <本地>/server/  $ROOT/server/

  2) 配置 .env：
     cd $ROOT/server
     cp .env.production.example .env
     vim .env       # 把 <服务器IP> 改成实际地址

  3) 安装依赖并构建：
     cd $ROOT/server
     npm install
     npm run build

  4) 初始化数据（仅首次）：
     npm run reset:db:seed

  5) 启动后端（pm2）：
     pm2 start ecosystem.config.js
     pm2 save
     pm2 startup    # 跟随系统自启
     # 按提示再执行一条 sudo env ... 命令

  6) 上传前端：
     # 本地构建
     flutter build web \\
       --base-href "/yuncan/" \\
       --dart-define=API_BASE_URL=http://<服务器IP>/yuncan-api
     # 上传到服务器
     rsync -av build/web/  <user>@<服务器IP>:$ROOT/app/

  7) 配置 Nginx：
     sudo cp $ROOT/server/deploy/nginx-feigong-yuncan.conf \\
             /etc/nginx/conf.d/feigong-yuncan.conf
     sudo nginx -t && sudo systemctl reload nginx

  8) 体检：
     cd $ROOT/server
     npm run check:ready
     # 浏览器访问 http://<服务器IP>/yuncan/

EOF
