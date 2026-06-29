# 非攻云餐 · 管理后台 (admin-web)

Vue3 + Vite + Element Plus 企业管理后台。

## 启动方式

```bash
# 1. 启动后端（另开终端）
cd server
npm run dev

# 2. 初始化商用数据（首次）
cd server
npm run seed:commercial

# 3. 启动管理后台
cd admin-web
npm install
npm run dev
```

浏览器访问：**http://localhost:5173**

默认平台管理员手机号：`13700000000`（`SMS_PROVIDER=mock` 时验证码固定 `123456`）

## 生产构建

```bash
cd admin-web
npm run build
# 产物在 dist/，部署路径 base=/admin/
```

## 页面结构（8 页）

| 路由 | 页面 |
|------|------|
| `/login` | 登录 |
| `/dashboard` | 工作台 |
| `/companies` | 企业管理 |
| `/employees` | 员工管理 |
| `/merchants` | 商家管理 |
| `/dishes` | 菜品管理 |
| `/meal-summary` | 订餐汇总（日期+餐段+商家聚合） |
| `/labels` | 标签打印中心 |
| `/system-config` | 系统配置 |

## 环境变量

开发环境 `vite.config.js` 将 `/api` 代理到 `http://localhost:3000`。生产环境请在 Nginx 反向代理 `/api` 到后端。
