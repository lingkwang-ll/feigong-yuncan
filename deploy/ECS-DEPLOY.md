# 非攻云餐 ECS 生产部署（独立路径 · 不影响考勤/报价）

## 一键部署

```bash
cd /opt/feigong-yuncan
chmod +x deploy/deploy-production-ecs.sh deploy/install-nginx-yuncan.sh
sudo ./deploy/deploy-production-ecs.sh
```

## 访问结构（公网 IP）

| 用途 | URL |
|------|-----|
| 员工/商家端 | http://118.31.188.176/yuncan/ |
| 管理后台 | http://118.31.188.176/yuncan-admin/ |
| API | http://118.31.188.176/yuncan-api/health |
| APK 下载 | http://118.31.188.176/downloads/pheako-yuncan.apk |

考勤、报价仍占用各自默认入口，**未修改 `/` 默认站点**。

## 域名（可选）

DNS `yuncan.pheako.com` → ECS 后，启用 `deploy/nginx-yuncan-domain.conf` 并配置 SSL：

| 用途 | URL |
|------|-----|
| 员工端 | https://yuncan.pheako.com/ |
| 管理后台 | https://yuncan.pheako.com/admin/ |
| API | https://yuncan.pheako.com/api/health |
| APK | https://yuncan.pheako.com/downloads/pheako-yuncan.apk |

## 架构

```
宿主机 nginx :80（default_server 不变，仅 include 云餐 snippet）
├── /yuncan/          → /opt/feigong-yuncan/web/yuncan/
├── /yuncan-admin/    → /opt/feigong-yuncan/web/yuncan-admin/
├── /yuncan-api/      → 127.0.0.1:3003/api/
├── /yuncan-uploads/  → 127.0.0.1:3003/uploads/
└── /downloads/       → /opt/feigong-yuncan/downloads/

systemd feigong-yuncan-api :3003
考勤 :3001 / 报价 :3002 不动
```

## 仅更新 nginx

```bash
sudo ./deploy/install-nginx-yuncan.sh
```

自动：备份 `/etc/nginx` → 注入 snippet → `nginx -t` → reload

## 验收

```bash
curl -I http://118.31.188.176/yuncan/
curl -I http://118.31.188.176/yuncan-admin/
curl http://118.31.188.176/yuncan-api/health
curl -I http://118.31.188.176/downloads/pheako-yuncan.apk
curl http://127.0.0.1:3003/api/health
systemctl status feigong-yuncan-api
```

## 文件清单

| 文件 | 说明 |
|------|------|
| `deploy/deploy-production-ecs.sh` | 全量生产部署 |
| `deploy/install-nginx-yuncan.sh` | nginx 安装/冲突检测/reload |
| `deploy/snippets/feigong-yuncan-locations.conf` | 云餐 location 块 |
| `deploy/nginx-yuncan-domain.conf` | 域名 server block |
| `deploy/systemd/feigong-yuncan-api.service` | API systemd |
| `deploy/env.server.production` | server/.env 模板 |
