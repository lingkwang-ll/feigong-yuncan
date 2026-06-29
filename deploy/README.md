# 非攻云餐 生产部署包

## 方式 A：Docker 一键启动（推荐，本机 / 云服务器均可）

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File deploy/build-release.ps1
powershell -ExecutionPolicy Bypass -File deploy/start-local.ps1
```

```bash
# Linux
chmod +x deploy/build-release.sh
./deploy/build-release.sh
docker compose -f deploy/docker-compose.yml up -d --build
```

| 入口 | 地址 |
|------|------|
| 员工/商家 Flutter Web | http://localhost:8080/ |
| 管理后台 admin-web | http://localhost:8080/admin/ |
| API（经 Nginx） | http://localhost:8080/api/ |
| API（直连 Node） | http://localhost:3000/api/ |
| 健康检查 | http://localhost:8080/api/health |

数据持久化：Docker volumes `feigong-data`、`feigong-uploads`。

## 方式 B：Linux + PM2 + Nginx（公网服务器）

```bash
cd server
npm install && npm run build
pm2 start dist/index.js --name feigong-server
pm2 save && pm2 startup

# 前端构建后同步到 /var/www/
# 使用 deploy/docker/nginx.conf 或 server/deploy/nginx-production.conf
```

构建 admin-web 时设置 `VITE_API_BASE_URL=/api` 或完整域名。

构建 Flutter 时：

```bash
flutter build web --base-href "/" --dart-define=API_BASE_URL=/api
```

## 方式 C：ZIP 离线包

执行 `deploy/package-release.ps1` 生成 `deploy/feigong-yuncan-release.zip`。
