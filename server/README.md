# 非攻云餐 — 后端服务 (server)

Express + TypeScript + SQLite 的最小可用后端，
负责账号、商家、菜品、订单、上传五类资源。

## 启动

### 开发模式

```powershell
cd server
copy .env.example .env       # 第一次需要
npm install
npm run seed                 # 写入演示数据（会清空既有表）
npm run dev                  # http://localhost:3000/api
```

健康检查：

```
GET http://localhost:3000/api/health
→ { "data": { "ok": true, "ts": "..." } }
```

启动日志会打印当前生效配置，便于排查环境：

```
[feigong-yuncan-server] started
  - bind         : 0.0.0.0:3000
  - api base     : http://localhost:3000/api
  - upload dir   : ./uploads
  - database     : ./data/feigong-yuncan.db
  - cors origin  : *
```

### 生产模式

```powershell
cd server
npm install
npm run build                # tsc → dist/
npm start                    # node dist/index.js
```

`npm start` 同样会读取 `.env`。

## 环境变量

- 本机开发样例：[`.env.example`](./.env.example)
- 服务器生产样例：[`.env.production.example`](./.env.production.example)
- 文档说明：根目录 [`README.md`](../README.md#-后端环境变量serverenv)

## 部署到服务器（IP 直连试运行）

完整手册见 [`deploy/DEPLOY.md`](./deploy/DEPLOY.md)。

简要 4 步：

```bash
# 1. 服务器目录 + pm2
sudo bash deploy/install_server.sh

# 2. 上传代码到 /opt/feigong-yuncan/server/，并填好 .env
cp .env.production.example .env && vim .env

# 3. 构建 + 启动
npm install && npm run build && npm run reset:db:seed
pm2 start ecosystem.config.js && pm2 save

# 4. Nginx
sudo cp deploy/nginx-feigong-yuncan.conf /etc/nginx/conf.d/feigong-yuncan.conf
sudo nginx -t && sudo systemctl reload nginx

# 5. 体检
npm run check:ready
```

## 目录结构

```
server/
├── src/
│   ├── index.ts             启动入口
│   ├── app.ts               express app + 中间件 + 路由装配
│   ├── db/
│   │   ├── database.ts      better-sqlite3 单例 + schema 自动加载
│   │   └── schema.sql       表结构
│   ├── models/
│   │   ├── types.ts         领域类型
│   │   └── mappers.ts       row ↔ DTO 转换
│   ├── middleware/          loadUser / errorHandler
│   ├── controllers/         路由处理器
│   ├── services/            业务层（数据库读写）
│   ├── routes/              REST 路由
│   ├── seed/seed.ts         种子数据
│   └── scripts/             维护脚本 TS 源
│       ├── reset_db.ts
│       ├── clear_orders.ts
│       ├── backup_db.ts
│       ├── prepare_trial_data.ts
│       ├── seed_trial_users.ts
│       ├── export_today_summary.ts
│       └── trial_data_shared.ts
├── scripts/                 维护脚本（PowerShell 包装）
│   ├── reset_db.ps1
│   ├── clear_orders.ps1
│   ├── backup_db.ps1
│   ├── check_ready.ps1      上线前体检
│   ├── e2e_flutter.ps1      端到端跑通脚本
│   ├── smoke.ps1            登录 + 列表冒烟
│   └── smoke_upload.ps1     上传冒烟
├── data/                    SQLite 文件（运行时）
├── uploads/                 上传文件（运行时）
└── backups/                 数据库备份（backup_db 生成）
```

## REST 路由总览

| 方法 | 路径                                          | 说明                          |
| ---- | --------------------------------------------- | ----------------------------- |
| GET  | `/api/health`                                 | 健康检查                      |
| POST | `/api/auth/login`                             | 登录（phone + code + role）   |
| POST | `/api/auth/logout`                            | 登出                          |
| GET  | `/api/auth/me`                                | 当前登录用户                  |
| GET  | `/api/merchants`                              | 附近商家                      |
| GET  | `/api/merchants/:merchantId/dishes`           | 商家菜单                      |
| GET  | `/api/merchant/profile`                       | 当前商家档案                  |
| GET  | `/api/merchant/dishes`                        | 当前商家所有菜品              |
| POST | `/api/merchant/dishes`                        | 新增菜品                      |
| PUT  | `/api/merchant/dishes/:id`                    | 修改菜品                      |
| PUT  | `/api/merchant/dishes/:id/availability`       | 上下架                        |
| DELETE | `/api/merchant/dishes/:id`                  | 删除菜品                      |
| GET  | `/api/merchant/orders`                        | 商家订单列表                  |
| POST | `/api/orders`                                 | 员工创建订单                  |
| GET  | `/api/orders`                                 | 员工自己的订单                |
| PUT  | `/api/orders/:id/status`                      | 更新订单状态                  |
| POST | `/api/uploads/payment-screenshot`             | 上传付款截图                  |
| POST | `/api/uploads/dish-image`                     | 上传菜品图                    |
| POST | `/api/uploads/merchant-qr-code`               | 上传 / 更新商家收款码         |

返回格式：

- 成功：`{ "data": <payload> }`
- 失败：`{ "error": { "code": "BAD_REQUEST", "message": "..." } }`

## 维护脚本

| 命令                      | 等价 PowerShell                         | 作用                            |
| ------------------------- | --------------------------------------- | ------------------------------- |
| `npm run reset:db`        | `./scripts/reset_db.ps1`                | 删库重建空表（先停服务）        |
| `npm run reset:db:seed`   | `./scripts/reset_db.ps1 -Seed`          | 重建后写 seed                   |
| `npm run clear:orders`    | `./scripts/clear_orders.ps1`            | 只清空 orders / order_items     |
| `npm run backup:db`       | `./scripts/backup_db.ps1`               | 备份到 `backups/`               |
| `npm run prepare:trial`   | TS: `prepare_trial_data.ts`             | 清空测试订单，准备试运行数据    |
| `npm run seed:trial-users`| TS: `seed_trial_users.ts`               | 更新试运行账号白名单            |
| `npm run export:today`    | TS: `export_today_summary.ts`           | 导出餐段汇总 JSON/CSV           |
| `npm run check:ready`     | `./scripts/check_ready.ps1`             | 上线 / 试运行体检               |

### 试运行前准备

```powershell
cd server
npm run backup:db          # 1. 备份
npm run prepare:trial      # 2. 清测试单 + 试运行账号/绿健食堂菜品
npm run check:ready        # 3. 体检（会写一条探测订单）
npm run dev                # 4. 启动
```

`prepare:trial` 会清空 `orders` / `order_items`（及 `reviews` 表若存在），**保留**其他商家与用户，并将 **绿健食堂** 菜品重置为试运行菜单，**不写入演示订单**。

导出汇总：`npm run export:today -- --date=2026-06-12 --meal=lunch`

### `check_ready` 覆盖项

1. `/api/health`
2. `/api/merchants` 有数据
3. 员工登录
4. 商家登录
5. 创建测试订单
6. 商家订单列表能查到该订单
7. 订单状态联动：`accepted` → `completed`
8. `uploads/` 目录存在且可写

执行：

```powershell
cd server
npm run check:ready
# 或自定义 API：
$env:API_BASE = 'http://118.31.188.176:3000/api'
npm run check:ready
```

## 常见问题

**Q: SQLite 文件被占用，reset_db 删不掉？**
A: 先停掉 `npm run dev` / `npm start`，再跑脚本。WAL 文件 `*.db-wal`、`*.db-shm` 同理。

**Q: 远端上传后图片 URL 是 `/uploads/xxx.png`，前端访问 404？**
A: 在 `.env` 把 `PUBLIC_BASE_URL` 设成前端能访问到的后端地址，比如 `http://118.31.188.176:3000`。

**Q: 跨域报错？**
A: `CORS_ORIGIN` 设成前端实际域名（多个用逗号），或临时设 `*` 验证。

**Q: 想完全清干净重新演示？**
A: `npm run backup:db` → `npm run reset:db:seed`。
