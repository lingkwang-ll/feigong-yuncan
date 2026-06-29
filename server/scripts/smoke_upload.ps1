$ErrorActionPreference = 'Stop'
$base = 'http://localhost:3000/api'

$tmp = Join-Path $env:TEMP ('feigong_test_' + [Guid]::NewGuid().ToString() + '.png')
[IO.File]::WriteAllBytes($tmp, [byte[]](137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,2,0,0,0,144,119,83,222,0,0,0,12,73,68,65,84,8,153,99,248,15,4,0,9,251,3,253,140,67,99,107,0,0,0,0,73,69,78,68,174,66,96,130))

Write-Host "--- POST /uploads/dish-image ---" -ForegroundColor Cyan
& curl.exe -s -X POST -F ("file=@" + $tmp) "$base/uploads/dish-image"
Write-Host ''

Write-Host "--- POST /uploads/merchant-qr-code ---" -ForegroundColor Cyan
& curl.exe -s -X POST -F ("file=@" + $tmp) -F 'merchantId=m_self' "$base/uploads/merchant-qr-code"
Write-Host ''

Write-Host "--- POST /uploads/payment-screenshot ---" -ForegroundColor Cyan
& curl.exe -s -X POST -F ("file=@" + $tmp) -F 'orderId=O20240516001' "$base/uploads/payment-screenshot"
Write-Host ''

Write-Host "--- GET /merchant/profile (qr should be /uploads/...) ---" -ForegroundColor Cyan
& curl.exe -s "$base/merchant/profile?userId=u_mer_1"
Write-Host ''
