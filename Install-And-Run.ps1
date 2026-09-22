param(
    [string]$WindhawkRoot = '',
    [int]$WaitSeconds = 300,
    [switch]$AllowPendingEmbedding
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleDirectory = Join-Path $packageRoot 'WindhawkMod'
$windhawkBootstrap = Join-Path $packageRoot 'Install-WindhawkPortable.ps1'
$installer = Join-Path $moduleDirectory '安装或更新-Windhawk模块.ps1'
$checker = Join-Path $moduleDirectory '检查任务栏模块.ps1'
$reporter = Join-Path $packageRoot 'TaskbarDiagnostic.ps1'
$app = Join-Path $packageRoot '内存释放任务栏工具.exe'
$workerScript = Join-Path $packageRoot 'MemoryCleanerFloat.ps1'

trap {
    Write-Host "One-click installation failed: $($_.Exception.Message)" -ForegroundColor Red
    if (Test-Path -LiteralPath $reporter -PathType Leaf) {
        try { & $reporter -WindhawkRoot $WindhawkRoot } catch { Write-Warning $_.Exception.Message }
    }
    exit 1
}

if ([Environment]::OSVersion.Version.Build -lt 22000) {
    throw 'Native taskbar embedding requires Windows 11.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This package requires Windows 11 x64.'
}
$nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($nativeArchitecture -eq 'ARM64') {
    throw 'This x64 package cannot inject ARM64 explorer.exe.'
}
foreach ($path in @($windhawkBootstrap, $installer, $checker, $reporter, $app, $workerScript, (Join-Path $moduleDirectory 'memory-cleaner-taskbar-slot.dll'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Package file is missing: $path" }
    Unblock-File -LiteralPath $path -ErrorAction SilentlyContinue
}

function Test-WindhawkPortable([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    $exe = Join-Path $Root 'windhawk.exe'
    $ini = Join-Path $Root 'windhawk.ini'
    return (Test-Path -LiteralPath $exe -PathType Leaf) -and
        (Test-Path -LiteralPath $ini -PathType Leaf) -and
        [bool](Select-String -LiteralPath $ini -SimpleMatch 'Portable=1' -Quiet -ErrorAction SilentlyContinue)
}

if ([string]::IsNullOrWhiteSpace($WindhawkRoot)) {
    $windhawkCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='windhawk.exe'" -ErrorAction SilentlyContinue)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
            $windhawkCandidates.Add((Split-Path -Parent $process.ExecutablePath))
        }
    }
    foreach ($candidate in @(
        (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk'),
        'D:\Windhawk',
        (Join-Path $packageRoot 'Windhawk'),
        'C:\Windhawk'
    )) { $windhawkCandidates.Add($candidate) }
    $WindhawkRoot = $windhawkCandidates | Select-Object -Unique | Where-Object { Test-WindhawkPortable $_ } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($WindhawkRoot)) {
        $WindhawkRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk'
    }
}
$WindhawkRoot = [IO.Path]::GetFullPath($WindhawkRoot)

$windhawkExe = Join-Path $WindhawkRoot 'windhawk.exe'
if (-not (Test-WindhawkPortable $WindhawkRoot)) {
    Write-Host 'Windhawk is not installed. Installing the official Portable build automatically...' -ForegroundColor Cyan
}
& $windhawkBootstrap -WindhawkRoot $WindhawkRoot

Write-Host 'Installing the Windhawk taskbar module...' -ForegroundColor Cyan
& $installer -WindhawkRoot $WindhawkRoot

$moduleConfig = Join-Path $WindhawkRoot 'AppData\Engine\Mods\local\@memory-cleaner-taskbar-slot.ini'
if (-not (Test-Path -LiteralPath $moduleConfig -PathType Leaf)) {
    throw "The taskbar module config was not created: $moduleConfig"
}
$moduleConfigText = Get-Content -LiteralPath $moduleConfig -Raw -Encoding UTF8
if ($moduleConfigText -notmatch '(?m)^Version=1\.6\.2\s*$') {
    throw 'The taskbar module was not upgraded to version 1.6.2.'
}
$libraryName = (($moduleConfigText -split "`r?`n") | Where-Object { $_ -like 'LibraryFileName=*' } | Select-Object -First 1) -replace '^LibraryFileName=', ''
$installedLibrary = Join-Path $WindhawkRoot "AppData\Engine\Mods\64\$libraryName"
if ([string]::IsNullOrWhiteSpace($libraryName) -or -not (Test-Path -LiteralPath $installedLibrary -PathType Leaf)) {
    throw 'The current taskbar module library was not installed.'
}
$packageLibrary = Join-Path $moduleDirectory 'memory-cleaner-taskbar-slot.dll'
if ((Get-FileHash -LiteralPath $installedLibrary -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $packageLibrary -Algorithm SHA256).Hash) {
    throw 'The installed taskbar module does not match the module included in this package.'
}

Write-Host 'Starting MemoryCleanerFloat...' -ForegroundColor Cyan
$running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ExecutablePath -eq $app
} | Select-Object -First 1
if ($null -eq $running) {
    Start-Process -FilePath $app -WorkingDirectory $packageRoot | Out-Null
}

Write-Host 'Waiting for Windhawk symbols and native taskbar injection. The first run can take several minutes; keep the computer online...' -ForegroundColor Yellow
$powershellExe = Join-Path $PSHOME 'powershell.exe'
& $powershellExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $checker -WindhawkRoot $WindhawkRoot -WaitSeconds $WaitSeconds
$checkerExitCode = $LASTEXITCODE
if ($checkerExitCode -ne 0) {
    try { & $reporter -WindhawkRoot $WindhawkRoot } catch { Write-Warning $_.Exception.Message }
    if ($AllowPendingEmbedding -and $checkerExitCode -eq 20) {
        Write-Host 'Pending: installation completed; Windhawk is still resolving symbols or waiting for Explorer injection.' -ForegroundColor Yellow
        exit 0
    }
    Write-Host 'Native embedding was not confirmed. Send TaskbarDiagnostic.txt to the tool provider.' -ForegroundColor Red
    exit $checkerExitCode
}

Write-Host 'Success: the native taskbar slot is active.' -ForegroundColor Green
exit 0
