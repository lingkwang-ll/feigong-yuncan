# =============================================================
# check_package.ps1
#
# Package + extra ordering end-to-end check.
# Business simplification: package rules only validate meat / vegetable;
# extras no longer depend on package.allowExtra.
#
#   1. merchant login
#   2. create dishes (meat / vegetable / extra)
#   3. extra dish without price -> 400
#   4. create one-meat-two-vegetable package (base 15);
#      request includes legacy staple=1 + allowExtra=false to verify
#      server drops them and still allows extras.
#   5. employee login -> list packages
#   6. under-pick / over-pick -> 400 (meat/vegetable only)
#   7. correct pick (1 meat + 2 veg) + 2 extras
#      -> server recalculates 15 + 6 + 3 = 24
#   8. merchant order detail shows package / selected / extras / final
#   9. payment screenshot + accept + employee tracking + complete
#  10. legacy single-dish order still works
# =============================================================

$ErrorActionPreference = 'Continue'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }

function ReadErrBody($err) {
    try {
        $resp = $err.Exception.Response
        if (-not $resp) { return $null }
        $s = $resp.GetResponseStream()
        $r = New-Object System.IO.StreamReader($s, [System.Text.Encoding]::UTF8)
        return $r.ReadToEnd()
    } catch { return $null }
}

$pass = 0
$fail = 0
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Info($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

Write-Host "=== feigong-yuncan check_package ===" -ForegroundColor Cyan
Write-Host "API base: $base"

function Login($phone, $role) {
    $body = @{ phone=$phone; password='123456'; role=$role } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body $body -TimeoutSec 5
}

# 1. merchant login
try {
    $mer = Login '13900000000' 'merchant'
    $merId = $mer.data.user.id
    $merHeaders = @{ Authorization = "Bearer $($mer.data.token)" }
    $prof = Invoke-RestMethod -Method Get -Uri "$base/merchant/profile" -Headers $merHeaders -TimeoutSec 5
    $merchantId = $prof.data.id
    Ok "merchant login (userId=$merId, merchantId=$merchantId)"
} catch {
    Bad "merchant login failed: $($_.Exception.Message)"; exit 1
}

# 2. create dishes
# pick a meal type whose deadline has not yet passed
$cfg = Invoke-RestMethod -Method Get -Uri "$base/config/runtime" -TimeoutSec 5
$now = Get-Date
$curMin = $now.Hour * 60 + $now.Minute
function Test-MealOpen($mealType) {
    $dl = $cfg.data.mealDeadlines.$mealType
    if (-not $dl) { return $true }
    $parts = $dl -split ':'
    if ($parts.Count -lt 2) { return $true }
    $dMin = [int]$parts[0] * 60 + [int]$parts[1]
    return $curMin -le $dMin
}
$mealType = 'lunch'
$mealOpen = $false
foreach ($mt in @('lunch','dinner','overtime','breakfast')) {
    if (Test-MealOpen $mt) { $mealType = $mt; $mealOpen = $true; break }
}
Info ("using mealType=" + $mealType + " (open=" + $mealOpen + ")")
function Skip($msg) { Write-Host "[SKIP] $msg" -ForegroundColor Yellow }

function CreateDish($name, $price, $category, $extraPrice) {
    $body = @{
        merchantId = $merchantId
        name = $name
        price = $price
        mealType = $mealType
        category = $category
        extraPrice = $extraPrice
        mealTypes = @($mealType)
        isAvailable = $true
    } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/dishes" -Headers $merHeaders -ContentType 'application/json' -Body $body -TimeoutSec 5
}

# extra without price must be rejected
try {
    $body = @{ merchantId=$merchantId; name='ExtraNoPrice'; price=0; mealType=$mealType; category='extra'; mealTypes=@($mealType) } | ConvertTo-Json -Compress
    $r = Invoke-WebRequest -Method Post -Uri "$base/dishes" -Headers $merHeaders -ContentType 'application/json' -Body $body -TimeoutSec 5 -UseBasicParsing
    Bad ("extra-without-price should be blocked but got " + $r.StatusCode)
} catch {
    $c = $_.Exception.Response.StatusCode.value__
    if ($c -eq 400) { Ok "extra-without-price blocked (400)" }
    else { Bad ("extra-without-price returned " + $c) }
}

try {
    $meat = CreateDish 'HongShaoRou-PKG' 0 'meat' 0
    $veg1 = CreateDish 'QingChaoQingCai-PKG' 0 'vegetable' 0
    $veg2 = CreateDish 'FanQieChaoDan-PKG' 0 'vegetable' 0
    $stap = CreateDish 'MiFan-PKG' 0 'staple' 0
    $extra1 = CreateDish 'JiTui-Extra' 0 'extra' 6
    $extra2 = CreateDish 'YinLiao-Extra' 0 'extra' 3
    Ok "dish library created (meat/veg/veg/staple/extra x2)"
} catch {
    Bad ("dish creation failed: " + $_.Exception.Message); exit 1
}

# 4. create package
#    Intentionally also send staple=1 and allowExtra=false: backend must
#    silently drop these and rebuild rules with meat/vegetable only.
try {
    $pkgBody = @{
        merchantId = $merchantId
        name = 'OneMeatTwoVeg-PKG'
        description = 'rules should be normalized to 1 meat + 2 veg'
        basePrice = 15
        mealTypes = @($mealType)
        rules = @{ meat=1; vegetable=2; staple=1 }
        allowExtra = $false
        isEnabled = $true
    } | ConvertTo-Json -Compress
    $pkg = Invoke-RestMethod -Method Post -Uri "$base/packages" -Headers $merHeaders -ContentType 'application/json' -Body $pkgBody -TimeoutSec 5
    $packageId = $pkg.data.id
    Ok ("package created (id=" + $packageId + ", basePrice=" + $pkg.data.basePrice + ")")
    # server should have stripped staple from rules
    $serverRules = $pkg.data.rules
    $stapleVal = 0
    if ($serverRules.PSObject.Properties['staple']) { $stapleVal = [int]$serverRules.staple }
    if ($stapleVal -eq 0) { Ok "server normalized rules: staple dropped" }
    else { Bad ("server kept staple=" + $stapleVal + " in rules") }
    if ($serverRules.meat -eq 1 -and $serverRules.vegetable -eq 2) { Ok "server kept meat=1 vegetable=2" }
    else { Bad ("server rules mismatch meat=" + $serverRules.meat + " vegetable=" + $serverRules.vegetable) }
} catch {
    Bad ("create package failed: " + $_.Exception.Message); exit 1
}

# 5. employee login + list packages
try {
    $emp = Login '13800000001' 'employee'
    $empHeaders = @{ Authorization = "Bearer $($emp.data.token)" }
    Ok ("employee login (id=" + $emp.data.user.id + ")")
} catch {
    Bad ("employee login failed: " + $_.Exception.Message); exit 1
}

try {
    $pkgs = Invoke-RestMethod -Method Get -Uri "$base/merchants/$merchantId/packages?mealType=$mealType" -TimeoutSec 5
    $found = $pkgs.data | Where-Object { $_.id -eq $packageId }
    if ($found) { Ok ("employee sees package " + $found.name) } else { Bad "employee did not see package"; exit 1 }
} catch {
    Bad ("list packages failed: " + $_.Exception.Message); exit 1
}

# 6. under-pick / over-pick
function PlaceOrder($selectedDishIds, $extras) {
    $body = @{
        merchantId = $merchantId
        merchantName = 'PkgTestMerchant'
        deliveryType = 'selfPickup'
        address = ''
        goodsAmount = 0; deliveryFee = 0; totalAmount = 0
        packageOrder = @{ packageId = $packageId; selectedDishIds = $selectedDishIds; extras = $extras }
    } | ConvertTo-Json -Compress -Depth 8
    return Invoke-WebRequest -Method Post -Uri "$base/orders" -Headers $empHeaders -ContentType 'application/json' -Body $body -TimeoutSec 5 -UseBasicParsing
}

# under-pick: 1 meat + 1 veg (rule requires 1 meat + 2 veg)
try {
    $r = PlaceOrder @($meat.data.id, $veg1.data.id) @()
    Bad ("under-pick should be blocked but got " + $r.StatusCode)
} catch {
    $c = $_.Exception.Response.StatusCode.value__
    if ($c -eq 400) { Ok "under-pick blocked (400)" }
    else { Bad ("under-pick returned " + $c) }
}

# over-pick: 2 meat + 2 veg (rule meat=1)
try {
    $r = PlaceOrder @($meat.data.id, $meat.data.id, $veg1.data.id, $veg2.data.id) @()
    Bad ("over-pick should be blocked but got " + $r.StatusCode)
} catch {
    $c = $_.Exception.Response.StatusCode.value__
    if ($c -eq 400) { Ok "over-pick blocked (400)" }
    else { Bad ("over-pick returned " + $c) }
}

# pick a staple (now disallowed inside packages -> DISH_CATEGORY_INVALID)
try {
    $r = PlaceOrder @($meat.data.id, $veg1.data.id, $stap.data.id) @()
    Bad ("staple-in-package should be blocked but got " + $r.StatusCode)
} catch {
    $c = $_.Exception.Response.StatusCode.value__
    if ($c -eq 400) { Ok "staple-in-package blocked (400)" }
    else { Bad ("staple-in-package returned " + $c) }
}

# 7. correct pick (1 meat + 2 veg) + 2 extras; intentionally pass wrong amounts.
#    Also: package was created with allowExtra=false, but extras must still
#    succeed because the gate has been removed.
$orderId = $null
if (-not $mealOpen) {
    Skip "package-order-creation skipped (all meal deadlines passed today)"
}
elseif ($true) {
try {
    $r = Invoke-RestMethod -Method Post -Uri "$base/orders" -Headers $empHeaders -ContentType 'application/json' -Body (@{
        merchantId = $merchantId
        merchantName = 'PkgTestMerchant'
        deliveryType = 'selfPickup'
        address = ''
        goodsAmount = 99999; deliveryFee = 99999; totalAmount = 99999
        packageOrder = @{
            packageId = $packageId
            selectedDishIds = @($meat.data.id, $veg1.data.id, $veg2.data.id)
            extras = @(@{ dishId = $extra1.data.id; quantity = 1 }, @{ dishId = $extra2.data.id; quantity = 1 })
        }
    } | ConvertTo-Json -Compress -Depth 8) -TimeoutSec 5

    $orderId = $r.data.id
    $final = $r.data.finalAmount
    $extraAmt = $r.data.extraAmount
    $basePrice = $r.data.packageBasePrice
    $total = $r.data.totalAmount

    Ok ("package order created (orderId=" + $orderId + ", extras allowed despite allowExtra=false)")
    Info ("  packageBasePrice=" + $basePrice + " extraAmount=" + $extraAmt + " finalAmount=" + $final + " totalAmount=" + $total)

    if ([math]::Abs($basePrice - 15) -lt 0.001) { Ok "server packageBasePrice = 15" } else { Bad ("packageBasePrice bad: " + $basePrice) }
    if ([math]::Abs($extraAmt - 9) -lt 0.001) { Ok "server extraAmount = 9 (6+3)" } else { Bad ("extraAmount bad: " + $extraAmt) }
    if ([math]::Abs($final - 24) -lt 0.001) { Ok "server finalAmount = 24 (15+9)" } else { Bad ("finalAmount bad: " + $final) }
    if ([math]::Abs($total - 24) -lt 0.001) { Ok "server totalAmount recomputed to 24 (front 99999 ignored)" } else { Bad ("totalAmount not recomputed: " + $total) }

    if ($r.data.packageId -eq $packageId) { Ok "order keeps packageId" } else { Bad "packageId missing/mismatch" }
    if ($r.data.selectedItems.Count -eq 3) { Ok ("order selectedItems = 3 (1 meat + 2 veg)") } else { Bad ("selectedItems abnormal got " + $r.data.selectedItems.Count) }
    if ($r.data.extraItems.Count -eq 2) { Ok "order extraItems = 2" } else { Bad ("extraItems abnormal got " + $r.data.extraItems.Count) }
} catch {
    $body = ReadErrBody $_
    Bad ("correct package order failed: " + $_.Exception.Message + " body=" + $body)
}
}

# 8. merchant order list should include this order with package + extras
if ($orderId) {
    try {
        $list = Invoke-RestMethod -Method Get -Uri "$base/merchant/orders?merchantId=$merchantId" -Headers $merHeaders -TimeoutSec 5
        $found = $list.data | Where-Object { $_.id -eq $orderId }
        if ($found) {
            Ok "merchant list includes order"
            if ($found.packageName) { Ok ("merchant sees packageName=" + $found.packageName) } else { Bad "merchant side packageName missing" }
            if ($found.extraItems -and $found.extraItems.Count -eq 2) { Ok "merchant sees 2 extras" } else { Bad "merchant side extras missing" }
            if ([math]::Abs($found.finalAmount - 24) -lt 0.001) { Ok "merchant finalAmount = 24" } else { Bad "merchant finalAmount mismatch" }
        } else { Bad "merchant order list missing the package order" }
    } catch {
        Bad ("merchant order list failed: " + $_.Exception.Message)
    }
}

# 9. lifecycle: upload payment screenshot -> merchant accept -> employee sees status -> merchant complete
if ($orderId) {
    # 9a. employee uploads payment screenshot (minimal 1x1 PNG)
    try {
        $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.png')
        # 67-byte minimal valid PNG (1x1 white pixel)
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
        if ($upObj -and $upObj.data.url) { Ok ("employee uploaded payment screenshot: " + $upObj.data.url) }
        else { Bad ("upload payment screenshot raw=" + $up) }
    } catch {
        Bad ("upload payment screenshot error: " + $_.Exception.Message)
    }

    # 9b. merchant moves order to accepted
    try {
        $r = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" -Headers $merHeaders -ContentType 'application/json' -Body (@{ status='accepted' } | ConvertTo-Json -Compress) -TimeoutSec 5
        if ($r.data.status -eq 'accepted') { Ok "merchant accepted order (status=accepted)" }
        else { Bad ("expected accepted got " + $r.data.status) }
    } catch {
        $body = ReadErrBody $_
        Bad ("merchant accept error: " + $_.Exception.Message + " body=" + $body)
    }

    # 9c. employee lists own orders -> should see this package order with full info
    try {
        $mine = Invoke-RestMethod -Method Get -Uri "$base/orders/my" -Headers $empHeaders -TimeoutSec 5
        $found = $mine.data | Where-Object { $_.id -eq $orderId }
        if ($found) {
            Ok ("employee sees own order, status=" + $found.status)
            if ($found.packageId -and $found.packageName) { Ok ("employee sees packageName=" + $found.packageName) } else { Bad "employee side packageName missing" }
            if ($found.selectedItems -and $found.selectedItems.Count -eq 3) { Ok ("employee sees selectedItems=3 (1 meat + 2 veg)") } else { Bad ("employee side selectedItems abnormal got " + $found.selectedItems.Count) }
            if ($found.extraItems -and $found.extraItems.Count -eq 2) { Ok "employee sees 2 extras" } else { Bad "employee side extras missing" }
            if ([math]::Abs($found.finalAmount - 24) -lt 0.001) { Ok "employee sees finalAmount=24" } else { Bad ("employee finalAmount=" + $found.finalAmount) }
        } else { Bad "employee /orders/my missing the package order" }
    } catch {
        Bad ("employee /orders/my error: " + $_.Exception.Message)
    }

    # 9d. merchant completes order
    try {
        $r = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" -Headers $merHeaders -ContentType 'application/json' -Body (@{ status='completed' } | ConvertTo-Json -Compress) -TimeoutSec 5
        if ($r.data.status -eq 'completed') { Ok "merchant completed order" }
        else { Bad ("expected completed got " + $r.data.status) }
    } catch {
        $body = ReadErrBody $_
        Bad ("merchant complete error: " + $_.Exception.Message + " body=" + $body)
    }
}

# 10. legacy plain dish order still works
if (-not $mealOpen) {
    Skip "legacy single-dish order skipped (all meal deadlines passed today)"
} else {
    try {
        $tmpDish = CreateDish 'LegacyDish' 12 '' 0
        # 老前端通常会传完整 dish 对象（check_ready 也这样传），这里同样写法
        $b = @{
            merchantId = $merchantId
            merchantName = 'PkgTestMerchant'
            deliveryType = 'selfPickup'; address=''
            goodsAmount = 12; deliveryFee = 0; totalAmount = 12
            items = @(@{ dish=$tmpDish.data; quantity=1 })
        } | ConvertTo-Json -Compress -Depth 10
        $r = Invoke-RestMethod -Method Post -Uri "$base/orders" -Headers $empHeaders -ContentType 'application/json' -Body $b -TimeoutSec 5
        if ($r.data.id) { Ok ("legacy single-dish order still works (orderId=" + $r.data.id + ")") } else { Bad "legacy single-dish order failed" }
    } catch {
        $body = ReadErrBody $_
        Bad ("legacy single-dish order error: " + $_.Exception.Message + " body=" + $body)
    }
}

Write-Host ""
Write-Host "------------------ summary ------------------" -ForegroundColor Cyan
Write-Host ("  PASS: " + $pass) -ForegroundColor Green
if ($fail -gt 0) {
    Write-Host ("  FAIL: " + $fail) -ForegroundColor Red
    exit 1
} else {
    Write-Host ("  FAIL: " + $fail) -ForegroundColor Green
    exit 0
}
