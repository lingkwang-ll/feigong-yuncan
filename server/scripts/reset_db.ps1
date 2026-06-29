# =============================================================
# reset_db.ps1
#
# 重置 SQLite 数据库（基于 src/scripts/reset_db.ts）
#   - 不加参数：只重建空表
#   - 加 -Seed：重建表 + 写入演示种子数据
#
# 用法：
#   cd server
#   powershell -ExecutionPolicy Bypass -File .\scripts\reset_db.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\reset_db.ps1 -Seed
#
# 注意：执行前先停掉 npm run dev / start，否则 db 文件被占用会删失败
# =============================================================
param([switch]$Seed)

$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..')
try {
    if ($Seed) {
        npx ts-node-dev --transpile-only src/scripts/reset_db.ts -- --seed
    } else {
        npx ts-node-dev --transpile-only src/scripts/reset_db.ts
    }
} finally {
    Pop-Location
}
