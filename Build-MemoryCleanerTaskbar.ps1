[CmdletBinding()]
param(
    [ValidatePattern('^\d+(\.\d+){0,3}$')]
    [string]$Version = '3.15.3'
)

$ErrorActionPreference = 'Stop'

# Keep every released version intact for traceability. User-facing shortcuts and
# pins must target the stable file below so upgrades cannot invalidate them.
$appRoot = Split-Path -Parent $PSCommandPath
$source = Join-Path $appRoot 'MemoryCleanerFloat.ps1'
$icon = Join-Path $appRoot 'lightning.ico'
$compiler = Join-Path $appRoot 'build\tools\ps2exe\ps2exe.ps1'
$versionedName = "内存释放任务栏工具-v$Version.exe"
$versionedPath = Join-Path $appRoot $versionedName
$stablePath = Join-Path $appRoot '内存释放任务栏工具.exe'

foreach ($path in @($source, $icon, $compiler)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required build input is missing: $path"
    }
}

$versionParts = $Version.Split('.')
while ($versionParts.Count -lt 4) { $versionParts += '0' }
$assemblyVersion = ($versionParts | Select-Object -First 4) -join '.'
$taskTempRoot = Join-Path ([IO.Path]::GetTempPath()) ("MemoryCleanerFloat-build-{0}" -f [guid]::NewGuid().ToString('N'))
$tempExe = Join-Path $taskTempRoot $versionedName

try {
    [void][IO.Directory]::CreateDirectory($taskTempRoot)
    . $compiler
    Invoke-ps2exe -inputFile $source -outputFile $tempExe -x64 -STA -noConsole -iconFile $icon -title '内存释放任务栏工具' -description '内存释放任务栏工具' -product 'MemoryCleanerFloat' -version $assemblyVersion -configFile -longPaths

    if (-not (Test-Path -LiteralPath $tempExe -PathType Leaf) -or (Get-Item -LiteralPath $tempExe).Length -lt 100KB) {
        throw 'The compiler did not produce a valid executable.'
    }

    # Publish only after the complete temporary build has passed validation.
    Copy-Item -LiteralPath $tempExe -Destination $versionedPath -Force
    Copy-Item -LiteralPath $tempExe -Destination $stablePath -Force
    Copy-Item -LiteralPath "$tempExe.config" -Destination "$versionedPath.config" -Force
    Copy-Item -LiteralPath "$tempExe.config" -Destination "$stablePath.config" -Force

    Get-Item -LiteralPath $versionedPath, $stablePath | Select-Object Name, Length, LastWriteTime, @{ Name = 'Version'; Expression = { $_.VersionInfo.FileVersion } }
}
finally {
    if (Test-Path -LiteralPath $taskTempRoot) {
        Remove-Item -LiteralPath $taskTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
