# =============================================================
# clear_orders.ps1
#
# 仅清空 orders 和 order_items，保留用户/商家/菜品。
#
# 用法：
#   cd server
#   powershell -ExecutionPolicy Bypass -File .\scripts\clear_orders.ps1
# =============================================================

$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..')
try {
    npx ts-node-dev --transpile-only src/scripts/clear_orders.ts
} finally {
    Pop-Location
}
