# check_coupon.ps1 - merchant coupon E2E checks

$ErrorActionPreference = 'Continue'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
. (Join-Path $PSScriptRoot '_ps_helpers.ps1')

$pass = 0
$fail = 0
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Info($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }
function Skip($msg) { Write-Host "[SKIP] $msg" -ForegroundColor Yellow }

function ReadErrBody($err) {
    try {
        $resp = $err.Exception.Response
        if (-not $resp) { return $null }
        $s = $resp.GetResponseStream()
        $r = New-Object System.IO.StreamReader($s, [System.Text.Encoding]::UTF8)
        return $r.ReadToEnd()
    } catch { return $null }
}

function Login($phone, $role) {
    $body = @{ phone = $phone; password = '123456'; role = $role } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body $body -TimeoutSec 8
}

function AdminLogin() {
    return Invoke-RestMethod -Method Post -Uri "$base/admin/auth/password-login" -ContentType 'application/json' -Body '{"phone":"13700000000","password":"123456"}' -TimeoutSec 8
}

function Invoke-Api {
    param([string]$Method, [string]$Uri, [hashtable]$Headers = @{}, [string]$Body = $null)
    try {
        $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; TimeoutSec = 15 }
        if ($Body) { $p.Body = $Body; $p.ContentType = 'application/json' }
        $resp = Invoke-WebRequest @p -UseBasicParsing
        $json = $null
        try { $json = $resp.Content | ConvertFrom-Json } catch {}
        return @{ Ok = $true; Code = [int]$resp.StatusCode; Data = $json.data; Raw = $json }
    } catch {
        $code = 0; $body = ReadErrBody $_
        try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        $json = $null
        try { if ($body) { $json = $body | ConvertFrom-Json } } catch {}
        return @{
            Ok = $false; Code = $code; Data = $json.data; Raw = $json; Body = $body
            ErrorCode = $(if ($json -and $json.error) { $json.error.code } else { $null })
        }
    }
}

function TodayStr {
    $d = Get-Date
    return '{0:0000}-{1:00}-{2:00}' -f $d.Year, $d.Month, $d.Day
}

Write-Host "=== feigong-yuncan check_coupon ===" -ForegroundColor Cyan
Write-Host "API base: $base"

# --- login ---
try {
    $mer = Login '13900000000' 'merchant'
    $merHeaders = @{ Authorization = "Bearer $($mer.data.token)" }
    $prof = Invoke-RestMethod -Method Get -Uri "$base/merchant/profile" -Headers $merHeaders -TimeoutSec 8
    $merchantId = $prof.data.id
    Ok "merchant login (merchantId=$merchantId)"
} catch {
    Bad "merchant login failed: $($_.Exception.Message)"; exit 1
}

try {
    $emp = Login '13800000001' 'employee'
    $empHeaders = @{ Authorization = "Bearer $($emp.data.token)" }
    $empUserId = $emp.data.user.id
    Ok "employee login (id=$empUserId)"
} catch {
    Bad "employee login failed: $($_.Exception.Message)"; exit 1
}

$admin = AdminLogin
$adminHeaders = @{ Authorization = "Bearer $($admin.data.token)" }

# --- meal type ---
$cfg = Invoke-RestMethod -Method Get -Uri "$base/config/runtime" -TimeoutSec 8
$now = Get-Date
$curMin = $now.Hour * 60 + $now.Minute
function Test-MealOpen($mealType) {
    $dl = $cfg.data.mealDeadlines.$mealType
    if (-not $dl) { return $true }
    $parts = ($dl -as [string]) -split ':'
    if ($parts.Count -lt 2) { return $true }
    $dMin = [int]$parts[0] * 60 + [int]$parts[1]
    return $curMin -le $dMin
}
$mealType = 'lunch'
foreach ($mt in @('lunch','dinner','breakfast')) {
    if (Test-MealOpen $mt) { $mealType = $mt; break }
}

# extend meal windows for E2E
$hoursBackup = @{ supportedMealTypes = @($prof.data.supportedMealTypes); mealOpeningHours = $prof.data.mealOpeningHours }
$extBody = @{
    merchantId = $merchantId
    supportedMealTypes = @('breakfast','lunch','dinner','overtime')
    mealOpeningHours = @{
        breakfast = @{ enabled = $true; start = '06:00'; end = '23:59' }
        lunch = @{ enabled = $true; start = '06:00'; end = '23:59' }
        dinner = @{ enabled = $true; start = '06:00'; end = '23:59' }
        overtime = @{ enabled = $true; start = '06:00'; end = '23:59' }
    }
} | ConvertTo-Json -Depth 6 -Compress
Invoke-Api -Method Put -Uri "$base/merchant/business-hours" -Headers $merHeaders -Body $extBody | Out-Null

# --- setup package (reuse pattern from check_package) ---
function CreateDish($name, $category, $extraPrice) {
    $body = @{
        merchantId = $merchantId; name = $name; price = 0; mealType = $mealType
        category = $category; extraPrice = $extraPrice; mealTypes = @($mealType); isAvailable = $true
    } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/dishes" -Headers $merHeaders -ContentType 'application/json' -Body $body -TimeoutSec 8
}

try {
    $meat = CreateDish 'CouponTest-Meat' 'meat' 0
    $veg1 = CreateDish 'CouponTest-Veg1' 'vegetable' 0
    $veg2 = CreateDish 'CouponTest-Veg2' 'vegetable' 0
    $extra1 = CreateDish 'CouponTest-Extra' 'extra' 9
    $pkgBody = @{
        merchantId = $merchantId; name = 'CouponTest-Pkg'; basePrice = 15
        mealTypes = @($mealType); rules = @{ meat = 1; vegetable = 2 }; isEnabled = $true
    } | ConvertTo-Json -Compress
    $pkg = Invoke-RestMethod -Method Post -Uri "$base/packages" -Headers $merHeaders -ContentType 'application/json' -Body $pkgBody -TimeoutSec 8
    $packageId = $pkg.data.id
    Ok "test package created (basePrice=15, id=$packageId)"
} catch {
    Bad "setup dishes/package failed: $($_.Exception.Message)"; exit 1
}

$selectedIds = @($meat.data.id, $veg1.data.id, $veg2.data.id)
$extras = @(@{ dishId = $extra1.data.id; quantity = 1 })
# total = 15 + 9 = 24

function PlaceOrder($claimId, $extrasArg) {
    $bodyHash = @{
        merchantId = $merchantId; merchantName = 'CouponTest'
        deliveryType = 'selfPickup'; mealType = $mealType
        goodsAmount = 0; deliveryFee = 0; totalAmount = 0
        packageOrder = @{
            packageId = $packageId
            selectedDishIds = $selectedIds
            extras = $extrasArg
        }
    }
    if ($claimId) { $bodyHash.couponClaimId = $claimId }
    $body = $bodyHash | ConvertTo-Json -Compress -Depth 8
    return Invoke-Api -Method Post -Uri "$base/orders" -Headers $empHeaders -Body $body
}

$startAt = (Get-Date).AddDays(-1).ToUniversalTime().ToString('o')
$endAt = (Get-Date).AddDays(30).ToUniversalTime().ToString('o')

# 1. merchant creates threshold coupon (min 20 off 5)
try {
    $cBody = @{
        name = 'Threshold20Off5-E2E'
        couponType = 'threshold'
        discountAmount = 5
        minOrderAmount = 20
        mealTypes = @($mealType)
        totalQuantity = 50
        perUserLimit = 5
        startAt = $startAt
        endAt = $endAt
    } | ConvertTo-Json -Compress
    $tpl = Invoke-RestMethod -Method Post -Uri "$base/merchant/coupons" -Headers $merHeaders -ContentType 'application/json' -Body $cBody -TimeoutSec 8
    $thresholdTplId = $tpl.data.id
    Ok "merchant created threshold coupon (id=$thresholdTplId)"
} catch {
    Bad "create threshold coupon failed: $($_.Exception.Message)"; exit 1
}

# fixed coupon for zero-pay test (off 15)
try {
    $fBody = @{
        name = 'FixedOff15-E2E'
        couponType = 'fixed'
        discountAmount = 15
        minOrderAmount = 0
        mealTypes = @($mealType)
        totalQuantity = 50
        perUserLimit = 5
        startAt = $startAt
        endAt = $endAt
    } | ConvertTo-Json -Compress
    $fixedTpl = Invoke-RestMethod -Method Post -Uri "$base/merchant/coupons" -Headers $merHeaders -ContentType 'application/json' -Body $fBody -TimeoutSec 8
    $fixedTplId = $fixedTpl.data.id
    Ok "merchant created fixed coupon (id=$fixedTplId)"
} catch {
    Bad "create fixed coupon failed: $($_.Exception.Message)"
}

# high threshold coupon (min 100 off 50)
try {
    $hBody = @{
        name = 'Threshold100Off50-E2E'
        couponType = 'threshold'
        discountAmount = 50
        minOrderAmount = 100
        mealTypes = @($mealType)
        totalQuantity = 10
        perUserLimit = 2
        startAt = $startAt
        endAt = $endAt
    } | ConvertTo-Json -Compress
    $highTpl = Invoke-RestMethod -Method Post -Uri "$base/merchant/coupons" -Headers $merHeaders -ContentType 'application/json' -Body $hBody -TimeoutSec 8
    $highTplId = $highTpl.data.id
    $highClaim = Invoke-RestMethod -Method Post -Uri "$base/coupons/$highTplId/claim" -Headers $empHeaders -ContentType 'application/json' -Body '{}' -TimeoutSec 8
    $highClaimId = $highClaim.data.id
    Ok "created high-threshold coupon and claimed"
} catch {
    Bad "high threshold coupon setup failed: $($_.Exception.Message)"
}

# 2. employee claims threshold coupon
try {
    $claim = Invoke-RestMethod -Method Post -Uri "$base/coupons/$thresholdTplId/claim" -Headers $empHeaders -ContentType 'application/json' -Body '{}' -TimeoutSec 8
    $thresholdClaimId = $claim.data.id
    Ok "employee claimed threshold coupon (claimId=$thresholdClaimId)"
} catch {
    Bad "claim failed: $($_.Exception.Message)"; exit 1
}

# 4. threshold not met (100 min on 24 order)
$res = PlaceOrder $highClaimId $extras
if (-not $res.Ok -and $res.ErrorCode -eq 'THRESHOLD_NOT_MET') {
    Ok "threshold not met blocked (THRESHOLD_NOT_MET)"
} elseif (-not $res.Ok) {
    Ok "threshold not met blocked (code=$($res.Code))"
} else {
    Bad "high threshold coupon should not apply but order succeeded"
}

# 3. threshold met — 24 total, discount 5, employee pay 19
$res = PlaceOrder $thresholdClaimId $extras
if ($res.Ok -and $res.Data.couponDiscountAmount -eq 5 -and $res.Data.employeePayAmount -eq 19) {
    Ok "threshold met: discount=5 employeePay=19 status=$($res.Data.status)"
    $orderWithCoupon = $res.Data.id
} else {
    Bad ("threshold order unexpected: ok=$($res.Ok) discount=$($res.Data.couponDiscountAmount) pay=$($res.Data.employeePayAmount) body=$($res.Body)")
}

if ($res.Data.status -eq 'pendingPayment') {
    Ok "employee still needs pay -> pendingPayment"
} else {
    Bad "expected pendingPayment got $($res.Data.status)"
}

# claim another threshold for company pay test
$claim2 = Invoke-RestMethod -Method Post -Uri "$base/coupons/$thresholdTplId/claim" -Headers $empHeaders -ContentType 'application/json' -Body '{}' -TimeoutSec 8
$thresholdClaimId2 = $claim2.data.id

# 5. company pay + coupon - roster employee 13800000002
try {
    $workDate = TodayStr
    Clear-OvertimeMealUsagesForE2e -WorkDate $workDate | Out-Null
    $existing = Invoke-Api -Method Get -Uri "$base/admin/overtime-rosters?workDate=$workDate" -Headers $adminHeaders
    if ($existing.Ok -and $existing.Data) {
        foreach ($row in $existing.Data) {
            if ($row.phone -eq '13800000002') {
                Invoke-Api -Method Delete -Uri "$base/admin/overtime-rosters/$($row.id)" -Headers $adminHeaders | Out-Null
            }
        }
    }
    $rosterBody = @{
        workDate = $workDate
        mealType = $mealType
        employeeName = 'WangWu'
        phone = '13800000002'
        department = 'Prod'
        employeeNo = 'E003'
    } | ConvertTo-Json -Compress
    $rosterRes = Invoke-Api -Method Post -Uri "$base/admin/overtime-rosters" -Headers $adminHeaders -Body $rosterBody
    if (-not $rosterRes.Ok) { throw "roster create failed: $($rosterRes.Body)" }
    $wang = Login '13800000002' 'employee'
    $wangHeaders = @{ Authorization = "Bearer $($wang.data.token)" }
    $wangClaim = Invoke-RestMethod -Method Post -Uri "$base/coupons/$thresholdTplId/claim" -Headers $wangHeaders -ContentType 'application/json' -Body '{}' -TimeoutSec 8
    $wangClaimId = $wangClaim.data.id
    $body = @{
        merchantId = $merchantId; merchantName = 'CouponTest'
        deliveryType = 'selfPickup'; mealType = $mealType
        goodsAmount = 0; deliveryFee = 0; totalAmount = 0
        couponClaimId = $wangClaimId
        packageOrder = @{
            packageId = $packageId
            selectedDishIds = $selectedIds
            extras = $extras
        }
    } | ConvertTo-Json -Compress -Depth 8
    $resCo = Invoke-Api -Method Post -Uri "$base/orders" -Headers $wangHeaders -Body $body
    if ($resCo.Ok -and $resCo.Data.companyPayAmount -eq 12 -and $resCo.Data.couponDiscountAmount -eq 5 -and $resCo.Data.employeePayAmount -eq 7) {
        Ok "company pay + coupon: company=12 discount=5 employeePay=7"
    } else {
        Bad ("company+coupon mismatch: ok=$($resCo.Ok) company=$($resCo.Data.companyPayAmount) discount=$($resCo.Data.couponDiscountAmount) pay=$($resCo.Data.employeePayAmount) body=$($resCo.Body)")
    }
} catch {
    Bad "company pay + coupon test failed: $($_.Exception.Message)"
}

# 6. coupon covers employee pay -> pendingMerchantConfirm (no extras, fixed 15 off)
try {
    $fixedClaim = Invoke-RestMethod -Method Post -Uri "$base/coupons/$fixedTplId/claim" -Headers $empHeaders -ContentType 'application/json' -Body '{}' -TimeoutSec 8
    $fixedClaimId = $fixedClaim.data.id
    $body = @{
        merchantId = $merchantId; merchantName = 'CouponTest'
        deliveryType = 'selfPickup'; mealType = $mealType
        goodsAmount = 0; deliveryFee = 0; totalAmount = 0
        couponClaimId = $fixedClaimId
        packageOrder = @{
            packageId = $packageId
            selectedDishIds = $selectedIds
            extras = @()
        }
    } | ConvertTo-Json -Compress -Depth 8
    $resZero = Invoke-Api -Method Post -Uri "$base/orders" -Headers $empHeaders -Body $body
    # total 15, no company pay, coupon 15 -> employee 0
    if ($resZero.Ok -and $resZero.Data.employeePayAmount -eq 0 -and $resZero.Data.status -eq 'pendingMerchantConfirm') {
        Ok "coupon zero employee pay -> pendingMerchantConfirm"
    } else {
        Bad ("zero pay expected pendingMerchantConfirm got pay=$($resZero.Data.employeePayAmount) status=$($resZero.Data.status)")
    }
} catch {
    Bad "zero pay coupon test failed: $($_.Exception.Message)"
}

# 8. same coupon cannot reuse
$reuse = PlaceOrder $thresholdClaimId $extras
if (-not $reuse.Ok) {
    Ok "reused coupon blocked (code=$($reuse.ErrorCode))"
} else {
    Bad "reused coupon should fail but order succeeded"
}

# 9. expired coupon cannot claim
try {
    $pastStart = (Get-Date).AddDays(-10).ToUniversalTime().ToString('o')
    $pastEnd = (Get-Date).AddDays(-1).ToUniversalTime().ToString('o')
    $expBody = @{
        name = 'Expired-E2E'
        couponType = 'fixed'
        discountAmount = 3
        mealTypes = @($mealType)
        totalQuantity = 10
        perUserLimit = 1
        startAt = $pastStart
        endAt = $pastEnd
    } | ConvertTo-Json -Compress
    $expTpl = Invoke-RestMethod -Method Post -Uri "$base/merchant/coupons" -Headers $merHeaders -ContentType 'application/json' -Body $expBody -TimeoutSec 8
    try {
        Invoke-WebRequest -Method Post -Uri "$base/coupons/$($expTpl.data.id)/claim" -Headers $empHeaders -ContentType 'application/json' -Body '{}' -TimeoutSec 8 -UseBasicParsing | Out-Null
        Bad "expired coupon claim should fail"
    } catch {
        $c = $_.Exception.Response.StatusCode.value__
        if ($c -eq 400) { Ok "expired coupon claim blocked (400)" }
        else { Bad "expired coupon returned $c" }
    }
} catch {
    Bad "expired coupon test setup failed: $($_.Exception.Message)"
}

# 10. unauthorized - employee cannot manage merchant coupons
$res403 = Invoke-Api -Method Post -Uri "$base/merchant/coupons" -Headers $empHeaders -Body (@{
    name = 'Hack'; couponType = 'fixed'; discountAmount = 99; totalQuantity = 1; startAt = $startAt; endAt = $endAt
} | ConvertTo-Json -Compress)
if (-not $res403.Ok -and $res403.Code -eq 403) {
    Ok "employee create coupon rejected (403)"
} else {
    Bad "expected 403 for employee coupon create got $($res403.Code)"
}

# restore meal hours
if ($hoursBackup) {
    $rb = @{
        merchantId = $merchantId
        supportedMealTypes = $hoursBackup.supportedMealTypes
        mealOpeningHours = $hoursBackup.mealOpeningHours
    } | ConvertTo-Json -Depth 8 -Compress
    Invoke-Api -Method Put -Uri "$base/merchant/business-hours" -Headers $merHeaders -Body $rb | Out-Null
}

Write-Host ""
Write-Host "=== check_coupon summary: PASS=$pass FAIL=$fail ===" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
