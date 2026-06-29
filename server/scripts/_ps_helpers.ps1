# Shared helpers for E2E scripts (UTF-8 JSON + safe merchant names)

function Test-CorruptDisplayName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    if ($Name -match '^\?+$') { return $true }
    if ($Name.Contains('???')) { return $true }
    if ($Name.StartsWith('?') -and $Name.ToUpper().Contains('E2E')) { return $true }
    return $false
}

function Resolve-SafeMerchantName {
    param(
        [string]$Name,
        [string]$Fallback = 'E2ETestShop'
    )
    if (Test-CorruptDisplayName $Name) { return $Fallback }
    return $Name
}

function PostJsonUtf8 {
    param($url, $headers, $obj)
    $json = $obj | ConvertTo-Json -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $h = @{}
    if ($headers) { foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] } }
    return Invoke-RestMethod -Method Post -Uri $url -Headers $h -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 5
}

function PutJsonUtf8 {
    param($url, $headers, $obj)
    $json = $obj | ConvertTo-Json -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $h = @{}
    if ($headers) { foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] } }
    return Invoke-RestMethod -Method Put -Uri $url -Headers $h -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 5
}

function Clear-OvertimeMealUsagesForE2e {
    param(
        [string]$WorkDate,
        [string[]]$Phones = @('13800000000', '13800000001', '13800000002'),
        [string]$MealType = ''
    )
    $scriptPath = Join-Path $PSScriptRoot 'clear_overtime_usages_for_e2e.js'
    if (-not (Test-Path $scriptPath)) { return 0 }
    $phoneArg = ($Phones -join ',')
    try {
        if ($MealType) {
            $out = (node $scriptPath $WorkDate $phoneArg $MealType 2>&1 | Out-String).Trim()
        } else {
            $out = (node $scriptPath $WorkDate $phoneArg 2>&1 | Out-String).Trim()
        }
        if ($out -match '^\d+$') { return [int]$out }
        return 0
    } catch {
        return 0
    }
}
