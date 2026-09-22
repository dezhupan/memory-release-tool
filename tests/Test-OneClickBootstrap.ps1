$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$bootstrapPath = Join-Path $project 'Install-WindhawkPortable.ps1'
$entryPath = Join-Path $project 'Install-And-Run.ps1'
$readmePath = Join-Path $project '使用说明.md'

function Assert-Contains([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw "FAIL: $Message" }
}

$bootstrap = [IO.File]::ReadAllText($bootstrapPath, [Text.Encoding]::UTF8)
$entry = [IO.File]::ReadAllText($entryPath, [Text.Encoding]::UTF8)
$readme = [IO.File]::ReadAllText($readmePath, [Text.Encoding]::UTF8)

Assert-Contains $bootstrap 'https://github\.com/ramensoftware/windhawk/releases/download/v1\.7\.3/windhawk_setup\.exe' 'uses the pinned official Windhawk release URL'
Assert-Contains $bootstrap '5116CC1703384AAC88B8D7A3B57F172AEA5DA32B6DF7355FB2F8247D23813C8F' 'pins the official installer SHA256'
Assert-Contains $bootstrap '4D93016570F982326EEBDFC9068E924FF21F6448534EA32672BB4C1D52A8193B' 'pins the official offline installer SHA256'
Assert-Contains $bootstrap 'Get-AuthenticodeSignature' 'checks the installer Authenticode signature'
Assert-Contains $bootstrap 'Michael Maltsev\|Open Source Developer' 'checks the expected signer'
Assert-Contains $bootstrap "'1204'" 'selects the official installer Portable mode control'
Assert-Contains $bootstrap "'1019'" 'sets the official installer destination control'
Assert-Contains $bootstrap 'Portable=1' 'verifies portable mode after installation'
Assert-Contains $bootstrap 'destination exists but is not a valid portable Windhawk installation' 'refuses to overwrite an unrelated non-empty destination'
Assert-Contains $bootstrap "'-tray-only'" 'starts Windhawk without opening its main window'
Assert-Contains $bootstrap 'HideTrayIcon.*Value = ''1''' 'hides the Windhawk notification icon'
Assert-Contains $bootstrap 'DontAutoShowToolkit.*Value = ''1''' 'suppresses the Windhawk toolkit window'
Assert-Contains $bootstrap "'-restart -tray-only'" 'applies hidden mode when upgrading an existing installation'
Assert-Contains $entry 'Install-WindhawkPortable\.ps1' 'the public entry invokes the Windhawk bootstrap'
Assert-Contains $entry 'LocalApplicationData' 'the public entry defaults to a per-user Windhawk location'
Assert-Contains $entry 'Get-CimInstance Win32_Process.+windhawk\.exe' 'the public entry detects the currently running Windhawk instance'
Assert-Contains $entry "'D:\\Windhawk'" 'the public entry can reuse an existing D drive Portable installation'
Assert-Contains $entry 'Version=1\\\.6\\\.2' 'the public entry rejects an outdated installed module'
Assert-Contains $entry 'installed taskbar module does not match' 'the public entry verifies the installed DLL against the bundled DLL'
Assert-Contains $entry 'MemoryCleanerFloat\.ps1' 'the package requires the hidden cleanup worker sidecar'
Assert-Contains $entry '\$powershellExe.+\$checker' 'the readiness checker runs as a child process'
Assert-Contains $entry 'AllowPendingEmbedding' 'graphical setup can finish while first-time symbols are still pending'
Assert-Contains $readme 'Windhawk 官方安装程序' 'the Chinese guide documents the bundled official Windhawk installer'

$downloadedSetup = Join-Path $project 'build\auto-download-cache\windhawk_setup.exe'
$installedWindhawk = Join-Path $project 'build\windhawk-auto-download-smoke\windhawk.exe'
$portableIni = Join-Path $project 'build\windhawk-auto-download-smoke\windhawk.ini'
if (Test-Path -LiteralPath $downloadedSetup -PathType Leaf) {
    $hash = (Get-FileHash -LiteralPath $downloadedSetup -Algorithm SHA256).Hash
    if ($hash -ne '5116CC1703384AAC88B8D7A3B57F172AEA5DA32B6DF7355FB2F8247D23813C8F') {
        throw 'FAIL: isolated auto-download installer hash mismatch'
    }
}
if (Test-Path -LiteralPath $installedWindhawk -PathType Leaf) {
    if (-not (Test-Path -LiteralPath $portableIni -PathType Leaf)) { throw 'FAIL: isolated portable ini missing' }
    if (-not (Select-String -LiteralPath $portableIni -SimpleMatch 'Portable=1' -Quiet)) { throw 'FAIL: isolated install is not portable' }
}

Write-Host 'PASS: one-click Windhawk bootstrap is pinned, verified, automated, repeatable, and documented.'
