# admin-web 生产发布说明

## 技术栈

Vue 3 + Element Plus + Vite + Pinia + Axios

## 本地开发启动

```bash
# 终端 1：后端
cd server
npm run dev

# 终端 2：管理后台
cd admin-web
npm install
npm run dev
```

访问：**http://localhost:5173**

开发模式通过 Vite 代理 `/api` → `http://localhost:3000`。

## 生产 API 地址配置

复制环境样例：

```bash
cd admin-web
cp .env.production.example .env.production
```

编辑 `.env.production`：

```env
VITE_API_BASE_URL=https://your-domain.com/api
```

> 必须包含 `/api` 后缀。Nginx 需将 `/api/` 反代到 Node 后端。

## 生产构建

```bash
cd admin-web
npm install
npm run build
```

输出目录：**admin-web/dist/**

生产构建 `base` 为 `/admin/`，部署后访问：

```
https://your-domain.com/admin/
```

## 后台登录账号

| 角色 | 手机号 | 说明 |
|------|--------|------|
| 平台管理员 | `13700000000` | `npm run seed:commercial` 创建 |

登录方式：短信验证码（当前 `SMS_PROVIDER=mock`）。

- 开发环境：验证码打印在后端日志 `[SmsService][mock] phone=... code=...`
- 生产 mock 试运行：从数据库 `sms_codes` 表读取最新验证码

## Nginx 部署

将 `dist/` 内容同步到服务器：

```bash
rsync -av admin-web/dist/ user@server:/opt/feigong-yuncan/admin/
```

Nginx 配置参考：`server/deploy/nginx-production.conf`

```nginx
location /admin/ {
    alias /opt/feigong-yuncan/admin/;
    try_files $uri $uri/ /admin/index.html;
}
```

## 与 Flutter Web 共存

| 路径 | 用途 |
|------|------|
| `/app/` | Flutter 员工/商家 Web 端 |
| `/admin/` | 管理后台 |
| `/api/` | 后端 API |
| `/uploads/` | 上传静态文件 |

## 验收

```bash
cd server
npm run check:release
```

第 2–4 项覆盖 admin 登录、企业列表、商家审核列表。
