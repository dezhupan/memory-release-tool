$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'TaskbarHost\Program.cs'
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8

function Assert-Contains([string]$Pattern, [string]$Message) {
    if ($source -notmatch $Pattern) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

Assert-Contains 'DefaultWidth = 430' 'reference capsule width is fixed at 430'
Assert-Contains 'DefaultHeight = 52' 'reference capsule height is fixed at 52'
Assert-Contains 'DrawLightningButton' 'blue lightning button is drawn'
Assert-Contains 'new PointF\(' 'lightning glyph uses a stable vector path'
Assert-Contains 'DrawMetric\(g,.*_state\.Download' 'download field is rendered'
Assert-Contains 'DrawMetric\(g,.*_state\.Upload' 'upload field is rendered'
Assert-Contains '100, 210, 255' 'download value uses cyan accent'
Assert-Contains '48, 209, 88' 'upload value uses green accent'
Assert-Contains 'DrawDivider\(g, x, sy\)' 'column separators use stable coordinates'

$snapshotPath = Join-Path $projectRoot 'build\visual-v2.1-diagnostic.png'
if (Test-Path -LiteralPath $snapshotPath) {
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Bitmap]::FromFile($snapshotPath)
    try {
        if ($image.Width -ne 430 -or $image.Height -ne 52) {
            throw "FAIL: snapshot size is $($image.Width)x$($image.Height), expected 430x52"
        }

        $bluePixels = 0
        $cyanPixels = 0
        $greenPixels = 0
        for ($y = 0; $y -lt $image.Height; $y += 2) {
            for ($x = 0; $x -lt $image.Width; $x += 2) {
                $pixel = $image.GetPixel($x, $y)
                if ($x -lt 50 -and $pixel.B -gt 180 -and $pixel.B -gt ($pixel.R + 70)) { $bluePixels++ }
                if ($x -gt 220 -and $x -lt 335 -and $pixel.B -gt 160 -and $pixel.G -gt 130) { $cyanPixels++ }
                if ($x -gt 320 -and $pixel.G -gt 130 -and $pixel.G -gt ($pixel.R + 55)) { $greenPixels++ }
            }
        }
        if ($bluePixels -lt 30) { throw 'FAIL: blue lightning circle was not detected' }
        if ($cyanPixels -lt 3) { throw 'FAIL: cyan download text was not detected' }
        if ($greenPixels -lt 3) { throw 'FAIL: green upload text was not detected' }
        Write-Host 'PASS: rendered snapshot contains the expected icon and accent colors'
    } finally {
        $image.Dispose()
    }
}

Write-Host 'Native taskbar visual tests passed.'
