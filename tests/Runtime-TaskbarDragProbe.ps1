param(
    [int]$StartX = 1500,
    [int]$EndX = 1250,
    [int]$Y = 1555,
    [string]$ScreenshotPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if (-not ('MemoryCleanerDragProbeNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MemoryCleanerDragProbeNative {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);
}
'@
}

[void][MemoryCleanerDragProbeNative]::SetProcessDPIAware()
$project = Split-Path -Parent $PSScriptRoot
$positionPath = Join-Path $env:LOCALAPPDATA 'MemoryCleanerFloat\taskbar-position.json'
$statePath = Join-Path $env:LOCALAPPDATA 'MemoryCleanerFloat\taskbar-state.json'
$settingsPath = Join-Path $project 'settings.json'
$logPath = Join-Path $project 'cleaner.log'
if ([string]::IsNullOrWhiteSpace($ScreenshotPath)) {
    $ScreenshotPath = Join-Path $project 'build\runtime-v3.2-after-drag.png'
}

Remove-Item -LiteralPath $positionPath -Force -ErrorAction SilentlyContinue
$logBefore = (Get-Item -LiteralPath $logPath).Length
$originalCursor = [System.Windows.Forms.Cursor]::Position

try {
    [void][MemoryCleanerDragProbeNative]::SetCursorPos($StartX, 1599)
    Start-Sleep -Milliseconds 1200
    [void][MemoryCleanerDragProbeNative]::SetCursorPos($StartX, $Y)
    Start-Sleep -Milliseconds 300
    [MemoryCleanerDragProbeNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    for ($step = 1; $step -le 20; $step++) {
        $x = $StartX + [int](($EndX - $StartX) * $step / 20)
        [void][MemoryCleanerDragProbeNative]::SetCursorPos($x, $Y)
        Start-Sleep -Milliseconds 30
    }
    [MemoryCleanerDragProbeNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Seconds 3

    $bitmap = New-Object System.Drawing.Bitmap 2560, 100
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen(0, 1500, 0, 0, $bitmap.Size)
        $bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
} finally {
    [System.Windows.Forms.Cursor]::Position = $originalCursor
}

$positionText = if (Test-Path -LiteralPath $positionPath) {
    Get-Content -LiteralPath $positionPath -Raw -Encoding UTF8
} else {
    'MISSING'
}
$settingsOffset = (Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json).TaskbarOffset
$stateOffset = (Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).TaskbarOffset
$logAfter = (Get-Item -LiteralPath $logPath).Length

[pscustomobject]@{
    PositionFile = $positionText
    SettingsOffset = $settingsOffset
    StateOffset = $stateOffset
    LogBytesAdded = $logAfter - $logBefore
    Screenshot = $ScreenshotPath
}
