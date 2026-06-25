param(
    [switch]$RunOnce,
    [switch]$Preview
)

$ErrorActionPreference = 'SilentlyContinue'
$script:ScriptPath = $MyInvocation.MyCommand.Path
try {
    $currentProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $currentProcessName = [System.IO.Path]::GetFileNameWithoutExtension($currentProcessPath)
    if ([System.IO.Path]::GetExtension($currentProcessPath) -ieq '.exe' -and $currentProcessName -notin @('powershell', 'powershell_ise', 'pwsh')) {
        $script:ScriptPath = $currentProcessPath
    }
} catch {}
$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
try {
    if (-not [string]::IsNullOrWhiteSpace($script:ScriptPath)) {
        $script:AppRoot = Split-Path -Parent $script:ScriptPath
    }
} catch {}
$script:SettingsPath = Join-Path $script:AppRoot 'settings.json'
$script:LogPath = Join-Path $script:AppRoot 'cleaner.log'
$script:StatePath = Join-Path $script:AppRoot 'cleaner.state.json'

function Write-AppLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
}

function Get-DefaultSettings {
    [pscustomobject]@{
        MinTrimMemoryMB = 40
        MinCloseMemoryMB = 120
        AggressiveBackgroundClose = $false
        ShowNetworkSpeed = $true
        ShowNetworkLocation = $true
        Language = 'en'
        IconStyle = 'bolt'
        LogCleanupIntervalDays = 7
        LogRetentionDays = 7
        KeepProcessNames = @(
            'Idle','System','Registry','Secure System','Memory Compression',
            'smss','csrss','wininit','winlogon','services','lsass','lsaiso',
            'svchost','fontdrvhost','dwm','ctfmon','sihost','explorer',
            'ShellExperienceHost','StartMenuExperienceHost','SearchHost',
            'SearchIndexer','RuntimeBroker','ApplicationFrameHost',
            'TextInputHost','SecurityHealthSystray','SecurityHealthService',
            'MsMpEng','NisSrv','spoolsv','audiodg','Taskmgr',
            'chrome','msedge','firefox','brave','opera',
            'Code','Codex','Cursor','devenv','pycharm64','idea64',
            'Weixin','WeChat','WeChatAppEx','QQ','TIM','DingTalk',
            'Typora','Yuque','wps','wpp','et','winword','excel','powerpnt',
            'Clash for Windows','Clash Verge','Clash Party',
            'OBS64','obs64','PotPlayerMini64','vlc',
            'Adobe Premiere Pro','AfterFX','Adobe Media Encoder',
            'DaVinci Resolve','CapCut','JianyingPro'
        )
        CloseProcessNames = @(
            'Widgets','WidgetService','GameBar','GameBarFTServer',
            'YourPhone','PhoneExperienceHost','SkypeApp','Copilot',
            'Cortana','NewsAndInterests','GoogleCrashHandler',
            'GoogleCrashHandler64','AdobeCollabSync','CCXProcess',
            'Creative Cloud Helper','Creative Cloud','Adobe Desktop Service',
            'AcroTray','armsvc','jusched','update_notifier',
            'Microsoft.Photos','Photos','OneDriveStandaloneUpdater'
        )
    }
}

function Save-Settings {
    param($Settings)
    $Settings | ConvertTo-Json -Depth 6 | Set-Content -Path $script:SettingsPath -Encoding UTF8
}

function Get-Settings {
    if (-not (Test-Path $script:SettingsPath)) {
        $defaults = Get-DefaultSettings
        Save-Settings $defaults
        return $defaults
    }

    try {
        $settings = Get-Content -Path $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $settings.KeepProcessNames) { $settings | Add-Member -NotePropertyName KeepProcessNames -NotePropertyValue @() }
        if ($null -eq $settings.CloseProcessNames) { $settings | Add-Member -NotePropertyName CloseProcessNames -NotePropertyValue @() }
        if ($null -eq $settings.ShowNetworkSpeed) { $settings | Add-Member -NotePropertyName ShowNetworkSpeed -NotePropertyValue $true }
        if ($null -eq $settings.ShowNetworkLocation) { $settings | Add-Member -NotePropertyName ShowNetworkLocation -NotePropertyValue $true }
        if ($null -eq $settings.Language) { $settings | Add-Member -NotePropertyName Language -NotePropertyValue 'en' }
        if ($null -eq $settings.IconStyle) { $settings | Add-Member -NotePropertyName IconStyle -NotePropertyValue 'bolt' }
        if ($null -eq $settings.LogCleanupIntervalDays) { $settings | Add-Member -NotePropertyName LogCleanupIntervalDays -NotePropertyValue 7 }
        if ($null -eq $settings.LogRetentionDays) { $settings | Add-Member -NotePropertyName LogRetentionDays -NotePropertyValue 7 }
        return $settings
    } catch {
        Write-AppLog "settings.json could not be read, using defaults: $($_.Exception.Message)"
        return Get-DefaultSettings
    }
}

function Get-AppState {
    if (-not (Test-Path $script:StatePath)) {
        return [pscustomobject]@{
            LastLogCleanupAt = $null
        }
    }

    try {
        return Get-Content -Path $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            LastLogCleanupAt = $null
        }
    }
}

function Save-AppState {
    param($State)
    $State | ConvertTo-Json -Depth 4 | Set-Content -Path $script:StatePath -Encoding UTF8
}

function Invoke-LogMaintenance {
    $settings = Get-Settings
    $intervalDays = [math]::Max(1, [int]$settings.LogCleanupIntervalDays)
    $retentionDays = [math]::Max(1, [int]$settings.LogRetentionDays)
    $state = Get-AppState
    $now = Get-Date
    $shouldRun = $true

    if (-not [string]::IsNullOrWhiteSpace([string]$state.LastLogCleanupAt)) {
        try {
            $lastCleanup = [datetime]::Parse([string]$state.LastLogCleanupAt, [System.Globalization.CultureInfo]::InvariantCulture)
            $shouldRun = (($now - $lastCleanup).TotalDays -ge $intervalDays)
        } catch {
            $shouldRun = $true
        }
    }

    if (-not $shouldRun) { return }

    $kept = @()
    $removed = 0
    if (Test-Path $script:LogPath) {
        $cutoff = $now.AddDays(-$retentionDays)
        foreach ($line in Get-Content -Path $script:LogPath -Encoding UTF8) {
            $keepLine = $true
            if ($line.Length -ge 19) {
                try {
                    $stamp = [datetime]::ParseExact($line.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
                    if ($stamp -lt $cutoff) { $keepLine = $false }
                } catch {
                    $keepLine = $true
                }
            }

            if ($keepLine) { $kept += $line }
            else { $removed++ }
        }
        Set-Content -Path $script:LogPath -Value $kept -Encoding UTF8
    }

    $state.LastLogCleanupAt = $now.ToString('o')
    Save-AppState $state
    Write-AppLog "log maintenance: intervalDays=$intervalDays retentionDays=$retentionDays removed=$removed"
}

function Test-NameInList {
    param([string]$Name, $List)
    if ([string]::IsNullOrWhiteSpace($Name) -or $null -eq $List) { return $false }
    foreach ($item in @($List)) {
        if ([string]::IsNullOrWhiteSpace([string]$item)) { continue }
        if ($Name -ieq [string]$item) { return $true }
    }
    return $false
}

function Ensure-NativeApis {
    if ('NativeMemoryCleaner' -as [type]) { return }
    $code = @"
using System;
using System.Runtime.InteropServices;

public static class NativeMemoryCleaner {
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
"@
    Add-Type -TypeDefinition $code
}

function Get-MemoryInfo {
    try {
        Ensure-NativeApis
        $status = New-Object NativeMemoryCleaner+MEMORYSTATUSEX
        $status.dwLength = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][NativeMemoryCleaner+MEMORYSTATUSEX])
        if ([NativeMemoryCleaner]::GlobalMemoryStatusEx([ref]$status)) {
            $totalMB = [math]::Round($status.ullTotalPhys / 1MB, 0)
            $freeMB = [math]::Round($status.ullAvailPhys / 1MB, 0)
            $usedMB = [math]::Max(0, $totalMB - $freeMB)
            return [pscustomobject]@{
                TotalMB = $totalMB
                FreeMB = $freeMB
                UsedMB = $usedMB
                UsedPercent = [int]$status.dwMemoryLoad
            }
        }
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)
        $usedMB = [math]::Max(0, $totalMB - $freeMB)
        $usedPercent = 0
        if ($totalMB -gt 0) {
            $usedPercent = [math]::Round(($usedMB / $totalMB) * 100, 0)
        }
        return [pscustomobject]@{
            TotalMB = $totalMB
            FreeMB = $freeMB
            UsedMB = $usedMB
            UsedPercent = $usedPercent
        }
    } catch {
        return [pscustomobject]@{
            TotalMB = 0
            FreeMB = 0
            UsedMB = 0
            UsedPercent = 0
        }
    }
}

function Get-KernelMemoryInfo {
    try {
        $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
        $nonPagedMB = [math]::Round($mem.PoolNonpagedBytes / 1MB, 0)
        $pagedMB = [math]::Round($mem.PoolPagedBytes / 1MB, 0)
        $cacheMB = [math]::Round($mem.CacheBytes / 1MB, 0)
        $committedGB = [math]::Round($mem.CommittedBytes / 1GB, 2)
        $commitLimitGB = [math]::Round($mem.CommitLimit / 1GB, 2)
        $isHigh = ($nonPagedMB -ge 2048)

        [pscustomobject]@{
            NonPagedPoolMB = $nonPagedMB
            PagedPoolMB = $pagedMB
            CacheMB = $cacheMB
            CommittedGB = $committedGB
            CommitLimitGB = $commitLimitGB
            IsNonPagedPoolHigh = $isHigh
        }
    } catch {
        [pscustomobject]@{
            NonPagedPoolMB = $null
            PagedPoolMB = $null
            CacheMB = $null
            CommittedGB = $null
            CommitLimitGB = $null
            IsNonPagedPoolHigh = $false
        }
    }
}

function Get-SuspectNetworkAdapters {
    $pattern = 'mihomo|meta tunnel|wintun|tap|tun|clash|vmware|hyper-v|vethernet|vpn|wireguard|ndis|virtual'
    $items = @()
    try {
        $adapters = Get-CimInstance Win32_NetworkAdapter | Where-Object {
            $_.NetEnabled -eq $true -and (
                [string]$_.Name -match $pattern -or
                [string]$_.Description -match $pattern -or
                [string]$_.NetConnectionID -match $pattern
            )
        }
        foreach ($adapter in $adapters) {
            $label = [string]$adapter.NetConnectionID
            if ([string]::IsNullOrWhiteSpace($label)) { $label = [string]$adapter.Name }
            $desc = [string]$adapter.Description
            if ([string]::IsNullOrWhiteSpace($desc)) { $desc = [string]$adapter.Name }
            $items += [pscustomobject]@{
                Name = $label
                Description = $desc
            }
        }
    } catch {}
    return $items | Sort-Object Name -Unique
}

function Get-SuspectKernelServices {
    $pattern = 'mihomo|clash|wintun|wireguard|vpn|vmware|vmnet|hyper-v|hns|wsl'
    $items = @()
    try {
        foreach ($svc in Get-Service | Where-Object { $_.Status -eq 'Running' -and ($_.Name -match $pattern -or $_.DisplayName -match $pattern) }) {
            $items += [pscustomobject]@{
                Name = [string]$svc.Name
                DisplayName = [string]$svc.DisplayName
            }
        }
    } catch {}
    return $items | Sort-Object Name -Unique
}

function Get-KernelPoolMessage {
    param($KernelInfo)

    if ($null -eq $KernelInfo -or $null -eq $KernelInfo.NonPagedPoolMB) { return $null }
    if ($KernelInfo.IsNonPagedPoolHigh -ne $true) { return $null }

    return "Nonpaged pool is $($KernelInfo.NonPagedPoolMB) MB. This is kernel/driver memory, so normal process trimming cannot release it. Disable or restart the leaking driver/device, usually a VPN/TUN/virtual network adapter."
}

function Get-UiText {
    param([string]$Key)
    $lang = 'en'
    try {
        if ($null -ne $script:uiSettings -and -not [string]::IsNullOrWhiteSpace([string]$script:uiSettings.Language)) {
            $lang = ([string]$script:uiSettings.Language).ToLowerInvariant()
        }
    } catch {}
    if ($lang -ne 'zh') {
        switch ($Key) {
            'External' { return 'Proxy' }
            'Internal' { return 'Direct' }
            'Offline' { return 'Offline' }
            'Download' { return 'Down' }
            'Upload' { return 'Up' }
            'Clean' { return 'Release' }
            'Cleaning' { return 'Releasing' }
            'Done' { return 'Done' }
            'Working' { return 'Working...' }
            'Freed' { return 'Freed' }
            'Preview' { return 'Preview ' }
            'Settings' { return 'Settings' }
            'Log' { return 'Log' }
            'Folder' { return 'Folder' }
            'Exit' { return 'Exit' }
            'CloseList' { return 'close list' }
            'Unknown' { return 'Unknown' }
            'DisplaySettings' { return 'Display settings' }
            'ShowSpeed' { return 'Show network speed' }
            'ShowLocation' { return 'Show proxy and location' }
            'Save' { return 'Save' }
            'Cancel' { return 'Cancel' }
            'Saved' { return 'Saved' }
            'Hidden' { return 'Hidden' }
        'SettingsHint' { return 'Changes apply immediately.' }
        'SaveFailed' { return 'Save failed' }
        'Language' { return 'Language' }
            'English' { return 'English' }
            'Chinese' { return 'Chinese' }
            'IconStyle' { return 'Icon style' }
            'IconBars' { return 'Bars' }
            'IconLeaf' { return 'Leaf' }
            'IconBolt' { return 'Bolt' }
            'IconSpark' { return 'Spark' }
            'IconShield' { return 'Shield' }
        'PreviewTitle' { return 'Close preview' }
        'PreviewIntro' { return 'Processes that would be closed:' }
        'PreviewNone' { return 'No background process would be closed now. Memory cache trimming will still run.' }
        'PreviewCount' { return 'Count' }
            'KernelMemory' { return 'Kernel memory' }
            'KernelMemoryTitle' { return 'Kernel memory diagnostics' }
            'KernelPoolHighTitle' { return 'Kernel pool is high' }
            default { return $Key }
        }
    }
    switch ($Key) {
        'External' { return -join ([char]0x5916, [char]0x7F51) }
        'Internal' { return -join ([char]0x5185, [char]0x7F51) }
        'Offline' { return -join ([char]0x79BB, [char]0x7EBF) }
        'Download' { return -join ([char]0x4E0B, [char]0x8F7D) }
        'Upload' { return -join ([char]0x4E0A, [char]0x4F20) }
        'Clean' { return -join ([char]0x91CA, [char]0x653E) }
        'Cleaning' { return -join ([char]0x91CA, [char]0x653E, [char]0x4E2D) }
        'Done' { return -join ([char]0x5B8C, [char]0x6210) }
        'Working' { return -join ([char]0x8BF7, [char]0x7A0D, [char]0x5019) }
        'Freed' { return -join ([char]0x5DF2, [char]0x91CA, [char]0x653E) }
        'Preview' { return -join ([char]0x9884, [char]0x89C8) }
        'Settings' { return -join ([char]0x8BBE, [char]0x7F6E) }
        'Log' { return -join ([char]0x65E5, [char]0x5FD7) }
        'Folder' { return -join ([char]0x6587, [char]0x4EF6, [char]0x5939) }
        'Exit' { return -join ([char]0x9000, [char]0x51FA) }
        'CloseList' { return -join ([char]0x5173, [char]0x95ED, [char]0x5217, [char]0x8868) }
        'Unknown' { return -join ([char]0x672A, [char]0x77E5) }
        'DisplaySettings' { return -join ([char]0x663E, [char]0x793A, [char]0x8BBE, [char]0x7F6E) }
        'ShowSpeed' { return -join ([char]0x663E, [char]0x793A, [char]0x7F51, [char]0x901F) }
        'ShowLocation' { return -join ([char]0x663E, [char]0x793A, [char]0x5916, [char]0x7F51, [char]0x548C, [char]0x7AD9, [char]0x70B9) }
        'Save' { return -join ([char]0x4FDD, [char]0x5B58) }
        'Cancel' { return -join ([char]0x53D6, [char]0x6D88) }
        'Saved' { return -join ([char]0x5DF2, [char]0x4FDD, [char]0x5B58) }
        'Hidden' { return -join ([char]0x5DF2, [char]0x9690, [char]0x85CF) }
        'SettingsHint' { return -join ([char]0x8BBE, [char]0x7F6E, [char]0x4F1A, [char]0x7ACB, [char]0x5373, [char]0x751F, [char]0x6548) }
        'SaveFailed' { return -join ([char]0x4FDD, [char]0x5B58, [char]0x5931, [char]0x8D25) }
        'Language' { return -join ([char]0x8BED, [char]0x8A00) }
        'English' { return -join ([char]0x82F1, [char]0x6587) }
        'Chinese' { return -join ([char]0x4E2D, [char]0x6587) }
        'IconStyle' { return -join ([char]0x56FE, [char]0x6807, [char]0x6837, [char]0x5F0F) }
        'IconBars' { return -join ([char]0x80FD, [char]0x91CF, [char]0x67F1) }
        'IconLeaf' { return -join ([char]0x53F6, [char]0x5B50) }
        'IconBolt' { return -join ([char]0x95EA, [char]0x7535) }
        'IconSpark' { return -join ([char]0x661F, [char]0x5149) }
        'IconShield' { return -join ([char]0x76FE, [char]0x724C) }
        'PreviewTitle' { return -join ([char]0x5173, [char]0x95ED, [char]0x9884, [char]0x89C8) }
        'PreviewIntro' { return -join ([char]0x5C06, [char]0x4F1A, [char]0x88AB, [char]0x5173, [char]0x95ED, [char]0x7684, [char]0x8FDB, [char]0x7A0B, [char]0xFF1A) }
        'PreviewNone' { return -join ([char]0x5F53, [char]0x524D, [char]0x4E0D, [char]0x4F1A, [char]0x5173, [char]0x95ED, [char]0x4EFB, [char]0x4F55, [char]0x540E, [char]0x53F0, [char]0x8FDB, [char]0x7A0B, [char]0xFF0C, [char]0x4ECD, [char]0x4F1A, [char]0x91CA, [char]0x653E, [char]0x5185, [char]0x5B58, [char]0x7F13, [char]0x5B58, [char]0x3002) }
        'PreviewCount' { return -join ([char]0x6570, [char]0x91CF) }
        'KernelMemory' { return -join ([char]0x5185, [char]0x6838, [char]0x5185, [char]0x5B58) }
        'KernelMemoryTitle' { return -join ([char]0x5185, [char]0x6838, [char]0x5185, [char]0x5B58, [char]0x8BCA, [char]0x65AD) }
        'KernelPoolHighTitle' { return -join ([char]0x5185, [char]0x6838, [char]0x6C60, [char]0x5F02, [char]0x5E38) }
        default { return $Key }
    }
}

function Get-CountryText {
    param([string]$CountryCode)
    $lang = 'en'
    try {
        if ($null -ne $script:uiSettings -and -not [string]::IsNullOrWhiteSpace([string]$script:uiSettings.Language)) {
            $lang = ([string]$script:uiSettings.Language).ToLowerInvariant()
        }
    } catch {}
    if ($lang -ne 'zh') {
        $code = ([string]$CountryCode).Trim().ToUpperInvariant()
        switch ($code) {
            'CN' { return 'China' }
            'TW' { return 'Taiwan' }
            'HK' { return 'Hong Kong' }
            'MO' { return 'Macau' }
            'JP' { return 'Japan' }
            'KR' { return 'Korea' }
            'US' { return 'United States' }
            'SG' { return 'Singapore' }
            'GB' { return 'United Kingdom' }
            'DE' { return 'Germany' }
            'FR' { return 'France' }
            'CA' { return 'Canada' }
            'AU' { return 'Australia' }
            'RU' { return 'Russia' }
            'IN' { return 'India' }
            'TH' { return 'Thailand' }
            'VN' { return 'Vietnam' }
            'MY' { return 'Malaysia' }
            'PH' { return 'Philippines' }
            'ID' { return 'Indonesia' }
            'NL' { return 'Netherlands' }
            'TR' { return 'Turkey' }
            'BR' { return 'Brazil' }
            'MX' { return 'Mexico' }
            default {
                if ([string]::IsNullOrWhiteSpace($code)) { return Get-UiText 'Unknown' }
                return $code
            }
        }
    }
    $code = ([string]$CountryCode).Trim().ToUpperInvariant()
    switch ($code) {
        'CN' { return -join ([char]0x4E2D, [char]0x56FD) }
        'TW' { return -join ([char]0x53F0, [char]0x6E7E) }
        'HK' { return -join ([char]0x9999, [char]0x6E2F) }
        'MO' { return -join ([char]0x6FB3, [char]0x95E8) }
        'JP' { return -join ([char]0x65E5, [char]0x672C) }
        'KR' { return -join ([char]0x97E9, [char]0x56FD) }
        'US' { return -join ([char]0x7F8E, [char]0x56FD) }
        'SG' { return -join ([char]0x65B0, [char]0x52A0, [char]0x5761) }
        'GB' { return -join ([char]0x82F1, [char]0x56FD) }
        'DE' { return -join ([char]0x5FB7, [char]0x56FD) }
        'FR' { return -join ([char]0x6CD5, [char]0x56FD) }
        'CA' { return -join ([char]0x52A0, [char]0x62FF, [char]0x5927) }
        'AU' { return -join ([char]0x6FB3, [char]0x5927, [char]0x5229, [char]0x4E9A) }
        'RU' { return -join ([char]0x4FC4, [char]0x7F57, [char]0x65AF) }
        'IN' { return -join ([char]0x5370, [char]0x5EA6) }
        'TH' { return -join ([char]0x6CF0, [char]0x56FD) }
        'VN' { return -join ([char]0x8D8A, [char]0x5357) }
        'MY' { return -join ([char]0x9A6C, [char]0x6765, [char]0x897F, [char]0x4E9A) }
        'PH' { return -join ([char]0x83F2, [char]0x5F8B, [char]0x5BBE) }
        'ID' { return -join ([char]0x5370, [char]0x5EA6, [char]0x5C3C, [char]0x897F, [char]0x4E9A) }
        'NL' { return -join ([char]0x8377, [char]0x5170) }
        'TR' { return -join ([char]0x571F, [char]0x8033, [char]0x5176) }
        'BR' { return -join ([char]0x5DF4, [char]0x897F) }
        'MX' { return -join ([char]0x58A8, [char]0x897F, [char]0x54E5) }
        default {
            if ([string]::IsNullOrWhiteSpace($code)) { return Get-UiText 'Unknown' }
            return $code
        }
    }
}

function Get-NetworkSnapshot {
    $rx = [int64]0
    $tx = [int64]0
    $active = $false
    $hasProxyLikeAdapter = $false

    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        try {
            if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
            if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }

            $nicText = (($nic.Name + ' ' + $nic.Description) -as [string])
            if ($nicText -match '(?i)wintun|wireguard|tap|tun|tailscale|zerotier|clash|mihomo|sing-box|v2ray|xray') {
                $hasProxyLikeAdapter = $true
            }

            if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel) { continue }

            $props = $nic.GetIPProperties()
            $ipv4 = $nic.GetIPv4Statistics()
            $rx += [int64]$ipv4.BytesReceived
            $tx += [int64]$ipv4.BytesSent
            $active = $true
        } catch {}
    }

    $hasProxyLikeProcess = $false
    $now = Get-Date
    try {
        $refreshProcessCache = $true
        if ($null -ne $script:lastProxyProcessCheckAt) {
            $refreshProcessCache = (($now - $script:lastProxyProcessCheckAt).TotalSeconds -ge $script:NetworkProcessRefreshSeconds)
        }
        if ($refreshProcessCache) {
            $proxyNames = @(
                'clash','clash-win64','clash-verge','clash verge','clash party','mihomo',
                'v2ray','v2rayn','xray','xrayn','sing-box','nekoray',
                'trojan','shadowsocks','sslocal','privoxy','hysteria',
                'wireguard','tailscale','zerotier'
            )
            $script:lastProxyProcessCheckAt = $now
            $script:lastProxyProcessResult = $false
            foreach ($proc in Get-Process) {
                $procName = [string]$proc.ProcessName
                if ((Test-NameInList $procName $proxyNames) -or $procName -match '(?i)clash|mihomo|v2ray|xray|sing|wireguard|tailscale|zerotier|nekoray') {
                    $script:lastProxyProcessResult = $true
                    break
                }
            }
        }
        $hasProxyLikeProcess = [bool]$script:lastProxyProcessResult
    } catch {
        $hasProxyLikeProcess = [bool]$script:lastProxyProcessResult
    }

    $proxySignature = Get-SystemProxySignature
    $networkSignature = ('{0}|adapter={1}|active={2}' -f $proxySignature, $hasProxyLikeAdapter, $active)
    if ($script:lastNetworkSignature -ne $networkSignature) {
        $script:lastNetworkSignature = $networkSignature
        $script:lastGeoProbeAt = $null
        $script:lastGeoCountry = $null
        if ($null -ne $script:geoLookupJob) {
            try { Remove-Job -Job $script:geoLookupJob -Force | Out-Null } catch {}
            $script:geoLookupJob = $null
        }
    }

    $mode = Get-UiText 'Offline'
    if ($active) {
        if ($proxySignature -match 'enable=1' -or $hasProxyLikeAdapter) { $mode = Get-UiText 'External' }
        else { $mode = Get-UiText 'Internal' }
    }

    if ($script:lastNetworkMode -ne $mode) {
        $script:lastNetworkMode = $mode
        $script:lastGeoProbeAt = $null
        $script:lastGeoCountry = $null
    }

    [pscustomobject]@{
        ReceivedBytes = $rx
        SentBytes = $tx
        Mode = $mode
    }
}

function Format-Speed {
    param([double]$BytesPerSecond)
    if ($BytesPerSecond -ge 1048576) {
        return ('{0:N1} MB/s' -f ($BytesPerSecond / 1048576))
    }
    if ($BytesPerSecond -ge 1024) {
        return ('{0:N0} KB/s' -f ($BytesPerSecond / 1024))
    }
    return ('{0:N0} B/s' -f $BytesPerSecond)
}

function Get-SystemProxyUri {
    try {
        $internetSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $proxySettings = Get-ItemProperty -Path $internetSettings
        if ([int]$proxySettings.ProxyEnable -ne 1) { return $null }
        $proxyServer = [string]$proxySettings.ProxyServer
        if ([string]::IsNullOrWhiteSpace($proxyServer)) { return $null }

        $target = $proxyServer
        if ($proxyServer -like '*=*') {
            $parts = $proxyServer -split ';'
            foreach ($part in $parts) {
                if ($part -match '^(https?|socks)=([^;]+)$') {
                    $target = $Matches[2]
                    break
                }
            }
        }

        if ($target -notmatch '^\w+://') {
            $target = 'http://' + $target
        }
        return [Uri]$target
    } catch {
        return $null
    }
}

function Get-SystemProxySignature {
    try {
        $internetSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $proxySettings = Get-ItemProperty -Path $internetSettings
        return ('enable={0};server={1};override={2}' -f [int]$proxySettings.ProxyEnable, [string]$proxySettings.ProxyServer, [string]$proxySettings.ProxyOverride)
    } catch {
        return 'proxy=unknown'
    }
}

function Test-TcpEndpoint {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs = 450
    )
    if ([string]::IsNullOrWhiteSpace($HostName) -or $Port -le 0) { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-ExternalReachable {
    param([Uri]$ProxyUri)
    try {
        $request = [System.Net.HttpWebRequest]::Create('https://www.google.com/generate_204')
        $request.Method = 'GET'
        $request.Timeout = 900
        $request.ReadWriteTimeout = 900
        $request.AllowAutoRedirect = $false
        $request.UserAgent = 'MemoryCleanerFloat'
        if ($null -ne $ProxyUri) {
            $request.Proxy = New-Object System.Net.WebProxy($ProxyUri)
        } else {
            $request.Proxy = [System.Net.WebRequest]::DefaultWebProxy
        }

        $response = $request.GetResponse()
        try {
            $code = [int]$response.StatusCode
            return ($code -ge 200 -and $code -lt 400)
        } finally {
            $response.Close()
        }
    } catch {
        return $false
    }
}

function Test-ProxyModeActive {
    param(
        [bool]$HasProxyLikeAdapter,
        [bool]$HasProxyLikeProcess
    )

    $proxyUri = Get-SystemProxyUri
    if ($null -ne $proxyUri) {
        $port = $proxyUri.Port
        if ($port -le 0) { $port = 80 }
        if ((Test-TcpEndpoint -HostName $proxyUri.Host -Port $port) -and (Test-ExternalReachable -ProxyUri $proxyUri)) {
            return $true
        }
    }

    if ($HasProxyLikeAdapter -or $HasProxyLikeProcess) {
        return (Test-ExternalReachable -ProxyUri $null)
    }

    return $false
}

function Invoke-IpCountryLookup {
    $urls = @(
        'https://ipapi.co/json/',
        'http://ip-api.com/json/?fields=status,countryCode,query'
    )

    foreach ($url in $urls) {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $request = [System.Net.HttpWebRequest]::Create($url)
            $request.Method = 'GET'
            $request.Timeout = 1200
            $request.ReadWriteTimeout = 1200
            $request.AllowAutoRedirect = $true
            $request.UserAgent = 'MemoryCleanerFloat'
            $request.Proxy = [System.Net.WebRequest]::DefaultWebProxy

            $response = $request.GetResponse()
            try {
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $reader.Close()
            } finally {
                $response.Close()
            }

            $json = $body | ConvertFrom-Json
            $code = $null
            if ($null -ne $json.country_code) { $code = [string]$json.country_code }
            elseif ($null -ne $json.countryCode) { $code = [string]$json.countryCode }
            if (-not [string]::IsNullOrWhiteSpace($code)) {
                return Get-CountryText $code
            }
        } catch {}
    }

    return Get-UiText 'Unknown'
}

function Start-IpCountryLookupJob {
    if ($null -ne $script:geoLookupJob) {
        try {
            if ($script:geoLookupJob.State -in @('Running', 'NotStarted')) { return }
            Remove-Job -Job $script:geoLookupJob -Force | Out-Null
        } catch {}
        $script:geoLookupJob = $null
    }

    $script:lastGeoProbeAt = Get-Date
    try {
        $script:geoLookupJob = Start-Job -ScriptBlock {
            $urls = @(
                'https://ipapi.co/json/',
                'http://ip-api.com/json/?fields=status,countryCode,query'
            )

            foreach ($url in $urls) {
                try {
                    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                    $request = [System.Net.HttpWebRequest]::Create($url)
                    $request.Method = 'GET'
                    $request.Timeout = 1800
                    $request.ReadWriteTimeout = 1800
                    $request.AllowAutoRedirect = $true
                    $request.UserAgent = 'MemoryCleanerFloat'
                    $request.Proxy = [System.Net.WebRequest]::DefaultWebProxy

                    $response = $request.GetResponse()
                    try {
                        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                        $body = $reader.ReadToEnd()
                        $reader.Close()
                    } finally {
                        $response.Close()
                    }

                    $json = $body | ConvertFrom-Json
                    $code = $null
                    if ($null -ne $json.country_code) { $code = [string]$json.country_code }
                    elseif ($null -ne $json.countryCode) { $code = [string]$json.countryCode }
                    if (-not [string]::IsNullOrWhiteSpace($code)) {
                        return $code.Trim().ToUpperInvariant()
                    }
                } catch {}
            }

            return ''
        }
    } catch {
        $script:geoLookupJob = $null
    }
}

function Update-IpCountryLookupJob {
    if ($null -eq $script:geoLookupJob) { return }
    try {
        if ($script:geoLookupJob.State -eq 'Running' -or $script:geoLookupJob.State -eq 'NotStarted') { return }
        $code = [string](Receive-Job -Job $script:geoLookupJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        Remove-Job -Job $script:geoLookupJob -Force | Out-Null
        $script:geoLookupJob = $null

        if (-not [string]::IsNullOrWhiteSpace($code)) {
            $script:lastGeoCountry = Get-CountryText $code
        } else {
            $script:lastGeoCountry = Get-UiText 'Unknown'
        }
    } catch {
        try { Remove-Job -Job $script:geoLookupJob -Force | Out-Null } catch {}
        $script:geoLookupJob = $null
        $script:lastGeoCountry = Get-UiText 'Unknown'
    }
}

function Get-CurrentIpCountryText {
    Update-IpCountryLookupJob
    $now = Get-Date
    $shouldStart = $true
    if ($null -ne $script:lastGeoProbeAt) {
        $shouldStart = (($now - $script:lastGeoProbeAt).TotalSeconds -ge $script:NetworkGeoRefreshSeconds)
    }
    if ($shouldStart) {
        Start-IpCountryLookupJob
    }
    if (-not [string]::IsNullOrWhiteSpace($script:lastGeoCountry)) { return $script:lastGeoCountry }
    return ''
}

function Get-ForegroundProcessId {
    Ensure-NativeApis
    $hwnd = [NativeMemoryCleaner]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return 0 }
    [uint32]$pidValue = 0
    [NativeMemoryCleaner]::GetWindowThreadProcessId($hwnd, [ref]$pidValue) | Out-Null
    return [int]$pidValue
}

function Get-ParentProcessId {
    param([int]$ProcessId)
    try {
        $proc = Get-WmiObject Win32_Process -Filter "ProcessId=$ProcessId"
        if ($null -eq $proc) { return 0 }
        return [int]$proc.ParentProcessId
    } catch {
        return 0
    }
}

function Get-ActiveProcessFamily {
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    $fg = Get-ForegroundProcessId
    if ($fg -le 0) { return $ids }

    $current = $fg
    for ($i = 0; $i -lt 10; $i++) {
        if ($current -le 0) { break }
        [void]$ids.Add($current)
        $parent = Get-ParentProcessId $current
        if ($parent -le 0 -or $parent -eq $current) { break }
        $current = $parent
    }
    return $ids
}

function Test-VisibleUserWindow {
    param([System.Diagnostics.Process]$Process)
    try {
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) { return $true }
        if (-not [string]::IsNullOrWhiteSpace($Process.MainWindowTitle)) { return $true }
    } catch {}
    return $false
}

function Get-ProcessPathSafe {
    param([System.Diagnostics.Process]$Process)
    try { return [string]$Process.Path } catch { return '' }
}

function Test-LikelyUserBackgroundProcess {
    param([System.Diagnostics.Process]$Process)
    $path = Get-ProcessPathSafe $Process
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if ($path -like "$env:windir\*") { return $false }
    if ($path -match '\\Windows\\') { return $false }
    return $true
}

function Test-CloseCandidate {
    param(
        [System.Diagnostics.Process]$Process,
        $Settings,
        [System.Collections.Generic.HashSet[int]]$ActiveIds
    )

    $name = $Process.ProcessName
    if ($Process.Id -eq $PID) { return $false }
    if ($ActiveIds.Contains([int]$Process.Id)) { return $false }
    if ($Process.SessionId -ne ([System.Diagnostics.Process]::GetCurrentProcess().SessionId)) { return $false }
    if (Test-NameInList $name $Settings.KeepProcessNames) { return $false }
    if (Test-VisibleUserWindow $Process) { return $false }

    $memMB = [math]::Round($Process.WorkingSet64 / 1MB, 1)
    if ($memMB -lt [double]$Settings.MinCloseMemoryMB) { return $false }

    if (Test-NameInList $name $Settings.CloseProcessNames) { return $true }
    if ($Settings.AggressiveBackgroundClose -eq $true -and (Test-LikelyUserBackgroundProcess $Process)) { return $true }
    return $false
}

function Get-CloseCandidates {
    param($Settings)
    $active = Get-ActiveProcessFamily
    $items = @()
    foreach ($p in Get-Process) {
        try {
            if (Test-CloseCandidate -Process $p -Settings $Settings -ActiveIds $active) {
                $items += [pscustomobject]@{
                    Id = $p.Id
                    Name = $p.ProcessName
                    MemoryMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
                    Path = Get-ProcessPathSafe $p
                }
            }
        } catch {}
    }
    return $items | Sort-Object MemoryMB -Descending
}

function Invoke-MemoryTrim {
    param($Settings)
    Ensure-NativeApis
    $active = Get-ActiveProcessFamily
    $trimmed = 0
    foreach ($p in Get-Process) {
        try {
            if ($p.Id -eq $PID) { continue }
            if ($active.Contains([int]$p.Id)) { continue }
            if ($p.WorkingSet64 -lt ([double]$Settings.MinTrimMemoryMB * 1MB)) { continue }
            [void][NativeMemoryCleaner]::EmptyWorkingSet($p.Handle)
            $trimmed++
        } catch {}
    }
    return $trimmed
}

function Invoke-Cleanup {
    param([switch]$PreviewOnly)

    $settings = Get-Settings
    $before = Get-MemoryInfo
    $beforeKernel = Get-KernelMemoryInfo
    $candidates = Get-CloseCandidates $settings

    if ($PreviewOnly) {
        return [pscustomobject]@{
            Before = $before
            After = $before
            BeforeKernel = $beforeKernel
            AfterKernel = $beforeKernel
            KernelMessage = Get-KernelPoolMessage $beforeKernel
            TrimmedCount = 0
            ClosedCount = 0
            ClosedItems = @()
            Candidates = $candidates
        }
    }

    $trimmed = Invoke-MemoryTrim $settings
    $closed = @()
    foreach ($item in $candidates) {
        try {
            Stop-Process -Id $item.Id -Force -ErrorAction Stop
            $closed += $item
        } catch {
            Write-AppLog "failed to close $($item.Name) pid=$($item.Id): $($_.Exception.Message)"
        }
    }

    Start-Sleep -Milliseconds 700
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $after = Get-MemoryInfo
    $afterKernel = Get-KernelMemoryInfo
    $kernelMessage = Get-KernelPoolMessage $afterKernel

    $names = ($closed | ForEach-Object { "$($_.Name)($($_.MemoryMB)MB)" }) -join ', '
    if ([string]::IsNullOrWhiteSpace($names)) { $names = 'none' }
    Write-AppLog "released: before=$($before.UsedPercent)% after=$($after.UsedPercent)% nonpagedBefore=$($beforeKernel.NonPagedPoolMB)MB nonpagedAfter=$($afterKernel.NonPagedPoolMB)MB trimmed=$trimmed closed=$($closed.Count) items=$names"
    if (-not [string]::IsNullOrWhiteSpace($kernelMessage)) {
        Write-AppLog "kernel warning: $kernelMessage"
    }

    [pscustomobject]@{
        Before = $before
        After = $after
        BeforeKernel = $beforeKernel
        AfterKernel = $afterKernel
        KernelMessage = $kernelMessage
        TrimmedCount = $trimmed
        ClosedCount = $closed.Count
        ClosedItems = $closed
        Candidates = $candidates
    }
}

function Format-ResultText {
    param($Result)
    $freed = [math]::Max(0, $Result.After.FreeMB - $Result.Before.FreeMB)
    $closedNames = ($Result.ClosedItems | ForEach-Object { $_.Name }) -join ', '
    if ([string]::IsNullOrWhiteSpace($closedNames)) { $closedNames = 'none' }
    return "Memory: $($Result.Before.UsedPercent)% -> $($Result.After.UsedPercent)%`nFreed: about $freed MB`nTrimmed: $($Result.TrimmedCount) processes`nClosed: $($Result.ClosedCount) ($closedNames)"
}

if ($RunOnce) {
    $result = Invoke-Cleanup
    $result | ConvertTo-Json -Depth 6
    exit
}

if ($Preview) {
    $result = Invoke-Cleanup -PreviewOnly
    $result.Candidates | Format-Table -AutoSize
    exit
}

$script:singleInstanceMutex = $null
$createdNew = $false
$script:singleInstanceMutex = New-Object System.Threading.Mutex($true, 'Global\MemoryCleanerFloat_6F7C6F1E_9D5B_48E7_A8C7_7B9015E6848D', [ref]$createdNew)
if (-not $createdNew) {
    exit
}

Invoke-LogMaintenance

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$appIconPath = Join-Path $script:AppRoot 'lightning.ico'
if (Test-Path $appIconPath) {
    try { $script:notifyIcon.Icon = New-Object System.Drawing.Icon($appIconPath) } catch {}
}
if ($null -eq $script:notifyIcon.Icon) {
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
}
$script:notifyIcon.Text = 'Memory Cleaner Float'
$script:notifyIcon.Visible = $true

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Memory Cleaner Float"
        Width="238" Height="92"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Topmost="True"
        SnapsToDevicePixels="True"
        UseLayoutRounding="True">
    <Grid x:Name="Root" RenderTransformOrigin="0.5,0.5" Cursor="Hand" ToolTip="&#x70B9;&#x51FB;&#x84DD;&#x8272;&#x6309;&#x94AE;&#x91CA;&#x653E;&#xFF0C;&#x62D6;&#x52A8;&#x9762;&#x677F;&#x79FB;&#x52A8;" ClipToBounds="True">
        <Grid.RenderTransform>
            <ScaleTransform x:Name="RootScale" ScaleX="1" ScaleY="1"/>
        </Grid.RenderTransform>
        <Border Margin="9" CornerRadius="27" Background="#01FFFFFF">
            <Border.Effect>
                <DropShadowEffect Color="#4A6478" BlurRadius="10" ShadowDepth="2" Opacity="0.16"/>
            </Border.Effect>
        </Border>
        <Border x:Name="Card" Margin="8" CornerRadius="28" BorderThickness="1" BorderBrush="#DDE8F2">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#F0FFFFFF" Offset="0"/>
                    <GradientStop Color="#D8EAF2FA" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>
        </Border>
        <Border x:Name="HoverLayer" Margin="8" CornerRadius="28" Background="#38FFFFFF" Opacity="0"/>
        <Border x:Name="PressLayer" Margin="8" CornerRadius="28" Background="#250A84FF" Opacity="0"/>
        <Border x:Name="DoneLayer" Margin="8" CornerRadius="28" Background="#3030D158" Opacity="0"/>
        <Border x:Name="PulseLayer" Margin="8" CornerRadius="28" BorderThickness="2" BorderBrush="#6530D158" Opacity="0" RenderTransformOrigin="0.5,0.5">
            <Border.RenderTransform>
                <ScaleTransform x:Name="PulseScale" ScaleX="1" ScaleY="1"/>
            </Border.RenderTransform>
        </Border>
        <Grid Margin="18,14,18,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="46"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid x:Name="IconButton" Width="42" Height="42" VerticalAlignment="Center" Cursor="Hand" RenderTransformOrigin="0.5,0.5">
                <Grid.RenderTransform>
                    <ScaleTransform x:Name="IconScale" ScaleX="1" ScaleY="1"/>
                </Grid.RenderTransform>
                <Ellipse x:Name="IconCircle">
                    <Ellipse.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#0A84FF" Offset="0"/>
                            <GradientStop Color="#64D2FF" Offset="1"/>
                        </LinearGradientBrush>
                    </Ellipse.Fill>
                </Ellipse>
                <Path x:Name="IconPath" Stroke="White" StrokeThickness="2.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Fill="Transparent"
                      Data="M13,24 L13,15 M20,24 L20,11 M27,24 L27,18"/>
                <Ellipse x:Name="ProgressRing" Width="42" Height="42" Stroke="#F5FFFFFF" StrokeThickness="3"
                         StrokeDashArray="2.4 4.2" Opacity="0" RenderTransformOrigin="0.5,0.5">
                    <Ellipse.RenderTransform>
                        <RotateTransform x:Name="RingRotate" Angle="0"/>
                    </Ellipse.RenderTransform>
                </Ellipse>
            </Grid>
            <StackPanel Grid.Column="2" VerticalAlignment="Center" IsHitTestVisible="False">
                <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="TitleText" Text="" Foreground="#64707D" FontFamily="Microsoft YaHei UI" FontSize="11" LineHeight="13"/>
                    <Border x:Name="ModeBadge" Margin="8,0,0,0" Padding="6,1,6,2" CornerRadius="8" Background="#260A84FF">
                        <TextBlock x:Name="ModeText" Text="&#x5916;&#x7F51; &#x53F0;&#x6E7E;" Foreground="#246B9E" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10"/>
                    </Border>
                </StackPanel>
                <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="PercentText" Text="0%" Foreground="#18202A" FontFamily="Segoe UI Semibold" FontSize="21" LineHeight="23"/>
                    <TextBlock Text="RAM" Foreground="#798694" FontFamily="Segoe UI" FontSize="9" Margin="5,7,0,0"/>
                </StackPanel>
                <TextBlock x:Name="StatusText" Text="&#x4E0B;&#x8F7D; 0 KB/s  &#x4E0A;&#x4F20; 0 KB/s" Foreground="#627181" FontFamily="Microsoft YaHei UI" FontSize="9.5" LineHeight="13" Margin="0,1,0,0" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$root = $window.FindName('Root')
$rootScale = $window.FindName('RootScale')
$hoverLayer = $window.FindName('HoverLayer')
$pressLayer = $window.FindName('PressLayer')
$doneLayer = $window.FindName('DoneLayer')
$pulseLayer = $window.FindName('PulseLayer')
$pulseScale = $window.FindName('PulseScale')
$iconButton = $window.FindName('IconButton')
$iconScale = $window.FindName('IconScale')
$iconCircle = $window.FindName('IconCircle')
$iconPath = $window.FindName('IconPath')
$progressRing = $window.FindName('ProgressRing')
$ringRotate = $window.FindName('RingRotate')
$titleText = $window.FindName('TitleText')
$percentText = $window.FindName('PercentText')
$modeBadge = $window.FindName('ModeBadge')
$modeText = $window.FindName('ModeText')
$statusText = $window.FindName('StatusText')
$script:uiSettings = Get-Settings

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = $workArea.Right - $window.Width - 28
$window.Top = [math]::Max(20, [int]($workArea.Height * 0.35))

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$cleanItem = $menu.Items.Add((Get-UiText 'Clean'))
$kernelItem = $menu.Items.Add((Get-UiText 'KernelMemory'))
$menu.Items.Add('-') | Out-Null
$settingsItem = $menu.Items.Add((Get-UiText 'Settings'))
$logItem = $menu.Items.Add((Get-UiText 'Log'))
$folderItem = $menu.Items.Add((Get-UiText 'Folder'))
$menu.Items.Add('-') | Out-Null
$exitItem = $menu.Items.Add((Get-UiText 'Exit'))
$script:notifyIcon.ContextMenuStrip = $menu

function Apply-UiSettings {
    $cleanItem.Text = Get-UiText 'Clean'
    $kernelItem.Text = Get-UiText 'KernelMemory'
    $settingsItem.Text = Get-UiText 'Settings'
    $logItem.Text = Get-UiText 'Log'
    $folderItem.Text = Get-UiText 'Folder'
    $exitItem.Text = Get-UiText 'Exit'

    if (-not $script:statusOverride) {
        $titleText.Text = ''
    }

    if (([string]$script:uiSettings.Language).ToLowerInvariant() -eq 'zh') {
        $root.ToolTip = (-join ([char]0x70B9, [char]0x84DD, [char]0x8272, [char]0x5706, [char]0x6309, [char]0x94AE, [char]0x91CA, [char]0x653E, [char]0xFF0C, [char]0x62D6, [char]0x52A8, [char]0x9762, [char]0x677F, [char]0x79FB, [char]0x52A8))
    } else {
        $root.ToolTip = 'Click the blue button to release. Drag the panel to move.'
    }

    Set-IconStyle
    Update-NetworkText
    Apply-WindowLayout
}

function Apply-WindowLayout {
    $showSpeed = ($script:uiSettings.ShowNetworkSpeed -eq $true)
    $showLocation = ($script:uiSettings.ShowNetworkLocation -eq $true)

    $targetWidth = 178
    $targetHeight = 74
    if ($showLocation -and $showSpeed) {
        $targetWidth = 238
        $targetHeight = 92
    } elseif ($showLocation -and -not $showSpeed) {
        $targetWidth = 220
        $targetHeight = 78
    } elseif (-not $showLocation -and $showSpeed) {
        $targetWidth = 218
        $targetHeight = 92
    }

    if ([math]::Abs([double]$window.Width - $targetWidth) -gt 0.5) {
        $window.Width = $targetWidth
    }
    if ([math]::Abs([double]$window.Height - $targetHeight) -gt 0.5) {
        $window.Height = $targetHeight
    }
}

function Set-IconStyle {
    $style = ([string]$script:uiSettings.IconStyle).ToLowerInvariant()
    $data = 'M13,24 L13,15 M20,24 L20,11 M27,24 L27,18'
    $strokeThickness = 2.2
    $fillBrush = [System.Windows.Media.Brushes]::Transparent
    $strokeBrush = [System.Windows.Media.Brushes]::White

    switch ($style) {
        'leaf' {
            $data = 'M29,12 C22,12 14,17 14,25 C14,31 20,34 25,30 C30,26 31,18 29,12 M16,29 C19,24 23,20 29,13'
            $strokeThickness = 2.0
        }
        'bolt' {
            $data = 'M23,8 L13,23 L21,23 L18,34 L30,18 L22,18 Z'
            $strokeThickness = 1.2
            $fillBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(214, 255, 255, 255))
        }
        'spark' {
            $data = 'M21,8 L23,18 L33,20 L23,22 L21,32 L19,22 L9,20 L19,18 Z'
            $strokeThickness = 1.2
            $fillBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(196, 255, 255, 255))
        }
        'shield' {
            $data = 'M21,9 L31,13 L29,25 C28,30 24,33 21,35 C18,33 14,30 13,25 L11,13 Z'
            $strokeThickness = 1.2
            $fillBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(174, 255, 255, 255))
        }
        default {
            $style = 'bars'
        }
    }

    $iconPath.Data = [System.Windows.Media.Geometry]::Parse($data)
    $iconPath.StrokeThickness = $strokeThickness
    $iconPath.Fill = $fillBrush
    $iconPath.Stroke = $strokeBrush
}

function New-WpfAnimation {
    param([double]$To, [int]$Ms)
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animation.To = $To
    $animation.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $animation.EasingFunction = $ease
    return $animation
}

function Set-WpfOpacity {
    param($Target, [double]$To, [int]$Ms)
    $Target.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-WpfAnimation $To $Ms))
}

function Set-WpfScale {
    param([double]$To, [int]$Ms)
    $rootScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-WpfAnimation $To $Ms))
    $rootScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-WpfAnimation $To $Ms))
}

function Set-ElementScale {
    param($ScaleTransform, [double]$To, [int]$Ms)
    $ScaleTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-WpfAnimation $To $Ms))
    $ScaleTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-WpfAnimation $To $Ms))
}

function New-IconBrush {
    param([bool]$Pressed)
    $brush = New-Object System.Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object System.Windows.Point(0, 0)
    $brush.EndPoint = New-Object System.Windows.Point(1, 1)
    if ($Pressed) {
        $first = New-Object System.Windows.Media.GradientStop
        $first.Color = [System.Windows.Media.Color]::FromRgb(48, 209, 88)
        $first.Offset = 0
        $second = New-Object System.Windows.Media.GradientStop
        $second.Color = [System.Windows.Media.Color]::FromRgb(40, 180, 120)
        $second.Offset = 1
    } else {
        $first = New-Object System.Windows.Media.GradientStop
        $first.Color = [System.Windows.Media.Color]::FromRgb(10, 132, 255)
        $first.Offset = 0
        $second = New-Object System.Windows.Media.GradientStop
        $second.Color = [System.Windows.Media.Color]::FromRgb(100, 210, 255)
        $second.Offset = 1
    }
    [void]$brush.GradientStops.Add($first)
    [void]$brush.GradientStops.Add($second)
    return $brush
}

function Set-IconPressVisual {
    param([bool]$Pressed)
    if ($Pressed) {
        $iconCircle.Fill = New-IconBrush $true
        Set-ElementScale $iconScale 0.88 95
    } else {
        $iconCircle.Fill = New-IconBrush $false
        Set-ElementScale $iconScale 1.0 180
    }
}

function Set-PressVisual {
    param([bool]$Pressed)
    if ($Pressed) {
        Set-WpfScale 0.965 120
        Set-WpfOpacity $pressLayer 1.0 120
    } else {
        Set-WpfScale 1.0 140
        Set-WpfOpacity $pressLayer 0.0 140
    }
}

function Flash-DoneVisual {
    Set-ElementScale $pulseScale 1.0 1
    Set-WpfOpacity $doneLayer 1.0 120
    Set-WpfOpacity $pulseLayer 1.0 80
    Set-ElementScale $pulseScale 1.12 520
    $flashTimer = New-Object System.Windows.Threading.DispatcherTimer
    $flashTimer.Interval = [TimeSpan]::FromMilliseconds(520)
    $flashTimer.Add_Tick({
        $flashTimer.Stop()
        Set-WpfOpacity $doneLayer 0.0 450
        Set-WpfOpacity $pulseLayer 0.0 450
    }.GetNewClosure())
    $flashTimer.Start()
}

function Start-ProgressAnimation {
    Set-WpfOpacity $progressRing 1.0 120
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animation.From = 0
    $animation.To = 360
    $animation.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(780))
    $animation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $ringRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $animation)
}

function Stop-ProgressAnimation {
    $ringRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    Set-WpfOpacity $progressRing 0.0 180
}

function Update-ButtonText {
    if ($script:isDraggingWindow -or $script:cleanupInProgress) { return }
    $mem = Get-MemoryInfo
    $percentText.Text = ('{0}%' -f [int]$mem.UsedPercent)
}

$script:lastNetSnapshot = $null
$script:lastNetSampleAt = $null
$script:lastNetworkSignature = $null
$script:lastNetworkMode = $null
$script:lastProxyProbeAt = $null
$script:lastProxyProbeResult = $null
$script:lastProxyProcessCheckAt = $null
$script:lastProxyProcessResult = $false
$script:lastGeoProbeAt = $null
$script:lastGeoCountry = $null
$script:geoLookupJob = $null
$script:NetworkProcessRefreshSeconds = 3
$script:NetworkGeoRefreshSeconds = 15
$script:statusOverride = $false
$script:cleanupInProgress = $false
$script:resetStatusTimer = $null
$script:cleanupProcess = $null
$script:cleanupStartedAt = $null
$script:cleanupTimeoutSeconds = 25
$script:cleanupPollTimer = $null
$script:postDragRefreshTimer = $null

function Queue-PostDragRefresh {
    if ($null -ne $script:postDragRefreshTimer) {
        try { $script:postDragRefreshTimer.Stop() } catch {}
    }
    $script:postDragRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:postDragRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(120)
    $script:postDragRefreshTimer.Add_Tick({
        $script:postDragRefreshTimer.Stop()
        if (-not $script:cleanupInProgress -and -not $script:isDraggingWindow) {
            Update-ButtonText
            Update-NetworkText
        }
    }.GetNewClosure())
    $script:postDragRefreshTimer.Start()
}

function Reset-NetworkStatusCache {
    $script:lastNetSnapshot = $null
    $script:lastNetSampleAt = $null
    $script:lastNetworkSignature = $null
    $script:lastNetworkMode = $null
    $script:lastProxyProbeAt = $null
    $script:lastProxyProbeResult = $null
    $script:lastProxyProcessCheckAt = $null
    $script:lastProxyProcessResult = $false
    $script:lastGeoProbeAt = $null
    $script:lastGeoCountry = $null
    if ($null -ne $script:geoLookupJob) {
        try { Remove-Job -Job $script:geoLookupJob -Force | Out-Null } catch {}
        $script:geoLookupJob = $null
    }
}

function Update-NetworkText {
    if ($script:isDraggingWindow -or $script:cleanupInProgress) { return }
    $now = Get-Date
    $snapshot = Get-NetworkSnapshot
    $downText = '0 B/s'
    $upText = '0 B/s'

    if ($null -ne $script:lastNetSnapshot -and $null -ne $script:lastNetSampleAt) {
        $seconds = [math]::Max(0.2, ($now - $script:lastNetSampleAt).TotalSeconds)
        $rxDelta = [math]::Max(0, $snapshot.ReceivedBytes - $script:lastNetSnapshot.ReceivedBytes)
        $txDelta = [math]::Max(0, $snapshot.SentBytes - $script:lastNetSnapshot.SentBytes)
        $downText = Format-Speed ($rxDelta / $seconds)
        $upText = Format-Speed ($txDelta / $seconds)
    }

    $script:lastNetSnapshot = $snapshot
    $script:lastNetSampleAt = $now
    if ($script:uiSettings.ShowNetworkLocation -eq $true) {
        $modeBadge.Visibility = [System.Windows.Visibility]::Visible
        if ($snapshot.Mode -eq (Get-UiText 'Offline')) {
            $modeText.Text = $snapshot.Mode
        } else {
            $countryText = Get-CurrentIpCountryText
            if ([string]::IsNullOrWhiteSpace($countryText)) {
                $modeText.Text = ('{0} ...' -f $snapshot.Mode)
            } else {
                $modeText.Text = ('{0} {1}' -f $snapshot.Mode, $countryText)
            }
        }
    } else {
        $modeBadge.Visibility = [System.Windows.Visibility]::Collapsed
    }

    if (-not $script:statusOverride) {
        if ($script:uiSettings.ShowNetworkSpeed -eq $true) {
            $statusText.Visibility = [System.Windows.Visibility]::Visible
            $statusText.Text = ('{0} {1}  {2} {3}' -f (Get-UiText 'Download'), $downText, (Get-UiText 'Upload'), $upText)
        } else {
            $statusText.Text = ''
            $statusText.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}

function Set-StatusMessage {
    param([string]$Text)
    if ($script:uiSettings.ShowNetworkSpeed -eq $true) {
        $statusText.Visibility = [System.Windows.Visibility]::Visible
        $statusText.Text = $Text
    } else {
        $statusText.Text = ''
        $statusText.Visibility = [System.Windows.Visibility]::Collapsed
    }
}

function Restore-IdleStatus {
    $titleText.Text = ''
    $script:statusOverride = $false
    Apply-WindowLayout
    Update-NetworkText
}

function Show-Balloon {
    param([string]$Title, [string]$Text)
    $script:notifyIcon.BalloonTipTitle = $Title
    $script:notifyIcon.BalloonTipText = $Text
    $script:notifyIcon.ShowBalloonTip(2500)
}

function Finish-UiCleanup {
    param($Result)

    Stop-ProgressAnimation
    Update-ButtonText
    $titleText.Text = ''

    $freed = 0
    $closedCount = 0
    if ($null -ne $Result -and $null -ne $Result.After -and $null -ne $Result.Before) {
        $freed = [math]::Max(0, [int]$Result.After.FreeMB - [int]$Result.Before.FreeMB)
        $closedCount = [int]$Result.ClosedCount
    }

    $script:cleanupInProgress = $false
    Restore-IdleStatus
    Flash-DoneVisual
    if ($null -ne $Result -and -not [string]::IsNullOrWhiteSpace([string]$Result.KernelMessage)) {
        Show-Balloon (Get-UiText 'KernelPoolHighTitle') ([string]$Result.KernelMessage)
    } else {
        Show-Balloon 'Memory released' "Freed about $freed MB; closed $closedCount background process(es)."
    }
}

function Fail-UiCleanup {
    param([string]$Message)

    Stop-ProgressAnimation
    Update-ButtonText
    $titleText.Text = ''
    Set-StatusMessage $Message
    $script:cleanupInProgress = $false
    Show-Balloon 'Memory release failed' $Message

    if ($null -ne $script:resetStatusTimer) { try { $script:resetStatusTimer.Stop() } catch {} }
    $script:resetStatusTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:resetStatusTimer.Interval = [TimeSpan]::FromSeconds(2.0)
    $script:resetStatusTimer.Add_Tick({
        $script:resetStatusTimer.Stop()
        $script:statusOverride = $false
        Apply-WindowLayout
        Update-NetworkText
    }.GetNewClosure())
    $script:resetStatusTimer.Start()
}

function Run-UiCleanup {
    if ($script:cleanupInProgress) { return }
    $script:cleanupInProgress = $true
    $script:statusOverride = $true
    $titleText.Text = Get-UiText 'Cleaning'
    Set-StatusMessage (Get-UiText 'Working')
    Start-ProgressAnimation
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    $scriptPath = $script:ScriptPath
    $process = New-Object System.Diagnostics.Process
    if ([System.IO.Path]::GetExtension($scriptPath) -ieq '.exe') {
        $sidecarScript = Join-Path $script:AppRoot 'MemoryCleanerFloat.ps1'
        if (Test-Path $sidecarScript) {
            $process.StartInfo.FileName = 'powershell.exe'
            $process.StartInfo.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -RunOnce' -f $sidecarScript)
        } else {
            $process.StartInfo.FileName = $scriptPath
            $process.StartInfo.Arguments = '-RunOnce'
        }
    } else {
        $process.StartInfo.FileName = 'powershell.exe'
        $process.StartInfo.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -RunOnce' -f $scriptPath)
    }
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true

    try {
        if (-not $process.Start()) {
            Fail-UiCleanup (Get-UiText 'Working')
            return
        }
    } catch {
        Write-AppLog "release worker start failed: $($_.Exception.Message)"
        Fail-UiCleanup 'Release worker failed to start.'
        return
    }

    if ($null -ne $script:cleanupPollTimer) { try { $script:cleanupPollTimer.Stop() } catch {} }
    $script:cleanupProcess = $process
    $script:cleanupStartedAt = Get-Date
    $script:cleanupTimeoutSeconds = 25
    $script:cleanupPollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:cleanupPollTimer.Interval = [TimeSpan]::FromMilliseconds(140)
    $script:cleanupPollTimer.Add_Tick({
        $process = $script:cleanupProcess
        if ($null -eq $process) {
            $script:cleanupPollTimer.Stop()
            return
        }

        if (-not $process.HasExited) {
            if (((Get-Date) - $script:cleanupStartedAt).TotalSeconds -lt $script:cleanupTimeoutSeconds) { return }
            try { $process.Kill() } catch {}
            try { $process.Dispose() } catch {}
            $script:cleanupPollTimer.Stop()
            $script:cleanupProcess = $null
            Write-AppLog "release worker timed out after $($script:cleanupTimeoutSeconds) seconds"
            Fail-UiCleanup 'Release timed out.'
            return
        }
        $script:cleanupPollTimer.Stop()
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.Dispose()
        $script:cleanupProcess = $null

        $result = $null
        try {
            if (-not [string]::IsNullOrWhiteSpace($output)) {
                $result = $output | ConvertFrom-Json
            }
        } catch {
            Write-AppLog "release result parse failed: $($_.Exception.Message)"
        }
        if (-not [string]::IsNullOrWhiteSpace($errorOutput)) {
            Write-AppLog "release worker stderr: $errorOutput"
        }
        Finish-UiCleanup $result
    })
    $script:cleanupPollTimer.Start()
}

function Show-PreviewWindow {
    $result = Invoke-Cleanup -PreviewOnly
    $lines = @()
    $lines += Get-UiText 'PreviewIntro'
    $lines += ('{0}: {1}' -f (Get-UiText 'PreviewCount'), @($result.Candidates).Count)
    $lines += ""
    if (@($result.Candidates).Count -eq 0) {
        $lines += Get-UiText 'PreviewNone'
    } else {
        foreach ($c in $result.Candidates) {
            $lines += ("{0,7} MB   PID {1,-7} {2}" -f $c.MemoryMB, $c.Id, $c.Name)
        }
    }
    [System.Windows.MessageBox]::Show(($lines -join [Environment]::NewLine), (Get-UiText 'PreviewTitle'), 'OK', 'Information') | Out-Null
}

function Show-KernelMemoryWindow {
    $kernel = Get-KernelMemoryInfo
    $adapters = @(Get-SuspectNetworkAdapters)
    $services = @(Get-SuspectKernelServices)
    $lines = @()

    $lines += ("Nonpaged pool: {0} MB" -f $kernel.NonPagedPoolMB)
    $lines += ("Paged pool: {0} MB" -f $kernel.PagedPoolMB)
    $lines += ("System cache: {0} MB" -f $kernel.CacheMB)
    $lines += ("Committed: {0} / {1} GB" -f $kernel.CommittedGB, $kernel.CommitLimitGB)
    $lines += ""

    $message = Get-KernelPoolMessage $kernel
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        $lines += $message
        $lines += ""
    } else {
        $lines += "Nonpaged pool is not above the warning threshold right now."
        $lines += ""
    }

    $lines += "Active virtual/tunnel adapters:"
    if ($adapters.Count -eq 0) {
        $lines += "  none detected"
    } else {
        foreach ($adapter in $adapters) {
            $lines += ("  {0} - {1}" -f $adapter.Name, $adapter.Description)
        }
    }
    $lines += ""

    $lines += "Related running services:"
    if ($services.Count -eq 0) {
        $lines += "  none detected"
    } else {
        foreach ($svc in $services) {
            $lines += ("  {0} - {1}" -f $svc.Name, $svc.DisplayName)
        }
    }
    $lines += ""
    $lines += "If nonpaged pool is high, close TUN mode, disable the virtual adapter, or update/restart the related driver. This tool cannot safely force-release leaked nonpaged pool from user mode."

    [System.Windows.MessageBox]::Show(($lines -join [Environment]::NewLine), (Get-UiText 'KernelMemoryTitle'), 'OK', 'Information') | Out-Null
}

function Show-SettingsWindow {
    $settingsWindow = New-Object System.Windows.Window
    $settingsWindow.Title = Get-UiText 'DisplaySettings'
    $settingsWindow.Width = 390
    $settingsWindow.Height = 350
    $settingsWindow.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $settingsWindow.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    $settingsWindow.Owner = $window
    $settingsWindow.Topmost = $true
    $settingsWindow.Background = [System.Windows.Media.Brushes]::White

    $rootPanel = New-Object System.Windows.Controls.StackPanel
    $rootPanel.Margin = New-Object System.Windows.Thickness(22)
    $rootPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = Get-UiText 'DisplaySettings'
    $titleBlock.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $titleBlock.FontSize = 18
    $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleBlock.Margin = New-Object System.Windows.Thickness(0, 0, 0, 14)
    [void]$rootPanel.Children.Add($titleBlock)

    $speedCheck = New-Object System.Windows.Controls.CheckBox
    $speedCheck.Content = Get-UiText 'ShowSpeed'
    $speedCheck.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $speedCheck.FontSize = 14
    $speedCheck.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
    $speedCheck.IsChecked = [bool]$script:uiSettings.ShowNetworkSpeed
    [void]$rootPanel.Children.Add($speedCheck)

    $locationCheck = New-Object System.Windows.Controls.CheckBox
    $locationCheck.Content = Get-UiText 'ShowLocation'
    $locationCheck.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $locationCheck.FontSize = 14
    $locationCheck.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
    $locationCheck.IsChecked = [bool]$script:uiSettings.ShowNetworkLocation
    [void]$rootPanel.Children.Add($locationCheck)

    $languagePanel = New-Object System.Windows.Controls.StackPanel
    $languagePanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $languagePanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

    $languageLabel = New-Object System.Windows.Controls.TextBlock
    $languageLabel.Text = Get-UiText 'Language'
    $languageLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $languageLabel.FontSize = 14
    $languageLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $languageLabel.Width = 82

    $languageBox = New-Object System.Windows.Controls.ComboBox
    $languageBox.Width = 150
    $languageBox.Height = 28
    $languageBox.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')

    $englishItem = New-Object System.Windows.Controls.ComboBoxItem
    $englishItem.Content = Get-UiText 'English'
    $englishItem.Tag = 'en'
    $chineseItem = New-Object System.Windows.Controls.ComboBoxItem
    $chineseItem.Content = Get-UiText 'Chinese'
    $chineseItem.Tag = 'zh'
    [void]$languageBox.Items.Add($englishItem)
    [void]$languageBox.Items.Add($chineseItem)
    if (([string]$script:uiSettings.Language).ToLowerInvariant() -eq 'zh') {
        $languageBox.SelectedItem = $chineseItem
    } else {
        $languageBox.SelectedItem = $englishItem
    }

    [void]$languagePanel.Children.Add($languageLabel)
    [void]$languagePanel.Children.Add($languageBox)
    [void]$rootPanel.Children.Add($languagePanel)

    $iconPanel = New-Object System.Windows.Controls.StackPanel
    $iconPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $iconPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

    $iconLabel = New-Object System.Windows.Controls.TextBlock
    $iconLabel.Text = Get-UiText 'IconStyle'
    $iconLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $iconLabel.FontSize = 14
    $iconLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $iconLabel.Width = 82

    $iconBox = New-Object System.Windows.Controls.ComboBox
    $iconBox.Width = 150
    $iconBox.Height = 28
    $iconBox.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')

    $barsItem = New-Object System.Windows.Controls.ComboBoxItem
    $barsItem.Content = Get-UiText 'IconBars'
    $barsItem.Tag = 'bars'
    $leafItem = New-Object System.Windows.Controls.ComboBoxItem
    $leafItem.Content = Get-UiText 'IconLeaf'
    $leafItem.Tag = 'leaf'
    $boltItem = New-Object System.Windows.Controls.ComboBoxItem
    $boltItem.Content = Get-UiText 'IconBolt'
    $boltItem.Tag = 'bolt'
    $sparkItem = New-Object System.Windows.Controls.ComboBoxItem
    $sparkItem.Content = Get-UiText 'IconSpark'
    $sparkItem.Tag = 'spark'
    $shieldItem = New-Object System.Windows.Controls.ComboBoxItem
    $shieldItem.Content = Get-UiText 'IconShield'
    $shieldItem.Tag = 'shield'

    foreach ($item in @($barsItem, $leafItem, $boltItem, $sparkItem, $shieldItem)) {
        [void]$iconBox.Items.Add($item)
    }

    $currentIconStyle = ([string]$script:uiSettings.IconStyle).ToLowerInvariant()
    foreach ($item in $iconBox.Items) {
        if ([string]$item.Tag -eq $currentIconStyle) {
            $iconBox.SelectedItem = $item
            break
        }
    }
    if ($null -eq $iconBox.SelectedItem) { $iconBox.SelectedItem = $barsItem }

    [void]$iconPanel.Children.Add($iconLabel)
    [void]$iconPanel.Children.Add($iconBox)
    [void]$rootPanel.Children.Add($iconPanel)

    $hintBlock = New-Object System.Windows.Controls.TextBlock
    $hintBlock.Text = Get-UiText 'SettingsHint'
    $hintBlock.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $hintBlock.FontSize = 12
    $hintBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(105, 116, 128))
    $hintBlock.Margin = New-Object System.Windows.Thickness(0, 0, 0, 18)
    [void]$rootPanel.Children.Add($hintBlock)

    $normalHintBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(105, 116, 128))
    $successHintBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(32, 148, 92))
    $errorHintBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(196, 48, 48))
    $normalButtonBrush = $saveButtonBackground = $null

    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $buttonPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right

    $saveButton = New-Object System.Windows.Controls.Button
    $saveButton.Content = Get-UiText 'Save'
    $saveButton.Width = 82
    $saveButton.Height = 32
    $saveButton.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $saveButton.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $normalButtonBrush = $saveButton.Background

    $cancelButton = New-Object System.Windows.Controls.Button
    $cancelButton.Content = Get-UiText 'Cancel'
    $cancelButton.Width = 82
    $cancelButton.Height = 32
    $cancelButton.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')

    [void]$buttonPanel.Children.Add($saveButton)
    [void]$buttonPanel.Children.Add($cancelButton)
    [void]$rootPanel.Children.Add($buttonPanel)

    function Update-SettingsWindowText {
        $settingsWindow.Title = Get-UiText 'DisplaySettings'
        $titleBlock.Text = Get-UiText 'DisplaySettings'
        $speedCheck.Content = Get-UiText 'ShowSpeed'
        $locationCheck.Content = Get-UiText 'ShowLocation'
        $languageLabel.Text = Get-UiText 'Language'
        $englishItem.Content = Get-UiText 'English'
        $chineseItem.Content = Get-UiText 'Chinese'
        $iconLabel.Text = Get-UiText 'IconStyle'
        $barsItem.Content = Get-UiText 'IconBars'
        $leafItem.Content = Get-UiText 'IconLeaf'
        $boltItem.Content = Get-UiText 'IconBolt'
        $sparkItem.Content = Get-UiText 'IconSpark'
        $shieldItem.Content = Get-UiText 'IconShield'
        $saveButton.Content = Get-UiText 'Save'
        $cancelButton.Content = Get-UiText 'Cancel'
        $hintBlock.Text = Get-UiText 'SettingsHint'
    }

    function Show-SettingsFeedback {
        param([bool]$Success)
        if ($Success) {
            $hintBlock.Text = Get-UiText 'Saved'
            $hintBlock.Foreground = $successHintBrush
            $saveButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(48, 209, 88))
            $saveButton.Foreground = [System.Windows.Media.Brushes]::White
        } else {
            $hintBlock.Text = Get-UiText 'SaveFailed'
            $hintBlock.Foreground = $errorHintBrush
        }

        $feedbackTimer = New-Object System.Windows.Threading.DispatcherTimer
        $feedbackTimer.Interval = [TimeSpan]::FromMilliseconds(1600)
        $feedbackTimer.Add_Tick({
            $feedbackTimer.Stop()
            $hintBlock.Text = Get-UiText 'SettingsHint'
            $hintBlock.Foreground = $normalHintBrush
            $saveButton.Background = $normalButtonBrush
            $saveButton.Foreground = [System.Windows.SystemColors]::ControlTextBrush
        })
        $feedbackTimer.Start()
    }

    $saveButton.Add_Click({
        try {
            $script:uiSettings.ShowNetworkSpeed = [bool]$speedCheck.IsChecked
            $script:uiSettings.ShowNetworkLocation = [bool]$locationCheck.IsChecked
            if ($null -ne $languageBox.SelectedItem -and -not [string]::IsNullOrWhiteSpace([string]$languageBox.SelectedItem.Tag)) {
                $script:uiSettings.Language = [string]$languageBox.SelectedItem.Tag
            } else {
                $script:uiSettings.Language = 'en'
            }
            if ($null -ne $iconBox.SelectedItem -and -not [string]::IsNullOrWhiteSpace([string]$iconBox.SelectedItem.Tag)) {
                $script:uiSettings.IconStyle = [string]$iconBox.SelectedItem.Tag
            } else {
                $script:uiSettings.IconStyle = 'bars'
            }
            Save-Settings $script:uiSettings
            $script:uiSettings = Get-Settings
            Reset-NetworkStatusCache
            Update-SettingsWindowText
            Apply-UiSettings
            Show-SettingsFeedback $true
            Write-AppLog "settings saved: speed=$($script:uiSettings.ShowNetworkSpeed) location=$($script:uiSettings.ShowNetworkLocation) language=$($script:uiSettings.Language) icon=$($script:uiSettings.IconStyle)"
        } catch {
            Write-AppLog "settings save failed: $($_.Exception.Message)"
            Show-SettingsFeedback $false
        }
    })
    $cancelButton.Add_Click({ $settingsWindow.Close() })

    $settingsWindow.Content = $rootPanel
    [void]$settingsWindow.ShowDialog()
}

$cleanItem.Add_Click({ Run-UiCleanup })
$kernelItem.Add_Click({ Show-KernelMemoryWindow })
$settingsItem.Add_Click({ Show-SettingsWindow })
$logItem.Add_Click({
    if (-not (Test-Path $script:LogPath)) { New-Item -ItemType File -Path $script:LogPath -Force | Out-Null }
    Start-Process notepad.exe $script:LogPath
})
$folderItem.Add_Click({ Start-Process explorer.exe $script:AppRoot })
$exitItem.Add_Click({
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    $window.Close()
})

$root.Add_MouseEnter({ Set-WpfOpacity $hoverLayer 1.0 140 })
$root.Add_MouseLeave({
    Set-WpfOpacity $hoverLayer 0.0 180
    Set-IconPressVisual $false
})
$root.Add_MouseRightButtonUp({
    $pos = [System.Windows.Forms.Cursor]::Position
    $menu.Show($pos)
})
$script:isDraggingWindow = $false
$script:dragMovedWindow = $false
$script:dragWasIconPress = $false
$script:dragStartPoint = $null
$script:dragStartLeftPx = 0
$script:dragStartTopPx = 0
$script:dragWindowHandle = [IntPtr]::Zero

function Sync-WindowPositionFromNativeRect {
    try {
        if ($script:dragWindowHandle -eq [IntPtr]::Zero) { return }
        $rect = New-Object NativeMemoryCleaner+RECT
        if (-not [NativeMemoryCleaner]::GetWindowRect($script:dragWindowHandle, [ref]$rect)) { return }
        $source = [System.Windows.PresentationSource]::FromVisual($window)
        if ($null -ne $source -and $null -ne $source.CompositionTarget) {
            $point = New-Object System.Windows.Point([double]$rect.Left, [double]$rect.Top)
            $logicalPoint = $source.CompositionTarget.TransformFromDevice.Transform($point)
            $window.Left = $logicalPoint.X
            $window.Top = $logicalPoint.Y
        }
    } catch {}
}

$root.Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($root.IsEnabled -eq $false) { return }
    if ($script:cleanupInProgress) {
        $e.Handled = $true
        return
    }

    $wasIconPress = ($e.OriginalSource -eq $iconButton -or $iconButton.IsAncestorOf($e.OriginalSource))
    Ensure-NativeApis
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    $script:dragWindowHandle = $helper.Handle
    $rect = New-Object NativeMemoryCleaner+RECT
    if ($script:dragWindowHandle -eq [IntPtr]::Zero -or -not [NativeMemoryCleaner]::GetWindowRect($script:dragWindowHandle, [ref]$rect)) {
        $e.Handled = $true
        return
    }

    $script:isDraggingWindow = $true
    $script:dragMovedWindow = $false
    $script:dragWasIconPress = $wasIconPress
    $script:dragStartPoint = [System.Windows.Forms.Control]::MousePosition
    $script:dragStartLeftPx = [int]$rect.Left
    $script:dragStartTopPx = [int]$rect.Top
    $root.CaptureMouse() | Out-Null

    if ($wasIconPress) {
        Set-IconPressVisual $true
    }

    $e.Handled = $true
})

$root.Add_MouseMove({
    param($sender, $e)
    if (-not $script:isDraggingWindow) { return }

    $current = [System.Windows.Forms.Control]::MousePosition
    $dx = [double]$current.X - [double]$script:dragStartPoint.X
    $dy = [double]$current.Y - [double]$script:dragStartPoint.Y
    if ([math]::Abs($dx) -gt 2 -or [math]::Abs($dy) -gt 2) {
        $script:dragMovedWindow = $true
    }

    $newLeft = $script:dragStartLeftPx + [int][math]::Round($dx)
    $newTop = $script:dragStartTopPx + [int][math]::Round($dy)
    [void][NativeMemoryCleaner]::SetWindowPos($script:dragWindowHandle, [IntPtr]::Zero, $newLeft, $newTop, 0, 0, 0x0015)
    $e.Handled = $true
})

$root.Add_MouseLeftButtonUp({
    param($sender, $e)
    if (-not $script:isDraggingWindow) { return }

    $script:isDraggingWindow = $false
    try { $root.ReleaseMouseCapture() } catch {}
    Sync-WindowPositionFromNativeRect
    Set-IconPressVisual $false

    if ($script:dragWasIconPress -and -not $script:dragMovedWindow) {
        Run-UiCleanup
    } else {
        Queue-PostDragRefresh
    }
    $e.Handled = $true
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(10)
$timer.Add_Tick({
    if (-not $script:isDraggingWindow -and -not $script:cleanupInProgress) { Update-ButtonText }
})
$timer.Start()
Update-ButtonText

$netTimer = New-Object System.Windows.Threading.DispatcherTimer
$netTimer.Interval = [TimeSpan]::FromSeconds(3)
$netTimer.Add_Tick({
    if (-not $script:isDraggingWindow -and -not $script:cleanupInProgress) { Update-NetworkText }
})
$netTimer.Start()
Apply-UiSettings

$logMaintenanceTimer = New-Object System.Windows.Threading.DispatcherTimer
$logMaintenanceTimer.Interval = [TimeSpan]::FromHours(6)
$logMaintenanceTimer.Add_Tick({ Invoke-LogMaintenance })
$logMaintenanceTimer.Start()

$window.Add_Closed({
    $timer.Stop()
    $netTimer.Stop()
    $logMaintenanceTimer.Stop()
    if ($null -ne $script:postDragRefreshTimer) {
        try { $script:postDragRefreshTimer.Stop() } catch {}
    }
    if ($null -ne $script:geoLookupJob) {
        try { Remove-Job -Job $script:geoLookupJob -Force | Out-Null } catch {}
        $script:geoLookupJob = $null
    }
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    if ($null -ne $script:singleInstanceMutex) {
        try { $script:singleInstanceMutex.ReleaseMutex() | Out-Null } catch {}
        $script:singleInstanceMutex.Dispose()
    }
})

Write-AppLog 'Memory Cleaner Float started with WPF UI.'
$app = New-Object System.Windows.Application
$app.Run($window) | Out-Null
exit

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$appIconPath = Join-Path $script:AppRoot 'lightning.ico'
if (Test-Path $appIconPath) {
    try { $script:notifyIcon.Icon = New-Object System.Drawing.Icon($appIconPath) } catch {}
}
if ($null -eq $script:notifyIcon.Icon) {
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
}
$script:notifyIcon.Text = 'Memory Cleaner Float'
$script:notifyIcon.Visible = $true

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Memory Cleaner Float'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.Width = 158
$form.Height = 62
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)
$form.Opacity = 0.97
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Left = $screen.Right - 190
$form.Top = [math]::Max(20, [int]($screen.Height * 0.35))

function New-RoundedRectPath {
    param(
        [System.Drawing.Rectangle]$Bounds,
        [int]$Radius
    )
    $diameter = $Radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($Bounds.X, $Bounds.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Bounds.X, $Bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

$formBounds = New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)
$form.Region = New-Object System.Drawing.Region((New-RoundedRectPath $formBounds 24))

$script:memoryPercent = 0
$script:isBusy = $false
$script:isHover = $false

$surface = New-Object System.Windows.Forms.Panel
$surface.Dock = 'Fill'
$surface.BackColor = [System.Drawing.Color]::Transparent
$surface.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($surface)

$titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Regular)
$percentFont = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Regular)
$smallFont = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Regular)

$surface.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $rect = New-Object System.Drawing.Rectangle(1, 1, $surface.Width - 3, $surface.Height - 3)
    $panelPath = New-RoundedRectPath $rect 23
    $topColor = if ($script:isHover) { [System.Drawing.Color]::FromArgb(255, 255, 255) } else { [System.Drawing.Color]::FromArgb(249, 251, 253) }
    $bottomColor = if ($script:isHover) { [System.Drawing.Color]::FromArgb(232, 239, 248) } else { [System.Drawing.Color]::FromArgb(225, 233, 243) }
    $panelBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $topColor, $bottomColor, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillPath($panelBrush, $panelPath)
    $panelBrush.Dispose()

    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(178, 194, 210), 1)
    $g.DrawPath($borderPen, $panelPath)
    $borderPen.Dispose()
    $panelPath.Dispose()

    $iconRect = New-Object System.Drawing.Rectangle(13, 13, 36, 36)
    $iconBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($iconRect, [System.Drawing.Color]::FromArgb(10, 132, 255), [System.Drawing.Color]::FromArgb(90, 200, 250), [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $g.FillEllipse($iconBrush, $iconRect)
    $iconBrush.Dispose()

    $iconPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
    $iconPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $iconPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($iconPen, 25, 22, 25, 40)
    $g.DrawLine($iconPen, 32, 26, 32, 40)
    $g.DrawLine($iconPen, 39, 19, 39, 40)
    $iconPen.Dispose()

    $title = if ($script:isBusy) { 'Cleaning' } else { 'Clean' }
    $percent = '{0}%' -f $script:memoryPercent
    $textColor = [System.Drawing.Color]::FromArgb(28, 35, 43)
    $mutedColor = [System.Drawing.Color]::FromArgb(92, 103, 115)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $title, $titleFont, (New-Object System.Drawing.Rectangle(60, 10, 86, 17)), $mutedColor, [System.Windows.Forms.TextFormatFlags]::NoPadding)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $percent, $percentFont, (New-Object System.Drawing.Rectangle(59, 25, 88, 25)), $textColor, [System.Windows.Forms.TextFormatFlags]::NoPadding)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'RAM', $smallFont, (New-Object System.Drawing.Rectangle(119, 32, 28, 14)), $mutedColor, [System.Windows.Forms.TextFormatFlags]::NoPadding)
})

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($surface, 'Left click: clean memory. Right click: menu.')

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$cleanItem = $menu.Items.Add('Clean now')
$previewItem = $menu.Items.Add('Preview close list')
$menu.Items.Add('-') | Out-Null
$settingsItem = $menu.Items.Add('Open settings.json')
$logItem = $menu.Items.Add('Open cleaner.log')
$folderItem = $menu.Items.Add('Open folder')
$menu.Items.Add('-') | Out-Null
$exitItem = $menu.Items.Add('Exit')
$surface.ContextMenuStrip = $menu
$script:notifyIcon.ContextMenuStrip = $menu

function Update-ButtonText {
    $mem = Get-MemoryInfo
    $script:memoryPercent = [int]$mem.UsedPercent
    $surface.Invalidate()
}

function Show-Balloon {
    param([string]$Title, [string]$Text)
    $script:notifyIcon.BalloonTipTitle = $Title
    $script:notifyIcon.BalloonTipText = $Text
    $script:notifyIcon.ShowBalloonTip(2500)
}

function Run-UiCleanup {
    $surface.Enabled = $false
    $script:isBusy = $true
    $surface.Invalidate()
    [System.Windows.Forms.Application]::DoEvents()
    $result = Invoke-Cleanup
    $script:isBusy = $false
    Update-ButtonText
    $surface.Enabled = $true
    $freed = [math]::Max(0, $result.After.FreeMB - $result.Before.FreeMB)
    Show-Balloon 'Memory cleaned' "Freed about $freed MB; closed $($result.ClosedCount) background process(es)."
}

function Show-PreviewWindow {
    $result = Invoke-Cleanup -PreviewOnly
    $lines = @()
    $lines += "These background processes would be closed by Clean now:"
    $lines += ""
    if (@($result.Candidates).Count -eq 0) {
        $lines += "No close candidates right now. Memory trim will still run."
    } else {
        foreach ($c in $result.Candidates) {
            $lines += ("{0,7} MB   PID {1,-7} {2}" -f $c.MemoryMB, $c.Id, $c.Name)
        }
    }
    $lines += ""
    $lines += "Edit settings.json to add KeepProcessNames or CloseProcessNames."
    [System.Windows.Forms.MessageBox]::Show(($lines -join [Environment]::NewLine), 'Preview close list', 'OK', 'Information') | Out-Null
}

$surface.Add_Click({
    if ($script:suppressNextClick) {
        $script:suppressNextClick = $false
        return
    }
    Run-UiCleanup
})
$cleanItem.Add_Click({ Run-UiCleanup })
$previewItem.Add_Click({ Show-PreviewWindow })
$settingsItem.Add_Click({ Start-Process notepad.exe $script:SettingsPath })
$logItem.Add_Click({
    if (-not (Test-Path $script:LogPath)) { New-Item -ItemType File -Path $script:LogPath -Force | Out-Null }
    Start-Process notepad.exe $script:LogPath
})
$folderItem.Add_Click({ Start-Process explorer.exe $script:AppRoot })
$exitItem.Add_Click({
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    $form.Close()
})

$surface.Add_MouseEnter({
    $script:isHover = $true
    $surface.Invalidate()
})
$surface.Add_MouseLeave({
    $script:isHover = $false
    $surface.Invalidate()
})

$script:dragging = $false
$script:dragMoved = $false
$script:suppressNextClick = $false
$script:dragStart = New-Object System.Drawing.Point
$script:formStart = New-Object System.Drawing.Point
$surface.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:dragging = $true
        $script:dragMoved = $false
        $script:dragStart = [System.Windows.Forms.Control]::MousePosition
        $script:formStart = $form.Location
    }
})
$surface.Add_MouseMove({
    param($sender, $e)
    if ($script:dragging) {
        $pos = [System.Windows.Forms.Control]::MousePosition
        if ([math]::Abs($pos.X - $script:dragStart.X) -gt 3 -or [math]::Abs($pos.Y - $script:dragStart.Y) -gt 3) {
            $script:dragMoved = $true
        }
        $form.Left = $script:formStart.X + ($pos.X - $script:dragStart.X)
        $form.Top = $script:formStart.Y + ($pos.Y - $script:dragStart.Y)
    }
})
$surface.Add_MouseUp({
    if ($script:dragMoved) {
        $script:suppressNextClick = $true
    }
    $script:dragging = $false
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-ButtonText })
$timer.Start()
Update-ButtonText

$form.Add_FormClosed({
    $timer.Stop()
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
})

Write-AppLog 'Memory Cleaner Float started.'
[System.Windows.Forms.Application]::Run($form)
