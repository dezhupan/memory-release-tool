$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$controllerPath = Join-Path $project 'MemoryCleanerFloat.ps1'
$modulePath = Join-Path $project 'WindhawkMod\memory-cleaner-taskbar-slot.wh.cpp'
$moduleBinaryPath = Join-Path $project 'WindhawkMod\memory-cleaner-taskbar-slot.dll'
$controller = Get-Content -LiteralPath $controllerPath -Raw -Encoding UTF8
$module = Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

Assert-Contains $module 'SystemTrayFrameGrid' 'module targets the real Windows 11 taskbar tray grid'
Assert-Contains $module 'ColumnDefinitions\(\)\.InsertAt\(0,' 'module inserts a dedicated grid column'
Assert-Contains $module 'ColumnDefinitions\(\)\.InsertAt\(1,' 'module inserts an in-layout drag spacer column'
Assert-Contains $module 'Grid::SetColumn\(child, Grid::GetColumn\(child\) \+ 2\)' 'existing tray children are shifted to reserve the module and drag spacer'
Assert-Contains $module 'childColumn - instance\.insertedColumnCount' 'unload restores original tray child columns'
Assert-Contains $module 'Local\\\\MemoryCleanerFloat_TaskbarClean' 'left-click cleanup event is fixed and local'
Assert-Contains $module 'Local\\\\MemoryCleanerFloat_TaskbarMenu' 'right-click menu event is fixed and local'
Assert-Contains $module 'Local\\\\MemoryCleanerFloat_TaskbarPositionChanged' 'drag position event is fixed and local'
Assert-Contains $module 'pendingCleanUntil' 'click feedback is shown before controller processing'
Assert-Contains $module 'PointerPressed' 'holding the left button starts drag tracking'
Assert-Contains $module 'PointerMoved' 'horizontal pointer movement updates the in-taskbar position'
Assert-Contains $module 'PointerReleased' 'releasing the left button completes the drag'
Assert-Contains $module 'dragTimer\.Interval\(std::chrono::milliseconds\(16\)\)' 'pressed-button cursor tracking keeps dragging responsive'
Assert-Contains $module 'GetAsyncKeyState\(VK_LBUTTON\)' 'drag completion is detected even if taskbar XAML suppresses a release event'
Assert-Contains $module 'RasterizationScale' 'physical cursor movement is converted to taskbar XAML units'
Assert-Contains $module 'kDragThreshold = 6\.0' 'click and drag use a movement threshold'
Assert-Contains $module 'suppressTapUntil' 'a completed drag cannot accidentally trigger cleanup'
Assert-Contains $module 'WriteTaskbarOffset' 'the selected taskbar position is persisted'
Assert-Contains $module 'taskbar-ready\.json' 'module publishes a cross-machine ready marker after real injection'
Assert-Contains $module 'WriteReadyMarker' 'ready marker is refreshed while the taskbar slot is alive'
Assert-Contains $module '@version\s+1\.6\.2' 'module source metadata uses the current module version'
Assert-Contains $module '\\"Version\\":\\"1\.6\.2\\"' 'ready marker uses the current module version'
Assert-Contains $module 'kReservedTaskbarWidth = 360\.0' 'dragging preserves a safe taskbar button area'
$busyText = -join ([char]0x6B63, [char]0x5728, [char]0x6E05, [char]0x7406, [char]0x5185, [char]0x5B58, [char]0x2026)
Assert-Contains $module '6B63\\u5728\\u6E05\\u7406\\u5185\\u5B58\\u2026' 'busy text explicitly describes memory cleaning'
Assert-Contains $module 'Width="360" Height="52"' 'taskbar slot uses the compact width while preserving v1.9 height'
Assert-Contains $module 'CornerRadius="18" BorderThickness="1" BorderBrush="#32FFFFFF"' 'v1.9 capsule radius and border are exact'
Assert-Contains $module 'Color="#EC303033" Offset="0"' 'v1.9 top gradient color is exact'
Assert-Contains $module 'Color="#EC1C1C1E" Offset="1"' 'v1.9 bottom gradient color is exact'
Assert-Contains $module 'GetNamedBoolean\(L"UseBackgroundColor", false\)' 'module reads the optional background color mode'
Assert-Contains $module 'GetNamedNumber\(L"BackgroundOpacity", 72\)' 'module reads translucent background opacity'
Assert-Contains $module 'std::clamp\(opacity, 20\.0, 90\.0\)' 'module clamps background opacity to a translucent range'
Assert-Contains $module 'backgroundColorBrush\.Color\(backgroundColor\)' 'module updates the pre-created translucent color brush inside the native slot'
Assert-Contains $module 'backgroundColorLayer\.Visibility\(Visibility::Collapsed\)' 'module reveals the exact v1.9 gradient when color mode is disabled'
Assert-Contains $module 'Width="30" Height="30" Margin="0,0,8,0"' 'v1.9 lightning button spacing is exact'
Assert-Contains $module 'Data="M15,3 L7,15 H13 L11,25 L21,11 H15 Z"' 'v1.9 lightning vector is exact'
Assert-Contains $module 'Foreground="#FF64D2FF"' 'v1.9 download accent is exact'
Assert-Contains $module 'Foreground="#FF30D158"' 'v1.9 upload accent is exact'
Assert-Contains $controller 'LocalApplicationData' 'controller supports a per-user Windhawk location'
Assert-Contains $controller "'D:\\Windhawk\\windhawk\.exe'" 'controller can reuse an existing D drive Windhawk installation'
Assert-Contains $controller 'Request-WindhawkTaskbarInjection' 'controller asks Explorer to initialize the injected XAML module'
Assert-Contains $controller 'Set-WindhawkHiddenRuntimeSettings' 'controller keeps Windhawk UI and tray entry hidden'
Assert-Contains $controller "Arguments = '-exit -wait'" 'controller exits Windhawk together with the memory tool'
Assert-Contains $controller 'Stop-WindhawkEngine\s+\$script:notifyIcon.Visible = \$false' 'WPF shutdown synchronizes Windhawk exit'
Assert-Contains $controller '\$timer.Stop\(\)\s+Stop-WindhawkEngine' 'WinForms fallback synchronizes Windhawk exit'
Assert-Contains $controller "'Working' \{ return -join \(\[char\]0x6B63, \[char\]0x5728, \[char\]0x6E05, \[char\]0x7406, \[char\]0x5185, \[char\]0x5B58" 'controller sends the Chinese cleaning status'
Assert-Contains $controller 'if \(\$script:cleanupInProgress -or \$script:statusOverride\) \{ Write-TaskbarHostState \}' 'busy and result state stay fresh while displayed'
Assert-Contains $controller 'function Show-AppContextMenu' 'all menu entry points use one focus-aware menu function'
Assert-Contains $controller 'EnableWindowsFormsInterop\(\)' 'WPF dispatches keyboard input to the WinForms context menu'
Assert-Contains $controller 'GetAsyncKeyState\(0x1B\)' 'Escape is monitored while the context menu is visible'
Assert-Contains $controller '\$escapeState -band 0x0001' 'short Escape presses are retained between timer ticks'
Assert-Contains $controller 'ToolStripDropDownCloseReason\]::Keyboard' 'Escape closes the context menu as a keyboard cancellation'
Assert-Contains $controller 'TaskbarOffset = 0' 'taskbar drag offset has a stable default'
Assert-Contains $controller 'function Sync-TaskbarDragPosition' 'controller synchronizes the dragged taskbar position'
Assert-Contains $controller 'taskbar-position\.json' 'drag position is stored in the local application state directory'
Assert-Contains $controller 'taskbar-ready\.json' 'controller observes real Windhawk injection readiness'
Assert-Contains $controller "TotalMinutes -lt 10" 'first-run injection retries cover slow symbol resolution'
Assert-Contains $controller '0x80L' 'context menu uses tool-window style instead of creating a taskbar button'
Assert-Contains $controller 'SetWindowLongPtr\(\$menuHandle, -8' 'context menu is owned by the hidden controller window'
Assert-NotContains $controller 'ShowInTaskbar\s*=\s*\$true' 'neither embedded nor floating mode creates an application taskbar button'
Assert-Contains $controller 'function Set-WpfTaskbarButtonVisibility' 'floating mode enforces native no-taskbar window styles'
Assert-Contains $controller '0x0037' 'native style changes are refreshed without moving or activating the window'
Assert-Contains $controller 'function Get-TaskbarDropInfo' 'floating drag detects the native taskbar drop zone'
Assert-Contains $controller 'function Convert-FloatingDropToTaskbar' 'dropping the floating panel switches to true embedding'
Assert-Contains $controller "DisplayMode = 'taskbar'" 'drop-to-taskbar persists embedded display mode'
Assert-Contains $controller 'TaskbarOffset = \$dropOffset' 'drop position is converted into the embedded taskbar offset'
Assert-Contains $controller '\$window\.Opacity = if \(\$script:dragOverTaskbar\)' 'dragging over the taskbar provides temporary snap feedback'
Assert-NotContains $controller '\$window\.AllowsTransparency\s*=' 'settings refresh never mutates AllowsTransparency after the HWND exists'
Assert-Contains $controller '\$slotWidth = 360\.0' 'floating drop placement uses the compact embedded width'
Assert-Contains $controller "taskbarModuleVersion = '1\.6\.2'" 'controller pins the current module version'
Assert-Contains $controller 'readyState\.Version -eq \$script:taskbarModuleVersion' 'controller accepts readiness only from the current module version'

if (-not (Test-Path -LiteralPath $moduleBinaryPath -PathType Leaf)) { throw 'FAIL: compiled taskbar module is missing' }
$binaryBytes = [IO.File]::ReadAllBytes($moduleBinaryPath)
$binaryUnicode = [Text.Encoding]::Unicode.GetString($binaryBytes)
if (-not $binaryUnicode.Contains('{"Version":"1.6.2","ExplorerPid":')) { throw 'FAIL: compiled module ready marker version is not current' }
Write-Host 'PASS: compiled module contains the current 1.6.2 ready marker version'

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($controllerPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "FAIL: controller parse error: $($errors[0].Message)" }
Write-Host 'PASS: controller PowerShell parses successfully'
Write-Host 'Windhawk true-embedding tests passed.'
