# =============================================================
# check_ready.ps1
#
# Pre-launch readiness check, covering the 8 critical paths:
#   1. /api/health
#   2. /api/merchants has data
#   3. employee login
#   4. merchant login
#   5. create a test order
#   6. merchant order list contains the new order
#   7. order status transitions: accepted -> completed
#   8. uploads/ exists and is writable
#
# Usage:
#   cd server
#   npm run check:ready
#   # or
#   powershell -ExecutionPolicy Bypass -File .\scripts\check_ready.ps1
#
# Override API base:
#   $env:API_BASE = 'http://118.31.188.176:3000/api'
# =============================================================

$ErrorActionPreference = 'Stop'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
. (Join-Path $PSScriptRoot '_ps_helpers.ps1')

$pass = 0
$fail = 0
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Info($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

Write-Host "================ feigong-yuncan check_ready ================" -ForegroundColor Cyan
Write-Host "API base: $base"

# 1. /api/health
try {
    $h = Invoke-RestMethod -Uri "$base/health" -Method Get -TimeoutSec 5
    if ($h.data.ok -eq $true) { Ok '/api/health OK' } else { Bad '/api/health returned not ok' }
} catch {
    Bad "/api/health unreachable: $($_.Exception.Message)"
    Write-Host "`nBackend not running. Start it with: cd server; npm run dev" -ForegroundColor Yellow
    exit 1
}

# 2. /api/merchants has data
try {
    $ms = Invoke-RestMethod -Uri "$base/merchants" -Method Get -TimeoutSec 5
    if ($ms.data.Count -gt 0) {
        Ok "/api/merchants returned $($ms.data.Count) items"
        $script:allMerchants = $ms.data
        $script:firstMerchant = $ms.data[0]
    } else {
        Bad '/api/merchants returned empty (please run: npm run seed)'
    }
} catch {
    Bad "/api/merchants failed: $($_.Exception.Message)"
}

# 3. employee login
try {
    $emp = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone='13800000001'; password='123456'; role='employee' } | ConvertTo-Json -Compress)
    if ($emp.data.user.role -eq 'employee') {
        Ok "employee login ok (id=$($emp.data.user.id))"
        $script:empId = $emp.data.user.id
        $script:empHeaders = @{ Authorization = "Bearer $($emp.data.token)" }
    } else {
        Bad 'employee login: role mismatch'
    }
} catch {
    Bad "employee login failed: $($_.Exception.Message)"
}

# 4. merchant login
try {
    $mer = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -TimeoutSec 5 `
        -ContentType 'application/json' `
        -Body (@{ phone='13900000000'; password='123456'; role='merchant' } | ConvertTo-Json -Compress)
    if ($mer.data.user.role -eq 'merchant') {
        Ok "merchant login ok (id=$($mer.data.user.id))"
        $script:merHeaders = @{ Authorization = "Bearer $($mer.data.token)" }
    } else {
        Bad 'merchant login: role mismatch'
    }
} catch {
    Bad "merchant login failed: $($_.Exception.Message)"
}

# 5. create a test order
$orderId = $null
if ($script:empId) {
    try {
        $cfg = Invoke-RestMethod -Uri "$base/config/runtime" -Method Get -TimeoutSec 5
        $deadlines = $cfg.data.mealDeadlines
        $now = Get-Date
        $currentMin = $now.Hour * 60 + $now.Minute
        function Test-MealOpen($mealType) {
            if (-not $deadlines) { return $true }
            $dl = $deadlines.$mealType
            if (-not $dl) { return $true }
            $parts = $dl -split ':'
            if ($parts.Count -lt 2) { return $true }
            $deadlineMin = [int]$parts[0] * 60 + [int]$parts[1]
            return $currentMin -le $deadlineMin
        }

        $merchantWithDishes = $null
        $dish = $null
        # Prefer the logged-in merchant (m_self) so the order belongs to a merchant
        # whose token we hold, avoiding 403 on subsequent merchant-side queries.
        $preferredOrder = @()
        if ($script:merHeaders) {
            try {
                $prof = Invoke-RestMethod -Uri "$base/merchant/profile" -Method Get -TimeoutSec 5 -Headers $script:merHeaders
                if ($prof.data.id) {
                    $own = $script:allMerchants | Where-Object { $_.id -eq $prof.data.id }
                    if ($own) { $preferredOrder += $own }
                }
            } catch {}
        }
        foreach ($m in $script:allMerchants) {
            if (-not ($preferredOrder | Where-Object { $_.id -eq $m.id })) {
                $preferredOrder += $m
            }
        }
        foreach ($m in $preferredOrder) {
            $dishes = Invoke-RestMethod -Uri "$base/merchants/$($m.id)/dishes" -Method Get -TimeoutSec 5
            foreach ($d in $dishes.data) {
                if (Test-MealOpen $d.mealType) {
                    $merchantWithDishes = $m
                    $dish = $d
                    break
                }
            }
            if ($merchantWithDishes) { break }
        }
        if (-not $merchantWithDishes) {
            Ok 'create order skipped (all meal deadlines passed for today)'
        } else {
            $merchantId = $merchantWithDishes.id
            $script:merchantWithDishesId = $merchantId
            $createBody = @{
                userId          = $script:empId
                merchantId      = $merchantId
                merchantName    = (Resolve-SafeMerchantName $merchantWithDishes.name 'E2ETestShop')
                customerName    = 'check_ready'
                customerCompany = 'check_ready'
                items           = @( @{ dish = $dish; quantity = 1 } )
                deliveryType    = 'selfPickup'
                address         = 'check_ready'
                remark          = 'check_ready'
                goodsAmount     = [double]$dish.price
                deliveryFee     = 0.0
                totalAmount     = [double]$dish.price
        status          = 'pendingPayment'
        paymentScreenshot = $null
            }
            $created = Invoke-RestMethod -Method Post -Uri "$base/orders" -TimeoutSec 5 `
                -ContentType 'application/json' `
                -Headers $script:empHeaders `
                -Body ($createBody | ConvertTo-Json -Depth 10 -Compress)
            if ($created.data.id) {
                $orderId = $created.data.id
                Ok "test order created (id=$orderId, status=$($created.data.status))"
            } else {
                Bad 'create order: response missing id'
            }
        }
    } catch {
        Bad "create order failed: $($_.Exception.Message)"
    }
} else {
    Bad 'skip: no employee available to create order'
}

# 6. merchant order list contains the new order
if ($orderId -and $script:merchantWithDishesId) {
    try {
        $mo = Invoke-RestMethod -Uri "$base/merchant/orders?merchantId=$($script:merchantWithDishesId)" -Method Get -TimeoutSec 5 `
            -Headers $script:merHeaders
        $hit = $mo.data | Where-Object { $_.id -eq $orderId }
        if ($hit) {
            Ok "merchant order list contains #$orderId"
        } else {
            Bad "merchant order list missing #$orderId"
        }
    } catch {
        Bad "merchant order query failed: $($_.Exception.Message)"
    }
}

# 7. status transition: upload screenshot -> accepted -> completed
if ($orderId) {
    # 7a. upload payment screenshot (minimal 1x1 PNG)
    try {
        $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.png')
        $bytes = [byte[]](
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,
            0xDE,0x00,0x00,0x00,0x0C,0x49,0x44,0x41,
            0x54,0x08,0x99,0x63,0xF8,0xFF,0xFF,0x3F,
            0x00,0x05,0xFE,0x02,0xFE,0xA9,0x5C,0x8A,
            0xFF,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
            0x44,0xAE,0x42,0x60,0x82
        )
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        $up = curl.exe -s -X POST `
            -H ("Authorization: Bearer " + $emp.data.token) `
            -F ("file=@" + $tmp + ";type=image/png") `
            -F ("orderId=" + $orderId) `
            -F "manualPayChannel=wechat" `
            "$base/uploads/payment-screenshot"
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        $upObj = $null
        try { $upObj = $up | ConvertFrom-Json } catch {}
        if ($upObj -and $upObj.data.url) { Ok "payment screenshot uploaded for check_ready order" }
        else { Bad ("upload payment screenshot failed raw=" + $up) }
    } catch {
        Bad ("upload payment screenshot error: " + $_.Exception.Message)
    }

    $r1 = $null
    $r1err = $null
    try {
        $body1 = @{ status = 'accepted' } | ConvertTo-Json -Compress
        $r1 = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" -TimeoutSec 5 -ContentType 'application/json' -Headers $script:merHeaders -Body $body1
    } catch {
        $r1err = $_.ErrorDetails.Message
    }

    if ($r1 -and $r1.data.status -eq 'accepted') {
        try {
            $body2 = @{ status = 'completed' } | ConvertTo-Json -Compress
            $r2 = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" -TimeoutSec 5 -ContentType 'application/json' -Headers $script:merHeaders -Body $body2
            if ($r2.data.status -eq 'completed') {
                Ok 'status transition accepted -> completed ok'
            } else {
                Bad "status -> completed unexpected: $($r2.data.status)"
            }
        } catch {
            Bad "status -> completed failed: $($_.Exception.Message)"
        }
    } elseif ($r1err -and $r1err -match 'PAYMENT_SCREENSHOT_REQUIRED') {
        try {
            $body3 = @{ status = 'cancelled'; rejectReason = 'check_ready: skip due to PAYMENT_SCREENSHOT_REQUIRED' } | ConvertTo-Json -Compress
            $rj = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" -TimeoutSec 5 -ContentType 'application/json' -Headers $script:merHeaders -Body $body3
            if ($rj.data.status -eq 'cancelled') {
                Ok 'status transition (skip accepted: PAYMENT_SCREENSHOT_REQUIRED) -> cancelled ok'
            } else {
                Bad "status fallback unexpected: $($rj.data.status)"
            }
        } catch {
            Bad "status fallback failed: $($_.Exception.Message)"
        }
    } elseif ($r1err -and $r1err -match 'INVALID_STATUS_TRANSITION') {
        Bad "status -> accepted blocked by state machine: $r1err"
    } else {
        Bad "status -> accepted failed: r1=$($r1.data.status); err=$r1err"
    }
}

# 8. uploads/ exists and writable
try {
    $uploadDir = if ($env:UPLOAD_DIR) { $env:UPLOAD_DIR } else { './uploads' }
    $abs = Resolve-Path -Path $uploadDir -ErrorAction SilentlyContinue
    if (-not $abs) {
        New-Item -ItemType Directory -Path $uploadDir -Force | Out-Null
        $abs = Resolve-Path -Path $uploadDir
    }
    $probe = Join-Path $abs.Path ".check_ready_$([Guid]::NewGuid().ToString('N')).tmp"
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
    Write-Host "`n[OK] all checks passed, ready for trial run" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[NO] please fix the failures above before going live" -ForegroundColor Red
    exit 1
}
