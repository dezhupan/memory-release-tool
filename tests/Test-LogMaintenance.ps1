$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'MemoryCleanerFloat.ps1'
$projectSettingsPath = Join-Path $projectRoot 'settings.json'
$testRoot = Join-Path $projectRoot 'build\test-log-maintenance'

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -ne $Actual) {
        throw "$Name failed: expected '$Expected', actual '$Actual'."
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "$Name failed." }
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

$functionNames = @(
    'Write-AppLog',
    'Get-DefaultSettings',
    'Save-Settings',
    'Get-Settings',
    'Get-LogRetentionDays',
    'Get-AppState',
    'Save-AppState',
    'Invoke-LogMaintenance',
    'Clear-AppLog'
)

foreach ($functionName in $functionNames) {
    $definition = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true) | Select-Object -First 1
    if ($null -eq $definition) { throw "$functionName was not found." }
    Invoke-Expression $definition.Extent.Text
}

Assert-Equal 7 (Get-LogRetentionDays ([pscustomobject]@{})) 'missing retention uses default'
Assert-Equal 7 (Get-LogRetentionDays ([pscustomobject]@{ LogRetentionDays = '' })) 'empty retention uses default'
Assert-Equal 7 (Get-LogRetentionDays ([pscustomobject]@{ LogRetentionDays = 'invalid' })) 'invalid retention uses default'
Assert-Equal 1 (Get-LogRetentionDays ([pscustomobject]@{ LogRetentionDays = 0 })) 'low direct-config retention is clamped'
Assert-Equal 1 (Get-LogRetentionDays ([pscustomobject]@{ LogRetentionDays = 1 })) 'minimum retention'
Assert-Equal 30 (Get-LogRetentionDays ([pscustomobject]@{ LogRetentionDays = 30 })) 'maximum retention'
Assert-Equal 30 (Get-LogRetentionDays ([pscustomobject]@{ LogRetentionDays = 31 })) 'high direct-config retention is clamped'

[void](New-Item -ItemType Directory -Path $testRoot -Force)
$script:SettingsPath = Join-Path $testRoot 'settings.json'
$script:LogPath = Join-Path $testRoot 'cleaner.log'
$script:StatePath = Join-Path $testRoot 'cleaner.state.json'

[pscustomobject]@{
    LogCleanupIntervalDays = 7
    LogRetentionDays = 2
} | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8

$now = Get-Date
$oldLine = '{0} old entry' -f $now.AddDays(-3).ToString('yyyy-MM-dd HH:mm:ss')
$currentLine = '{0} current entry' -f $now.ToString('yyyy-MM-dd HH:mm:ss')
@($oldLine, $currentLine, 'unparseable entry') | Set-Content -Path $script:LogPath -Encoding UTF8
[pscustomobject]@{ LastLogCleanupAt = $now.ToString('o') } | ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8

Invoke-LogMaintenance -Force
$maintainedLog = Get-Content -Path $script:LogPath -Raw -Encoding UTF8
Assert-True ($maintainedLog -notmatch 'old entry') 'forced maintenance removes expired entry'
Assert-Contains $maintainedLog 'current entry' 'forced maintenance keeps current entry'
Assert-Contains $maintainedLog 'unparseable entry' 'forced maintenance preserves unknown line'
Assert-Contains $maintainedLog 'retentionDays=2' 'forced maintenance records retention'

$lateOldLine = '{0} late old entry' -f $now.AddDays(-4).ToString('yyyy-MM-dd HH:mm:ss')
Add-Content -Path $script:LogPath -Value $lateOldLine -Encoding UTF8
Invoke-LogMaintenance
$notDueLog = Get-Content -Path $script:LogPath -Raw -Encoding UTF8
Assert-Contains $notDueLog 'late old entry' 'maintenance waits until daily check is due'

[pscustomobject]@{ LastLogCleanupAt = $now.AddDays(-2).ToString('o') } | ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8
Invoke-LogMaintenance
$dueLog = Get-Content -Path $script:LogPath -Raw -Encoding UTF8
Assert-True ($dueLog -notmatch 'late old entry') 'daily maintenance removes expired entry'

Clear-AppLog
$clearedLines = @(Get-Content -Path $script:LogPath -Encoding UTF8)
Assert-Equal 1 $clearedLines.Count 'manual clear leaves one audit entry'
Assert-Contains $clearedLines[0] 'log cleared manually' 'manual clear audit entry'

$projectSettings = Get-Content -Path $projectSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ([int]$projectSettings.LogRetentionDays -ge 1 -and [int]$projectSettings.LogRetentionDays -le 30) 'configured retention range'
Assert-Equal 1 ([int]$projectSettings.LogCleanupIntervalDays) 'daily maintenance configuration'

$source = Get-Content -Path $scriptPath -Raw -Encoding UTF8
Assert-Contains $source 'newLogRetentionDays -lt 1.+newLogRetentionDays -gt 30' 'settings retention validation'
Assert-Contains $source 'Invoke-LogMaintenance -Force' 'save applies retention immediately'
Assert-Contains $source '\$clearLogButton\.Add_Click' 'manual clear button wiring'
Assert-Contains $source '\$intervalDays = 1' 'daily maintenance schedule'

Write-Output 'PASS: log retention boundaries, immediate maintenance, daily schedule, manual clear, and UI wiring.'
