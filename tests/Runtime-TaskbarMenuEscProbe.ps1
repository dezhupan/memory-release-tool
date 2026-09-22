$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if (-not ('MemoryCleanerMenuProbeNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class MemoryCleanerMenuProbeNative {
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);

    public static string[] VisibleWindowsForProcess(uint expectedProcessId) {
        var result = new List<string>();
        EnumWindows((hwnd, parameter) => {
            uint processId;
            GetWindowThreadProcessId(hwnd, out processId);
            if (processId == expectedProcessId && IsWindowVisible(hwnd)) {
                var className = new StringBuilder(256);
                GetClassName(hwnd, className, className.Capacity);
                result.Add(className.ToString());
            }
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }
}
'@
}

[void][MemoryCleanerMenuProbeNative]::SetProcessDPIAware()
$project = Split-Path -Parent $PSScriptRoot
$app = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like '*v3.2.exe'
} | Select-Object -First 1
if ($null -eq $app) { throw 'v3.2 is not running.' }

$baseline = [MemoryCleanerMenuProbeNative]::VisibleWindowsForProcess([uint32]$app.ProcessId)
$originalCursor = [System.Windows.Forms.Cursor]::Position
try {
    [void][MemoryCleanerMenuProbeNative]::SetCursorPos(1875, 1599)
    Start-Sleep -Milliseconds 1200
    [void][MemoryCleanerMenuProbeNative]::SetCursorPos(1875, 1555)
    Start-Sleep -Milliseconds 250
    [MemoryCleanerMenuProbeNative]::mouse_event(8, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 70
    [MemoryCleanerMenuProbeNative]::mouse_event(16, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 600
    $opened = [MemoryCleanerMenuProbeNative]::VisibleWindowsForProcess([uint32]$app.ProcessId)

    [MemoryCleanerMenuProbeNative]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [MemoryCleanerMenuProbeNative]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 700
    $closed = [MemoryCleanerMenuProbeNative]::VisibleWindowsForProcess([uint32]$app.ProcessId)
} finally {
    [void][MemoryCleanerMenuProbeNative]::SetCursorPos($originalCursor.X, $originalCursor.Y)
}

$openedMenuWindows = @($opened | Where-Object { $_ -like 'WindowsForms10.*' }).Count
$closedMenuWindows = @($closed | Where-Object { $_ -like 'WindowsForms10.*' }).Count
if ($openedMenuWindows -lt 1) { throw 'Right-click did not open the WinForms context menu.' }
if ($closedMenuWindows -ne 0) { throw 'Escape did not close the WinForms context menu.' }

[pscustomobject]@{
    BaselineWindows = $baseline -join ', '
    OpenedMenuWindows = $openedMenuWindows
    ClosedMenuWindowsAfterEsc = $closedMenuWindows
}
