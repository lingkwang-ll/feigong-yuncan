# check_support_chat.ps1 — platform support chat E2E

$ErrorActionPreference = 'Continue'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }

function PostJsonUtf8($url, $headers, $obj) {
    $json = $obj | ConvertTo-Json -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $h = @{}
    if ($headers) { foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] } }
    return Invoke-RestMethod -Method Post -Uri $url -Headers $h -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 10
}

$pass = 0
$fail = 0
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }

Write-Host "=== feigong-yuncan check_support_chat ===" -ForegroundColor Cyan
Write-Host "API base: $base"

function Login($phone, $role) {
    $body = @{ phone=$phone; password='123456'; role=$role } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/auth/password-login" -ContentType 'application/json' -Body $body -TimeoutSec 10
}

function AdminLogin() {
    $phone = if ($env:PLATFORM_ADMIN_PHONE) { $env:PLATFORM_ADMIN_PHONE } else { '13700000000' }
    $body = @{ phone=$phone; password='123456' } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri "$base/admin/auth/password-login" -ContentType 'application/json' -Body $body -TimeoutSec 10
}

try {
    $emp = Login '13800000000' 'employee'
    $empHeaders = @{ Authorization = "Bearer $($emp.data.token)" }
    Ok "employee login"
} catch { Bad "employee login: $($_.Exception.Message)"; exit 1 }

try {
    $mer = Login '13900000000' 'merchant'
    $merHeaders = @{ Authorization = "Bearer $($mer.data.token)" }
    Ok "merchant login"
} catch { Bad "merchant login: $($_.Exception.Message)"; exit 1 }

try {
    $adm = AdminLogin
    $admHeaders = @{ Authorization = "Bearer $($adm.data.token)" }
    Ok "admin login"
} catch { Bad "admin login: $($_.Exception.Message)"; exit 1 }

$empMsg = [string]::Concat([char]0x6211, [char]0x8FD9, [char]0x8FB9, [char]0x4ED8, [char]0x6B3E, [char]0x622A, [char]0x56FE, [char]0x4E0A, [char]0x4F20, [char]0x4E0D, [char]0x4E86)
try {
    PostJsonUtf8 "$base/support/conversation/messages" $empHeaders @{ messageType='text'; content=$empMsg } | Out-Null
    Ok "employee sent support message"
} catch { Bad "employee send message: $($_.Exception.Message)" }

try {
    Start-Sleep -Seconds 1
    $list = Invoke-RestMethod -Uri "$base/admin/support/conversations" -Headers $admHeaders -TimeoutSec 10
    $conv = ($list.data | Where-Object { $_.userRole -eq 'employee' } | Select-Object -First 1)
    if (-not $conv) { throw 'no employee support conversation' }
    if ($conv.adminUnreadCount -lt 1) { throw "adminUnreadCount=$($conv.adminUnreadCount)" }
    $script:empConvId = $conv.id
    Ok "admin sees employee conversation unread=$($conv.adminUnreadCount)"
} catch { Bad "admin list unread: $($_.Exception.Message)" }

$adminReply = [string]::Concat([char]0x8BF7, [char]0x91CD, [char]0x65B0, [char]0x4E0A, [char]0x4F20, [char]0x622A, [char]0x56FE, [char]0x8BD5, [char]0x8BD5)
try {
    PostJsonUtf8 "$base/admin/support/conversations/$($script:empConvId)/messages" $admHeaders @{ messageType='text'; content=$adminReply } | Out-Null
    Ok "admin replied to employee"
} catch { Bad "admin reply: $($_.Exception.Message)" }

try {
    Start-Sleep -Seconds 1
    $msgs = Invoke-RestMethod -Uri "$base/support/conversation/messages" -Headers $empHeaders -TimeoutSec 10
    $found = $false
    foreach ($m in $msgs.data) {
        if ($m.senderType -eq 'admin' -and $m.content -eq $adminReply) { $found = $true; break }
    }
    if (-not $found) { throw 'admin reply not found' }
    Ok "employee received admin reply"
} catch { Bad "employee read reply: $($_.Exception.Message)" }

$merMsg = 'label printer size question'
try {
    PostJsonUtf8 "$base/support/conversation/messages" $merHeaders @{ messageType='text'; content=$merMsg } | Out-Null
    Ok "merchant sent support message"
} catch { Bad "merchant send: $($_.Exception.Message)" }

try {
    $list = Invoke-RestMethod -Uri "$base/admin/support/conversations" -Headers $admHeaders -TimeoutSec 10
    $mconv = ($list.data | Where-Object { $_.userRole -eq 'merchant' } | Select-Object -First 1)
    if (-not $mconv) { throw 'no merchant support conversation' }
    $script:merConvId = $mconv.id
    Ok "admin sees merchant conversation"
} catch { Bad "admin merchant conv: $($_.Exception.Message)" }

try {
    PostJsonUtf8 "$base/admin/support/conversations/$($script:merConvId)/messages" $admHeaders @{ messageType='text'; content='use 50mm in label settings' } | Out-Null
    Ok "admin replied to merchant"
} catch { Bad "admin reply merchant: $($_.Exception.Message)" }

try {
    Invoke-RestMethod -Uri "$base/support/conversation" -TimeoutSec 5 | Out-Null
    Bad "unauth support should 401"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401) { Ok "unauth GET /support/conversation -> 401" } else { Bad "unauth expected 401 got $code" }
}

try {
    Invoke-RestMethod -Uri "$base/admin/support/conversations" -Headers $empHeaders -TimeoutSec 5 | Out-Null
    Bad "employee admin list should fail"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401 -or $code -eq 403) { Ok "employee GET admin/support -> $code" } else { Bad "employee admin list expected 401/403 got $code" }
}

Write-Host "------------------ summary ------------------" -ForegroundColor Cyan
Write-Host "  PASS: $pass"
Write-Host "  FAIL: $fail"
if ($fail -gt 0) { exit 1 }
Write-Host "[OK] support chat checks passed" -ForegroundColor Green
