$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'MemoryCleanerFloat.ps1'
$settingsPath = Join-Path $projectRoot 'settings.json'

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -ne $Actual) {
        throw "$Name failed: expected '$Expected', actual '$Actual'."
    }
}

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Name)
    if ($Text -notmatch $Pattern) {
        throw "$Name failed: pattern '$Pattern' was not found."
    }
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse failed: $($parseErrors[0].Message)"
}

$intervalFunction = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-AutoCleanupIntervalMinutes'
}, $true) | Select-Object -First 1
if ($null -eq $intervalFunction) { throw 'Get-AutoCleanupIntervalMinutes was not found.' }
Invoke-Expression $intervalFunction.Extent.Text

Assert-Equal 30 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{})) 'missing setting uses default'
Assert-Equal 30 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{ AutoCleanupIntervalMinutes = '' })) 'empty setting uses default'
Assert-Equal 30 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{ AutoCleanupIntervalMinutes = 'invalid' })) 'invalid setting uses default'
Assert-Equal 1 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{ AutoCleanupIntervalMinutes = 0 })) 'low direct-config value is clamped'
Assert-Equal 1 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{ AutoCleanupIntervalMinutes = 1 })) 'minimum interval'
Assert-Equal 30 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{ AutoCleanupIntervalMinutes = 30 })) 'default interval'
Assert-Equal 1440 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{ AutoCleanupIntervalMinutes = 1440 })) 'maximum interval'
Assert-Equal 1440 (Get-AutoCleanupIntervalMinutes ([pscustomobject]@{ AutoCleanupIntervalMinutes = 1441 })) 'high direct-config value is clamped'

$settings = Get-Content -Raw -Encoding UTF8 $settingsPath | ConvertFrom-Json
$configuredMinutes = [int]$settings.AutoCleanupIntervalMinutes
if ($configuredMinutes -lt 1 -or $configuredMinutes -gt 1440) {
    throw "configured interval failed: '$configuredMinutes' is outside 1-1440."
}

$source = Get-Content -Raw -Encoding UTF8 $scriptPath
Assert-Contains $source '\$script:autoCleanupTimer\.Add_Tick' 'timer tick handler'
Assert-Contains $source 'Run-UiCleanup' 'timer reuses UI cleanup entry point'
Assert-Contains $source 'newAutoCleanupMinutes -lt 1.+newAutoCleanupMinutes -gt 1440' 'settings range validation'
Assert-Contains $source '\$script:autoCleanupTimer\.Stop\(\)' 'timer shutdown or reset'
Assert-Contains $source 'automatic release triggered' 'automatic trigger logging'
Assert-Contains $source '\$script:cleanupTimeoutSeconds = 120' 'cleanup safety timeout allows slower computers'
Assert-Contains $source '\$sidecarScript = Join-Path \$script:AppRoot' 'cleanup uses the installed sidecar script'
Assert-Contains $source '-WindowStyle Hidden' 'cleanup worker is launched hidden'
Assert-Contains $source 'release worker script is missing' 'missing worker fails without launching another main window'
Assert-Contains $source '\$process\.StandardOutput\.ReadToEndAsync\(\)' 'worker stdout is drained asynchronously'
Assert-Contains $source '\$process\.StandardError\.ReadToEndAsync\(\)' 'worker stderr is drained asynchronously'
Assert-Contains $source '\$script:cleanupProcess\.WaitForExit\(2000\)' 'active worker is stopped when the window closes'
if ($source -match '\$process\.Standard(Output|Error)\.ReadToEnd\(\)') {
    throw 'cleanup worker failed: redirected output is read only after process exit, which can deadlock on a full pipe.'
}
$stdoutDrainIndex = $source.IndexOf('$process.StandardOutput.ReadToEndAsync()')
$pollStartIndex = $source.IndexOf('$script:cleanupPollTimer.Start()', $stdoutDrainIndex)
if ($stdoutDrainIndex -lt 0 -or $pollStartIndex -le $stdoutDrainIndex) {
    throw 'cleanup worker failed: redirected output must start draining before exit polling begins.'
}
if ($source -match 'StartInfo\.FileName\s*=\s*\$scriptPath' -or $source -match "'-end -RunOnce'") {
    throw 'cleanup worker failed: main executable fallback would open another application window.'
}

Write-Output 'PASS: auto-cleanup configuration, boundaries, non-blocking worker I/O, timer wiring, logging, and PowerShell syntax.'
