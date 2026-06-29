# 非攻云餐 · 正式发布交付清单

本文档为正式可交付版本的上线与验收指南。

---

## 1. 后端启动

### 开发

```bash
cd server
cp .env.example .env
npm install
npm run dev
# http://localhost:3000/api
```

### 生产（PM2）

```bash
cd /opt/feigong-yuncan/server
cp .env.production.example .env   # 编辑 JWT_SECRET、PUBLIC_BASE_URL 等
npm install --omit=dev
npm run build
npm run seed:commercial
pm2 start ecosystem.config.js
pm2 save
```

---

## 2. admin-web 启动

见 [admin-web-release.md](./admin-web-release.md)

```bash
cd admin-web
npm install
npm run dev          # 开发
npm run build        # 生产 → dist/
```

---

## 3. Flutter Web 启动 / 构建

```bash
# 开发
flutter run -d chrome

# 生产（Nginx /app/ 路径）
flutter build web \
  --base-href "/app/" \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=https://your-domain.com/api
```

产物：`build/web/` → 部署到 `/opt/feigong-yuncan/app/`

---

## 4. Android APK 打包

见 [android-release.md](./android-release.md)

```bash
flutter build apk --release \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=https://your-domain.com/api
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

---

## 5. Nginx 部署

```bash
sudo cp server/deploy/nginx-production.conf /etc/nginx/conf.d/feigong-yuncan.conf
# 修改 server_name、SSL（如需要）
sudo nginx -t && sudo systemctl reload nginx
```

| 路径 | 目录 |
|------|------|
| `/app/` | `/opt/feigong-yuncan/app` |
| `/admin/` | `/opt/feigong-yuncan/admin` |
| `/api/` | 反代 `http://127.0.0.1:3000/api` |
| `/uploads/` | `/opt/feigong-yuncan/uploads` |

---

## 6. PM2 启动

```bash
cd /opt/feigong-yuncan/server
pm2 start ecosystem.config.js
pm2 save
pm2 startup    # 开机自启（按提示执行）
```

或使用一键脚本：

```bash
sudo ./deploy/deploy_production.sh
```

---

## 7. 数据备份

```bash
cd server
npm run backup:db
# 备份文件在 server/backups/ 或脚本指定目录
```

生产建议 cron 每日备份 `/opt/feigong-yuncan/data/` 到 `/opt/feigong-yuncan/backups/`。

---

## 8. 试运行账号

| 角色 | 手机号 | 说明 |
|------|--------|------|
| 平台管理员 | 13700000000 | admin-web 登录 |
| 员工 | 13800000000 / 001 / 002 | 张三 / 李四 / 王五 |
| 商家 | 13900000000 | 绿健食堂 |

初始化：

```bash
cd server
npm run seed:commercial    # 平台管理员
npm run seed:trial-users   # 试运行员工/商家
npm run prepare:trial      # 清空订单 + 试运行菜品
```

短信：`SMS_PROVIDER=mock`，验证码见服务端日志或 `sms_codes` 表。

---

## 9. 生产上线前检查

### 必跑脚本

```bash
cd server
npm run check:ready      # 8 项基础链路
npm run check:release    # 10 项正式发布验收
```

### Flutter / 前端

```bash
flutter analyze
flutter build web --dart-define=ENV=prod
flutter build apk --release --dart-define=ENV=prod
cd admin-web && npm run build
cd server && npm run build
```

### 配置核对

- [ ] `JWT_SECRET` 已改为随机强密码
- [ ] `PUBLIC_BASE_URL` 与 Nginx 域名一致
- [ ] `CORS_ORIGIN` 已限制为生产域名
- [ ] `DATABASE_PATH` / `UPLOAD_DIR` 在 `/opt/feigong-yuncan/` 下
- [ ] Android `key.properties` 已配置 Release 签名
- [ ] admin-web `.env.production` 中 `VITE_API_BASE_URL` 正确

---

## 10. 回滚方案

### 后端

```bash
pm2 stop feigong-yuncan-server
# 恢复上一版本代码
cd /opt/feigong-yuncan/server && git checkout <tag>
npm install --omit=dev && npm run build
pm2 restart feigong-yuncan-server
```

### 数据库

```bash
cp /opt/feigong-yuncan/backups/feigong-yuncan-YYYYMMDD.db \
   /opt/feigong-yuncan/data/feigong-yuncan.db
pm2 restart feigong-yuncan-server
```

### 前端静态资源

保留上一版 `app/`、`admin/` 目录备份，Nginx alias 指回旧目录即可，无需重启 Node。

### Nginx

```bash
sudo cp /etc/nginx/conf.d/feigong-yuncan.conf.bak \
        /etc/nginx/conf.d/feigong-yuncan.conf
sudo nginx -t && sudo systemctl reload nginx
```

---

## 交付物清单

| 交付物 | 路径 |
|--------|------|
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Flutter Web | `build/web/` |
| admin-web | `admin-web/dist/` |
| 后端 | `server/dist/` |
| Nginx 配置 | `server/deploy/nginx-production.conf` |
| 部署脚本 | `server/deploy/deploy_production.sh` |
| 环境样例 | `server/.env.production.example` |
| 验收脚本 | `server/scripts/final_release_check.ps1` |

---

## 版本信息

- 应用版本：`1.0.0+1`（pubspec.yaml）
- 包名：`com.feigong.yuncan`
- 后端：`feigong-yuncan-server@0.1.0`
