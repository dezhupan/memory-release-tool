param(
    [string]$WindhawkRoot = '',
    [string]$SetupPath = '',
    [int]$TimeoutSeconds = 900,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($WindhawkRoot)) {
    $WindhawkRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk'
}
if ([string]::IsNullOrWhiteSpace($SetupPath)) {
    $bundledSetup = Join-Path $packageRoot 'Dependencies\windhawk_setup.exe'
    if (Test-Path -LiteralPath $bundledSetup -PathType Leaf) {
        $SetupPath = $bundledSetup
    } else {
        $SetupPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Dependencies\windhawk_setup_v1.7.3.exe'
    }
}

$onlineSetupSha256 = '5116CC1703384AAC88B8D7A3B57F172AEA5DA32B6DF7355FB2F8247D23813C8F'
$offlineSetupSha256 = '4D93016570F982326EEBDFC9068E924FF21F6448534EA32672BB4C1D52A8193B'
$acceptedSetupSha256 = @($onlineSetupSha256, $offlineSetupSha256)
$expectedVersion = '1.7.3'
$officialSetupUrl = 'https://github.com/ramensoftware/windhawk/releases/download/v1.7.3/windhawk_setup.exe'

function Write-Step([string]$Message) {
    Write-Host "[Windhawk] $Message" -ForegroundColor Cyan
}

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Test-WindhawkPortable([string]$Root) {
    $exe = Join-Path $Root 'windhawk.exe'
    $ini = Join-Path $Root 'windhawk.ini'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or -not (Test-Path -LiteralPath $ini -PathType Leaf)) {
        return $false
    }

    try {
        return [bool](Select-String -LiteralPath $ini -SimpleMatch 'Portable=1' -Quiet)
    } catch {
        return $false
    }
}

function Set-WindhawkHiddenSettings([string]$Root) {
    $settingsPath = Join-Path $Root 'AppData\settings.ini'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { return }
    $content = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
    foreach ($entry in @(
        @{ Name = 'HideTrayIcon'; Value = '1' },
        @{ Name = 'DontAutoShowToolkit'; Value = '1' },
        @{ Name = 'DisableToolkitHotkey'; Value = '1' },
        @{ Name = 'ModTasksDialogDelay'; Value = '86400000' }
    )) {
        if ($content -match "(?m)^$([regex]::Escape($entry.Name))=") {
            $content = $content -replace "(?m)^$([regex]::Escape($entry.Name))=.*$", "$($entry.Name)=$($entry.Value)"
        } else {
            $content = $content.TrimEnd() + "`r`n$($entry.Name)=$($entry.Value)`r`n"
        }
    }
    [System.IO.File]::WriteAllText($settingsPath, $content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-SetupWindowWithControl(
    [System.Windows.Automation.AutomationElement]$AutomationRoot,
    [System.Windows.Automation.Condition]$ProcessCondition,
    [string]$AutomationId,
    [datetime]$Deadline
) {
    $idCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $AutomationId
    )

    do {
        $windows = $AutomationRoot.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            $ProcessCondition
        )
        foreach ($window in $windows) {
            $element = $window.FindFirst(
                [System.Windows.Automation.TreeScope]::Descendants,
                $idCondition
            )
            if ($null -ne $element) {
                return [pscustomobject]@{ Window = $window; Element = $element }
            }
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $Deadline)

    return $null
}

function Click-NativeButton([System.Windows.Automation.AutomationElement]$Element) {
    $handle = [IntPtr]$Element.Current.NativeWindowHandle
    if ($handle -eq [IntPtr]::Zero) {
        throw "Installer control has no native window handle: $($Element.Current.AutomationId)"
    }
    [void][MemoryCleanerWindhawkSetupUi]::SendMessageButton($handle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Set-NativeText([System.Windows.Automation.AutomationElement]$Element, [string]$Text) {
    $handle = [IntPtr]$Element.Current.NativeWindowHandle
    if ($handle -eq [IntPtr]::Zero) {
        throw "Installer text control has no native window handle: $($Element.Current.AutomationId)"
    }
    [void][MemoryCleanerWindhawkSetupUi]::SendMessageText($handle, 0x000C, [IntPtr]::Zero, $Text)
}

if ([Environment]::OSVersion.Version.Build -lt 22000) {
    throw 'Windhawk taskbar embedding requires Windows 11.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This package requires Windows 11 x64.'
}
$nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($nativeArchitecture -eq 'ARM64') {
    throw 'This package cannot install the x64 taskbar module on Windows on ARM.'
}

$WindhawkRoot = Get-FullPath $WindhawkRoot
$SetupPath = Get-FullPath $SetupPath
$windhawkExe = Join-Path $WindhawkRoot 'windhawk.exe'

if (Test-WindhawkPortable $WindhawkRoot) {
    Write-Step "Portable installation already exists: $WindhawkRoot"
    Set-WindhawkHiddenSettings -Root $WindhawkRoot
    if (-not $NoStart) {
        $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ExecutablePath -eq $windhawkExe
        } | Select-Object -First 1
        if ($null -eq $running) {
            Start-Process -FilePath $windhawkExe -ArgumentList '-tray-only' -WorkingDirectory $WindhawkRoot -WindowStyle Hidden | Out-Null
        } else {
            Start-Process -FilePath $windhawkExe -ArgumentList '-restart -tray-only' -WorkingDirectory $WindhawkRoot -WindowStyle Hidden | Out-Null
        }
    }
    return
}

if (-not (Test-Path -LiteralPath $SetupPath -PathType Leaf) -or
    $acceptedSetupSha256 -notcontains (Get-FileHash -LiteralPath $SetupPath -Algorithm SHA256).Hash) {
    $setupDirectory = Split-Path -Parent $SetupPath
    New-Item -ItemType Directory -Path $setupDirectory -Force | Out-Null
    $temporarySetup = Join-Path $setupDirectory ("windhawk-download-{0}.exe" -f $PID)
    Write-Step "Downloading the official signed Windhawk $expectedVersion installer..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $officialSetupUrl -OutFile $temporarySetup
        $downloadHash = (Get-FileHash -LiteralPath $temporarySetup -Algorithm SHA256).Hash
        if ($downloadHash -ne $onlineSetupSha256) {
            throw "Downloaded Windhawk installer SHA256 verification failed. Expected $onlineSetupSha256, got $downloadHash"
        }
        $downloadSignature = Get-AuthenticodeSignature -LiteralPath $temporarySetup
        if ($downloadSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
            throw "Downloaded Windhawk installer signature is not valid: $($downloadSignature.Status)"
        }
        $downloadSigner = [string]$downloadSignature.SignerCertificate.Subject
        if ($downloadSigner -notmatch 'Michael Maltsev|Open Source Developer') {
            throw "Unexpected downloaded Windhawk installer signer: $downloadSigner"
        }
        Move-Item -LiteralPath $temporarySetup -Destination $SetupPath -Force
    } finally {
        if (Test-Path -LiteralPath $temporarySetup -PathType Leaf) {
            Remove-Item -LiteralPath $temporarySetup -Force -ErrorAction SilentlyContinue
        }
    }
}

$actualHash = (Get-FileHash -LiteralPath $SetupPath -Algorithm SHA256).Hash
if ($acceptedSetupSha256 -notcontains $actualHash) {
    throw "Windhawk installer SHA256 verification failed. Got $actualHash"
}

$signature = Get-AuthenticodeSignature -LiteralPath $SetupPath
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "Windhawk installer signature is not valid: $($signature.Status)"
}
$signer = [string]$signature.SignerCertificate.Subject
if ($signer -notmatch 'Michael Maltsev|Open Source Developer') {
    throw "Unexpected Windhawk installer signer: $signer"
}

$parent = Split-Path -Parent $WindhawkRoot
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw "The destination drive or parent folder does not exist: $parent"
}
if (Test-Path -LiteralPath $WindhawkRoot) {
    $existing = @(Get-ChildItem -LiteralPath $WindhawkRoot -Force -ErrorAction Stop)
    if ($existing.Count -gt 0) {
        throw "The destination exists but is not a valid portable Windhawk installation: $WindhawkRoot"
    }
} else {
    New-Item -ItemType Directory -Path $WindhawkRoot | Out-Null
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if (-not ('MemoryCleanerWindhawkSetupUi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class MemoryCleanerWindhawkSetupUi
{
    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern IntPtr SendMessageButton(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern IntPtr SendMessageText(IntPtr hWnd, uint message, IntPtr wParam, string lParam);
}
'@
}

Unblock-File -LiteralPath $SetupPath -ErrorAction SilentlyContinue
Write-Step "Installing official Windhawk $expectedVersion Portable to $WindhawkRoot"
$setupProcess = Start-Process -FilePath $SetupPath -PassThru
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

try {
    $automationRoot = [System.Windows.Automation.AutomationElement]::RootElement
    $processCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $setupProcess.Id
    )

    $language = Get-SetupWindowWithControl $automationRoot $processCondition '1002' $deadline
    if ($null -eq $language) {
        throw 'Timed out waiting for the Windhawk language page.'
    }
    $languageOk = Get-SetupWindowWithControl $automationRoot $processCondition '1' $deadline
    Click-NativeButton $languageOk.Element

    $portable = Get-SetupWindowWithControl $automationRoot $processCondition '1204' $deadline
    if ($null -eq $portable) {
        throw 'Timed out waiting for the Windhawk installation mode page.'
    }
    Click-NativeButton $portable.Element
    Start-Sleep -Milliseconds 300
    $modeNext = Get-SetupWindowWithControl $automationRoot $processCondition '1' $deadline
    Click-NativeButton $modeNext.Element

    $directory = Get-SetupWindowWithControl $automationRoot $processCondition '1019' $deadline
    if ($null -eq $directory) {
        throw 'Timed out waiting for the Windhawk destination page.'
    }
    Set-NativeText $directory.Element $WindhawkRoot
    Start-Sleep -Milliseconds 300
    $installButton = Get-SetupWindowWithControl $automationRoot $processCondition '1' $deadline
    Click-NativeButton $installButton.Element

    Write-Step 'The official installer is deploying its files.'
    do {
        $setupProcess.Refresh()
        if ($setupProcess.HasExited) { break }

        if (Test-Path -LiteralPath $windhawkExe -PathType Leaf) {
            $finishButton = Get-SetupWindowWithControl $automationRoot $processCondition '1' (Get-Date).AddMilliseconds(400)
            if ($null -ne $finishButton -and $finishButton.Element.Current.IsEnabled) {
                Click-NativeButton $finishButton.Element
                break
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    if (-not (Test-Path -LiteralPath $windhawkExe -PathType Leaf)) {
        throw 'Windhawk installation did not complete before the timeout. Check the network connection and retry.'
    }

    $exitDeadline = (Get-Date).AddSeconds(20)
    do {
        $setupProcess.Refresh()
        if ($setupProcess.HasExited) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $exitDeadline)
} finally {
    $setupProcess.Refresh()
    if (-not $setupProcess.HasExited -and (Test-WindhawkPortable $WindhawkRoot)) {
        Stop-Process -Id $setupProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-WindhawkPortable $WindhawkRoot)) {
    throw "Windhawk files were created, but portable mode verification failed: $WindhawkRoot"
}

$installedVersion = (Get-Item -LiteralPath $windhawkExe).VersionInfo.FileVersion
Write-Step "Portable installation verified. Version: $installedVersion"
Set-WindhawkHiddenSettings -Root $WindhawkRoot

if (-not $NoStart) {
    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -eq $windhawkExe
    } | Select-Object -First 1
    if ($null -eq $running) {
        Start-Process -FilePath $windhawkExe -ArgumentList '-tray-only' -WorkingDirectory $WindhawkRoot -WindowStyle Hidden | Out-Null
    }
    Write-Step 'Windhawk is running invisibly for the embedded taskbar module.'
}
