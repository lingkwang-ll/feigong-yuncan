# check_online_payment_settlement.ps1 — 在线支付 + 平台担保结算 E2E
$ErrorActionPreference = 'Continue'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
. (Join-Path $PSScriptRoot '_ps_helpers.ps1')
$pass = 0; $fail = 0
function Ok($m) { Write-Host "[PASS] $m" -ForegroundColor Green; $script:pass++ }
function Bad($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; $script:fail++ }

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
        [string]$JsonPayload = $null,
        [string]$ContentType = 'application/json'
    )
    try {
        $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; TimeoutSec = 15 }
        if ($JsonPayload) { $p.Body = $JsonPayload; $p.ContentType = $ContentType }
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

function Get-Prop($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    return $obj.PSObject.Properties[$name].Value
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
    $res = Invoke-Api -Method Put -Uri "$base/merchant/business-hours" -Headers $Headers -JsonPayload $body
    if (-not $res.Ok) { Bad "extend meal windows failed: $($res.Body)"; exit 1 }
    Write-Host "       extended E2E meal windows to 23:59 for all meal types" -ForegroundColor DarkGray
}

function Restore-E2eMealWindows($Headers, [string]$MerchantId) {
    if (-not $script:hoursBackup) { return }
    $body = @{
        merchantId = $MerchantId
        supportedMealTypes = $script:hoursBackup.supportedMealTypes
        mealOpeningHours = $script:hoursBackup.mealOpeningHours
    } | ConvertTo-Json -Depth 8 -Compress
    Invoke-Api -Method Put -Uri "$base/merchant/business-hours" -Headers $Headers -JsonPayload $body | Out-Null
    Write-Host '       restored merchant meal windows' -ForegroundColor DarkGray
}

function Pick-OpenMealDish($Dishes, $Cfg, [string[]]$PreferOrder) {
    foreach ($mt in $PreferOrder) {
        if (-not (Test-MealDeadlineOpen $Cfg $mt)) { continue }
        $d = $Dishes | Where-Object { $_.mealType -eq $mt -and $_.isAvailable -and $_.price -gt 0 } | Select-Object -First 1
        if ($d) { return @{ MealType = $mt; Dish = $d } }
    }
    foreach ($mt in $PreferOrder) {
        $d = $Dishes | Where-Object { $_.mealType -eq $mt -and $_.isAvailable -and $_.price -gt 0 } | Select-Object -First 1
        if ($d) { return @{ MealType = $mt; Dish = $d } }
    }
    return $null
}

function New-PaymentJson([string]$oid) {
    return (@{ oid = $oid; channel = 'wechat_pay' } | ConvertTo-Json -Compress) -replace '"oid"', '"orderId"'
}

Write-Host '=== check_online_payment_settlement ==='

$admin = Invoke-RestMethod -Method Post -Uri "$base/admin/auth/password-login" -ContentType 'application/json' `
  -Body '{"phone":"13700000000","password":"123456"}'
$adminH = @{ Authorization = "Bearer $($admin.data.token)" }

$mer = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' `
  -Body (@{ phone = '13900000000'; password = '123456'; role = 'merchant' } | ConvertTo-Json -Compress)
$merH = @{ Authorization = "Bearer $($mer.data.token)" }
$prof = Invoke-RestMethod -Uri "$base/merchant/profile" -Headers $merH
$merchantId = $prof.data.id
$merchantName = Resolve-SafeMerchantName $prof.data.name 'E2ETestShop'

$runtimeCfg = Invoke-RestMethod -Uri "$base/config/runtime" -TimeoutSec 8
$needExtend = -not (Test-MealDeadlineOpen $runtimeCfg 'lunch') -and -not (Test-MealDeadlineOpen $runtimeCfg 'dinner') -and -not (Test-MealDeadlineOpen $runtimeCfg 'breakfast')
if ($needExtend) {
    Write-Host '       meal deadlines passed; temporarily extending merchant meal windows' -ForegroundColor DarkGray
}
Set-E2eMealWindowsOpen $merH $merchantId $prof.data

$emp = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' `
  -Body (@{ phone = '13800000001'; password = '123456'; role = 'employee' } | ConvertTo-Json -Compress)
$empH = @{ Authorization = "Bearer $($emp.data.token)" }

$dishes = Invoke-RestMethod -Uri "$base/merchants/$merchantId/dishes" -Headers $merH
$picked = Pick-OpenMealDish $dishes.data $runtimeCfg @('lunch', 'dinner', 'breakfast', 'overtime')
if (-not $picked) { Bad 'no available dish for open meal type'; Restore-E2eMealWindows $merH $merchantId; exit 1 }
$dish = $picked.Dish
$testMealType = $picked.MealType
Write-Host "       using mealType=$testMealType dish=$($dish.name)" -ForegroundColor DarkGray

$createJson = @{
    merchantId = $merchantId
    merchantName = $merchantName
    deliveryType = 'selfPickup'
    mealType = $testMealType
    address = 'e2e'
    goodsAmount = [double]$dish.price
    deliveryFee = 0
    totalAmount = [double]$dish.price
    items = @(@{ dish = $dish; quantity = 1 })
} | ConvertTo-Json -Depth 10 -Compress

try {
$created = Invoke-Api -Method Post -Uri "$base/orders" -Headers $empH -JsonPayload $createJson
if (-not $created.Ok) { Bad "create order failed: $($created.Body)"; exit 1 }
$spOid = ([string](Get-Prop $created.Data 'id')).Trim()
if (-not $spOid) { Bad 'order id missing'; exit 1 }
if ((Get-Prop $created.Data 'employeePayAmount') -gt 0) {
    Ok "self_pay order employeePayAmount=$(Get-Prop $created.Data 'employeePayAmount')"
} else { Bad 'expected employeePayAmount > 0' }

# 2. payment create
$payCreateRaw = Invoke-RestMethod -Method Post -Uri "$base/payments/create" -Headers $empH -ContentType 'application/json' -Body (New-PaymentJson $spOid)
$paymentId = Get-Prop $payCreateRaw.data 'paymentId'
Ok "payment_transaction created ($paymentId)"

# 3. mock-paid
$mock1 = Invoke-Api -Method Post -Uri "$base/payments/mock-paid" -Headers $empH `
  -JsonPayload (@{ paymentId = $paymentId } | ConvertTo-Json -Compress)
if (-not $mock1.Ok) { Bad "mock-paid failed: $($mock1.Body)"; exit 1 }
$afterPay = Invoke-RestMethod -Uri "$base/merchant/orders?merchantId=$merchantId" -Headers $merH
$paidOrder = $afterPay.data | Where-Object { (Get-Prop $_ 'id') -eq $spOid }
if ($paidOrder.status -eq 'pendingMerchantConfirm') { Ok 'order pendingMerchantConfirm after mock pay' }
else { Bad "status=$($paidOrder.status)" }
if ($paidOrder.settlementStatus -eq 'paid_to_platform') { Ok 'settlementStatus=paid_to_platform' }
else { Bad "settlementStatus=$($paidOrder.settlementStatus)" }

# 4. 重复 mock 幂等
$dup = Invoke-Api -Method Post -Uri "$base/payments/mock-paid" -Headers $empH `
  -JsonPayload (@{ paymentId = $paymentId } | ConvertTo-Json -Compress)
if ($dup.Ok) { Ok 'duplicate mock-paid idempotent' } else { Bad 'duplicate mock-paid failed' }

# 5. 金额不一致拒绝
$created2 = Invoke-Api -Method Post -Uri "$base/orders" -Headers $empH -JsonPayload $createJson
$oid2 = [string](Get-Prop $created2.Data 'id')
$pay2 = Invoke-Api -Method Post -Uri "$base/payments/create" -Headers $empH -JsonPayload (New-PaymentJson $oid2)
$badAmt = Invoke-Api -Method Post -Uri "$base/payments/mock-paid" -Headers $empH `
  -JsonPayload (@{ paymentId = (Get-Prop $pay2.Data 'paymentId'); amount = 0.01 } | ConvertTo-Json -Compress)
if (-not $badAmt.Ok) { Ok 'wrong amount rejected' } else { Bad 'wrong amount should fail' }

# 6. 接单 + 完成
$acc = Invoke-Api -Method Put -Uri "$base/orders/$spOid/status" -Headers $merH `
  -JsonPayload (@{ status = 'accepted' } | ConvertTo-Json -Compress)
if (-not $acc.Ok) { Bad "accept failed: $($acc.Body)" }
$doneReq = Invoke-Api -Method Put -Uri "$base/orders/$spOid/status" -Headers $merH `
  -JsonPayload (@{ status = 'completed' } | ConvertTo-Json -Compress)
if (-not $doneReq.Ok) { Bad "complete failed: $($doneReq.Body)" }
$done = (Invoke-RestMethod -Uri "$base/merchant/orders?merchantId=$merchantId" -Headers $merH).data | Where-Object { (Get-Prop $_ 'id') -eq $spOid }
if ($done.settlementStatus -eq 'completed_pending_settlement') { Ok 'completed_pending_settlement' }
else { Bad "after complete settlementStatus=$($done.settlementStatus)" }
if ($done.settlementEligibleAt) { Ok 'settlementEligibleAt set (+7d)' }
else { Bad 'settlementEligibleAt missing' }

# 7. 强制到期 + eligible + settle
Invoke-Api -Method Post -Uri "$base/admin/settlements/force-eligible" -Headers $adminH `
  -JsonPayload ((ConvertTo-Json -InputObject @{ targetOrderId = $spOid } -Compress) -replace 'targetOrderId', 'orderId') | Out-Null
$settlements = Invoke-RestMethod -Uri "$base/admin/settlements?merchantId=$merchantId" -Headers $adminH
$st = $settlements.data | Where-Object { (Get-Prop $_ 'order_id') -eq $spOid } | Select-Object -First 1
if ($st.status -eq 'eligible') { Ok 'settlement eligible' } else { Bad "settlement status=$($st.status)" }
$settle = Invoke-Api -Method Post -Uri "$base/admin/settlements/settle" -Headers $adminH `
  -JsonPayload (@{ settlementId = (Get-Prop $st 'id') } | ConvertTo-Json -Compress)
if (-not $settle.Ok) { Bad "settle failed: $($settle.Body)" }
$final = (Invoke-RestMethod -Uri "$base/merchant/orders?merchantId=$merchantId" -Headers $merH).data | Where-Object { (Get-Prop $_ 'id') -eq $spOid }
if ($final.settlementStatus -eq 'settled') { Ok 'order settled' } else { Bad "final settlementStatus=$($final.settlementStatus)" }

# 8. 企业代付不创建员工支付单
$zhang = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' `
  -Body (@{ phone = '13800000000'; password = '123456'; role = 'employee' } | ConvertTo-Json -Compress)
$zhangH = @{ Authorization = "Bearer $($zhang.data.token)" }
$co = Invoke-Api -Method Post -Uri "$base/orders" -Headers $zhangH -JsonPayload $createJson
if ((Get-Prop $co.Data 'employeePayAmount') -eq 0) { Ok 'company_pay employeePayAmount=0' } else { Bad 'company should be 0' }
$coReject = Invoke-Api -Method Post -Uri "$base/payments/create" -Headers $zhangH `
  -JsonPayload (New-PaymentJson (Get-Prop $co.Data 'id'))
if (-not $coReject.Ok) { Ok 'company_pay rejects payment create' } else { Bad 'company_pay should not create payment' }

} finally {
    Restore-E2eMealWindows $merH $merchantId
}

Write-Host "`nSUMMARY: PASS=$pass FAIL=$fail"
if ($fail -gt 0) { exit 1 }
Write-Host '[OK] check_online_payment_settlement passed'
