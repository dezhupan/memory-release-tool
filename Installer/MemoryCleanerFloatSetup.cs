using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("MemoryCleanerFloat Setup")]
[assembly: AssemblyDescription("内存释放任务栏工具图形安装程序")]
[assembly: AssemblyCompany("MemoryCleanerFloat")]
[assembly: AssemblyProduct("内存释放任务栏工具")]
[assembly: AssemblyCopyright("Copyright © 2026")]
[assembly: AssemblyVersion("3.15.3.0")]
[assembly: AssemblyFileVersion("3.15.3.0")]

internal sealed class SetupForm : Form
{
    private readonly TextBox installPath;
    private readonly Button browseButton;
    private readonly Button installButton;
    private readonly Button cancelButton;
    private readonly CheckBox desktopShortcut;
    private readonly ProgressBar progress;
    private readonly Label status;
    private bool installing;

    public SetupForm()
    {
        Text = "内存释放任务栏工具 v3.15.3 安装程序";
        ClientSize = new Size(650, 430);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        Font = new Font("Microsoft YaHei UI", 9F);

        Panel header = new Panel { Dock = DockStyle.Top, Height = 112, BackColor = Color.FromArgb(31, 34, 41) };
        Controls.Add(header);

        Label icon = new Label
        {
            Text = "⚡",
            ForeColor = Color.FromArgb(56, 174, 255),
            Font = new Font("Segoe UI Symbol", 30F, FontStyle.Bold),
            Location = new Point(27, 22),
            AutoSize = true
        };
        header.Controls.Add(icon);

        Label title = new Label
        {
            Text = "内存释放任务栏工具",
            ForeColor = Color.White,
            Font = new Font("Microsoft YaHei UI", 18F, FontStyle.Bold),
            Location = new Point(92, 23),
            AutoSize = true
        };
        header.Controls.Add(title);

        Label subtitle = new Label
        {
            Text = "真正嵌入 Windows 11 任务栏 · 离线整合安装",
            ForeColor = Color.FromArgb(190, 196, 207),
            Font = new Font("Microsoft YaHei UI", 9.5F),
            Location = new Point(96, 65),
            AutoSize = true
        };
        header.Controls.Add(subtitle);

        Label intro = new Label
        {
            Text = "安装程序将部署内存工具，并自动复用或安装 Windhawk Portable。",
            Location = new Point(32, 138),
            Size = new Size(580, 24)
        };
        Controls.Add(intro);

        Label pathLabel = new Label { Text = "安装位置", Location = new Point(32, 184), AutoSize = true };
        Controls.Add(pathLabel);

        installPath = new TextBox
        {
            Location = new Point(32, 210),
            Size = new Size(482, 27),
            Text = Directory.Exists("D:\\") ? "D:\\MemoryCleanerFloat" : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "MemoryCleanerFloat")
        };
        Controls.Add(installPath);

        browseButton = new Button { Text = "浏览...", Location = new Point(524, 208), Size = new Size(92, 31) };
        browseButton.Click += BrowseButton_Click;
        Controls.Add(browseButton);

        desktopShortcut = new CheckBox
        {
            Text = "创建桌面快捷方式",
            Checked = true,
            Location = new Point(32, 254),
            AutoSize = true
        };
        Controls.Add(desktopShortcut);

        Label note = new Label
        {
            Text = "Windhawk 官方离线安装器已包含在本安装包中；首次加载任务栏模块仍可能需要联网解析系统符号。",
            ForeColor = Color.FromArgb(90, 94, 102),
            Location = new Point(32, 286),
            Size = new Size(584, 42)
        };
        Controls.Add(note);

        progress = new ProgressBar
        {
            Location = new Point(32, 334),
            Size = new Size(584, 10),
            Style = ProgressBarStyle.Blocks
        };
        Controls.Add(progress);

        status = new Label
        {
            Text = "准备安装",
            ForeColor = Color.FromArgb(70, 76, 86),
            Location = new Point(32, 352),
            Size = new Size(370, 30)
        };
        Controls.Add(status);

        installButton = new Button
        {
            Text = "立即安装",
            Location = new Point(414, 376),
            Size = new Size(98, 34),
            BackColor = Color.FromArgb(38, 143, 255),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat
        };
        installButton.FlatAppearance.BorderSize = 0;
        installButton.Click += InstallButton_Click;
        Controls.Add(installButton);

        cancelButton = new Button { Text = "取消", Location = new Point(520, 376), Size = new Size(96, 34) };
        cancelButton.Click += delegate { Close(); };
        Controls.Add(cancelButton);

        AcceptButton = installButton;
        CancelButton = cancelButton;
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (installing)
        {
            e.Cancel = true;
            MessageBox.Show(this, "安装正在进行，请等待完成。", "内存释放任务栏工具", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        base.OnFormClosing(e);
    }

    private void BrowseButton_Click(object sender, EventArgs e)
    {
        using (FolderBrowserDialog dialog = new FolderBrowserDialog())
        {
            dialog.Description = "选择内存释放任务栏工具的安装位置";
            dialog.SelectedPath = installPath.Text;
            if (dialog.ShowDialog(this) == DialogResult.OK)
            {
                installPath.Text = Path.Combine(dialog.SelectedPath, "MemoryCleanerFloat");
            }
        }
    }

    private async void InstallButton_Click(object sender, EventArgs e)
    {
        string destination;
        try
        {
            destination = ValidateDestination(installPath.Text);
            ValidateSystem();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "无法安装", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        if (Directory.Exists(destination) && Directory.GetFileSystemEntries(destination).Length > 0 &&
            !File.Exists(Path.Combine(destination, ".memorycleanerfloat-install")))
        {
            DialogResult answer = MessageBox.Show(this,
                "所选目录不是空目录。继续安装只会覆盖本工具同名文件，不会清空其他内容。是否继续？",
                "确认安装位置", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (answer != DialogResult.Yes) return;
        }

        installing = true;
        installButton.Enabled = false;
        browseButton.Enabled = false;
        installPath.Enabled = false;
        desktopShortcut.Enabled = false;
        cancelButton.Enabled = false;
        progress.Style = ProgressBarStyle.Marquee;
        progress.MarqueeAnimationSpeed = 24;
        bool createDesktop = desktopShortcut.Checked;

        try
        {
            await Task.Run(delegate { InstallProduct(destination, createDesktop); });
            SetStatus("安装完成，任务栏模块已启动。", Color.FromArgb(22, 135, 70));
            progress.Style = ProgressBarStyle.Continuous;
            progress.Value = 100;
            installButton.Text = "完成";
            installButton.Enabled = true;
            installButton.Click -= InstallButton_Click;
            installButton.Click += delegate { Close(); };
            cancelButton.Visible = false;
            installing = false;
            MessageBox.Show(this, "安装完成。内存信息模块已启动；首次解析系统符号时，任务栏显示可能需要稍等几分钟。", "安装成功", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            installing = false;
            SetStatus("安装失败：" + ex.Message, Color.FromArgb(205, 48, 48));
            progress.Style = ProgressBarStyle.Continuous;
            progress.Value = 0;
            installButton.Enabled = true;
            browseButton.Enabled = true;
            installPath.Enabled = true;
            desktopShortcut.Enabled = true;
            cancelButton.Enabled = true;
            MessageBox.Show(this,
                "安装没有完成：\r\n\r\n" + ex.Message + "\r\n\r\n如果已经生成 TaskbarDiagnostic.txt，请把它发给工具提供者。",
                "安装失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static void ValidateSystem()
    {
        if (!Environment.Is64BitOperatingSystem) throw new InvalidOperationException("仅支持 Windows 11 x64。 ");
        string architecture = Environment.GetEnvironmentVariable("PROCESSOR_ARCHITEW6432") ?? Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE") ?? "";
        if (architecture.IndexOf("ARM64", StringComparison.OrdinalIgnoreCase) >= 0) throw new InvalidOperationException("当前安装包不支持 Windows on ARM。");
        int build = 0;
        using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
        {
            int.TryParse(Convert.ToString(key == null ? null : key.GetValue("CurrentBuildNumber")), out build);
        }
        if (build < 22000) throw new InvalidOperationException("真正嵌入任务栏需要 Windows 11。");
    }

    private static string ValidateDestination(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("请选择安装位置。");
        string full = Path.GetFullPath(Environment.ExpandEnvironmentVariables(value.Trim()));
        string root = Path.GetPathRoot(full);
        if (string.Equals(full.TrimEnd(Path.DirectorySeparatorChar), root.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("不能直接安装到磁盘根目录。");
        return full;
    }

    private void InstallProduct(string destination, bool createDesktop)
    {
        SetStatus("正在解压安装文件...", Color.FromArgb(70, 76, 86));
        Directory.CreateDirectory(destination);
        StopInstalledApps(destination);
        ExtractPayload(destination);
        string windhawkRoot = ResolveWindhawkRoot(destination);
        WriteInstallMarker(destination, windhawkRoot);

        SetStatus("正在复用或离线安装 Windhawk Portable...", Color.FromArgb(70, 76, 86));
        int exitCode = RunPowerShell(destination, windhawkRoot);
        if (exitCode != 0) throw new InvalidOperationException("任务栏模块安装返回错误代码 " + exitCode + "。");

        RegisterUninstaller(destination);
        CreateShortcuts(destination, createDesktop);
    }

    private static void ExtractPayload(string destination)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream resource = assembly.GetManifestResourceStream("MemoryCleanerFloat.Payload.zip"))
        {
            if (resource == null) throw new InvalidOperationException("安装数据损坏：缺少 Payload.zip。");
            using (ZipArchive archive = new ZipArchive(resource, ZipArchiveMode.Read, false))
            {
                string safeRoot = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string target = Path.GetFullPath(Path.Combine(destination, relative));
                    if (!target.StartsWith(safeRoot, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("安装数据包含不安全路径。");
                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(target);
                        continue;
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    if (string.Equals(relative, "settings.json", StringComparison.OrdinalIgnoreCase) && File.Exists(target)) continue;
                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        input.CopyTo(output);
                    }
                }
            }
        }
    }

    private int RunPowerShell(string destination, string windhawkRoot)
    {
        string script = Path.Combine(destination, "Install-And-Run.ps1");
        ProcessStartInfo start = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -WindhawkRoot \"" + windhawkRoot + "\" -AllowPendingEmbedding",
            WorkingDirectory = destination,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        using (Process process = new Process { StartInfo = start })
        {
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args) { if (!string.IsNullOrWhiteSpace(args.Data)) MapStatus(args.Data); };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args) { if (!string.IsNullOrWhiteSpace(args.Data)) SetStatus(args.Data, Color.FromArgb(205, 48, 48)); };
            if (!process.Start()) throw new InvalidOperationException("无法启动安装流程。");
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static void WriteInstallMarker(string destination, string windhawkRoot)
    {
        string content = "MemoryCleanerFloat v3.15.3\r\nWindhawkRoot=" + windhawkRoot + "\r\n";
        File.WriteAllText(Path.Combine(destination, ".memorycleanerfloat-install"), content, new UTF8Encoding(false));
    }

    private static bool IsPortableWindhawk(string root)
    {
        if (string.IsNullOrWhiteSpace(root)) return false;
        try
        {
            string exe = Path.Combine(root, "windhawk.exe");
            string ini = Path.Combine(root, "windhawk.ini");
            return File.Exists(exe) && File.Exists(ini) &&
                   File.ReadAllText(ini).IndexOf("Portable=1", StringComparison.OrdinalIgnoreCase) >= 0;
        }
        catch { return false; }
    }

    private static string ResolveWindhawkRoot(string destination)
    {
        foreach (Process process in Process.GetProcessesByName("windhawk"))
        {
            try
            {
                string executable = process.MainModule == null ? "" : process.MainModule.FileName;
                string root = string.IsNullOrWhiteSpace(executable) ? "" : Path.GetDirectoryName(executable);
                if (IsPortableWindhawk(root)) return Path.GetFullPath(root);
            }
            catch { }
            finally { process.Dispose(); }
        }

        string localRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MemoryCleanerFloat", "Windhawk");
        string[] candidates = new string[]
        {
            localRoot,
            @"D:\Windhawk",
            Path.Combine(destination, "Windhawk"),
            Path.Combine(Path.GetDirectoryName(destination) ?? destination, "Windhawk"),
            @"C:\Windhawk"
        };
        foreach (string candidate in candidates)
        {
            if (IsPortableWindhawk(candidate)) return Path.GetFullPath(candidate);
        }
        return Path.GetFullPath(localRoot);
    }

    private void MapStatus(string line)
    {
        string text = line;
        if (line.IndexOf("Installing official Windhawk", StringComparison.OrdinalIgnoreCase) >= 0) text = "正在安装 Windhawk Portable...";
        else if (line.IndexOf("Portable installation verified", StringComparison.OrdinalIgnoreCase) >= 0) text = "Windhawk 安装完成，正在部署任务栏模块...";
        else if (line.IndexOf("Installing the Windhawk taskbar module", StringComparison.OrdinalIgnoreCase) >= 0) text = "正在安装任务栏嵌入模块...";
        else if (line.IndexOf("Starting MemoryCleanerFloat", StringComparison.OrdinalIgnoreCase) >= 0) text = "正在启动内存释放工具...";
        else if (line.IndexOf("Waiting for Windhawk", StringComparison.OrdinalIgnoreCase) >= 0) text = "正在等待任务栏完成嵌入，首次运行可能需要几分钟...";
        else if (line.IndexOf("Pending:", StringComparison.OrdinalIgnoreCase) >= 0) text = "安装已完成，任务栏模块仍在进行首次加载。";
        else if (line.IndexOf("Success:", StringComparison.OrdinalIgnoreCase) >= 0) text = "任务栏嵌入已经确认。";
        SetStatus(text, Color.FromArgb(70, 76, 86));
    }

    private void SetStatus(string text, Color color)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action<string, Color>(SetStatus), text, color);
            return;
        }
        status.Text = text;
        status.ForeColor = color;
    }

    private static void RegisterUninstaller(string destination)
    {
        string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\MemoryCleanerFloat";
        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(keyPath))
        {
            key.SetValue("DisplayName", "内存释放任务栏工具");
            key.SetValue("DisplayVersion", "3.15.3");
            key.SetValue("Publisher", "MemoryCleanerFloat");
            key.SetValue("InstallLocation", destination);
            key.SetValue("DisplayIcon", Path.Combine(destination, "内存释放任务栏工具.exe"));
            key.SetValue("UninstallString", "\"" + Path.Combine(destination, "Uninstall.exe") + "\"");
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }
    }

    private static void CreateShortcuts(string destination, bool createDesktop)
    {
        string app = Path.Combine(destination, "内存释放任务栏工具.exe");
        string uninstall = Path.Combine(destination, "Uninstall.exe");
        string startFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "内存释放任务栏工具");
        Directory.CreateDirectory(startFolder);
        CreateShortcut(Path.Combine(startFolder, "内存释放任务栏工具.lnk"), app, destination, "内存释放任务栏工具");
        CreateShortcut(Path.Combine(startFolder, "卸载内存释放任务栏工具.lnk"), uninstall, destination, "卸载内存释放任务栏工具");
        if (createDesktop)
        {
            CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "内存释放任务栏工具.lnk"), app, destination, "内存释放任务栏工具");
        }
    }

    private static void CreateShortcut(string shortcutPath, string targetPath, string workingDirectory, string description)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        dynamic shell = Activator.CreateInstance(shellType);
        dynamic shortcut = shell.CreateShortcut(shortcutPath);
        shortcut.TargetPath = targetPath;
        shortcut.WorkingDirectory = workingDirectory;
        shortcut.Description = description;
        shortcut.IconLocation = targetPath + ",0";
        shortcut.Save();
    }

    private static void StopInstalledApps(string destination)
    {
        string normalizedDestination = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        foreach (Process process in Process.GetProcesses())
        {
            try
            {
                string executablePath = process.MainModule == null ? "" : process.MainModule.FileName;
                if (string.IsNullOrWhiteSpace(executablePath)) continue;
                string fullPath = Path.GetFullPath(executablePath);
                string fileName = Path.GetFileName(fullPath);
                bool knownApp = fileName.StartsWith("内存释放任务栏工具", StringComparison.OrdinalIgnoreCase) ||
                                fileName.StartsWith("MemoryCleanerTaskbar-v", StringComparison.OrdinalIgnoreCase);
                if (knownApp && fullPath.StartsWith(normalizedDestination, StringComparison.OrdinalIgnoreCase))
                {
                    process.Kill();
                    process.WaitForExit(5000);
                }
            }
            catch { }
            finally { process.Dispose(); }
        }
    }
}

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SetupForm());
    }
}
