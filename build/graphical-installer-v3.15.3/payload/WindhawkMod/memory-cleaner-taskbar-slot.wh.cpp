// ==WindhawkMod==
// @id              memory-cleaner-taskbar-slot
// @name            Memory Cleaner Taskbar Slot
// @name:zh-CN      内存清理任务栏真占位
// @description     Adds a real XAML layout slot for Memory Cleaner in the Windows 11 taskbar.
// @description:zh-CN 在 Windows 11 任务栏中为内存清理工具创建参与原生布局的真实槽位。
// @version         1.6.2
// @author          MemoryCleanerFloat
// @include         explorer.exe
// @architecture    x86-64
// @compilerOptions -lole32 -loleaut32 -lruntimeobject
// ==/WindhawkMod==

// ==WindhawkModReadme==
/*
# 内存清理任务栏真占位

本模块只负责 Windows 11 任务栏中的原生 XAML 槽位、显示状态和点击转发。
真正的内存清理仍由“内存释放任务栏工具”独立进程执行。

- 左键：释放内存。
- 按住左键横向拖动：在任务栏布局内移动并保存位置。
- 右键：打开工具菜单。
- 清理时明确显示“正在清理内存…”。
- 控制程序退出、状态失效或模块禁用时，自动移除槽位并恢复托盘布局。
*/
// ==/WindhawkModReadme==

// ==WindhawkModSettings==
/*
- showOnAllTaskbars: false
  $name: 在所有任务栏显示
  $description: 关闭时只在主任务栏显示。
*/
// ==/WindhawkModSettings==

#include <windhawk_utils.h>

#undef GetCurrentTime

#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Core.h>
#include <winrt/Windows.UI.Input.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Windows.UI.Xaml.h>
#include <winrt/Windows.UI.Xaml.Automation.Peers.h>
#include <winrt/Windows.UI.Xaml.Controls.h>
#include <winrt/Windows.UI.Xaml.Controls.Primitives.h>
#include <winrt/Windows.UI.Xaml.Input.h>
#include <winrt/Windows.UI.Xaml.Markup.h>
#include <winrt/Windows.UI.Xaml.Media.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

using namespace winrt::Windows::Data::Json;
using namespace winrt::Windows::UI::Xaml;
using namespace winrt::Windows::UI::Xaml::Controls;
using namespace winrt::Windows::UI::Xaml::Media;

namespace wuxi = winrt::Windows::UI::Xaml::Input;
namespace wuxcp = winrt::Windows::UI::Xaml::Controls::Primitives;
namespace wuxap = winrt::Windows::UI::Xaml::Automation::Peers;
namespace wuxm = winrt::Windows::UI::Xaml::Markup;

namespace {

constexpr wchar_t kRootName[] = L"MemoryCleanerTaskbarSlotRoot";
constexpr wchar_t kCleanEventName[] = L"Local\\MemoryCleanerFloat_TaskbarClean";
constexpr wchar_t kMenuEventName[] = L"Local\\MemoryCleanerFloat_TaskbarMenu";
constexpr wchar_t kPositionEventName[] =
    L"Local\\MemoryCleanerFloat_TaskbarPositionChanged";
constexpr wchar_t kEjectEventName[] =
    L"Local\\MemoryCleanerFloat_TaskbarEject";
constexpr ULONGLONG kStateMaxAgeMs = 15000;
constexpr double kDragThreshold = 6.0;
constexpr double kSlotWidth = 360.0;
constexpr double kReservedTaskbarWidth = 360.0;
constexpr double kAbsoluteMaximumOffset = 1600.0;
constexpr double kSpacerFollowStep = 6.0;
constexpr ULONGLONG kSpacerFollowIntervalMs = 120;

struct Settings {
    bool showOnAllTaskbars = false;
};

struct CleanerState {
    int memoryPercent = 0;
    std::wstring location = L"--";
    std::wstring networkMode = L"网络";
    std::wstring download = L"0 B/s";
    std::wstring upload = L"0 B/s";
    std::wstring message;
    bool showLocation = true;
    bool showSpeed = true;
    bool busy = false;
    bool visible = false;
    bool modeTaskbar = true;
    bool useBackgroundColor = false;
    std::wstring backgroundColor = L"#303033";
    double backgroundOpacity = 72;
    double taskbarOffset = 0;
};

struct UiInstance {
    HWND taskbarWnd = nullptr;
    Grid parent{nullptr};
    Grid root{nullptr};
    FrameworkElement defaultBackgroundLayer{nullptr};
    FrameworkElement backgroundColorLayer{nullptr};
    SolidColorBrush backgroundColorBrush{nullptr};
    FrameworkElement hoverLayer{nullptr};
    StackPanel statusPanel{nullptr};
    StackPanel messagePanel{nullptr};
    FrameworkElement locationSeparator{nullptr};
    FrameworkElement locationPanel{nullptr};
    FrameworkElement speedSeparator{nullptr};
    FrameworkElement downloadPanel{nullptr};
    FrameworkElement uploadPanel{nullptr};
    TextBlock memoryText{nullptr};
    TextBlock locationText{nullptr};
    TextBlock locationCaption{nullptr};
    TextBlock downloadText{nullptr};
    TextBlock uploadText{nullptr};
    TextBlock messageText{nullptr};
    DispatcherTimer timer{nullptr};
    DispatcherTimer dragTimer{nullptr};
    ColumnDefinition spacerColumn{nullptr};
    int insertedColumn = -1;
    int insertedColumnCount = 0;
    bool busy = false;
    ULONGLONG pendingCleanUntil = 0;
    ULONGLONG pendingPositionUntil = 0;
    ULONGLONG nextReadyHeartbeatAt = 0;
    bool pointerPressed = false;
    bool dragging = false;
    bool ejected = false;
    uint32_t pointerId = 0;
    double dragStartX = 0;
    LONG dragStartCursorX = 0;
    LONG dragStartCursorY = 0;
    double dragScale = 1.0;
    double dragStartOffset = 0;
    double taskbarOffset = 0;
    double originalTrayWidth = 0;
    double lastSpacerOffset = 0;
    ULONGLONG lastSpacerUpdateAt = 0;
    double dragMinTx = -1600.0;
    double dragMaxTx = 1600.0;
    ULONGLONG suppressTapUntil = 0;
    TranslateTransform dragTranslate{nullptr};
    winrt::event_token tappedToken{};
    winrt::event_token rightTappedToken{};
    winrt::event_token pointerPressedToken{};
    winrt::event_token pointerMovedToken{};
    winrt::event_token pointerReleasedToken{};
    winrt::event_token pointerCanceledToken{};
    winrt::event_token pointerCaptureLostToken{};
    winrt::event_token pointerEnteredToken{};
    winrt::event_token pointerExitedToken{};
    winrt::event_token timerToken{};
    winrt::event_token dragTimerToken{};
};

Settings g_settings;
std::mutex g_settingsMutex;
std::vector<std::unique_ptr<UiInstance>> g_instances;
std::mutex g_instancesMutex;
std::atomic<bool> g_unloading{false};
std::atomic<bool> g_taskbarViewDllLoaded{false};

std::wstring GetStateDirectory() {
    wchar_t localAppData[MAX_PATH]{};
    DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData,
                                           ARRAYSIZE(localAppData));
    if (!length || length >= ARRAYSIZE(localAppData)) {
        return {};
    }

    std::wstring result(localAppData, length);
    result += L"\\MemoryCleanerFloat";
    return result;
}

std::wstring GetStatePath() {
    auto result = GetStateDirectory();
    if (!result.empty()) result += L"\\taskbar-state.json";
    return result;
}

std::wstring GetPositionPath() {
    auto result = GetStateDirectory();
    if (!result.empty()) result += L"\\taskbar-position.json";
    return result;
}

std::wstring GetEjectPath() {
    auto result = GetStateDirectory();
    if (!result.empty()) result += L"\\taskbar-eject.json";
    return result;
}

std::wstring GetReadyPath() {
    auto result = GetStateDirectory();
    if (!result.empty()) result += L"\\taskbar-ready.json";
    return result;
}

ULONGLONG FileTimeToMilliseconds(const FILETIME& fileTime) {
    ULARGE_INTEGER value{};
    value.LowPart = fileTime.dwLowDateTime;
    value.HighPart = fileTime.dwHighDateTime;
    return value.QuadPart / 10000;
}

bool ReadTextFile(const std::wstring& path, std::wstring* output,
                  FILETIME* lastWriteTime) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_WRITE |
                                  FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return false;
    }

    BY_HANDLE_FILE_INFORMATION info{};
    LARGE_INTEGER size{};
    bool ok = GetFileInformationByHandle(file, &info) &&
              GetFileSizeEx(file, &size) && size.QuadPart >= 0 &&
              size.QuadPart <= 1024 * 1024;
    if (!ok) {
        CloseHandle(file);
        return false;
    }

    std::string utf8(static_cast<size_t>(size.QuadPart), '\0');
    DWORD bytesRead = 0;
    ok = utf8.empty() ||
         (ReadFile(file, utf8.data(), static_cast<DWORD>(utf8.size()),
                   &bytesRead, nullptr) &&
          bytesRead == utf8.size());
    CloseHandle(file);
    if (!ok) {
        return false;
    }

    int wideLength = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         utf8.data(),
                                         static_cast<int>(utf8.size()), nullptr,
                                         0);
    if (wideLength < 0 || (!utf8.empty() && wideLength == 0)) {
        return false;
    }

    output->assign(static_cast<size_t>(wideLength), L'\0');
    if (wideLength > 0) {
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                            static_cast<int>(utf8.size()), output->data(),
                            wideLength);
    }
    *lastWriteTime = info.ftLastWriteTime;
    return true;
}

bool IsStateFresh(const FILETIME& lastWriteTime) {
    FILETIME nowFileTime{};
    GetSystemTimeAsFileTime(&nowFileTime);
    ULONGLONG now = FileTimeToMilliseconds(nowFileTime);
    ULONGLONG updated = FileTimeToMilliseconds(lastWriteTime);
    return now >= updated && now - updated <= kStateMaxAgeMs;
}

bool ReadCleanerState(CleanerState* state) {
    std::wstring jsonText;
    FILETIME lastWriteTime{};
    auto path = GetStatePath();
    if (path.empty() || !ReadTextFile(path, &jsonText, &lastWriteTime) ||
        !IsStateFresh(lastWriteTime)) {
        return false;
    }

    try {
        auto json = JsonObject::Parse(jsonText);
        state->memoryPercent = std::clamp(
            static_cast<int>(json.GetNamedNumber(L"MemoryPercent", 0)), 0,
            100);
        state->location = json.GetNamedString(L"Location", L"--");
        state->networkMode = json.GetNamedString(L"NetworkMode", L"网络");
        state->download = json.GetNamedString(L"Download", L"0 B/s");
        state->upload = json.GetNamedString(L"Upload", L"0 B/s");
        state->message = json.GetNamedString(L"Message", L"");
        state->showLocation = json.GetNamedBoolean(L"ShowLocation", true);
        state->showSpeed = json.GetNamedBoolean(L"ShowSpeed", true);
        state->useBackgroundColor =
            json.GetNamedBoolean(L"UseBackgroundColor", false);
        state->backgroundColor =
            json.GetNamedString(L"BackgroundColor", L"#303033");
        state->backgroundOpacity = std::clamp(
            json.GetNamedNumber(L"BackgroundOpacity", 72), 20.0, 90.0);
        state->busy = json.GetNamedBoolean(L"Busy", false);
        state->visible = json.GetNamedBoolean(L"Visible", false);
        state->modeTaskbar =
            json.GetNamedString(L"Mode", L"taskbar") == L"taskbar";
        state->taskbarOffset = std::clamp(
            json.GetNamedNumber(L"TaskbarOffset", 0), 0.0,
            kAbsoluteMaximumOffset);
        return true;
    } catch (...) {
        return false;
    }
}

bool WriteUtf8FileAtomic(const std::wstring& path, const std::wstring& text) {
    if (path.empty()) return false;
    auto directory = GetStateDirectory();
    if (directory.empty()) return false;
    CreateDirectoryW(directory.c_str(), nullptr);

    int utf8Length = WideCharToMultiByte(
        CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0,
        nullptr, nullptr);
    if (utf8Length <= 0) return false;

    std::string utf8(static_cast<size_t>(utf8Length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        utf8.data(), utf8Length, nullptr, nullptr);

    auto temporaryPath = path + L".tmp";
    HANDLE file = CreateFileW(temporaryPath.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;

    DWORD written = 0;
    bool ok = WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()),
                        &written, nullptr) &&
              written == utf8.size() && FlushFileBuffers(file);
    CloseHandle(file);
    if (!ok) {
        DeleteFileW(temporaryPath.c_str());
        return false;
    }

    if (!MoveFileExW(temporaryPath.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporaryPath.c_str());
        return false;
    }
    return true;
}

bool WriteTaskbarOffset(double offset) {
    int roundedOffset = static_cast<int>(std::lround(std::clamp(
        offset, 0.0, kAbsoluteMaximumOffset)));
    std::wstring json =
        L"{\"Offset\":" + std::to_wstring(roundedOffset) + L"}";
    return WriteUtf8FileAtomic(GetPositionPath(), json);
}

bool WriteEjectRequest(long cursorX, long cursorY) {
    std::wstring json = L"{\"X\":" + std::to_wstring(cursorX) + L",\"Y\":" +
                        std::to_wstring(cursorY) + L"}";
    return WriteUtf8FileAtomic(GetEjectPath(), json);
}

bool WriteReadyMarker() {
    std::wstring json = L"{\"Version\":\"1.6.2\",\"ExplorerPid\":" +
                        std::to_wstring(GetCurrentProcessId()) + L"}";
    return WriteUtf8FileAtomic(GetReadyPath(), json);
}

void SignalControllerEvent(PCWSTR name) {
    HANDLE eventHandle = OpenEventW(EVENT_MODIFY_STATE, FALSE, name);
    if (!eventHandle) {
        return;
    }
    SetEvent(eventHandle);
    CloseHandle(eventHandle);
}

SolidColorBrush Brush(BYTE a, BYTE r, BYTE g, BYTE b) {
    return SolidColorBrush(winrt::Windows::UI::Color{a, r, g, b});
}

double GetMaximumTaskbarOffset(UiInstance& instance) {
    double availableWidth = 0;
    try {
        if (auto xamlRoot = instance.parent.XamlRoot()) {
            availableWidth = xamlRoot.Size().Width;
        }
    } catch (...) {}

    if (availableWidth <= 0) {
        RECT clientRect{};
        HWND taskbar = instance.taskbarWnd
                           ? instance.taskbarWnd
                           : FindWindowW(L"Shell_TrayWnd", nullptr);
        if (taskbar && GetClientRect(taskbar, &clientRect)) {
            availableWidth = static_cast<double>(clientRect.right -
                                                 clientRect.left);
        }
    }

    if (availableWidth <= 0) return 1000.0;
    double maximum = availableWidth - instance.originalTrayWidth - kSlotWidth -
                     kReservedTaskbarWidth;
    return std::clamp(maximum, 0.0, kAbsoluteMaximumOffset);
}

void ApplyTaskbarOffset(UiInstance& instance, double requestedOffset) {
    if (!instance.spacerColumn) return;
    double offset = std::clamp(requestedOffset, 0.0,
                               GetMaximumTaskbarOffset(instance));
    if (std::abs(offset - instance.taskbarOffset) < 0.5) return;
    instance.taskbarOffset = offset;
    instance.spacerColumn.Width(
        GridLength{offset, GridUnitType::Pixel});
}

void PersistTaskbarOffset(UiInstance& instance) {
    instance.pendingPositionUntil = GetTickCount64() + 5000;
    if (WriteTaskbarOffset(instance.taskbarOffset)) {
        SignalControllerEvent(kPositionEventName);
    }
}

bool IsCursorOutsideTaskbar(UiInstance& instance) {
    if (!instance.taskbarWnd) return false;
    RECT taskbarRect{};
    if (!GetWindowRect(instance.taskbarWnd, &taskbarRect)) return false;
    POINT cursor{};
    if (!GetCursorPos(&cursor)) return false;
    return cursor.x < taskbarRect.left || cursor.x > taskbarRect.right ||
           cursor.y < taskbarRect.top || cursor.y > taskbarRect.bottom;
}

bool UpdateDragFromCursor(UiInstance& instance) {
    if (!instance.pointerPressed) return false;
    POINT cursor{};
    if (!GetCursorPos(&cursor)) return false;
    double scale = instance.dragScale > 0 ? instance.dragScale : 1.0;
    double deltaX = static_cast<double>(cursor.x - instance.dragStartCursorX) /
                    scale;
    double deltaY = static_cast<double>(cursor.y - instance.dragStartCursorY) /
                    scale;
    if (!instance.dragging &&
        std::abs(deltaX) < kDragThreshold && std::abs(deltaY) < kDragThreshold) {
        return false;
    }
    instance.dragging = true;

    // Smooth drag: the slot follows the pointer via RenderTransform only.
    // The taskbar grid layout is never touched while dragging, so there is no
    // re-layout stutter. The grid clip is disabled at injection time, which
    // lets the slot glide over the other taskbar elements and stay visible
    // instead of being clipped as it moves. The final offset lands on the
    // spacer column on release.
    // The slot glides with the pointer via RenderTransform (smooth, no layout
    // work per frame) while the spacer column follows in small throttled steps
    // so the slot stays at its layout position (never covering other taskbar
    // elements and never sliding out of view). Updating only the transform
    // leaves the slot floating over the taskbar, which reads as either
    // "covering" the icons or, at the window edge, "hiding".
    if (IsCursorOutsideTaskbar(instance)) {
        // The pointer has left the taskbar: let the slot visually follow the
        // cursor all the way out instead of being clamped at the edge.
        double offset = std::clamp(instance.dragStartOffset - deltaX, 0.0,
                                   GetMaximumTaskbarOffset(instance));
        double tx = -(offset - instance.lastSpacerOffset);
        tx = std::clamp(tx, instance.dragMinTx, instance.dragMaxTx);
        instance.dragTranslate.X(tx);
        instance.dragTranslate.Y(-deltaY);
    } else {
        double offset = std::clamp(instance.dragStartOffset - deltaX, 0.0,
                                   GetMaximumTaskbarOffset(instance));
        ULONGLONG now = GetTickCount64();
        if (std::abs(offset - instance.lastSpacerOffset) >=
                kSpacerFollowStep ||
            now - instance.lastSpacerUpdateAt >= kSpacerFollowIntervalMs) {
            ApplyTaskbarOffset(instance, offset);
            instance.lastSpacerOffset = instance.taskbarOffset;
            instance.lastSpacerUpdateAt = now;
            instance.dragTranslate.X(0);
        } else {
            double tx = -(offset - instance.lastSpacerOffset);
            tx = std::clamp(tx, instance.dragMinTx, instance.dragMaxTx);
            instance.dragTranslate.X(tx);
        }
        instance.dragTranslate.Y(0);
    }
    return true;
}

void FinishDrag(UiInstance& instance) {
    if (!instance.pointerPressed) return;
    bool wasDragging = instance.dragging;
    instance.pointerPressed = false;
    instance.dragging = false;
    try {
        if (instance.dragTimer) instance.dragTimer.Stop();
    } catch (...) {}
    if (wasDragging) {
        instance.dragTranslate.X(0);
        instance.dragTranslate.Y(0);

        double finalOffset = instance.dragStartOffset;
        POINT cursor{};
        if (GetCursorPos(&cursor)) {
            double scale = instance.dragScale > 0 ? instance.dragScale : 1.0;
            double deltaX =
                static_cast<double>(cursor.x - instance.dragStartCursorX) /
                scale;
            finalOffset = instance.dragStartOffset - deltaX;
        }
        ApplyTaskbarOffset(instance, finalOffset);
        instance.lastSpacerOffset = instance.taskbarOffset;

        if (IsCursorOutsideTaskbar(instance)) {
            // Dropped outside the taskbar: eject the slot and hand the panel
            // over to the floating controller window. The slot stays hidden
            // (the controller switches its state to floating) and comes back
            // when the user switches back to taskbar mode.
            instance.ejected = true;
            // Short anti-flash window: long enough for the controller to react
            // to the eject (it polls every 250ms), short enough that dragging
            // the floating panel back into the taskbar restores the slot
            // almost immediately instead of waiting seconds.
            instance.pendingPositionUntil = GetTickCount64() + 600;
            instance.root.Visibility(Visibility::Collapsed);
            instance.spacerColumn.Width(GridLength{0.0, GridUnitType::Pixel});
            WriteEjectRequest(cursor.x, cursor.y);
            SignalControllerEvent(kEjectEventName);
            return;
        }

        instance.suppressTapUntil = GetTickCount64() + 500;
        PersistTaskbarOffset(instance);
    }
}

Grid BuildSlot(UiInstance& instance) {
    // Colors, typography, spacing, icon, and information layout remain aligned
    // with v1.9. The outer width is compacted to remove unused side space.
    auto loaded = wuxm::XamlReader::Load(LR"XAML(
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      x:Name="MemoryCleanerTaskbarSlotRoot" Width="360" Height="52"
      Background="#01000000" Visibility="Collapsed">
    <Border x:Name="DefaultBackgroundLayer" Margin="1" CornerRadius="18" BorderThickness="1" BorderBrush="#32FFFFFF" IsHitTestVisible="False">
        <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#EC303033" Offset="0"/>
                <GradientStop Color="#EC1C1C1E" Offset="1"/>
            </LinearGradientBrush>
        </Border.Background>
    </Border>
    <Border x:Name="BackgroundColorLayer" Margin="1" CornerRadius="18" BorderThickness="1" BorderBrush="#32FFFFFF" IsHitTestVisible="False" Visibility="Collapsed">
        <Border.Background>
            <SolidColorBrush x:Name="BackgroundColorBrush" Color="#B8303033"/>
        </Border.Background>
    </Border>
    <Border x:Name="HoverLayer" Margin="1" CornerRadius="18" Background="#24FFFFFF" Opacity="0" IsHitTestVisible="False"/>
    <StackPanel x:Name="StatusPanel" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False">
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
            <TextBlock x:Name="MemoryText" Text="0%" Foreground="#FFF5F5F7" FontFamily="Segoe UI Variable Display Semibold, Segoe UI Semibold" FontSize="16.5" LineHeight="18" TextAlignment="Center"/>
            <TextBlock Text="RAM" Foreground="#B8EBEBF5" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center"/>
        </StackPanel>
        <Border x:Name="LocationSeparator" Width="1" Height="22" Background="#32FFFFFF" Margin="7,0"/>
        <StackPanel x:Name="LocationPanel" Width="60" VerticalAlignment="Center">
            <TextBlock x:Name="LocationText" Text="--" Foreground="#FFF5F5F7" FontFamily="Microsoft YaHei UI" FontWeight="SemiBold" FontSize="12" LineHeight="15" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="LocationCaption" Text="&#x7F51;&#x7EDC;" Foreground="#B8EBEBF5" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
        <Border x:Name="SpeedSeparator" Width="1" Height="22" Background="#32FFFFFF" Margin="7,0"/>
        <StackPanel x:Name="DownloadPanel" Width="72" VerticalAlignment="Center">
            <TextBlock x:Name="DownloadText" Text="0 B/s" Foreground="#FF64D2FF" FontFamily="Segoe UI Variable Text, Segoe UI" FontWeight="SemiBold" FontSize="11" LineHeight="14" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
            <TextBlock Text="&#x4E0B;&#x8F7D;" Foreground="#B8EBEBF5" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center"/>
        </StackPanel>
        <StackPanel x:Name="UploadPanel" Width="72" VerticalAlignment="Center" Margin="6,0,0,0">
            <TextBlock x:Name="UploadText" Text="0 B/s" Foreground="#FF30D158" FontFamily="Segoe UI Variable Text, Segoe UI" FontWeight="SemiBold" FontSize="11" LineHeight="14" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
            <TextBlock Text="&#x4E0A;&#x4F20;" Foreground="#B8EBEBF5" FontFamily="Microsoft YaHei UI" FontSize="9" LineHeight="10" TextAlignment="Center"/>
        </StackPanel>
    </StackPanel>
    <StackPanel x:Name="MessagePanel" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False">
        <Ellipse Width="8" Height="8" Fill="#FF0A84FF" Margin="0,0,7,0"/>
        <TextBlock x:Name="MessageText" Text="&#x6B63;&#x5728;&#x6E05;&#x7406;&#x5185;&#x5B58;&#x2026;" Foreground="#FFF5F5F7" FontFamily="Microsoft YaHei UI" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
</Grid>
)XAML");
    Grid root = loaded.as<Grid>();
    root.Name(kRootName);
    root.VerticalAlignment(VerticalAlignment::Center);

    instance.defaultBackgroundLayer =
        root.FindName(L"DefaultBackgroundLayer").as<FrameworkElement>();
    instance.backgroundColorLayer =
        root.FindName(L"BackgroundColorLayer").as<FrameworkElement>();
    instance.backgroundColorBrush =
        root.FindName(L"BackgroundColorBrush").as<SolidColorBrush>();
    instance.hoverLayer = root.FindName(L"HoverLayer").as<FrameworkElement>();
    instance.statusPanel = root.FindName(L"StatusPanel").as<StackPanel>();
    instance.messagePanel = root.FindName(L"MessagePanel").as<StackPanel>();
    instance.locationSeparator = root.FindName(L"LocationSeparator").as<FrameworkElement>();
    instance.locationPanel = root.FindName(L"LocationPanel").as<FrameworkElement>();
    instance.speedSeparator = root.FindName(L"SpeedSeparator").as<FrameworkElement>();
    instance.downloadPanel = root.FindName(L"DownloadPanel").as<FrameworkElement>();
    instance.uploadPanel = root.FindName(L"UploadPanel").as<FrameworkElement>();
    instance.memoryText = root.FindName(L"MemoryText").as<TextBlock>();
    instance.locationText = root.FindName(L"LocationText").as<TextBlock>();
    instance.locationCaption = root.FindName(L"LocationCaption").as<TextBlock>();
    instance.downloadText = root.FindName(L"DownloadText").as<TextBlock>();
    instance.uploadText = root.FindName(L"UploadText").as<TextBlock>();
    instance.messageText = root.FindName(L"MessageText").as<TextBlock>();

    auto toolTip = ToolTip();
    toolTip.Content(winrt::box_value(
        L"\u5DE6\u952E\u70B9\u51FB\u91CA\u653E\u5185\u5B58\uFF1B\u6309\u4F4F\u5DE6\u952E\u6A2A\u5411\u62D6\u52A8\uFF1B\u53F3\u952E\u6253\u5F00\u5DE5\u5177\u83DC\u5355"));
    ToolTipService::SetToolTip(root, toolTip);

    return root;
}

int HexDigit(wchar_t value) {
    if (value >= L'0' && value <= L'9') return value - L'0';
    if (value >= L'a' && value <= L'f') return value - L'a' + 10;
    if (value >= L'A' && value <= L'F') return value - L'A' + 10;
    return -1;
}

bool TryParseBackgroundColor(const std::wstring& value, double opacity,
                             winrt::Windows::UI::Color* color) {
    if (!color || value.size() != 7 || value[0] != L'#') return false;
    int components[6]{};
    for (size_t i = 0; i < 6; ++i) {
        components[i] = HexDigit(value[i + 1]);
        if (components[i] < 0) return false;
    }
    color->A = static_cast<uint8_t>(std::lround(
        std::clamp(opacity, 20.0, 90.0) * 255.0 / 100.0));
    color->R = static_cast<uint8_t>(components[0] * 16 + components[1]);
    color->G = static_cast<uint8_t>(components[2] * 16 + components[3]);
    color->B = static_cast<uint8_t>(components[4] * 16 + components[5]);
    return true;
}

void UpdateSlot(UiInstance& instance) {
    if (!instance.root) return;

    CleanerState state;
    if (!ReadCleanerState(&state) || !state.visible) {
        instance.root.Visibility(Visibility::Collapsed);
        instance.busy = false;
        return;
    }

    // The controller switched to floating mode: keep the taskbar slot hidden
    // until taskbar mode is requested again.
    if (!state.modeTaskbar) {
        if (!instance.ejected) {
            instance.ejected = true;
            instance.dragTranslate.X(0);
            instance.dragTranslate.Y(0);
        }
        instance.root.Visibility(Visibility::Collapsed);
        instance.spacerColumn.Width(GridLength{0.0, GridUnitType::Pixel});
        instance.busy = false;
        return;
    }

    if (instance.ejected) {
        // Just ejected: wait for the controller to react before restoring the
        // slot so it does not flash back into the taskbar mid-transition.
        if (GetTickCount64() < instance.pendingPositionUntil) {
            instance.root.Visibility(Visibility::Collapsed);
            return;
        }
        instance.ejected = false;
        instance.dragTranslate.X(0);
        instance.dragTranslate.Y(0);
    }

    if (!instance.pointerPressed &&
        GetTickCount64() >= instance.pendingPositionUntil) {
        ApplyTaskbarOffset(instance, state.taskbarOffset);
    }

    instance.root.Visibility(Visibility::Visible);
    winrt::Windows::UI::Color backgroundColor{};
    const bool useCustomBackground = state.useBackgroundColor &&
        TryParseBackgroundColor(state.backgroundColor,
                                 state.backgroundOpacity,
                                 &backgroundColor);
    // Selected alpha applies only to this background layer. Text, icon,
    // dividers and borders remain opaque and readable.
    instance.defaultBackgroundLayer.Visibility(useCustomBackground
        ? Visibility::Collapsed : Visibility::Visible);
    if (useCustomBackground) {
        instance.backgroundColorBrush.Color(backgroundColor);
        instance.backgroundColorLayer.Visibility(Visibility::Visible);
    } else {
        instance.backgroundColorLayer.Visibility(Visibility::Collapsed);
    }
    ULONGLONG now = GetTickCount64();
    if (now >= instance.nextReadyHeartbeatAt) {
        if (WriteReadyMarker()) {
            instance.nextReadyHeartbeatAt = now + 5000;
        } else {
            instance.nextReadyHeartbeatAt = now + 1000;
        }
    }
    bool pendingClean = GetTickCount64() < instance.pendingCleanUntil;
    instance.busy = state.busy || pendingClean;

    bool showMessage = instance.busy || !state.message.empty();
    instance.statusPanel.Visibility(showMessage ? Visibility::Collapsed
                                                : Visibility::Visible);
    instance.messagePanel.Visibility(showMessage ? Visibility::Visible
                                                 : Visibility::Collapsed);
    if (showMessage) {
        instance.messageText.Text((state.busy || pendingClean || state.message.empty())
                                      ? L"\u6B63\u5728\u6E05\u7406\u5185\u5B58\u2026"
                                      : state.message);
        return;
    }

    instance.memoryText.Text(std::to_wstring(state.memoryPercent) + L"%");
    instance.locationText.Text(state.location.empty() ? L"--" : state.location);
    instance.locationCaption.Text(state.networkMode.empty() ? L"\u7F51\u7EDC"
                                                            : state.networkMode);
    instance.downloadText.Text(state.download);
    instance.uploadText.Text(state.upload);

    auto locationVisibility = state.showLocation ? Visibility::Visible
                                                 : Visibility::Collapsed;
    auto speedVisibility = state.showSpeed ? Visibility::Visible
                                           : Visibility::Collapsed;
    instance.locationSeparator.Visibility(locationVisibility);
    instance.locationPanel.Visibility(locationVisibility);
    instance.speedSeparator.Visibility(speedVisibility);
    instance.downloadPanel.Visibility(speedVisibility);
    instance.uploadPanel.Visibility(speedVisibility);
}

FrameworkElement FindDescendantByName(FrameworkElement const& root,
                                      std::wstring_view name, int depth = 24) {
    if (!root || depth <= 0) return nullptr;
    int count = VisualTreeHelper::GetChildrenCount(root);
    for (int i = 0; i < count; ++i) {
        auto child = VisualTreeHelper::GetChild(root, i)
                         .try_as<FrameworkElement>();
        if (!child) continue;
        if (child.Name() == name) return child;
        if (auto found = FindDescendantByName(child, name, depth - 1)) {
            return found;
        }
    }
    return nullptr;
}

UiInstance* FindInstance(Grid const& parent) {
    void* parentAbi = winrt::get_abi(parent);
    for (auto& instance : g_instances) {
        if (instance->parent && winrt::get_abi(instance->parent) == parentAbi) {
            return instance.get();
        }
    }
    return nullptr;
}

void RevokeInstanceEvents(UiInstance& instance) {
    try {
        if (instance.timer) instance.timer.Stop();
    } catch (...) {}
    try {
        if (instance.timer) instance.timer.Tick(instance.timerToken);
    } catch (...) {}
    try {
        if (instance.dragTimer) instance.dragTimer.Stop();
    } catch (...) {}
    try {
        if (instance.dragTimer) instance.dragTimer.Tick(instance.dragTimerToken);
    } catch (...) {}
    try {
        if (instance.root) instance.root.Tapped(instance.tappedToken);
    } catch (...) {}
    try {
        if (instance.root) instance.root.RightTapped(instance.rightTappedToken);
    } catch (...) {}
    try {
        if (instance.root) instance.root.PointerPressed(instance.pointerPressedToken);
    } catch (...) {}
    try {
        if (instance.root) instance.root.PointerMoved(instance.pointerMovedToken);
    } catch (...) {}
    try {
        if (instance.root) instance.root.PointerReleased(instance.pointerReleasedToken);
    } catch (...) {}
    try {
        if (instance.root) instance.root.PointerCanceled(instance.pointerCanceledToken);
    } catch (...) {}
    try {
        if (instance.root) {
            instance.root.PointerCaptureLost(instance.pointerCaptureLostToken);
        }
    } catch (...) {}
    try {
        if (instance.root) instance.root.PointerEntered(instance.pointerEnteredToken);
    } catch (...) {}
    try {
        if (instance.root) instance.root.PointerExited(instance.pointerExitedToken);
    } catch (...) {}
}

void RemoveInstance(UiInstance& instance) {
    RevokeInstanceEvents(instance);
    if (!instance.parent) return;

    try {
        auto children = instance.parent.Children();
        int column = instance.insertedColumn;
        for (int i = static_cast<int>(children.Size()) - 1; i >= 0; --i) {
            auto child = children.GetAt(i).try_as<FrameworkElement>();
            if (child && child.Name() == kRootName) {
                column = Grid::GetColumn(child);
                children.RemoveAt(i);
            }
        }

        if (instance.insertedColumnCount > 0 && column >= 0 &&
            column + instance.insertedColumnCount <=
                static_cast<int>(instance.parent.ColumnDefinitions().Size())) {
            for (uint32_t i = 0; i < children.Size(); ++i) {
                auto child = children.GetAt(i).try_as<FrameworkElement>();
                if (!child) continue;
                int childColumn = Grid::GetColumn(child);
                if (childColumn >= column + instance.insertedColumnCount) {
                    Grid::SetColumn(child,
                                    childColumn - instance.insertedColumnCount);
                }
            }
            for (int i = instance.insertedColumnCount - 1; i >= 0; --i) {
                instance.parent.ColumnDefinitions().RemoveAt(column + i);
            }
        }
    } catch (...) {
        Wh_Log(L"Failed to restore taskbar grid");
    }
}

bool InjectIntoTray(Grid trayGrid, FrameworkElement sourceElement) {
    if (!trayGrid || g_unloading) return false;

    Settings settings;
    {
        std::lock_guard<std::mutex> lock(g_settingsMutex);
        settings = g_settings;
    }
    {
        std::lock_guard<std::mutex> lock(g_instancesMutex);
        if (FindInstance(trayGrid)) {
            WriteReadyMarker();
            return true;
        }
        // The primary taskbar is realized first. In primary-only mode, accept
        // only the first distinct tray grid instead of trying to map an XAML
        // island back to an HWND with unreliable compatibility handles.
        if (!settings.showOnAllTaskbars && !g_instances.empty()) return false;
    }

    auto instance = std::make_unique<UiInstance>();
    instance->taskbarWnd = FindWindowW(L"Shell_TrayWnd", nullptr);
    instance->parent = trayGrid;
    instance->originalTrayWidth = trayGrid.ActualWidth();
    instance->root = BuildSlot(*instance);
    instance->dragTranslate = TranslateTransform();
    instance->root.RenderTransform(instance->dragTranslate);

    instance->tappedToken = instance->root.Tapped(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::TappedRoutedEventArgs const& args) {
            args.Handled(true);
            if (GetTickCount64() < instancePtr->suppressTapUntil) return;
            if (!instancePtr->busy) {
                instancePtr->busy = true;
                instancePtr->pendingCleanUntil = GetTickCount64() + 1500;
                instancePtr->statusPanel.Visibility(Visibility::Collapsed);
                instancePtr->messagePanel.Visibility(Visibility::Visible);
                instancePtr->messageText.Text(
                    L"\u6B63\u5728\u6E05\u7406\u5185\u5B58\u2026");
                SignalControllerEvent(kCleanEventName);
            }
        });
    instance->rightTappedToken = instance->root.RightTapped(
        [](winrt::Windows::Foundation::IInspectable const&,
           wuxi::RightTappedRoutedEventArgs const& args) {
            args.Handled(true);
            SignalControllerEvent(kMenuEventName);
        });
    instance->pointerPressedToken = instance->root.PointerPressed(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::PointerRoutedEventArgs const& args) {
            auto point = args.GetCurrentPoint(nullptr);
            if (!point.Properties().IsLeftButtonPressed()) return;
            instancePtr->pointerPressed = true;
            instancePtr->dragging = false;
            instancePtr->pointerId = args.Pointer().PointerId();
            instancePtr->dragStartX = point.Position().X;
            instancePtr->dragStartOffset = instancePtr->taskbarOffset;
            instancePtr->lastSpacerOffset = instancePtr->taskbarOffset;
            instancePtr->lastSpacerUpdateAt = GetTickCount64();
            // Clamp the drag translate so the slot never leaves the taskbar
            // window. Without this the slot slides off the window edge and
            // looks like it is hiding instead of being dragged.
            {
                double windowWidth = 0;
                double slotLayoutX = 0;
                try {
                    if (auto xamlRoot = instancePtr->root.XamlRoot()) {
                        windowWidth = xamlRoot.Size().Width;
                        auto content = xamlRoot.Content();
                        if (content) {
                            auto pt = instancePtr->root.TransformToVisual(content)
                                          .TransformPoint(
                                              winrt::Windows::Foundation::Point{0, 0});
                            slotLayoutX = pt.X;
                        }
                    }
                } catch (...) {}
                instancePtr->dragMinTx = -slotLayoutX + 2.0;
                instancePtr->dragMaxTx =
                    windowWidth - kSlotWidth - 2.0 - slotLayoutX;
                if (instancePtr->dragMinTx > 0) instancePtr->dragMinTx = 0;
                if (instancePtr->dragMaxTx < 0) instancePtr->dragMaxTx = 0;
            }
            POINT cursor{};
            if (GetCursorPos(&cursor)) {
                instancePtr->dragStartCursorX = cursor.x;
                instancePtr->dragStartCursorY = cursor.y;
            } else {
                instancePtr->dragStartCursorX =
                    static_cast<LONG>(std::lround(point.Position().X));
                instancePtr->dragStartCursorY =
                    static_cast<LONG>(std::lround(point.Position().Y));
            }
            instancePtr->dragScale = 1.0;
            try {
                if (auto xamlRoot = instancePtr->root.XamlRoot()) {
                    instancePtr->dragScale = xamlRoot.RasterizationScale();
                }
            } catch (...) {}
            instancePtr->root.CapturePointer(args.Pointer());
            if (instancePtr->dragTimer) instancePtr->dragTimer.Start();
        });
    instance->pointerMovedToken = instance->root.PointerMoved(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::PointerRoutedEventArgs const& args) {
            if (!instancePtr->pointerPressed ||
                args.Pointer().PointerId() != instancePtr->pointerId) {
                return;
            }
            auto point = args.GetCurrentPoint(nullptr);
            if (!point.Properties().IsLeftButtonPressed()) return;
            // Dragging is driven by the 16ms drag timer (which polls
            // GetCursorPos). Re-running the layout follow from the high-rate
            // pointer-move event used to reflow the taskbar grid far faster
            // than 60fps, which is what made the drag stutter.
            if (instancePtr->dragging) args.Handled(true);
        });
    instance->pointerReleasedToken = instance->root.PointerReleased(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::PointerRoutedEventArgs const& args) {
            if (!instancePtr->pointerPressed ||
                args.Pointer().PointerId() != instancePtr->pointerId) {
                return;
            }
            bool wasDragging = instancePtr->dragging;
            FinishDrag(*instancePtr);
            instancePtr->root.ReleasePointerCapture(args.Pointer());
            if (wasDragging) {
                args.Handled(true);
            }
        });
    instance->pointerCanceledToken = instance->root.PointerCanceled(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::PointerRoutedEventArgs const& args) {
            if (!instancePtr->pointerPressed ||
                args.Pointer().PointerId() != instancePtr->pointerId) {
                return;
            }
            FinishDrag(*instancePtr);
        });
    instance->pointerCaptureLostToken = instance->root.PointerCaptureLost(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::PointerRoutedEventArgs const&) {
            FinishDrag(*instancePtr);
        });
    instance->pointerEnteredToken = instance->root.PointerEntered(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::PointerRoutedEventArgs const&) {
            instancePtr->hoverLayer.Opacity(1.0);
        });
    instance->pointerExitedToken = instance->root.PointerExited(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            wuxi::PointerRoutedEventArgs const&) {
            instancePtr->hoverLayer.Opacity(0.0);
        });

    ColumnDefinition slotColumn;
    slotColumn.Width(GridLength{1.0, GridUnitType::Auto});
    trayGrid.ColumnDefinitions().InsertAt(0, slotColumn);
    ColumnDefinition spacerColumn;
    spacerColumn.Width(GridLength{0.0, GridUnitType::Pixel});
    trayGrid.ColumnDefinitions().InsertAt(1, spacerColumn);
    instance->spacerColumn = spacerColumn;
    instance->insertedColumn = 0;
    instance->insertedColumnCount = 2;
    for (uint32_t i = 0; i < trayGrid.Children().Size(); ++i) {
        auto child = trayGrid.Children().GetAt(i).try_as<FrameworkElement>();
        if (child) Grid::SetColumn(child, Grid::GetColumn(child) + 2);
    }
    Grid::SetColumn(instance->root, 0);
    trayGrid.Children().Append(instance->root);

    instance->timer = DispatcherTimer();
    instance->timer.Interval(std::chrono::milliseconds(250));
    instance->timerToken = instance->timer.Tick(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            winrt::Windows::Foundation::IInspectable const&) {
            UpdateSlot(*instancePtr);
        });
    instance->timer.Start();
    instance->dragTimer = DispatcherTimer();
    instance->dragTimer.Interval(std::chrono::milliseconds(16));
    instance->dragTimerToken = instance->dragTimer.Tick(
        [instancePtr = instance.get()](
            winrt::Windows::Foundation::IInspectable const&,
            winrt::Windows::Foundation::IInspectable const&) {
            if (!instancePtr->pointerPressed) {
                instancePtr->dragTimer.Stop();
                return;
            }
            if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0) {
                FinishDrag(*instancePtr);
                return;
            }
            UpdateDragFromCursor(*instancePtr);
        });
    UpdateSlot(*instance);

    {
        std::lock_guard<std::mutex> lock(g_instancesMutex);
        g_instances.push_back(std::move(instance));
    }
    WriteReadyMarker();
    Wh_Log(L"Injected a real taskbar slot");
    return true;
}

void TryInjectFromElement(FrameworkElement element) {
    if (!element || g_unloading) return;

    FrameworkElement current = element;
    for (int depth = 0; depth < 20 && current; ++depth) {
        if (winrt::get_class_name(current) == L"Taskbar.TaskbarFrame") {
            FrameworkElement ancestor = current;
            for (int parentDepth = 0; parentDepth < 5 && ancestor;
                 ++parentDepth) {
                auto parentObject = VisualTreeHelper::GetParent(ancestor);
                ancestor = parentObject.try_as<FrameworkElement>();
                if (!ancestor) break;
                auto tray = FindDescendantByName(ancestor,
                                                 L"SystemTrayFrameGrid")
                                .try_as<Grid>();
                if (tray) {
                    InjectIntoTray(tray, current);
                    return;
                }
            }
            return;
        }

        auto parentObject = VisualTreeHelper::GetParent(current);
        current = parentObject.try_as<FrameworkElement>();
    }
}

FrameworkElement GetFrameworkElementFromNative(void* pThis) {
    try {
        void* iUnknownPtr = (void**)pThis + 3;
        winrt::Windows::Foundation::IUnknown iUnknown;
        winrt::copy_from_abi(iUnknown, iUnknownPtr);
        return iUnknown.try_as<FrameworkElement>();
    } catch (...) {
        return nullptr;
    }
}

void ScheduleInjection(void* pThis) {
    try {
        auto element = GetFrameworkElementFromNative(pThis);
        if (!element) return;
        auto dispatcher = element.Dispatcher();
        if (!dispatcher) return;
        auto weakElement = winrt::make_weak(element);
        dispatcher.RunAsync(
            winrt::Windows::UI::Core::CoreDispatcherPriority::Low,
            [weakElement]() {
                if (auto element = weakElement.get()) {
                    TryInjectFromElement(element);
                }
            });
    } catch (...) {}
}

using TaskbarResources_OnTaskListButtonGotFocus_t = void(WINAPI*)(
    void*, winrt::Windows::Foundation::IInspectable const&,
    RoutedEventArgs const&);
TaskbarResources_OnTaskListButtonGotFocus_t
    TaskbarResources_OnTaskListButtonGotFocus_Original;

void WINAPI TaskbarResources_OnTaskListButtonGotFocus_Hook(
    void* pThis, winrt::Windows::Foundation::IInspectable const& sender,
    RoutedEventArgs const& args) {
    TaskbarResources_OnTaskListButtonGotFocus_Original(pThis, sender, args);
    try {
        if (auto element = sender.try_as<FrameworkElement>()) {
            TryInjectFromElement(element);
        }
    } catch (...) {}
}

using TaskListButtonAutomationPeer_SetFocusCore_t = int(WINAPI*)(void*);
TaskListButtonAutomationPeer_SetFocusCore_t
    TaskListButtonAutomationPeer_SetFocusCore_Original;

int WINAPI TaskListButtonAutomationPeer_SetFocusCore_Hook(void* pThis) {
    int result = TaskListButtonAutomationPeer_SetFocusCore_Original(pThis);
    try {
        void* iUnknownPtr = reinterpret_cast<void**>(pThis) + 3;
        winrt::Windows::Foundation::IUnknown iUnknown;
        winrt::copy_from_abi(iUnknown, iUnknownPtr);
        auto peer = iUnknown.try_as<wuxap::FrameworkElementAutomationPeer>();
        if (peer) {
            if (auto owner = peer.Owner().try_as<FrameworkElement>()) {
                TryInjectFromElement(owner);
            }
        }
    } catch (...) {}
    return result;
}

using TaskListButton_UpdateVisualStates_t = void(WINAPI*)(void*);
TaskListButton_UpdateVisualStates_t TaskListButton_UpdateVisualStates_Original;

void WINAPI TaskListButton_UpdateVisualStates_Hook(void* pThis) {
    TaskListButton_UpdateVisualStates_Original(pThis);
    ScheduleInjection(pThis);
}

using ExperienceToggleButton_UpdateVisualStates_t = void(WINAPI*)(void*);
ExperienceToggleButton_UpdateVisualStates_t
    ExperienceToggleButton_UpdateVisualStates_Original;

void WINAPI ExperienceToggleButton_UpdateVisualStates_Hook(void* pThis) {
    ExperienceToggleButton_UpdateVisualStates_Original(pThis);
    ScheduleInjection(pThis);
}

bool HookTaskbarViewDllSymbols(HMODULE module) {
    WindhawkUtils::SYMBOL_HOOK hooks[] = {
        {
            {LR"(private: void __cdecl winrt::Taskbar::implementation::TaskListButton::UpdateVisualStates(void))"},
            &TaskListButton_UpdateVisualStates_Original,
            TaskListButton_UpdateVisualStates_Hook,
        },
        {
            {LR"(private: void __cdecl winrt::Taskbar::implementation::ExperienceToggleButton::UpdateVisualStates(void))"},
            &ExperienceToggleButton_UpdateVisualStates_Original,
            ExperienceToggleButton_UpdateVisualStates_Hook,
            true,
        },
        {
            {LR"(public: void __cdecl winrt::Taskbar::implementation::TaskbarResources::OnTaskListButtonGotFocus(struct winrt::Windows::Foundation::IInspectable const &,struct winrt::Windows::UI::Xaml::RoutedEventArgs const &))"},
            &TaskbarResources_OnTaskListButtonGotFocus_Original,
            TaskbarResources_OnTaskListButtonGotFocus_Hook,
            true,
        },
        {
            {
                LR"(public: virtual int __cdecl winrt::impl::produce<struct winrt::Taskbar::implementation::TaskListButtonAutomationPeer,struct winrt::Windows::UI::Xaml::Automation::Peers::IAutomationPeerOverrides>::SetFocusCore(void))",
                LR"(?SetFocusCore@?$produce@UTaskListButtonAutomationPeer@implementation@Taskbar@winrt@@UIAutomationPeerOverrides@Peers@Automation@Xaml@UI@Windows@4@@impl@winrt@@UEAAHXZ)",
            },
            &TaskListButtonAutomationPeer_SetFocusCore_Original,
            TaskListButtonAutomationPeer_SetFocusCore_Hook,
            true,
        },
    };

    return WindhawkUtils::HookSymbols(module, hooks, ARRAYSIZE(hooks));
}

HMODULE GetTaskbarViewModuleHandle() {
    HMODULE module = GetModuleHandleW(L"Taskbar.View.dll");
    return module ? module : GetModuleHandleW(L"ExplorerExtensions.dll");
}

using LoadLibraryExW_t = decltype(&LoadLibraryExW);
LoadLibraryExW_t LoadLibraryExW_Original;

HMODULE WINAPI LoadLibraryExW_Hook(LPCWSTR fileName, HANDLE file,
                                   DWORD flags) {
    HMODULE module = LoadLibraryExW_Original(fileName, file, flags);
    if (module && !g_taskbarViewDllLoaded &&
        GetTaskbarViewModuleHandle() == module &&
        !g_taskbarViewDllLoaded.exchange(true)) {
        if (HookTaskbarViewDllSymbols(module)) {
            Wh_ApplyHookOperations();
        }
    }
    return module;
}

void LoadSettings() {
    Settings settings;
    settings.showOnAllTaskbars =
        Wh_GetIntSetting(L"showOnAllTaskbars") != 0;

    std::lock_guard<std::mutex> lock(g_settingsMutex);
    g_settings = settings;
}

}  // namespace

BOOL Wh_ModInit() {
    Wh_Log(L"Initializing Memory Cleaner taskbar slot");
    g_unloading = false;
    LoadSettings();

    if (HMODULE module = GetTaskbarViewModuleHandle()) {
        g_taskbarViewDllLoaded = true;
        if (!HookTaskbarViewDllSymbols(module)) return FALSE;
    } else {
        HMODULE kernelBase = GetModuleHandleW(L"kernelbase.dll");
        auto loadLibrary = reinterpret_cast<decltype(&LoadLibraryExW)>(
            GetProcAddress(kernelBase, "LoadLibraryExW"));
        WindhawkUtils::Wh_SetFunctionHookT(loadLibrary, LoadLibraryExW_Hook,
                                           &LoadLibraryExW_Original);
    }

    return TRUE;
}

void Wh_ModUninit() {
    Wh_Log(L"Removing Memory Cleaner taskbar slot");
    g_unloading = true;

    std::vector<std::unique_ptr<UiInstance>> instances;
    {
        std::lock_guard<std::mutex> lock(g_instancesMutex);
        instances = std::move(g_instances);
    }

    for (auto& instance : instances) {
        if (!instance->root) continue;
        auto dispatcher = instance->root.Dispatcher();
        auto remove = [instancePtr = instance.get()]() {
            RemoveInstance(*instancePtr);
        };
        if (dispatcher && dispatcher.HasThreadAccess()) {
            remove();
        } else if (dispatcher) {
            try {
                dispatcher.RunAsync(
                    winrt::Windows::UI::Core::CoreDispatcherPriority::Normal,
                    remove)
                    .get();
            } catch (...) {}
        }
    }

    auto readyPath = GetReadyPath();
    if (!readyPath.empty()) DeleteFileW(readyPath.c_str());
}

void Wh_ModSettingsChanged() {
    LoadSettings();
}
