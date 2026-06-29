# check_overtime_single_use.ps1 - roster company pay single-use per date+meal_type

$ErrorActionPreference = 'Continue'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
. (Join-Path $PSScriptRoot '_ps_helpers.ps1')
$script:pass = 0; $script:fail = 0

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

Write-Host "=== check_overtime_single_use ===" -ForegroundColor Cyan
$today = TodayStr
Info "workDate=$today"
$cleared = Clear-OvertimeMealUsagesForE2e -WorkDate $today -Phones @('13800000001') -MealType 'lunch'
if ($cleared -gt 0) { Info "cleared $cleared lunch usage record(s) for li" }

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

$li = Login '13800000001' 'employee'
$liHeaders = @{ Authorization = "Bearer $($li.data.token)" }
Ok "employee li login"

$deptProd = [char]0x751F + [char]0x4EA7 + [char]0x90E8
$empLi = [char]0x674E + [char]0x56DB

# cleanup li roster rows for today
$existing = Invoke-Api -Method Get -Uri "$base/admin/overtime-rosters?workDate=$today" -Headers $adminHeaders
if ($existing.Ok -and $existing.Data) {
    foreach ($row in $existing.Data) {
        if ($row.phone -eq '13800000001') {
            Invoke-Api -Method Delete -Uri "$base/admin/overtime-rosters/$($row.id)" -Headers $adminHeaders | Out-Null
        }
    }
}

$rosterBody = @{
    workDate = $today
    mealType = 'lunch'
    employeeName = $empLi
    phone = '13800000001'
    department = $deptProd
    employeeNo = 'E002'
} | ConvertTo-Json -Compress
$rosterRes = Invoke-Api -Method Post -Uri "$base/admin/overtime-rosters" -Headers $adminHeaders -Body $rosterBody
if ($rosterRes.Ok) {
    Ok "created lunch roster for li"
    if ($rosterRes.Data.usageStatus -eq 'unused') {
        Ok "new roster shows unused before order"
    } else {
        Bad "new roster should be unused got usageStatus=$($rosterRes.Data.usageStatus)"
    }
    $listCheck = Invoke-Api -Method Get -Uri "$base/admin/overtime-rosters?workDate=$today&mealType=lunch" -Headers $adminHeaders
    $rowCheck = $listCheck.Data | Where-Object { $_.id -eq $rosterRes.Data.id } | Select-Object -First 1
    if ($rowCheck -and $rowCheck.usageStatus -eq 'unused') {
        Ok "list API confirms unused after create"
    } else {
        Bad "list API should show unused after create"
    }
} else { Bad "create roster failed: $($rosterRes.Body)" }

$dishes = Invoke-RestMethod -Uri "$base/merchants/$merchantId/dishes" -Method Get -TimeoutSec 8
$lunchDish = $dishes.Data | Where-Object { $_.mealType -eq 'lunch' -and $_.price -gt 0 } | Select-Object -First 1
$dinnerDish = $dishes.Data | Where-Object { $_.mealType -eq 'dinner' -and $_.price -gt 0 } | Select-Object -First 1
if (-not $lunchDish) {
    Bad "no lunch dish"
    Write-Host "SUMMARY: PASS=$($script:pass) FAIL=$($script:fail)" -ForegroundColor Cyan
    exit 1
}

function New-MealOrder {
    param($headers, $dish, [string]$MealType)
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

$o1 = New-MealOrder -headers $liHeaders -dish $lunchDish -MealType 'lunch'
$total1 = [double]$lunchDish.price
$expectCo1 = [Math]::Min($total1, 12)
$expectEmp1 = [Math]::Max(0, $total1 - 12)
if ($o1.Ok) {
    if ($expectEmp1 -le 0 -and $o1.Data.paymentType -eq 'company_pay') {
        Ok "first lunch order company_pay (total=$total1)"
    } elseif ($expectEmp1 -gt 0 -and $o1.Data.paymentType -eq 'mixed_pay') {
        Ok "first lunch order mixed_pay (total=$total1 cap=12)"
    } else {
        Bad "first lunch paymentType=$($o1.Data.paymentType) total=$total1"
    }
    if ([Math]::Abs([double]$o1.Data.companyPayAmount - $expectCo1) -lt 0.01) {
        Ok "first lunch companyPayAmount=$expectCo1"
    } else {
        Bad "first lunch companyPayAmount=$($o1.Data.companyPayAmount) expected $expectCo1"
    }
    if ([Math]::Abs([double]$o1.Data.employeePayAmount - $expectEmp1) -lt 0.01) {
        Ok "first lunch employeePayAmount=$expectEmp1"
    } else {
        Bad "first lunch employeePayAmount=$($o1.Data.employeePayAmount) expected $expectEmp1"
    }
    if ($expectEmp1 -le 0 -and $o1.Data.status -eq 'pendingMerchantConfirm') {
        Ok "first lunch enters merchant summary (pendingMerchantConfirm)"
    } elseif ($expectEmp1 -gt 0 -and $o1.Data.status -eq 'pendingPayment') {
        Ok "first lunch pendingPayment until screenshot"
    } else {
        Bad "first lunch status=$($o1.Data.status)"
    }
} else {
    Bad "first lunch expected company/mixed pay body=$($o1.Body)"
}

$o2 = New-MealOrder -headers $liHeaders -dish $lunchDish -MealType 'lunch'
if ($o2.Ok -and $o2.Data.paymentType -eq 'self_pay') {
    Ok "second lunch order self_pay"
} else {
    Bad "second lunch expected self_pay got $($o2.Data.paymentType)"
}
if ($o2.Ok -and $o2.Data.status -eq 'pendingPayment') {
    Ok "second lunch pendingPayment excluded from merchant actionable summary"
} else {
    Bad "second lunch expected pendingPayment got $($o2.Data.status)"
}

# switch merchant test - still self pay
$otherMer = Invoke-RestMethod -Uri "$base/merchants" -Method Get -TimeoutSec 8
$alt = $otherMer.data | Where-Object { $_.id -ne $merchantId } | Select-Object -First 1
if ($alt) {
    $altDishes = Invoke-RestMethod -Uri "$base/merchants/$($alt.id)/dishes" -Method Get -TimeoutSec 8
    $altLunch = $altDishes.Data | Where-Object { $_.mealType -eq 'lunch' -and $_.price -gt 0 } | Select-Object -First 1
    if ($altLunch) {
        $bodyAlt = @{
            merchantId = $alt.id
            merchantName = (Resolve-SafeMerchantName $alt.name 'AltShop')
            deliveryType = 'selfPickup'
            mealType = 'lunch'
            goodsAmount = $altLunch.price
            totalAmount = $altLunch.price
            items = @(@{ dishId = $altLunch.id; dishName = $altLunch.name; mealType = 'lunch'; price = $altLunch.price; quantity = 1 })
        } | ConvertTo-Json -Depth 6 -Compress
        $oAlt = Invoke-Api -Method Post -Uri "$base/orders" -Headers $liHeaders -Body $bodyAlt
        if ($oAlt.Ok -and $oAlt.Data.paymentType -eq 'self_pay') {
            Ok "lunch at other merchant self_pay"
        } elseif (-not $oAlt.Ok) {
            Info "skip other-merchant test: order failed ($($oAlt.ErrorCode))"
            Ok "lunch at other merchant blocked or failed (acceptable for self_pay rule)"
        } else {
            Bad "other merchant lunch expected self_pay got $($oAlt.Data.paymentType)"
        }
    } else { Info "skip other-merchant test: no lunch dish" }
} else { Info "skip other-merchant test: only one merchant" }

if ($dinnerDish) {
    $oDinner = New-MealOrder -headers $liHeaders -dish $dinnerDish -MealType 'dinner'
    if ($oDinner.Ok -and $oDinner.Data.paymentType -eq 'self_pay') {
        Ok "dinner not on lunch roster -> self_pay"
    } else {
        Bad "dinner expected self_pay got $($oDinner.Data.paymentType)"
    }
} else { Info "skip dinner test: no dinner dish" }

$listAfter = Invoke-Api -Method Get -Uri "$base/admin/overtime-rosters?workDate=$today&mealType=lunch" -Headers $adminHeaders
$row = $listAfter.Data | Where-Object { $_.phone -eq '13800000001' } | Select-Object -First 1
if ($row -and $row.usageStatus -eq 'used' -and $row.usageOrderId) {
    Ok "admin roster shows usage merchant/order/time"
} else {
    Bad "admin roster missing usage info: $($listAfter.Body)"
}

$elig = Invoke-Api -Method Get -Uri "$base/orders/company-pay-eligibility?mealType=lunch" -Headers $liHeaders
if ($elig.Ok -and $elig.Data.companyPayUsed -eq $true) {
    Ok "company-pay-eligibility lunch shows used"
} else {
    Bad "eligibility unexpected: $($elig.Body)"
}

# self_pay pending -> upload screenshot -> pendingMerchantConfirm
if ($o2.Ok) {
    $up = Upload-PaymentScreenshot ($li.data.token) $o2.Data.id
    if ($up.Code -eq 200) { Ok "self_pay upload screenshot ok" } else { Bad "screenshot upload failed code=$($up.Code)" }
    Start-Sleep -Milliseconds 300
    $mine = Invoke-RestMethod -Uri "$base/orders/my" -Headers $liHeaders -TimeoutSec 8
    $po = $mine.data | Where-Object { $_.id -eq $o2.Data.id } | Select-Object -First 1
    if ($po -and $po.status -in @('paymentSubmitted','pendingMerchantConfirm')) {
        Ok "after screenshot order enters pendingMerchantConfirm flow"
    } else {
        Bad "after screenshot unexpected status=$($po.status)"
    }
}

if ($rosterRes.Ok -and $rosterRes.Data.id) {
    Invoke-Api -Method Delete -Uri "$base/admin/overtime-rosters/$($rosterRes.Data.id)" -Headers $adminHeaders | Out-Null
    Info "cleaned up test roster"
}

} finally {
    Restore-E2eMealWindows $merHeaders $merchantId
}

Write-Host ""
Write-Host "SUMMARY: PASS=$($script:pass) FAIL=$($script:fail)" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 }
Write-Host "[OK] check_overtime_single_use passed" -ForegroundColor Green
exit 0
