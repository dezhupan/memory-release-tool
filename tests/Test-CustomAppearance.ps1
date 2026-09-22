$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'MemoryCleanerFloat.ps1'
$settingsPath = Join-Path $projectRoot 'settings.json'
$samplePath = Join-Path $projectRoot 'portrait-cutout.png'
$normalizedPath = Join-Path $projectRoot 'custom-appearance.png'

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "$Name failed." }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Name)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw "$Name failed: no exception was raised." }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Drawing

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "PowerShell parse failed: $($parseErrors[0].Message)" }

$imageInfoFunction = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-AppearanceBitmapInfo'
}, $true) | Select-Object -First 1
if ($null -eq $imageInfoFunction) { throw 'Get-AppearanceBitmapInfo was not found.' }
Invoke-Expression $imageInfoFunction.Extent.Text

$backgroundFunctions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Get-BackgroundColorHex', 'Get-BackgroundTransparency', 'Get-BackgroundAlphaPercent', 'Test-TaskbarEjectSuppressed')
}, $true)
if ($backgroundFunctions.Count -ne 4) { throw 'Background color and embedded-mode guard helper functions were not found.' }
foreach ($function in $backgroundFunctions) { Invoke-Expression $function.Extent.Text }

$sampleInfo = Get-AppearanceBitmapInfo -Path $samplePath
Assert-True ($sampleInfo.HasTransparency -eq $true) 'transparent sample detection'
Assert-True ($sampleInfo.PixelWidth -gt 100 -and $sampleInfo.PixelHeight -gt 100) 'transparent sample dimensions'

$normalizedInfo = Get-AppearanceBitmapInfo -Path $normalizedPath
Assert-True ($normalizedInfo.HasTransparency -eq $true) 'normalized image transparency'
Assert-True ($normalizedInfo.PixelWidth -eq 731 -and $normalizedInfo.PixelHeight -eq 858) 'transparent-margin crop'

$testAssetDir = Join-Path $projectRoot 'build\test-assets'
[void](New-Item -ItemType Directory -Path $testAssetDir -Force)
$sourceBitmap = New-Object System.Drawing.Bitmap(24, 18)
try {
    $graphics = [System.Drawing.Graphics]::FromImage($sourceBitmap)
    try { $graphics.Clear([System.Drawing.Color]::CornflowerBlue) } finally { $graphics.Dispose() }
    $formatCases = @(
        @{ Name = 'JPEG'; Path = (Join-Path $testAssetDir 'appearance-test.jpg'); Format = [System.Drawing.Imaging.ImageFormat]::Jpeg },
        @{ Name = 'BMP'; Path = (Join-Path $testAssetDir 'appearance-test.bmp'); Format = [System.Drawing.Imaging.ImageFormat]::Bmp },
        @{ Name = 'GIF'; Path = (Join-Path $testAssetDir 'appearance-test.gif'); Format = [System.Drawing.Imaging.ImageFormat]::Gif },
        @{ Name = 'TIFF'; Path = (Join-Path $testAssetDir 'appearance-test.tiff'); Format = [System.Drawing.Imaging.ImageFormat]::Tiff }
    )
    foreach ($case in $formatCases) {
        $sourceBitmap.Save($case.Path, $case.Format)
        $info = Get-AppearanceBitmapInfo -Path $case.Path
        Assert-True ($info.PixelWidth -eq 24 -and $info.PixelHeight -eq 18) "$($case.Name) decode"
        Assert-True ($info.HasTransparency -eq $false) "$($case.Name) opaque detection"
    }
} finally {
    $sourceBitmap.Dispose()
}

Assert-Throws { Get-AppearanceBitmapInfo -Path $scriptPath | Out-Null } 'unsupported file rejection'

$source = Get-Content -Raw -Encoding UTF8 $scriptPath
$xamlMatch = [regex]::Match($source, '\[xml\]\$xaml = @"\r?\n(?<xaml>.*?)\r?\n"@', [System.Text.RegularExpressions.RegexOptions]::Singleline)
Assert-True $xamlMatch.Success 'XAML block discovery'
[xml]$xaml = $xamlMatch.Groups['xaml'].Value
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
try {
    Assert-True ($null -ne $window.FindName('DefaultView')) 'default view'
    Assert-True ($null -ne $window.FindName('CustomView')) 'custom view'
    Assert-True ($null -ne $window.FindName('CustomAppearanceImage')) 'custom image control'
    Assert-True ($null -ne $window.FindName('CustomStatusText')) 'custom status control'
} finally {
    $window.Close()
}

$settings = Get-Content -Raw -Encoding UTF8 $settingsPath | ConvertFrom-Json
Assert-True ($settings.UseCustomAppearance -eq $false) 'default appearance remains enabled'
Assert-True ($settings.CustomAppearanceReady -eq $false) 'draft image is not treated as imported'
Assert-True ([string]$settings.CustomAppearanceFile -eq 'custom-appearance.png') 'relative custom image setting'
Assert-True ($source -match 'ImageFormats[^\r\n]+WebP') 'WebP format remains documented'
Assert-True ($source -match 'Save-NormalizedAppearanceImage') 'normalized local image import'
Assert-True ($source -match '\$script:customAppearanceActive -or') 'custom-image click cleanup wiring'
Assert-True ((Get-BackgroundColorHex ([pscustomobject]@{ BackgroundColor = '#12abEF' })) -eq '#12ABEF') 'background color normalization'
Assert-True ((Get-BackgroundColorHex ([pscustomobject]@{ BackgroundColor = 'invalid' })) -eq '#303033') 'invalid background color fallback'
Assert-True ((Get-BackgroundTransparency ([pscustomobject]@{ BackgroundOpacity = 1 })) -eq 20) 'background transparency minimum'
Assert-True ((Get-BackgroundTransparency ([pscustomobject]@{ BackgroundOpacity = 100 })) -eq 90) 'background transparency maximum'
Assert-True ((Get-BackgroundAlphaPercent ([pscustomobject]@{ BackgroundOpacity = 90 })) -eq 10) 'background transparency converts to native alpha'
Assert-True (Test-TaskbarEjectSuppressed -TaskbarModeActive $true -GuardUntil (Get-Date).AddSeconds(1)) 'appearance update suppresses synthetic eject while embedded'
Assert-True (-not (Test-TaskbarEjectSuppressed -TaskbarModeActive $false -GuardUntil (Get-Date).AddSeconds(1))) 'floating mode does not suppress eject handling'
Assert-True (-not (Test-TaskbarEjectSuppressed -TaskbarModeActive $true -GuardUntil (Get-Date).AddSeconds(-1))) 'expired appearance guard allows real eject handling'
Assert-True ($source -match 'BackgroundAppearance') 'background color appearance option'
Assert-True ($source -match 'System\.Windows\.Forms\.ColorDialog') 'native color picker'
Assert-True ($source -match 'UseBackgroundColor = \(\$script:uiSettings\.UseBackgroundColor -eq \$true\)') 'background appearance is sent to the embedded module'
Assert-True ($source -match 'Protect-EmbeddedModeForAppearanceUpdate\s+Apply-UiSettings') 'saving appearance protects the embedded display mode'
Assert-True ($source -match '(?s)Test-TaskbarEjectSuppressed.+Convert-TaskbarSlotToFloating') 'synthetic eject is filtered before switching to floating mode'
Assert-True ($source -match 'VerticalScrollBarVisibility.*Auto') 'settings remain usable when DPI reduces available height'

Write-Output 'PASS: default/custom appearance, alpha cropping, PNG/JPEG/BMP/GIF/TIFF decoding, invalid input, XAML controls, and click wiring.'
