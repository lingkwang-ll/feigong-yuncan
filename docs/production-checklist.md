# 非攻云餐 · 生产环境配置清单

> 本文档列出**生产服务器**上 `server/.env` 与 `admin-web/.env.production` 必须修改的字段，以及上线前必须完成的安全动作。
>
> **绝对禁止**直接照搬开发环境配置（`server/.env`、`admin-web/.env.production.example` 里的占位域名）到生产服务器上。

---

## 1. `server/.env` 必填项（生产）

复制：`cp server/.env.production.example server/.env` 后按本清单逐项改写。

| 配置 | 必填值 | 说明 |
|---|---|---|
| `NODE_ENV` | `production` | 启用生产模式，关闭部分调试日志 |
| `HOST` | `0.0.0.0` | 监听全部网卡（nginx 反代时可改 `127.0.0.1`） |
| `PORT` | `3000` 或运维约定值 | 与 nginx 上游一致 |
| `JWT_SECRET` | **长随机字符串（≥ 32 字符）** | 务必更换默认值，建议 `openssl rand -hex 32` 生成 |
| `JWT_EXPIRES_IN` | `7d` | 默认即可；如需更短按需调整 |
| `CORS_ORIGIN` | `https://yuncan.pheako.com,https://yuncan.pheako.com/admin` | 必须改成白名单；**禁止 `*`** |
| `DATABASE_PATH` | `/opt/feigong-yuncan/data/feigong-yuncan.db` | **必须放代码目录之外**，方便升级不丢数据 |
| `UPLOAD_DIR` | `/opt/feigong-yuncan/uploads` | 同上，独立于代码目录 |
| `PUBLIC_BASE_URL` | `https://yuncan.pheako.com` | 上传接口返回绝对路径时使用，**不要带 `/api` 后缀** |
| `PLATFORM_ADMIN_PHONE` | 真实平台管理员手机号 | `seed:commercial` 会用此手机号建初始管理员账号 |
| `SMS_PROVIDER` | `mock` | **暂不启用短信**；登录走密码模式，验证码相关接口走 mock |
| `ALIYUN_SMS_*` 四件套 | 留空 | 接入阿里云时再填，并把 `SMS_PROVIDER` 改成 `aliyun` |
| `AMAP_WEB_KEY` / `AMAP_SECURITY_CODE` | 看是否启用配送地图 | 不启用可留空 |

> 关于短信：当前后端实现只在 `SMS_PROVIDER=mock` 时正常工作。如果误填 `aliyun` 但不配置 KEY，发送验证码接口会抛 `500`。后续接入正式短信时，请同步在前端把"忘记密码/短信通知"打开。

---

## 2. `admin-web/.env.production` 必填项

```env
# 正式域名，必须以 /api 结尾，禁止使用 localhost
VITE_API_BASE_URL=https://yuncan.pheako.com/api
```

构建命令：

```bash
cd admin-web
npm install
npm run build
# 产物 dist/ 由 nginx 挂到 /admin/
```

---

## 3. Flutter / App 端打包

打包必须显式传入两个 `--dart-define`：

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=https://yuncan.pheako.com/api \
  --dart-define=ENV=prod
```

详见 [`docs/release.md`](./release.md)。

---

## 4. 默认密码红线

仓库里所有种子账号默认密码均为 `123456`，**上线前必须强制修改**：

| 角色 | 默认手机号 | 默认密码 | 上线前动作 |
|---|---|---|---|
| 平台管理员 | `13700000000` | `123456` | 改成强密码 |
| 商家试运行账号 | `13900000000` | `123456` | 改成强密码或停用 |
| 员工试运行账号 | `13800000000` | `123456` | 改成强密码或停用 |
| 首批正式平台管理员 | `PLATFORM_ADMIN_PHONE` | `123456` | 在 admin-web 上首登后立刻"修改密码" |
| 首批正式商家 | 各自手机号 | `123456` | 在 App 商家端首登后立刻"修改密码" |
| 首批正式员工 | 各自手机号 | `123456` | 同上 |

`server/src/utils/password.util.ts` 中 `DEFAULT_PASSWORD='123456'` 是后台批量录入时的初始密码，**不要直接上线作为长期使用密码**。

如果需要批量重置某个账号，可在 admin-web 上点击"重置密码"，会把目标账号密码重置回 `123456`，然后联系本人尽快改密。

---

## 5. 数据 / 上传目录权限

```bash
mkdir -p /opt/feigong-yuncan/data /opt/feigong-yuncan/uploads
chown -R feigong:feigong /opt/feigong-yuncan
chmod 750 /opt/feigong-yuncan/data
chmod 755 /opt/feigong-yuncan/uploads
```

建议：

- nginx 直接静态托管 `/opt/feigong-yuncan/uploads` 到 `https://yuncan.pheako.com/uploads/`（与后端 `app.use('/uploads', express.static(...))` 保持一致）；
- 用 `cron` 每日跑一次 `npm run backup:db` 与 `npm run backup:uploads`，备份目录建议在不同磁盘。

---

## 6. 上线自检（必须全部通过）

服务器部署完成后：

```bash
cd /opt/feigong-yuncan/server
API_BASE=https://yuncan.pheako.com/api npm run check:ready      # 必须 8/8
API_BASE=https://yuncan.pheako.com/api npm run check:security   # 必须 45/45
```

打包后再 grep 一遍生产包是否带 `localhost`：

```bash
rg -n localhost build/web admin-web/dist
```

如果有任何一项失败，不能放行上线。

---

## 7. 当前已知"暂不开通"项（合规公示）

App 内"用户支付页 / 订单详情页"已加固定文案：

> 当前暂未开通微信/支付宝线上支付，采用商家收款码转账 + 上传付款截图的方式，商家确认后订单生效。
> 如需退款，请联系商家或平台管理员处理。

且：

- 登录页 / 商家入驻页"用户协议、隐私政策、订餐及退款规则、商家服务协议、食品安全承诺书"5 份文档已内嵌静态正文；
- 短信验证码 / 短信通知**暂不开通**，登录使用账号密码模式；
- 在线支付**暂不开通**，订单走"收款码 + 付款截图人工核对"。

接入微信/支付宝、阿里云短信、退款工单、投诉售后等模块时，请：

1. 同步更新本清单与 [`docs/release-checklist.md`](./release-checklist.md)；
2. 同步更新 `legal_documents.dart` 中的协议正文与版本号 `legalVersion`；
3. 同步通知运营 / 法务复核 5 份协议。
