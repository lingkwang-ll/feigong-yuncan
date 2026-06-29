# =============================================================
# final_go_live_check.ps1 — 上线前最终验收
#
# 用法：
#   cd server
#   npm run check:go-live
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

Write-Host "================ feigong-yuncan final_go_live_check ================" -ForegroundColor Cyan
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

# 1. health
try {
    $h = Invoke-RestMethod -Uri "$base/health" -Method Get -TimeoutSec 5
    if ($h.data.ok -eq $true) { Ok '/api/health OK' } else { Bad '/api/health returned not ok' }
} catch {
    Bad "/api/health unreachable: $($_.Exception.Message)"
    Write-Host "`n请先启动后端: cd server; npm run dev" -ForegroundColor Yellow
    exit 1
}

# 2. runtime config
try {
    $cfg = Invoke-RestMethod -Uri "$base/config/runtime" -Method Get -TimeoutSec 5
    if ($cfg.data.mealDeadlines -and $cfg.data.appSettings) {
        Ok "runtime config ok (requirePayment=$($cfg.data.appSettings.requirePaymentScreenshot))"
    } else {
        Bad 'runtime config missing fields'
    }
} catch {
    Bad "runtime config failed: $($_.Exception.Message)"
}

# 3. admin login
$adminToken = $null
try {
    $login = Invoke-RestMethod -Method Post -Uri "$base/admin/auth/password-login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone=$adminPhone; password='123456' } | ConvertTo-Json -Compress)
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

# 4. merchant onboarding list
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

# 5. employee login
$empId = $null
try {
    $emp = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone='13800000000'; password='123456'; role='employee' } | ConvertTo-Json -Compress)
    if ($emp.data.user.role -eq 'employee') {
        Ok "employee login ok (id=$($emp.data.user.id))"
        $empId = $emp.data.user.id
    } else {
        Bad 'employee login: role mismatch'
    }
} catch {
    Bad "employee login failed: $($_.Exception.Message)"
}

# 6. merchant login
$merchantId = $null
try {
    $mer = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone='13900000000'; password='123456'; role='merchant' } | ConvertTo-Json -Compress)
    if ($mer.data.user.role -eq 'merchant') {
        Ok "merchant login ok (id=$($mer.data.user.id))"
    } else {
        Bad 'merchant login: role mismatch'
    }
    $profile = Invoke-RestMethod -Uri "$base/merchant/profile?userId=$($mer.data.user.id)" -Method Get -TimeoutSec 5
    $merchantId = $profile.data.id
} catch {
    Bad "merchant login failed: $($_.Exception.Message)"
}

# 7. create order（选择未过截止时间的餐段）
$orderId = $null
if ($empId -and $merchantId) {
    try {
        $dishes = Invoke-RestMethod -Uri "$base/merchants/$merchantId/dishes" -Method Get -TimeoutSec 5
        if ($dishes.data.Count -le 0) {
            Bad "merchant $merchantId has no dishes"
        } else {
            $now = Get-Date
            $currentMin = $now.Hour * 60 + $now.Minute
            $deadlines = $cfg.data.mealDeadlines
            function Test-MealOpen($mealType) {
                $dl = $deadlines.$mealType
                if (-not $dl) { return $true }
                $parts = $dl -split ':'
                if ($parts.Count -lt 2) { return $true }
                $deadlineMin = [int]$parts[0] * 60 + [int]$parts[1]
                return $currentMin -le $deadlineMin
            }
            $dish = $null
            foreach ($d in $dishes.data) {
                if (Test-MealOpen $d.mealType) { $dish = $d; break }
            }
            if (-not $dish) {
                Ok "create order skipped (all meal deadlines passed for today)"
            } else {
                $body = @{
                    userId=$empId; merchantId=$merchantId; merchantName='go-live-check'
                    customerName='release'; customerCompany='release'
                    items=@(@{ dish=$dish; quantity=1 })
                    deliveryType='selfPickup'; address='release'; phone='13800000000'
                    remark='go-live-check'; goodsAmount=[double]$dish.price
                    deliveryFee=0.0; totalAmount=[double]$dish.price
                    status='pendingMerchantConfirm'; paymentScreenshot=$null
                }
                $created = Invoke-RestMethod -Method Post -Uri "$base/orders" -TimeoutSec 5 `
                    -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 10 -Compress)
                if ($created.data.id) {
                    $orderId = $created.data.id
                    Ok "create order ok (id=$orderId, mealType=$($dish.mealType))"
                } else {
                    Bad 'create order: missing id'
                }
            }
        }
    } catch {
        Bad "create order failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip create order: missing employee or merchant'
}

# 8. merchant orders summary
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

# 9. labels data
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

# 10. export meal summary
if ($adminToken -and $merchantId) {
    try {
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $exportUri = "$base/admin/meal-summary/export?date=$today&mealType=lunch&merchantId=$merchantId"
        $resp = Invoke-WebRequest -Uri $exportUri -Headers $adminHeaders -TimeoutSec 10 -UseBasicParsing
        if ($resp.StatusCode -eq 200 -and $resp.Content.Length -gt 0) {
            Ok "meal summary export ok ($($resp.Content.Length) bytes)"
        } else {
            Bad 'meal summary export empty'
        }
    } catch {
        Bad "meal summary export failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip export: missing admin token or merchantId'
}

# 11. uploads writable
try {
    $uploadDir = if ($env:UPLOAD_DIR) { $env:UPLOAD_DIR } else { './uploads' }
    $abs = Resolve-Path -Path $uploadDir -ErrorAction SilentlyContinue
    if (-not $abs) {
        New-Item -ItemType Directory -Path $uploadDir -Force | Out-Null
        $abs = Resolve-Path -Path $uploadDir
    }
    $probe = Join-Path $abs.Path ".go_live_check_$([Guid]::NewGuid().ToString('N')).tmp"
    Set-Content -Path $probe -Value 'ok' -Encoding ascii
    Remove-Item -Path $probe -Force
    Ok "uploads dir writable: $($abs.Path)"
} catch {
    Bad "uploads dir not writable: $($_.Exception.Message)"
}

# 12. admin_operation_logs table exists
try {
    $checkScript = Join-Path $PSScriptRoot 'check_admin_logs_table.js'
    Push-Location (Split-Path $checkScript -Parent | Split-Path -Parent)
    $has = (node $checkScript 2>$null | Out-String).Trim()
    Pop-Location
    if ($has -eq 'yes') { Ok 'admin_operation_logs table exists' } else { Bad 'admin_operation_logs table missing' }
} catch {
    Bad "admin_operation_logs check failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "------------------ summary ------------------" -ForegroundColor Cyan
Write-Host "  PASS: $pass" -ForegroundColor Green
$failColor = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "  FAIL: $fail" -ForegroundColor $failColor

if ($fail -eq 0) {
    Write-Host "`n[OK] final go-live check passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[NO] please fix failures before release" -ForegroundColor Red
    exit 1
}
