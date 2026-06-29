# =============================================================
# test_upload.ps1 — 最小上传自测
#
# 用法：
#   cd server
#   powershell -ExecutionPolicy Bypass -File ./scripts/test_upload.ps1
#
# 环境变量：
#   API_BASE=http://localhost:3000/api
# =============================================================

$ErrorActionPreference = 'Stop'
$base = if ($env:API_BASE) { $env:API_BASE } else { 'http://localhost:3000/api' }
$url = "$base/uploads/merchant-qr-code"

Write-Host "================ test_upload ================" -ForegroundColor Cyan
Write-Host "POST $url"

$tmp = New-TemporaryFile
try {
    # 最小 PNG 头
    [IO.File]::WriteAllBytes($tmp.FullName, [byte[]](137, 80, 78, 71, 13, 10, 26, 10))

    $boundary = [Guid]::NewGuid().ToString('N')
    $fileBytes = [IO.File]::ReadAllBytes($tmp.FullName)
    $fileName = 'test_upload.png'

    $bodyStream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.StreamWriter($bodyStream, [Text.Encoding]::ASCII)
    $writer.NewLine = "`r`n"
    $writer.Write("--$boundary")
    $writer.WriteLine()
    $writer.Write("Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"")
    $writer.WriteLine()
    $writer.WriteLine('Content-Type: image/png')
    $writer.WriteLine()
    $writer.Flush()
    $headerBytes = $bodyStream.ToArray()
    $footerText = "`r`n--$boundary--`r`n"
    $footerBytes = [Text.Encoding]::ASCII.GetBytes($footerText)
    $body = New-Object byte[] ($headerBytes.Length + $fileBytes.Length + $footerBytes.Length)
    [Array]::Copy($headerBytes, 0, $body, 0, $headerBytes.Length)
    [Array]::Copy($fileBytes, 0, $body, $headerBytes.Length, $fileBytes.Length)
    [Array]::Copy($footerBytes, 0, $body, $headerBytes.Length + $fileBytes.Length, $footerBytes.Length)

    $resp = Invoke-WebRequest -Uri $url -Method Post `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $body -TimeoutSec 10

    Write-Host "HTTP $($resp.StatusCode)" -ForegroundColor Green
    Write-Host $resp.Content

    $json = $resp.Content | ConvertFrom-Json
    if ($json.data.url -match '/uploads/') {
        Write-Host "[PASS] upload ok: $($json.data.url)" -ForegroundColor Green
        exit 0
    }
    Write-Host "[FAIL] response missing /uploads/ url" -ForegroundColor Red
    exit 1
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host $reader.ReadToEnd()
    }
    exit 1
} finally {
    Remove-Item -Path $tmp.FullName -Force -ErrorAction SilentlyContinue
}
