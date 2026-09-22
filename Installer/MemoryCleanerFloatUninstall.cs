using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Reflection;

[assembly: AssemblyTitle("MemoryCleanerFloat Uninstall")]
[assembly: AssemblyDescription("内存释放任务栏工具卸载程序")]
[assembly: AssemblyCompany("MemoryCleanerFloat")]
[assembly: AssemblyProduct("内存释放任务栏工具")]
[assembly: AssemblyVersion("3.15.3.0")]
[assembly: AssemblyFileVersion("3.15.3.0")]

internal static class UninstallProgram
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        string installDirectory = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        string marker = Path.Combine(installDirectory, ".memorycleanerfloat-install");
        string app = Path.Combine(installDirectory, "内存释放任务栏工具.exe");
        string disable = Path.Combine(installDirectory, "WindhawkMod", "禁用-Windhawk模块.ps1");
        string windhawkRoot = ResolveWindhawkRoot(marker);

        if (!File.Exists(marker) || !File.Exists(app) || !File.Exists(disable) || IsDriveRoot(installDirectory))
        {
            MessageBox.Show("安装目录验证失败，为保护文件，卸载已经停止。", "无法卸载", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        DialogResult answer = MessageBox.Show(
            "确定卸载内存释放任务栏工具吗？\r\n\r\n将禁用任务栏模块并删除本工具及其设置，但不会删除 Windhawk。",
            "卸载内存释放任务栏工具", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (answer != DialogResult.Yes) return;

        try
        {
            if (File.Exists(Path.Combine(windhawkRoot, "windhawk.exe")))
            {
                ProcessStartInfo disableStart = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + disable + "\" -WindhawkRoot \"" + windhawkRoot + "\"",
                    WorkingDirectory = installDirectory,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                using (Process process = Process.Start(disableStart))
                {
                    if (!process.WaitForExit(60000) || process.ExitCode != 0)
                        throw new InvalidOperationException("无法安全禁用任务栏模块，错误代码 " + (process.HasExited ? process.ExitCode.ToString() : "超时") + "。");
                }
            }

            foreach (Process process in Process.GetProcesses())
            {
                try
                {
                    string executablePath = process.MainModule == null ? "" : process.MainModule.FileName;
                    string fileName = Path.GetFileName(executablePath);
                    bool knownApp = fileName.StartsWith("内存释放任务栏工具", StringComparison.OrdinalIgnoreCase) ||
                                    fileName.StartsWith("MemoryCleanerTaskbar-v", StringComparison.OrdinalIgnoreCase);
                    if (knownApp && string.Equals(Path.GetDirectoryName(executablePath), installDirectory, StringComparison.OrdinalIgnoreCase))
                    {
                        process.Kill();
                        process.WaitForExit(5000);
                    }
                }
                catch { }
                finally { process.Dispose(); }
            }

            Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\MemoryCleanerFloat", false);
            DeleteIfExists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "内存释放任务栏工具.lnk"));
            string startFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "内存释放任务栏工具");
            if (Directory.Exists(startFolder)) Directory.Delete(startFolder, true);

            ProcessStartInfo cleanup = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/d /c ping 127.0.0.1 -n 3 >nul & rmdir /s /q \"" + installDirectory + "\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            Process.Start(cleanup);
            MessageBox.Show("卸载已完成。Windhawk 已保留，不会影响它的其他模块。", "卸载完成", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show("卸载未完成：\r\n\r\n" + ex.Message, "卸载失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static bool IsDriveRoot(string path)
    {
        string root = Path.GetPathRoot(path);
        return string.Equals(path.TrimEnd(Path.DirectorySeparatorChar), root.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);
    }

    private static string ResolveWindhawkRoot(string marker)
    {
        try
        {
            foreach (string line in File.ReadAllLines(marker))
            {
                if (line.StartsWith("WindhawkRoot=", StringComparison.OrdinalIgnoreCase))
                {
                    string root = line.Substring("WindhawkRoot=".Length).Trim();
                    if (File.Exists(Path.Combine(root, "windhawk.exe"))) return root;
                }
            }
        }
        catch { }
        string localRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MemoryCleanerFloat", "Windhawk");
        if (File.Exists(Path.Combine(localRoot, "windhawk.exe"))) return localRoot;
        if (File.Exists(@"D:\Windhawk\windhawk.exe")) return @"D:\Windhawk";
        return localRoot;
    }

    private static void DeleteIfExists(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }
}
