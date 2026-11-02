#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // When returning from system overlays like Win+V (Clipboard History), the
  // VK_LWIN/VK_RWIN key-up was consumed by the overlay, leaving Meta latched
  // in Flutter when the injected Ctrl+V arrives. Clear any physically released
  // Win key on reactivation / focus restore.
  if (flutter_controller_ &&
      ((message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE) ||
       message == WM_SETFOCUS)) {
    const int win_keys[2] = {VK_LWIN, VK_RWIN};
    for (const int vk : win_keys) {
      if ((static_cast<USHORT>(::GetAsyncKeyState(vk)) & 0x8000U) == 0U) {
        const UINT scan =
            ::MapVirtualKeyW(static_cast<UINT>(vk), MAPVK_VK_TO_VSC);
        const ULONG_PTR flags =
            1ULL | (static_cast<ULONG_PTR>(scan & 0xFFU) << 16) |
            (1ULL << 24) | (1ULL << 30) | (1ULL << 31);
        (void)flutter_controller_->HandleTopLevelWindowProc(
            hwnd, WM_KEYUP, static_cast<WPARAM>(vk),
            static_cast<LPARAM>(flags));
      }
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
