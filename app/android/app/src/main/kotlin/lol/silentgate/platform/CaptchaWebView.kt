package lol.silentgate.platform

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

/**
 * Встроенное окно прохождения капчи ВК (Вариант Б):
 *
 * 1. Открывает локальный loopback-прокси `http://127.0.0.1:<port>/` внутри
 *    системного [WebView] (0 МБ сторонних библиотек в APK, 0 МБ в простое).
 * 2. Первые 2.6 секунды диалог полностью прозрачен (`alpha = 0.01f`) и не
 *    перехватывает касания (`FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`), пока
 *    Chromium рендерит чекбокс `#not-robot-captcha-checkbox` и получает
 *    настоящее системное касание [MotionEvent] (`event.isTrusted === true`).
 * 3. Если ВК сразу выдаёт `success_token`, Dart получает `STATUS:CAPTCHA_SOLVED`
 *    и вызывает `close` — [WebView] уничтожается (`destroy()`), а пользователь
 *    даже не видит всплывающего окна и не уходит в браузер.
 * 4. Если через 2.6 с токен ещё не получен (например, ВК запросил слайдер-пазл),
 *    уже загруженное компактное окно плавно проявляется поверх SilentGate
 *    (с кнопкой запасного открытия во внешнем браузере) и само закрывается
 *    сразу после решения.
 * 5. Если Activity свёрнута или на прошивке вырезан системный WebView
 *    (de-Googled ROM), возвращает `false`, и Dart автоматически открывает
 *    ссылку через штатный внешний браузер.
 */
object CaptchaWebView {
    const val CHANNEL = "lol.silentgate/captcha"

    private val main = Handler(Looper.getMainLooper())
    private var activityRef: WeakReference<Activity>? = null
    private var dialog: Dialog? = null
    private var webView: WebView? = null
    private var sessionSeq: Long = 0
    private var clickedInSession = false

    fun attach(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    fun detach(activity: Activity) {
        if (activityRef?.get() === activity) {
            closeInternal()
            activityRef = null
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                val url = call.argument<String>("url")?.trim().orEmpty()
                val title = call.argument<String>("title")?.trim()
                    ?.takeIf { it.isNotEmpty() } ?: "Подтверждение"
                val mode = call.argument<String>("mode")?.trim().orEmpty()
                main.post {
                    result.success(openInternal(url, title, isSupport = mode == "support"))
                }
            }
            "close" -> {
                main.post {
                    closeInternal()
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun openInternal(url: String, title: String, isSupport: Boolean = false): Boolean {
        if (url.isEmpty()) return false
        val activity = activityRef?.get() ?: return false
        if (activity.isFinishing || activity.isDestroyed) return false

        closeInternal()
        val mySeq = ++sessionSeq
        clickedInSession = false

        val wv = try {
            WebView(activity)
        } catch (_: Throwable) {
            // На прошивках без пакета Android System WebView — честный откат в браузер.
            return false
        }

        return try {
            CookieManager.getInstance().apply {
                setAcceptCookie(true)
                setAcceptThirdPartyCookies(wv, true)
            }

            wv.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = false
                allowFileAccess = false
                allowContentAccess = false
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                // Убираем маркер "; wv", чтобы антибот видел обычный мобильный Chrome.
                userAgentString = userAgentString
                    .replace("; wv)", ")")
                    .replace(Regex("""\sVersion/\d+\.\d+\s"""), " ")
            }
            wv.setBackgroundColor(Color.parseColor("#161922"))

            val density = activity.resources.displayMetrics.density
            fun dp(v: Int): Int = (v * density).roundToInt()

            val rootCard = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#161922"))
                    cornerRadius = dp(16).toFloat()
                    setStroke(dp(1), Color.parseColor("#2A3042"))
                }
                clipToOutline = true
            }

            val header = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(10), dp(10), dp(10))
                setBackgroundColor(Color.parseColor("#1D2230"))
            }

            val titleView = TextView(activity).apply {
                text = title
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }

            val browserBtn = TextView(activity).apply {
                text = "В браузере"
                setTextColor(Color.parseColor("#8AB4F8"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(dp(10), dp(6), dp(10), dp(6))
                setOnClickListener {
                    runCatching {
                        activity.startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                    closeInternal()
                }
            }

            val closeBtn = TextView(activity).apply {
                text = "✕"
                setTextColor(Color.parseColor("#9AA0A6"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setPadding(dp(10), dp(4), dp(8), dp(4))
                setOnClickListener { closeInternal() }
            }

            header.addView(titleView)
            header.addView(browserBtn)
            header.addView(closeBtn)

            val webContainer = FrameLayout(activity).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(if (isSupport) 520 else 430),
                )
            }
            webContainer.addView(
                wv,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )

            rootCard.addView(header)
            rootCard.addView(webContainer)

            val dlg = Dialog(activity).apply {
                requestWindowFeature(Window.FEATURE_NO_TITLE)
                setContentView(rootCard)
                setCanceledOnTouchOutside(false)
                setOnDismissListener {
                    if (sessionSeq == mySeq) {
                        destroyWebViewOnly()
                    }
                }
            }

            dlg.window?.apply {
                setBackgroundDrawableResource(android.R.color.transparent)
                // Скрытая фаза (2.6 с): окно не видно и не перехватывает ввод,
                // но WebView полноценно рендерит DOM и принимает trusted MotionEvent!
                clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                addFlags(
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                )
                attributes = attributes.also { lp ->
                    lp.width = (activity.resources.displayMetrics.widthPixels * 0.92f)
                        .roundToInt()
                        .coerceAtMost(dp(400))
                    lp.height = ViewGroup.LayoutParams.WRAP_CONTENT
                    lp.alpha = 0.01f
                }
            }

            wv.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                    super.onPageFinished(view, loadedUrl)
                    if (isSupport) {
                        view?.evaluateJavascript(
                            """
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
                            """.trimIndent(),
                            null,
                        )
                    } else {
                        scheduleCheckboxProbes(mySeq)
                    }
                }
            }

            webView = wv
            dialog = dlg
            dlg.show()
            wv.loadUrl(url)

            if (isSupport) {
                revealDialog()
            } else {
                // Если за 2.6 с чекбокс сам не закрыл капчу (например, выпал пазл),
                // плавно показываем уже загруженное окно пользователю.
                main.postDelayed({
                    if (sessionSeq == mySeq) {
                        revealDialog()
                    }
                }, 2600L)
            }

            true
        } catch (_: Throwable) {
            closeInternal()
            false
        }
    }

    private fun scheduleCheckboxProbes(seq: Long) {
        val delays = longArrayOf(350L, 850L, 1450L, 2050L)
        for (d in delays) {
            main.postDelayed({
                if (sessionSeq == seq && !clickedInSession) {
                    probeAndTapCheckbox(seq)
                }
            }, d)
        }
    }

    private fun probeAndTapCheckbox(seq: Long) {
        val wv = webView ?: return
        if (sessionSeq != seq || clickedInSession) return

        val js = """
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
        """.trimIndent()

        wv.evaluateJavascript(js) { raw ->
            if (sessionSeq != seq || clickedInSession || raw.isNullOrBlank()) return@evaluateJavascript
            val cleaned = raw.trim().removeSurrounding("\"")
            val parts = cleaned.split(',')
            if (parts.size != 2) return@evaluateJavascript
            val cssX = parts[0].toFloatOrNull() ?: return@evaluateJavascript
            val cssY = parts[1].toFloatOrNull() ?: return@evaluateJavascript
            if (cssX <= 4f || cssY <= 4f) return@evaluateJavascript

            val targetView = webView ?: return@evaluateJavascript
            @Suppress("DEPRECATION")
            val scale = targetView.scale.takeIf { it > 0.1f }
                ?: targetView.resources.displayMetrics.density
            val vx = cssX * scale
            val vy = cssY * scale

            clickedInSession = true
            dispatchTrustedTap(targetView, vx, vy, seq)
        }
    }

    private fun dispatchTrustedTap(view: WebView, x: Float, y: Float, seq: Long) {
        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(
            downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0
        )
        view.dispatchTouchEvent(down)
        down.recycle()

        main.postDelayed({
            if (sessionSeq != seq || webView !== view) return@postDelayed
            val moveTime = SystemClock.uptimeMillis()
            val move = MotionEvent.obtain(
                downTime, moveTime, MotionEvent.ACTION_MOVE, x + 1.2f, y + 0.8f, 0
            )
            view.dispatchTouchEvent(move)
            move.recycle()
        }, 28L)

        main.postDelayed({
            if (sessionSeq != seq || webView !== view) return@postDelayed
            val upTime = SystemClock.uptimeMillis()
            val up = MotionEvent.obtain(
                downTime, upTime, MotionEvent.ACTION_UP, x + 1.2f, y + 0.8f, 0
            )
            view.dispatchTouchEvent(up)
            up.recycle()
        }, 68L)
    }

    private fun revealDialog() {
        val dlg = dialog ?: return
        if (!dlg.isShowing) return
        dlg.window?.apply {
            clearFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            )
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setDimAmount(0.58f)
            attributes = attributes.also { lp ->
                lp.alpha = 1.0f
            }
        }
    }

    private fun destroyWebViewOnly() {
        val wv = webView
        webView = null
        dialog = null
        if (wv != null) {
            runCatching {
                (wv.parent as? ViewGroup)?.removeView(wv)
                wv.stopLoading()
                wv.loadUrl("about:blank")
                wv.clearHistory()
                wv.removeAllViews()
                wv.destroy()
            }
        }
    }

    fun closeInternal() {
        sessionSeq++
        clickedInSession = false
        val dlg = dialog
        dialog = null
        if (dlg != null) {
            runCatching {
                if (dlg.isShowing) dlg.dismiss()
            }
        }
        destroyWebViewOnly()
    }
}
