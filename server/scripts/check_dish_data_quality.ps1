# =============================================================
# check_dish_data_quality.ps1
#
# 菜品数据规范检查（只读数据库，不修改数据）
#
# Usage:
#   cd server
#   powershell -ExecutionPolicy Bypass -File .\scripts\check_dish_data_quality.ps1
# =============================================================

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "Running dish data quality check (read-only)..." -ForegroundColor Cyan
npx ts-node --transpile-only scripts/check_dish_data_quality.ts
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Host "check_dish_data_quality finished with exit code $code" -ForegroundColor Yellow
}
exit $code
