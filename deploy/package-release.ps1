# 打包 ZIP 部署包
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ReleaseDir = Join-Path $PSScriptRoot "release"
$ZipPath = Join-Path $PSScriptRoot "feigong-yuncan-release.zip"

if (-not (Test-Path (Join-Path $ReleaseDir "admin-web\index.html"))) {
    & (Join-Path $PSScriptRoot "build-release.ps1")
}

if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

$Staging = Join-Path $env:TEMP "feigong-yuncan-staging"
if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging | Out-Null

Copy-Item -Recurse (Join-Path $PSScriptRoot "docker") (Join-Path $Staging "docker")
Copy-Item (Join-Path $PSScriptRoot "docker-compose.yml") $Staging
Copy-Item (Join-Path $PSScriptRoot "README.md") $Staging
Copy-Item (Join-Path $PSScriptRoot "build-release.ps1") $Staging
Copy-Item (Join-Path $PSScriptRoot "build-release.sh") $Staging
Copy-Item (Join-Path $PSScriptRoot "start-local.ps1") $Staging
Copy-Item -Recurse $ReleaseDir (Join-Path $Staging "release")

# server 构建产物 + 部署必需文件（Docker 构建上下文）
$ServerStage = Join-Path $Staging "server"
New-Item -ItemType Directory -Path $ServerStage | Out-Null
Copy-Item (Join-Path $Root "server\package.json") $ServerStage
Copy-Item (Join-Path $Root "server\package-lock.json") $ServerStage
Copy-Item -Recurse (Join-Path $Root "server\dist") (Join-Path $ServerStage "dist")

Compress-Archive -Path "$Staging\*" -DestinationPath $ZipPath -Force
Remove-Item $Staging -Recurse -Force

Write-Host "[OK] 部署包已生成: $ZipPath" -ForegroundColor Green
Write-Host "     大小: $([math]::Round((Get-Item $ZipPath).Length / 1MB, 2)) MB"
