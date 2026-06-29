#requires -Version 5.1
# =============================================================
# security_check.ps1
#
# Verify Must-Fix 1 (App-side auth) + Must-Fix 2 (admin listEmployees FORBIDDEN)
#
# Covers:
#   A. Unauthenticated access to mutating App routes must return 401
#   B. Merchant A cannot operate on Merchant B (403/401)
#   C. Employee cannot hit merchant-only routes
#   D. Logged-in normal flows still work for admin/merchant/employee
#   E. Merchant token on /api/admin/employees returns 401/403 (not 500)
#
# Usage:
#   cd server
#   powershell -ExecutionPolicy Bypass -File .\scripts\security_check.ps1
# =============================================================

$ErrorActionPreference = 'Stop'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }

$pass = 0
$fail = 0
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Info($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

function Invoke-Status {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [string]$ContentType = 'application/json'
    )
    try {
        $p = @{
            Method  = $Method
            Uri     = $Uri
            Headers = $Headers
            TimeoutSec = 8
        }
        if ($Body) {
            $p.Body = $Body
            $p.ContentType = $ContentType
        }
        $resp = Invoke-WebRequest @p -UseBasicParsing
        return @{ Code = [int]$resp.StatusCode; Body = $resp.Content }
    } catch {
        $r = $_.Exception.Response
        if ($r) {
            $code = [int]$r.StatusCode
            $body = $null
            try {
                $stream = $r.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $body = $reader.ReadToEnd()
            } catch { $body = $_.ErrorDetails.Message }
            return @{ Code = $code; Body = $body }
        }
        return @{ Code = 0; Body = $_.Exception.Message }
    }
}

function Expect-Status {
    param(
        [string]$Label,
        [int[]]$Expected,
        [hashtable]$Result
    )
    if ($Expected -contains $Result.Code) {
        Ok ("{0} -> {1}" -f $Label, $Result.Code)
    } else {
        Bad ("{0} -> {1} (expected {2}); body={3}" -f $Label, $Result.Code, ($Expected -join '|'), $Result.Body)
    }
}

Write-Host '================ security_check ================' -ForegroundColor Cyan
Write-Host "API base: $base"

# --- prereq: login admin / employee / merchantA, then create merchantB ---
$admin = Invoke-RestMethod -Method Post -Uri "$base/admin/auth/password-login" -ContentType 'application/json' -Body '{"phone":"13700000000","password":"123456"}'
$adminHeaders = @{ Authorization = "Bearer $($admin.data.token)" }
Ok "admin login (role=$($admin.data.user.role))"

$emp = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body '{"phone":"13800000000","password":"123456","role":"employee"}'
$empHeaders = @{ Authorization = "Bearer $($emp.data.token)" }
Ok "employee login (id=$($emp.data.user.id), role=$($emp.data.user.role))"

$merA = Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body '{"phone":"13900000000","password":"123456","role":"merchant"}'
$merAHeaders = @{ Authorization = "Bearer $($merA.data.token)" }
$merAId = $merA.data.user.id
Ok "merchant A login (id=$merAId)"

# resolve merchant A's merchant_id and pick another merchant as B
$allMerchants = (Invoke-RestMethod -Uri "$base/admin/merchants" -Headers $adminHeaders).data
$merARow = $allMerchants | Where-Object { $_.userId -eq $merAId } | Select-Object -First 1
if (-not $merARow) {
    # fallback: take the first approved merchant linked to user
    $merARow = $allMerchants | Where-Object { $_.userId } | Select-Object -First 1
}
$merAMerchantId = $merARow.id
$merBRow = $allMerchants | Where-Object { $_.id -ne $merAMerchantId } | Select-Object -First 1
if (-not $merBRow) { Bad "need at least 2 merchants; only $($allMerchants.Count) found"; exit 1 }
$merBMerchantId = $merBRow.id
Info "merchant A (mine)  -> $($merARow.merchantName) [$merAMerchantId]"
Info "merchant B (other) -> $($merBRow.merchantName) [$merBMerchantId]"

# pick one dish belonging to merchant B for cross-tenant tests
$dishesB = (Invoke-RestMethod -Uri "$base/admin/dishes?merchantId=$merBMerchantId" -Headers $adminHeaders).data
if (-not $dishesB -or $dishesB.Count -eq 0) {
    Info "merchant B has no dishes; creating one via admin for cross-tenant test"
    $dishCreate = @{ merchantId = $merBMerchantId; name = 'security_check_temp'; price = 1; mealType = 'lunch'; description = 'tmp' } | ConvertTo-Json -Compress
    $newDish = (Invoke-RestMethod -Method Post -Uri "$base/admin/dishes" -Headers $adminHeaders -ContentType 'application/json' -Body $dishCreate).data
    $dishBId = $newDish.id
} else {
    $dishBId = $dishesB[0].id
}
Info "dish belonging to merchant B -> $dishBId"

# pick one of merchant A's own dishes for normal-flow tests
$dishesA = (Invoke-RestMethod -Uri "$base/admin/dishes?merchantId=$merAMerchantId" -Headers $adminHeaders).data
if (-not $dishesA -or $dishesA.Count -eq 0) {
    Info "merchant A has no dishes; creating one for normal-flow tests"
    $dishCreate = @{ merchantId = $merAMerchantId; name = 'security_check_self'; price = 1; mealType = 'lunch'; description = 'tmp' } | ConvertTo-Json -Compress
    $newDish = (Invoke-RestMethod -Method Post -Uri "$base/admin/dishes" -Headers $adminHeaders -ContentType 'application/json' -Body $dishCreate).data
    $dishAId = $newDish.id
} else {
    $dishAId = $dishesA[0].id
}
Info "dish belonging to merchant A -> $dishAId"

Write-Host ''
Write-Host '--- A. Unauthenticated requests must return 401 ---' -ForegroundColor Cyan

Expect-Status 'unauth PUT /orders/:id/status' @(401) (Invoke-Status -Method 'PUT' -Uri "$base/orders/x/status" -Body '{"status":"completed"}')
Expect-Status 'unauth PUT /merchant/is-open'  @(401) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/is-open"  -Body "{`"merchantId`":`"$merAMerchantId`",`"isOpen`":true}")
Expect-Status 'unauth PUT /merchant/profile'  @(401) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/profile"  -Body "{`"merchantId`":`"$merAMerchantId`",`"name`":`"hacker`"}")
Expect-Status 'unauth PUT /merchant/delivery-settings' @(401) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/delivery-settings" -Body "{`"merchantId`":`"$merAMerchantId`",`"deliveryFee`":99}")
Expect-Status 'unauth PUT /merchant/business-hours' @(401) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/business-hours" -Body "{`"merchantId`":`"$merAMerchantId`",`"supportedMealTypes`":[]}")
Expect-Status 'unauth PUT /merchant/payment-qr-code' @(401) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/payment-qr-code" -Body "{`"merchantId`":`"$merAMerchantId`",`"paymentQrCode`":`"hack`"}")
Expect-Status 'unauth POST /dishes' @(401) (Invoke-Status -Method 'POST' -Uri "$base/dishes" -Body "{`"merchantId`":`"$merAMerchantId`",`"name`":`"x`",`"price`":1,`"mealType`":`"lunch`"}")
Expect-Status 'unauth PUT /dishes/:id' @(401) (Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishAId" -Body '{"name":"hacked"}')
Expect-Status 'unauth PUT /dishes/:id/available' @(401) (Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishAId/available" -Body '{"isAvailable":false}')
Expect-Status 'unauth PUT /dishes/:id/sold-out'  @(401) (Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishAId/sold-out"  -Body '{"isSoldOut":true}')
Expect-Status 'unauth DELETE /dishes/:id' @(401) (Invoke-Status -Method 'DELETE' -Uri "$base/dishes/$dishAId")
Expect-Status 'unauth GET /merchant/orders' @(401) (Invoke-Status -Method 'GET' -Uri "$base/merchant/orders?merchantId=$merAMerchantId")
Expect-Status 'unauth POST /uploads/payment-screenshot' @(401) (Invoke-Status -Method 'POST' -Uri "$base/uploads/payment-screenshot" -Body '' -ContentType 'multipart/form-data')
Expect-Status 'unauth POST /uploads/dish-image'        @(401) (Invoke-Status -Method 'POST' -Uri "$base/uploads/dish-image"        -Body '' -ContentType 'multipart/form-data')
Expect-Status 'unauth POST /uploads/merchant-qr-code'  @(401) (Invoke-Status -Method 'POST' -Uri "$base/uploads/merchant-qr-code"  -Body '' -ContentType 'multipart/form-data')
Expect-Status 'unauth POST /uploads/merchant-license'  @(401) (Invoke-Status -Method 'POST' -Uri "$base/uploads/merchant-license"  -Body '' -ContentType 'multipart/form-data')
Expect-Status 'unauth POST /uploads/store-photo'       @(401) (Invoke-Status -Method 'POST' -Uri "$base/uploads/store-photo"       -Body '' -ContentType 'multipart/form-data')
Expect-Status 'unauth POST /uploads/merchant-logo'     @(401) (Invoke-Status -Method 'POST' -Uri "$base/uploads/merchant-logo"     -Body '' -ContentType 'multipart/form-data')
Expect-Status 'unauth POST /orders'         @(401) (Invoke-Status -Method 'POST' -Uri "$base/orders" -Body '{"merchantId":"x","merchantName":"x","items":[],"goodsAmount":0,"totalAmount":0,"deliveryType":"selfPickup"}')
Expect-Status 'unauth GET /orders/my'       @(401) (Invoke-Status -Method 'GET'  -Uri "$base/orders/my")

Write-Host ''
Write-Host '--- B. Cross-merchant access must return 401/403 ---' -ForegroundColor Cyan

Expect-Status 'merA edits merB dish'        @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishBId" -Headers $merAHeaders -Body '{"name":"hijack"}')
Expect-Status 'merA toggles merB available' @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishBId/available" -Headers $merAHeaders -Body '{"isAvailable":false}')
Expect-Status 'merA marks merB sold-out'    @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishBId/sold-out"  -Headers $merAHeaders -Body '{"isSoldOut":true}')
Expect-Status 'merA deletes merB dish'      @(401,403) (Invoke-Status -Method 'DELETE' -Uri "$base/dishes/$dishBId" -Headers $merAHeaders)
Expect-Status 'merA creates dish on merB'   @(401,403) (Invoke-Status -Method 'POST' -Uri "$base/dishes" -Headers $merAHeaders -Body "{`"merchantId`":`"$merBMerchantId`",`"name`":`"hijack`",`"price`":1,`"mealType`":`"lunch`"}")
Expect-Status 'merA edits merB profile'     @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/profile" -Headers $merAHeaders -Body "{`"merchantId`":`"$merBMerchantId`",`"name`":`"hijack`"}")
Expect-Status 'merA toggles merB is-open'   @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/is-open" -Headers $merAHeaders -Body "{`"merchantId`":`"$merBMerchantId`",`"isOpen`":false}")
Expect-Status 'merA changes merB payment-qr' @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/payment-qr-code" -Headers $merAHeaders -Body "{`"merchantId`":`"$merBMerchantId`",`"paymentQrCode`":`"x`"}")
Expect-Status 'merA lists merB orders'      @(401,403) (Invoke-Status -Method 'GET' -Uri "$base/merchant/orders?merchantId=$merBMerchantId" -Headers $merAHeaders)

Write-Host ''
Write-Host '--- C. Employee cannot use merchant-only routes ---' -ForegroundColor Cyan

Expect-Status 'employee GET /merchant/orders'   @(401,403) (Invoke-Status -Method 'GET' -Uri "$base/merchant/orders?merchantId=$merAMerchantId" -Headers $empHeaders)
Expect-Status 'employee PUT /merchant/is-open'  @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/merchant/is-open" -Headers $empHeaders -Body "{`"merchantId`":`"$merAMerchantId`",`"isOpen`":true}")
Expect-Status 'employee POST /dishes'           @(401,403) (Invoke-Status -Method 'POST' -Uri "$base/dishes" -Headers $empHeaders -Body "{`"merchantId`":`"$merAMerchantId`",`"name`":`"x`",`"price`":1,`"mealType`":`"lunch`"}")
Expect-Status 'employee PUT /dishes/:id'        @(401,403) (Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishAId" -Headers $empHeaders -Body '{"name":"x"}')
Expect-Status 'employee POST /uploads/dish-image' @(401,403) (Invoke-Status -Method 'POST' -Uri "$base/uploads/dish-image" -Headers $empHeaders -Body '' -ContentType 'multipart/form-data')

Write-Host ''
Write-Host '--- D. Normal happy-path access must still work ---' -ForegroundColor Cyan

# D.1 merchant toggles own is-open
$resp = Invoke-Status -Method 'PUT' -Uri "$base/merchant/is-open" -Headers $merAHeaders -Body "{`"merchantId`":`"$merAMerchantId`",`"isOpen`":true}"
Expect-Status 'merA toggles own is-open=true' @(200) $resp

# D.2 merchant lists own orders
$resp = Invoke-Status -Method 'GET' -Uri "$base/merchant/orders" -Headers $merAHeaders
Expect-Status 'merA lists own orders'        @(200) $resp

# D.3 merchant lists own orders with own merchantId
$resp = Invoke-Status -Method 'GET' -Uri "$base/merchant/orders?merchantId=$merAMerchantId" -Headers $merAHeaders
Expect-Status 'merA lists own orders (with id)' @(200) $resp

# D.4 merchant updates own dish
$resp = Invoke-Status -Method 'PUT' -Uri "$base/dishes/$dishAId/sold-out" -Headers $merAHeaders -Body '{"isSoldOut":false}'
Expect-Status 'merA sets own dish sold-out=false' @(200) $resp

# D.5 employee can fetch own orders + create order (small flow)
$resp = Invoke-Status -Method 'GET' -Uri "$base/orders/my" -Headers $empHeaders
Expect-Status 'employee GET /orders/my' @(200) $resp

# D.6 admin lists employees normally
$resp = Invoke-Status -Method 'GET' -Uri "$base/admin/employees" -Headers $adminHeaders
Expect-Status 'admin GET /admin/employees' @(200) $resp

# D.7 admin lists merchants normally
$resp = Invoke-Status -Method 'GET' -Uri "$base/admin/merchants" -Headers $adminHeaders
Expect-Status 'admin GET /admin/merchants' @(200) $resp

Write-Host ''
Write-Host '--- E. Re-test of known bug: merchant on /admin/employees ---' -ForegroundColor Cyan

$resp = Invoke-Status -Method 'GET' -Uri "$base/admin/employees" -Headers $merAHeaders
Expect-Status 'merchant GET /admin/employees (must NOT be 500)' @(401,403) $resp

Write-Host ''
Write-Host '------------------ summary ------------------' -ForegroundColor Cyan
Write-Host ("  PASS: {0}" -f $pass) -ForegroundColor Green
$col = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("  FAIL: {0}" -f $fail) -ForegroundColor $col

if ($fail -eq 0) {
    Write-Host "`n[OK] all security checks passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[NO] please review the failures above" -ForegroundColor Red
    exit 1
}
