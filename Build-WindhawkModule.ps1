[CmdletBinding()]
param(
    [string]$WindhawkRoot = 'D:\Windhawk'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSCommandPath
$source = Join-Path $project 'WindhawkMod\memory-cleaner-taskbar-slot.wh.cpp'
$output = Join-Path $project 'WindhawkMod\memory-cleaner-taskbar-slot.dll'
$compilerRoot = Join-Path $WindhawkRoot 'Compiler'
$compiler = Join-Path $compilerRoot 'bin\clang++.exe'
$windhawkLibrary = Get-ChildItem -LiteralPath (Join-Path $WindhawkRoot 'Engine') -Filter 'windhawk.lib' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq '64' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
$windhawkApi = Join-Path $compilerRoot 'include\windhawk_api.h'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('MemoryCleanerFloat-module-' + [guid]::NewGuid().ToString('N'))
$tempOutput = Join-Path $tempRoot 'memory-cleaner-taskbar-slot.dll'

foreach ($path in @($source, $compiler, $windhawkLibrary, $windhawkApi)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required module build input is missing: $path" }
}

try {
    [void][IO.Directory]::CreateDirectory($tempRoot)
    $arguments = @(
        '-std=c++23', '-O2', '-shared',
        '-DUNICODE', '-D_UNICODE', '-DWINVER=0x0A00', '-D_WIN32_WINNT=0x0A00', '-D_WIN32_IE=0x0A00',
        '-DNTDDI_VERSION=0x0A000008', '-D__USE_MINGW_ANSI_STDIO=0', '-DWH_MOD',
        '-DWH_MOD_ID=L"memory-cleaner-taskbar-slot"', '-DWH_MOD_VERSION=L"1.6.2"',
        $windhawkLibrary, '-x', 'c++', $source, '-include', 'windhawk_api.h',
        '-target', 'x86_64-w64-mingw32', '-Wl,--export-all-symbols',
        '-lole32', '-loleaut32', '-lruntimeobject', '-o', $tempOutput
    )
    & $compiler @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempOutput -PathType Leaf)) {
        throw "Windhawk module compilation failed with exit code $LASTEXITCODE."
    }
    if ((Get-Item -LiteralPath $tempOutput).Length -lt 100KB) { throw 'Compiled module is unexpectedly small.' }
    Copy-Item -LiteralPath $tempOutput -Destination $output -Force
    [pscustomobject]@{
        Module = $output
        SizeKB = [math]::Round((Get-Item -LiteralPath $output).Length / 1KB, 2)
        SHA256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
        Version = '1.6.2'
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
