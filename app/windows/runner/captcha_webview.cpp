#include "captcha_webview.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <locale>
#include <sstream>
#include <string>

#include "third_party/webview2/include/WebView2.h"

namespace {

constexpr wchar_t kCaptchaWndClass[] = L"SilentGateCaptchaWebViewWnd";
constexpr UINT_PTR kTimerPoll = 101;
constexpr UINT_PTR kTimerReveal = 102;
constexpr UINT_PTR kTimerClickRelease = 103;
constexpr UINT_PTR kIdmOpenBrowser = 1001;

double ParseInvariantDouble(const std::wstring& s) {
  std::wistringstream iss(s);
  iss.imbue(std::locale::classic());
  double val = 0.0;
  iss >> val;
  return val;
}

std::wstring Utf8ToWide(const std::string& str) {
  if (str.empty()) return std::wstring();
  int count = MultiByteToWideChar(CP_UTF8, 0, str.c_str(),
                                  static_cast<int>(str.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.size()),
                      &out[0], count);
  return out;
}

template <typename CallbackInterface, typename Arg1, typename Arg2, typename Fn>
class WebViewCallback final : public CallbackInterface {
 public:
  explicit WebViewCallback(Fn fn) : ref_count_(1), fn_(std::move(fn)) {}
  virtual ~WebViewCallback() = default;

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** ppvObject) override {
    if (!ppvObject) return E_POINTER;
    if (riid == IID_IUnknown) {
      *ppvObject = static_cast<IUnknown*>(this);
      AddRef();
      return S_OK;
    }
    *ppvObject = static_cast<CallbackInterface*>(this);
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(++ref_count_);
  }

  ULONG STDMETHODCALLTYPE Release() override {
    ULONG count = static_cast<ULONG>(--ref_count_);
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT STDMETHODCALLTYPE Invoke(Arg1 a, Arg2 b) override {
    return fn_(a, b);
  }

 private:
  std::atomic<long> ref_count_;
  Fn fn_;
};

template <typename CallbackInterface, typename Arg1, typename Arg2, typename Fn>
CallbackInterface* MakeWebViewCallback(Fn fn) {
  return new WebViewCallback<CallbackInterface, Arg1, Arg2, Fn>(std::move(fn));
}

std::wstring GetCaptchaUserDataFolder() {
  wchar_t local_app_data[MAX_PATH] = {0};
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0,
                                 local_app_data))) {
    std::wstring path = local_app_data;
    path += L"\\SilentGate\\webview2-captcha";
    return path;
  }
  wchar_t temp_dir[MAX_PATH] = {0};
  GetTempPathW(MAX_PATH, temp_dir);
  std::wstring path = temp_dir;
  path += L"SilentGate-webview2-captcha";
  return path;
}

}  // namespace

struct CaptchaWebViewManager::Impl {
  explicit Impl(HWND parent) : parent_hwnd(parent) {}

  HWND parent_hwnd = nullptr;
  HWND hwnd = nullptr;
  HBRUSH bg_brush = nullptr;
  ICoreWebView2Environment* env = nullptr;
  ICoreWebView2Controller* controller = nullptr;
  ICoreWebView2* webview = nullptr;
  uint64_t session_id = 0;
  int poll_attempts = 0;
  bool clicked = false;
  bool revealed = false;
  bool is_support_mode = false;
  double pending_click_x = 0.0;
  double pending_click_y = 0.0;
  std::wstring current_url;

  void EnsureClassRegistered() {
    static bool registered = false;
    if (registered) return;
    bg_brush = CreateSolidBrush(RGB(22, 25, 34));
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.lpfnWndProc = &Impl::WndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = bg_brush;
    wc.lpszClassName = kCaptchaWndClass;
    wc.hIcon = LoadIconW(wc.hInstance, L"IDI_APP_ICON");
    RegisterClassExW(&wc);
    registered = true;
  }

  void ResizeWebView() {
    if (!controller || !hwnd) return;
    RECT bounds = {};
    GetClientRect(hwnd, &bounds);
    controller->put_Bounds(bounds);
  }

  void RevealWindow() {
    if (!hwnd || revealed) return;
    revealed = true;
    KillTimer(hwnd, kTimerReveal);

    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    ex &= ~(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    UINT dpi = GetDpiForWindow(hwnd);
    int w = MulDiv(is_support_mode ? 480 : 430, static_cast<int>(dpi), 96);
    int h = MulDiv(is_support_mode ? 680 : 540, static_cast<int>(dpi), 96);
    int x = 200;
    int y = 160;
    if (parent_hwnd && IsWindow(parent_hwnd)) {
      RECT pr = {};
      if (GetWindowRect(parent_hwnd, &pr)) {
        x = pr.left + ((pr.right - pr.left) - w) / 2;
        y = pr.top + ((pr.bottom - pr.top) - h) / 2;
      }
    }
    SetWindowPos(hwnd, HWND_TOP, x, y, w, h, SWP_SHOWWINDOW | SWP_FRAMECHANGED);
    ResizeWebView();
    ShowWindow(hwnd, SW_SHOWNORMAL);
    SetForegroundWindow(hwnd);
  }

  void DispatchCdpMouse(const char* type, double x, double y,
                        const char* button, int click_count) {
    if (!webview) return;
    int ix = static_cast<int>(std::lround(x));
    int iy = static_cast<int>(std::lround(y));
    char json[256];
    std::snprintf(
        json, sizeof(json),
        "{\"type\":\"%s\",\"x\":%d,\"y\":%d,\"button\":\"%s\","
        "\"buttons\":%d,\"clickCount\":%d}",
        type, ix, iy, button,
        (std::string(type) == "mousePressed") ? 1 : 0, click_count);
    std::wstring wjson = Utf8ToWide(json);
    auto* noop = MakeWebViewCallback<
        ICoreWebView2CallDevToolsProtocolMethodCompletedHandler, HRESULT, LPCWSTR>(
        [](HRESULT, LPCWSTR) -> HRESULT { return S_OK; });
    webview->CallDevToolsProtocolMethod(L"Input.dispatchMouseEvent",
                                        wjson.c_str(), noop);
    noop->Release();
  }

  void PollForCheckbox() {
    if (!webview || clicked || !hwnd) return;
    poll_attempts++;
    if (poll_attempts > 6) {
      KillTimer(hwnd, kTimerPoll);
      return;
    }

    const wchar_t* js = LR"JS(
      (function() {
        var sels = [
          '#not-robot-captcha-checkbox',
          '.CheckboxCaptcha-Button',
          '.CheckboxCaptcha-Anchor',
          'input[type="checkbox"]',
          '[data-testid*="checkbox"]'
        ];
        for (var i = 0; i < sels.length; i++) {
          var el = document.querySelector(sels[i]);
          if (el) {
            var r = el.getBoundingClientRect();
            if (r.width > 8 && r.height > 8) {
              var cx = r.left + r.width * 0.48;
              var cy = r.top + r.height * 0.52;
              return cx.toFixed(1) + ',' + cy.toFixed(1);
            }
          }
        }
        return '';
      })();
    )JS";

    uint64_t expected_sid = session_id;
    Impl* self = this;
    auto* handler =
        MakeWebViewCallback<ICoreWebView2ExecuteScriptCompletedHandler, HRESULT, LPCWSTR>(
            [self, expected_sid](HRESULT hr, LPCWSTR result_json) -> HRESULT {
              if (FAILED(hr) || !result_json ||
                  self->session_id != expected_sid || self->clicked ||
                  !self->webview) {
                return S_OK;
              }
              std::wstring res(result_json);
              // ExecuteScript returns JSON-quoted string like "\"124.5,210.0\""
              if (res.size() < 5 || res.front() != L'"' || res.back() != L'"') {
                return S_OK;
              }
              std::wstring inner = res.substr(1, res.size() - 2);
              size_t comma = inner.find(L',');
              if (comma == std::wstring::npos) return S_OK;

              double cx = ParseInvariantDouble(inner.substr(0, comma));
              double cy = ParseInvariantDouble(inner.substr(comma + 1));
              if (cx <= 5.0 || cy <= 5.0) return S_OK;

              self->clicked = true;
              if (self->hwnd) {
                KillTimer(self->hwnd, kTimerPoll);
              }

              // Smooth human-like approach + trusted CDP click
              double start_x = cx - 42.0;
              double start_y = cy + 28.0;
              for (int step = 1; step <= 4; ++step) {
                double t = static_cast<double>(step) / 4.0;
                double mx = start_x + (cx - start_x) * t;
                double my = start_y + (cy - start_y) * (t * t);
                self->DispatchCdpMouse("mouseMoved", mx, my, "none", 0);
              }
              self->pending_click_x = cx;
              self->pending_click_y = cy;
              self->DispatchCdpMouse("mousePressed", cx, cy, "left", 1);
              if (self->hwnd) {
                SetTimer(self->hwnd, kTimerClickRelease, 65, nullptr);
              }
              return S_OK;
            });
    webview->ExecuteScript(js, handler);
    handler->Release();
  }

  void OpenSupportModal() {
    if (!webview || !hwnd) return;
    const wchar_t* js = LR"JS(
      (function() {
        try {
          var modal = document.getElementById('support-modal');
          if (modal && !modal.classList.contains('is-open')) {
            var btn = document.getElementById('supFab') ||
                      document.querySelector('[data-modal-open="support-modal"]');
            if (btn) btn.click();
          }
        } catch (e) {}
      })();
    )JS";
    auto* noop = MakeWebViewCallback<
        ICoreWebView2ExecuteScriptCompletedHandler, HRESULT, LPCWSTR>(
        [](HRESULT, LPCWSTR) -> HRESULT { return S_OK; });
    webview->ExecuteScript(js, noop);
    noop->Release();
  }

  void CloseSession() {
    session_id++;
    clicked = false;
    revealed = false;
    is_support_mode = false;
    poll_attempts = 0;

    if (hwnd) {
      KillTimer(hwnd, kTimerPoll);
      KillTimer(hwnd, kTimerReveal);
      KillTimer(hwnd, kTimerClickRelease);
    }
    if (webview) {
      webview->Release();
      webview = nullptr;
    }
    if (controller) {
      controller->Close();
      controller->Release();
      controller = nullptr;
    }
    if (env) {
      env->Release();
      env = nullptr;
    }
    if (hwnd) {
      HWND to_destroy = hwnd;
      hwnd = nullptr;
      SetWindowLongPtrW(to_destroy, GWLP_USERDATA, 0);
      DestroyWindow(to_destroy);
    }
  }

  static LRESULT CALLBACK WndProc(HWND wnd, UINT msg, WPARAM wp, LPARAM lp) {
    Impl* self = reinterpret_cast<Impl*>(GetWindowLongPtrW(wnd, GWLP_USERDATA));
    switch (msg) {
      case WM_SIZE:
        if (self) self->ResizeWebView();
        return 0;
      case WM_TIMER:
        if (self) {
          if (wp == kTimerPoll) {
            self->PollForCheckbox();
          } else if (wp == kTimerReveal) {
            self->RevealWindow();
          } else if (wp == kTimerClickRelease) {
            KillTimer(wnd, kTimerClickRelease);
            self->DispatchCdpMouse("mouseReleased", self->pending_click_x,
                                   self->pending_click_y, "left", 1);
          }
        }
        return 0;
      case WM_SYSCOMMAND:
        if ((wp & 0xFFF0) == kIdmOpenBrowser && self &&
            !self->current_url.empty()) {
          std::wstring url_copy = self->current_url;
          self->CloseSession();
          ShellExecuteW(nullptr, L"open", url_copy.c_str(), nullptr, nullptr,
                        SW_SHOWNORMAL);
          return 0;
        }
        break;
      case WM_CLOSE:
        if (self) {
          self->CloseSession();
        } else {
          DestroyWindow(wnd);
        }
        return 0;
    }
    return DefWindowProcW(wnd, msg, wp, lp);
  }
};

CaptchaWebViewManager::CaptchaWebViewManager(HWND parent_hwnd)
    : impl_(std::make_unique<Impl>(parent_hwnd)) {}

CaptchaWebViewManager::~CaptchaWebViewManager() { Close(); }

void CaptchaWebViewManager::Close() {
  if (impl_) {
    impl_->CloseSession();
  }
}

void CaptchaWebViewManager::RegisterChannel(
    flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lol.silentgate/captcha",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "close") {
          Close();
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() != "open") {
          result->NotImplemented();
          return;
        }

        std::string url;
        std::string title = "SilentGate — Подтверждение";
        std::string mode = "captcha";
        if (const auto* map =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto it_url = map->find(flutter::EncodableValue("url"));
          if (it_url != map->end()) {
            if (const auto* s = std::get_if<std::string>(&it_url->second)) {
              url = *s;
            }
          }
          auto it_title = map->find(flutter::EncodableValue("title"));
          if (it_title != map->end()) {
            if (const auto* s = std::get_if<std::string>(&it_title->second)) {
              if (!s->empty()) title = *s;
            }
          }
          auto it_mode = map->find(flutter::EncodableValue("mode"));
          if (it_mode != map->end()) {
            if (const auto* s = std::get_if<std::string>(&it_mode->second)) {
              if (!s->empty()) mode = *s;
            }
          }
        }

        if (url.empty()) {
          result->Success(flutter::EncodableValue(false));
          return;
        }

        // Check if Microsoft Edge WebView2 Runtime is installed on this PC.
        LPWSTR version_info = nullptr;
        HRESULT ver_hr =
            GetAvailableCoreWebView2BrowserVersionString(nullptr, &version_info);
        if (version_info) {
          CoTaskMemFree(version_info);
        }
        if (FAILED(ver_hr)) {
          // Clean fallback to external browser on stripped Windows ISOs.
          result->Success(flutter::EncodableValue(false));
          return;
        }

        impl_->CloseSession();
        impl_->EnsureClassRegistered();
        impl_->is_support_mode = (mode == "support");

        uint64_t current_sid = ++impl_->session_id;
        std::wstring wtitle = Utf8ToWide(title);
        std::wstring wurl = Utf8ToWide(url);
        impl_->current_url = wurl;

        // Start off-screen & nearly transparent (alpha=1) with NOACTIVATE so
        // Chromium renders and accepts trusted CDP clicks for 2.6s without
        // flashing any popup if checkbox auto-solves!
        HWND wnd = CreateWindowExW(
            WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
            kCaptchaWndClass, wtitle.c_str(),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, -32000, -32000, 420, 520,
            impl_->parent_hwnd, nullptr, GetModuleHandleW(nullptr), nullptr);
        if (!wnd) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
        if (HMENU sys_menu = GetSystemMenu(wnd, FALSE)) {
          AppendMenuW(sys_menu, MF_SEPARATOR, 0, nullptr);
          AppendMenuW(sys_menu, MF_STRING, kIdmOpenBrowser,
                      L"Открыть в обычном браузере");
        }

        BOOL dark_mode = TRUE;
        DwmSetWindowAttribute(wnd, 20 /*DWMWA_USE_IMMERSIVE_DARK_MODE*/,
                              &dark_mode, sizeof(dark_mode));
        SetLayeredWindowAttributes(wnd, 0, 1, LWA_ALPHA);
        SetWindowLongPtrW(wnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(impl_.get()));
        ShowWindow(wnd, SW_SHOWNOACTIVATE);
        impl_->hwnd = wnd;
        if (impl_->is_support_mode) {
          impl_->RevealWindow();
        }

        auto shared_result = std::shared_ptr<
            flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
        Impl* raw_impl = impl_.get();
        std::wstring udf = GetCaptchaUserDataFolder();

        auto* env_handler = MakeWebViewCallback<
            ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler, HRESULT, ICoreWebView2Environment*>(
            [raw_impl, current_sid, wurl,
             shared_result](HRESULT env_hr,
                            ICoreWebView2Environment* created_env) -> HRESULT {
              if (raw_impl->session_id != current_sid || !raw_impl->hwnd) {
                if (shared_result) {
                  shared_result->Success(flutter::EncodableValue(false));
                }
                return S_OK;
              }
              if (FAILED(env_hr) || !created_env) {
                raw_impl->CloseSession();
                if (shared_result) {
                  shared_result->Success(flutter::EncodableValue(false));
                }
                return S_OK;
              }

              created_env->AddRef();
              raw_impl->env = created_env;

              auto* ctrl_handler = MakeWebViewCallback<
                  ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, HRESULT, ICoreWebView2Controller*>(
                  [raw_impl, current_sid, wurl, shared_result](
                      HRESULT ctrl_hr,
                      ICoreWebView2Controller* created_ctrl) -> HRESULT {
                    if (raw_impl->session_id != current_sid || !raw_impl->hwnd) {
                      if (created_ctrl) created_ctrl->Close();
                      if (shared_result) {
                        shared_result->Success(flutter::EncodableValue(false));
                      }
                      return S_OK;
                    }
                    if (FAILED(ctrl_hr) || !created_ctrl) {
                      raw_impl->CloseSession();
                      if (shared_result) {
                        shared_result->Success(flutter::EncodableValue(false));
                      }
                      return S_OK;
                    }

                    created_ctrl->AddRef();
                    raw_impl->controller = created_ctrl;
                    created_ctrl->put_IsVisible(TRUE);
                    raw_impl->ResizeWebView();

                    ICoreWebView2* wv = nullptr;
                    if (FAILED(created_ctrl->get_CoreWebView2(&wv)) || !wv) {
                      raw_impl->CloseSession();
                      if (shared_result) {
                        shared_result->Success(flutter::EncodableValue(false));
                      }
                      return S_OK;
                    }
                    raw_impl->webview = wv;

                    ICoreWebView2Settings* settings = nullptr;
                    if (SUCCEEDED(wv->get_Settings(&settings)) && settings) {
                      settings->put_AreDefaultContextMenusEnabled(FALSE);
                      settings->put_AreDevToolsEnabled(FALSE);
                      settings->put_IsStatusBarEnabled(FALSE);
                      settings->Release();
                    }

                    EventRegistrationToken nav_token = {};
                    auto* nav_handler = MakeWebViewCallback<
                        ICoreWebView2NavigationCompletedEventHandler, ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs*>(
                        [raw_impl, current_sid](
                            ICoreWebView2*,
                            ICoreWebView2NavigationCompletedEventArgs*)
                            -> HRESULT {
                          if (raw_impl->session_id == current_sid &&
                              raw_impl->hwnd) {
                            if (raw_impl->is_support_mode) {
                              raw_impl->OpenSupportModal();
                            } else if (!raw_impl->clicked) {
                              SetTimer(raw_impl->hwnd, kTimerPoll, 420, nullptr);
                            }
                          }
                          return S_OK;
                        });
                    wv->add_NavigationCompleted(nav_handler, &nav_token);
                    nav_handler->Release();

                    if (!raw_impl->is_support_mode) {
                      SetTimer(raw_impl->hwnd, kTimerReveal, 2600, nullptr);
                    }
                    wv->Navigate(wurl.c_str());

                    if (shared_result) {
                      shared_result->Success(flutter::EncodableValue(true));
                    }
                    return S_OK;
                  });

              created_env->CreateCoreWebView2Controller(raw_impl->hwnd,
                                                        ctrl_handler);
              ctrl_handler->Release();
              return S_OK;
            });

        HRESULT start_hr = CreateCoreWebView2EnvironmentWithOptions(
            nullptr, udf.c_str(), nullptr, env_handler);
        env_handler->Release();
        if (FAILED(start_hr)) {
          impl_->CloseSession();
          shared_result->Success(flutter::EncodableValue(false));
        }
      });
}
