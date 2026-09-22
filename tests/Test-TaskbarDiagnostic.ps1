$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$diagnosticPath = Join-Path $project 'TaskbarDiagnostic.ps1'
$launcherPath = Join-Path $project 'Run-Diagnostic.cmd'

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($diagnosticPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "FAIL: diagnostic parse error: $($errors[0].Message)" }
Write-Host 'PASS: diagnostic PowerShell parses successfully'

$launcherBytes = [System.IO.File]::ReadAllBytes($launcherPath)
if (@($launcherBytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
    throw 'FAIL: Run-Diagnostic.cmd must remain ASCII-only'
}
Write-Host 'PASS: diagnostic launcher is ASCII-only'

$source = Get-Content -LiteralPath $diagnosticPath -Raw -Encoding UTF8
foreach ($pattern in @(
    'TaskbarDiagnostic\.txt',
    'DesktopDirectory',
    '\$env:TEMP',
    'Module runtime status',
    'Module runtime task',
    'Ready marker active',
    'Likely cause',
    'Unable to write TaskbarDiagnostic\.txt'
)) {
    if ($source -notmatch $pattern) { throw "FAIL: missing diagnostic behavior: $pattern" }
}
Write-Host 'PASS: diagnostic covers output fallback, Windhawk runtime, readiness, and explicit failure'

$outputDirectory = Join-Path (Join-Path $project 'build') ('diagnostic-test-' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($outputDirectory)
& $diagnosticPath -ReportDirectory $outputDirectory -NoOpen -Quiet
$reportPath = Join-Path $outputDirectory 'TaskbarDiagnostic.txt'
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'FAIL: diagnostic report was not generated' }
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
foreach ($key in @('Diagnostic version: 2.2', 'Windows build:', 'One-click bootstrap exists:', 'Bundled Windhawk installer exists:', 'Windhawk installer cache exists:', 'Expected module version: 1.6.2', 'Windhawk root:', 'Module config exists:', 'Likely cause:')) {
    if ($report -notlike "*$key*") { throw "FAIL: report is missing $key" }
}
Write-Host "PASS: real diagnostic report generated at $reportPath"
Write-Host 'Taskbar diagnostic tests passed.'
