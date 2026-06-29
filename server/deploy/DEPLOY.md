# 非攻云餐 服务器部署与试运行手册

适用场景：把当前项目部署到一台 Linux 服务器,做**内部试运行**(IP 直连,不绑域名,不上 HTTPS)。

部署完成后可达成:

- 员工 / 商家在公司局域网/外网通过 `http://<服务器IP>/yuncan/` 访问 Flutter Web
- 后端 API 跑在 `127.0.0.1:3000`,Nginx 反代到 `/yuncan-api/`
- 上传图片落到 `/opt/feigong-yuncan/uploads/`,SQLite 落到 `/opt/feigong-yuncan/data/`
- 后端用 pm2 守护,服务重启 / 机器重启自动拉起
- 任何代码重新部署都不会丢业务数据

---

## 1. 服务器准备

最小要求:

- Linux(CentOS 7+ / Ubuntu 20.04+),x86_64,1c2g 起步
- Node.js **>= 18**(`node -v` 看一下)
- Nginx
- 开放端口:`80`(对外),`3000` 仅本机即可

安装依赖(Ubuntu):

```bash
sudo apt update
sudo apt install -y curl git nginx build-essential
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pm2
```

安装依赖(CentOS / RHEL):

```bash
sudo yum install -y curl git nginx gcc-c++ make
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo yum install -y nodejs
sudo npm install -g pm2
```

---

## 2. 目录规划

**所有持久化数据都放在 `/opt/feigong-yuncan/` 下,代码重新部署不会动它**:

```
/opt/feigong-yuncan/
├── app/                 Flutter Web 构建产物（build/web 内容）
├── server/              Node.js 后端代码
├── data/                SQLite 数据库 ← 不要放在 server/ 内
├── uploads/             上传文件     ← 不要放在 server/ 内
├── backups/             数据库备份
└── logs/                pm2 / nginx 日志
```

一键创建:

```bash
sudo bash /path/to/install_server.sh
# 或手工：
sudo mkdir -p /opt/feigong-yuncan/{app,server,data,uploads,backups,logs}
sudo chown -R $USER:$USER /opt/feigong-yuncan
```

> 关键:数据库走绝对路径 `/opt/feigong-yuncan/data/feigong-yuncan.db`,
> uploads 走绝对路径 `/opt/feigong-yuncan/uploads`,
> 这样后续 `git pull` / 重新部署 server 代码都不会覆盖业务数据。

---

## 3. 上传后端代码

本地仓库 → 服务器(任选其一):

```bash
# 方案 A: rsync（推荐）
rsync -av --exclude node_modules --exclude dist --exclude data --exclude uploads \
  ./server/  <user>@<服务器IP>:/opt/feigong-yuncan/server/

# 方案 B: git clone
ssh <user>@<服务器IP>
cd /opt/feigong-yuncan
git clone <repo-url> tmp && mv tmp/server/. server/ && rm -rf tmp
```

---

## 4. 后端 .env

```bash
cd /opt/feigong-yuncan/server
cp .env.production.example .env
vim .env
```

把里面的 `<服务器IP>` 改成实际地址,推荐内容:

```ini
HOST=0.0.0.0
PORT=3000
DATABASE_PATH=/opt/feigong-yuncan/data/feigong-yuncan.db
UPLOAD_DIR=/opt/feigong-yuncan/uploads
PUBLIC_BASE_URL=http://<服务器IP>
CORS_ORIGIN=*
```

> `PUBLIC_BASE_URL` 不要写 `:3000`,因为最终走 Nginx 80。
> 如果你**不打算**用 Nginx 反代,直接暴露 3000,那就写 `http://<服务器IP>:3000`。

---

## 5. 后端构建 + 启动

### 5.1 构建

```bash
cd /opt/feigong-yuncan/server
npm install
npm run build
```

### 5.2 首次初始化数据库

```bash
# 写入演示账号 / 商家 / 菜品 / 演示订单
npm run reset:db:seed
```

后续如果只是想清掉所有订单保留账号 / 菜品:

```bash
npm run clear:orders
```

### 5.3 启动(pm2)

```bash
pm2 start ecosystem.config.js
pm2 save
pm2 startup           # 跟随系统自启，按提示再执行它打印出来的 sudo env ... 命令
pm2 status
pm2 logs feigong-yuncan-server --lines 50
```

日志在 `/opt/feigong-yuncan/logs/server.out.log` / `server.err.log`。

### 5.4 健康检查

```bash
curl http://127.0.0.1:3000/api/health
# → {"data":{"ok":true,"ts":"..."}}
```

如果未装 pm2,也可以临时:

```bash
nohup npm start > /opt/feigong-yuncan/logs/server.out.log 2>&1 &
```

---

## 6. 前端构建 + 上传

### 6.1 本地构建(走 Nginx 反代,推荐)

```bash
flutter build web \
  --base-href "/yuncan/" \
  --dart-define=API_BASE_URL=http://<服务器IP>/yuncan-api
```

### 6.2 本地构建(直连 3000,简化版)

如果暂时不上 Nginx 反代:

```bash
flutter build web \
  --dart-define=API_BASE_URL=http://<服务器IP>:3000/api
```

> 同时要开放服务器安全组 3000 端口。

### 6.3 上传

```bash
rsync -av build/web/  <user>@<服务器IP>:/opt/feigong-yuncan/app/
```

---

## 7. Nginx 配置

```bash
sudo cp /opt/feigong-yuncan/server/deploy/nginx-feigong-yuncan.conf \
        /etc/nginx/conf.d/feigong-yuncan.conf
sudo nginx -t
sudo systemctl reload nginx
```

访问入口:

| 资源        | URL                                            |
| ----------- | ---------------------------------------------- |
| Flutter Web | `http://<服务器IP>/yuncan/`                    |
| 后端 API    | `http://<服务器IP>/yuncan-api/`(浏览器侧)    |
| 上传文件    | `http://<服务器IP>/uploads/...`                |
| 健康检查    | `http://<服务器IP>/health`                     |

---

## 8. 防火墙 / 安全组

| 端口 | 说明                            | 是否对外 |
| ---- | ------------------------------- | -------- |
| 22   | SSH                             | 看需要   |
| 80   | Nginx 对外                      | **是**   |
| 3000 | Node.js,**仅 127.0.0.1**       | 否(若走反代)<br>是(若直连)|

云厂商安全组(阿里云 / 腾讯云 / AWS)别忘了同步放行 80。如果走方案 5.2 直连 3000,要放行 3000。

仅内网试运行:把上面的"是"改成"内网放行",其它别开。

---

## 9. 上线前 / 部署后体检

```bash
cd /opt/feigong-yuncan/server
npm run check:ready
```

8 项预期全 PASS:

```
[PASS] /api/health OK
[PASS] /api/merchants returned 6 items
[PASS] employee login ok (id=u_emp_1)
[PASS] merchant login ok (id=u_mer_1)
[PASS] test order created ...
[PASS] merchant order list contains #...
[PASS] status transition accepted -> completed ok
[PASS] uploads dir writable: /opt/feigong-yuncan/uploads
```

如果要测远端而不是本机:

```bash
API_BASE=http://<服务器IP>/yuncan-api npm run check:ready
# 或直连：
API_BASE=http://<服务器IP>:3000/api    npm run check:ready
```

体检完后清掉脏单据:

```bash
npm run clear:orders
npm run seed         # 顺手补回演示订单
```

---

## 10. 试运行账号

固定演示账号(seed 写入,**任意 6 位验证码均通过**):

| 角色 | 手机号       | 验证码 | 选身份   |
| ---- | ------------ | ------ | -------- |
| 员工 | 13800000000  | 任意   | 我是员工 |
| 商家 | 13900000000  | 任意   | 我是商家 |

走通流程建议:

1. 员工登录 → 选商家 → 加菜 → 去结算 → 确认订单 → 扫码付款 → 上传截图 → 提交订单
2. 商家登录 → 首页看新订单 → 接单 → (配送中) → 完成
3. 员工"我的订单"刷新 → 看到状态变成"已完成"
4. 商家"菜品管理"测试新增 / 编辑 / 上下架
5. 商家"我的"测试更换收款码

---

## 11. 数据维护

| 场景                    | 命令                       |
| ----------------------- | -------------------------- |
| 试运行前先备份          | `npm run backup:db`        |
| 只清订单,留账号 / 菜品 | `npm run clear:orders`     |
| 完全重置 + 写 demo 数据 | `npm run reset:db:seed`    |
| 备份恢复                | 见下                       |

恢复某次备份:

```bash
pm2 stop feigong-yuncan-server
cp /opt/feigong-yuncan/backups/feigong-yuncan-YYYYMMDD-HHmmss.db \
   /opt/feigong-yuncan/data/feigong-yuncan.db
pm2 start feigong-yuncan-server
```

---

## 12. 日常更新流程

```bash
# 1. 本地推代码到服务器
rsync -av --exclude node_modules --exclude dist \
  ./server/  <user>@<服务器IP>:/opt/feigong-yuncan/server/

# 2. 服务器侧重启
ssh <user>@<服务器IP>
cd /opt/feigong-yuncan/server
bash deploy/restart.sh        # 自动 npm install + npm run build + pm2 restart

# 3. 前端更新
flutter build web \
  --base-href "/yuncan/" \
  --dart-define=API_BASE_URL=http://<服务器IP>/yuncan-api
rsync -av build/web/ <user>@<服务器IP>:/opt/feigong-yuncan/app/
# 浏览器强刷 (Ctrl+F5)
```

---

## 13. 常见问题

**Q1. 浏览器打开 `/yuncan/` 是白屏**
A: F12 看 Console。多半是 `base-href` 没设。重新 `flutter build web --base-href "/yuncan/"`。

**Q2. 前端能开但所有 API 都 CORS 错**
A:
- 走 Nginx 反代时不会有跨域,先确认 `API_BASE_URL=http://<服务器IP>/yuncan-api`
- 走 3000 直连时把 `CORS_ORIGIN` 改成前端实际域名 / IP,或临时设 `*`

**Q3. 上传图片成功但页面 404**
A: `PUBLIC_BASE_URL` 没改对。前端浏览器要能通过这个地址访问到 `/uploads/...`。

**Q4. pm2 重启后端会"丢"环境变量**
A: `.env` 修改后用 `pm2 restart feigong-yuncan-server --update-env` 才会重读。

**Q5. `npm run reset:db` 报 db 文件被占用**
A: 先 `pm2 stop feigong-yuncan-server`,再 reset,再 `pm2 start`。

**Q6. SQLite 性能够吗?**
A: 内部试运行(几十人,日单量百级)完全够。后续如果要扩,把 `DATABASE_PATH` 换成 MySQL 接入层。

---

## 14. 同时部署多份(开发 / 测试 / 演示)

按目录隔离即可:

```
/opt/feigong-yuncan-dev/
/opt/feigong-yuncan-staging/
/opt/feigong-yuncan/                # 试运行
```

每份各自有 `.env`(改 PORT) / pm2 进程名(改 `ecosystem.config.js` 的 `name`) /
Nginx server 块(改 `location` 前缀)。

---

完成上述步骤,**项目就具备了"交给运维 / 同事即可上线"的完整能力**。
