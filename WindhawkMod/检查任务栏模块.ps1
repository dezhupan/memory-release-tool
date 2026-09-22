param(
    [string]$WindhawkRoot = '',
    [int]$WaitSeconds = 180,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$modId = 'local@memory-cleaner-taskbar-slot'
$requiredModuleVersion = '1.6.2'
$readyPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\taskbar-ready.json'

function Resolve-WindhawkRoot {
    param([string]$PreferredRoot)
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PreferredRoot)) { $candidates += $PreferredRoot }
    $candidates += @(
        (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'MemoryCleanerFloat\Windhawk'),
        'D:\Windhawk',
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'Windhawk')
    )
    foreach ($candidate in $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'windhawk.exe') -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Get-SharedTextFile {
    param([string]$Path)
    try {
        $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::Unicode, $true)
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
    } catch { return '' }
}

function Get-ModuleRuntimeState {
    param([string]$Root)
    $result = [ordered]@{ Status = ''; Task = '' }
    $writable = Join-Path $Root 'AppData\Engine\ModsWritable'
    foreach ($category in @('mod-status','mod-task')) {
        $directory = Join-Path $writable $category
        $files = @(Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$modId" })
        $values = @($files | ForEach-Object { Get-SharedTextFile $_.FullName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($category -eq 'mod-status') { $result.Status = $values -join '; ' }
        else { $result.Task = $values -join '; ' }
    }
    return [pscustomobject]$result
}

function Test-ReadyMarker {
    if (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) { return $false }
    try {
        $file = Get-Item -LiteralPath $readyPath
        $ready = Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $currentSessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId
        $explorer = Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object {
            $_.SessionId -eq $currentSessionId
        } | Sort-Object StartTime -Descending | Select-Object -First 1
        return (
            $null -ne $explorer -and
            [string]$ready.Version -eq [string]$script:expectedModuleVersion -and
            [int]$ready.ExplorerPid -eq [int]$explorer.Id -and
            ((Get-Date) - $file.LastWriteTime).TotalSeconds -le 15
        )
    } catch { return $false }
}

$resolvedRoot = Resolve-WindhawkRoot $WindhawkRoot
if ($null -eq $resolvedRoot) {
    if (-not $Quiet) { Write-Host '未找到 Windhawk。请先安装 Windhawk，推荐使用 D:\Windhawk。' -ForegroundColor Red }
    exit 10
}

$configPath = Join-Path $resolvedRoot "AppData\Engine\Mods\$modId.ini"
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    if (-not $Quiet) { Write-Host '未找到任务栏模块配置，请先运行安装脚本。' -ForegroundColor Red }
    exit 11
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
$script:expectedModuleVersion = ((($config -split "`r?`n") | Where-Object { $_ -like 'Version=*' }) -replace '^Version=', '' | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($script:expectedModuleVersion)) {
    if (-not $Quiet) { Write-Host '任务栏模块配置缺少版本号。' -ForegroundColor Red }
    exit 13
}
if ($script:expectedModuleVersion -ne $requiredModuleVersion) {
    if (-not $Quiet) { Write-Host "检测到旧任务栏模块 $script:expectedModuleVersion，当前安装包需要 $requiredModuleVersion。请重新运行当前安装程序升级。" -ForegroundColor Red }
    exit 14
}
if ($config -match '(?m)^Disabled=1\s*$') {
    if (-not $Quiet) { Write-Host '任务栏模块当前被禁用。' -ForegroundColor Red }
    exit 12
}

$deadline = (Get-Date).AddSeconds([math]::Max(1, $WaitSeconds))
do {
    if (Test-ReadyMarker) {
        if (-not $Quiet) { Write-Host '任务栏模块已经真正嵌入并处于活动状态。' -ForegroundColor Green }
        exit 0
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

$runtime = Get-ModuleRuntimeState $resolvedRoot
$build = [Environment]::OSVersion.Version.Build
if (-not $Quiet) {
    Write-Host '任务栏模块未能确认嵌入。' -ForegroundColor Red
    Write-Host "Windows build: $build"
    Write-Host "Windhawk: $resolvedRoot"
    Write-Host "Module status: $($runtime.Status)"
    Write-Host "Module task: $($runtime.Task)"
    if ($runtime.Task -match 'symbols') {
        Write-Host 'Windhawk 仍在下载或解析当前 Windows 版本的任务栏符号，请保持联网并稍后重试。' -ForegroundColor Yellow
    } elseif ($runtime.Status -notmatch 'Loaded') {
        Write-Host '模块没有加载到 explorer.exe；请检查 Windhawk 是否运行、模块是否启用。' -ForegroundColor Yellow
    } else {
        Write-Host '模块已加载但未找到原生 Windows 11 任务栏。请禁用 ExplorerPatcher、StartAllBack 等任务栏替换工具后重试。' -ForegroundColor Yellow
    }
}
exit 20
