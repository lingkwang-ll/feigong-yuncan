# 非攻云餐 生产构建脚本（Windows）
# 用法：powershell -ExecutionPolicy Bypass -File deploy/build-release.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "========== 非攻云餐 生产构建 ==========" -ForegroundColor Cyan

# 1. 后端
Write-Host "[1/3] 构建 server..." -ForegroundColor Yellow
Push-Location (Join-Path $Root "server")
npm install
npm run build
if (-not (Test-Path "dist\db\schema.sql")) {
    throw "dist/db/schema.sql 缺失，请检查 copy-static.js"
}
Pop-Location

# 2. admin-web（同源 /api，走 Nginx 反代）
Write-Host "[2/3] 构建 admin-web..." -ForegroundColor Yellow
Push-Location (Join-Path $Root "admin-web")
$env:VITE_API_BASE_URL = "/api"
npm install
npm run build
Pop-Location

# 3. Flutter Web
Write-Host "[3/3] 构建 Flutter Web..." -ForegroundColor Yellow
Push-Location $Root
flutter pub get
flutter build web --release `
  --base-href "/" `
  --dart-define=ENV=prod `
  --dart-define=API_BASE_URL=/api
Pop-Location

# 4. 汇总到 deploy/release
$Release = Join-Path $PSScriptRoot "release"
$AdminDest = Join-Path $Release "admin-web"
$AppDest = Join-Path $Release "employee-app"

if (Test-Path $Release) { Remove-Item $Release -Recurse -Force }
New-Item -ItemType Directory -Path $AdminDest -Force | Out-Null
New-Item -ItemType Directory -Path $AppDest -Force | Out-Null

Copy-Item -Recurse -Force (Join-Path $Root "admin-web\dist\*") $AdminDest
Copy-Item -Recurse -Force (Join-Path $Root "build\web\*") $AppDest

Write-Host ""
Write-Host "[OK] 构建完成" -ForegroundColor Green
Write-Host "  admin-web   -> deploy/release/admin-web"
Write-Host "  employee    -> deploy/release/employee-app"
Write-Host "  server dist -> server/dist"
Write-Host ""
Write-Host "下一步：docker compose -f deploy/docker-compose.yml up -d --build" -ForegroundColor Cyan
