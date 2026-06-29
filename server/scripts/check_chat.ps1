# =============================================================
# check_chat.ps1
#
# Order conversation (chat) end-to-end check.
#
#   1. employee login
#   2. merchant login
#   3. create / reuse an order belonging to the logged-in merchant
#   4. employee fetches /api/conversations/order/:orderId (create or reuse)
#   5. employee sends a text message
#   6. employee sends an emoji message
#   7. merchant lists /api/merchant/conversations and finds the order's conv
#   8. merchant fetches messages
#   9. merchant replies with a text message
#  10. merchant marks the conversation read (employee unread for merchant -> 0)
#  11. employee fetches messages again and marks read
#  12. unauthenticated request -> 401 (text send + image upload)
#  13. cross-merchant access (other merchant) -> 403
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

function DetailErr($err) {
    $msg = $err.Exception.Message
    $code = ''
    try { $code = $err.Exception.Response.StatusCode.value__ } catch {}
    $body = ReadErrBody $err
    return "msg=$msg status=$code body=$body"
}

# Send JSON as raw UTF-8 bytes so Chinese / emoji survive PowerShell encoding.
function PostJsonUtf8($url, $headers, $obj) {
    $json = $obj | ConvertTo-Json -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $h = @{}
    if ($headers) { foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] } }
    return Invoke-RestMethod -Method Post -Uri $url -Headers $h -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 5
}

$pass = 0
$fail = 0
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Info($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

Write-Host "=== feigong-yuncan check_chat ===" -ForegroundColor Cyan
Write-Host "API base: $base"

function Login($phone, $role) {
    $body = @{ phone=$phone; password='123456'; role=$role } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body $body -TimeoutSec 5
}

# -------------------------------------------------------------
# 1. employee login
# -------------------------------------------------------------
try {
    $emp = Login '13800000000' 'employee'
    $empId = $emp.data.user.id
    $empToken = $emp.data.token
    $empHeaders = @{ Authorization = "Bearer $empToken" }
    Ok "employee login (id=$empId)"
} catch {
    Bad ("employee login failed: " + $_.Exception.Message); exit 1
}

# -------------------------------------------------------------
# 2. merchant login (this token is bound to one specific merchant)
# -------------------------------------------------------------
try {
    $mer = Login '13900000000' 'merchant'
    $merId = $mer.data.user.id
    $merToken = $mer.data.token
    $merHeaders = @{ Authorization = "Bearer $merToken" }
    $prof = Invoke-RestMethod -Method Get -Uri "$base/merchant/profile" -Headers $merHeaders -TimeoutSec 5
    $merchantId = $prof.data.id
    Ok "merchant login (userId=$merId, merchantId=$merchantId)"
} catch {
    Bad ("merchant login failed: " + $_.Exception.Message); exit 1
}

# -------------------------------------------------------------
# 3. create or reuse an order owned by the logged-in merchant.
#    Use a tiny legacy single-dish order so we do not depend on packages.
# -------------------------------------------------------------
function Test-MealOpen($cfg, $mealType) {
    $dl = $cfg.data.mealDeadlines.$mealType
    if (-not $dl) { return $true }
    $parts = $dl -split ':'
    if ($parts.Count -lt 2) { return $true }
    $dMin = [int]$parts[0] * 60 + [int]$parts[1]
    $now = Get-Date
    $cur = $now.Hour * 60 + $now.Minute
    return $cur -le $dMin
}

$mealType = 'lunch'
try {
    $cfg = Invoke-RestMethod -Method Get -Uri "$base/config/runtime" -TimeoutSec 5
    foreach ($mt in @('lunch','dinner','overtime','breakfast')) {
        if (Test-MealOpen $cfg $mt) { $mealType = $mt; break }
    }
    Info ("using mealType=" + $mealType)
} catch {
    Info "config/runtime not available, fallback to lunch"
}

# create one small dish under the logged-in merchant
function CreateDishLite($name, $price) {
    $body = @{
        merchantId = $merchantId
        name = $name
        price = $price
        mealType = $mealType
        mealTypes = @($mealType)
        category = ''
        isAvailable = $true
    } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/dishes" -Headers $merHeaders -ContentType 'application/json' -Body $body -TimeoutSec 5
}

$orderId = $null
try {
    $dish = $null
    try {
        $dish = CreateDishLite 'ChatTestDish' 12
        Info ("dish created id=" + $dish.data.id)
    } catch {
        Info ("create dish failed (ignored): " + (DetailErr $_))
    }

    $created = $false
    if ($dish -and $dish.data.id) {
        try {
            $body = @{
                merchantId = $merchantId
                merchantName = 'ChatTestMerchant'
                deliveryType = 'selfPickup'; address=''; phone='13800000000'
                goodsAmount = 12; deliveryFee = 0; totalAmount = 12
                items = @(@{ dish=$dish.data; quantity=1 })
            } | ConvertTo-Json -Compress -Depth 10
            $r = Invoke-RestMethod -Method Post -Uri "$base/orders" -Headers $empHeaders -ContentType 'application/json' -Body $body -TimeoutSec 5
            $orderId = $r.data.id
            if ($orderId) {
                Ok ("order created (orderId=$orderId)")
                $created = $true
                if ($r.data.status -eq 'pendingPayment') {
                    Ok "order status=pendingPayment (chat should work before payment)"
                }
            }
        } catch {
            $detail = DetailErr $_
            if ($detail -match 'MEAL_DEADLINE_PASSED|deadline|deadlinePassed|400') {
                Info ("create order skipped (will reuse existing): " + $detail)
            } else {
                Info ("create order failed: " + $detail)
            }
        }
    }

    if (-not $created) {
        # Fallback: find an existing order belonging to the logged-in employee
        # whose merchant is the logged-in merchant. This keeps the script
        # runnable at any time of day (after meal deadlines have passed).
        try {
            $mine = Invoke-RestMethod -Method Get -Uri "$base/orders/my" -Headers $empHeaders -TimeoutSec 5
            $hit = $mine.data | Where-Object { $_.merchantId -eq $merchantId } | Select-Object -First 1
            if ($hit) {
                $orderId = $hit.id
                Ok "reuse existing order (orderId=$orderId, status=$($hit.status))"
            } else {
                Bad "no existing order to reuse and meal deadline has passed"
                exit 1
            }
        } catch {
            Bad ("reuse-existing-order lookup failed: " + (DetailErr $_)); exit 1
        }
    }
} catch {
    Bad ("create-or-reuse order failed: " + (DetailErr $_)); exit 1
}

# -------------------------------------------------------------
# 4. employee gets/creates conversation for the order
# -------------------------------------------------------------
$convId = $null
try {
    $r = Invoke-RestMethod -Method Get -Uri "$base/conversations/order/$orderId" -Headers $empHeaders -TimeoutSec 5
    $convId = $r.data.id
    if ($convId) { Ok ("conversation resolved (id=$convId, orderNo=" + $r.data.orderNo + ")") }
    else { Bad "conversation resolve returned no id"; exit 1 }
} catch {
    Bad ("get conversation failed: " + (ReadErrBody $_)); exit 1
}

# -------------------------------------------------------------
# 4b. system messages must not count as merchant unread
# -------------------------------------------------------------
try {
    $r = Invoke-RestMethod -Method Get -Uri "$base/merchant/conversations" -Headers $merHeaders -TimeoutSec 5
    $hit = $r.data | Where-Object { $_.orderId -eq $orderId }
    if ($hit -and $hit.merchantUnreadCount -eq 0) {
        Ok "system messages do not inflate merchant unread"
    } elseif ($hit) {
        Bad ("merchant unread should be 0 before employee chat, got " + $hit.merchantUnreadCount)
    } else {
        Bad "merchant list missing conversation for unread baseline check"
    }
} catch {
    Bad ("merchant unread baseline check failed: " + (ReadErrBody $_))
}

# -------------------------------------------------------------
# 5. employee sends a text message
# -------------------------------------------------------------
$empText = '你好，少放辣'
try {
    $r = PostJsonUtf8 "$base/conversations/$convId/messages" $empHeaders @{ messageType='text'; content=$empText }
    if ($r.data.messageType -eq 'text' -and $r.data.content -eq $empText) {
        Ok "employee text message sent"
    } else {
        Bad ("employee text shape mismatch: type=" + $r.data.messageType + " content=" + $r.data.content)
    }
} catch {
    Bad ("employee text send failed: " + (DetailErr $_))
}

# -------------------------------------------------------------
# 6. employee sends an emoji message
# -------------------------------------------------------------
$empEmoji = '😀'
try {
    $r = PostJsonUtf8 "$base/conversations/$convId/messages" $empHeaders @{ messageType='emoji'; content=$empEmoji }
    if ($r.data.messageType -eq 'emoji' -and $r.data.content -eq $empEmoji) {
        Ok "employee emoji message sent"
    } else {
        Bad ("employee emoji shape mismatch: type=" + $r.data.messageType + " content=" + $r.data.content)
    }
} catch {
    Bad ("employee emoji send failed: " + (DetailErr $_))
}

# -------------------------------------------------------------
# 7. merchant lists conversations and finds this one
# -------------------------------------------------------------
try {
    $r = Invoke-RestMethod -Method Get -Uri "$base/merchant/conversations" -Headers $merHeaders -TimeoutSec 5
    $hit = $r.data | Where-Object { $_.orderId -eq $orderId }
    if ($hit) {
        Ok ("merchant sees conversation (unread=" + $hit.merchantUnreadCount + ")")
        if ($hit.merchantUnreadCount -ge 2) { Ok "merchant unread reflects 2 employee messages" }
        else { Bad ("merchant unread expected >= 2, got " + $hit.merchantUnreadCount) }
    } else {
        Bad "merchant list missing the conversation"
    }
} catch {
    Bad ("merchant list conversations failed: " + (ReadErrBody $_))
}

# -------------------------------------------------------------
# 8. merchant fetches messages
# -------------------------------------------------------------
try {
    $r = Invoke-RestMethod -Method Get -Uri "$base/merchant/conversations/$convId/messages" -Headers $merHeaders -TimeoutSec 5
    $types = @($r.data | ForEach-Object { $_.messageType })
    if ($types -contains 'text' -and $types -contains 'emoji' -and $types -contains 'system') {
        Ok ("merchant sees text/emoji/system messages (count=" + $r.data.Count + ")")
    } else {
        Bad ("merchant message types mismatch: " + ($types -join ','))
    }
} catch {
    Bad ("merchant list messages failed: " + (ReadErrBody $_))
}

# -------------------------------------------------------------
# 9. merchant replies with a text
# -------------------------------------------------------------
try {
    $r = PostJsonUtf8 "$base/merchant/conversations/$convId/messages" $merHeaders @{ messageType='text'; content='收到，按要求处理' }
    if ($r.data.senderType -eq 'merchant') { Ok "merchant replied" }
    else { Bad ("merchant reply senderType=" + $r.data.senderType) }
} catch {
    Bad ("merchant reply failed: " + (DetailErr $_))
}

# -------------------------------------------------------------
# 10. merchant marks read -> merchant unread should be 0
# -------------------------------------------------------------
try {
    $r = Invoke-RestMethod -Method Post -Uri "$base/merchant/conversations/$convId/read" -Headers $merHeaders -TimeoutSec 5
    if ($r.data.merchantUnreadCount -eq 0) { Ok "merchant markRead -> merchantUnreadCount=0" }
    else { Bad ("merchant unread not zero after mark: " + $r.data.merchantUnreadCount) }
} catch {
    Bad ("merchant markRead failed: " + (ReadErrBody $_))
}

# -------------------------------------------------------------
# 11. employee fetches messages and marks read
# -------------------------------------------------------------
try {
    $r = Invoke-RestMethod -Method Get -Uri "$base/conversations/$convId/messages" -Headers $empHeaders -TimeoutSec 5
    if ($r.data.Count -ge 4) { Ok ("employee sees >=4 messages (text+emoji+system+merchant reply)") }
    else { Bad ("employee message count too low: " + $r.data.Count) }

    $r2 = Invoke-RestMethod -Method Post -Uri "$base/conversations/$convId/read" -Headers $empHeaders -TimeoutSec 5
    if ($r2.data.employeeUnreadCount -eq 0) { Ok "employee markRead -> employeeUnreadCount=0" }
    else { Bad ("employee unread not zero after mark: " + $r2.data.employeeUnreadCount) }
} catch {
    Bad ("employee list/markRead failed: " + (ReadErrBody $_))
}

# -------------------------------------------------------------
# 12. unauthenticated -> 401
# -------------------------------------------------------------
function Expect401($label, $scriptblock) {
    try {
        $r = & $scriptblock
        Bad ("$label expected 401, got " + $r.StatusCode)
    } catch {
        $c = 0
        try { $c = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($c -eq 401) { Ok "$label blocked (401)" }
        else { Bad ("$label expected 401, got $c") }
    }
}

Expect401 "unauth text send" {
    $body = @{ messageType='text'; content='ghost' } | ConvertTo-Json -Compress
    Invoke-WebRequest -Method Post -Uri "$base/conversations/$convId/messages" -ContentType 'application/json' -Body $body -TimeoutSec 5 -UseBasicParsing
}

Expect401 "unauth list messages" {
    Invoke-WebRequest -Method Get -Uri "$base/conversations/$convId/messages" -TimeoutSec 5 -UseBasicParsing
}

# 12b. unauth image upload -> 401 (no Authorization header at all)
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
    $out = curl.exe -s -o NUL -w "%{http_code}" -X POST `
        -F ("file=@" + $tmp + ";type=image/png") `
        "$base/conversations/$convId/images"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if ($out -eq '401') { Ok "unauth image upload blocked (401)" }
    else { Bad ("unauth image upload expected 401, got " + $out) }
} catch {
    Bad ("unauth image upload error: " + $_.Exception.Message)
}

# -------------------------------------------------------------
# 13. cross-merchant -> 403
#     Find another merchant id and try to use its routes with merchantId
#     query param via the logged-in merchant token. The merchantList
#     endpoint silently scopes by token so we hit messages directly:
#     read another merchant's conversation if any. Fallback to ensure
#     "wrong role" 403 by hitting merchant endpoint as employee.
# -------------------------------------------------------------
try {
    $body = @{ messageType='text'; content='hack' } | ConvertTo-Json -Compress
    $r = Invoke-WebRequest -Method Post -Uri "$base/merchant/conversations/$convId/messages" -Headers $empHeaders -ContentType 'application/json' -Body $body -TimeoutSec 5 -UseBasicParsing
    Bad ("employee calling merchant send expected 403, got " + $r.StatusCode)
} catch {
    $c = 0
    try { $c = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($c -eq 403) { Ok "employee calling merchant send blocked (403)" }
    else { Bad ("employee calling merchant send expected 403, got $c") }
}

try {
    $r = Invoke-WebRequest -Method Get -Uri "$base/conversations/$convId/messages" -Headers $merHeaders -TimeoutSec 5 -UseBasicParsing
    Bad ("merchant calling employee list expected 403, got " + $r.StatusCode)
} catch {
    $c = 0
    try { $c = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($c -eq 403) { Ok "merchant calling employee list blocked (403)" }
    else { Bad ("merchant calling employee list expected 403, got $c") }
}

# -------------------------------------------------------------
# summary
# -------------------------------------------------------------
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
