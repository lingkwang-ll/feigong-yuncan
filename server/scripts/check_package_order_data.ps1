# check_package_order_data.ps1 - ASCII only (encoding safe)

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

Write-Host "=== feigong-yuncan check_package_order_data ===" -ForegroundColor Cyan
Write-Host "API base: $base"

function Login($phone, $role) {
    $body = @{ phone=$phone; password='123456'; role=$role } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType "application/json" -Body $body -TimeoutSec 10
}

$DEMO_PACKAGE_ID = "pkg_pkgdemo_2m2v"
$mealType = "lunch"

try {
    $emp = Login "13800000001" "employee"
    $empHeaders = @{ Authorization = "Bearer $($emp.data.token)" }
    Ok "employee login (id=$($emp.data.user.id))"
} catch {
    Bad "employee login failed: $($_.Exception.Message)"; exit 1
}

$merchantId = $null
$merchantName = $null
$data = $null

try {
    $merchants = Invoke-RestMethod -Method Get -Uri "$base/merchants" -Headers $empHeaders -TimeoutSec 10
    foreach ($m in $merchants.data) {
        try {
            $pod = Invoke-RestMethod -Method Get -Uri "$base/merchants/$($m.id)/package-order-data?mealType=$mealType" -Headers $empHeaders -TimeoutSec 10
            $hit = @($pod.data.packages) | Where-Object { $_.id -eq $DEMO_PACKAGE_ID } | Select-Object -First 1
            if ($hit) {
                $merchantId = $m.id
                $merchantName = $m.name
                $data = $pod.data
                break
            }
        } catch {
            continue
        }
    }
    if (-not $merchantId) {
        Bad "demo merchant with package $DEMO_PACKAGE_ID not found"
        exit 1
    }
    Ok "found demo merchant merchantId=$merchantId"
    Ok "package-order-data fetched"
} catch {
    Bad "merchant scan failed: $($_.Exception.Message)"; exit 1
}

$packages = @($data.packages)
$meat = @($data.dishes.meat)
$vegetable = @($data.dishes.vegetable)
$extra = @($data.dishes.extra)

Info "packages=$($packages.Count) meat=$($meat.Count) vegetable=$($vegetable.Count) extra=$($extra.Count)"

if ($packages.Count -ge 3) { Ok "packages count >= 3" } else { Bad "packages count < 3 ($($packages.Count))" }
if ($meat.Count -ge 3) { Ok "meat count >= 3" } else { Bad "meat count < 3 ($($meat.Count))" }
if ($vegetable.Count -ge 3) { Ok "vegetable count >= 3" } else { Bad "vegetable count < 3 ($($vegetable.Count))" }
if ($extra.Count -ge 3) { Ok "extra count >= 3" } else { Bad "extra count < 3 ($($extra.Count))" }

try {
    $rawDishes = Invoke-RestMethod -Method Get -Uri "$base/merchants/$merchantId/dishes?mealType=$mealType" -Headers $empHeaders -TimeoutSec 10
    $demoDishIds = @()
    foreach ($m in $meat) { $demoDishIds += $m.id }
    foreach ($v in $vegetable) { $demoDishIds += $v.id }
    foreach ($e in $extra) { $demoDishIds += $e.id }
    foreach ($id in $demoDishIds) {
        $d = $rawDishes.data | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $d) { Bad "dish $id missing in dishes API"; continue }
        if ($d.category -eq "meat") { Ok "meat dish $id category=meat" }
        elseif ($d.category -eq "vegetable") { Ok "vegetable dish $id category=vegetable" }
        elseif ($d.category -eq "extra" -and $d.extraPrice -gt 0) { Ok "extra dish $id category=extra extraPrice=$($d.extraPrice)" }
        else { Bad "dish $id invalid category/extraPrice" }
    }
} catch {
    Bad "dishes API check failed: $($_.Exception.Message)"
}

$pkg2m2v = $packages | Where-Object { $_.id -eq $DEMO_PACKAGE_ID } | Select-Object -First 1
if (-not $pkg2m2v) {
    Bad "package $DEMO_PACKAGE_ID not found"
} else {
    Ok "found package id=$($pkg2m2v.id) basePrice=$($pkg2m2v.basePrice)"
}

if ($pkg2m2v) {
    $meatIds = @($meat | Select-Object -First 2 | ForEach-Object { $_.id })
    $vegIds = @($vegetable | Select-Object -First 2 | ForEach-Object { $_.id })
    $extraId = $extra[0].id
    $extraPrice = [double]$extra[0].extraPrice
    $basePrice = [double]$pkg2m2v.basePrice
    $expectedFinal = $basePrice + $extraPrice

    try {
        $underBody = @{
            merchantId = $merchantId
            merchantName = $merchantName
            deliveryType = "selfPickup"
            items = @()
            goodsAmount = 0
            deliveryFee = 0
            totalAmount = 0
            packageOrder = @{
                packageId = $pkg2m2v.id
                selectedDishIds = @($meatIds[0])
                extras = @()
            }
        } | ConvertTo-Json -Depth 6 -Compress
        Invoke-RestMethod -Method Post -Uri "$base/orders" -Headers $empHeaders -ContentType "application/json" -Body $underBody -TimeoutSec 10 | Out-Null
        Bad "under-pick should be 400"
    } catch {
        Ok "under-pick blocked (400)"
    }

    try {
        $overIds = $meatIds + $meatIds + $vegIds + $vegIds
        $overBody = @{
            merchantId = $merchantId
            merchantName = $merchantName
            deliveryType = "selfPickup"
            items = @()
            goodsAmount = 0
            deliveryFee = 0
            totalAmount = 0
            packageOrder = @{
                packageId = $pkg2m2v.id
                selectedDishIds = $overIds
                extras = @()
            }
        } | ConvertTo-Json -Depth 6 -Compress
        Invoke-RestMethod -Method Post -Uri "$base/orders" -Headers $empHeaders -ContentType "application/json" -Body $overBody -TimeoutSec 10 | Out-Null
        Bad "over-pick should be 400"
    } catch {
        Ok "over-pick blocked (400)"
    }

    try {
        $selected = @($meatIds + $vegIds)
        $orderBody = @{
            merchantId = $merchantId
            merchantName = $merchantName
            deliveryType = "selfPickup"
            items = @()
            goodsAmount = 0
            deliveryFee = 0
            totalAmount = 99999
            packageOrder = @{
                packageId = $pkg2m2v.id
                selectedDishIds = $selected
                extras = @(@{ dishId = $extraId; quantity = 1 })
            }
        } | ConvertTo-Json -Depth 6 -Compress
        $order = Invoke-RestMethod -Method Post -Uri "$base/orders" -Headers $empHeaders -ContentType "application/json" -Body $orderBody -TimeoutSec 10
        $final = [double]$order.data.finalAmount
        if ($final -eq $expectedFinal) {
            Ok "order finalAmount=$final (expected $expectedFinal)"
        } else {
            Bad "order finalAmount=$final expected $expectedFinal"
        }
    } catch {
        Bad "correct order failed: $($_.Exception.Message)"
        $body = ReadErrBody $_
        if ($body) { Info $body }
    }
}

Write-Host ""
Write-Host "------------------ summary ------------------"
Write-Host "  PASS: $pass"
Write-Host "  FAIL: $fail"
if ($fail -eq 0) {
    Write-Host "[OK] check_package_order_data passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] check_package_order_data failed" -ForegroundColor Red
    exit 1
}
