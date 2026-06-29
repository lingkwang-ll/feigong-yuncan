# =============================================================
# check_payment_review.ps1
#
# E2E acceptance for payment flow, company pay, reviews, and risk control.
#
# Covers:
#   A. Personal payment (pendingPayment -> screenshot -> pendingMerchantConfirm -> accepted -> completed)
#   B. Company pay (0 yuan, company_pay, skip screenshot, pendingMerchantConfirm -> accepted)
#   C. Reviews (completed-only, once per order, rating 1-5, images 0-9)
#   D. Risk control (grade downgrade, rating warning, auto close shop) + restore merchant state
#
# Usage:
#   cd server
#   powershell -ExecutionPolicy Bypass -File .\scripts\check_payment_review.ps1
#
# Override API base:
#   $env:API_BASE = 'http://118.31.188.176:3000/api'
# =============================================================

$ErrorActionPreference = 'Continue'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
. (Join-Path $PSScriptRoot '_ps_helpers.ps1')

# Section counters
$script:personalPass = 0; $script:personalFail = 0
$script:companyPass = 0;  $script:companyFail = 0
$script:reviewPass = 0;   $script:reviewFail = 0
$script:riskPass = 0;     $script:riskFail = 0

function OkPersonal($msg) { Write-Host "[PASS][personal] $msg" -ForegroundColor Green;  $script:personalPass++ }
function BadPersonal($msg) { Write-Host "[FAIL][personal] $msg" -ForegroundColor Red;    $script:personalFail++ }
function OkCompany($msg)  { Write-Host "[PASS][company]  $msg" -ForegroundColor Green;  $script:companyPass++ }
function BadCompany($msg)  { Write-Host "[FAIL][company]  $msg" -ForegroundColor Red;    $script:companyFail++ }
function OkReview($msg)   { Write-Host "[PASS][review]   $msg" -ForegroundColor Green;  $script:reviewPass++ }
function BadReview($msg)   { Write-Host "[FAIL][review]   $msg" -ForegroundColor Red;    $script:reviewFail++ }
function OkRisk($msg)     { Write-Host "[PASS][risk]     $msg" -ForegroundColor Green;  $script:riskPass++ }
function BadRisk($msg)     { Write-Host "[FAIL][risk]     $msg" -ForegroundColor Red;    $script:riskFail++ }
function Info($msg)       { Write-Host "         $msg" -ForegroundColor DarkGray }

function ReadErrBody($err) {
    try {
        $resp = $err.Exception.Response
        if (-not $resp) { return $null }
        $s = $resp.GetResponseStream()
        $r = New-Object System.IO.StreamReader($s, [System.Text.Encoding]::UTF8)
        return $r.ReadToEnd()
    } catch { return $null }
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [string]$ContentType = 'application/json'
    )
    try {
        $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; TimeoutSec = 12 }
        if ($Body) { $p.Body = $Body; $p.ContentType = $ContentType }
        $resp = Invoke-WebRequest @p -UseBasicParsing
        $json = $null
        try { $json = $resp.Content | ConvertFrom-Json } catch {}
        return @{
            Ok = $true
            Code = [int]$resp.StatusCode
            Data = $json.data
            Raw = $json
            Body = $resp.Content
        }
    } catch {
        $code = 0
        $body = ReadErrBody $_
        try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        $json = $null
        try { if ($body) { $json = $body | ConvertFrom-Json } } catch {}
        return @{
            Ok = $false
            Code = $code
            Data = $json.data
            Raw = $json
            Body = $body
            ErrorCode = $(if ($json -and $json.error) { $json.error.code } else { $null })
        }
    }
}

function Login($phone, $role) {
    $body = @{ phone = $phone; password = '123456'; role = $role } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body $body -TimeoutSec 8
}

function AdminLogin() {
    return Invoke-RestMethod -Method Post -Uri "$base/admin/auth/password-login" -ContentType 'application/json' -Body '{"phone":"13700000000","password":"123456"}' -TimeoutSec 8
}

function Test-MealOpen($mealType, $deadlines) {
    if (-not $deadlines) { return $true }
    $dl = $deadlines.$mealType
    if (-not $dl) { return $true }
    $parts = $dl -split ':'
    if ($parts.Count -lt 2) { return $true }
    $now = Get-Date
    $curMin = $now.Hour * 60 + $now.Minute
    $dMin = [int]$parts[0] * 60 + [int]$parts[1]
    return $curMin -le $dMin
}

function Pick-SelfPayMealType($deadlines) {
    foreach ($mt in @('lunch', 'dinner', 'breakfast')) {
        if (Test-MealOpen $mt $deadlines) { return $mt }
    }
    return $null
}

function Pick-CompanyPayMealType($deadlines) {
    foreach ($mt in @('lunch', 'dinner', 'breakfast')) {
        if (Test-MealOpen $mt $deadlines) { return $mt }
    }
    return $null
}

function Upload-PaymentScreenshot($token, $orderId, [string]$ManualChannel = 'wechat') {
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
    $raw = curl.exe -s -w "`nHTTP_CODE:%{http_code}" -X POST `
        -H ("Authorization: Bearer " + $token) `
        -F ("file=@" + $tmp + ";type=image/png") `
        -F ("orderId=" + $orderId) `
        -F ("manualPayChannel=" + $ManualChannel) `
        "$base/uploads/payment-screenshot"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $codeLine = ($raw -split "`n") | Where-Object { $_ -match '^HTTP_CODE:' } | Select-Object -Last 1
    $httpCode = 0
    if ($codeLine -match 'HTTP_CODE:(\d+)') { $httpCode = [int]$Matches[1] }
    $jsonPart = ($raw -split "`nHTTP_CODE:")[0]
    $obj = $null
    try { $obj = $jsonPart | ConvertFrom-Json } catch {}
    $errCode = $null
    if ($obj -and $obj.error) { $errCode = $obj.error.code }
    return @{ Code = $httpCode; Data = $obj.data; Body = $jsonPart; Raw = $obj; ErrorCode = $errCode }
}

$script:serverRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:savedEnableReview = $null
$script:savedAppSettings = $null

function Save-EnableReviewSetting {
    try {
        $admin = AdminLogin
        $headers = @{ Authorization = "Bearer $($admin.data.token)" }
        $cfg = Invoke-RestMethod -Uri "$base/admin/system-config" -Headers $headers -TimeoutSec 8
        $script:savedAppSettings = $cfg.data.appSettings
        $script:savedEnableReview = [bool]$cfg.data.appSettings.enableReview
        return $headers
    } catch {
        return $null
    }
}

function Enable-ReviewForTest($adminHeaders) {
    if (-not $adminHeaders) { return $false }
    try {
        Invoke-RestMethod -Method Put -Uri "$base/admin/system-config" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
            appSettings = @{ enableReview = $true }
        } | ConvertTo-Json -Compress) | Out-Null
        return $true
    } catch { return $false }
}

function Restore-EnableReviewSetting($adminHeaders) {
    if (-not $adminHeaders -or $null -eq $script:savedEnableReview) { return }
    try {
        Invoke-RestMethod -Method Put -Uri "$base/admin/system-config" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
            appSettings = @{ enableReview = $script:savedEnableReview }
        } | ConvertTo-Json -Compress) | Out-Null
    } catch {
        # best effort restore
    }
}

function New-CompletedSelfPayOrder {
    param([hashtable]$Headers)
    $c = Create-DishOrder -EmpHeaders $Headers -MerchantId $merchantId -MerchantName $merchantName -Dish $selfPayDish -MealType $selfPayMeal -PaymentType 'self_pay'
    if (-not $c.Ok) { return $null }
    $oid = $c.Data.id
    $up = Upload-PaymentScreenshot ($Headers.Authorization -replace '^Bearer\s+','') $oid
    if ($up.Code -ne 200) { return $null }
    Invoke-Api -Method Put -Uri "$base/orders/$oid/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress) | Out-Null
    Invoke-Api -Method Put -Uri "$base/orders/$oid/status" -Headers $merHeaders -Body (@{ status = 'completed' } | ConvertTo-Json -Compress) | Out-Null
    return $oid
}

function New-CompletedOrderForRisk {
    param([hashtable]$Headers, [string]$Suffix = 'risk')
    $coMeal = Pick-CompanyPayMealType $deadlines
    if (-not $coMeal) { $coMeal = 'lunch' }
    $coDish = $dishes.data | Where-Object { $_.mealType -eq $coMeal -and $_.price -gt 0 } | Select-Object -First 1
    if (-not $coDish) { $coDish = $selfPayDish }
    $c = Create-DishOrder -EmpHeaders $Headers -MerchantId $merchantId -MerchantName $merchantName -Dish $coDish -MealType $coMeal
    if (-not $c.Ok) { return $null }
    $oid = $c.Data.id
    Invoke-Api -Method Put -Uri "$base/orders/$oid/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress) | Out-Null
    Invoke-Api -Method Put -Uri "$base/orders/$oid/status" -Headers $merHeaders -Body (@{ status = 'completed' } | ConvertTo-Json -Compress) | Out-Null
    return $oid
}

function Restore-MerchantSnapshot($merchantId, $rating, $grade, $isOpen) {
    $dbPath = if ($env:DB_PATH) { $env:DB_PATH } else { './data/feigong-yuncan.db' }
    $absDb = Join-Path $script:serverRoot ($dbPath -replace '^\./','')
    if (-not (Test-Path $absDb)) {
        BadRisk "restore skipped: database not found at $absDb"
        return $false
    }
    $helper = Join-Path $script:serverRoot 'scripts/e2e_restore_merchant.js'
    if (-not (Test-Path $helper)) {
        BadRisk "restore helper missing: $helper"
        return $false
    }
    try {
        Push-Location $script:serverRoot
        $out = node $helper $absDb $rating $grade $(if ($isOpen) { '1' } else { '0' }) $merchantId 2>&1
        Pop-Location
        if ($LASTEXITCODE -eq 0) {
            OkRisk "merchant snapshot restored (rating=$rating grade=$grade isOpen=$isOpen)"
            return $true
        }
        BadRisk "merchant restore failed: $out"
        return $false
    } catch {
        Pop-Location
        BadRisk "merchant restore error: $($_.Exception.Message)"
        return $false
    }
}

function Test-ApiErrCode {
    param(
        $Result,
        [string[]]$Codes
    )
    if (-not $Result) { return $false }
    foreach ($c in $Codes) {
        if ($Result.Body -and $Result.Body -match [regex]::Escape($c)) { return $true }
        if ($Result.Raw -and $Result.Raw.error -and $Result.Raw.error.code -eq $c) { return $true }
        if ($Result.ErrorCode -and $Result.ErrorCode -eq $c) { return $true }
    }
    return $false
}

function Find-OrderInList($list, $orderId) {
    return $list | Where-Object { $_.id -eq $orderId } | Select-Object -First 1
}

function Create-DishOrder {
    param(
        [hashtable]$EmpHeaders,
        [string]$MerchantId,
        [string]$MerchantName,
        [object]$Dish,
        [string]$MealType = $null,
        [string]$PaymentType = $null
    )
    $body = @{
        merchantId = $MerchantId
        merchantName = $MerchantName
        deliveryType = 'selfPickup'
        address = 'e2e-check'
        remark = 'check_payment_review'
        goodsAmount = [double]$Dish.price
        deliveryFee = 0.0
        totalAmount = [double]$Dish.price
        items = @( @{ dish = $Dish; quantity = 1 } )
    }
    if ($MealType) { $body.mealType = $MealType }
    if ($PaymentType) { $body.paymentType = $PaymentType }
    $json = $body | ConvertTo-Json -Depth 10 -Compress
    return Invoke-Api -Method Post -Uri "$base/orders" -Headers $EmpHeaders -Body $json
}

Write-Host "=== feigong-yuncan check_payment_review ===" -ForegroundColor Cyan
Write-Host "API base: $base"

# --- health ---
try {
    $h = Invoke-RestMethod -Uri "$base/health" -Method Get -TimeoutSec 5
    if ($h.data.ok -ne $true) {
        Write-Host "[FAIL] /api/health not ok" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[FAIL] backend unreachable: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Start backend: cd server; npm run dev" -ForegroundColor Yellow
    exit 1
}

# --- shared setup ---
$cfg = Invoke-RestMethod -Uri "$base/config/runtime" -Method Get -TimeoutSec 8
$deadlines = $cfg.data.mealDeadlines
$selfPayMeal = Pick-SelfPayMealType $deadlines
$companyPayMeal = Pick-CompanyPayMealType $deadlines
if (-not $selfPayMeal -and -not $companyPayMeal) {
    Write-Host "[SKIP] all meal deadlines passed today; cannot run order e2e" -ForegroundColor Yellow
    exit 1
}
if ($selfPayMeal) { Info "personal-pay mealType=$selfPayMeal" }
if ($companyPayMeal) { Info "company-pay mealType=$companyPayMeal" }

try {
    $mer = Login '13900000000' 'merchant'
    $merHeaders = @{ Authorization = "Bearer $($mer.data.token)" }
    $prof = Invoke-RestMethod -Uri "$base/merchant/profile" -Headers $merHeaders -TimeoutSec 8
    $merchantId = $prof.data.id
    $merchantName = Resolve-SafeMerchantName $prof.data.name 'E2ETestShop'
    OkPersonal "merchant login (merchantId=$merchantId)"
    OkCompany  "merchant ready for company-pay accept"
} catch {
    BadPersonal "merchant login failed: $($_.Exception.Message)"
    BadCompany  "merchant login failed"
    exit 1
}

$dishes = Invoke-RestMethod -Uri "$base/merchants/$merchantId/dishes" -Method Get -TimeoutSec 8
$selfPayDish = $null
if ($selfPayMeal) {
    $selfPayDish = $dishes.data | Where-Object { $_.mealType -eq $selfPayMeal -and $_.price -gt 0 } | Select-Object -First 1
    if (-not $selfPayDish) {
        $selfPayDish = $dishes.data | Where-Object { $_.mealType -ne 'overtime' -and $_.price -gt 0 } | Select-Object -First 1
    }
}

# =============================================================
# A. Personal payment flow (employee 李四 / 销售部 -> self_pay)
# =============================================================
Write-Host "`n--- A. Personal payment ---" -ForegroundColor Cyan

$personalOrderId = $null
try {
    $empSelf = Login '13800000001' 'employee'
    $empSelfHeaders = @{ Authorization = "Bearer $($empSelf.data.token)" }
    OkPersonal "employee login (李四/销售部, id=$($empSelf.data.user.id))"
} catch {
    BadPersonal "employee login failed: $($_.Exception.Message)"
}

if ($empSelfHeaders -and $selfPayDish -and $selfPayMeal) {
    $created = Create-DishOrder -EmpHeaders $empSelfHeaders -MerchantId $merchantId -MerchantName $merchantName -Dish $selfPayDish -MealType $selfPayMeal -PaymentType 'self_pay'
    if ($created.Ok -and $created.Data.id) {
        $personalOrderId = $created.Data.id
        $st = $created.Data.status
        $pt = $created.Data.paymentType
        if ($st -eq 'pendingPayment') { OkPersonal "create order -> status=pendingPayment" }
        else { BadPersonal "create order expected pendingPayment got status=$st" }
        if ($pt -eq 'self_pay') { OkPersonal "paymentType=self_pay" }
        else { BadPersonal "expected paymentType=self_pay got $pt" }
        if ([double]$created.Data.totalAmount -gt 0) { OkPersonal "totalAmount > 0 ($($created.Data.totalAmount))" }
        else { BadPersonal "personal order totalAmount should be > 0" }
    } else {
        BadPersonal "create personal order failed code=$($created.Code) body=$($created.Body)"
    }
} elseif (-not $selfPayMeal) {
    BadPersonal "skip personal pay: lunch/dinner/breakfast deadlines all passed"
} else {
    BadPersonal "no non-overtime dish for personal pay test"
}

if ($personalOrderId) {
    $acc = Invoke-Api -Method Put -Uri "$base/orders/$personalOrderId/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress)
    if (-not $acc.Ok -and ($acc.Code -eq 400 -or (Test-ApiErrCode -Result $acc -Codes @('PAYMENT_SCREENSHOT_REQUIRED','PAYMENT_FLOW_INCOMPLETE','INVALID_STATUS_TRANSITION')))) {
        OkPersonal "merchant cannot accept before screenshot (blocked)"
    } elseif ($acc.Ok -and $acc.Data.status -eq 'accepted') {
        BadPersonal "merchant accepted without screenshot (should be blocked)"
    } else {
        BadPersonal "unexpected accept-before-screenshot response code=$($acc.Code) body=$($acc.Body)"
    }

    $up = Upload-PaymentScreenshot $empSelf.data.token $personalOrderId
    if ($up.Code -eq 200 -and $up.Data.url) {
        OkPersonal "payment screenshot uploaded"
    } else {
        BadPersonal "upload payment screenshot failed code=$($up.Code) body=$($up.Body)"
    }

    Start-Sleep -Milliseconds 300
    $mine = Invoke-RestMethod -Uri "$base/orders/my" -Headers $empSelfHeaders -TimeoutSec 8
    $po = Find-OrderInList $mine.data $personalOrderId
    if ($po) {
        if ($po.status -in @('paymentSubmitted', 'pendingMerchantConfirm')) {
            OkPersonal "after upload status=$($po.status) (paymentSubmitted or pendingMerchantConfirm)"
        } else {
            BadPersonal "after upload unexpected status=$($po.status)"
        }
        if ($po.paymentScreenshot) { OkPersonal "paymentScreenshot persisted on order" }
        else { BadPersonal "paymentScreenshot missing after upload" }
        if ($po.manualPayChannel -eq 'wechat') { OkPersonal "manualPayChannel=wechat persisted" }
        else { BadPersonal "manualPayChannel expected wechat got $($po.manualPayChannel)" }
    } else {
        BadPersonal "employee cannot find order after upload"
    }

    $acc2 = Invoke-Api -Method Put -Uri "$base/orders/$personalOrderId/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress)
    if ($acc2.Ok -and $acc2.Data.status -eq 'accepted') {
        OkPersonal "merchant accepted after screenshot -> accepted"
    } else {
        BadPersonal "merchant accept after screenshot failed code=$($acc2.Code) body=$($acc2.Body)"
    }

    $done = Invoke-Api -Method Put -Uri "$base/orders/$personalOrderId/status" -Headers $merHeaders -Body (@{ status = 'completed' } | ConvertTo-Json -Compress)
    if ($done.Ok -and $done.Data.status -eq 'completed') {
        OkPersonal "merchant completed -> completed"
    } else {
        BadPersonal "merchant complete failed code=$($done.Code) body=$($done.Body)"
    }
}

# =============================================================
# B. Company pay flow
# =============================================================
Write-Host "`n--- B. Company pay ---" -ForegroundColor Cyan

$companyOrderId = $null
$savedCompanyPayDepts = $null
try {
    $admin = AdminLogin
    $adminHeaders = @{ Authorization = "Bearer $($admin.data.token)" }
    $sysCfg = Invoke-RestMethod -Uri "$base/admin/system-config" -Headers $adminHeaders -TimeoutSec 8
    $savedCompanyPayDepts = $sysCfg.data.appSettings.companyPayDepartments
    if ($savedCompanyPayDepts -and $savedCompanyPayDepts.Count -gt 0) {
        OkCompany "companyPayDepartments configured: $($savedCompanyPayDepts -join ', ')"
    } else {
        BadCompany "companyPayDepartments missing in system config"
    }
} catch {
    BadCompany "admin/system-config read failed: $($_.Exception.Message)"
}

try {
    $empCo = Login '13800000000' 'employee'
    $empCoHeaders = @{ Authorization = "Bearer $($empCo.data.token)" }
    OkCompany "employee login (张三/行政部, id=$($empCo.data.user.id))"
} catch {
    BadCompany "employee login for company pay failed: $($_.Exception.Message)"
}

if ($empCoHeaders -and $companyPayMeal) {
    $coDish = $dishes.data | Where-Object { $_.mealType -eq $companyPayMeal -and $_.price -gt 0 } | Select-Object -First 1
    if (-not $coDish) { $coDish = $selfPayDish }
    $coCreated = Create-DishOrder -EmpHeaders $empCoHeaders -MerchantId $merchantId -MerchantName $merchantName -Dish $coDish -MealType $companyPayMeal -PaymentType 'company_pay'
    if ($coCreated.Ok -and $coCreated.Data.id) {
        $companyOrderId = $coCreated.Data.id
        $d = $coCreated.Data
        if ([math]::Abs([double]$d.totalAmount) -gt 0) { OkCompany "totalAmount preserved ($($d.totalAmount))" }
        else { BadCompany "company order totalAmount=$($d.totalAmount) expected > 0" }
        if ([math]::Abs([double]$d.companyPayAmount - [double]$d.totalAmount) -lt 0.001) { OkCompany "companyPayAmount=totalAmount" }
        else { BadCompany "companyPayAmount=$($d.companyPayAmount) total=$($d.totalAmount)" }
        if ([math]::Abs([double]$d.employeePayAmount) -lt 0.001) { OkCompany "employeePayAmount=0" }
        else { BadCompany "employeePayAmount=$($d.employeePayAmount) expected 0" }
        if ($d.paymentType -eq 'company_pay') { OkCompany "paymentType=company_pay" }
        else { BadCompany "expected paymentType=company_pay got $($d.paymentType)" }
        if ($d.status -eq 'pendingMerchantConfirm') { OkCompany "initial status=pendingMerchantConfirm" }
        else { BadCompany "expected pendingMerchantConfirm got $($d.status)" }
    } else {
        BadCompany "create company order failed code=$($coCreated.Code) body=$($coCreated.Body)"
    }
} else {
    BadCompany "skip company pay order: no employee login or no open meal window"
}

if ($companyOrderId) {
    $upCo = Upload-PaymentScreenshot $empCo.data.token $companyOrderId
    if ($upCo.Code -eq 400 -and (Test-ApiErrCode -Result $upCo -Codes @('COMPANY_PAY_NO_SCREENSHOT'))) {
        OkCompany "company order rejects payment screenshot upload"
    } elseif ($upCo.Code -eq 200) {
        BadCompany "company order should not allow screenshot upload"
    } else {
        BadCompany "unexpected screenshot response for company order code=$($upCo.Code) body=$($upCo.Body)"
    }

    $coAcc = Invoke-Api -Method Put -Uri "$base/orders/$companyOrderId/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress)
    if ($coAcc.Ok -and $coAcc.Data.status -eq 'accepted') {
        OkCompany "merchant accepted company order without screenshot"
    } else {
        BadCompany "merchant accept company order failed code=$($coAcc.Code) body=$($coAcc.Body)"
    }

    # complete for potential review reuse
    Invoke-Api -Method Put -Uri "$base/orders/$companyOrderId/status" -Headers $merHeaders -Body (@{ status = 'completed' } | ConvertTo-Json -Compress) | Out-Null
}

# overtime no longer auto company_pay without roster (covered by check_overtime_roster_pay.ps1)

# =============================================================
# C. Review flow
# =============================================================
Write-Host "`n--- C. Reviews ---" -ForegroundColor Cyan

$reviewAdminHeaders = Save-EnableReviewSetting
if ($reviewAdminHeaders) {
    if ($script:savedEnableReview) {
        OkReview "enableReview already true in system config"
    } elseif (Enable-ReviewForTest $reviewAdminHeaders) {
        OkReview "temporarily enabled enableReview for e2e (will restore)"
    } else {
        BadReview "failed to enable enableReview for e2e"
    }
} else {
    BadReview "cannot read system config for enableReview"
}

$reviewOrderId = $null
if ($empSelfHeaders -and $selfPayDish -and $selfPayMeal) {
    $reviewOrderId = New-CompletedSelfPayOrder -Headers $empSelfHeaders
    if ($reviewOrderId) { OkReview "created dedicated completed order for review ($reviewOrderId)" }
}
if (-not $reviewOrderId) { $reviewOrderId = $personalOrderId }
if (-not $reviewOrderId -and $companyOrderId) { $reviewOrderId = $companyOrderId }

if (-not $reviewOrderId) {
    BadReview "no completed order available for review tests"
} elseif (-not $empSelfHeaders) {
    BadReview "no employee headers for review tests"
} else {
    # pending order cannot be reviewed
    $pending = Create-DishOrder -EmpHeaders $empSelfHeaders -MerchantId $merchantId -MerchantName $merchantName -Dish $selfPayDish -MealType $selfPayMeal -PaymentType 'self_pay'
    if ($pending.Ok -and $pending.Data.id) {
        $badRev = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empSelfHeaders -Body (@{
            orderId = $pending.Data.id; rating = 5; content = 'should fail'; images = @()
        } | ConvertTo-Json -Compress)
        if (-not $badRev.Ok -and ($badRev.Code -eq 400 -or (Test-ApiErrCode -Result $badRev -Codes @('ORDER_NOT_COMPLETED','REVIEW_DISABLED')))) {
            OkReview "non-completed order cannot be reviewed"
        } else {
            BadReview "expected ORDER_NOT_COMPLETED for pending order code=$($badRev.Code) body=$($badRev.Body)"
        }
    }

    $badRating = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empSelfHeaders -Body (@{
        orderId = $reviewOrderId; rating = 0; content = 'bad'; images = @()
    } | ConvertTo-Json -Compress)
    if (-not $badRating.Ok -and ($badRating.Code -eq 400 -or (Test-ApiErrCode -Result $badRating -Codes @('INVALID_RATING','REVIEW_DISABLED')))) {
        OkReview "rating=0 rejected (INVALID_RATING)"
    } else {
        BadReview "rating=0 should be rejected code=$($badRating.Code) body=$($badRating.Body)"
    }

    $tooManyImg = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empSelfHeaders -Body (@{
        orderId = $reviewOrderId; rating = 5; content = 'too many'; images = @('a','b','c','d','e','f','g','h','i','j')
    } | ConvertTo-Json -Compress)
    if (-not $tooManyImg.Ok -and ($tooManyImg.Code -eq 400 -or (Test-ApiErrCode -Result $tooManyImg -Codes @('INVALID_IMAGE_COUNT','REVIEW_DISABLED')))) {
        OkReview "10 images rejected (max 9)"
    } else {
        BadReview "10 images should be rejected code=$($tooManyImg.Code) body=$($tooManyImg.Body)"
    }

    $twoImgOrder = New-CompletedSelfPayOrder -Headers $empSelfHeaders
    if ($twoImgOrder) {
        $twoImgRev = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empSelfHeaders -Body (@{
            orderId = $twoImgOrder; rating = 5; content = 'two imgs'; images = @('http://local/a.png','http://local/b.png')
        } | ConvertTo-Json -Compress)
        if ($twoImgRev.Ok) { OkReview "2-image review accepted" }
        else { BadReview "2-image review should succeed code=$($twoImgRev.Code) body=$($twoImgRev.Body)" }
    } else {
        BadReview "could not create order for 2-image review test"
    }

    $oneImgOrder = New-CompletedSelfPayOrder -Headers $empSelfHeaders
    if ($oneImgOrder) {
        $oneImgRev = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empSelfHeaders -Body (@{
            orderId = $oneImgOrder; rating = 4; content = 'one img'; images = @('http://local/x.png')
        } | ConvertTo-Json -Compress)
        if ($oneImgRev.Ok) { OkReview "1-image review accepted" }
        else { BadReview "1-image review should succeed code=$($oneImgRev.Code) body=$($oneImgRev.Body)" }
    } else {
        BadReview "could not create order for 1-image review test"
    }

    if (-not $reviewOrderId) {
        $reviewOrderId = New-CompletedSelfPayOrder -Headers $empSelfHeaders
    }

    $merBefore = Invoke-RestMethod -Uri "$base/merchants" -Method Get -TimeoutSec 8
    $mBefore = $merBefore.data | Where-Object { $_.id -eq $merchantId } | Select-Object -First 1
    $ratingBefore = if ($mBefore) { [double]$mBefore.rating } else { 0 }

    $goodRev = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empSelfHeaders -Body (@{
        orderId = $reviewOrderId; rating = 5; content = 'e2e good review'; images = @()
    } | ConvertTo-Json -Compress)
    if ($goodRev.Ok -and $goodRev.Data.id) {
        OkReview "submit review ok (rating=5, 0 images)"
    } else {
        BadReview "submit review failed code=$($goodRev.Code) body=$($goodRev.Body)"
    }

    $gotRev = Invoke-Api -Method Get -Uri "$base/reviews/order/$reviewOrderId" -Headers $empSelfHeaders
    if ($gotRev.Ok -and $gotRev.Data -and $gotRev.Data.orderId -eq $reviewOrderId) {
        OkReview "GET /api/reviews/order/:id returns review"
        if ($gotRev.Data.rating -ge 1 -and $gotRev.Data.rating -le 5) { OkReview "stored rating in range 1-5" }
        else { BadReview "stored rating out of range" }
    } else {
        BadReview "GET review by order failed code=$($gotRev.Code)"
    }

    $dup = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empSelfHeaders -Body (@{
        orderId = $reviewOrderId; rating = 4; content = 'dup'; images = @()
    } | ConvertTo-Json -Compress)
    if (-not $dup.Ok -and ($dup.Code -eq 400)) {
        OkReview "duplicate review rejected"
    } else {
        BadReview "duplicate review should be rejected code=$($dup.Code) body=$($dup.Body)"
    }

    $merAfter = Invoke-RestMethod -Uri "$base/merchants" -Method Get -TimeoutSec 8
    $mAfter = $merAfter.data | Where-Object { $_.id -eq $merchantId } | Select-Object -First 1
    if ($mAfter -and $mAfter.rating -ne $null) {
        OkReview "merchant rating field present after review (rating=$($mAfter.rating))"
        if ($mAfter.hygieneGrade) { OkReview "merchant hygieneGrade present ($($mAfter.hygieneGrade))" }
        else { BadReview "merchant hygieneGrade missing after review" }
    } else {
        BadReview "merchant rating not updated/visible"
    }

    # valid 3-image review on company order if available and not yet reviewed
    if ($companyOrderId -and $companyOrderId -ne $reviewOrderId -and $empCoHeaders) {
        $coReviewOrder = $companyOrderId
        $existingCo = Invoke-Api -Method Get -Uri "$base/reviews/order/$coReviewOrder" -Headers $empCoHeaders
        if ($existingCo.Ok -and $existingCo.Data) {
            $coReviewOrder = New-CompletedOrderForRisk -Headers $empCoHeaders -Suffix 'img'
        }
        if ($coReviewOrder) {
            $imgRev = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empCoHeaders -Body (@{
                orderId = $coReviewOrder; rating = 4; content = 'with images'; images = @('http://local/a.png','http://local/b.png','http://local/c.png')
            } | ConvertTo-Json -Compress)
            if ($imgRev.Ok) { OkReview "3-image review accepted on company order" }
            else { BadReview "3-image review failed code=$($imgRev.Code) body=$($imgRev.Body)" }
        }
    }
}

# =============================================================
# D. Risk control (isolated snapshot + restore)
# =============================================================
Write-Host "`n--- D. Risk control ---" -ForegroundColor Cyan

$riskMerchantId = $merchantId
$riskSnapshot = $null
$adminHeaders2 = $reviewAdminHeaders
try {
    if (-not $adminHeaders2) {
        $admin2 = AdminLogin
        $adminHeaders2 = @{ Authorization = "Bearer $($admin2.data.token)" }
    }
    $pubMer = Invoke-RestMethod -Uri "$base/merchants" -Method Get -TimeoutSec 8
    $riskRow = $pubMer.data | Where-Object { $_.id -eq $riskMerchantId } | Select-Object -First 1
    if ($riskRow) {
        $riskSnapshot = @{
            rating = [double]$riskRow.rating
            grade = [string]$riskRow.hygieneGrade
            isOpen = [bool]$riskRow.isOpen
        }
        OkRisk "saved merchant snapshot (rating=$($riskSnapshot.rating) grade=$($riskSnapshot.grade) isOpen=$($riskSnapshot.isOpen))"
    } else {
        BadRisk "cannot read merchant row for snapshot"
    }
} catch {
    BadRisk "read merchant snapshot failed: $($_.Exception.Message)"
}

if ($riskSnapshot -and $empCoHeaders) {
    if (-not $script:savedEnableReview -and $reviewAdminHeaders) {
        Enable-ReviewForTest $reviewAdminHeaders | Out-Null
    }
    Restore-MerchantSnapshot $riskMerchantId 4.8 'A' $true | Out-Null

    $riskOrderIds = @()
    for ($i = 0; $i -lt 3; $i++) {
        $oid = New-CompletedOrderForRisk -Headers $empCoHeaders -Suffix $i
        if ($oid) { $riskOrderIds += $oid }
    }
    if ($riskOrderIds.Count -lt 3) {
        BadRisk "could not create 3 completed orders for risk tests"
    } else {
        OkRisk "created $($riskOrderIds.Count) completed orders for low-score reviews"
    }

    foreach ($i in 0..2) {
        $rv = Invoke-Api -Method Post -Uri "$base/reviews" -Headers $empCoHeaders -Body (@{
            orderId = $riskOrderIds[$i]; rating = 1; content = "risk low #$i"; images = @()
        } | ConvertTo-Json -Compress)
        if (-not $rv.Ok) { BadRisk "low-score review #$i failed code=$($rv.Code) body=$($rv.Body)" }
    }

    Start-Sleep -Milliseconds 400
    $riskMer = Invoke-RestMethod -Uri "$base/merchants" -Method Get -TimeoutSec 8
    $riskM = $riskMer.data | Where-Object { $_.id -eq $riskMerchantId } | Select-Object -First 1
    if ($riskM) {
        $r = [double]$riskM.rating
        $g = [string]$riskM.hygieneGrade
        $open = [bool]$riskM.isOpen

        if ($r -lt 3.0) { OkRisk "average rating < 3.0 triggers remediation threshold (rating=$r)" }
        else { BadRisk "expected rating < 3.0 after 3x1-star, got $r" }

        if ($g -ne 'A') { OkRisk "merchant grade degraded from A (now $g)" }
        else { BadRisk "expected grade downgrade from A, still $g" }

        if (-not $open -and $r -lt 2.5) { OkRisk "average rating < 2.5 auto closed shop (isOpen=false)" }
        elseif ($r -ge 2.5) { OkRisk "rating >= 2.5 shop may remain open (rating=$r isOpen=$open)" }
        else { BadRisk "expected is_open=0 when rating < 2.5, isOpen=$open rating=$r" }
    } else {
        BadRisk "cannot read merchant after risk reviews"
    }
}

# always restore merchant snapshot if captured
if ($riskSnapshot) {
    Restore-MerchantSnapshot $riskMerchantId $riskSnapshot.rating $riskSnapshot.grade $riskSnapshot.isOpen | Out-Null
    try {
        Invoke-RestMethod -Method Put -Uri "$base/admin/merchants/$riskMerchantId/open" -Headers $adminHeaders2 -ContentType 'application/json' -Body (@{ isOpen = $riskSnapshot.isOpen } | ConvertTo-Json -Compress) | Out-Null
    } catch { }
    Restore-EnableReviewSetting $reviewAdminHeaders
    $verify = Invoke-RestMethod -Uri "$base/merchants" -Method Get -TimeoutSec 8
    $vr = $verify.data | Where-Object { $_.id -eq $riskMerchantId } | Select-Object -First 1
    if ($vr -and [math]::Abs([double]$vr.rating - $riskSnapshot.rating) -lt 0.01 -and $vr.hygieneGrade -eq $riskSnapshot.grade -and [bool]$vr.isOpen -eq $riskSnapshot.isOpen) {
        OkRisk "verified merchant state restored after risk tests"
    } else {
        BadRisk "merchant state restore verification failed (rating=$($vr.rating) grade=$($vr.hygieneGrade) isOpen=$($vr.isOpen))"
    }
}

# =============================================================
# Summary
# =============================================================
Write-Host "`n================ SUMMARY ================" -ForegroundColor Cyan

function SectionOk($pass, $fail) { return ($fail -eq 0 -and $pass -gt 0) }

$personalOk = SectionOk $script:personalPass $script:personalFail
$companyOk  = SectionOk $script:companyPass $script:companyFail
$reviewOk   = SectionOk $script:reviewPass $script:reviewFail
$riskOk     = SectionOk $script:riskPass $script:riskFail

Write-Host "Personal payment : PASS=$script:personalPass FAIL=$script:personalFail -> $(if ($personalOk) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($personalOk) { 'Green' } else { 'Red' })
Write-Host "Company pay      : PASS=$script:companyPass FAIL=$script:companyFail -> $(if ($companyOk) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($companyOk) { 'Green' } else { 'Red' })
Write-Host "Reviews          : PASS=$script:reviewPass FAIL=$script:reviewFail -> $(if ($reviewOk) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($reviewOk) { 'Green' } else { 'Red' })
Write-Host "Risk control     : PASS=$script:riskPass FAIL=$script:riskFail -> $(if ($riskOk) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($riskOk) { 'Green' } else { 'Red' })

$totalFail = $script:personalFail + $script:companyFail + $script:reviewFail + $script:riskFail
if ($totalFail -eq 0) {
    Write-Host "`n[OK] check_payment_review all sections passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[NO] check_payment_review has failures" -ForegroundColor Red
    exit 1
}
