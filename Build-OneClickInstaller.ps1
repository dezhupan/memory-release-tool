[CmdletBinding()]
param(
    [ValidatePattern('^\d+(\.\d+){1,3}$')]
    [string]$Version = '3.15.3'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSCommandPath
$buildRoot = Join-Path $project "build\graphical-installer-v$Version"
$payload = Join-Path $buildRoot 'payload'
$payloadZip = Join-Path $buildRoot 'Payload.zip'
$dist = Join-Path $project 'dist'
$setupOutput = Join-Path $dist "MemoryCleanerFloat-Setup-v$Version.exe"
$hashOutput = Join-Path $dist "MemoryCleanerFloat-Setup-v$Version-SHA256.txt"
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$setupSource = Join-Path $project 'Installer\MemoryCleanerFloatSetup.cs'
$uninstallSource = Join-Path $project 'Installer\MemoryCleanerFloatUninstall.cs'
$appName = '内存释放任务栏工具.exe'
$expectedAppVersion = ($Version.Split('.') + @('0', '0', '0', '0') | Select-Object -First 4) -join '.'
$windhawkHash = '5116CC1703384AAC88B8D7A3B57F172AEA5DA32B6DF7355FB2F8247D23813C8F'

function Copy-RequiredFile([string]$RelativePath, [string]$DestinationRelativePath = $RelativePath) {
    $source = Join-Path $project $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required installer input is missing: $source"
    }
    $destination = Join-Path $payload $DestinationRelativePath
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "The .NET Framework C# compiler is unavailable: $compiler"
}

$app = Join-Path $project $appName
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) {
    throw "Build the current application first: $app"
}
if ((Get-Item -LiteralPath $app).VersionInfo.FileVersion -ne $expectedAppVersion) {
    throw "Application file version mismatch. Expected $expectedAppVersion."
}

$windhawkSetup = Join-Path $project 'Dependencies\windhawk_setup.exe'
if ((Get-FileHash -LiteralPath $windhawkSetup -Algorithm SHA256).Hash -ne $windhawkHash) {
    throw 'Bundled Windhawk installer SHA256 verification failed.'
}
$signature = Get-AuthenticodeSignature -LiteralPath $windhawkSetup
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
    [string]$signature.SignerCertificate.Subject -notmatch 'Michael Maltsev|Open Source Developer') {
    throw "Bundled Windhawk installer signature verification failed: $($signature.Status)"
}

if (Test-Path -LiteralPath $buildRoot) {
    $resolvedBuild = [IO.Path]::GetFullPath($buildRoot)
    $resolvedExpectedParent = [IO.Path]::GetFullPath((Join-Path $project 'build'))
    if (-not $resolvedBuild.StartsWith($resolvedExpectedParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace unexpected build path: $resolvedBuild"
    }
    Remove-Item -LiteralPath $resolvedBuild -Recurse -Force
}
[void][IO.Directory]::CreateDirectory($payload)
[void][IO.Directory]::CreateDirectory($dist)

# Explicit allowlist: historical EXEs, ZIPs, logs, state files, screenshots and
# previous build output can never enter the installer by accident.
foreach ($file in @(
    $appName,
    "$appName.config",
    'MemoryCleanerTaskbarHost.exe',
    'MemoryCleanerFloat.ps1',
    'lightning.ico',
    '使用说明.md',
    'Install-And-Run.cmd',
    'Install-And-Run.ps1',
    'Install-WindhawkPortable.ps1',
    'TaskbarDiagnostic.ps1',
    'Run-Diagnostic.cmd',
    'Dependencies\windhawk_setup.exe',
    'WindhawkMod\安装或更新-Windhawk模块.ps1',
    'WindhawkMod\检查任务栏模块.ps1',
    'WindhawkMod\禁用-Windhawk模块.ps1',
    'WindhawkMod\memory-cleaner-taskbar-slot.dll',
    'WindhawkMod\memory-cleaner-taskbar-slot.wh.cpp'
)) {
    Copy-RequiredFile $file
}

$uninstallOutput = Join-Path $payload 'Uninstall.exe'
& $compiler /nologo /target:winexe /optimize+ /platform:x64 "/win32icon:$project\lightning.ico" "/out:$uninstallOutput" /reference:System.Windows.Forms.dll $uninstallSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $uninstallOutput -PathType Leaf)) {
    throw 'Failed to compile Uninstall.exe.'
}

$payloadHashes = Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($payload.Length + 1)
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
}
[IO.File]::WriteAllLines((Join-Path $payload 'SHA256.txt'), $payloadHashes, (New-Object Text.UTF8Encoding($false)))

Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $payloadZip) { Remove-Item -LiteralPath $payloadZip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($payload, $payloadZip, [IO.Compression.CompressionLevel]::Optimal, $false)

& $compiler /nologo /target:winexe /optimize+ /platform:x64 "/win32icon:$project\lightning.ico" "/out:$setupOutput" "/resource:$payloadZip,MemoryCleanerFloat.Payload.zip" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:Microsoft.CSharp.dll $setupSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $setupOutput -PathType Leaf)) {
    throw 'Failed to compile the one-click installer.'
}

$setupItem = Get-Item -LiteralPath $setupOutput
if ($setupItem.VersionInfo.FileVersion -ne $expectedAppVersion) {
    throw "Installer file version mismatch. Expected $expectedAppVersion."
}
$setupHash = (Get-FileHash -LiteralPath $setupOutput -Algorithm SHA256).Hash
[IO.File]::WriteAllText($hashOutput, "SHA256  $setupHash`r`nFILE    $($setupItem.Name)`r`n", (New-Object Text.UTF8Encoding($false)))

$oldPayloadApps = @(Get-ChildItem -LiteralPath $payload -Filter '内存释放任务栏工具-v*.exe')
if ($oldPayloadApps.Count -gt 0) {
    throw "Old application versions entered the payload: $($oldPayloadApps.Name -join ', ')"
}

[pscustomobject]@{
    Installer = $setupOutput
    SizeMB = [math]::Round($setupItem.Length / 1MB, 2)
    SHA256 = $setupHash
    PayloadFiles = @(Get-ChildItem -LiteralPath $payload -File -Recurse).Count
}
