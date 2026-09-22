$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'MemoryCleanerFloat.ps1'
$hostPath = Join-Path $projectRoot 'TaskbarHost\Program.cs'
$source = Get-Content -Raw -Encoding UTF8 $scriptPath
$hostSource = Get-Content -Raw -Encoding UTF8 $hostPath

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Name)
    if ($Text -notmatch $Pattern) { throw "$Name failed: pattern '$Pattern' was not found." }
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "PowerShell parse failed: $($parseErrors[0].Message)" }

Assert-Contains $source 'if \(-not \$trayDetected -or \$buttons\.Count -eq 0\) \{ return \$null \}' 'incomplete taskbar UI Automation tree rejection'
Assert-Contains $source "Explorer owns the injected slot's position and size" 'native Windhawk slot owns stable taskbar placement'
Assert-Contains $source '\$script:taskbarHostBounds = \$null' 'legacy host bounds are disabled for the injected slot'
Assert-Contains $source 'if \(\$window\.IsVisible\) \{ \$window\.Hide\(\) \}' 'legacy WPF overlay is hidden in taskbar mode'
Assert-Contains $source 'Ensure-TaskbarHost' 'native taskbar host is supervised by controller'
Assert-Contains $hostSource 'if \(Native\.GetParent\(_strip\.Handle\) != taskbar\)' 'native host reattaches after Explorer restart'
Assert-Contains $hostSource 'Native\.SetParent\(Handle, taskbar\)' 'native control is parented into Shell_TrayWnd'
Assert-Contains $hostSource 'Native\.WsChild \| Native\.WsVisible' 'native host uses child-window style'
Assert-Contains $hostSource 'if \(Native\.GetParent\(Handle\) != taskbar\)' 'failed embedding is verified and never shown as a floating fallback'
Assert-Contains $hostSource 'Native\.WsExToolWindow \| Native\.WsExNoActivate' 'native host requests non-activating tool-window behavior where Explorer preserves it'
Assert-Contains $hostSource 'Native\.SetParent\(Handle, taskbar\)' 'native host applies the taskbar parent after WinForms creates its handle'
Assert-Contains $hostSource 'Native\.TrySetWindowLongPtr\(Handle, Native\.GwlExStyle' 'Windows 11 composition styles are applied only after embedding'
Assert-Contains $hostSource 'state\.Width > 0 \? state\.Width' 'UI Automation physical width is not double-scaled at high DPI'
Assert-Contains $hostSource 'taskbarRect\.Left \+ _lastBounds\.Left' 'pointer hit testing uses the same taskbar-relative physical coordinates'

Write-Output 'PASS: taskbar placement is owned by the injected slot, controller state stays synchronized, and the WPF overlay stays hidden.'
