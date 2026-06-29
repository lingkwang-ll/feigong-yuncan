# =============================================================
# backup_db.ps1
#
# 把 SQLite 数据库复制到 server/backups/，文件名带时间戳。
# 服务运行中也可安全备份（使用 better-sqlite3 的 .backup()）。
#
# 用法：
#   cd server
#   powershell -ExecutionPolicy Bypass -File .\scripts\backup_db.ps1
# =============================================================

$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..')
try {
    npx ts-node-dev --transpile-only src/scripts/backup_db.ts
} finally {
    Pop-Location
}
