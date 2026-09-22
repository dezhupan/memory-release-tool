param(
    [string]$WindhawkRoot = ''
)

$ErrorActionPreference = 'Stop'
$modId = 'local@memory-cleaner-taskbar-slot'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$windhawkCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($WindhawkRoot)) { $windhawkCandidates += $WindhawkRoot }
$windhawkCandidates += @(
    'D:\Windhawk',
    (Join-Path (Split-Path -Parent $scriptRoot) 'Windhawk')
)
$WindhawkRoot = $windhawkCandidates | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath (Join-Path $_ 'windhawk.exe') -PathType Leaf)
} | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($WindhawkRoot)) {
    throw 'Windhawk was not found. Install it first; D:\Windhawk is recommended.'
}
$WindhawkRoot = [System.IO.Path]::GetFullPath($WindhawkRoot)
$windhawkExe = Join-Path $WindhawkRoot 'windhawk.exe'
$targetSourceDir = Join-Path $WindhawkRoot 'AppData\ModsSource'
$targetModsDir = Join-Path $WindhawkRoot 'AppData\Engine\Mods'
$targetDllDir = Join-Path $targetModsDir '64'
$readyPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\taskbar-ready.json'

if (-not (Test-Path -LiteralPath $windhawkExe -PathType Leaf)) {
    throw "Windhawk was not found at: $windhawkExe"
}

$sourceDll = Join-Path $scriptRoot 'memory-cleaner-taskbar-slot.dll'
$sourceCode = Join-Path $scriptRoot 'memory-cleaner-taskbar-slot.wh.cpp'
if (-not (Test-Path -LiteralPath $sourceDll -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceCode -PathType Leaf)) {
    throw 'The Windhawk module DLL or source file is missing. Extract the complete package and retry.'
}

$dllHash = (Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
$moduleVersion = '1.6.2'
$dllName = 'local@memory-cleaner-taskbar-slot_{0}_{1}.dll' -f $moduleVersion, $dllHash
$configPath = Join-Path $targetModsDir "$modId.ini"
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $oldConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    if ($oldConfig -match '(?m)^Disabled=') {
        $oldConfig = $oldConfig -replace '(?m)^Disabled=.*$', 'Disabled=1'
    } else {
        $oldConfig = $oldConfig -replace '(?m)^\[Mod\]\s*$', "[Mod]`r`nDisabled=1"
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, $oldConfig, $encoding)
    Start-Sleep -Seconds 2
}
Remove-Item -LiteralPath $readyPath -Force -ErrorAction SilentlyContinue

[void][System.IO.Directory]::CreateDirectory($targetSourceDir)
[void][System.IO.Directory]::CreateDirectory($targetDllDir)
Copy-Item -LiteralPath $sourceCode -Destination (Join-Path $targetSourceDir "$modId.wh.cpp") -Force
Copy-Item -LiteralPath $sourceDll -Destination (Join-Path $targetDllDir $dllName) -Force

$config = @"
[Mod]
LibraryFileName=$dllName
Disabled=0
LoggingEnabled=1
DebugLoggingEnabled=0
Include=explorer.exe
Exclude=
Architecture=x86-64
Version=$moduleVersion

[Settings]
showOnAllTaskbars=0
"@
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $config, $encoding)
$packageRoot = Split-Path -Parent $scriptRoot
$settingsPath = Join-Path $packageRoot 'settings.json'
try {
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $settings = [pscustomobject]@{}
    }
    if ($null -eq $settings.PSObject.Properties['WindhawkPath']) {
        $settings | Add-Member -NotePropertyName WindhawkPath -NotePropertyValue $windhawkExe
    } else {
        $settings.WindhawkPath = $windhawkExe
    }
    if ($null -eq $settings.PSObject.Properties['DisplayMode']) { $settings | Add-Member -NotePropertyName DisplayMode -NotePropertyValue 'taskbar' }
    if ($null -eq $settings.PSObject.Properties['TaskbarPosition']) { $settings | Add-Member -NotePropertyName TaskbarPosition -NotePropertyValue 'left' }
    if ($null -eq $settings.PSObject.Properties['TaskbarOffset']) { $settings | Add-Member -NotePropertyName TaskbarOffset -NotePropertyValue 0 }
    $settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
} catch {
    throw "settings.json could not be updated: $($_.Exception.Message)"
}
$runningWindhawk = Get-CimInstance Win32_Process -Filter "Name='windhawk.exe'" -ErrorAction SilentlyContinue | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
    [string]::Equals([System.IO.Path]::GetFullPath($_.ExecutablePath), [System.IO.Path]::GetFullPath($windhawkExe), [System.StringComparison]::OrdinalIgnoreCase)
} | Select-Object -First 1
if ($null -eq $runningWindhawk) {
    Start-Process -FilePath $windhawkExe -ArgumentList '-tray-only' -WindowStyle Hidden
} else {
    Start-Process -FilePath $windhawkExe -ArgumentList '-restart -tray-only' -WindowStyle Hidden
}
Write-Host "Installation complete. Module version: $moduleVersion. Windhawk root: $WindhawkRoot" -ForegroundColor Green
