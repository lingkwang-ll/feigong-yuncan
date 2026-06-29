# 非攻云餐 — 备份与恢复说明

## 备份命令

在 `server` 目录下执行：

```bash
# 备份 SQLite 数据库（在线安全备份）
npm run backup:db

# 备份 uploads 图片目录（复制到 backups/uploads-时间戳/）
npm run backup:uploads
```

备份输出目录：`server/backups/`

| 类型 | 文件名示例 |
|------|------------|
| 数据库 | `feigong-yuncan-20260612-153045.db` |
| 上传文件 | `uploads-20260612-153045/` |

## 建议备份时机

- 正式上线前
- 后台修改系统配置前
- 大批量导入员工 / 审核商家前
- 试运行结束转商用前

## 恢复数据库

1. **停止后端服务**（避免写入冲突）
2. 找到要恢复的 `.db` 文件，例如 `server/backups/feigong-yuncan-xxx.db`
3. 覆盖当前数据库文件（默认路径 `server/data/feigong-yuncan.db`）：

```powershell
cd server
Copy-Item -Force ".\backups\feigong-yuncan-YYYYMMDD-HHmmss.db" ".\data\feigong-yuncan.db"
```

4. 重新启动：`npm run dev` 或 `npm start`

> 恢复前请先对当前库做一次 `npm run backup:db`，以便回滚。

## 恢复 uploads

1. **停止后端服务**（可选，建议停止）
2. 将备份目录复制回 `server/uploads/`：

```powershell
cd server
Remove-Item -Recurse -Force .\uploads\*
Copy-Item -Recurse -Force ".\backups\uploads-YYYYMMDD-HHmmss\*" ".\uploads\"
```

3. 确认子目录存在：`payments` / `dishes` / `qrcodes` / `licenses` / `stores` / `merchants`
4. 重启服务

## 环境变量

| 变量 | 说明 | 默认 |
|------|------|------|
| `DATABASE_PATH` | 数据库路径 | `./data/feigong-yuncan.db` |
| `UPLOAD_DIR` | 上传根目录 | `./uploads` |

## 上线前检查

```bash
cd server
npm run check:release
# 或
npm run check:go-live
```

检查项包括：health、登录、商家入驻、下单、汇总、标签、导出、uploads 可写、运行时配置可读。
