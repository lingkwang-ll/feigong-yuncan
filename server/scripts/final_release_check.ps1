# =============================================================
# final_release_check.ps1 — 正式发布验收（10 项）
#
# 用法：
#   cd server
#   npm run check:release
#
# 环境变量：
#   API_BASE=http://localhost:3000/api
#   DATABASE_PATH=./data/feigong-yuncan.db
#   ADMIN_PHONE=13700000000
# =============================================================

$ErrorActionPreference = 'Stop'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
$dbPath = if ($env:DATABASE_PATH) { $env:DATABASE_PATH } else { './data/feigong-yuncan.db' }
$adminPhone = if ($env:ADMIN_PHONE) { $env:ADMIN_PHONE } else { '13700000000' }

$pass = 0
$fail = 0
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Info($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

Write-Host "================ feigong-yuncan final_release_check ================" -ForegroundColor Cyan
Write-Host "API base: $base"

function Get-LatestSmsCode($phone) {
    $absDb = Resolve-Path -Path $dbPath -ErrorAction SilentlyContinue
    if (-not $absDb) { return $null }
    $nodeScript = @"
const Database=require('better-sqlite3');
const db=new Database('$($absDb.Path.Replace('\','/'))');
const row=db.prepare('SELECT code FROM sms_codes WHERE phone=? ORDER BY created_at DESC LIMIT 1').get('$phone');
console.log(row?row.code:'');
"@
    $out = node -e $nodeScript 2>$null
    return ($out | Out-String).Trim()
}

# 1. /api/health
try {
    $h = Invoke-RestMethod -Uri "$base/health" -Method Get -TimeoutSec 5
    if ($h.data.ok -eq $true) { Ok '/api/health OK' } else { Bad '/api/health returned not ok' }
} catch {
    Bad "/api/health unreachable: $($_.Exception.Message)"
    Write-Host "`n请先启动后端: cd server; npm run dev" -ForegroundColor Yellow
    exit 1
}

# 2. admin 登录
$adminToken = $null
try {
    Invoke-RestMethod -Method Post -Uri "$base/auth/sms/send" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone=$adminPhone; scene='login' } | ConvertTo-Json -Compress) | Out-Null
    Start-Sleep -Milliseconds 300
    $code = Get-LatestSmsCode $adminPhone
    if (-not $code) { $code = '123456' }
    $login = Invoke-RestMethod -Method Post -Uri "$base/admin/auth/login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone=$adminPhone; code=$code } | ConvertTo-Json -Compress)
    if ($login.data.token) {
        $adminToken = $login.data.token
        Ok "admin login ok (role=$($login.data.user.role))"
    } else {
        Bad 'admin login: missing token'
    }
} catch {
    Bad "admin login failed: $($_.Exception.Message)"
}

$adminHeaders = @{}
if ($adminToken) { $adminHeaders = @{ Authorization = "Bearer $adminToken" } }

# 3. 企业列表
if ($adminToken) {
    try {
        $companies = Invoke-RestMethod -Uri "$base/admin/companies" -Method Get -Headers $adminHeaders -TimeoutSec 5
        if ($companies.data.Count -ge 0) {
            Ok "companies list ok ($($companies.data.Count) items)"
        } else {
            Bad 'companies list empty'
        }
    } catch {
        Bad "companies list failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip companies: no admin token'
}

# 4. 商家审核列表
if ($adminToken) {
    try {
        $merchants = Invoke-RestMethod -Uri "$base/admin/merchant-onboarding" -Method Get -Headers $adminHeaders -TimeoutSec 5
        Ok "merchant onboarding list ok ($($merchants.data.Count) items)"
    } catch {
        Bad "merchant onboarding list failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip merchant onboarding: no admin token'
}

# 5. 员工登录
$empId = $null
try {
    $emp = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone='13800000000'; code='123456'; role='employee' } | ConvertTo-Json -Compress)
    if ($emp.data.role -eq 'employee') {
        Ok "employee login ok (id=$($emp.data.id))"
        $empId = $emp.data.id
    } else {
        Bad 'employee login: role mismatch'
    }
} catch {
    Bad "employee login failed: $($_.Exception.Message)"
}

# 6. 商家登录
$merchantId = $null
try {
    $mer = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone='13900000000'; code='123456'; role='merchant' } | ConvertTo-Json -Compress)
    if ($mer.data.role -eq 'merchant') {
        Ok "merchant login ok (id=$($mer.data.id))"
    } else {
        Bad 'merchant login: role mismatch'
    }
    $profile = Invoke-RestMethod -Uri "$base/merchant/profile?userId=$($mer.data.id)" -Method Get -TimeoutSec 5
    $merchantId = $profile.data.id
} catch {
    Bad "merchant login failed: $($_.Exception.Message)"
}

# 7. 下单 API
$orderId = $null
if ($empId -and $merchantId) {
    try {
        $dishes = Invoke-RestMethod -Uri "$base/merchants/$merchantId/dishes" -Method Get -TimeoutSec 5
        if ($dishes.data.Count -le 0) {
            Bad "merchant $merchantId has no dishes"
        } else {
            $dish = $dishes.data[0]
            $body = @{
                userId=$empId; merchantId=$merchantId; merchantName='release-check'
                customerName='release'; customerCompany='release'
                items=@(@{ dish=$dish; quantity=1 })
                deliveryType='selfPickup'; address='release'; phone='13800000000'
                remark='release-check'; goodsAmount=[double]$dish.price
                deliveryFee=0.0; totalAmount=[double]$dish.price
                status='pendingMerchantConfirm'; paymentScreenshot=$null
            }
            $created = Invoke-RestMethod -Method Post -Uri "$base/orders" -TimeoutSec 5 `
                -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 10 -Compress)
            if ($created.data.id) {
                $orderId = $created.data.id
                Ok "create order ok (id=$orderId)"
            } else {
                Bad 'create order: missing id'
            }
        }
    } catch {
        Bad "create order failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip create order: missing employee or merchant'
}

# 8. 商家汇总 API
if ($merchantId) {
    try {
        $mo = Invoke-RestMethod -Uri "$base/merchant/orders?merchantId=$merchantId" -Method Get -TimeoutSec 5
        Ok "merchant orders summary ok ($($mo.data.Count) items)"
    } catch {
        Bad "merchant orders failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip merchant orders: no merchantId'
}

# 9. 标签数据
if ($adminToken) {
    try {
        $labels = Invoke-RestMethod -Uri "$base/admin/labels" -Method Get -Headers $adminHeaders -TimeoutSec 5
        Ok "labels data ok ($($labels.data.Count) orders)"
    } catch {
        Bad "labels data failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip labels: no admin token'
}

# 10. uploads 可写
try {
    $uploadDir = if ($env:UPLOAD_DIR) { $env:UPLOAD_DIR } else { './uploads' }
    $abs = Resolve-Path -Path $uploadDir -ErrorAction SilentlyContinue
    if (-not $abs) {
        New-Item -ItemType Directory -Path $uploadDir -Force | Out-Null
        $abs = Resolve-Path -Path $uploadDir
    }
    $probe = Join-Path $abs.Path ".release_check_$([Guid]::NewGuid().ToString('N')).tmp"
    Set-Content -Path $probe -Value 'ok' -Encoding ascii
    Remove-Item -Path $probe -Force
    Ok "uploads dir writable: $($abs.Path)"
} catch {
    Bad "uploads dir not writable: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "------------------ summary ------------------" -ForegroundColor Cyan
Write-Host "  PASS: $pass" -ForegroundColor Green
$failColor = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "  FAIL: $fail" -ForegroundColor $failColor

if ($fail -eq 0) {
    Write-Host "`n[OK] final release check passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[NO] please fix failures before release" -ForegroundColor Red
    exit 1
}
