using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace MemoryCleanerTaskbarHost;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        Native.SetProcessDpiAwarenessContext(new IntPtr(-4));
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        var options = HostOptions.Parse(args);
        using var mutex = new Mutex(true, options.MutexName, out var created);
        if (!created) return;
        using var context = new HostContext(options);
        Application.Run(context);
    }
}

internal sealed class HostContext : ApplicationContext
{
    private readonly HostOptions _options;
    private readonly System.Windows.Forms.Timer _timer;
    private TaskbarStrip? _strip;
    private EventWaitHandle? _cleanEvent;
    private EventWaitHandle? _menuEvent;
    private DateTime _lastStateWriteUtc;
    private HostState _state = new();
    private HostState? _lastAppliedState;
    private bool _snapshotWritten;

    internal HostContext(HostOptions options)
    {
        _options = options;
        if (!string.IsNullOrWhiteSpace(options.CleanEventName))
        {
            try { _cleanEvent = EventWaitHandle.OpenExisting(options.CleanEventName); } catch { }
        }
        if (!string.IsNullOrWhiteSpace(options.MenuEventName))
        {
            try { _menuEvent = EventWaitHandle.OpenExisting(options.MenuEventName); } catch { }
        }

        _timer = new System.Windows.Forms.Timer { Interval = 250 };
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
        Tick();
    }

    private void Tick()
    {
        if (_options.ParentProcessId > 0 && !IsProcessAlive(_options.ParentProcessId))
        {
            ExitThread();
            return;
        }

        var taskbar = Native.FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero) return;

        if (_strip is null || _strip.IsDisposed || !Native.IsWindow(_strip.Handle))
        {
            try { _strip?.Dispose(); } catch { }
            _strip = new TaskbarStrip(OnCleanClicked, OnMenuClicked);
        }

        if (Native.GetParent(_strip.Handle) != taskbar)
        {
            if (!_strip.Attach(taskbar)) return;
        }

        ReadStateIfChanged();
        var forceApply = _lastAppliedState is null || !_state.LayoutEquals(_lastAppliedState);
        _strip.Apply(_state, taskbar, forceApply);
        _lastAppliedState = _state.Clone();
        if (!_snapshotWritten && !string.IsNullOrWhiteSpace(_options.SnapshotPath))
        {
            try
            {
                _strip.SaveSnapshot(_options.SnapshotPath);
                _snapshotWritten = true;
            }
            catch { }
        }
    }

    private void ReadStateIfChanged()
    {
        if (string.IsNullOrWhiteSpace(_options.StatePath)) return;
        try
        {
            var info = new FileInfo(_options.StatePath);
            if (!info.Exists || info.LastWriteTimeUtc <= _lastStateWriteUtc) return;
            string json;
            using (var stream = new FileStream(info.FullName, FileMode.Open, FileAccess.Read,
                       FileShare.ReadWrite | FileShare.Delete))
            using (var reader = new StreamReader(stream))
                json = reader.ReadToEnd();
            var next = JsonSerializer.Deserialize<HostState>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            if (next is null) return;
            _state = next;
            _lastStateWriteUtc = info.LastWriteTimeUtc;
        }
        catch
        {
            // The controller replaces the state file atomically. A partially
            // observed replacement is harmless and will be retried next tick.
        }
    }

    private void OnCleanClicked()
    {
        try
        {
            if (_cleanEvent is null && !string.IsNullOrWhiteSpace(_options.CleanEventName))
                _cleanEvent = EventWaitHandle.OpenExisting(_options.CleanEventName);
            _cleanEvent?.Set();
        }
        catch { }
    }

    private void OnMenuClicked()
    {
        try
        {
            if (_menuEvent is null && !string.IsNullOrWhiteSpace(_options.MenuEventName))
                _menuEvent = EventWaitHandle.OpenExisting(_options.MenuEventName);
            _menuEvent?.Set();
        }
        catch { }
    }

    private static bool IsProcessAlive(int processId)
    {
        try { return !Process.GetProcessById(processId).HasExited; }
        catch { return false; }
    }

    protected override void ExitThreadCore()
    {
        _timer.Stop();
        _timer.Dispose();
        try { _strip?.Dispose(); } catch { }
        try { _cleanEvent?.Dispose(); } catch { }
        try { _menuEvent?.Dispose(); } catch { }
        base.ExitThreadCore();
    }
}

internal sealed class TaskbarStrip : UserControl
{
    private const int DefaultWidth = 430;
    private const int DefaultHeight = 52;
    private const float DesignWidth = 430f;
    private const float DesignHeight = 52f;
    private readonly Action _onClean;
    private readonly Action _onMenu;
    private readonly System.Windows.Forms.Timer _pointerTimer;
    private HostState _state = new();
    private bool _hovered;
    private IntPtr _taskbar;
    private bool _leftWasDown;
    private bool _rightWasDown;
    private bool _clickArmed;
    private bool _menuArmed;
    private Rectangle _lastBounds;
    private bool _lastBusy;


    internal TaskbarStrip(Action onClean, Action onMenu)
    {
        _onClean = onClean;
        _onMenu = onMenu;
        SetStyle(ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.UserPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        Size = new Size(DefaultWidth, DefaultHeight);
        _pointerTimer = new System.Windows.Forms.Timer { Interval = 40 };
        _pointerTimer.Tick += (_, _) => PollPointer();
        _pointerTimer.Start();
    }

    internal bool Attach(IntPtr taskbar)
    {
        _taskbar = taskbar;
        Native.ShowWindow(Handle, Native.SwHide);
        Native.SetLastError(0);
        Native.SetParent(Handle, taskbar);
        if (Native.GetParent(Handle) != taskbar)
        {
            Native.ShowWindow(Handle, Native.SwHide);
            return false;
        }
        Native.SetWindowLong(Handle, Native.GwlStyle, Native.WsChild | Native.WsVisible);
        Native.TrySetWindowLongPtr(Handle, Native.GwlExStyle,
            Native.WsExControlParent | Native.WsExLayered | Native.WsExComposited |
            Native.WsExTransparent | Native.WsExToolWindow | Native.WsExNoActivate);
        Native.SetLayeredWindowAttributes(Handle, 0, 255, Native.LwaColorKey | Native.LwaAlpha);
        Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0,
            Native.SwpNoActivate | Native.SwpNoMove | Native.SwpNoSize | Native.SwpFrameChanged);
        Native.ShowWindow(Handle, Native.SwShowNoActivate);
        return true;
    }

    internal void Apply(HostState state, IntPtr taskbar, bool forceBounds = false)
    {
        _state = state;
        if (_lastBusy != state.Busy)
        {
            _lastBusy = state.Busy;
            Cursor = state.Busy ? Cursors.WaitCursor : Cursors.Hand;
            if (state.Busy)
            {
                _clickArmed = false;
                _leftWasDown = false;
            }
        }
        if (!state.Visible)
        {
            Native.ShowWindow(Handle, Native.SwHide);
            return;
        }

        var bounds = ResolveBounds(state, taskbar);
        if (forceBounds || bounds != _lastBounds || !Visible)
        {
            Native.SetWindowPos(Handle, IntPtr.Zero, bounds.X, bounds.Y, bounds.Width, bounds.Height,
                Native.SwpNoActivate | Native.SwpShowWindow);
            _lastBounds = bounds;
        }
        Invalidate();
    }

    private void PollPointer()
    {
        if (!Native.GetCursorPos(out var point)) return;
        RECT rect;
        if (_taskbar != IntPtr.Zero && Native.GetWindowRect(_taskbar, out var taskbarRect))
        {
            rect = new RECT
            {
                Left = taskbarRect.Left + _lastBounds.Left,
                Top = taskbarRect.Top + _lastBounds.Top,
                Right = taskbarRect.Left + _lastBounds.Right,
                Bottom = taskbarRect.Top + _lastBounds.Bottom
            };
        }
        else if (!Native.GetWindowRect(Handle, out rect))
        {
            return;
        }
        var inside = point.X >= rect.Left && point.X < rect.Right && point.Y >= rect.Top && point.Y < rect.Bottom;
        if (inside != _hovered)
        {
            _hovered = inside;
            Invalidate();
        }

        var leftDown = (Native.GetAsyncKeyState(0x01) & 0x8000) != 0;
        if (_state.Busy)
        {
            _clickArmed = false;
            _leftWasDown = leftDown;
        }
        else
        {
            if (leftDown && !_leftWasDown) _clickArmed = inside;
            if (!leftDown && _leftWasDown)
            {
                if (_clickArmed && inside) _onClean();
                _clickArmed = false;
            }
            _leftWasDown = leftDown;
        }

        var rightDown = (Native.GetAsyncKeyState(0x02) & 0x8000) != 0;
        if (rightDown && !_rightWasDown) _menuArmed = inside;
        if (!rightDown && _rightWasDown)
        {
            if (_menuArmed && inside) _onMenu();
            _menuArmed = false;
        }
        _rightWasDown = rightDown;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _pointerTimer.Stop();
            _pointerTimer.Dispose();
        }
        base.Dispose(disposing);
    }

    private static Rectangle ResolveBounds(HostState state, IntPtr taskbar)
    {
        Native.GetWindowRect(taskbar, out var taskbarRect);
        var taskbarWidth = Math.Max(1, taskbarRect.Right - taskbarRect.Left);
        var taskbarHeight = Math.Max(1, taskbarRect.Bottom - taskbarRect.Top);
        var dpiScale = Math.Max(1.0, Native.GetDpiForWindow(taskbar) / 96.0);
        // State bounds come from taskbar UI Automation and are already physical
        // pixels. Scaling them again shifts both the child and its click target
        // on 125%/150% displays. Only scale the built-in fallback dimensions.
        var requestedWidth = state.Width > 0 ? state.Width : (int)Math.Round(DefaultWidth * dpiScale);
        var requestedHeight = state.Height > 0 ? state.Height : (int)Math.Round(DefaultHeight * dpiScale);
        var requestedTop = state.Top;
        var requestedLeft = state.Left;
        var width = Math.Clamp(requestedWidth, 330, Math.Max(330, taskbarWidth - 16));
        var height = Math.Clamp(requestedHeight, 32, taskbarHeight);
        var y = requestedTop >= 0 ? requestedTop : Math.Max(0, (taskbarHeight - height) / 2);
        int x;

        if (requestedLeft >= 0)
        {
            x = requestedLeft;
        }
        else if (string.Equals(state.Position, "right", StringComparison.OrdinalIgnoreCase))
        {
            var tray = Native.FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);
            if (tray != IntPtr.Zero && Native.GetWindowRect(tray, out var trayRect))
                x = trayRect.Left - taskbarRect.Left - width - 8;
            else
                x = taskbarWidth - width - 190;
        }
        else
        {
            x = 8;
        }

        x = Math.Clamp(x, 0, Math.Max(0, taskbarWidth - width));
        y = Math.Clamp(y, 0, Math.Max(0, taskbarHeight - height));
        return new Rectangle(x, y, width, height);
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.Clear(Color.Black); // black is the layered-window color key
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        var sx = Width / DesignWidth;
        var sy = Height / DesignHeight;
        var inset = Math.Max(1f, 1.25f * Math.Min(sx, sy));
        var card = new RectangleF(inset, inset, Math.Max(1, Width - inset * 2), Math.Max(1, Height - inset * 2));
        using var path = RoundedRectangle(card, Math.Max(1f, card.Height / 2f));
        var fill = _hovered ? Color.FromArgb(255, 43, 43, 47) : Color.FromArgb(255, 29, 29, 32);
        using (var brush = new SolidBrush(fill)) g.FillPath(brush, path);
        using (var pen = new Pen(_hovered ? Color.FromArgb(150, 90, 200, 250) : Color.FromArgb(108, 128, 128, 136), Math.Max(1f, sy)))
            g.DrawPath(pen, path);

        if (!string.IsNullOrWhiteSpace(_state.Message))
        {
            DrawMessage(g, _state.Message);
            return;
        }

        DrawStatus(g);
    }

    internal void SaveSnapshot(string path)
    {
        using var bitmap = new Bitmap(Math.Max(1, Width), Math.Max(1, Height));
        DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }


    private void DrawMessage(Graphics g, string message)
    {
        using var dot = new SolidBrush(Color.FromArgb(255, 10, 132, 255));
        g.FillEllipse(dot, 18, Height / 2f - 4, 8, 8);
        using var font = new Font("Microsoft YaHei UI", 12.5f, FontStyle.Bold, GraphicsUnit.Pixel);
        using var text = new SolidBrush(Color.FromArgb(255, 245, 245, 247));
        var rect = new RectangleF(34, 0, Width - 48, Height);
        using var format = CenterFormat(StringAlignment.Near);
        g.DrawString(message, font, text, rect, format);
    }

    private void DrawStatus(Graphics g)
    {
        var showLocation = _state.ShowLocation;
        var showSpeed = _state.ShowSpeed;
        var sx = Width / DesignWidth;
        var sy = Height / DesignHeight;
        var compact = Width < 350;
        var iconWidth = (compact ? 46f : 55f) * sx;
        var contentLeft = iconWidth;
        var contentRight = Width - 5f * sx;
        var contentWidth = Math.Max(1f, contentRight - contentLeft);
        var weights = new List<float> { 79f };
        if (showLocation) weights.Add(94f);
        if (showSpeed) { weights.Add(98f); weights.Add(98f); }
        var totalWeight = weights.Sum();
        var x = contentLeft;
        var section = 0;

        DrawLightningButton(g, new RectangleF(7f * sx, 7f * sy, 38f * sy, 38f * sy));

        var ramWidth = contentWidth * weights[section++] / totalWeight;
        DrawRam(g, new RectangleF(x, 0, ramWidth, Height), sy);
        x += ramWidth;
        if (showLocation)
        {
            DrawDivider(g, x, sy);
            var locationWidth = contentWidth * weights[section++] / totalWeight;
            DrawLocation(g, new RectangleF(x, 0, locationWidth, Height), sy);
            x += locationWidth;
        }
        if (showSpeed)
        {
            DrawDivider(g, x, sy);
            var downWidth = contentWidth * weights[section++] / totalWeight;
            DrawMetric(g, new RectangleF(x, 0, downWidth, Height), "下载", _state.Download, Color.FromArgb(255, 100, 210, 255), sy);
            x += downWidth;
            DrawDivider(g, x, sy);
            var upWidth = contentWidth * weights[section] / totalWeight;
            DrawMetric(g, new RectangleF(x, 0, upWidth, Height), "上传", _state.Upload, Color.FromArgb(255, 48, 209, 88), sy);
        }
    }

    private static void DrawLightningButton(Graphics g, RectangleF rect)
    {
        using var circle = new LinearGradientBrush(rect,
            Color.FromArgb(255, 94, 204, 255), Color.FromArgb(255, 10, 132, 255), 130f);
        g.FillEllipse(circle, rect);
        using (var rim = new Pen(Color.FromArgb(120, 170, 231, 255), 1f))
            g.DrawEllipse(rim, rect);

        var x = rect.X;
        var y = rect.Y;
        var w = rect.Width;
        var h = rect.Height;
        var bolt = new[]
        {
            new PointF(x + w * .56f, y + h * .16f),
            new PointF(x + w * .29f, y + h * .53f),
            new PointF(x + w * .47f, y + h * .53f),
            new PointF(x + w * .39f, y + h * .84f),
            new PointF(x + w * .70f, y + h * .42f),
            new PointF(x + w * .52f, y + h * .42f)
        };
        using var boltBrush = new SolidBrush(Color.White);
        g.FillPolygon(boltBrush, bolt);
    }

    private void DrawRam(Graphics g, RectangleF rect, float scale)
    {
        using var percentFont = new Font("Segoe UI Variable Display", Math.Max(13f, 18.5f * scale), FontStyle.Bold, GraphicsUnit.Pixel);
        using var labelFont = new Font("Segoe UI", Math.Max(8f, 9.8f * scale), FontStyle.Regular, GraphicsUnit.Pixel);
        using var primary = new SolidBrush(Color.FromArgb(255, 245, 245, 247));
        using var secondary = new SolidBrush(Color.FromArgb(215, 225, 225, 232));
        using var format = CenterFormat();
        var percent = Math.Clamp(_state.MemoryPercent, 0, 100) + "%";
        g.DrawString(percent, percentFont, primary, new RectangleF(rect.X, 3f * scale, rect.Width, 27f * scale), format);
        g.DrawString("RAM", labelFont, secondary, new RectangleF(rect.X, 28f * scale, rect.Width, 17f * scale), format);
    }

    private void DrawLocation(Graphics g, RectangleF rect, float scale)
    {
        using var valueFont = new Font("Microsoft YaHei UI", Math.Max(11f, 14f * scale), FontStyle.Bold, GraphicsUnit.Pixel);
        using var labelFont = new Font("Microsoft YaHei UI", Math.Max(8f, 9.8f * scale), FontStyle.Regular, GraphicsUnit.Pixel);
        using var primary = new SolidBrush(Color.FromArgb(255, 245, 245, 247));
        using var secondary = new SolidBrush(Color.FromArgb(215, 225, 225, 232));
        using var format = CenterFormat();
        g.DrawString(string.IsNullOrWhiteSpace(_state.Location) ? "--" : _state.Location, valueFont, primary, new RectangleF(rect.X + 3, 3f * scale, rect.Width - 6, 27f * scale), format);
        g.DrawString(string.IsNullOrWhiteSpace(_state.NetworkMode) ? "网络" : _state.NetworkMode, labelFont, secondary, new RectangleF(rect.X + 3, 28f * scale, rect.Width - 6, 17f * scale), format);
    }

    private void DrawMetric(Graphics g, RectangleF rect, string label, string value, Color accent, float scale)
    {
        using var valueFont = new Font("Segoe UI Variable Text", Math.Max(10f, 13f * scale), FontStyle.Bold, GraphicsUnit.Pixel);
        using var labelFont = new Font("Microsoft YaHei UI", Math.Max(8f, 9.8f * scale), FontStyle.Regular, GraphicsUnit.Pixel);
        using var accentBrush = new SolidBrush(accent);
        using var secondary = new SolidBrush(Color.FromArgb(215, 225, 225, 232));
        using var format = CenterFormat();
        g.DrawString(value, valueFont, accentBrush, new RectangleF(rect.X + 2, 3f * scale, rect.Width - 4, 27f * scale), format);
        g.DrawString(label, labelFont, secondary, new RectangleF(rect.X + 2, 28f * scale, rect.Width - 4, 17f * scale), format);
    }

    private void DrawDivider(Graphics g, float x, float scale)
    {
        using var pen = new Pen(Color.FromArgb(92, 210, 210, 218), Math.Max(1f, scale));
        g.DrawLine(pen, x, 11f * scale, x, Height - 11f * scale);
    }

    private static StringFormat CenterFormat(StringAlignment alignment = StringAlignment.Center) => new()
    {
        Alignment = alignment,
        LineAlignment = StringAlignment.Center,
        Trimming = StringTrimming.EllipsisCharacter,
        FormatFlags = StringFormatFlags.NoWrap
    };

    private static GraphicsPath RoundedRectangle(RectangleF rect, float radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(rect.X, rect.Y, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Y, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.X, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}

internal sealed class HostState
{
    public int MemoryPercent { get; set; }
    public string Location { get; set; } = "--";
    public string NetworkMode { get; set; } = "网络";
    public string Download { get; set; } = "0 B/s";
    public string Upload { get; set; } = "0 B/s";
    public string Message { get; set; } = "";
    public string Position { get; set; } = "left";
    public int Left { get; set; } = -1;
    public int Top { get; set; } = -1;
    public int Width { get; set; } = 430;
    public int Height { get; set; } = 52;
    public bool ShowLocation { get; set; } = true;
    public bool ShowSpeed { get; set; } = true;
    public bool Busy { get; set; }
    public bool Visible { get; set; } = true;

    internal bool LayoutEquals(HostState other) =>
        Position == other.Position && Left == other.Left && Top == other.Top &&
        Width == other.Width && Height == other.Height && Visible == other.Visible;

    internal HostState Clone() => (HostState)MemberwiseClone();
}

internal sealed class HostOptions
{
    public string StatePath { get; private set; } = "";
    public string CleanEventName { get; private set; } = "";
    public string MenuEventName { get; private set; } = "";
    public string MutexName { get; private set; } = "Local\\MemoryCleanerTaskbarHost";
    public int ParentProcessId { get; private set; }
    public string SnapshotPath { get; private set; } = "";

    internal static HostOptions Parse(string[] args)
    {
        var result = new HostOptions();
        for (var i = 0; i < args.Length; i++)
        {
            var value = i + 1 < args.Length ? args[i + 1] : "";
            switch (args[i].ToLowerInvariant())
            {
                case "--state": result.StatePath = value; i++; break;
                case "--clean-event": result.CleanEventName = value; i++; break;
                case "--menu-event": result.MenuEventName = value; i++; break;
                case "--parent-pid": int.TryParse(value, out var pid); result.ParentProcessId = pid; i++; break;
                case "--instance": result.MutexName = "Local\\MemoryCleanerTaskbarHost_" + value; i++; break;
                case "--snapshot": result.SnapshotPath = value; i++; break;
            }
        }
        return result;
    }
}

[StructLayout(LayoutKind.Sequential)]
internal struct RECT { public int Left, Top, Right, Bottom; }

internal static class Native
{
    internal const int GwlStyle = -16;
    internal const int GwlExStyle = -20;
    internal const int WsChild = 0x40000000;
    internal const int WsVisible = 0x10000000;
    internal const int WsExControlParent = 0x00010000;
    internal const int WsExLayered = 0x00080000;
    internal const int WsExComposited = 0x02000000;
    internal const int WsExTransparent = 0x00000020;
    internal const int WsExToolWindow = 0x00000080;
    internal const int WsExNoActivate = 0x08000000;
    internal const uint LwaColorKey = 0x1;
    internal const uint LwaAlpha = 0x2;
    internal const int SwHide = 0;
    internal const int SwShowNoActivate = 8;
    internal const uint SwpNoActivate = 0x0010;
    internal const uint SwpNoSize = 0x0001;
    internal const uint SwpNoMove = 0x0002;
    internal const uint SwpFrameChanged = 0x0020;
    internal const uint SwpShowWindow = 0x0040;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr FindWindow(string className, string? title);
    [DllImport("user32.dll")] internal static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string? title);
    [DllImport("user32.dll")] internal static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] internal static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] internal static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)] internal static extern int SetWindowLong(IntPtr window, int index, int value);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)] internal static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] private static extern IntPtr SetWindowLongPtr64(IntPtr window, int index, IntPtr value);
    [DllImport("user32.dll")] internal static extern bool SetLayeredWindowAttributes(IntPtr window, uint colorKey, byte alpha, uint flags);
    [DllImport("user32.dll")] internal static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] internal static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] internal static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int virtualKey);
    [DllImport("kernel32.dll")] internal static extern void SetLastError(uint errorCode);

    internal static void TrySetWindowLongPtr(IntPtr window, int index, int value)
    {
        try
        {
            if (IntPtr.Size == 8) SetWindowLongPtr64(window, index, new IntPtr(value));
            else SetWindowLong(window, index, value);
        }
        catch
        {
            // Basic embedded child rendering remains available if an older
            // taskbar implementation rejects the Windows 11 composition flags.
        }
    }
}

[StructLayout(LayoutKind.Sequential)]
internal struct POINT { public int X, Y; }
