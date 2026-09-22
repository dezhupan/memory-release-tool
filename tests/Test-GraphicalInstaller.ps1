$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$setupSourcePath = Join-Path $project 'Installer\MemoryCleanerFloatSetup.cs'
$uninstallSourcePath = Join-Path $project 'Installer\MemoryCleanerFloatUninstall.cs'
$build = Join-Path $project 'build\graphical-installer-v3.15.3'
$setupPath = Join-Path $project 'dist\MemoryCleanerFloat-Setup-v3.15.3.exe'
$payloadPath = Join-Path $build 'payload'

function Assert-Contains([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$setupSource = [IO.File]::ReadAllText($setupSourcePath, [Text.Encoding]::UTF8)
$uninstallSource = [IO.File]::ReadAllText($uninstallSourcePath, [Text.Encoding]::UTF8)

Assert-Contains $setupSource 'GetManifestResourceStream\("MemoryCleanerFloat\.Payload\.zip"\)' 'setup extracts one embedded payload'
Assert-Contains $setupSource 'ZipArchive' 'setup uses structured ZIP extraction'
Assert-Contains $setupSource 'StartsWith\(safeRoot' 'setup blocks ZIP path traversal'
Assert-Contains $setupSource '\.memorycleanerfloat-install' 'setup writes a product marker'
Assert-Contains $setupSource 'CurrentVersion\\Uninstall\\MemoryCleanerFloat' 'setup registers Windows uninstall metadata'
Assert-Contains $setupSource 'CreateShortcut' 'setup creates native Windows shortcuts'
Assert-Contains $setupSource 'Path\.Combine\(destination, "内存释放任务栏工具\.exe"\)' 'shortcuts and uninstall metadata use the stable application target'
Assert-Contains $setupSource 'CreateNoWindow = true' 'deployment PowerShell runs without a console window'
Assert-Contains $setupSource 'AllowPendingEmbedding' 'first-time symbol resolution is not reported as a false install failure'
Assert-Contains $setupSource 'StopInstalledApps' 'upgrade stops only the installed app before replacing files'
Assert-Contains $setupSource 'LocalApplicationData' 'Windhawk uses a per-user location without requiring a D drive'
Assert-Contains $setupSource 'ResolveWindhawkRoot' 'setup detects and reuses an existing Portable Windhawk instance'
Assert-Contains $setupSource 'WindhawkRoot=' 'setup records the selected Windhawk root for safe upgrades and uninstall'
Assert-Contains $uninstallSource 'ResolveWindhawkRoot' 'uninstaller reuses the Windhawk root recorded by setup'
Assert-Contains $uninstallSource 'IsDriveRoot' 'uninstaller rejects dangerous root-directory deletion'
Assert-Contains $uninstallSource 'DeleteSubKeyTree' 'uninstaller removes its Apps and Features entry'
Assert-Contains $uninstallSource 'Windhawk' 'uninstaller documents that Windhawk is preserved'
if ($uninstallSource -match 'rmdir[^\r\n]+Windhawk') { throw 'FAIL: uninstaller must not recursively delete Windhawk' }

if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) { throw 'FAIL: graphical Setup.exe is missing' }
$setupItem = Get-Item -LiteralPath $setupPath
if ($setupItem.VersionInfo.FileVersion -ne '3.15.3.0') { throw 'FAIL: graphical setup file version mismatch' }
if ([string]::IsNullOrWhiteSpace($setupItem.VersionInfo.ProductName)) { throw 'FAIL: graphical setup product name is missing' }
if ($setupItem.Length -le 60MB) { throw 'FAIL: graphical setup does not contain the application and offline dependency payload' }

$offline = Join-Path $payloadPath 'Dependencies\windhawk_setup.exe'
if ((Get-FileHash -LiteralPath $offline -Algorithm SHA256).Hash -ne '5116CC1703384AAC88B8D7A3B57F172AEA5DA32B6DF7355FB2F8247D23813C8F') {
    throw 'FAIL: bundled offline Windhawk installer hash mismatch'
}
if ((Get-AuthenticodeSignature -LiteralPath $offline).Status -ne 'Valid') { throw 'FAIL: bundled offline Windhawk signature is invalid' }
if (-not (Test-Path -LiteralPath (Join-Path $payloadPath 'MemoryCleanerFloat.ps1') -PathType Leaf)) { throw 'FAIL: hidden cleanup worker sidecar is missing' }
if (-not (Test-Path -LiteralPath (Join-Path $payloadPath '内存释放任务栏工具.exe') -PathType Leaf)) { throw 'FAIL: stable application executable is missing' }
if (-not (Test-Path -LiteralPath (Join-Path $payloadPath 'MemoryCleanerTaskbarHost.exe') -PathType Leaf)) { throw 'FAIL: taskbar host executable is missing' }
$oldExecutables = @(Get-ChildItem -LiteralPath $payloadPath -Filter '内存释放任务栏工具-v*.exe')
if ($oldExecutables.Count -ne 0) {
    throw "FAIL: payload contains old application versions: $($oldExecutables.Name -join ', ')"
}

$runIndex = $setupSource.IndexOf('RunPowerShell(destination, windhawkRoot)')
$shortcutIndex = $setupSource.IndexOf('CreateShortcuts(destination, createDesktop)')
$registerIndex = $setupSource.IndexOf('RegisterUninstaller(destination)')
if ($runIndex -lt 0 -or $shortcutIndex -lt $runIndex -or $registerIndex -lt $runIndex) {
    throw 'FAIL: shortcuts and uninstall registration must happen only after successful module deployment'
}
Write-Host 'PASS: setup publishes shortcuts and uninstall metadata only after module deployment succeeds'

Write-Host 'PASS: graphical installer, current-only payload, offline dependency, safe extraction, shortcuts, and uninstall are verified.'
