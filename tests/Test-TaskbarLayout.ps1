$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'MemoryCleanerFloat.ps1'

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -ne $Actual) { throw "$Name failed: expected '$Expected', actual '$Actual'." }
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "PowerShell parse failed: $($errors[0].Message)" }
$functionAst = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-TaskbarPlacement'
}, $true) | Select-Object -First 1
if ($null -eq $functionAst) { throw 'Resolve-TaskbarPlacement was not found.' }
Invoke-Expression $functionAst.Extent.Text

$layout = [pscustomobject]@{
    Left = 0; Top = 1540; Right = 2560; Bottom = 1600; Width = 2560; Height = 60
    ButtonLeft = 828; ButtonRight = 1705; TrayLeft = 2146; Dpi = 96
}
$left = Resolve-TaskbarPlacement -Layout $layout -Position left
Assert-Equal 8 $left.Left 'left placement starts after taskbar edge'
Assert-Equal 360 $left.Width 'left placement uses compact preferred width'
Assert-Equal 1543 $left.Top 'left placement vertical centering'

$right = Resolve-TaskbarPlacement -Layout $layout -Position right
Assert-Equal 1778 $right.Left 'right placement aligns compact module before tray'
Assert-Equal 360 $right.Width 'right placement uses compact preferred width'
Assert-Equal 2138 ($right.Left + $right.Width) 'right placement tray safety gap'

$compactLayout = [pscustomobject]@{
    Left = 0; Top = 1040; Right = 1920; Bottom = 1080; Width = 1920; Height = 40
    ButtonLeft = 200; ButtonRight = 1400; TrayLeft = 1660; Dpi = 144
}
$compact = Resolve-TaskbarPlacement -Layout $compactLayout -Position right
Assert-Equal 244 $compact.Width 'narrow gap uses compact width'
Assert-Equal 144 $compact.Dpi 'taskbar DPI is preserved'

$blockedLayout = [pscustomobject]@{
    Left = 0; Top = 1040; Right = 1920; Bottom = 1080; Width = 1920; Height = 40
    ButtonLeft = 150; ButtonRight = 1500; TrayLeft = 1670; Dpi = 96
}
Assert-Equal $null (Resolve-TaskbarPlacement -Layout $blockedLayout -Position right) 'insufficient gap hides status bar'

Write-Output 'PASS: left, right, compact, DPI, safety-gap, and insufficient-space taskbar placement.'
