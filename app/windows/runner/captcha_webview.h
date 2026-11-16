#ifndef RUNNER_CAPTCHA_WEBVIEW_H_
#define RUNNER_CAPTCHA_WEBVIEW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

class CaptchaWebViewManager {
 public:
  explicit CaptchaWebViewManager(HWND parent_hwnd);
  ~CaptchaWebViewManager();

  CaptchaWebViewManager(const CaptchaWebViewManager&) = delete;
  CaptchaWebViewManager& operator=(const CaptchaWebViewManager&) = delete;

  void RegisterChannel(flutter::BinaryMessenger* messenger);
  void Close();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_CAPTCHA_WEBVIEW_H_
