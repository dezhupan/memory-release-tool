param(
    [string]$WindhawkRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WindhawkRoot)) {
    $WindhawkRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk'
}
$windhawkExe = Join-Path $WindhawkRoot 'windhawk.exe'
$configPath = Join-Path $WindhawkRoot 'AppData\Engine\Mods\local@memory-cleaner-taskbar-slot.ini'
if (-not (Test-Path -LiteralPath $windhawkExe -PathType Leaf)) {
    throw "Windhawk was not found at: $windhawkExe"
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Write-Host 'The module is not installed. Nothing to disable.'
    exit 0
}

$content = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
if ($content -match '(?m)^Disabled=') {
    $content = $content -replace '(?m)^Disabled=.*$', 'Disabled=1'
} else {
    $content = $content -replace '(?m)^\[Mod\]\s*$', "[Mod]`r`nDisabled=1"
}
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $content, $encoding)
Write-Host 'The module is disabled. The original taskbar layout will be restored automatically.' -ForegroundColor Yellow
