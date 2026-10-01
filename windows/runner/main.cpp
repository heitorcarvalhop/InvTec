#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {

// PROMPT 11.3.9.2 — window size policy, all values are CLIENT sizes in logical
// pixels (the area Flutter lays out in; title bar and borders are added on
// top). 1280x720 is the smallest viewport the app screens were verified at
// without RenderFlex overflow; the initial size is larger so the app opens
// comfortably but the user can still shrink it to the minimum, enlarge it
// freely or maximize it (WS_OVERLAPPEDWINDOW keeps the normal Windows caption
// buttons — this is NOT fullscreen).
constexpr unsigned int kMinClientWidth = 1280;
constexpr unsigned int kMinClientHeight = 720;
constexpr unsigned int kInitialClientWidth = 1440;
constexpr unsigned int kInitialClientHeight = 810;

struct InitialPlacement {
  Win32Window::Point origin;
  Win32Window::Size size;
};

// Outer window size that yields the wanted CLIENT size, clamped to the work
// area of the primary monitor and centered on it. Values are returned in
// logical pixels because Win32Window::Create scales them by the monitor DPI.
InitialPlacement ComputeInitialPlacement(unsigned int client_width,
                                         unsigned int client_height) {
  const POINT origin_point = {0, 0};
  HMONITOR monitor = MonitorFromPoint(origin_point, MONITOR_DEFAULTTOPRIMARY);
  const double scale_factor = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;

  // Non-client thickness measured at 96 dpi = logical thickness.
  RECT frame = {0, 0, static_cast<LONG>(client_width),
                static_cast<LONG>(client_height)};
  AdjustWindowRectExForDpi(&frame, WS_OVERLAPPEDWINDOW, FALSE, 0, 96);
  LONG outer_width = frame.right - frame.left;
  LONG outer_height = frame.bottom - frame.top;

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  LONG left = 10;
  LONG top = 10;
  if (GetMonitorInfo(monitor, &monitor_info)) {
    const LONG work_width = static_cast<LONG>(
        (monitor_info.rcWork.right - monitor_info.rcWork.left) / scale_factor);
    const LONG work_height = static_cast<LONG>(
        (monitor_info.rcWork.bottom - monitor_info.rcWork.top) / scale_factor);
    outer_width = std::min(outer_width, work_width);
    outer_height = std::min(outer_height, work_height);
    left = static_cast<LONG>(monitor_info.rcWork.left / scale_factor) +
           (work_width - outer_width) / 2;
    top = static_cast<LONG>(monitor_info.rcWork.top / scale_factor) +
          (work_height - outer_height) / 2;
  }

  return {Win32Window::Point(static_cast<unsigned int>(std::max<LONG>(left, 0)),
                             static_cast<unsigned int>(std::max<LONG>(top, 0))),
          Win32Window::Size(static_cast<unsigned int>(outer_width),
                            static_cast<unsigned int>(outer_height))};
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const InitialPlacement placement =
      ComputeInitialPlacement(kInitialClientWidth, kInitialClientHeight);
  // PROMPT 11.5.17 — título da janela/taskbar padronizado como "InvTec"
  // (identidade visual); o binário continua "invtec.exe" (ver
  // `windows/CMakeLists.txt`, `BINARY_NAME` — inalterado de propósito).
  if (!window.Create(L"InvTec", placement.origin, placement.size)) {
    return EXIT_FAILURE;
  }
  window.SetMinimumClientSize(
      Win32Window::Size(kMinClientWidth, kMinClientHeight));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
