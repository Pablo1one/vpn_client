#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <functional>
#include <memory>
#include <string>

class Win32Window {
 public:
  struct Point { unsigned int x, y; Point(unsigned int x, unsigned int y) : x(x), y(y) {} };
  struct Size  { unsigned int width, height; Size(unsigned int w, unsigned int h) : width(w), height(h) {} };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring& title, const Point& origin, const Size& size);
  bool Show();
  void Destroy();
  HWND GetHandle();
  void SetQuitOnClose(bool quit_on_close);
  RECT GetClientArea();

 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();
  void SetChildContent(HWND content);
  virtual LRESULT MessageHandler(HWND window, UINT const message,
                                  WPARAM const wparam, LPARAM const lparam) noexcept;

 private:
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;
  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                   WPARAM const wparam, LPARAM const lparam) noexcept;
  void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
