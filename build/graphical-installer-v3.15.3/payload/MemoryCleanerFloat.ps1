param(
    [switch]$RunOnce,
    [switch]$Preview,
    [switch]$Diagnostics,
    # Internal regression-test entry point. It only opens the normal settings
    # window after startup and has no effect during ordinary launches.
    [switch]$OpenSettingsForTest
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
$script:CustomAppearancePath = Join-Path $script:AppRoot 'custom-appearance.png'
$script:AppVersion = '3.15.3'

function Write-AppLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
}

function Get-DefaultSettings {
    $windhawkCandidates = @(
        (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk\windhawk.exe'),
        'D:\Windhawk\windhawk.exe'
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$script:AppRoot)) {
        $windhawkCandidates += Join-Path $script:AppRoot 'Windhawk\windhawk.exe'
    }
    $defaultWindhawkPath = $windhawkCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($defaultWindhawkPath)) {
        $defaultWindhawkPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk\windhawk.exe'
    }
    [pscustomobject]@{
        MinTrimMemoryMB = 10
        TrimPressurePercent = 0
        ConservativeWorkingSetTrim = $false
        MinCloseMemoryMB = 120
        AggressiveBackgroundClose = $false
        ShowNetworkSpeed = $true
        ShowNetworkLocation = $true
        Language = 'zh'
        IconStyle = 'bolt'
        UseCustomAppearance = $false
        UseBackgroundColor = $false
        BackgroundColor = '#F0F0F2'
        # Stored value is the user-visible transparency percentage: 90 means
        # almost transparent; 20 means mostly opaque.
        BackgroundOpacity = 20
        CustomAppearanceReady = $false
        CustomAppearanceFile = 'custom-appearance.png'
        DisplayMode = 'taskbar'
        TaskbarPosition = 'left'
        TaskbarOffset = 0
        WindhawkPath = $defaultWindhawkPath
        AutoCleanupIntervalMinutes = 30
        LogCleanupIntervalDays = 1
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
            'ChatGPT','Xmind','full-line-inference',
            'Weixin','WeChat','WeChatAppEx','QQ','TIM','DingTalk',
            'Typora','Yuque','wps','wpp','et','winword','excel','powerpnt',
            'Clash for Windows','Clash Verge','Clash Party',
            'mihomo','OneDrive','OneDrive.Sync.Service','Snipaste',
            'wetype_server','YoudaoDict','YoudaoDictHelper',
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
            'Microsoft.Photos','Photos','OneDriveStandaloneUpdater',
            'OverlayHelper','HP.OMEN.Overlay.OverlayHelper',
            'OmenInstallMonitor','OmenCommandCenterBackground',
            'wpsupdate','WPSUpdate'
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
        if ($null -eq $settings.UseCustomAppearance) { $settings | Add-Member -NotePropertyName UseCustomAppearance -NotePropertyValue $false }
        if ($null -eq $settings.UseBackgroundColor) { $settings | Add-Member -NotePropertyName UseBackgroundColor -NotePropertyValue $false }
        if ($null -eq $settings.BackgroundColor) { $settings | Add-Member -NotePropertyName BackgroundColor -NotePropertyValue '#F0F0F2' }
        if ($null -eq $settings.BackgroundOpacity) { $settings | Add-Member -NotePropertyName BackgroundOpacity -NotePropertyValue 20 }
        if ($null -eq $settings.CustomAppearanceReady) { $settings | Add-Member -NotePropertyName CustomAppearanceReady -NotePropertyValue $false }
        if ($null -eq $settings.CustomAppearanceFile) { $settings | Add-Member -NotePropertyName CustomAppearanceFile -NotePropertyValue 'custom-appearance.png' }
        if ($null -eq $settings.DisplayMode) { $settings | Add-Member -NotePropertyName DisplayMode -NotePropertyValue 'taskbar' }
        if ($null -eq $settings.TaskbarPosition) { $settings | Add-Member -NotePropertyName TaskbarPosition -NotePropertyValue 'left' }
        if ($null -eq $settings.TaskbarOffset) { $settings | Add-Member -NotePropertyName TaskbarOffset -NotePropertyValue 0 }
        $parsedTaskbarOffset = 0
        if (-not [int]::TryParse([string]$settings.TaskbarOffset, [ref]$parsedTaskbarOffset)) { $parsedTaskbarOffset = 0 }
        $settings.TaskbarOffset = [math]::Min(1600, [math]::Max(0, $parsedTaskbarOffset))
        if ($null -eq $settings.WindhawkPath) { $settings | Add-Member -NotePropertyName WindhawkPath -NotePropertyValue (Get-DefaultSettings).WindhawkPath }
        if ($null -eq $settings.TrimPressurePercent) { $settings | Add-Member -NotePropertyName TrimPressurePercent -NotePropertyValue 0 }
        if ($null -eq $settings.ConservativeWorkingSetTrim) { $settings | Add-Member -NotePropertyName ConservativeWorkingSetTrim -NotePropertyValue $false }
        if ($null -eq $settings.AutoCleanupIntervalMinutes) { $settings | Add-Member -NotePropertyName AutoCleanupIntervalMinutes -NotePropertyValue 30 }
        if ($null -eq $settings.LogCleanupIntervalDays) { $settings | Add-Member -NotePropertyName LogCleanupIntervalDays -NotePropertyValue 1 }
        if ($null -eq $settings.LogRetentionDays) { $settings | Add-Member -NotePropertyName LogRetentionDays -NotePropertyValue 7 }
        return $settings
    } catch {
        Write-AppLog "settings.json could not be read, using defaults: $($_.Exception.Message)"
        return Get-DefaultSettings
    }
}

function Get-AutoCleanupIntervalMinutes {
    param($Settings)

    $minutes = 30
    $rawValue = $null
    try { $rawValue = $Settings.AutoCleanupIntervalMinutes } catch {}
    if ($null -eq $rawValue -or [string]::IsNullOrWhiteSpace([string]$rawValue)) { return $minutes }

    $parsedMinutes = 0
    if (-not [int]::TryParse(([string]$rawValue).Trim(), [ref]$parsedMinutes)) { return $minutes }
    return [math]::Min(1440, [math]::Max(1, $parsedMinutes))
}

function Get-LogRetentionDays {
    param($Settings)

    $days = 7
    $rawValue = $null
    try { $rawValue = $Settings.LogRetentionDays } catch {}
    if ($null -eq $rawValue -or [string]::IsNullOrWhiteSpace([string]$rawValue)) { return $days }

    $parsedDays = 0
    if (-not [int]::TryParse(([string]$rawValue).Trim(), [ref]$parsedDays)) { return $days }
    return [math]::Min(30, [math]::Max(1, $parsedDays))
}

function Get-BackgroundColorHex {
    param($Settings)

    $value = '#F0F0F2'
    try { $value = ([string]$Settings.BackgroundColor).Trim().ToUpperInvariant() } catch {}
    if ($value -notmatch '^#[0-9A-F]{6}$') { return '#303033' }
    return $value
}

function Get-BackgroundTransparency {
    param($Settings)

    $transparency = 20
    try {
        $parsed = 0
        if ([int]::TryParse([string]$Settings.BackgroundOpacity, [ref]$parsed)) { $transparency = $parsed }
    } catch {}
    return [math]::Min(90, [math]::Max(20, $transparency))
}

function Get-BackgroundAlphaPercent {
    param($Settings)

    return 100 - (Get-BackgroundTransparency $Settings)
}

function Test-TaskbarEjectSuppressed {
    param(
        [bool]$TaskbarModeActive,
        [datetime]$GuardUntil,
        [datetime]$Now = (Get-Date)
    )

    return $TaskbarModeActive -and $GuardUntil -gt $Now
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
    param([switch]$Force)

    $settings = Get-Settings
    $intervalDays = 1
    $retentionDays = Get-LogRetentionDays $settings
    $state = Get-AppState
    $now = Get-Date
    $shouldRun = $true

    if (-not $Force -and -not [string]::IsNullOrWhiteSpace([string]$state.LastLogCleanupAt)) {
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

function Clear-AppLog {
    Set-Content -Path $script:LogPath -Value @() -Encoding UTF8
    $state = Get-AppState
    $state.LastLogCleanupAt = (Get-Date).ToString('o')
    Save-AppState $state
    Write-AppLog 'log cleared manually'
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

    [StructLayout(LayoutKind.Sequential)]
    public struct PERFORMANCE_INFORMATION {
        public uint cb;
        public ulong CommitTotal;
        public ulong CommitLimit;
        public ulong CommitPeak;
        public ulong PhysicalTotal;
        public ulong PhysicalAvailable;
        public ulong SystemCache;
        public ulong KernelTotal;
        public ulong KernelPaged;
        public ulong KernelNonpaged;
        public ulong PageSize;
        public uint HandleCount;
        public uint ProcessCount;
        public uint ThreadCount;
    }

    [DllImport("psapi.dll", SetLastError=true)]
    public static extern bool GetPerformanceInfo(out PERFORMANCE_INFORMATION pPerformanceInformation, uint cb);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct PROCESSENTRY32 {
        public uint dwSize;
        public uint cntUsage;
        public uint th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID;
        public uint cntThreads;
        public uint th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExeFile;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool Process32First(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool Process32Next(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")]
    public static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr FindWindowEx(IntPtr hWndParent, IntPtr hWndChildAfter, string lpszClass, string lpszWindow);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hWnd);

    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    [DllImport("ntdll.dll")]
    public static extern int NtQuerySystemInformation(int systemInformationClass, IntPtr systemInformation, int systemInformationLength, out int returnLength);

    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, uint dwFlags);
}
"@
    Add-Type -TypeDefinition $code
}

function Set-WpfTaskbarButtonVisibility {
    param(
        [System.Windows.Window]$TargetWindow,
        [bool]$Visible
    )
    try {
        Ensure-NativeApis
        $interop = New-Object System.Windows.Interop.WindowInteropHelper($TargetWindow)
        $handle = $interop.Handle
        if ($handle -eq [IntPtr]::Zero) { $handle = $interop.EnsureHandle() }
        if ($handle -eq [IntPtr]::Zero) { return $false }
        $extendedStyle = [NativeMemoryCleaner]::GetWindowLongPtr($handle, -20).ToInt64()
        if ($Visible) {
            $extendedStyle = ($extendedStyle -bor 0x40000L) -band (-bnot 0x80L)
        } else {
            $extendedStyle = ($extendedStyle -bor 0x80L) -band (-bnot 0x40000L)
        }
        [void][NativeMemoryCleaner]::SetWindowLongPtr($handle, -20, [IntPtr]$extendedStyle)
        # Refresh non-client styles without moving, resizing, activating, or
        # changing the floating panel's topmost order.
        [void][NativeMemoryCleaner]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0037)
        return $true
    } catch {
        Write-AppLog "taskbar button style update failed: $($_.Exception.Message)"
        return $false
    }
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
    param([switch]$SkipStandby)
    # Reads kernel memory via GetPerformanceInfo (psapi) instead of the WMI
    # performance counter query (Win32_PerfFormattedData_PerfOS_Memory). The
    # WMI query can hang for tens of seconds when the performance library
    # stalls, which made cleaning look stuck and occasionally hit the 120s
    # worker timeout. GetPerformanceInfo is a fast native call that never
    # blocks on the performance library.
    Ensure-NativeApis
    try {
        $pi = New-Object NativeMemoryCleaner+PERFORMANCE_INFORMATION
        $pi.cb = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][NativeMemoryCleaner+PERFORMANCE_INFORMATION])
        if (-not [NativeMemoryCleaner]::GetPerformanceInfo([ref]$pi, $pi.cb)) { throw 'GetPerformanceInfo failed' }
        # GetPerformanceInfo reports sizes in pages, not bytes.
        $pageSize = [double]$pi.PageSize
        $nonPagedMB = [math]::Round($pi.KernelNonpaged * $pageSize / 1MB, 0)
        $pagedMB = [math]::Round($pi.KernelPaged * $pageSize / 1MB, 0)
        $cacheMB = [math]::Round($pi.SystemCache * $pageSize / 1MB, 0)
        $availableMB = [math]::Round($pi.PhysicalAvailable * $pageSize / 1MB, 0)
        $committedGB = [math]::Round($pi.CommitTotal * $pageSize / 1GB, 2)
        $commitLimitGB = [math]::Round($pi.CommitLimit * $pageSize / 1GB, 2)

        $standbyMB = 0
        $modifiedMB = 0
        if (-not $SkipStandby) {
            # Standby/modified lists have no public fast API; they are only
            # shown in the kernel-memory diagnostic window, where a slower
            # query is acceptable. The cleaning worker passes -SkipStandby.
            try {
                $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
                $standbyMB = [math]::Round(($mem.StandbyCacheCoreBytes + $mem.StandbyCacheNormalPriorityBytes + $mem.StandbyCacheReserveBytes) / 1MB, 0)
                $modifiedMB = [math]::Round($mem.ModifiedPageListBytes / 1MB, 0)
            } catch {}
        }

        $compressionMB = 0
        try {
            $compressionMB = [math]::Round(((Get-Process -Name 'Memory Compression' -ErrorAction Stop | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 0)
        } catch {}
        $isHigh = ($nonPagedMB -ge 2048)

        [pscustomobject]@{
            NonPagedPoolMB = $nonPagedMB
            PagedPoolMB = $pagedMB
            CacheMB = $cacheMB
            AvailableMB = $availableMB
            StandbyMB = $standbyMB
            ModifiedMB = $modifiedMB
            CompressionMB = $compressionMB
            CommittedGB = $committedGB
            CommitLimitGB = $commitLimitGB
            IsNonPagedPoolHigh = $isHigh
        }
    } catch {
        Write-AppLog "kernel memory query failed: $($_.Exception.Message)"
        [pscustomobject]@{
            NonPagedPoolMB = $null
            PagedPoolMB = $null
            CacheMB = $null
            AvailableMB = $null
            StandbyMB = $null
            ModifiedMB = $null
            CompressionMB = $null
            CommittedGB = $null
            CommitLimitGB = $null
            IsNonPagedPoolHigh = $false
        }
    }
}

function Get-PoolTagOwnerHint {
    param([string]$Tag)

    switch -Regex ($Tag) {
        '^RTLF$' { return 'Realtek LightWeight Filter (rtf64x64.sys)' }
        '^(NvLH|NvLD|NvLF|NVRM|nvpc)$' { return 'NVIDIA display driver (nvlddmkm.sys)' }
        '^(Via3|Via8|Vi08)$' { return 'DirectX graphics memory manager (dxgmms2.sys)' }
        '^EtwB$' { return 'Windows ETW trace buffers' }
        '^Toke$' { return 'Windows access tokens' }
        default { return 'unknown driver/component' }
    }
}

function Get-KernelPoolTags {
    param([int]$Top = 8)

    $buffer = [IntPtr]::Zero
    try {
        Ensure-NativeApis
        $length = 1MB
        while ($true) {
            $buffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($length)
            $returnLength = 0
            $status = [NativeMemoryCleaner]::NtQuerySystemInformation(22, $buffer, $length, [ref]$returnLength)
            if ($status -eq 0) { break }
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
            $buffer = [IntPtr]::Zero
            if ($status -ne -1073741820) { return @() }
            $length = [math]::Max($length * 2, $returnLength + 64KB)
            if ($length -gt 64MB) { return @() }
        }

        $count = [System.Runtime.InteropServices.Marshal]::ReadInt32($buffer)
        if ($count -lt 1 -or $count -gt 100000) { return @() }
        $headerSize = if ([IntPtr]::Size -eq 8) { 8 } else { 4 }
        $entrySize = if ([IntPtr]::Size -eq 8) { 40 } else { 28 }
        $pagedOffset = if ([IntPtr]::Size -eq 8) { 16 } else { 12 }
        $nonPagedOffset = if ([IntPtr]::Size -eq 8) { 32 } else { 24 }
        $items = New-Object 'System.Collections.Generic.List[object]'

        for ($index = 0; $index -lt $count; $index++) {
            $entry = [IntPtr]::Add($buffer, $headerSize + ($index * $entrySize))
            $tagBytes = New-Object byte[] 4
            [System.Runtime.InteropServices.Marshal]::Copy($entry, $tagBytes, 0, 4)
            $tag = [System.Text.Encoding]::ASCII.GetString($tagBytes)
            if ([IntPtr]::Size -eq 8) {
                $pagedBytes = [System.Runtime.InteropServices.Marshal]::ReadInt64($entry, $pagedOffset)
                $nonPagedBytes = [System.Runtime.InteropServices.Marshal]::ReadInt64($entry, $nonPagedOffset)
            } else {
                $pagedBytes = [uint32][System.Runtime.InteropServices.Marshal]::ReadInt32($entry, $pagedOffset)
                $nonPagedBytes = [uint32][System.Runtime.InteropServices.Marshal]::ReadInt32($entry, $nonPagedOffset)
            }
            if ($nonPagedBytes -lt 256KB) { continue }
            [void]$items.Add([pscustomobject]@{
                Tag = $tag
                PagedMB = [math]::Round($pagedBytes / 1MB, 1)
                NonPagedMB = [math]::Round($nonPagedBytes / 1MB, 1)
                Owner = Get-PoolTagOwnerHint $tag
            })
        }

        return @($items | Sort-Object NonPagedMB -Descending | Select-Object -First ([math]::Max(1, $Top)))
    } catch {
        Write-AppLog "pool tag query failed: $($_.Exception.Message)"
        return @()
    } finally {
        if ($buffer -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        }
    }
}

function Get-SuspectNetworkAdapters {
    $pattern = 'mihomo|meta tunnel|wintun|tap|tun|clash|vmware|hyper-v|vethernet|wsl|vpn|wireguard|ndis|virtual|vswitch'
    $items = @()
    try {
        $adapters = Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object {
            $_.Status -eq 'Up' -and ([string]$_.Name -match $pattern -or [string]$_.InterfaceDescription -match $pattern)
        }
        foreach ($adapter in $adapters) {
            $items += [pscustomobject]@{
                Name = [string]$adapter.Name
                Description = [string]$adapter.InterfaceDescription
            }
        }
    } catch {
        try {
            $adapters = Get-CimInstance Win32_NetworkAdapter | Where-Object {
                $_.NetEnabled -eq $true -and ([string]$_.Name -match $pattern -or [string]$_.Description -match $pattern -or [string]$_.NetConnectionID -match $pattern)
            }
            foreach ($adapter in $adapters) {
                $label = [string]$adapter.NetConnectionID
                if ([string]::IsNullOrWhiteSpace($label)) { $label = [string]$adapter.Name }
                $items += [pscustomobject]@{ Name = $label; Description = [string]$adapter.Description }
            }
        } catch {}
    }
    return $items | Sort-Object Name -Unique
}

function Get-SuspectNetworkBindings {
    $items = @()
    try {
        foreach ($binding in Get-NetAdapterBinding -AllBindings -IncludeHidden -ErrorAction Stop | Where-Object {
            $_.Enabled -eq $true -and ($_.ComponentID -eq 'nt_rtf64' -or $_.DisplayName -match 'Realtek LightWeight Filter')
        }) {
            $items += [pscustomobject]@{
                Name = [string]$binding.Name
                DisplayName = [string]$binding.DisplayName
                ComponentID = [string]$binding.ComponentID
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
    param($KernelInfo, $PoolTags)

    if ($null -eq $KernelInfo -or $null -eq $KernelInfo.NonPagedPoolMB) { return $null }
    if ($KernelInfo.IsNonPagedPoolHigh -ne $true) { return $null }

    $topTag = @($PoolTags | Sort-Object NonPagedMB -Descending | Select-Object -First 1)
    if ($topTag.Count -gt 0 -and $topTag[0].Tag -eq 'RTLF') {
        return "Nonpaged pool is $($KernelInfo.NonPagedPoolMB) MB. Top tag RTLF uses $($topTag[0].NonPagedMB) MB: Realtek LightWeight Filter (rtf64x64.sys). Normal process trimming cannot release it; update/restart or temporarily unbind that network filter to verify the leak."
    }
    if ($topTag.Count -gt 0) {
        return "Nonpaged pool is $($KernelInfo.NonPagedPoolMB) MB. Top tag $($topTag[0].Tag) uses $($topTag[0].NonPagedMB) MB ($($topTag[0].Owner)). Normal process trimming cannot release kernel/driver memory."
    }
    return "Nonpaged pool is $($KernelInfo.NonPagedPoolMB) MB. This is kernel/driver memory, so normal process trimming cannot release it."
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
            'Network' { return 'Network' }
            'Clean' { return 'Release' }
            'Cleaning' { return 'Releasing' }
            'Done' { return 'Done' }
            'Working' { return 'Cleaning memory...' }
            'Freed' { return 'Freed' }
            'CleanupFailedNoResult' { return 'Cleanup failed: no result' }
            'CleanupClosed' { return 'Freed {0} MB - closed {1} background apps' }
            'CleanupFreed' { return 'Freed {0} MB - memory {1}% to {2}%' }
            'CleanupNotNeeded' { return 'No cleanup needed - memory {0}%' }
            'CleanupNoReleasable' { return 'No releasable app memory - {0}%' }
            'CleanupStartFailed' { return 'Cleanup failed to start.' }
            'CleanupTimeout' { return 'Cleanup timed out. Try again later.' }
            'Preview' { return 'Preview ' }
            'Settings' { return 'Settings' }
            'Log' { return 'Log' }
            'Folder' { return 'Folder' }
            'Exit' { return 'Exit' }
            'ShowWindow' { return 'Show floating window' }
            'HideWindow' { return 'Hide floating window' }
            'TrayName' { return 'Memory Cleaner Float' }
            'SwitchToFloating' { return 'Switch to floating window' }
            'SwitchToTaskbar' { return 'Switch to taskbar status' }
            'TaskbarTooltip' { return 'Click anywhere to release memory. Right-click for menu.' }
            'DisplayPosition' { return 'Display position' }
            'TaskbarLeft' { return 'Taskbar - embedded' }
            'TaskbarRight' { return 'Taskbar - right' }
            'FloatingWindow' { return 'Floating window' }
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
            'AutoCleanupInterval' { return 'Auto release interval' }
            'MinutesRange' { return 'minutes (1-1440)' }
            'IntervalInvalid' { return 'Enter a whole number from 1 to 1440 minutes.' }
            'LogRetentionDays' { return 'Log retention' }
            'DaysRange' { return 'days (1-30)' }
            'RetentionInvalid' { return 'Enter a whole number from 1 to 30 days.' }
            'ClearLogNow' { return 'Clear log now' }
            'LogCleared' { return 'Log cleared' }
            'Appearance' { return 'Appearance' }
            'DefaultAppearance' { return 'Default appearance' }
            'BackgroundAppearance' { return 'Background color' }
            'ChooseColor' { return 'Choose color...' }
            'BackgroundOpacity' { return 'Transparency' }
            'CustomAppearance' { return 'Custom image' }
            'ChooseImage' { return 'Choose image...' }
            'ImageFormats' { return 'PNG, JPG, BMP, GIF, TIFF, or WebP' }
            'ImageSelected' { return 'Selected: {0}' }
            'ImageDecodeFailed' { return 'This image format cannot be decoded on this computer.' }
            'ImageRequired' { return 'Choose an image before enabling custom appearance.' }
            'TransparencyHint' { return 'Transparent images follow the subject outline; other images stay rectangular.' }
            'CustomTooltip' { return 'Click the image to release memory. Drag to move. Right-click for menu.' }
            'DefaultTooltip' { return 'Click the blue button to release. Drag the panel to move.' }
        'PreviewTitle' { return 'Close preview' }
        'PreviewIntro' { return 'Processes that would be closed:' }
        'PreviewNone' { return 'No background process would be closed now. Working-set trim only runs under high pressure and skips protected or visible apps.' }
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
        'Network' { return -join ([char]0x7F51, [char]0x7EDC) }
        'Clean' { return -join ([char]0x91CA, [char]0x653E) }
        'Cleaning' { return -join ([char]0x91CA, [char]0x653E, [char]0x4E2D) }
        'Done' { return -join ([char]0x5B8C, [char]0x6210) }
        'Working' { return -join ([char]0x6B63, [char]0x5728, [char]0x6E05, [char]0x7406, [char]0x5185, [char]0x5B58, [char]0x2026) }
        'Freed' { return -join ([char]0x5DF2, [char]0x91CA, [char]0x653E) }
        'CleanupFailedNoResult' { return (-join ([char]0x6E05, [char]0x7406, [char]0x5931, [char]0x8D25, [char]0xFF1A, [char]0x672A, [char]0x83B7, [char]0x53D6, [char]0x5230, [char]0x7ED3, [char]0x679C)) }
        'CleanupClosed' { return (-join ([char]0x5DF2, [char]0x91CA, [char]0x653E)) + ' {0} MB - ' + (-join ([char]0x5DF2, [char]0x5173, [char]0x95ED)) + ' {1} ' + (-join ([char]0x4E2A, [char]0x540E, [char]0x53F0, [char]0x8FDB, [char]0x7A0B)) }
        'CleanupFreed' { return (-join ([char]0x5DF2, [char]0x91CA, [char]0x653E)) + ' {0} MB - ' + (-join ([char]0x5185, [char]0x5B58)) + ' {1}% -> {2}%' }
        'CleanupNotNeeded' { return (-join ([char]0x65E0, [char]0x9700, [char]0x6E05, [char]0x7406)) + ' - ' + (-join ([char]0x5F53, [char]0x524D, [char]0x5185, [char]0x5B58)) + ' {0}%' }
        'CleanupNoReleasable' { return (-join ([char]0x6CA1, [char]0x6709, [char]0x53EF, [char]0x91CA, [char]0x653E, [char]0x5185, [char]0x5B58)) + ' - ' + (-join ([char]0x5F53, [char]0x524D)) + ' {0}%' }
        'CleanupStartFailed' { return (-join ([char]0x6E05, [char]0x7406, [char]0x5931, [char]0x8D25, [char]0xFF1A, [char]0x4EFB, [char]0x52A1, [char]0x65E0, [char]0x6CD5, [char]0x542F, [char]0x52A8)) }
        'CleanupTimeout' { return (-join ([char]0x6E05, [char]0x7406, [char]0x8D85, [char]0x65F6, [char]0xFF0C, [char]0x8BF7, [char]0x7A0D, [char]0x540E, [char]0x91CD, [char]0x8BD5)) }
        'Preview' { return -join ([char]0x9884, [char]0x89C8) }
        'Settings' { return -join ([char]0x8BBE, [char]0x7F6E) }
        'Log' { return -join ([char]0x65E5, [char]0x5FD7) }
        'Folder' { return -join ([char]0x6587, [char]0x4EF6, [char]0x5939) }
        'Exit' { return -join ([char]0x9000, [char]0x51FA) }
        'ShowWindow' { return -join ([char]0x663E, [char]0x793A, [char]0x60AC, [char]0x6D6E, [char]0x7A97) }
        'HideWindow' { return -join ([char]0x9690, [char]0x85CF, [char]0x60AC, [char]0x6D6E, [char]0x7A97) }
        'TrayName' { return -join ([char]0x5185, [char]0x5B58, [char]0x91CA, [char]0x653E, [char]0x60AC, [char]0x6D6E, [char]0x5DE5, [char]0x5177) }
        'SwitchToFloating' { return -join ([char]0x5207, [char]0x6362, [char]0x4E3A, [char]0x60AC, [char]0x6D6E, [char]0x7A97) }
        'SwitchToTaskbar' { return -join ([char]0x5207, [char]0x6362, [char]0x4E3A, [char]0x4EFB, [char]0x52A1, [char]0x680F, [char]0x72B6, [char]0x6001) }
        'TaskbarTooltip' { return -join ([char]0x5355, [char]0x51FB, [char]0x4EFB, [char]0x610F, [char]0x4F4D, [char]0x7F6E, [char]0x91CA, [char]0x653E, [char]0x5185, [char]0x5B58, [char]0xFF0C, [char]0x53F3, [char]0x952E, [char]0x6253, [char]0x5F00, [char]0x83DC, [char]0x5355, [char]0x3002) }
        'DisplayPosition' { return -join ([char]0x663E, [char]0x793A, [char]0x4F4D, [char]0x7F6E) }
        'TaskbarLeft' { return (-join ([char]0x4EFB, [char]0x52A1, [char]0x680F)) + ' - ' + (-join ([char]0x771F, [char]0x5D4C, [char]0x5165)) }
        'TaskbarRight' { return -join ([char]0x4EFB, [char]0x52A1, [char]0x680F, [char]0x53F3, [char]0x4FA7) }
        'FloatingWindow' { return -join ([char]0x60AC, [char]0x6D6E, [char]0x7A97) }
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
        'AutoCleanupInterval' { return -join ([char]0x81EA, [char]0x52A8, [char]0x91CA, [char]0x653E, [char]0x95F4, [char]0x9694) }
        'MinutesRange' { return -join ([char]0x5206, [char]0x949F, [char]0xFF08, [char]0x0031, [char]0x002D, [char]0x0031, [char]0x0034, [char]0x0034, [char]0x0030, [char]0xFF09) }
        'IntervalInvalid' { return -join ([char]0x8BF7, [char]0x8F93, [char]0x5165, [char]0x0031, [char]0x5230, [char]0x0031, [char]0x0034, [char]0x0034, [char]0x0030, [char]0x4E4B, [char]0x95F4, [char]0x7684, [char]0x6574, [char]0x6570, [char]0x5206, [char]0x949F, [char]0x3002) }
        'LogRetentionDays' { return -join ([char]0x65E5, [char]0x5FD7, [char]0x4FDD, [char]0x7559, [char]0x5929, [char]0x6570) }
        'DaysRange' { return -join ([char]0x5929, [char]0xFF08, [char]0x0031, [char]0x002D, [char]0x0033, [char]0x0030, [char]0xFF09) }
        'RetentionInvalid' { return -join ([char]0x8BF7, [char]0x8F93, [char]0x5165, [char]0x0031, [char]0x5230, [char]0x0033, [char]0x0030, [char]0x4E4B, [char]0x95F4, [char]0x7684, [char]0x6574, [char]0x6570, [char]0x5929, [char]0x6570, [char]0x3002) }
        'ClearLogNow' { return -join ([char]0x7ACB, [char]0x5373, [char]0x6E05, [char]0x7406) }
        'LogCleared' { return -join ([char]0x65E5, [char]0x5FD7, [char]0x5DF2, [char]0x6E05, [char]0x7406) }
        'Appearance' { return -join ([char]0x5916, [char]0x5F62) }
        'DefaultAppearance' { return -join ([char]0x9ED8, [char]0x8BA4, [char]0x5916, [char]0x5F62) }
        'BackgroundAppearance' { return -join ([char]0x80CC, [char]0x666F, [char]0x989C, [char]0x8272) }
        'ChooseColor' { return (-join ([char]0x9009, [char]0x62E9, [char]0x989C, [char]0x8272)) + '...' }
        'BackgroundOpacity' { return -join ([char]0x900F, [char]0x660E, [char]0x5EA6) }
        'CustomAppearance' { return -join ([char]0x81EA, [char]0x5B9A, [char]0x4E49, [char]0x56FE, [char]0x7247) }
        'ChooseImage' { return (-join ([char]0x9009, [char]0x62E9, [char]0x56FE, [char]0x7247)) + '...' }
        'ImageFormats' { return 'PNG' + [char]0x3001 + 'JPG' + [char]0x3001 + 'BMP' + [char]0x3001 + 'GIF' + [char]0x3001 + 'TIFF ' + [char]0x6216 + ' WebP' }
        'ImageSelected' { return (-join ([char]0x5DF2, [char]0x9009, [char]0x62E9, [char]0xFF1A)) + '{0}' }
        'ImageDecodeFailed' { return -join ([char]0x5F53, [char]0x524D, [char]0x7535, [char]0x8111, [char]0x65E0, [char]0x6CD5, [char]0x8BFB, [char]0x53D6, [char]0x8FD9, [char]0x79CD, [char]0x56FE, [char]0x7247, [char]0x683C, [char]0x5F0F, [char]0x3002) }
        'ImageRequired' { return -join ([char]0x542F, [char]0x7528, [char]0x81EA, [char]0x5B9A, [char]0x4E49, [char]0x5916, [char]0x5F62, [char]0x524D, [char]0xFF0C, [char]0x8BF7, [char]0x5148, [char]0x9009, [char]0x62E9, [char]0x56FE, [char]0x7247, [char]0x3002) }
        'TransparencyHint' { return -join ([char]0x900F, [char]0x660E, [char]0x56FE, [char]0x7247, [char]0x6309, [char]0x4EBA, [char]0x7269, [char]0x8F6E, [char]0x5ED3, [char]0x663E, [char]0x793A, [char]0xFF1B, [char]0x4E0D, [char]0x900F, [char]0x660E, [char]0x56FE, [char]0x7247, [char]0x4FDD, [char]0x6301, [char]0x77E9, [char]0x5F62, [char]0x3002) }
        'CustomTooltip' { return -join ([char]0x5355, [char]0x51FB, [char]0x4EBA, [char]0x7269, [char]0x91CA, [char]0x653E, [char]0x5185, [char]0x5B58, [char]0xFF0C, [char]0x62D6, [char]0x52A8, [char]0x4EBA, [char]0x7269, [char]0x79FB, [char]0x52A8, [char]0xFF0C, [char]0x53F3, [char]0x952E, [char]0x6253, [char]0x5F00, [char]0x83DC, [char]0x5355, [char]0x3002) }
        'DefaultTooltip' { return -join ([char]0x70B9, [char]0x51FB, [char]0x84DD, [char]0x8272, [char]0x5706, [char]0x5F62, [char]0x6309, [char]0x94AE, [char]0x91CA, [char]0x653E, [char]0xFF0C, [char]0x62D6, [char]0x52A8, [char]0x9762, [char]0x677F, [char]0x79FB, [char]0x52A8, [char]0x3002) }
        'PreviewTitle' { return -join ([char]0x5173, [char]0x95ED, [char]0x9884, [char]0x89C8) }
        'PreviewIntro' { return -join ([char]0x5C06, [char]0x4F1A, [char]0x88AB, [char]0x5173, [char]0x95ED, [char]0x7684, [char]0x8FDB, [char]0x7A0B, [char]0xFF1A) }
        'PreviewNone' { return -join ([char]0x5F53, [char]0x524D, [char]0x6CA1, [char]0x6709, [char]0x8981, [char]0x5173, [char]0x95ED, [char]0x7684, [char]0x8FDB, [char]0x7A0B, [char]0xFF1B, [char]0x9AD8, [char]0x538B, [char]0x529B, [char]0x65F6, [char]0x624D, [char]0x4F1A, [char]0x5B89, [char]0x5168, [char]0x6574, [char]0x7406, [char]0x3002) }
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

function Get-ProcessParentMap {
    # One toolhelp snapshot gives every PID -> parent PID in a single fast
    # native call. The old per-ancestor Get-WmiObject Win32_Process lookup was
    # slow and could hang exactly like the performance-counter WMI query.
    Ensure-NativeApis
    $map = @{}
    $snapshot = [NativeMemoryCleaner]::CreateToolhelp32Snapshot(0x2, 0)
    if ($snapshot -eq [IntPtr]::Zero) { return $map }
    try {
        $entry = New-Object NativeMemoryCleaner+PROCESSENTRY32
        $entry.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][NativeMemoryCleaner+PROCESSENTRY32])
        if ([NativeMemoryCleaner]::Process32First($snapshot, [ref]$entry)) {
            do {
                $map[[int]$entry.th32ProcessID] = [int]$entry.th32ParentProcessID
            } while ([NativeMemoryCleaner]::Process32Next($snapshot, [ref]$entry))
        }
    } catch {
    } finally {
        [void][NativeMemoryCleaner]::CloseHandle($snapshot)
    }
    return $map
}

function Get-ActiveProcessFamily {
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    $fg = Get-ForegroundProcessId
    if ($fg -le 0) { return $ids }
    $parents = Get-ProcessParentMap
    if ($parents.Count -eq 0) { return $ids }

    $current = $fg
    for ($i = 0; $i -lt 10; $i++) {
        if ($current -le 0) { break }
        [void]$ids.Add($current)
        $parent = 0
        if ($parents.ContainsKey($current)) { $parent = $parents[$current] }
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
        [System.Collections.Generic.HashSet[int]]$ActiveIds,
        [int]$CurrentSessionId
    )

    $name = $Process.ProcessName
    if ($Process.Id -eq $PID) { return $false }
    if ($ActiveIds.Contains([int]$Process.Id)) { return $false }
    # The session id is computed once by the caller; building a Process object
    # per candidate just to read it takes ~3s across a few hundred processes.
    if ($Process.SessionId -ne $CurrentSessionId) { return $false }
    if (Test-NameInList $name $Settings.KeepProcessNames) { return $false }
    # Explicit close list wins regardless of size.
    if (Test-NameInList $name $Settings.CloseProcessNames) { return $true }

    # Check working set before touching MainWindowHandle/Title/Path: querying
    # those per-process is slow (a few seconds across all processes) and can
    # stall on special processes. Small processes are skipped without paying
    # that cost.
    $memMB = [math]::Round($Process.WorkingSet64 / 1MB, 1)
    if ($memMB -lt [double]$Settings.MinCloseMemoryMB) { return $false }

    if (Test-VisibleUserWindow $Process) { return $false }

    if ($Settings.AggressiveBackgroundClose -eq $true -and (Test-LikelyUserBackgroundProcess $Process)) { return $true }
    return $false
}

function Get-CloseCandidates {
    param($Settings)
    $active = Get-ActiveProcessFamily
    $currentSessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $items = @()
    foreach ($p in Get-Process) {
        try {
            if (Test-CloseCandidate -Process $p -Settings $Settings -ActiveIds $active -CurrentSessionId $currentSessionId) {
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
    param($Settings, $MemoryInfo)
    Ensure-NativeApis
    $pressureThreshold = [int]$Settings.TrimPressurePercent
    if ($pressureThreshold -gt 0) { $pressureThreshold = [math]::Min(95, [math]::Max(50, $pressureThreshold)) }
    if ($null -eq $MemoryInfo -or ($pressureThreshold -gt 0 -and [int]$MemoryInfo.UsedPercent -lt $pressureThreshold)) {
        return [pscustomobject]@{ Count = 0; Eligible = $false; Reason = "below ${pressureThreshold}% threshold" }
    }
    $active = Get-ActiveProcessFamily
    $trimmed = 0
    foreach ($p in Get-Process) {
        try {
            if ($p.Id -eq $PID) { continue }
            if ($active.Contains([int]$p.Id)) { continue }
            if ($Settings.ConservativeWorkingSetTrim -eq $true) {
                if (-not (Test-LikelyUserBackgroundProcess $p)) { continue }
                if (Test-NameInList $p.ProcessName $Settings.KeepProcessNames) { continue }
                if (Test-VisibleUserWindow $p) { continue }
            }
            if ($p.WorkingSet64 -lt ([double]$Settings.MinTrimMemoryMB * 1MB)) { continue }
            if ([NativeMemoryCleaner]::EmptyWorkingSet($p.Handle)) { $trimmed++ }
        } catch {}
    }
    return [pscustomobject]@{ Count = $trimmed; Eligible = $true; Reason = 'manual full working-set trim' }
}

function Stop-CuratedScheduledTasks {
    param($Candidates)

    $candidateNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($Candidates)) { [void]$candidateNames.Add([string]$item.Name) }
    $stoppedProcessNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $mappings = @(
        [pscustomobject]@{ ProcessName = 'OverlayHelper'; TaskPattern = 'OmenOverlay-sid-*' },
        [pscustomobject]@{ ProcessName = 'OmenInstallMonitor'; TaskPattern = 'OmenInstallMonitor-sid-*' }
    )

    foreach ($mapping in $mappings) {
        if (-not $candidateNames.Contains([string]$mapping.ProcessName)) { continue }
        try {
            $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
                $_.TaskPath -eq '\' -and $_.TaskName -like ([string]$mapping.TaskPattern) -and $_.State -eq 'Running'
            })
            foreach ($task in $tasks) {
                Stop-ScheduledTask -InputObject $task -ErrorAction Stop
                [void]$stoppedProcessNames.Add([string]$mapping.ProcessName)
                Write-AppLog "stopped scheduled task: $($task.TaskName) for $($mapping.ProcessName)"
            }
        } catch {
            Write-AppLog "failed to stop scheduled task for $($mapping.ProcessName): $($_.Exception.Message)"
        }
    }
    return ,$stoppedProcessNames
}

function Invoke-Cleanup {
    param([switch]$PreviewOnly)

    $cleanupWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $settings = Get-Settings
    $before = Get-MemoryInfo
    Write-AppLog "cleanup step: memory-info done $($cleanupWatch.ElapsedMilliseconds)ms"
    $beforeKernel = Get-KernelMemoryInfo -SkipStandby
    Write-AppLog "cleanup step: kernel-info done $($cleanupWatch.ElapsedMilliseconds)ms"
    $beforePoolTags = @()
    $candidates = Get-CloseCandidates $settings
    Write-AppLog "cleanup step: close-candidates done $($cleanupWatch.ElapsedMilliseconds)ms (count $($candidates.Count))"

    if ($PreviewOnly) {
        $beforePoolTags = @(Get-KernelPoolTags -Top 8)
        $pressureThreshold = [int]$settings.TrimPressurePercent
        if ($pressureThreshold -gt 0) { $pressureThreshold = [math]::Min(95, [math]::Max(50, $pressureThreshold)) }
        return [pscustomobject]@{
            Before = $before
            After = $before
            BeforeKernel = $beforeKernel
            AfterKernel = $beforeKernel
            PoolTags = $beforePoolTags
            KernelMessage = Get-KernelPoolMessage $beforeKernel $beforePoolTags
            TrimmedCount = 0
            TrimEligible = ($pressureThreshold -le 0 -or [int]$before.UsedPercent -ge $pressureThreshold)
            TrimReason = if ($pressureThreshold -le 0) { 'manual trim always enabled' } else { "threshold ${pressureThreshold}%" }
            ClosedCount = 0
            ClosedItems = @()
            Candidates = $candidates
        }
    }

    $trimResult = Invoke-MemoryTrim $settings $before
    $trimmed = [int]$trimResult.Count
    Write-AppLog "cleanup step: memory-trim done $($cleanupWatch.ElapsedMilliseconds)ms (trimmed $trimmed)"
    $closed = @()
    $stoppedTaskProcessNames = Stop-CuratedScheduledTasks $candidates
    Write-AppLog "cleanup step: scheduled-tasks done $($cleanupWatch.ElapsedMilliseconds)ms"
    if ($stoppedTaskProcessNames.Count -gt 0) { Start-Sleep -Milliseconds 300 }
    foreach ($item in $candidates) {
        try {
            if ($stoppedTaskProcessNames.Contains([string]$item.Name) -and $null -eq (Get-Process -Id $item.Id -ErrorAction SilentlyContinue)) {
                $closed += $item
                continue
            }
            Stop-Process -Id $item.Id -Force -ErrorAction Stop
            $closed += $item
        } catch {
            Write-AppLog "failed to close $($item.Name) pid=$($item.Id): $($_.Exception.Message)"
        }
    }
    Write-AppLog "cleanup step: close-procs done $($cleanupWatch.ElapsedMilliseconds)ms (closed $($closed.Count))"

    Start-Sleep -Milliseconds 700
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $after = Get-MemoryInfo
    $afterKernel = Get-KernelMemoryInfo -SkipStandby
    $afterPoolTags = @(Get-KernelPoolTags -Top 3)
    $kernelMessage = Get-KernelPoolMessage $afterKernel $afterPoolTags
    Write-AppLog "cleanup step: final-stats done $($cleanupWatch.ElapsedMilliseconds)ms"

    $names = ($closed | ForEach-Object { "$($_.Name)($($_.MemoryMB)MB)" }) -join ', '
    if ([string]::IsNullOrWhiteSpace($names)) { $names = 'none' }
    $topTagText = 'none'
    if ($afterPoolTags.Count -gt 0) { $topTagText = "$($afterPoolTags[0].Tag):$($afterPoolTags[0].NonPagedMB)MB" }
    Write-AppLog "release: before=$($before.UsedPercent)% after=$($after.UsedPercent)% available=$($afterKernel.AvailableMB)MB nonpagedBefore=$($beforeKernel.NonPagedPoolMB)MB nonpagedAfter=$($afterKernel.NonPagedPoolMB)MB topNonpaged=$topTagText trimPressure=$($settings.TrimPressurePercent)% trimEligible=$($trimResult.Eligible) trimReason=$($trimResult.Reason) trimmed=$trimmed closed=$($closed.Count) items=$names"
    if (-not [string]::IsNullOrWhiteSpace($kernelMessage)) {
        Write-AppLog "kernel warning: $kernelMessage"
    }

    [pscustomobject]@{
        Before = $before
        After = $after
        BeforeKernel = $beforeKernel
        AfterKernel = $afterKernel
        PoolTags = $afterPoolTags
        KernelMessage = $kernelMessage
        TrimmedCount = $trimmed
        TrimEligible = [bool]$trimResult.Eligible
        TrimReason = [string]$trimResult.Reason
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
    return "Memory: $($Result.Before.UsedPercent)% -> $($Result.After.UsedPercent)%`nTemporarily available: about $freed MB`nSafely trimmed: $($Result.TrimmedCount) background processes`nClosed: $($Result.ClosedCount) ($closedNames)"
}

if ($Diagnostics) {
    $kernel = Get-KernelMemoryInfo -SkipStandby
    $poolTags = @(Get-KernelPoolTags -Top 8)
    [pscustomobject]@{
        Kernel = $kernel
        PoolTags = $poolTags
        Message = Get-KernelPoolMessage $kernel $poolTags
        ActiveVirtualAdapters = @(Get-SuspectNetworkAdapters)
        RealtekFilterBindings = @(Get-SuspectNetworkBindings)
        RelatedServices = @(Get-SuspectKernelServices)
    } | ConvertTo-Json -Depth 6
    exit
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
$script:activationEvent = $null
$instanceNameSuffix = ''
if (-not [string]::IsNullOrWhiteSpace([string]$env:MEMORY_CLEANER_FLOAT_TEST_INSTANCE) -and [string]$env:MEMORY_CLEANER_FLOAT_TEST_INSTANCE -match '^[A-Za-z0-9_-]{1,32}$') {
    $instanceNameSuffix = '_' + [string]$env:MEMORY_CLEANER_FLOAT_TEST_INSTANCE
}
$activationEventName = 'Global\MemoryCleanerFloat_6F7C6F1E_9D5B_48E7_A8C7_7B9015E6848D_Activate' + $instanceNameSuffix
$mutexName = 'Global\MemoryCleanerFloat_6F7C6F1E_9D5B_48E7_A8C7_7B9015E6848D' + $instanceNameSuffix
$activationEventCreated = $false
try {
    $script:activationEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $activationEventName, [ref]$activationEventCreated)
} catch {}
$createdNew = $false
$script:singleInstanceMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    if ($null -ne $script:activationEvent) {
        try { [void]$script:activationEvent.Set() } catch {}
        try { $script:activationEvent.Dispose() } catch {}
    }
    exit
}

Invoke-LogMaintenance

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName WindowsFormsIntegration
[System.Windows.Forms.Integration.WindowsFormsHost]::EnableWindowsFormsInterop()

function Get-AppearanceBitmapInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Appearance image does not exist: $Path"
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
            $stream,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )
        if ($decoder.Frames.Count -lt 1) { throw 'The image contains no readable frame.' }
        $source = $decoder.Frames[0]

        $converted = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap
        $converted.BeginInit()
        $converted.Source = $source
        $converted.DestinationFormat = [System.Windows.Media.PixelFormats]::Bgra32
        $converted.EndInit()
        $converted.Freeze()
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }

    $width = [int]$converted.PixelWidth
    $height = [int]$converted.PixelHeight
    if ($width -lt 1 -or $height -lt 1) { throw 'The image has an invalid size.' }
    if ($width -gt 8192 -or $height -gt 8192 -or ([long]$width * [long]$height) -gt 33554432) {
        throw 'The image is too large. Use an image no larger than 8192 x 8192 pixels.'
    }

    $stride = $width * 4
    $pixels = New-Object byte[] ($stride * $height)
    $converted.CopyPixels($pixels, $stride, 0)

    $minX = $width
    $minY = $height
    $maxX = -1
    $maxY = -1
    $hasTransparency = $false
    for ($y = 0; $y -lt $height; $y++) {
        $rowOffset = ($y * $stride) + 3
        for ($x = 0; $x -lt $width; $x++) {
            $alpha = $pixels[$rowOffset + ($x * 4)]
            if ($alpha -lt 250) { $hasTransparency = $true }
            if ($alpha -le 8) { continue }
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }

    if ($maxX -lt $minX -or $maxY -lt $minY) { throw 'The image is fully transparent.' }
    $padding = 2
    $minX = [math]::Max(0, $minX - $padding)
    $minY = [math]::Max(0, $minY - $padding)
    $maxX = [math]::Min($width - 1, $maxX + $padding)
    $maxY = [math]::Min($height - 1, $maxY + $padding)
    $cropWidth = ($maxX - $minX) + 1
    $cropHeight = ($maxY - $minY) + 1
    $rect = New-Object System.Windows.Int32Rect($minX, $minY, $cropWidth, $cropHeight)
    $cropped = New-Object System.Windows.Media.Imaging.CroppedBitmap($converted, $rect)
    $cropped.Freeze()

    return [pscustomobject]@{
        Source = $cropped
        PixelWidth = [int]$cropped.PixelWidth
        PixelHeight = [int]$cropped.PixelHeight
        HasTransparency = $hasTransparency
    }
}

function Save-NormalizedAppearanceImage {
    param([Parameter(Mandatory = $true)][string]$SourcePath)

    $imageInfo = Get-AppearanceBitmapInfo -Path $SourcePath
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    [void]$encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($imageInfo.Source))
    $output = $null
    try {
        $output = [System.IO.File]::Open($script:CustomAppearancePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $encoder.Save($output)
    } finally {
        if ($null -ne $output) { $output.Dispose() }
    }
    return $imageInfo
}

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
        SizeToContent="Manual"
        ShowInTaskbar="False"
        Topmost="True"
        SnapsToDevicePixels="True"
        UseLayoutRounding="True">
    <Grid x:Name="Root" RenderTransformOrigin="0.5,0.5" Cursor="Hand" ToolTip="&#x70B9;&#x51FB;&#x84DD;&#x8272;&#x6309;&#x94AE;&#x91CA;&#x653E;&#xFF0C;&#x62D6;&#x52A8;&#x9762;&#x677F;&#x79FB;&#x52A8;" ClipToBounds="True">
        <Grid.RenderTransform>
            <ScaleTransform x:Name="RootScale" ScaleX="1" ScaleY="1"/>
        </Grid.RenderTransform>
        <Grid x:Name="DefaultView">
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
                    <TextBlock x:Name="RamCaption" Text="RAM" Foreground="#798694" FontFamily="Segoe UI" FontSize="9" Margin="5,7,0,0"/>
                </StackPanel>
                <TextBlock x:Name="StatusText" Text="&#x4E0B;&#x8F7D; 0 KB/s  &#x4E0A;&#x4F20; 0 KB/s" Foreground="#627181" FontFamily="Microsoft YaHei UI" FontSize="9.5" LineHeight="13" Margin="0,1,0,0" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
        </Grid>
        </Grid>
        <Grid x:Name="CustomView" Visibility="Collapsed">
            <Image x:Name="CustomAppearanceImage" Stretch="Uniform" SnapsToDevicePixels="True" IsHitTestVisible="False"/>
            <Border x:Name="CustomStatusBadge" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,8,8" Padding="9,5,9,5" CornerRadius="11" Background="#B818202A" IsHitTestVisible="False">
                <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="CustomPercentText" Text="0%" Foreground="White" FontFamily="Segoe UI Semibold" FontSize="14"/>
                    <TextBlock x:Name="CustomStatusText" Text="RAM" Foreground="#D8FFFFFF" FontFamily="Microsoft YaHei UI" FontSize="10" Margin="6,3,0,0" TextTrimming="CharacterEllipsis" MaxWidth="170"/>
                </StackPanel>
            </Border>
        </Grid>
        <Grid x:Name="TaskbarView" Visibility="Collapsed" Background="#01000000">
            <Border x:Name="TaskbarCapsule" Margin="1" CornerRadius="18" BorderThickness="1" BorderBrush="#32FFFFFF">
                <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                        <GradientStop Color="#EC303033" Offset="0"/>
                        <GradientStop Color="#EC1C1C1E" Offset="1"/>
                    </LinearGradientBrush>
                </Border.Background>
            </Border>
            <Border x:Name="TaskbarHover" Margin="1" CornerRadius="18" Background="#24FFFFFF" Opacity="0"/>
            <StackPanel x:Name="TaskbarContentPanel" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False">
                <Grid Width="30" Height="30" Margin="0,0,8,0">
                    <Ellipse>
                        <Ellipse.Fill>
                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                <GradientStop Color="#0A84FF" Offset="0"/>
                                <GradientStop Color="#64D2FF" Offset="1"/>
                            </LinearGradientBrush>
                        </Ellipse.Fill>
                    </Ellipse>
                    <Path Fill="White" Data="M15,3 L7,15 H13 L11,25 L21,11 H15 Z" Stretch="Uniform" Width="14" Height="20"/>
                </Grid>
                <StackPanel Width="56" VerticalAlignment="Center">
                    <TextBlock x:Name="TaskbarPercentText" Text="0%" Foreground="#FF1B2027" FontFamily="Segoe UI Variable Display Semibold, Segoe UI Semibold" FontSize="16.5" LineHeight="18" TextAlignment="Center"/>
                    <TextBlock x:Name="TaskbarMemoryCaption" Text="RAM" Foreground="#FF46505C" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center"/>
                </StackPanel>
                <Border x:Name="TaskbarLocationSeparator" Width="1" Height="22" Background="#32FFFFFF" Margin="7,0"/>
                <StackPanel x:Name="TaskbarLocationPanel" Width="60" VerticalAlignment="Center">
                    <TextBlock x:Name="TaskbarLocationValueText" Text="--" Foreground="#FF1B2027" FontFamily="Microsoft YaHei UI" FontWeight="SemiBold" FontSize="12" LineHeight="15" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <TextBlock x:Name="TaskbarLocationCaption" Text="&#x7F51;&#x7EDC;" Foreground="#FF46505C" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <Border x:Name="TaskbarSpeedSeparator" Width="1" Height="22" Background="#32FFFFFF" Margin="7,0"/>
                <StackPanel Width="72" VerticalAlignment="Center">
                    <TextBlock x:Name="TaskbarDownloadValueText" Text="0 B/s" Foreground="#FF0A5FA8" FontFamily="Segoe UI Variable Text, Segoe UI" FontWeight="SemiBold" FontSize="11" LineHeight="14" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <TextBlock x:Name="TaskbarDownloadCaption" Text="&#x4E0B;&#x8F7D;" Foreground="#FF46505C" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center"/>
                </StackPanel>
                <StackPanel x:Name="TaskbarUploadPanel" Width="72" VerticalAlignment="Center" Margin="6,0,0,0">
                    <TextBlock x:Name="TaskbarUploadValueText" Text="0 B/s" Foreground="#FF17823C" FontFamily="Segoe UI Variable Text, Segoe UI" FontWeight="SemiBold" FontSize="11" LineHeight="14" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <TextBlock x:Name="TaskbarUploadCaption" Text="&#x4E0A;&#x4F20;" Foreground="#FF46505C" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center"/>
                </StackPanel>
            </StackPanel>
            <StackPanel x:Name="TaskbarMessagePanel" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False">
                <Ellipse Width="8" Height="8" Fill="#FF0A84FF" Margin="0,0,7,0"/>
                <TextBlock x:Name="TaskbarMessageText" Text="&#x6B63;&#x5728;&#x91CA;&#x653E;&#x5185;&#x5B58;..." Foreground="#FF1B2027" FontFamily="Microsoft YaHei UI" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$root = $window.FindName('Root')
$rootScale = $window.FindName('RootScale')
$defaultView = $window.FindName('DefaultView')
$card = $window.FindName('Card')
$customView = $window.FindName('CustomView')
$customAppearanceImage = $window.FindName('CustomAppearanceImage')
$customStatusBadge = $window.FindName('CustomStatusBadge')
$customPercentText = $window.FindName('CustomPercentText')
$customStatusText = $window.FindName('CustomStatusText')
$taskbarView = $window.FindName('TaskbarView')
$taskbarCapsule = $window.FindName('TaskbarCapsule')
$taskbarHover = $window.FindName('TaskbarHover')
$taskbarContentPanel = $window.FindName('TaskbarContentPanel')
$taskbarPercentText = $window.FindName('TaskbarPercentText')
$taskbarMemoryCaption = $window.FindName('TaskbarMemoryCaption')
$taskbarLocationSeparator = $window.FindName('TaskbarLocationSeparator')
$taskbarLocationPanel = $window.FindName('TaskbarLocationPanel')
$taskbarLocationValueText = $window.FindName('TaskbarLocationValueText')
$taskbarLocationCaption = $window.FindName('TaskbarLocationCaption')
$taskbarSpeedSeparator = $window.FindName('TaskbarSpeedSeparator')
$taskbarDownloadValueText = $window.FindName('TaskbarDownloadValueText')
$taskbarDownloadCaption = $window.FindName('TaskbarDownloadCaption')
$taskbarUploadPanel = $window.FindName('TaskbarUploadPanel')
$taskbarUploadValueText = $window.FindName('TaskbarUploadValueText')
$taskbarUploadCaption = $window.FindName('TaskbarUploadCaption')
$taskbarMessagePanel = $window.FindName('TaskbarMessagePanel')
$taskbarMessageText = $window.FindName('TaskbarMessageText')
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
$ramCaption = $window.FindName('RamCaption')
$modeBadge = $window.FindName('ModeBadge')
$modeText = $window.FindName('ModeText')
$statusText = $window.FindName('StatusText')
$script:uiSettings = Get-Settings
$script:autoCleanupIntervalMinutes = Get-AutoCleanupIntervalMinutes $script:uiSettings
$script:autoCleanupTimer = $null
$script:taskbarModeActive = $false
$script:taskbarAppearanceGuardUntil = [datetime]::MinValue
$script:taskbarModuleVersion = '1.6.2'
$script:taskbarMemoryPercent = 0
$script:taskbarNetworkLabel = '--'
$script:taskbarNetworkCaptionText = Get-UiText 'Network'
$script:taskbarDownText = '0 B/s'
$script:taskbarUpText = '0 B/s'
$script:taskbarCompact = $false
$script:lastTaskbarPlacementSignature = ''
$script:taskbarNoSpaceCount = 0
$script:taskbarNoSpaceHideThreshold = 3
$script:taskbarHostProcess = $null
$script:taskbarHostBounds = $null
$script:taskbarHostMessage = ''
$script:taskbarInjectionAttempts = 0
$script:taskbarStateDirectory = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat'
try { [void][System.IO.Directory]::CreateDirectory($script:taskbarStateDirectory) } catch {}
$script:taskbarHostStatePath = Join-Path $script:taskbarStateDirectory 'taskbar-state.json'
$script:taskbarPositionStatePath = Join-Path $script:taskbarStateDirectory 'taskbar-position.json'
$script:taskbarReadyStatePath = Join-Path $script:taskbarStateDirectory 'taskbar-ready.json'
try { Remove-Item -LiteralPath $script:taskbarPositionStatePath -Force -ErrorAction SilentlyContinue } catch {}
$script:taskbarHostCleanEventName = 'Local\MemoryCleanerFloat_TaskbarClean'
$script:taskbarHostMenuEventName = 'Local\MemoryCleanerFloat_TaskbarMenu'
$script:taskbarPositionEventName = 'Local\MemoryCleanerFloat_TaskbarPositionChanged'
$script:taskbarEjectEventName = 'Local\MemoryCleanerFloat_TaskbarEject'
$script:taskbarEjectStatePath = Join-Path $script:taskbarStateDirectory 'taskbar-eject.json'
$script:taskbarHostCleanEvent = $null
$script:taskbarHostMenuEvent = $null
$script:taskbarPositionEvent = $null
$script:taskbarEjectEvent = $null
try {
    $script:taskbarHostCleanEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:taskbarHostCleanEventName)
    $script:taskbarHostMenuEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:taskbarHostMenuEventName)
    $script:taskbarPositionEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:taskbarPositionEventName)
    $script:taskbarEjectEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:taskbarEjectEventName)
} catch {
    Write-AppLog "taskbar host event creation failed: $($_.Exception.Message)"
}

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = $workArea.Right - $window.Width - 28
$window.Top = [math]::Max(20, [int]($workArea.Height * 0.35))

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$showHideItem = $menu.Items.Add((Get-UiText 'HideWindow'))
$taskbarPositionItem = New-Object System.Windows.Forms.ToolStripMenuItem
$taskbarLeftItem = New-Object System.Windows.Forms.ToolStripMenuItem
$taskbarRightItem = New-Object System.Windows.Forms.ToolStripMenuItem
[void]$taskbarPositionItem.DropDownItems.Add($taskbarLeftItem)
[void]$taskbarPositionItem.DropDownItems.Add($taskbarRightItem)
$menu.Items.Add('-') | Out-Null
$cleanItem = $menu.Items.Add((Get-UiText 'Clean'))
$kernelItem = $menu.Items.Add((Get-UiText 'KernelMemory'))
$menu.Items.Add('-') | Out-Null
$settingsItem = $menu.Items.Add((Get-UiText 'Settings'))
$logItem = $menu.Items.Add((Get-UiText 'Log'))
$folderItem = $menu.Items.Add((Get-UiText 'Folder'))
$menu.Items.Add('-') | Out-Null
$exitItem = $menu.Items.Add((Get-UiText 'Exit'))
$script:notifyIcon.ContextMenuStrip = $menu
$script:customAppearanceActive = $false

function Show-AppContextMenu {
    param([System.Drawing.Point]$Position)
    # A top-level ContextMenuStrip without an owner is treated by the Windows 11
    # taskbar as a temporary app window. Give it the hidden WPF controller as its
    # owner and mark it as a tool window before it becomes visible.
    try {
        Ensure-NativeApis
        $menu.CreateControl()
        $menuHandle = $menu.Handle
        $ownerHandle = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        $extendedStyle = [NativeMemoryCleaner]::GetWindowLongPtr($menuHandle, -20).ToInt64()
        $extendedStyle = ($extendedStyle -bor 0x80L) -band (-bnot 0x40000L)
        [void][NativeMemoryCleaner]::SetWindowLongPtr($menuHandle, -20, [IntPtr]$extendedStyle)
        if ($ownerHandle -ne [IntPtr]::Zero) {
            [void][NativeMemoryCleaner]::SetWindowLongPtr($menuHandle, -8, $ownerHandle)
        }
    } catch {
        Write-AppLog "context menu taskbar suppression failed: $($_.Exception.Message)"
    }
    $menu.Show($Position)
    try {
        [void][NativeMemoryCleaner]::SetForegroundWindow($menu.Handle)
        [void]$menu.Focus()
    } catch {}
}

function Get-TaskbarLayout {
    Ensure-NativeApis
    $taskbarHandle = [NativeMemoryCleaner]::FindWindow('Shell_TrayWnd', $null)
    if ($taskbarHandle -eq [IntPtr]::Zero) { return $null }
    $taskbarRect = New-Object NativeMemoryCleaner+RECT
    if (-not [NativeMemoryCleaner]::GetWindowRect($taskbarHandle, [ref]$taskbarRect)) { return $null }

    $taskbarElement = $null
    try { $taskbarElement = [System.Windows.Automation.AutomationElement]::FromHandle($taskbarHandle) } catch {}
    if ($null -eq $taskbarElement) { return $null }

    $buttons = @()
    $trayLeft = [int]$taskbarRect.Right
    $trayDetected = $false
    $trayHandle = [NativeMemoryCleaner]::FindWindowEx($taskbarHandle, [IntPtr]::Zero, 'TrayNotifyWnd', $null)
    if ($trayHandle -ne [IntPtr]::Zero) {
        $trayRect = New-Object NativeMemoryCleaner+RECT
        if ([NativeMemoryCleaner]::GetWindowRect($trayHandle, [ref]$trayRect) -and $trayRect.Left -gt $taskbarRect.Left -and $trayRect.Left -lt $taskbarRect.Right) {
            $trayLeft = [int]$trayRect.Left
            $trayDetected = $true
        }
    }
    try {
        $children = $taskbarElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($child in $children) {
            try {
                $rect = $child.Current.BoundingRectangle
                if ($rect.Width -le 0 -or $rect.Height -le 0) { continue }
                $className = [string]$child.Current.ClassName
                $automationId = [string]$child.Current.AutomationId
                if ($className -eq 'TrayNotifyWnd') {
                    $trayLeft = [math]::Min($trayLeft, [int][math]::Round($rect.Left))
                    $trayDetected = $true
                }
                if ($className -eq 'ToggleButton' -or $className -eq 'Taskbar.TaskListButtonAutomationPeer' -or $automationId -in @('StartButton','SearchButton','TaskViewButton')) {
                    $buttons += [pscustomobject]@{
                        Left = [int][math]::Round($rect.Left)
                        Right = [int][math]::Round($rect.Right)
                    }
                }
            } catch {}
        }
    } catch {}

    # UI Automation can briefly return an incomplete taskbar tree while the
    # tray redraws. Reject that sample instead of treating the tray as empty.
    if (-not $trayDetected -or $buttons.Count -eq 0) { return $null }

    $buttonLeft = [int]$taskbarRect.Left
    $buttonRight = [int]$taskbarRect.Left
    if ($buttons.Count -gt 0) {
        $buttonLeft = [int](($buttons | Measure-Object Left -Minimum).Minimum)
        $buttonRight = [int](($buttons | Measure-Object Right -Maximum).Maximum)
    }

    [pscustomobject]@{
        Left = [int]$taskbarRect.Left
        Top = [int]$taskbarRect.Top
        Right = [int]$taskbarRect.Right
        Bottom = [int]$taskbarRect.Bottom
        Width = [int]($taskbarRect.Right - $taskbarRect.Left)
        Height = [int]($taskbarRect.Bottom - $taskbarRect.Top)
        ButtonLeft = $buttonLeft
        ButtonRight = $buttonRight
        TrayLeft = $trayLeft
        Dpi = try { [int][NativeMemoryCleaner]::GetDpiForWindow($taskbarHandle) } catch { 96 }
    }
}

function Resolve-TaskbarPlacement {
    param(
        $Layout,
        [string]$Position = 'left',
        [int]$PreferredWidth = 360,
        [int]$MinimumWidth = 190,
        [int]$Gap = 8
    )
    if ($null -eq $Layout) { return $null }
    if ($Position -eq 'right') {
        $availableLeft = $Layout.ButtonRight + $Gap
        $availableRight = $Layout.TrayLeft - $Gap
        $availableWidth = $availableRight - $availableLeft
        if ($availableWidth -lt $MinimumWidth) { return $null }
        $width = [math]::Min($PreferredWidth, $availableWidth)
        $left = $availableRight - $width
    } else {
        $availableLeft = $Layout.Left + $Gap
        $availableRight = $Layout.ButtonLeft - $Gap
        $availableWidth = $availableRight - $availableLeft
        if ($availableWidth -lt $MinimumWidth) { return $null }
        $width = [math]::Min($PreferredWidth, $availableWidth)
        $left = $availableLeft
    }
    $height = [math]::Max(36, $Layout.Height - 6)
    [pscustomobject]@{
        Left = [int]$left
        Top = [int]($Layout.Top + [math]::Round(($Layout.Height - $height) / 2.0))
        Width = [int]$width
        Height = [int]$height
        Dpi = [math]::Max(96, [int]$Layout.Dpi)
    }
}

function Get-TaskbarPlacement {
    param([string]$Position = 'left')
    Resolve-TaskbarPlacement -Layout (Get-TaskbarLayout) -Position $Position
}

function Set-NativeWindowBounds {
    param($Bounds)
    if ($null -eq $Bounds) { return $false }
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    if ($helper.Handle -eq [IntPtr]::Zero) { return $false }
    [void][NativeMemoryCleaner]::SetWindowPos($helper.Handle, [IntPtr](-1), $Bounds.Left, $Bounds.Top, $Bounds.Width, $Bounds.Height, 0x0010)
    return $true
}

function Sync-WpfTaskbarBounds {
    param($Bounds)
    if ($null -eq $Bounds) { return }
    $dpi = [math]::Max(96, [double]$Bounds.Dpi)
    $deviceToDip = 96.0 / $dpi
    $window.Left = [double]$Bounds.Left * $deviceToDip
    $window.Top = [double]$Bounds.Top * $deviceToDip
    $window.Width = [double]$Bounds.Width * $deviceToDip
    $window.Height = [double]$Bounds.Height * $deviceToDip
}

function Get-TaskbarHostExecutable {
    $candidates = @(
        (Join-Path $script:AppRoot 'MemoryCleanerTaskbarHost.exe'),
        (Join-Path $script:AppRoot 'build\taskbar-host-v2-prototype\MemoryCleanerTaskbarHost.exe'),
        (Join-Path $script:AppRoot 'TaskbarHost\bin\Release\net8.0-windows\MemoryCleanerTaskbarHost.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Set-WindhawkHiddenRuntimeSettings {
    param([string]$WindhawkExecutable)

    try {
        $windhawkRoot = Split-Path -Parent $WindhawkExecutable
        $settingsPath = Join-Path $windhawkRoot 'AppData\settings.ini'
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
    } catch {
        Write-AppLog "Windhawk hidden settings update failed: $($_.Exception.Message)"
    }
}

function Stop-WindhawkEngine {
    if ($script:windhawkStopRequested) { return }
    $script:windhawkStopRequested = $true

    $candidates = @(
        [string]$script:uiSettings.WindhawkPath,
        'D:\Windhawk\windhawk.exe',
        (Join-Path $script:AppRoot 'Windhawk\windhawk.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $resolvedPath = [System.IO.Path]::GetFullPath($candidate)
        $running = Get-Process -Name 'windhawk' -ErrorAction SilentlyContinue | Where-Object {
            try { [string]::Equals($_.Path, $resolvedPath, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
        } | Select-Object -First 1
        if ($null -eq $running) { return }

        try {
            $stopProcess = New-Object System.Diagnostics.Process
            $stopProcess.StartInfo.FileName = $resolvedPath
            $stopProcess.StartInfo.Arguments = '-exit -wait'
            $stopProcess.StartInfo.WorkingDirectory = Split-Path -Parent $resolvedPath
            $stopProcess.StartInfo.UseShellExecute = $false
            $stopProcess.StartInfo.CreateNoWindow = $true
            $stopProcess.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            if ($stopProcess.Start()) {
                if (-not $stopProcess.WaitForExit(15000)) { try { $stopProcess.Kill() } catch {} }
                $stopProcess.Dispose()
            }
            Write-AppLog "Windhawk taskbar engine stopped with MemoryCleanerFloat: $resolvedPath"
        } catch {
            Write-AppLog "Windhawk taskbar engine stop failed: $($_.Exception.Message)"
        }
        return
    }
}

function Ensure-TaskbarHost {
    # The old host was a top-level overlay window. The Windhawk module now owns
    # the real Explorer XAML slot; this only ensures the portable engine runs.
    $configuredPath = [string]$script:uiSettings.WindhawkPath
    $candidates = @(
        $configuredPath,
        'D:\Windhawk\windhawk.exe',
        (Join-Path $script:AppRoot 'Windhawk\windhawk.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $resolvedPath = [System.IO.Path]::GetFullPath($candidate)
        Set-WindhawkHiddenRuntimeSettings -WindhawkExecutable $resolvedPath
        $running = Get-Process -Name 'windhawk' -ErrorAction SilentlyContinue | Where-Object {
            try { [string]::Equals($_.Path, $resolvedPath, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
        } | Select-Object -First 1
        if ($null -ne $running) { return $true }
        try {
            Start-Process -FilePath $resolvedPath -ArgumentList '-tray-only' -WindowStyle Hidden | Out-Null
            Write-AppLog "Windhawk taskbar engine started: $resolvedPath"
            return $true
        } catch {
            Write-AppLog "Windhawk taskbar engine start failed: $($_.Exception.Message)"
            return $false
        }
    }

    Write-AppLog 'Windhawk executable was not found; taskbar slot is unavailable'
    return $false
}

function Request-WindhawkTaskbarInjection {
    # Focus requests to a taskbar button interrupt typing and make the
    # taskbar blink. The module auto-injects on its own once the hook is in
    # place, so the controller only nudges the first few attempts and never
    # once the ready marker is fresh.
    try {
        if (Test-Path -LiteralPath $script:taskbarReadyStatePath -PathType Leaf) {
            $readyFile = Get-Item -LiteralPath $script:taskbarReadyStatePath
            if (((Get-Date) - $readyFile.LastWriteTime).TotalSeconds -le 15) {
                return
            }
        }
        if ($script:taskbarInjectionAttempts -ge 4) { return }

        Ensure-NativeApis
        $foreground = [NativeMemoryCleaner]::GetForegroundWindow()
        $taskbarHandle = [NativeMemoryCleaner]::FindWindow('Shell_TrayWnd', $null)
        if ($taskbarHandle -eq [IntPtr]::Zero) { return }
        $taskbarElement = [System.Windows.Automation.AutomationElement]::FromHandle($taskbarHandle)
        if ($null -eq $taskbarElement) { return }
        $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Taskbar.TaskListButtonAutomationPeer')
        $button = $taskbarElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($null -eq $button) { return }
        $button.SetFocus()
        if ($foreground -ne [IntPtr]::Zero) {
            [void][NativeMemoryCleaner]::SetForegroundWindow($foreground)
        }
    } catch {
        Write-AppLog "Windhawk taskbar injection request failed: $($_.Exception.Message)"
    }
}

function Write-TaskbarHostState {
    Ensure-NativeApis
    $bounds = $script:taskbarHostBounds
    $left = -1
    $top = -1
    $width = 360
    $height = 52
    if ($null -ne $bounds) {
        $left = [int]$bounds.Left
        $top = [int]$bounds.Top
        $width = [int]$bounds.Width
        $height = [int]$bounds.Height
    }

    $state = [ordered]@{
        MemoryPercent = [int]$script:taskbarMemoryPercent
        Location = if ([string]::IsNullOrWhiteSpace($script:taskbarNetworkLabel)) { '--' } else { [string]$script:taskbarNetworkLabel }
        NetworkMode = if ([string]::IsNullOrWhiteSpace($script:taskbarNetworkCaptionText)) { Get-UiText 'Network' } else { [string]$script:taskbarNetworkCaptionText }
        Download = [string]$script:taskbarDownText
        Upload = [string]$script:taskbarUpText
        Message = [string]$script:taskbarHostMessage
        Mode = if ($script:taskbarModeActive) { 'taskbar' } else { 'floating' }
        Position = ([string]$script:uiSettings.TaskbarPosition).ToLowerInvariant()
        TaskbarOffset = [int]$script:uiSettings.TaskbarOffset
        Left = $left
        Top = $top
        Width = $width
        Height = $height
        ShowLocation = ($script:uiSettings.ShowNetworkLocation -eq $true)
        ShowSpeed = ($script:uiSettings.ShowNetworkSpeed -eq $true)
        UseBackgroundColor = ($script:uiSettings.UseBackgroundColor -eq $true)
        BackgroundColor = Get-BackgroundColorHex $script:uiSettings
        # The native taskbar module expects an alpha percentage, while the UI
        # intentionally exposes transparency to the user.
        BackgroundOpacity = Get-BackgroundAlphaPercent $script:uiSettings
        Busy = [bool]$script:cleanupInProgress
        Visible = [bool]$script:taskbarModeActive
    }

    try {
        $json = $state | ConvertTo-Json -Compress
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $written = $false
        for ($attempt = 0; $attempt -lt 4 -and -not $written; $attempt++) {
            try {
                $tempPath = $script:taskbarHostStatePath + '.tmp'
                $stream = New-Object System.IO.FileStream($tempPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                try {
                    $bytes = $encoding.GetBytes($json)
                    $stream.Write($bytes, 0, $bytes.Length)
                    $stream.Flush()
                } finally {
                    $stream.Dispose()
                }
                # Replace atomically so the module never observes a truncated
                # or half-written JSON file while it polls every 250 ms.
                [void][NativeMemoryCleaner]::MoveFileEx($tempPath, $script:taskbarHostStatePath, 0x1 -bor 0x8)
                $written = $true
            } catch {
                if ($attempt -lt 3) { Start-Sleep -Milliseconds 15 }
                else { throw }
            }
        }
    } catch {
        Write-AppLog "taskbar host state write failed: $($_.Exception.Message)"
        return
    }

}

function Sync-TaskbarDragPosition {
    if (-not (Test-Path -LiteralPath $script:taskbarPositionStatePath -PathType Leaf)) { return }
    try {
        $positionState = Get-Content -LiteralPath $script:taskbarPositionStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $offset = 0
        if (-not [int]::TryParse([string]$positionState.Offset, [ref]$offset)) { return }
        $offset = [math]::Min(1600, [math]::Max(0, $offset))
        if ([int]$script:uiSettings.TaskbarOffset -eq $offset) { return }
        $script:uiSettings.TaskbarOffset = $offset
        Save-Settings $script:uiSettings
        Write-TaskbarHostState
        Write-AppLog "taskbar module position saved: offset=$offset"
    } catch {
        Write-AppLog "taskbar module position could not be synchronized: $($_.Exception.Message)"
    }
}

function Update-TaskbarStatusText {
    if (-not $script:taskbarModeActive) { return }
    if ($script:statusOverride) { return }
    $taskbarMessagePanel.Visibility = [System.Windows.Visibility]::Collapsed
    $taskbarContentPanel.Visibility = [System.Windows.Visibility]::Visible
    $taskbarPercentText.Text = ('{0}%' -f $script:taskbarMemoryPercent)
    $taskbarLocationValueText.Text = if ([string]::IsNullOrWhiteSpace($script:taskbarNetworkLabel)) { '--' } else { $script:taskbarNetworkLabel }
    $taskbarLocationCaption.Text = if ([string]::IsNullOrWhiteSpace($script:taskbarNetworkCaptionText)) { Get-UiText 'Network' } else { $script:taskbarNetworkCaptionText }
    $taskbarDownloadValueText.Text = $script:taskbarDownText
    $taskbarUploadValueText.Text = $script:taskbarUpText

    $showLocation = ($script:uiSettings.ShowNetworkLocation -eq $true)
    $showSpeed = ($script:uiSettings.ShowNetworkSpeed -eq $true)
    $taskbarLocationSeparator.Visibility = if ($showLocation) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $taskbarLocationPanel.Visibility = if ($showLocation) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $taskbarSpeedSeparator.Visibility = if ($showSpeed) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $taskbarDownloadValueText.Visibility = if ($showSpeed) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $taskbarDownloadCaption.Visibility = if ($showSpeed) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $taskbarUploadPanel.Visibility = if ($showSpeed -and -not $script:taskbarCompact) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $taskbarMemoryCaption.Visibility = if ($script:taskbarCompact) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    Write-TaskbarHostState
}

function Protect-EmbeddedModeForAppearanceUpdate {
    if ($script:taskbarModeActive) {
        # Updating the native slot's background can make Windows briefly report
        # a lost pointer capture. That synthetic event must not be interpreted
        # as the user dragging the slot out of the taskbar.
        $script:taskbarAppearanceGuardUntil = (Get-Date).AddSeconds(2)
    }
}

function Apply-TaskbarPlacement {
    if (-not $script:taskbarModeActive) { return }
    # Explorer owns the injected slot's position and size. Keeping the state
    # fresh is the only placement work required on the controller side.
    $script:taskbarCompact = $false
    $script:taskbarHostBounds = $null
    Update-TaskbarStatusText
    if ($window.IsVisible) { $window.Hide() }
}

function Set-DisplayMode {
    param([string]$Mode, [string]$Position = '', [double]$FloatLeft = [double]::NaN, [double]$FloatTop = [double]::NaN)
    if ($Mode -eq 'taskbar') {
        if ($Position -notin @('left','right')) { $Position = 'left' }
        $script:uiSettings.DisplayMode = 'taskbar'
        $script:uiSettings.TaskbarPosition = $Position
        $script:taskbarModeActive = $true
        $script:taskbarInjectionAttempts = 0
        $script:taskbarInjectionStartedAt = Get-Date
        Write-TaskbarHostState
        [void](Ensure-TaskbarHost)
        $window.Dispatcher.BeginInvoke([Action]{
            Request-WindhawkTaskbarInjection
        }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
        $defaultView.Visibility = [System.Windows.Visibility]::Collapsed
        $customView.Visibility = [System.Windows.Visibility]::Collapsed
        $taskbarView.Visibility = [System.Windows.Visibility]::Visible
        $window.ShowInTaskbar = $false
        [void](Set-WpfTaskbarButtonVisibility -TargetWindow $window -Visible $false)
        $window.Background = [System.Windows.Media.Brushes]::Transparent
        $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
        $root.ToolTip = Get-UiText 'TaskbarTooltip'
        $showHideItem.Text = Get-UiText 'SwitchToFloating'
        Update-TaskbarStatusText
        Apply-TaskbarPlacement
        if ($window.IsVisible) { $window.Hide() }
    } else {
        $script:uiSettings.DisplayMode = 'floating'
        $script:taskbarModeActive = $false
        $script:taskbarHostMessage = ''
        Write-TaskbarHostState
        $taskbarView.Visibility = [System.Windows.Visibility]::Collapsed
        # The tray icon is the persistent entry point; the floating panel must
        # not create a second taskbar button.
        $window.ShowInTaskbar = $false
        Apply-AppearanceSettings
        if (-not [double]::IsNaN($FloatLeft) -and -not [double]::IsNaN($FloatTop)) {
            $window.Left = $FloatLeft
            $window.Top = $FloatTop
        } else {
            $window.Left = $workArea.Right - $window.Width - 28
            $window.Top = [math]::Max(20, [int]($workArea.Height * 0.35))
        }
        [void](Set-WpfTaskbarButtonVisibility -TargetWindow $window -Visible $false)
        if (-not $window.IsVisible) { $window.Show() }
        [void](Set-WpfTaskbarButtonVisibility -TargetWindow $window -Visible $false)
        $showHideItem.Text = Get-UiText 'SwitchToTaskbar'
    }
}

function Update-WindowVisibilityMenu {
    if ($script:taskbarModeActive) {
        $showHideItem.Text = Get-UiText 'SwitchToFloating'
        return
    }
    if ($window.IsVisible -and $window.WindowState -ne [System.Windows.WindowState]::Minimized) {
        $showHideItem.Text = Get-UiText 'HideWindow'
    } else {
        $showHideItem.Text = Get-UiText 'ShowWindow'
    }
}

function Show-MainWindow {
    if ($script:taskbarModeActive) {
        Apply-TaskbarPlacement
        return
    }
    [void](Set-WpfTaskbarButtonVisibility -TargetWindow $window -Visible $false)
    if (-not $window.IsVisible) { $window.Show() }
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    }
    $window.ShowInTaskbar = $false
    [void](Set-WpfTaskbarButtonVisibility -TargetWindow $window -Visible $false)
    $window.Topmost = $true
    [void]$window.Activate()
    Update-WindowVisibilityMenu
}

function Toggle-MainWindow {
    if ($script:taskbarModeActive) {
        Set-DisplayMode -Mode 'floating'
        Save-Settings $script:uiSettings
        return
    }
    Set-DisplayMode -Mode 'taskbar' -Position ([string]$script:uiSettings.TaskbarPosition)
    Save-Settings $script:uiSettings
    return
    <# Legacy visibility toggle retained for older configurations.
    if ($window.IsVisible -and $window.WindowState -ne [System.Windows.WindowState]::Minimized) {
        $window.Hide()
        Update-WindowVisibilityMenu
        return
    }
    Show-MainWindow
    #>
}

function Update-TrayTooltip {
    param([int]$MemoryPercent)
    $trayText = ('{0} | RAM {1}% | {2}' -f (Get-UiText 'TrayName'), $MemoryPercent, (Get-UiText 'ShowWindow'))
    if ($trayText.Length -gt 63) { $trayText = $trayText.Substring(0, 63) }
    try { $script:notifyIcon.Text = $trayText } catch {}
}

function New-WpfGradientBrush {
    param([string]$TopColor, [string]$BottomColor)

    $brush = New-Object System.Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object System.Windows.Point(0, 0)
    $brush.EndPoint = New-Object System.Windows.Point(0, 1)
    $top = New-Object System.Windows.Media.GradientStop
    $top.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($TopColor)
    $top.Offset = 0
    $bottom = New-Object System.Windows.Media.GradientStop
    $bottom.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($BottomColor)
    $bottom.Offset = 1
    [void]$brush.GradientStops.Add($top)
    [void]$brush.GradientStops.Add($bottom)
    return $brush
}

function Set-BackgroundColorAppearance {
    $hex = Get-BackgroundColorHex $script:uiSettings
    $alphaPercent = Get-BackgroundAlphaPercent $script:uiSettings
    $alpha = [byte][math]::Round(255 * ($alphaPercent / 100.0))
    $red = [Convert]::ToByte($hex.Substring(1, 2), 16)
    $green = [Convert]::ToByte($hex.Substring(3, 2), 16)
    $blue = [Convert]::ToByte($hex.Substring(5, 2), 16)
    $color = [System.Windows.Media.Color]::FromArgb($alpha, $red, $green, $blue)
    $brush = New-Object System.Windows.Media.SolidColorBrush($color)
    $card.Background = $brush
    $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(92, 255, 255, 255))
    $taskbarCapsule.Background = $brush

    # 文字恒深：亮度越高文字越接近纯黑；背景再暗，文字也始终处于深色区间。
    $luminance = (0.2126 * $red) + (0.7152 * $green) + (0.0722 * $blue)
    $mainLevel = [byte][math]::Round(24 + ($luminance / 255.0) * 24)
    $subLevel = [byte][math]::Round(46 + ($luminance / 255.0) * 26)
    $mainBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb($mainLevel, $mainLevel, $mainLevel))
    $subBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb($subLevel, $subLevel, $subLevel))
    $blueBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(10, 95, 168))
    $greenBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(23, 130, 60))

    # 标准悬浮窗（DefaultView）
    $titleText.Foreground = $subBrush
    $percentText.Foreground = $mainBrush
    $ramCaption.Foreground = $subBrush
    $statusText.Foreground = $subBrush
    $modeText.Foreground = $mainBrush
    $modeBadge.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(64, 255, 255, 255))

    # 任务栏模式（TaskbarView）：主值/消息为深色；下载/上传数字保留蓝绿色系但加深以适配浅底
    $taskbarPercentText.Foreground = $mainBrush
    $taskbarMemoryCaption.Foreground = $subBrush
    $taskbarLocationValueText.Foreground = $mainBrush
    $taskbarLocationCaption.Foreground = $subBrush
    $taskbarDownloadValueText.Foreground = $blueBrush
    $taskbarUploadValueText.Foreground = $greenBrush
    $taskbarDownloadCaption.Foreground = $subBrush
    $taskbarUploadCaption.Foreground = $subBrush
    $taskbarMessageText.Foreground = $mainBrush
}

function Reset-DefaultBackgroundAppearance {
    $card.Background = New-WpfGradientBrush '#F0FFFFFF' '#D8EAF2FA'
    $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#DDE8F2'))
    $taskbarCapsule.Background = New-WpfGradientBrush '#F0F5F8FC' '#E0EAF2FA'
    $titleText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#64707D'))
    $percentText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#18202A'))
    $ramCaption.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#798694'))
    $statusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#627181'))
    $modeText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#246B9E'))
    $modeBadge.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#260A84FF'))
    # 任务栏文字同样恒深，配浅色胶囊背景
    $taskbarPercentText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#18202A'))
    $taskbarMemoryCaption.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#627181'))
    $taskbarLocationValueText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#18202A'))
    $taskbarLocationCaption.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#627181'))
    $taskbarDownloadValueText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#0A5FA8'))
    $taskbarUploadValueText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#17823C'))
    $taskbarDownloadCaption.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#627181'))
    $taskbarUploadCaption.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#627181'))
    $taskbarMessageText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#18202A'))
}

function Apply-AppearanceSettings {
    if ($script:uiSettings.UseBackgroundColor -eq $true) {
        Set-BackgroundColorAppearance
    } else {
        Reset-DefaultBackgroundAppearance
    }
    $script:customAppearanceActive = $false
    $customView.Visibility = [System.Windows.Visibility]::Collapsed
    $defaultView.Visibility = [System.Windows.Visibility]::Visible
    $customAppearanceImage.Source = $null
    $root.ToolTip = Get-UiText 'DefaultTooltip'
    Apply-WindowLayout
}

function Apply-UiSettings {
    Update-WindowVisibilityMenu
    $taskbarPositionItem.Text = Get-UiText 'DisplayPosition'
    $taskbarLeftItem.Text = Get-UiText 'TaskbarLeft'
    $taskbarRightItem.Text = Get-UiText 'TaskbarRight'
    $taskbarLeftItem.Checked = ($script:taskbarModeActive -and ([string]$script:uiSettings.TaskbarPosition).ToLowerInvariant() -eq 'left')
    $taskbarRightItem.Checked = ($script:taskbarModeActive -and ([string]$script:uiSettings.TaskbarPosition).ToLowerInvariant() -eq 'right')
    $cleanItem.Text = Get-UiText 'Clean'
    $kernelItem.Text = Get-UiText 'KernelMemory'
    $settingsItem.Text = Get-UiText 'Settings'
    $logItem.Text = Get-UiText 'Log'
    $folderItem.Text = Get-UiText 'Folder'
    $exitItem.Text = Get-UiText 'Exit'

    if (-not $script:statusOverride) {
        $titleText.Text = ''
    }

    Set-IconStyle
    Update-NetworkText
    Apply-AppearanceSettings
    $mode = ([string]$script:uiSettings.DisplayMode).ToLowerInvariant()
    if ($mode -eq 'taskbar') {
        Set-DisplayMode -Mode 'taskbar' -Position ([string]$script:uiSettings.TaskbarPosition)
    } else {
        Set-DisplayMode -Mode 'floating'
    }
}

function Apply-WindowLayout {
    if ($script:customAppearanceActive) { return }
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
    if ($script:taskbarModeActive) {
        Write-TaskbarHostState
        return
    }
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
    if ($script:taskbarModeActive) {
        Write-TaskbarHostState
        return
    }
    Set-WpfOpacity $progressRing 1.0 120
    $customStatusBadge.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(210, 10, 132, 255))
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animation.From = 0
    $animation.To = 360
    $animation.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(780))
    $animation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $ringRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $animation)
}

function Stop-ProgressAnimation {
    if ($script:taskbarModeActive) {
        Write-TaskbarHostState
        return
    }
    $ringRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    Set-WpfOpacity $progressRing 0.0 180
    $customStatusBadge.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(184, 24, 32, 42))
}

function Update-ButtonText {
    if ($script:isDraggingWindow -or $script:cleanupInProgress) { return }
    $mem = Get-MemoryInfo
    $script:taskbarMemoryPercent = [int]$mem.UsedPercent
    $percentText.Text = ('{0}%' -f [int]$mem.UsedPercent)
    $customPercentText.Text = ('{0}%' -f [int]$mem.UsedPercent)
    Update-TrayTooltip -MemoryPercent ([int]$mem.UsedPercent)
    Update-TaskbarStatusText
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
$script:cleanupOutputTask = $null
$script:cleanupErrorTask = $null
$script:cleanupStartedAt = $null
$script:cleanupTimeoutSeconds = 120
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
    $script:taskbarDownText = $downText
    $script:taskbarUpText = $upText
    if ($script:uiSettings.ShowNetworkLocation -eq $true) {
        $modeBadge.Visibility = [System.Windows.Visibility]::Visible
        if ($snapshot.Mode -eq (Get-UiText 'Offline')) {
            $modeText.Text = $snapshot.Mode
            $script:taskbarNetworkLabel = $snapshot.Mode
            $script:taskbarNetworkCaptionText = Get-UiText 'Network'
        } else {
            $countryText = Get-CurrentIpCountryText
            if ([string]::IsNullOrWhiteSpace($countryText)) {
                $modeText.Text = ('{0} ...' -f $snapshot.Mode)
                $script:taskbarNetworkLabel = '--'
            } else {
                $modeText.Text = ('{0} {1}' -f $snapshot.Mode, $countryText)
                $script:taskbarNetworkLabel = $countryText
            }
            $script:taskbarNetworkCaptionText = $snapshot.Mode
        }
    } else {
        $modeBadge.Visibility = [System.Windows.Visibility]::Collapsed
        $script:taskbarNetworkLabel = ''
        $script:taskbarNetworkCaptionText = Get-UiText 'Network'
    }

    if (-not $script:statusOverride) {
        $customStatusText.Text = 'RAM'
        if ($script:uiSettings.ShowNetworkSpeed -eq $true) {
            $statusText.Visibility = [System.Windows.Visibility]::Visible
            $statusText.Text = ('{0} {1}  {2} {3}' -f (Get-UiText 'Download'), $downText, (Get-UiText 'Upload'), $upText)
        } else {
            $statusText.Text = ''
            $statusText.Visibility = [System.Windows.Visibility]::Collapsed
        }
        Update-TaskbarStatusText
    }
}

function Set-StatusMessage {
    param([string]$Text)
    $customStatusText.Text = $Text
    if ($script:taskbarModeActive) {
        $script:taskbarHostMessage = $Text
        $taskbarContentPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $taskbarMessagePanel.Visibility = [System.Windows.Visibility]::Visible
        $taskbarMessageText.Text = $Text
        Write-TaskbarHostState
    }
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
    $customStatusText.Text = 'RAM'
    $script:statusOverride = $false
    $script:taskbarHostMessage = ''
    if (-not $script:taskbarModeActive) { Apply-WindowLayout }
    Update-NetworkText
    Update-TaskbarStatusText
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
    $trimmedCount = 0
    $beforePercent = 0
    $afterPercent = 0
    $trimEligible = $false
    $closedDisplay = ''
    if ($null -ne $Result -and $null -ne $Result.After -and $null -ne $Result.Before) {
        $freed = [math]::Max(0, [int]$Result.After.FreeMB - [int]$Result.Before.FreeMB)
        $closedCount = [int]$Result.ClosedCount
        $trimmedCount = [int]$Result.TrimmedCount
        $beforePercent = [int]$Result.Before.UsedPercent
        $afterPercent = [int]$Result.After.UsedPercent
        $trimEligible = [bool]$Result.TrimEligible
        $closedDisplay = (@($Result.ClosedItems) | Select-Object -First 2 | ForEach-Object { [string]$_.Name }) -join ','
    }

    $script:cleanupInProgress = $false
    $script:statusOverride = $true
    $titleText.Text = Get-UiText 'Done'
    if ($null -eq $Result) {
        Set-StatusMessage (Get-UiText 'CleanupFailedNoResult')
    } elseif ($closedCount -gt 0) {
        Set-StatusMessage ((Get-UiText 'CleanupClosed') -f $freed, $closedCount)
    } elseif ($freed -gt 0) {
        Set-StatusMessage ((Get-UiText 'CleanupFreed') -f $freed, $beforePercent, $afterPercent)
    } elseif (-not $trimEligible) {
        Set-StatusMessage ((Get-UiText 'CleanupNotNeeded') -f $afterPercent)
    } else {
        Set-StatusMessage ((Get-UiText 'CleanupNoReleasable') -f $afterPercent)
    }
    if (-not $script:taskbarModeActive) { Apply-WindowLayout }
    Flash-DoneVisual
    if ($null -eq $Result) {
        Show-Balloon 'Memory release failed' 'No cleanup result was returned.'
    } else {
        if ($trimEligible) {
            $summary = "$beforePercent% -> $afterPercent%; temporarily available +$freed MB; trimmed $trimmedCount; closed $closedCount."
        } else {
            $summary = "$beforePercent% -> $afterPercent%; working-set trim skipped: $($Result.TrimReason); closed $closedCount."
        }
        $topTags = @($Result.PoolTags)
        if ($topTags.Count -gt 0 -and [int]$Result.AfterKernel.NonPagedPoolMB -ge 2048) {
            $summary += " Kernel $($topTags[0].Tag) $($topTags[0].NonPagedMB) MB is driver memory and was not released."
        }
        Show-Balloon 'Memory release complete' $summary
    }

    if ($null -ne $script:resetStatusTimer) { try { $script:resetStatusTimer.Stop() } catch {} }
    $script:resetStatusTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:resetStatusTimer.Interval = [TimeSpan]::FromSeconds(4.0)
    $script:resetStatusTimer.Add_Tick({
        $script:resetStatusTimer.Stop()
        Restore-IdleStatus
    }.GetNewClosure())
    $script:resetStatusTimer.Start()
}

function Fail-UiCleanup {
    param([string]$Message)

    Stop-ProgressAnimation
    Update-ButtonText
    $titleText.Text = ''
    $script:cleanupInProgress = $false
    Set-StatusMessage $Message
    Show-Balloon 'Memory release failed' $Message

    if ($null -ne $script:resetStatusTimer) { try { $script:resetStatusTimer.Stop() } catch {} }
    $script:resetStatusTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:resetStatusTimer.Interval = [TimeSpan]::FromSeconds(2.0)
        $script:resetStatusTimer.Add_Tick({
            $script:resetStatusTimer.Stop()
            $script:statusOverride = $false
            if (-not $script:taskbarModeActive) { Apply-WindowLayout }
            Update-NetworkText
            Update-TaskbarStatusText
        }.GetNewClosure())
    $script:resetStatusTimer.Start()
}

function Run-UiCleanup {
    if ($script:cleanupInProgress) { return }
    if ($null -ne $script:autoCleanupTimer) {
        try {
            $script:autoCleanupTimer.Stop()
            $script:autoCleanupTimer.Interval = [TimeSpan]::FromMinutes($script:autoCleanupIntervalMinutes)
            $script:autoCleanupTimer.Start()
        } catch {}
    }
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
        if (-not (Test-Path -LiteralPath $sidecarScript -PathType Leaf)) {
            Write-AppLog "release worker script is missing: $sidecarScript"
            Fail-UiCleanup (Get-UiText 'CleanupStartFailed')
            return
        }
        $process.StartInfo.FileName = 'powershell.exe'
        $process.StartInfo.Arguments = ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -RunOnce' -f $sidecarScript)
    } else {
        $process.StartInfo.FileName = 'powershell.exe'
        $process.StartInfo.Arguments = ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -RunOnce' -f $scriptPath)
    }
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true

    try {
        if (-not $process.Start()) {
            Fail-UiCleanup (Get-UiText 'CleanupStartFailed')
            return
        }
        # Drain both redirected pipes immediately. Waiting for HasExited before
        # reading can deadlock when the JSON result fills the child-process pipe:
        # the child waits for pipe space while the UI waits for the child to exit.
        $script:cleanupOutputTask = $process.StandardOutput.ReadToEndAsync()
        $script:cleanupErrorTask = $process.StandardError.ReadToEndAsync()
    } catch {
        Write-AppLog "release worker start failed: $($_.Exception.Message)"
        try { if (-not $process.HasExited) { $process.Kill() } } catch {}
        try { $process.Dispose() } catch {}
        $script:cleanupOutputTask = $null
        $script:cleanupErrorTask = $null
        Fail-UiCleanup 'Release worker failed to start.'
        return
    }

    if ($null -ne $script:cleanupPollTimer) { try { $script:cleanupPollTimer.Stop() } catch {} }
    $script:cleanupProcess = $process
    $script:cleanupStartedAt = Get-Date
    $script:cleanupTimeoutSeconds = 120
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
            try { [void]$process.WaitForExit(2000) } catch {}
            try { $process.Dispose() } catch {}
            $script:cleanupPollTimer.Stop()
            $script:cleanupProcess = $null
            $script:cleanupOutputTask = $null
            $script:cleanupErrorTask = $null
            Write-AppLog "release worker timed out after $($script:cleanupTimeoutSeconds) seconds"
            Fail-UiCleanup (Get-UiText 'CleanupTimeout')
            return
        }
        $script:cleanupPollTimer.Stop()
        $output = ''
        $errorOutput = ''
        try {
            if ($null -ne $script:cleanupOutputTask) {
                $output = $script:cleanupOutputTask.GetAwaiter().GetResult()
            }
            if ($null -ne $script:cleanupErrorTask) {
                $errorOutput = $script:cleanupErrorTask.GetAwaiter().GetResult()
            }
        } catch {
            Write-AppLog "release worker output read failed: $($_.Exception.Message)"
        }
        $process.Dispose()
        $script:cleanupProcess = $null
        $script:cleanupOutputTask = $null
        $script:cleanupErrorTask = $null

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

function Get-TopProcessMemoryGroups {
    param([int]$Top = 6)
    try {
        return @(Get-Process | Group-Object ProcessName | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Count = $_.Count
                PrivateMB = [math]::Round(($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum / 1MB, 0)
            }
        } | Sort-Object PrivateMB -Descending | Select-Object -First ([math]::Max(1, $Top)))
    } catch { return @() }
}

function Show-KernelMemoryWindow {
    $kernel = Get-KernelMemoryInfo
    $poolTags = @(Get-KernelPoolTags -Top 8)
    $adapters = @(Get-SuspectNetworkAdapters)
    $bindings = @(Get-SuspectNetworkBindings)
    $services = @(Get-SuspectKernelServices)
    $processGroups = @(Get-TopProcessMemoryGroups -Top 6)
    $lines = @()

    $lines += ("Nonpaged pool: {0} MB" -f $kernel.NonPagedPoolMB)
    $lines += ("Paged pool: {0} MB" -f $kernel.PagedPoolMB)
    $lines += ("Available physical memory: {0} MB" -f $kernel.AvailableMB)
    $lines += ("Standby cache (already available): {0} MB" -f $kernel.StandbyMB)
    $lines += ("Memory compression working set: {0} MB" -f $kernel.CompressionMB)
    $lines += ("System cache working set: {0} MB" -f $kernel.CacheMB)
    $lines += ("Committed: {0} / {1} GB" -f $kernel.CommittedGB, $kernel.CommitLimitGB)
    $lines += ""

    $message = Get-KernelPoolMessage $kernel $poolTags
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        $lines += $message
        $lines += ""
    } else {
        $lines += "Nonpaged pool is not above the warning threshold right now."
        $lines += ""
    }

    $lines += "Top nonpaged pool tags:"
    if ($poolTags.Count -eq 0) {
        $lines += "  unavailable"
    } else {
        foreach ($tag in $poolTags) {
            $lines += ("  {0,-4} {1,8:N1} MB   {2}" -f $tag.Tag, $tag.NonPagedMB, $tag.Owner)
        }
    }
    $lines += ""

    $lines += "Largest application private allocations (not all physically resident):"
    foreach ($group in $processGroups) {
        $suffix = if ($group.Count -gt 1) { " ($($group.Count) processes)" } else { "" }
        $lines += ("  {0,7:N0} MB   {1}{2}" -f $group.PrivateMB, $group.Name, $suffix)
    }
    $lines += ""

    $lines += "Active virtual/tunnel adapters:"
    if ($adapters.Count -eq 0) {
        $lines += "  none detected"
    } else {
        foreach ($adapter in @($adapters | Select-Object -First 6)) {
            $lines += ("  {0} - {1}" -f $adapter.Name, $adapter.Description)
        }
    }
    $lines += ""

    $lines += "Active Realtek filter bindings:"
    if ($bindings.Count -eq 0) {
        $lines += "  none detected"
    } else {
        foreach ($binding in @($bindings | Select-Object -First 8)) {
            $lines += ("  {0} - {1} ({2})" -f $binding.Name, $binding.DisplayName, $binding.ComponentID)
        }
    }
    $lines += ""

    $lines += "Related running services:"
    if ($services.Count -eq 0) {
        $lines += "  none detected"
    } else {
        foreach ($svc in @($services | Select-Object -First 6)) {
            $lines += ("  {0} - {1}" -f $svc.Name, $svc.DisplayName)
        }
    }
    $lines += ""
    $lines += "This tool will not force-release kernel pool memory. Use the top tag and owner above to update, restart, or temporarily unbind the responsible driver for verification."

    [System.Windows.MessageBox]::Show(($lines -join [Environment]::NewLine), (Get-UiText 'KernelMemoryTitle'), 'OK', 'Information') | Out-Null
}

function Show-SettingsWindow {
    if ($null -ne $script:settingsWindow -and $script:settingsWindow.IsVisible) {
        [void]$script:settingsWindow.Activate()
        return
    }

    $settingsWindow = New-Object System.Windows.Window
    $script:settingsWindow = $settingsWindow
    # Modeless WPF event handlers run in a closure scope. Keep all mutable
    # settings state in one reference object so every handler updates the real
    # application settings instead of a closure-local copy.
    $settingsState = [pscustomobject]@{
        UiSettings = $script:uiSettings
        PendingBackgroundColor = Get-BackgroundColorHex $script:uiSettings
        AutoCleanupTimer = $script:autoCleanupTimer
        AppVersion = $script:AppVersion
    }
    $settingsWindow.Title = ('{0} v{1}' -f (Get-UiText 'DisplaySettings'), $settingsState.AppVersion)
    $settingsWindow.Width = 640
    $settingsWindow.Height = 580
    $settingsWindow.MaxHeight = [math]::Max(600, [System.Windows.SystemParameters]::WorkArea.Height - 12)
    $settingsWindow.ResizeMode = [System.Windows.ResizeMode]::NoResize
    if ($script:taskbarModeActive) {
        $settingsWindow.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    } else {
        $settingsWindow.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        $settingsWindow.Owner = $window
    }
    $settingsWindow.Topmost = $true
    $settingsWindow.Background = [System.Windows.Media.Brushes]::White

    $rootPanel = New-Object System.Windows.Controls.StackPanel
    $rootPanel.Margin = New-Object System.Windows.Thickness(22)
    $rootPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = ('{0} v{1}' -f (Get-UiText 'DisplaySettings'), $settingsState.AppVersion)
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

    $displayPositionPanel = New-Object System.Windows.Controls.StackPanel
    $displayPositionPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $displayPositionPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

    $displayPositionLabel = New-Object System.Windows.Controls.TextBlock
    $displayPositionLabel.Text = Get-UiText 'DisplayPosition'
    $displayPositionLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $displayPositionLabel.FontSize = 14
    $displayPositionLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $displayPositionLabel.Width = 165

    $displayPositionBox = New-Object System.Windows.Controls.ComboBox
    $displayPositionBox.Width = 190
    $displayPositionBox.Height = 28
    $displayPositionBox.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $taskbarLeftChoice = New-Object System.Windows.Controls.ComboBoxItem
    $taskbarLeftChoice.Content = Get-UiText 'TaskbarLeft'
    $taskbarLeftChoice.Tag = 'taskbar-left'
    $taskbarRightChoice = New-Object System.Windows.Controls.ComboBoxItem
    $taskbarRightChoice.Content = Get-UiText 'TaskbarRight'
    $taskbarRightChoice.Tag = 'taskbar-right'
    $floatingChoice = New-Object System.Windows.Controls.ComboBoxItem
    $floatingChoice.Content = Get-UiText 'FloatingWindow'
    $floatingChoice.Tag = 'floating'
    [void]$displayPositionBox.Items.Add($taskbarLeftChoice)
    [void]$displayPositionBox.Items.Add($floatingChoice)
    if (([string]$script:uiSettings.DisplayMode).ToLowerInvariant() -eq 'taskbar') {
        $displayPositionBox.SelectedItem = $taskbarLeftChoice
    } else {
        $displayPositionBox.SelectedItem = $floatingChoice
    }
    [void]$displayPositionPanel.Children.Add($displayPositionLabel)
    [void]$displayPositionPanel.Children.Add($displayPositionBox)
    [void]$rootPanel.Children.Add($displayPositionPanel)

    $autoCleanupPanel = New-Object System.Windows.Controls.StackPanel
    $autoCleanupPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $autoCleanupPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

    $autoCleanupLabel = New-Object System.Windows.Controls.TextBlock
    $autoCleanupLabel.Text = Get-UiText 'AutoCleanupInterval'
    $autoCleanupLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $autoCleanupLabel.FontSize = 14
    $autoCleanupLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $autoCleanupLabel.Width = 165

    $autoCleanupBox = New-Object System.Windows.Controls.TextBox
    $autoCleanupBox.Width = 64
    $autoCleanupBox.Height = 28
    $autoCleanupBox.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $autoCleanupBox.FontSize = 14
    $autoCleanupBox.Text = [string]$script:autoCleanupIntervalMinutes
    $autoCleanupBox.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Center

    $autoCleanupUnit = New-Object System.Windows.Controls.TextBlock
    $autoCleanupUnit.Text = Get-UiText 'MinutesRange'
    $autoCleanupUnit.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $autoCleanupUnit.FontSize = 12
    $autoCleanupUnit.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(105, 116, 128))
    $autoCleanupUnit.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $autoCleanupUnit.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)

    [void]$autoCleanupPanel.Children.Add($autoCleanupLabel)
    [void]$autoCleanupPanel.Children.Add($autoCleanupBox)
    [void]$autoCleanupPanel.Children.Add($autoCleanupUnit)
    [void]$rootPanel.Children.Add($autoCleanupPanel)

    $logRetentionPanel = New-Object System.Windows.Controls.StackPanel
    $logRetentionPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $logRetentionPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

    $logRetentionLabel = New-Object System.Windows.Controls.TextBlock
    $logRetentionLabel.Text = Get-UiText 'LogRetentionDays'
    $logRetentionLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $logRetentionLabel.FontSize = 14
    $logRetentionLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $logRetentionLabel.Width = 165

    $logRetentionBox = New-Object System.Windows.Controls.TextBox
    $logRetentionBox.Width = 64
    $logRetentionBox.Height = 28
    $logRetentionBox.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $logRetentionBox.FontSize = 14
    $logRetentionBox.Text = [string](Get-LogRetentionDays $script:uiSettings)
    $logRetentionBox.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Center

    $logRetentionUnit = New-Object System.Windows.Controls.TextBlock
    $logRetentionUnit.Text = Get-UiText 'DaysRange'
    $logRetentionUnit.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $logRetentionUnit.FontSize = 12
    $logRetentionUnit.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(105, 116, 128))
    $logRetentionUnit.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $logRetentionUnit.Margin = New-Object System.Windows.Thickness(8, 0, 8, 0)

    $clearLogButton = New-Object System.Windows.Controls.Button
    $clearLogButton.Content = Get-UiText 'ClearLogNow'
    $clearLogButton.Width = 92
    $clearLogButton.Height = 28
    $clearLogButton.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')

    [void]$logRetentionPanel.Children.Add($logRetentionLabel)
    [void]$logRetentionPanel.Children.Add($logRetentionBox)
    [void]$logRetentionPanel.Children.Add($logRetentionUnit)
    [void]$logRetentionPanel.Children.Add($clearLogButton)
    [void]$rootPanel.Children.Add($logRetentionPanel)

    $backgroundBaseline = [pscustomobject]@{
        Color = [string]$settingsState.UiSettings.BackgroundColor
        Transparency = [int](Get-BackgroundTransparency $settingsState.UiSettings)
        UseBackgroundColor = [bool]$settingsState.UiSettings.UseBackgroundColor
    }
    $backgroundSection = New-Object System.Windows.Controls.StackPanel
    $backgroundSection.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

    $backgroundColorLabel = New-Object System.Windows.Controls.TextBlock
    $backgroundColorLabel.Text = Get-UiText 'BackgroundAppearance'
    $backgroundColorLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $backgroundColorLabel.FontSize = 14
    $backgroundColorLabel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
    [void]$backgroundSection.Children.Add($backgroundColorLabel)

    $backgroundColorPanel = New-Object System.Windows.Controls.StackPanel
    $backgroundColorPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $backgroundColorPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)

    $backgroundColorPreview = New-Object System.Windows.Controls.Border
    $backgroundColorPreview.Width = 30
    $backgroundColorPreview.Height = 30
    $backgroundColorPreview.CornerRadius = New-Object System.Windows.CornerRadius(3)
    $backgroundColorPreview.BorderThickness = New-Object System.Windows.Thickness(1)
    $backgroundColorPreview.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(150, 150, 150))
    $backgroundColorPreview.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

    $chooseColorButton = New-Object System.Windows.Controls.Button
    $chooseColorButton.Width = 112
    $chooseColorButton.Height = 30

    $backgroundOpacityLabel = New-Object System.Windows.Controls.TextBlock
    $backgroundOpacityLabel.Text = Get-UiText 'BackgroundOpacity'
    $backgroundOpacityLabel.Margin = New-Object System.Windows.Thickness(12, 5, 6, 0)
    $backgroundOpacityLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $backgroundOpacitySlider = New-Object System.Windows.Controls.Slider
    $backgroundOpacitySlider.Minimum = 20
    $backgroundOpacitySlider.Maximum = 90
    $backgroundOpacitySlider.Value = Get-BackgroundTransparency $script:uiSettings
    $backgroundOpacitySlider.TickFrequency = 1
    $backgroundOpacitySlider.IsSnapToTickEnabled = $true
    $backgroundOpacitySlider.Width = 105
    $backgroundOpacitySlider.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $backgroundOpacityValue = New-Object System.Windows.Controls.TextBlock
    $backgroundOpacityValue.Width = 42
    $backgroundOpacityValue.Margin = New-Object System.Windows.Thickness(6, 5, 0, 0)
    $backgroundOpacityValue.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    [void]$backgroundColorPanel.Children.Add($backgroundColorPreview)
    [void]$backgroundColorPanel.Children.Add($chooseColorButton)
    [void]$backgroundColorPanel.Children.Add($backgroundOpacityLabel)
    [void]$backgroundColorPanel.Children.Add($backgroundOpacitySlider)
    [void]$backgroundColorPanel.Children.Add($backgroundOpacityValue)

    [void]$backgroundSection.Children.Add($backgroundColorPanel)
    [void]$rootPanel.Children.Add($backgroundSection)

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

    $updateBackgroundColorPreview = {
        $hex = [string]$settingsState.PendingBackgroundColor
        if ($hex -notmatch '^#[0-9A-Fa-f]{6}$') { $hex = '#303033' }
        $red = [Convert]::ToByte($hex.Substring(1, 2), 16)
        $green = [Convert]::ToByte($hex.Substring(3, 2), 16)
        $blue = [Convert]::ToByte($hex.Substring(5, 2), 16)
        $backgroundColorPreview.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb($red, $green, $blue))
        $chooseColorButton.Content = $hex.ToUpperInvariant()
        $backgroundOpacityValue.Text = ('{0}%' -f [int][math]::Round($backgroundOpacitySlider.Value))
    }.GetNewClosure()

    $applyBackgroundPreview = {
        $settingsState.UiSettings.UseBackgroundColor = $true
        $settingsState.UiSettings.BackgroundColor = [string]$settingsState.PendingBackgroundColor
        $settingsState.UiSettings.BackgroundOpacity = [int][math]::Round($backgroundOpacitySlider.Value)
        Protect-EmbeddedModeForAppearanceUpdate
        Apply-AppearanceSettings
        Write-TaskbarHostState
    }.GetNewClosure()

    $updateSettingsWindowText = {
        $settingsWindow.Title = ('{0} v{1}' -f (Get-UiText 'DisplaySettings'), $settingsState.AppVersion)
        $titleBlock.Text = ('{0} v{1}' -f (Get-UiText 'DisplaySettings'), $settingsState.AppVersion)
        $speedCheck.Content = Get-UiText 'ShowSpeed'
        $locationCheck.Content = Get-UiText 'ShowLocation'
        $displayPositionLabel.Text = Get-UiText 'DisplayPosition'
        $taskbarLeftChoice.Content = Get-UiText 'TaskbarLeft'
        $taskbarRightChoice.Content = Get-UiText 'TaskbarRight'
        $floatingChoice.Content = Get-UiText 'FloatingWindow'
        $autoCleanupLabel.Text = Get-UiText 'AutoCleanupInterval'
        $autoCleanupUnit.Text = Get-UiText 'MinutesRange'
        $logRetentionLabel.Text = Get-UiText 'LogRetentionDays'
        $logRetentionUnit.Text = Get-UiText 'DaysRange'
        $clearLogButton.Content = Get-UiText 'ClearLogNow'
        $backgroundColorLabel.Text = Get-UiText 'BackgroundAppearance'
        $backgroundOpacityLabel.Text = Get-UiText 'BackgroundOpacity'
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
    }.GetNewClosure()

    $chooseColorButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.ColorDialog
        $hex = [string]$settingsState.PendingBackgroundColor
        if ($hex -notmatch '^#[0-9A-Fa-f]{6}$') { $hex = '#303033' }
        $dialog.Color = [System.Drawing.Color]::FromArgb(
            [Convert]::ToByte($hex.Substring(1, 2), 16),
            [Convert]::ToByte($hex.Substring(3, 2), 16),
            [Convert]::ToByte($hex.Substring(5, 2), 16)
        )
        $dialog.FullOpen = $true
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $settingsState.PendingBackgroundColor = '#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R, $dialog.Color.G, $dialog.Color.B
            & $updateBackgroundColorPreview
            & $applyBackgroundPreview
        }
        $dialog.Dispose()
    }.GetNewClosure())

    $backgroundOpacitySlider.Add_ValueChanged({
        & $updateBackgroundColorPreview
        & $applyBackgroundPreview
    }.GetNewClosure())

    $showSettingsFeedback = {
        param([bool]$Success, [string]$Message = '')
        if ($Success) {
            if ([string]::IsNullOrWhiteSpace($Message)) { $Message = Get-UiText 'Saved' }
            $hintBlock.Text = $Message
            $hintBlock.Foreground = $successHintBrush
            $saveButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(48, 209, 88))
            $saveButton.Foreground = [System.Windows.Media.Brushes]::White
        } else {
            if ([string]::IsNullOrWhiteSpace($Message)) { $Message = Get-UiText 'SaveFailed' }
            $hintBlock.Text = $Message
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
        }.GetNewClosure())
        $feedbackTimer.Start()
    }.GetNewClosure()

    $clearLogButton.Add_Click({
        try {
            Clear-AppLog
            & $showSettingsFeedback $true (Get-UiText 'LogCleared')
        } catch {
            Write-AppLog "manual log clear failed: $($_.Exception.Message)"
            & $showSettingsFeedback $false (Get-UiText 'SaveFailed')
        }
    }.GetNewClosure())

    $saveButton.Add_Click({
        try {
            $newAutoCleanupMinutes = 0
            if (-not [int]::TryParse($autoCleanupBox.Text.Trim(), [ref]$newAutoCleanupMinutes) -or $newAutoCleanupMinutes -lt 1 -or $newAutoCleanupMinutes -gt 1440) {
                & $showSettingsFeedback $false (Get-UiText 'IntervalInvalid')
                return
            }
            $newLogRetentionDays = 0
            if (-not [int]::TryParse($logRetentionBox.Text.Trim(), [ref]$newLogRetentionDays) -or $newLogRetentionDays -lt 1 -or $newLogRetentionDays -gt 30) {
                & $showSettingsFeedback $false (Get-UiText 'RetentionInvalid')
                return
            }
            $settingsState.UiSettings.ShowNetworkSpeed = [bool]$speedCheck.IsChecked
            $settingsState.UiSettings.ShowNetworkLocation = [bool]$locationCheck.IsChecked
            $settingsState.UiSettings.AutoCleanupIntervalMinutes = $newAutoCleanupMinutes
            $settingsState.UiSettings.LogCleanupIntervalDays = 1
            $settingsState.UiSettings.LogRetentionDays = $newLogRetentionDays
            $settingsState.UiSettings.UseCustomAppearance = $false
            $settingsState.UiSettings.UseBackgroundColor = $true
            $settingsState.UiSettings.BackgroundColor = [string]$settingsState.PendingBackgroundColor
            $settingsState.UiSettings.BackgroundOpacity = [int][math]::Round($backgroundOpacitySlider.Value)
            $displayChoice = [string]$displayPositionBox.SelectedItem.Tag
            if ($displayChoice -eq 'floating') {
                $settingsState.UiSettings.DisplayMode = 'floating'
            } else {
                $settingsState.UiSettings.DisplayMode = 'taskbar'
                $settingsState.UiSettings.TaskbarPosition = 'left'
            }
            if ($null -ne $languageBox.SelectedItem -and -not [string]::IsNullOrWhiteSpace([string]$languageBox.SelectedItem.Tag)) {
                $settingsState.UiSettings.Language = [string]$languageBox.SelectedItem.Tag
            } else {
                $settingsState.UiSettings.Language = 'en'
            }
            if ($null -ne $iconBox.SelectedItem -and -not [string]::IsNullOrWhiteSpace([string]$iconBox.SelectedItem.Tag)) {
                $settingsState.UiSettings.IconStyle = [string]$iconBox.SelectedItem.Tag
            } else {
                $settingsState.UiSettings.IconStyle = 'bars'
            }
            Save-Settings $settingsState.UiSettings
            $backgroundBaseline.Color = [string]$settingsState.UiSettings.BackgroundColor
            $backgroundBaseline.Transparency = [int](Get-BackgroundTransparency $settingsState.UiSettings)
            $backgroundBaseline.UseBackgroundColor = [bool]$settingsState.UiSettings.UseBackgroundColor
            Invoke-LogMaintenance -Force
            if ($null -ne $settingsState.AutoCleanupTimer) {
                $settingsState.AutoCleanupTimer.Stop()
                $settingsState.AutoCleanupTimer.Interval = [TimeSpan]::FromMinutes($newAutoCleanupMinutes)
                $settingsState.AutoCleanupTimer.Start()
            }
            Reset-NetworkStatusCache
            & $updateSettingsWindowText
            Protect-EmbeddedModeForAppearanceUpdate
            Apply-UiSettings
            & $showSettingsFeedback $true
            Write-AppLog "settings saved: speed=$($settingsState.UiSettings.ShowNetworkSpeed) location=$($settingsState.UiSettings.ShowNetworkLocation) language=$($settingsState.UiSettings.Language) icon=$($settingsState.UiSettings.IconStyle) autoCleanupMinutes=$newAutoCleanupMinutes logRetentionDays=$newLogRetentionDays customAppearance=$($settingsState.UiSettings.UseCustomAppearance) backgroundColor=$($settingsState.UiSettings.UseBackgroundColor):$($settingsState.UiSettings.BackgroundColor) opacity=$($settingsState.UiSettings.BackgroundOpacity)"
        } catch {
            Write-AppLog "settings save failed: $($_.Exception.Message)"
            & $showSettingsFeedback $false
        }
    }.GetNewClosure())
    $cancelButton.Add_Click({ $settingsWindow.Close() }.GetNewClosure())

    $settingsWindow.Add_Closed({
        $settingsState.UiSettings.UseBackgroundColor = $backgroundBaseline.UseBackgroundColor
        $settingsState.UiSettings.BackgroundColor = $backgroundBaseline.Color
        $settingsState.UiSettings.BackgroundOpacity = $backgroundBaseline.Transparency
        Apply-AppearanceSettings
        Write-TaskbarHostState
        $script:settingsWindow = $null
    }.GetNewClosure())

    $settingsScrollViewer = New-Object System.Windows.Controls.ScrollViewer
    $settingsScrollViewer.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $settingsScrollViewer.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
    $settingsScrollViewer.Content = $rootPanel
    $settingsWindow.Content = $settingsScrollViewer
    & $updateBackgroundColorPreview
    [void]$settingsWindow.Show()
}

$showHideItem.Add_Click({ Toggle-MainWindow })
$taskbarLeftItem.Add_Click({
    Set-DisplayMode -Mode 'taskbar' -Position 'left'
    Save-Settings $script:uiSettings
    Apply-UiSettings
})
$taskbarRightItem.Add_Click({
    Set-DisplayMode -Mode 'taskbar' -Position 'right'
    Save-Settings $script:uiSettings
    Apply-UiSettings
})
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
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Toggle-MainWindow
    }
})
$window.Add_StateChanged({ Update-WindowVisibilityMenu })
$window.Add_IsVisibleChanged({ Update-WindowVisibilityMenu })

$root.Add_MouseEnter({
    if ($script:taskbarModeActive) {
        Set-WpfOpacity $taskbarHover 1.0 100
    } else {
        Set-WpfOpacity $hoverLayer 1.0 140
    }
})
$root.Add_MouseLeave({
    Set-WpfOpacity $hoverLayer 0.0 180
    Set-WpfOpacity $taskbarHover 0.0 120
    Set-IconPressVisual $false
})
$root.Add_MouseRightButtonUp({
    $pos = [System.Windows.Forms.Cursor]::Position
    Show-AppContextMenu -Position $pos
})
$script:isDraggingWindow = $false
$script:dragMovedWindow = $false
$script:dragWasIconPress = $false
$script:dragStartPoint = $null
$script:dragStartLeftPx = 0
$script:dragStartTopPx = 0
$script:dragWindowHandle = [IntPtr]::Zero
$script:taskbarClickArmed = $false
$script:dragOverTaskbar = $false

function Get-TaskbarDropInfo {
    param([System.Drawing.Point]$CursorPoint)
    try {
        Ensure-NativeApis
        $taskbarHandle = [NativeMemoryCleaner]::FindWindow('Shell_TrayWnd', $null)
        if ($taskbarHandle -eq [IntPtr]::Zero) { return $null }
        $taskbarRect = New-Object NativeMemoryCleaner+RECT
        if (-not [NativeMemoryCleaner]::GetWindowRect($taskbarHandle, [ref]$taskbarRect)) { return $null }
        $width = [int]($taskbarRect.Right - $taskbarRect.Left)
        $height = [int]($taskbarRect.Bottom - $taskbarRect.Top)
        # Native Windows 11 supports a horizontal taskbar. Reject replacement
        # taskbars instead of pretending a floating overlay is embedded.
        if ($width -le $height) { return $null }
        $dpi = try { [int][NativeMemoryCleaner]::GetDpiForWindow($taskbarHandle) } catch { 96 }
        if ($dpi -le 0) { $dpi = 96 }
        $margin = [int][math]::Ceiling(16.0 * $dpi / 96.0)
        $insideDropZone = (
            $CursorPoint.X -ge $taskbarRect.Left -and
            $CursorPoint.X -lt $taskbarRect.Right -and
            $CursorPoint.Y -ge ($taskbarRect.Top - $margin) -and
            $CursorPoint.Y -lt ($taskbarRect.Bottom + $margin)
        )
        if (-not $insideDropZone) { return $null }

        $trayLeft = [int]$taskbarRect.Right
        $trayHandle = [NativeMemoryCleaner]::FindWindowEx($taskbarHandle, [IntPtr]::Zero, 'TrayNotifyWnd', $null)
        if ($trayHandle -ne [IntPtr]::Zero) {
            $trayRect = New-Object NativeMemoryCleaner+RECT
            if ([NativeMemoryCleaner]::GetWindowRect($trayHandle, [ref]$trayRect) -and $trayRect.Left -gt $taskbarRect.Left) {
                $trayLeft = [int]$trayRect.Left
            }
        }
        return [pscustomobject]@{
            Left = [int]$taskbarRect.Left
            Right = [int]$taskbarRect.Right
            Width = $width
            TrayLeft = $trayLeft
            Dpi = $dpi
        }
    } catch {
        Write-AppLog "taskbar drop detection failed: $($_.Exception.Message)"
        return $null
    }
}

function Convert-TaskbarSlotToFloating {
    # The module ejected the taskbar slot (the user dragged it out of the
    # taskbar). Switch to floating mode and drop the panel at the release
    # point so the drag feels like the slot simply flew out of the taskbar.
    try {
        if (-not $script:taskbarModeActive) { return }
        $cursor = [System.Windows.Forms.Cursor]::Position
        # The controller window is hidden in taskbar mode, so it has no WPF
        # presentation source to convert from. Use the taskbar monitor DPI
        # directly; this preserves the mouse release point after a restart.
        $taskbarHandle = [NativeMemoryCleaner]::FindWindow('Shell_TrayWnd', $null)
        $dpi = 96
        if ($taskbarHandle -ne [IntPtr]::Zero) {
            try { $dpi = [math]::Max(96, [int][NativeMemoryCleaner]::GetDpiForWindow($taskbarHandle)) } catch {}
        }
        $scale = [double]$dpi / 96.0
        $floatLeft = ([double]$cursor.X / $scale) - ($window.Width / 2.0)
        $floatTop = ([double]$cursor.Y / $scale) - ($window.Height / 2.0)
        Set-DisplayMode -Mode 'floating' -FloatLeft $floatLeft -FloatTop $floatTop
        try { Remove-Item -LiteralPath $script:taskbarEjectStatePath -Force -ErrorAction SilentlyContinue } catch {}
        Write-AppLog "taskbar slot ejected to floating: cursorX=$($cursor.X) cursorY=$($cursor.Y) dpi=$dpi left=$floatLeft top=$floatTop"
    } catch {
        Write-AppLog "taskbar slot eject failed: $($_.Exception.Message)"
    }
}

function Convert-FloatingDropToTaskbar {
    param([System.Drawing.Point]$CursorPoint)
    if ($script:taskbarModeActive) { return $false }
    $dropInfo = Get-TaskbarDropInfo -CursorPoint $CursorPoint
    if ($null -eq $dropInfo) { return $false }

    $scale = [math]::Max(1.0, [double]$dropInfo.Dpi / 96.0)
    $slotWidth = 360.0
    $trayWidth = [math]::Max(0.0, ([double]$dropInfo.Right - [double]$dropInfo.TrayLeft) / $scale)
    $maximumOffset = [math]::Max(0.0, ([double]$dropInfo.Width / $scale) - $trayWidth - $slotWidth - 360.0)
    $baseCenterX = [double]$dropInfo.TrayLeft - (($slotWidth * $scale) / 2.0)
    $dropOffset = ($baseCenterX - [double]$CursorPoint.X) / $scale
    $dropOffset = [int][math]::Round([math]::Min(1600.0, [math]::Min($maximumOffset, [math]::Max(0.0, $dropOffset))))

    $script:uiSettings.DisplayMode = 'taskbar'
    $script:uiSettings.TaskbarPosition = 'left'
    $script:uiSettings.TaskbarOffset = $dropOffset
    Save-Settings $script:uiSettings
    Apply-UiSettings
    Write-AppLog "floating panel dropped into taskbar: offset=$dropOffset cursorX=$($CursorPoint.X)"
    return $true
}

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

    # The taskbar capsule is fixed in place. Keep its click path independent
    # from floating-window drag/capture so a click cannot perturb its layout.
    if ($script:taskbarModeActive) {
        $script:taskbarClickArmed = $true
        Set-WpfOpacity $taskbarHover 1.0 70
        $e.Handled = $true
        return
    }

    $wasIconPress = ($script:customAppearanceActive -or $e.OriginalSource -eq $iconButton -or $iconButton.IsAncestorOf($e.OriginalSource))
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
    $script:dragOverTaskbar = $false
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

    if ($script:taskbarModeActive) {
        $e.Handled = $true
        return
    }

    $script:dragOverTaskbar = ($null -ne (Get-TaskbarDropInfo -CursorPoint $current))
    $window.Opacity = if ($script:dragOverTaskbar) { 0.82 } else { 1.0 }

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
    $window.Opacity = 1.0

    $dropPoint = [System.Windows.Forms.Control]::MousePosition
    if ($script:dragMovedWindow -and (Convert-FloatingDropToTaskbar -CursorPoint $dropPoint)) {
        $script:dragOverTaskbar = $false
        $e.Handled = $true
        return
    }
    $script:dragOverTaskbar = $false

    if (-not $script:dragMovedWindow -and ($script:taskbarModeActive -or $script:dragWasIconPress)) {
        Run-UiCleanup
    } else {
        Queue-PostDragRefresh
    }
    $e.Handled = $true
})

$root.Add_PreviewMouseLeftButtonUp({
    param($sender, $e)
    if (-not $script:taskbarModeActive -or -not $script:taskbarClickArmed) { return }
    $script:taskbarClickArmed = $false
    Set-WpfOpacity $taskbarHover 0.0 120
    if (-not $script:cleanupInProgress) {
        Run-UiCleanup
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

$script:autoCleanupTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:autoCleanupTimer.Interval = [TimeSpan]::FromMinutes($script:autoCleanupIntervalMinutes)
$script:autoCleanupTimer.Add_Tick({
    if (-not $script:isDraggingWindow -and -not $script:cleanupInProgress) {
        Write-AppLog "automatic release triggered: intervalMinutes=$($script:autoCleanupIntervalMinutes)"
        Run-UiCleanup
    }
})
$script:autoCleanupTimer.Start()

$logMaintenanceTimer = New-Object System.Windows.Threading.DispatcherTimer
$logMaintenanceTimer.Interval = [TimeSpan]::FromHours(6)
$logMaintenanceTimer.Add_Tick({ Invoke-LogMaintenance })
$logMaintenanceTimer.Start()

$taskbarPlacementTimer = New-Object System.Windows.Threading.DispatcherTimer
$taskbarPlacementTimer.Interval = [TimeSpan]::FromSeconds(2)
$taskbarPlacementTimer.Add_Tick({
    if ($script:taskbarModeActive) {
        Sync-TaskbarDragPosition
        $taskbarReady = $false
        try {
            if (Test-Path -LiteralPath $script:taskbarReadyStatePath -PathType Leaf) {
                $readyFile = Get-Item -LiteralPath $script:taskbarReadyStatePath
                $readyState = Get-Content -LiteralPath $script:taskbarReadyStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $readyPid = 0
                [void][int]::TryParse([string]$readyState.ExplorerPid, [ref]$readyPid)
                $readyExplorer = $null
                if ($readyPid -gt 0) {
                    try { $readyExplorer = Get-Process -Id $readyPid -ErrorAction SilentlyContinue } catch {}
                }
                $taskbarReady = (
                    $null -ne $readyExplorer -and
                    $readyExplorer.ProcessName -ieq 'explorer' -and
                    [string]$readyState.Version -eq $script:taskbarModuleVersion -and
                    ((Get-Date) - $readyFile.LastWriteTime).TotalSeconds -le 15
                )
            }
        } catch { $taskbarReady = $false }
        if (-not $taskbarReady -and ((Get-Date) - $script:taskbarInjectionStartedAt).TotalMinutes -lt 10) {
            Request-WindhawkTaskbarInjection
            $script:taskbarInjectionAttempts++
        }
        if ($script:cleanupInProgress -or $script:statusOverride) { Write-TaskbarHostState }
        elseif (-not $script:isDraggingWindow) { Apply-TaskbarPlacement }
    }
})
$taskbarPlacementTimer.Start()

$activationTimer = New-Object System.Windows.Threading.DispatcherTimer
$activationTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$activationTimer.Add_Tick({
    if ($menu.Visible) {
        $escapeState = [int][NativeMemoryCleaner]::GetAsyncKeyState(0x1B)
        if (($escapeState -band 0x8000) -ne 0 -or ($escapeState -band 0x0001) -ne 0) {
            $menu.Close([System.Windows.Forms.ToolStripDropDownCloseReason]::Keyboard)
        }
    }
    if ($null -ne $script:activationEvent -and $script:activationEvent.WaitOne(0)) {
        Show-MainWindow
    }
    if ($null -ne $script:taskbarHostCleanEvent -and $script:taskbarHostCleanEvent.WaitOne(0)) {
        Run-UiCleanup
    }
    if ($null -ne $script:taskbarHostMenuEvent -and $script:taskbarHostMenuEvent.WaitOne(0)) {
        Show-AppContextMenu -Position ([System.Windows.Forms.Cursor]::Position)
    }
    if ($null -ne $script:taskbarPositionEvent -and $script:taskbarPositionEvent.WaitOne(0)) {
        Sync-TaskbarDragPosition
    }
    if ($null -ne $script:taskbarEjectEvent -and $script:taskbarEjectEvent.WaitOne(0)) {
        if (Test-TaskbarEjectSuppressed -TaskbarModeActive $script:taskbarModeActive -GuardUntil $script:taskbarAppearanceGuardUntil) {
            try { Remove-Item -LiteralPath $script:taskbarEjectStatePath -Force -ErrorAction SilentlyContinue } catch {}
            Write-AppLog 'ignored synthetic taskbar eject during appearance update'
        } else {
            Convert-TaskbarSlotToFloating
        }
    }
})
$activationTimer.Start()

$window.Add_Closed({
    $timer.Stop()
    $netTimer.Stop()
    $script:autoCleanupTimer.Stop()
    $logMaintenanceTimer.Stop()
    $taskbarPlacementTimer.Stop()
    $activationTimer.Stop()
    if ($null -ne $script:cleanupPollTimer) {
        try { $script:cleanupPollTimer.Stop() } catch {}
    }
    if ($null -ne $script:cleanupProcess) {
        try {
            if (-not $script:cleanupProcess.HasExited) { $script:cleanupProcess.Kill() }
            [void]$script:cleanupProcess.WaitForExit(2000)
        } catch {}
        try { $script:cleanupProcess.Dispose() } catch {}
        $script:cleanupProcess = $null
        $script:cleanupOutputTask = $null
        $script:cleanupErrorTask = $null
    }
    if ($null -ne $script:taskbarHostProcess) {
        try {
            if (-not $script:taskbarHostProcess.HasExited) { $script:taskbarHostProcess.Kill() }
        } catch {}
        try { $script:taskbarHostProcess.Dispose() } catch {}
        $script:taskbarHostProcess = $null
    }
    if ($null -ne $script:taskbarHostCleanEvent) {
        try { $script:taskbarHostCleanEvent.Dispose() } catch {}
        $script:taskbarHostCleanEvent = $null
    }
    if ($null -ne $script:taskbarHostMenuEvent) {
        try { $script:taskbarHostMenuEvent.Dispose() } catch {}
        $script:taskbarHostMenuEvent = $null
    }
    if ($null -ne $script:taskbarPositionEvent) {
        try { $script:taskbarPositionEvent.Dispose() } catch {}
        $script:taskbarPositionEvent = $null
    }
    if ($null -ne $script:taskbarEjectEvent) {
        try { $script:taskbarEjectEvent.Dispose() } catch {}
        $script:taskbarEjectEvent = $null
    }
    try { Remove-Item -LiteralPath $script:taskbarHostStatePath -Force -ErrorAction SilentlyContinue } catch {}
    if ($null -ne $script:postDragRefreshTimer) {
        try { $script:postDragRefreshTimer.Stop() } catch {}
    }
    if ($null -ne $script:geoLookupJob) {
        try { Remove-Job -Job $script:geoLookupJob -Force | Out-Null } catch {}
        $script:geoLookupJob = $null
    }
    Stop-WindhawkEngine
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    if ($null -ne $script:activationEvent) {
        try { $script:activationEvent.Dispose() } catch {}
        $script:activationEvent = $null
    }
    if ($null -ne $script:singleInstanceMutex) {
        try { $script:singleInstanceMutex.ReleaseMutex() | Out-Null } catch {}
        $script:singleInstanceMutex.Dispose()
    }
})

Write-AppLog "Memory Cleaner Float started with WPF UI. autoCleanupMinutes=$($script:autoCleanupIntervalMinutes)"
$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$app.MainWindow = $window
if (-not $script:taskbarModeActive -and -not $window.IsVisible) {
    $window.Show()
}
if ($OpenSettingsForTest) {
    $window.Dispatcher.BeginInvoke([System.Action]{ Show-SettingsWindow }) | Out-Null
}
$app.Run() | Out-Null
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
$showHideItem = $menu.Items.Add('Show or hide floating window')
$menu.Items.Add('-') | Out-Null
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

function Show-MainForm {
    if (-not $form.Visible) { $form.Show() }
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    $form.ShowInTaskbar = $false
    $form.Activate()
}

function Toggle-MainForm {
    if ($form.Visible -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.Hide()
    } else {
        Show-MainForm
    }
}

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
$showHideItem.Add_Click({ Toggle-MainForm })
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
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Toggle-MainForm
    }
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
    Stop-WindhawkEngine
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
})

Write-AppLog 'Memory Cleaner Float started.'
[System.Windows.Forms.Application]::Run($form)
