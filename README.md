# Memory Release Tool

A lightweight Windows floating memory helper built with PowerShell/WPF.

It can:

- show current RAM usage in a small draggable floating window
- trim process working sets
- avoid closing common foreground and user applications
- show network speed and proxy/direct status
- diagnose high nonpaged pool usage
- list likely virtual/TUN/VPN network adapters when kernel memory is abnormal

## Files

- `MemoryCleanerFloat.ps1`: source script
- `内存释放悬浮工具.exe`: packaged Windows executable
- `settings.json`: default runtime settings
- `lightning.ico`: tray/window icon
- `*-preview.png`: UI preview images

## Usage

Double-click `内存释放悬浮工具.exe`.

Right-click the floating window for:

- release now
- kernel memory diagnostics
- settings
- log
- folder
- exit

## Privacy Notes

Runtime files are intentionally excluded from the repository:

- `cleaner.log`
- `cleaner.state.json`
- `*.bak-*`

These may contain local timestamps or machine-specific runtime traces and should not be committed.

## Build

This project can be packaged with `ps2exe`:

```powershell
Invoke-ps2exe -inputFile .\MemoryCleanerFloat.ps1 -outputFile .\内存释放悬浮工具.exe -noConsole -STA -x64 -iconFile .\lightning.ico
```
