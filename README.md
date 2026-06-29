# 非攻云餐 (Feigong Yuncan)

一个面向企业内部的简易订餐工具。员工挑菜下单 → 扫码付款上传截图 →
商家审单接单 → 配送 / 自提 → 完成。

> 这是一个 "够用就好" 的内部小工具，不是外卖平台。所以业务、UI、状态机都尽量做减法。

> ⚠ **UI 修改前请先阅读 [`docs/ui-lock-rules.md`](./docs/ui-lock-rules.md)**。
> 该文件定义了 UI 锁定基线、禁止 / 允许清单、品牌色板与改动流程；
> 任何 UI 改动若违反其中条款，必须 revert。

## ✦ 技术栈

- 前端：Flutter 3.x（移动端 + Web）
  - `provider` 状态管理
  - `shared_preferences` 本地缓存
  - `http` 调用后端 API
- 后端：Node.js 18+ / TypeScript / Express 4 / SQLite (better-sqlite3) / Multer
- 部署：单机即可，所有数据落在 `server/data/feigong-yuncan.db`，上传落在 `server/uploads/`

## ✦ 目录结构

```
.
├── lib/                          Flutter 前端
│   ├── api/                      ApiClient + 各业务 API (auth/order/dish/merchant)
│   ├── repositories/             Repository 层（local / api 双源）
│   ├── state/                    provider 状态：AppState / CartState / OrderState ...
│   ├── features/                 页面：auth / employee / merchant
│   ├── widgets/                  通用组件（MobileAppFrame、AppLogo、DishCard ...）
│   └── theme/                    色板 / 字号 / 间距
├── design_reference/             10 张 UI 参考图（不要在代码里自由发挥）
├── server/                       后端服务
│   ├── src/                      Express + SQLite 业务源码
│   ├── scripts/                  PowerShell 维护脚本 (reset_db / backup_db / check_ready ...)
│   ├── data/                     SQLite 数据文件（运行时生成）
│   ├── uploads/                  上传文件（运行时生成）
│   ├── backups/                  数据库备份（backup_db 生成）
│   └── README.md                 后端独立说明
└── README.md                     本文档
```

## ✦ 快速启动（开发环境）

### 1. 启动后端

```powershell
cd server
copy .env.example .env       # 第一次需要
npm install
npm run seed                 # 写入演示数据（员工 / 商家 / 菜品 / 演示订单）
npm run dev                  # http://localhost:3000/api
```

默认演示账号（验证码任意 6 位通过）：

| 角色 | 手机号       |
| ---- | ------------ |
| 员工 | 13800000000  |
| 商家 | 13900000000  |

### 2. 启动前端（Flutter）

```powershell
flutter pub get
flutter run -d chrome        # Web 调试
# 或
flutter run                  # 真机 / 模拟器
```

前端默认请求 `http://localhost:3000/api`。

### 3. 数据源模式

`lib/api/api_config.dart`：

```dart
static const DataSourceMode dataSourceMode = DataSourceMode.api;
```

- `DataSourceMode.api`：调用后端
- `DataSourceMode.local`：纯前端 mock + shared_preferences（**不需要后端就能跑通 UI**）

两种模式都被保留，方便没装 Node 的同事也能看 UI。

## ✦ API 地址覆盖（dart-define）

代码默认值：

```dart
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);
```

部署到远程服务器时，**编译期** 用 `--dart-define` 覆盖：

```powershell
# 1. 调试连远端
flutter run -d chrome `
  --dart-define=API_BASE_URL=http://192.168.0.10:3000/api

# 2. 本机构建（连本地后端）
flutter build web `
  --dart-define=API_BASE_URL=http://localhost:3000/api

# 3. 上线构建（举例：阿里云）
flutter build web `
  --dart-define=API_BASE_URL=http://118.31.188.176:3000/api
```

构建产物在 `build/web/`，直接部署到 Nginx / 静态资源服务器即可。

## ✦ 后端环境变量（server/.env）

| 变量名           | 默认值                              | 说明                                                         |
| ---------------- | ----------------------------------- | ------------------------------------------------------------ |
| `PORT`           | `3000`                              | 监听端口                                                     |
| `HOST`           | `0.0.0.0`                           | 监听地址                                                     |
| `DATABASE_PATH`  | `./data/feigong-yuncan.db`          | SQLite 文件路径（兼容旧名 `DATABASE_FILE`）                  |
| `UPLOAD_DIR`     | `./uploads`                         | 上传根目录，子目录：`payments` / `dishes` / `qrcodes`        |
| `PUBLIC_BASE_URL`| `http://localhost:3000`             | 拼装可访问图片 URL；留空时返回相对路径 `/uploads/xxx.png`    |
| `CORS_ORIGIN`    | `*`                                 | 允许的来源；多个用逗号分隔                                   |

修改后重启 `npm run dev` / `npm start` 生效。

## ✦ 运维脚本

在 `server/` 目录下执行：

| 命令                  | 作用                                          |
| --------------------- | --------------------------------------------- |
| `npm run seed`        | 写入演示数据（**会清空既有数据**）            |
| `npm run reset:db`    | 删库 → 重建空表（**会丢数据，慎用**）         |
| `npm run reset:db:seed` | 删库 → 重建空表 → 写 seed                  |
| `npm run clear:orders`| 仅清空订单 / 订单项，保留账号 / 商家 / 菜品   |
| `npm run backup:db`   | 备份 SQLite 到 `server/backups/` 带时间戳     |
| `npm run prepare:trial` | 清空测试订单，保留商家菜品，写入试运行账号/菜单 |
| `npm run seed:trial-users` | 仅更新试运行员工/商家白名单              |
| `npm run export:today` | 导出指定日期餐段企业订餐汇总（JSON/CSV）    |
| `npm run check:ready` | 试运行体检（健康检查 / 登录 / 下单 / 接单 / 上传） |

### 试运行前准备

正式对外开放订餐前，建议按顺序执行：

```powershell
cd server

# 1. 备份当前数据库
npm run backup:db

# 2. 清空演示/测试订单，切换到试运行数据（不写测试单）
npm run prepare:trial

# 3. 系统体检（会创建一条探测订单，试运行开始前可再 prepare:trial 一次）
npm run check:ready

# 4. 启动后端
npm run dev
```

导出今日汇总（默认今天 + 当前餐段，输出到 `server/exports/`）：

```powershell
npm run export:today
npm run export:today -- --date=2026-06-12 --meal=lunch --format=both
```

> Windows 直接调 PowerShell 版本也行：`server/scripts/reset_db.ps1` 等。

## ✦ 健康检查

```
GET http://localhost:3000/api/health
→ { "data": { "ok": true, "ts": "2026-xx-xxT..." } }
```

## ✦ 常见问题

**1. Flutter 网页访问后端 404 / CORS 失败**

- 后端是否启动：`npm run dev`
- `apiBaseUrl` 是否匹配：默认 `http://localhost:3000/api`
- 远程访问：在 `server/.env` 把 `CORS_ORIGIN` 设成前端的实际域名 / IP，或用 `*`
- 移动浏览器 / 真机：必须用机器 IP，不能用 `localhost`

**2. Android 模拟器连不上 localhost**

Android 模拟器里的 `localhost` 指模拟器自己，要用宿主机别名 `10.0.2.2`：

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

**3. `npm run reset:db` 报 db 文件占用**

先停掉 `npm run dev` / `npm start` 再执行。
WAL 模式下 `-wal/-shm` 文件被占用同样会失败。

**4. 上传图片后页面看不到**

- 后端 `PUBLIC_BASE_URL` 是否能被前端访问到（局域网 IP 不要写成 localhost）
- `server/uploads/` 是否存在且可写：`npm run check:ready` 第 8 项会探测

**5. 想清理脏数据但保留账号 / 菜品**

用 `npm run clear:orders`，不要直接删 db。

## ✦ 服务器部署 / 内部试运行

把整个项目部署到一台 Linux 服务器，按 IP 直连访问。

详细手册：[`server/deploy/DEPLOY.md`](./server/deploy/DEPLOY.md)

核心约定：

- **目录规划**：所有持久化数据放在 `/opt/feigong-yuncan/` 下
  ```
  /opt/feigong-yuncan/
  ├── app/                Flutter Web 构建产物
  ├── server/             Node.js 后端代码
  ├── data/               SQLite
  ├── uploads/            上传文件
  ├── backups/            数据库备份
  └── logs/               pm2 / nginx 日志
  ```
- **后端**：`pm2 start ecosystem.config.js`（守护 + 自启）
- **前端**：`flutter build web --base-href "/yuncan/" --dart-define=API_BASE_URL=http://<服务器IP>/yuncan-api`
- **Nginx**：`server/deploy/nginx-feigong-yuncan.conf`（同时反代 API + 静态站点 + uploads）
- **体检**：`npm run check:ready`，8 项预期全 PASS

试运行账号（seed 内置，验证码任意 6 位）：

| 角色 | 手机号       | 选身份   |
| ---- | ------------ | -------- |
| 员工 | 13800000000  | 我是员工 |
| 商家 | 13900000000  | 我是商家 |

部署相关文件：

| 文件 | 用途 |
|---|---|
| `server/.env.production.example`     | 生产 .env 模板（含目录绝对路径） |
| `server/ecosystem.config.js`         | pm2 配置 |
| `server/deploy/nginx-feigong-yuncan.conf` | Nginx 反代 + 静态 + uploads |
| `server/deploy/install_server.sh`    | 服务器首次部署一键脚本 |
| `server/deploy/restart.sh`           | 拉新代码后的重建 + 重启 |
| `server/deploy/DEPLOY.md`            | 完整部署 / 试运行 / 维护手册 |

## ✦ 不要做

- 不要改业务流程 / 订单状态机
- 不要重新设计 UI（必须对齐 `design_reference/feigong_yuncan_ui/`）
- 不要把 `local` 模式删掉，没装后端的同事也要能看 UI

更详细的后端文档见 [`server/README.md`](./server/README.md)。
