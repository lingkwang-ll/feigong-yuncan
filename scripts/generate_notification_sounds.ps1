# Generates short notification WAV files for merchant alerts.
param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\assets\audio")
)

function Write-BeepWav {
    param(
        [string]$Path,
        [double]$Frequency,
        [double]$DurationSec = 0.18,
        [int]$Volume = 9000
    )
    $sampleRate = 22050
    $samples = [int][Math]::Round($sampleRate * $DurationSec)
    $dataSize = $samples * 2
    $fs = [System.IO.File]::Create($Path)
    try {
        $bw = New-Object System.IO.BinaryWriter($fs)
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
        $bw.Write([int32](36 + $dataSize))
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
        $bw.Write([int32]16)
        $bw.Write([int16]1)
        $bw.Write([int16]1)
        $bw.Write([int32]$sampleRate)
        $bw.Write([int32]($sampleRate * 2))
        $bw.Write([int16]2)
        $bw.Write([int16]16)
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
        $bw.Write([int32]$dataSize)
        for ($i = 0; $i -lt $samples; $i++) {
            $t = $i / $sampleRate
            $fadeIn = [Math]::Min(1.0, $i / ($sampleRate * 0.02))
            $fadeOut = [Math]::Min(1.0, ($samples - $i) / ($sampleRate * 0.06))
            $env = $fadeIn * $fadeOut
            $val = [Math]::Sin(2 * [Math]::PI * $Frequency * $t) * $env
            $sample = [int16]($val * $Volume)
            $bw.Write($sample)
        }
    } finally {
        $fs.Close()
    }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-BeepWav -Path (Join-Path $OutDir 'message.wav') -Frequency 880 -DurationSec 0.16
Write-BeepWav -Path (Join-Path $OutDir 'new_order.wav') -Frequency 660 -DurationSec 0.22 -Volume 10000
Write-BeepWav -Path (Join-Path $OutDir 'new_order2.wav') -Frequency 990 -DurationSec 0.12 -Volume 8000
# Double-tone new order: append second tone into one file by copying message pattern
# Also copy to .mp3 names for asset registration (WAV data, browsers accept via AudioElement)
Copy-Item (Join-Path $OutDir 'message.wav') (Join-Path $OutDir 'message.mp3') -Force
Copy-Item (Join-Path $OutDir 'new_order.wav') (Join-Path $OutDir 'new_order.mp3') -Force
Write-Host "Generated notification sounds in $OutDir"
