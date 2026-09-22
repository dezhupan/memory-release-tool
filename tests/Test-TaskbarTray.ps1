$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'MemoryCleanerFloat.ps1'
$hostPath = Join-Path $projectRoot 'TaskbarHost\Program.cs'

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Name)
    if ($Text -notmatch $Pattern) {
        throw "$Name failed: pattern '$Pattern' was not found."
    }
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse failed: $($parseErrors[0].Message)"
}

$source = Get-Content -Raw -Encoding UTF8 $scriptPath
$hostSource = Get-Content -Raw -Encoding UTF8 $hostPath
Assert-Contains $source 'ShowInTaskbar="False"' 'WPF taskbar status avoids an application button'
Assert-Contains $source '\$form\.ShowInTaskbar = \$false' 'WinForms fallback avoids an application taskbar button'
Assert-Contains $source '\$script:notifyIcon\.Add_MouseClick' 'tray left-click handler'
Assert-Contains $source 'Toggle-MainWindow' 'WPF show/hide behavior'
Assert-Contains $source 'Toggle-MainForm' 'WinForms fallback show/hide behavior'
Assert-Contains $source 'Update-TrayTooltip' 'tray memory tooltip'
Assert-Contains $source 'TaskbarView' 'taskbar status view'
Assert-Contains $source 'Get-TaskbarLayout' 'taskbar UI Automation layout discovery'
Assert-Contains $source 'Get-TaskbarPlacement' 'left and right free-space placement'
Assert-Contains $source "TaskbarPosition = 'left'" 'default left placement'
Assert-Contains $source "Set-DisplayMode -Mode 'taskbar' -Position 'right'" 'right placement menu action'
Assert-Contains $source '\$root\.Add_PreviewMouseLeftButtonUp' 'whole taskbar status uses a window-level fixed-position click handler'
Assert-Contains $source 'Run-UiCleanup' 'taskbar click uses cleanup entry point'
Assert-Contains $source 'taskbarPlacementTimer' 'dynamic taskbar relocation'
Assert-Contains $source 'TaskbarCapsule' 'Apple-style dark capsule surface'
Assert-Contains $source 'TaskbarContentPanel' 'stable taskbar data layout'
Assert-Contains $source 'TaskbarMessagePanel' 'in-place cleanup status layout'
Assert-Contains $source 'SizeToContent="Manual"' 'taskbar status cannot resize itself to transient text'
Assert-Contains $source 'if \(\$null -eq \$layout\)' 'incomplete taskbar samples are handled separately from insufficient space'
Assert-Contains $source 'Write-TaskbarHostState' 'taskbar metrics are sent to the native host'
Assert-Contains $source 'Ensure-TaskbarHost' 'native taskbar host lifecycle is supervised'
Assert-Contains $source '\$script:taskbarHostCleanEvent\.WaitOne\(0\)' 'native taskbar click reaches the cleanup entry point'
Assert-Contains $source '\$script:taskbarHostMenuEvent\.WaitOne\(0\)' 'native taskbar right-click reaches the tray menu'
Assert-Contains $source "'Working' \{ return -join \(\[char\]0x6B63, \[char\]0x5728, \[char\]0x6E05, \[char\]0x7406, \[char\]0x5185, \[char\]0x5B58" 'Chinese in-progress text explicitly says memory is being cleaned'
Assert-Contains $source 'Busy = \[bool\]\$script:cleanupInProgress' 'controller sends the busy state to the native host'
Assert-Contains $source '\$app\.MainWindow = \$window' 'WPF message loop owns the controller window without auto-showing it'
Assert-Contains $source 'if \(-not \$script:taskbarModeActive -and -not \$window\.IsVisible\)' 'only floating mode is shown during startup'
Assert-Contains $source '\$app\.Run\(\)' 'WPF starts a windowless message loop for embedded mode'
if ($source -match '\$app\.Run\(\$window\)') { throw 'startup visibility failed: taskbar mode would auto-show the floating window.' }
Assert-Contains $hostSource 'if \(_state\.Busy\)' 'native host blocks repeated cleanup clicks while busy'
Assert-Contains $hostSource 'Cursors\.WaitCursor' 'native host shows a busy cursor during cleanup'
Assert-Contains $source "'CleanupFreed' \{ return \(-join \(\[char\]0x5DF2, \[char\]0x91CA, \[char\]0x653E" 'successful cleanup result is explicit and readable'
Assert-Contains $source "'CleanupNotNeeded' \{ return \(-join \(\[char\]0x65E0, \[char\]0x9700, \[char\]0x6E05, \[char\]0x7406" 'no-op cleanup result explains why nothing changed'
Assert-Contains $source 'if \(-not \$script:taskbarModeActive\) \{ Apply-WindowLayout \}' 'taskbar cleanup never applies floating-window dimensions'
Assert-Contains $source 'EventWaitHandle' 'single-instance activation event'
Assert-Contains $source '\$script:activationEvent\.Set\(\)' 'second-launch activation signal'
Assert-Contains $source '\$script:activationEvent\.WaitOne\(0\)' 'running-instance activation receiver'
Assert-Contains $source '\$sidecarScript = Join-Path \$script:AppRoot' 'compiled app uses the hidden sidecar cleanup worker'
Assert-Contains $source '-WindowStyle Hidden' 'cleanup worker is hidden'

Write-Output 'PASS: taskbar status, left/right placement, whole-bar cleanup click, dynamic relocation, tray fallback, and single-instance activation wiring.'
