param(
    [string]$WindhawkRoot = '',
    [string]$ReportDirectory = '',
    [switch]$NoOpen,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modId = 'local@memory-cleaner-taskbar-slot'
$expectedModuleVersion = '1.6.2'
$reportName = 'TaskbarDiagnostic.txt'
$lines = New-Object System.Collections.Generic.List[string]

function Add-ReportLine {
    param([string]$Name, $Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { $Value = '<none>' }
    $lines.Add(('{0}: {1}' -f $Name, $Value))
}

function Read-SharedUnicodeFile {
    param([string]$Path)
    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        try {
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::Unicode, $true)
            try { return $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
    } catch { return ('<unreadable: {0}>' -f $_.Exception.Message) }
}

$lines.Add('MemoryCleanerFloat taskbar diagnostic')
Add-ReportLine 'Diagnostic version' '2.2'
Add-ReportLine 'Generated' ((Get-Date).ToString('o'))
Add-ReportLine 'Windows version' ([Environment]::OSVersion.Version.ToString())
Add-ReportLine 'Windows build' ([Environment]::OSVersion.Version.Build)
Add-ReportLine 'OS 64-bit' ([Environment]::Is64BitOperatingSystem)
$nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
Add-ReportLine 'Native architecture' $nativeArchitecture

$bootstrapPath = Join-Path $packageRoot 'Install-WindhawkPortable.ps1'
$bundledSetupPath = Join-Path $packageRoot 'Dependencies\windhawk_setup.exe'
$bundledSetupExists = Test-Path -LiteralPath $bundledSetupPath -PathType Leaf
$bundledSetupHash = ''
$bundledSetupSignature = ''
$setupCachePath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Dependencies\windhawk_setup_v1.7.3.exe'
$setupCacheExists = Test-Path -LiteralPath $setupCachePath -PathType Leaf
$setupCacheHash = ''
$setupCacheSignature = ''
Add-ReportLine 'One-click bootstrap exists' (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)
Add-ReportLine 'Bundled Windhawk installer exists' $bundledSetupExists
if ($bundledSetupExists) {
    try { $bundledSetupHash = (Get-FileHash -LiteralPath $bundledSetupPath -Algorithm SHA256 -ErrorAction Stop).Hash } catch { $bundledSetupHash = '<error>' }
    try { $bundledSetupSignature = (Get-AuthenticodeSignature -LiteralPath $bundledSetupPath).Status } catch { $bundledSetupSignature = '<error>' }
}
Add-ReportLine 'Bundled Windhawk installer SHA256' $bundledSetupHash
Add-ReportLine 'Bundled Windhawk installer signature' $bundledSetupSignature
Add-ReportLine 'Windhawk installer cache path' $setupCachePath
Add-ReportLine 'Windhawk installer cache exists' $setupCacheExists
if ($setupCacheExists) {
    try { $setupCacheHash = (Get-FileHash -LiteralPath $setupCachePath -Algorithm SHA256 -ErrorAction Stop).Hash } catch { $setupCacheHash = '<error>' }
    try { $setupCacheSignature = (Get-AuthenticodeSignature -LiteralPath $setupCachePath).Status } catch { $setupCacheSignature = '<error>' }
}
Add-ReportLine 'Windhawk installer cache SHA256' $setupCacheHash
Add-ReportLine 'Windhawk installer cache signature' $setupCacheSignature

try {
    $screens = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
        if ($null -ne $_.CurrentHorizontalResolution -and $null -ne $_.CurrentVerticalResolution) {
            '{0}x{1}' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution
        }
    } | Where-Object { $_ })
    Add-ReportLine 'Screen resolution' ($screens -join '; ')
} catch { Add-ReportLine 'Screen resolution' ('<error: {0}>' -f $_.Exception.Message) }
Add-ReportLine 'Resolution relevance' 'Only limits maximum drag offset; offset 0 should still be visible.'

$currentSessionId = (Get-Process -Id $PID -ErrorAction SilentlyContinue).SessionId
$explorer = Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object {
    $_.SessionId -eq $currentSessionId
} | Sort-Object StartTime -Descending | Select-Object -First 1
Add-ReportLine 'Explorer running' ($null -ne $explorer)
if ($null -ne $explorer) { Add-ReportLine 'Explorer PID' $explorer.Id }
Add-ReportLine 'ExplorerPatcher running' (@(Get-Process -Name ep_taskbar,ExplorerPatcher -ErrorAction SilentlyContinue).Count -gt 0)
Add-ReportLine 'StartAllBack running' (@(Get-Process -Name StartAllBackCfg,StartAllBackX64 -ErrorAction SilentlyContinue).Count -gt 0)

$windhawkProcesses = @(Get-CimInstance Win32_Process -Filter "Name='windhawk.exe'" -ErrorAction SilentlyContinue)
$windhawkCandidates = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($WindhawkRoot)) { $windhawkCandidates.Add($WindhawkRoot) }
foreach ($process in $windhawkProcesses) {
    if (-not [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
        $windhawkCandidates.Add((Split-Path -Parent $process.ExecutablePath))
    }
}
foreach ($candidate in @(
    (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk'),
    'D:\Windhawk',
    (Join-Path $packageRoot 'Windhawk'),
    'C:\Windhawk',
    'C:\Program Files\Windhawk'
)) {
    $windhawkCandidates.Add($candidate)
}
$uniqueCandidates = @($windhawkCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$resolvedWindhawkRoot = $uniqueCandidates | Where-Object {
    Test-Path -LiteralPath (Join-Path $_ 'windhawk.exe') -PathType Leaf
} | Select-Object -First 1

Add-ReportLine 'Windhawk candidates' ($uniqueCandidates -join '; ')
Add-ReportLine 'Windhawk running' ($windhawkProcesses.Count -gt 0)
Add-ReportLine 'Windhawk root' $resolvedWindhawkRoot
Add-ReportLine 'Windhawk executable exists' (-not [string]::IsNullOrWhiteSpace($resolvedWindhawkRoot))
Add-ReportLine 'Expected module version' $expectedModuleVersion
$packageModulePath = Join-Path $packageRoot 'WindhawkMod\memory-cleaner-taskbar-slot.dll'
$packageModuleExists = Test-Path -LiteralPath $packageModulePath -PathType Leaf
Add-ReportLine 'Bundled module exists' $packageModuleExists
if ($packageModuleExists) {
    Add-ReportLine 'Bundled module SHA256' ((Get-FileHash -LiteralPath $packageModulePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash)
}

$configExists = $false
$moduleDisabled = $null
$moduleVersion = ''
$configuredModuleVersion = ''
$libraryExists = $false
$runtimeStatus = ''
$runtimeTask = ''
if (-not [string]::IsNullOrWhiteSpace($resolvedWindhawkRoot)) {
    $configPath = Join-Path $resolvedWindhawkRoot "AppData\Engine\Mods\$modId.ini"
    $configExists = Test-Path -LiteralPath $configPath -PathType Leaf
    Add-ReportLine 'Module config path' $configPath
    Add-ReportLine 'Module config exists' $configExists
    if ($configExists) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $moduleVersion = ((($config -split "`r?`n") | Where-Object { $_ -like 'Version=*' }) -join '; ')
            $configuredModuleVersion = ($moduleVersion -replace '^Version=', '')
            $moduleDisabled = ($config -match '(?m)^Disabled=1\s*$')
            $libraryName = ((($config -split "`r?`n") | Where-Object { $_ -like 'LibraryFileName=*' }) -replace '^LibraryFileName=', '' | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace($libraryName)) {
                $libraryPath = Join-Path $resolvedWindhawkRoot "AppData\Engine\Mods\64\$libraryName"
                $libraryExists = Test-Path -LiteralPath $libraryPath -PathType Leaf
                Add-ReportLine 'Module library path' $libraryPath
            }
        } catch { Add-ReportLine 'Module config read error' $_.Exception.Message }
    }
    Add-ReportLine 'Module version' $moduleVersion
    Add-ReportLine 'Module disabled' $moduleDisabled
    Add-ReportLine 'Module library exists' $libraryExists

    foreach ($category in @('mod-status', 'mod-task')) {
        $directory = Join-Path $resolvedWindhawkRoot "AppData\Engine\ModsWritable\$category"
        $values = @(Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "*$modId"
        } | ForEach-Object { Read-SharedUnicodeFile $_.FullName } | Where-Object { $_ })
        if ($category -eq 'mod-status') { $runtimeStatus = $values -join '; ' }
        else { $runtimeTask = $values -join '; ' }
    }
} else {
    Add-ReportLine 'Module config exists' $false
}
Add-ReportLine 'Module runtime status' $runtimeStatus
Add-ReportLine 'Module runtime task' $runtimeTask

$readyPath = Join-Path $env:LOCALAPPDATA 'MemoryCleanerFloat\taskbar-ready.json'
$readyExists = Test-Path -LiteralPath $readyPath -PathType Leaf
$readyFresh = $false
$readyVersionMatches = $false
Add-ReportLine 'Ready marker path' $readyPath
Add-ReportLine 'Ready marker exists' $readyExists
if ($readyExists) {
    try {
        $readyFile = Get-Item -LiteralPath $readyPath -ErrorAction Stop
        $readyContent = Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8 -ErrorAction Stop
        $ready = $readyContent | ConvertFrom-Json -ErrorAction Stop
        $readyAge = ((Get-Date) - $readyFile.LastWriteTime).TotalSeconds
        $readyVersionMatches = (-not [string]::IsNullOrWhiteSpace($configuredModuleVersion) -and [string]$ready.Version -eq $configuredModuleVersion)
        $readyFresh = ($null -ne $explorer -and $readyVersionMatches -and [int]$ready.ExplorerPid -eq [int]$explorer.Id -and $readyAge -le 15)
        Add-ReportLine 'Ready marker content' $readyContent
        Add-ReportLine 'Ready marker age seconds' ('{0:N1}' -f $readyAge)
    } catch { Add-ReportLine 'Ready marker read error' $_.Exception.Message }
}
Add-ReportLine 'Ready marker active' $readyFresh
Add-ReportLine 'Ready marker version matches config' $readyVersionMatches

$statePath = Join-Path $env:LOCALAPPDATA 'MemoryCleanerFloat\taskbar-state.json'
$controllerStateExists = Test-Path -LiteralPath $statePath -PathType Leaf
Add-ReportLine 'Controller state exists' $controllerStateExists
if ($controllerStateExists) {
    try {
        $stateFile = Get-Item -LiteralPath $statePath -ErrorAction Stop
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        Add-ReportLine 'Controller visible' $state.Visible
        Add-ReportLine 'Controller offset' $state.TaskbarOffset
        Add-ReportLine 'Controller state age seconds' ('{0:N1}' -f (((Get-Date) - $stateFile.LastWriteTime).TotalSeconds))
    } catch { Add-ReportLine 'Controller state read error' $_.Exception.Message }
}

$likelyCause = 'Unknown. Send this complete report to the tool provider.'
if ([Environment]::OSVersion.Version.Build -lt 22000) {
    $likelyCause = 'Unsupported OS: native embedding requires Windows 11.'
} elseif ($nativeArchitecture -eq 'ARM64') {
    $likelyCause = 'Unsupported architecture: this package is x64 and cannot inject ARM64 explorer.exe.'
} elseif ([string]::IsNullOrWhiteSpace($resolvedWindhawkRoot)) {
    $likelyCause = 'Windhawk Portable was not found. Run the current graphical installer again; it can install Windhawk without requiring a D: drive.'
} elseif ($windhawkProcesses.Count -eq 0) {
    $likelyCause = 'Windhawk is installed but not running.'
} elseif (-not $configExists) {
    $likelyCause = 'The MemoryCleanerFloat Windhawk module was not installed.'
} elseif ($configuredModuleVersion -ne $expectedModuleVersion) {
    $likelyCause = "An outdated taskbar module is still installed ($configuredModuleVersion instead of $expectedModuleVersion). Exit the tool and run the current installer again to upgrade the existing Windhawk instance."
} elseif ($moduleDisabled -eq $true) {
    $likelyCause = 'The MemoryCleanerFloat Windhawk module is disabled.'
} elseif (-not $libraryExists) {
    $likelyCause = 'The configured x64 module DLL is missing.'
} elseif ($runtimeTask -match '(?i)symbol') {
    $likelyCause = 'Windhawk is still downloading or resolving symbols. Keep the computer online and retry later.'
} elseif ($runtimeStatus -notmatch '(?i)Loaded') {
    $likelyCause = 'The module was not loaded into explorer.exe.'
} elseif (-not $readyFresh) {
    $likelyCause = 'The module loaded but did not create the native taskbar slot. Check taskbar replacement software or Windows build compatibility.'
} else {
    $likelyCause = 'The native taskbar slot was active when this report was generated.'
}
Add-ReportLine 'Likely cause' $likelyCause

$targetDirectories = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($ReportDirectory)) { $targetDirectories.Add($ReportDirectory) }
$targetDirectories.Add($packageRoot)
$desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
if (-not [string]::IsNullOrWhiteSpace($desktop)) { $targetDirectories.Add($desktop) }
if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) { $targetDirectories.Add($env:TEMP) }

$reportPath = $null
$writeErrors = New-Object System.Collections.Generic.List[string]
foreach ($directory in @($targetDirectories | Select-Object -Unique)) {
    try {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        $candidatePath = Join-Path $directory $reportName
        [System.IO.File]::WriteAllLines($candidatePath, $lines, (New-Object System.Text.UTF8Encoding($true)))
        $reportPath = $candidatePath
        break
    } catch { $writeErrors.Add(('{0}: {1}' -f $directory, $_.Exception.Message)) }
}

if ([string]::IsNullOrWhiteSpace($reportPath)) {
    $message = 'Unable to write TaskbarDiagnostic.txt. ' + ($writeErrors -join ' | ')
    Write-Error $message
    if (-not $Quiet) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($message, 'MemoryCleanerFloat diagnostic', 'OK', 'Error')
        } catch {}
    }
    throw $message
}

Write-Host ('Diagnostic report created: {0}' -f $reportPath) -ForegroundColor Green
if (-not $Quiet) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $successMessage = "Report created:`r`n$reportPath`r`n`r`nSend this file to the tool provider."
        [void][System.Windows.Forms.MessageBox]::Show($successMessage, 'MemoryCleanerFloat diagnostic', 'OK', 'Information')
    } catch {}
}
if (-not $NoOpen) {
    try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $reportPath) | Out-Null } catch {}
}
