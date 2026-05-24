#include "win32_window.h"

#include <dwmapi.h>
#include <flutter/flutter_view_controller.h>

namespace {
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
// Keeps track of the windows for DwmSetWindowAttribute.
HBRUSH bg_brush;
} // namespace

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                          const Point& origin,
                          const Size& size) {
  Destroy();
  const wchar_t* window_class = RegisterWindowClass();
  if (!window_class) {
    return false;
  }
  HWND hwnd = ::CreateWindow(
      window_class, title.c_str(),
      WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      Scale(origin.x, current_dpi_), Scale(origin.y, current_dpi_),
      Scale(size.width, current_dpi_), Scale(size.height, current_dpi_),
      nullptr, nullptr, ::GetModuleHandle(nullptr), this);
  if (!hwnd) {
    return false;
  }
  UpdateTheme(hwnd);
  return OnCreate();
}

bool Win32Window::Show() {
  return ::ShowWindow(window_handle_, SW_SHOWNORMAL);
}

void Win32Window::Destroy() {
  OnDestroy();
  if (window_handle_) {
    ::DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  ::GetClientRect(window_handle_, &frame);
  return frame;
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  ::SetParent(content, window_handle_);
  RECT frame = GetClientArea();
  ::MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
               frame.bottom - frame.top, true);
  ::SetFocus(child_content_);
}

bool Win32Window::OnCreate() { return true; }
void Win32Window::OnDestroy() {}

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message,
                                     WPARAM const wparam,
                                     LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      if (quit_on_close_) {
        ::PostQuitMessage(0);
      }
      return 0;
    case WM_SIZE: {
      RECT frame = GetClientArea();
      if (child_content_ != nullptr) {
        ::MoveWindow(child_content_, frame.left, frame.top,
                     frame.right - frame.left, frame.bottom - frame.top, TRUE);
      }
      return 0;
    }
    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        ::SetFocus(child_content_);
      }
      return 0;
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }
  return ::DefWindowProc(hwnd, message, wparam, lparam);
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      ::GetWindowLongPtr(window, GWLP_USERDATA));
}

LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message,
                                       WPARAM const wparam,
                                       LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    ::SetWindowLongPtr(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    auto* that = static_cast<Win32Window*>(cs->lpCreateParams);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}

void Win32Window::UpdateTheme(HWND const window) {
  BOOL dark_mode = TRUE;
  ::DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_mode,
                           sizeof(dark_mode));
}
