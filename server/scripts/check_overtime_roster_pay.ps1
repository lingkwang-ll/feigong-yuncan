# check_overtime_roster_pay.ps1 - roster date+meal_type company pay E2E

$ErrorActionPreference = 'Continue'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
. (Join-Path $PSScriptRoot '_ps_helpers.ps1')
$script:pass = 0; $script:fail = 0
$script:rosterIds = @()

function Ok($msg) { Write-Host "[PASS] $msg" -ForegroundColor Green; $script:pass++ }
function Bad($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:fail++ }
function Info($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

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
    param([string]$Method, [string]$Uri, [hashtable]$Headers = @{}, [string]$Body = $null)
    try {
        $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; TimeoutSec = 15 }
        if ($Body) { $p.Body = $Body; $p.ContentType = 'application/json' }
        $resp = Invoke-WebRequest @p -UseBasicParsing
        $json = $null
        try { $json = $resp.Content | ConvertFrom-Json } catch {}
        return @{ Ok = $true; Code = [int]$resp.StatusCode; Data = $json.data; Raw = $json; Body = $resp.Content }
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

function Login($phone, $role) {
    $body = @{ phone = $phone; password = '123456'; role = $role } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body $body -TimeoutSec 8
}

function AdminLogin() {
    return Invoke-RestMethod -Method Post -Uri "$base/admin/auth/password-login" -ContentType 'application/json' -Body '{"phone":"13700000000","password":"123456"}' -TimeoutSec 8
}

function TodayStr {
    $d = Get-Date
    return '{0:0000}-{1:00}-{2:00}' -f $d.Year, $d.Month, $d.Day
}

function Get-CurrentMinute {
    $n = Get-Date
    return $n.Hour * 60 + $n.Minute
}

function Test-MealDeadlineOpen($cfg, [string]$mealType) {
    if (-not $cfg -or -not $cfg.data -or -not $cfg.data.mealDeadlines) { return $true }
    $dl = $cfg.data.mealDeadlines.$mealType
    if (-not $dl) { return $true }
    $parts = ($dl -as [string]) -split ':'
    if ($parts.Count -lt 2) { return $true }
    $dMin = [int]$parts[0] * 60 + [int]$parts[1]
    return (Get-CurrentMinute) -le $dMin
}

function Set-E2eMealWindowsOpen($Headers, [string]$MerchantId, $ProfileData) {
    $script:hoursBackup = @{
        supportedMealTypes = @($ProfileData.supportedMealTypes)
        mealOpeningHours = $ProfileData.mealOpeningHours
    }
    $extended = @{
        breakfast = @{ enabled = $true; start = '06:00'; end = '23:59' }
        lunch = @{ enabled = $true; start = '06:00'; end = '23:59' }
        dinner = @{ enabled = $true; start = '06:00'; end = '23:59' }
        overtime = @{ enabled = $true; start = '06:00'; end = '23:59' }
    }
    $body = @{
        merchantId = $MerchantId
        supportedMealTypes = @('breakfast', 'lunch', 'dinner', 'overtime')
        mealOpeningHours = $extended
    } | ConvertTo-Json -Depth 6 -Compress
    $res = Invoke-Api -Method Put -Uri "$base/merchant/business-hours" -Headers $Headers -Body $body
    if ($res.Ok) { Info 'extended E2E meal windows to 23:59 for all meal types' }
    else { Bad "extend meal windows failed: $($res.Body)" }
}

function Restore-E2eMealWindows($Headers, [string]$MerchantId) {
    if (-not $script:hoursBackup) { return }
    $body = @{
        merchantId = $MerchantId
        supportedMealTypes = $script:hoursBackup.supportedMealTypes
        mealOpeningHours = $script:hoursBackup.mealOpeningHours
    } | ConvertTo-Json -Depth 8 -Compress
    Invoke-Api -Method Put -Uri "$base/merchant/business-hours" -Headers $Headers -Body $body | Out-Null
    Info 'restored merchant meal windows'
}

function Pick-OpenMealDish($Dishes, $Cfg, [string[]]$PreferOrder) {
    foreach ($mt in $PreferOrder) {
        if (-not (Test-MealDeadlineOpen $Cfg $mt)) { continue }
        $d = $Dishes | Where-Object { $_.mealType -eq $mt -and $_.isAvailable -and $_.price -gt 0 } | Select-Object -First 1
        if ($d) { return @{ MealType = $mt; Dish = $d } }
    }
    return $null
}

function Upload-PaymentScreenshot($token, $orderId) {
    $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.png')
    $bytes = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,0xDE,0x00,0x00,0x00,0x0C,0x49,0x44,0x41,0x54,0x08,0x99,0x63,0xF8,0xFF,0xFF,0x3F,0x00,0x05,0xFE,0x02,0xFE,0xA9,0x5C,0x8A,0xFF,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82)
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    $raw = curl.exe -s -w "`nHTTP_CODE:%{http_code}" -X POST -H ("Authorization: Bearer " + $token) -F ("file=@" + $tmp + ";type=image/png") -F ("orderId=" + $orderId) -F "manualPayChannel=wechat" "$base/uploads/payment-screenshot"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $codeLine = ($raw -split "`n") | Where-Object { $_ -match '^HTTP_CODE:' } | Select-Object -Last 1
    $httpCode = 0
    if ($codeLine -match 'HTTP_CODE:(\d+)') { $httpCode = [int]$Matches[1] }
    return @{ Code = $httpCode }
}

Write-Host "=== check_overtime_roster_pay ===" -ForegroundColor Cyan
$today = TodayStr
Info "workDate=$today"
$cleared = Clear-OvertimeMealUsagesForE2e -WorkDate $today
if ($cleared -gt 0) { Info "cleared $cleared overtime usage record(s) for E2E employees" }

$admin = AdminLogin
$adminHeaders = @{ Authorization = "Bearer $($admin.data.token)" }
Ok "admin login"

$mer = Login '13900000000' 'merchant'
$merHeaders = @{ Authorization = "Bearer $($mer.data.token)" }
$prof = Invoke-RestMethod -Uri "$base/merchant/profile" -Headers $merHeaders -TimeoutSec 8
$merchantId = $prof.data.id
$merchantName = Resolve-SafeMerchantName $prof.data.name 'E2ETestShop'
Ok "merchant login ($merchantId)"

$runtimeCfg = Invoke-RestMethod -Uri "$base/config/runtime" -TimeoutSec 8
$needExtend = -not (Test-MealDeadlineOpen $runtimeCfg 'lunch') -or -not (Test-MealDeadlineOpen $runtimeCfg 'dinner')
if ($needExtend) { Info 'some meal deadlines passed; temporarily extending merchant meal windows' }
Set-E2eMealWindowsOpen $merHeaders $merchantId $prof.data

try {
$zhang = Login '13800000000' 'employee'
$zhangHeaders = @{ Authorization = "Bearer $($zhang.data.token)" }
Ok "employee zhang login"

$wang = Login '13800000002' 'employee'
$wangHeaders = @{ Authorization = "Bearer $($wang.data.token)" }
Ok "employee wang login (mixed pay)"

$deptAdmin = [char]0x884C + [char]0x653F + [char]0x90E8
$empZhang = [char]0x5F20 + [char]0x4E09
$empWang = [char]0x738B + [char]0x4E94
$deptProd = [char]0x751F + [char]0x4EA7 + [char]0x90E8

$li = Login '13800000001' 'employee'
$liHeaders = @{ Authorization = "Bearer $($li.data.token)" }
Ok "employee li login"

# cleanup existing roster for same phone/date
$existing = Invoke-Api -Method Get -Uri "$base/admin/overtime-rosters?workDate=$today" -Headers $adminHeaders
if ($existing.Ok -and $existing.Data) {
    foreach ($row in $existing.Data) {
        if ($row.phone -eq '13800000000' -or $row.phone -eq '13800000002' -or $row.phone -eq '13800000001') {
            Invoke-Api -Method Delete -Uri "$base/admin/overtime-rosters/$($row.id)" -Headers $adminHeaders | Out-Null
        }
    }
}

$rosterBody = @{
    workDate = $today
    mealType = 'lunch'
    employeeName = $empZhang
    phone = '13800000000'
    department = $deptAdmin
    employeeNo = 'E001'
} | ConvertTo-Json -Compress
$rosterRes = Invoke-Api -Method Post -Uri "$base/admin/overtime-rosters" -Headers $adminHeaders -Body $rosterBody
if ($rosterRes.Ok -and $rosterRes.Data.id) {
    $script:rosterIds += $rosterRes.Data.id
    Ok "created lunch roster entry for zhang"
    if ($rosterRes.Data.usageStatus -eq 'unused') {
        Ok "new zhang roster unused before order"
    } else {
        Bad "new zhang roster should be unused got $($rosterRes.Data.usageStatus)"
    }
} else {
    Bad "create roster failed: $($rosterRes.Body)"
}

$wangRosterBody = @{
    workDate = $today
    mealType = 'lunch'
    employeeName = $empWang
    phone = '13800000002'
    department = $deptProd
    employeeNo = 'E003'
} | ConvertTo-Json -Compress
$wangRosterRes = Invoke-Api -Method Post -Uri "$base/admin/overtime-rosters" -Headers $adminHeaders -Body $wangRosterBody
if ($wangRosterRes.Ok -and $wangRosterRes.Data.id) {
    $script:rosterIds += $wangRosterRes.Data.id
    Ok "created lunch roster entry for wang (mixed pay)"
} else {
    Bad "create wang roster failed: $($wangRosterRes.Body)"
}

$dishes = Invoke-RestMethod -Uri "$base/merchants/$merchantId/dishes" -Method Get -TimeoutSec 8
$lunchDish = $dishes.Data | Where-Object { $_.mealType -eq 'lunch' -and $_.price -gt 0 } | Select-Object -First 1
$dinnerDish = $dishes.Data | Where-Object { $_.mealType -eq 'dinner' -and $_.price -gt 0 } | Select-Object -First 1
$extraDish = $dishes.Data | Where-Object { $_.category -eq 'extra' -and $_.extraPrice -gt 0 } | Select-Object -First 1

function New-MealDishOrder($headers, $dish, [string]$MealType) {
    $body = @{
        merchantId = $merchantId
        merchantName = $merchantName
        deliveryType = 'selfPickup'
        mealType = $MealType
        goodsAmount = $dish.price
        totalAmount = $dish.price
        items = @(@{
            dishId = $dish.id
            dishName = $dish.name
            mealType = $MealType
            price = $dish.price
            quantity = 1
        })
    } | ConvertTo-Json -Depth 6 -Compress
    return Invoke-Api -Method Post -Uri "$base/orders" -Headers $headers -Body $body
}

if ($lunchDish) {
    $o1 = New-MealDishOrder $zhangHeaders $lunchDish 'lunch'
    if ($o1.Ok) {
        $d = $o1.Data
        $total1 = [double]$d.totalAmount
        $expectCo = [Math]::Min($total1, 12)
        $expectEmp = [Math]::Max(0, $total1 - 12)
        if ($expectEmp -le 0 -and $d.paymentType -eq 'company_pay') {
            Ok "on-roster lunch paymentType=company_pay (total=$total1)"
        } elseif ($expectEmp -gt 0 -and $d.paymentType -eq 'mixed_pay') {
            Ok "on-roster lunch paymentType=mixed_pay (total=$total1 cap=12)"
        } else {
            Bad "expected company/mixed got $($d.paymentType)"
        }
        if ([Math]::Abs([double]$d.companyPayAmount - $expectCo) -lt 0.01) {
            Ok "companyPayAmount=$expectCo"
        } else { Bad "companyPayAmount=$($d.companyPayAmount) expected $expectCo" }
        if ([Math]::Abs([double]$d.employeePayAmount - $expectEmp) -lt 0.01) {
            Ok "employeePayAmount=$expectEmp"
        } else { Bad "employeePayAmount=$($d.employeePayAmount) expected $expectEmp" }
        if ($expectEmp -le 0 -and $d.status -eq 'pendingMerchantConfirm') {
            Ok "status=pendingMerchantConfirm"
            $acc1 = Invoke-Api -Method Put -Uri "$base/orders/$($d.id)/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress)
            if ($acc1.Ok) { Ok "merchant accepted without screenshot" } else { Bad "merchant accept failed" }
        } elseif ($expectEmp -gt 0 -and $d.status -eq 'pendingPayment') {
            Ok "status=pendingPayment until screenshot"
        } else {
            Bad "status=$($d.status)"
        }
    } else { Bad "on-roster lunch order create failed $($o1.Body)" }
} else { Bad "no lunch dish found" }

$meat = $dishes.Data | Where-Object { $_.category -eq 'meat' } | Select-Object -First 1
$veg = $dishes.Data | Where-Object { $_.category -eq 'vegetable' } | Select-Object -First 2

if ($meat -and $veg -and $extraDish) {
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $pkgBody = @{
        name = "OT-E2E-$suffix"
        description = 'e2e'
        basePrice = 10
        mealTypes = @('lunch')
        rules = @{ meat = 1; vegetable = 2 }
        allowExtra = $true
    } | ConvertTo-Json -Depth 5 -Compress
    $pkg = Invoke-Api -Method Post -Uri "$base/packages" -Headers $merHeaders -Body $pkgBody
    if ($pkg.Ok) {
        $pkgId = $pkg.Data.id
        $selected = @($meat.id) + ($veg | ForEach-Object { $_.id })
        $pkgOrderBody = @{
            merchantId = $merchantId
            merchantName = $merchantName
            deliveryType = 'selfPickup'
            mealType = 'lunch'
            packageOrder = @{
                packageId = $pkgId
                selectedDishIds = $selected
                extras = @(@{ dishId = $extraDish.id; quantity = 1 })
            }
        } | ConvertTo-Json -Depth 8 -Compress
        $o2 = Invoke-Api -Method Post -Uri "$base/orders" -Headers $wangHeaders -Body $pkgOrderBody
        if ($o2.Ok) {
            $d2 = $o2.Data
            $total2 = [double]$d2.totalAmount
            if ($d2.paymentType -eq 'mixed_pay') { Ok "on-roster with extra paymentType=mixed_pay" } else { Bad "expected mixed_pay got $($d2.paymentType)" }
            if ([double]$d2.companyPayAmount -eq 12 -and [double]$d2.employeePayAmount -eq ($total2 - 12)) {
                Ok "split company=$($d2.companyPayAmount) employee=$($d2.employeePayAmount) (cap=12 total=$total2)"
            } else { Bad "invalid amount split company=$($d2.companyPayAmount) employee=$($d2.employeePayAmount) total=$total2" }
            $accBlock = Invoke-Api -Method Put -Uri "$base/orders/$($d2.id)/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress)
            if (-not $accBlock.Ok -and $accBlock.ErrorCode -eq 'PAYMENT_SCREENSHOT_REQUIRED') {
                Ok "merchant blocked before screenshot"
            } elseif ($accBlock.Ok) {
                Bad "merchant accepted before screenshot (requirePaymentScreenshot may be off)"
            } else {
                Ok "merchant blocked before screenshot (code=$($accBlock.ErrorCode))"
            }
            $up = Upload-PaymentScreenshot ($wang.data.token) $d2.id
            if ($up.Code -eq 200) { Ok "screenshot uploaded" } else { Bad "upload failed code=$($up.Code)" }
            $acc2 = Invoke-Api -Method Put -Uri "$base/orders/$($d2.id)/status" -Headers $merHeaders -Body (@{ status = 'accepted' } | ConvertTo-Json -Compress)
            if ($acc2.Ok) { Ok "merchant accepted after screenshot" } else { Bad "accept after screenshot failed" }
        } else { Bad "mixed package order failed $($o2.Body)" }
    } else { Bad "create test package failed" }
} else { Bad "skip mixed pay: missing dishes" }

if ($lunchDish) {
    $o3 = New-MealDishOrder $liHeaders $lunchDish 'lunch'
    if ($o3.Ok) {
        $d3 = $o3.Data
        if ($d3.paymentType -eq 'self_pay') { Ok "off-roster lunch paymentType=self_pay" } else { Bad "expected self_pay got $($d3.paymentType)" }
        if ([math]::Abs([double]$d3.companyPayAmount) -lt 0.001) { Ok "companyPayAmount=0 off-roster" } else { Bad "companyPayAmount=$($d3.companyPayAmount)" }
        if ([double]$d3.employeePayAmount -gt 0) { Ok "employeePayAmount=full" } else { Bad "employeePayAmount=0" }
        if ($d3.status -eq 'pendingPayment') { Ok "status=pendingPayment" } else { Bad "status=$($d3.status)" }
    } else { Bad "off-roster lunch order failed" }
}

if ($dinnerDish) {
    $o4 = New-MealDishOrder $zhangHeaders $dinnerDish 'dinner'
    if ($o4.Ok -and $o4.Data.paymentType -eq 'self_pay') {
        Ok "dinner not on lunch roster -> self_pay (paymentType=$($o4.Data.paymentType))"
    } else {
        Bad "dinner control expected self_pay: $($o4.Body)"
    }
} else { Info 'skip dinner control: no dinner dish' }

$labels = Invoke-Api -Method Get -Uri "$base/admin/labels?date=$today&mealType=lunch&merchantId=$merchantId" -Headers $adminHeaders
if ($labels.Ok -and $labels.Data.Count -gt 0) {
    $g = $labels.Data[0]
    if ($g.labelCode -notlike 'LC-*') { Ok "label code numeric ($($g.labelCode))" } else { Bad "label still has LC prefix" }
    if ($g.employeeName) { Ok "label has employee name" } else { Bad "label missing name" }
    if ($g.department) { Ok "label has department" } else { Bad "label missing department" }
    $hasDetail = ($g.meats.Count + $g.vegetables.Count + $g.packages.Count + $g.extras.Count + $g.items.Count) -gt 0
    if ($hasDetail) { Ok "label has dish details" } else { Bad "label missing dish details" }
} else { Bad "labels empty or failed" }

} finally {
    foreach ($rid in $script:rosterIds) {
        Invoke-Api -Method Delete -Uri "$base/admin/overtime-rosters/$rid" -Headers $adminHeaders | Out-Null
    }
    if ($script:rosterIds.Count -gt 0) { Ok "cleaned up test roster records" }
    Restore-E2eMealWindows $merHeaders $merchantId
}

Write-Host "`nSUMMARY: PASS=$($script:pass) FAIL=$($script:fail)" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 }
Write-Host "[OK] check_overtime_roster_pay passed" -ForegroundColor Green
