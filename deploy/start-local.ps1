# 本地一键启动（Docker Compose）
# 用法：powershell -ExecutionPolicy Bypass -File deploy/start-local.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path (Join-Path $PSScriptRoot "release\admin-web\index.html"))) {
    Write-Host "未找到构建产物，先执行 build-release.ps1 ..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "build-release.ps1")
}

Push-Location $Root
docker compose -f deploy/docker-compose.yml up -d --build
Pop-Location

Start-Sleep -Seconds 8

try {
    $health = Invoke-RestMethod -Uri "http://localhost:8080/api/health" -TimeoutSec 10
    Write-Host ""
    Write-Host "========== 部署成功 ==========" -ForegroundColor Green
    Write-Host "员工/商家端 : http://localhost:8080/"
    Write-Host "管理后台   : http://localhost:8080/admin/"
    Write-Host "API 健康   : http://localhost:8080/api/health -> ok=$($health.data.ok)"
    Write-Host "API 直连   : http://localhost:3000/api/health"
} catch {
    Write-Host "启动中或健康检查失败，请执行: docker compose -f deploy/docker-compose.yml logs" -ForegroundColor Red
    throw
}
