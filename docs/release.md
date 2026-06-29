# 非攻云餐 · 上线打包命令文档

> 本文档作为正式上线时的**打包/部署速查表**，与 [`docs/release-checklist.md`](./release-checklist.md)、[`docs/production-checklist.md`](./production-checklist.md) 配合使用。
>
> **绝对禁止**生产包带 `localhost` / `127.0.0.1` / 默认 `JWT_SECRET`。

---

## 0. 上线前必做检查

1. 已阅读 [`docs/production-checklist.md`](./production-checklist.md)，把 `.env` 中的 `JWT_SECRET`、`CORS_ORIGIN`、`DATABASE_PATH`、`UPLOAD_DIR`、`PUBLIC_BASE_URL`、`PLATFORM_ADMIN_PHONE` 全部改为正式值。
2. 已经在后台修改所有默认密码 `123456`（平台管理员、首批商家、首批员工）。
3. 在测试机上跑过 `npm run check:ready` 与 `npm run check:security` 全部通过。

---

## 1. 后端 server 生产启动

```bash
# 在生产服务器（假设代码部署在 /opt/feigong-yuncan/server）
cd /opt/feigong-yuncan/server

# 1) 第一次部署：拷贝模板 .env 并按本机情况编辑
cp .env.production.example .env
vim .env                    # 必填见 docs/production-checklist.md

# 2) 安装依赖（仅生产依赖）
npm install --omit=dev

# 3) 编译
npm run build               # 输出 dist/

# 4) 首次部署：种入平台管理员账号
npm run seed:commercial

# 5) 启动（推荐 pm2）
pm2 start dist/index.js --name feigong-yuncan-server --time
pm2 save
pm2 startup                 # 设置开机自启
```

启动后 health check：

```bash
curl https://yuncan.pheako.com/api/health
# 应返回 {"data":{"ok":true,"ts":"..."}}
```

如果只是想本机预览生产编译产物：

```bash
cd server
npm run build
NODE_ENV=production node dist/index.js
```

---

## 2. admin-web 后台构建

```bash
cd admin-web

# 1) 第一次部署：拷贝 .env.production 并把域名改成正式域名
cp .env.production.example .env.production   # 仓库已自带一份默认值
vim .env.production
# VITE_API_BASE_URL=https://yuncan.pheako.com/api  (必须以 /api 结尾，禁止 localhost)

# 2) 构建
npm install
npm run build                # 输出 dist/

# 3) 部署
#    - 将 dist/* 拷贝到 nginx 的 /opt/feigong-yuncan/admin-web/ 目录
#    - nginx 把 /admin/ 反向代理到 /opt/feigong-yuncan/admin-web/index.html
#    - nginx 把 /api/ 反向代理到 后端 3000 端口
```

**Vite 注意**：

- `vite.config.js` 在 `production` 模式下设置 `base = '/admin/'`，所以静态资源会自动加 `/admin/` 前缀。
- `dist/index.html` 必须挂在 nginx 的 `/admin/` 路径下，访问 `https://yuncan.pheako.com/admin/`。

---

## 3. Flutter Web 构建

```bash
cd <项目根目录>

# 必须显式传 API_BASE_URL 和 ENV=prod，否则会带着默认 localhost 上线
flutter build web --release \
  --dart-define=API_BASE_URL=https://yuncan.pheako.com/api \
  --dart-define=ENV=prod

# 产物：build/web/
# 部署：拷贝到 nginx 的 /opt/feigong-yuncan/app-web/ 下，挂到根域名或 /m/ 路径
```

> `lib/api/api_config.dart` 已支持：
> - `--dart-define=API_BASE_URL=...`  → 替换 `apiBaseUrl`
> - `--dart-define=ENV=prod`         → 关闭 API 日志、走生产模式

---

## 4. Flutter Android APK 构建

```bash
cd <项目根目录>

# 1) 调试包（自检用）
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://yuncan.pheako.com/api \
  --dart-define=ENV=prod

# 2) Release 包（正式发布）
flutter build apk --release \
  --dart-define=API_BASE_URL=https://yuncan.pheako.com/api \
  --dart-define=ENV=prod

# 3) 分架构包（应用商店）
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://yuncan.pheako.com/api \
  --dart-define=ENV=prod

# 产物：build/app/outputs/flutter-apk/
```

> Release 包前请先在 `android/key.properties` 配置签名密钥，参考 `docs/android-release.md`。

---

## 5. iOS（按需）

```bash
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://yuncan.pheako.com/api \
  --dart-define=ENV=prod
```

需提前在 Xcode 配置 Bundle ID 与签名证书。

---

## 6. API_BASE_URL 红线（严禁忽略）

打包前 grep 一遍最终产物里是否还残留 `localhost`：

```bash
# Flutter Web
rg -n localhost build/web/main.dart.js | head

# admin-web
rg -n localhost admin-web/dist | head
```

如果出现 `http://localhost:3000/api`：

- **Flutter**：忘了传 `--dart-define=API_BASE_URL=...`；
- **admin-web**：`.env.production` 没改或没有被加载（`mode=production` 才会读 `.env.production`，确认 `npm run build` 没加 `--mode development`）。

任何包带 `localhost` 都**禁止**上线。

---

## 7. 上线后自检脚本

```bash
# 后端
cd /opt/feigong-yuncan/server
API_BASE=https://yuncan.pheako.com/api npm run check:ready
API_BASE=https://yuncan.pheako.com/api npm run check:security
```

`check:security` 必须 45/45 通过。

---

## 8. 回滚

- 后端：`pm2 stop feigong-yuncan-server` → 回到上一版本 dist 目录 → `pm2 restart`。
- 数据库：从 `npm run backup:db` 的最近一份 `.sqlite.bak` 恢复（**绝不可直接 rm 现有库**）。
- admin-web / Flutter Web：把 nginx 静态目录指回上一版本即可。
