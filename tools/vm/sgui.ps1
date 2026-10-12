# Оснастка для проверки интерфейса ВНУТРИ гостя SG-Test.
#
# Зачем: через PowerShell Direct мы попадаем в СЕССИЮ 0, где окна нет вовсе —
# ни нажать, ни снять. Поэтому скрипт запускается задачей Планировщика с
# /RU <user> /IT (⚠️ БЕЗ /RP: пароль вместе с /IT делает задачу нерабочей,
# и schtasks /Run отвечает «Элемент не найден»), то есть в интерактивной
# сессии 1, где окно есть и курсор существует.
#
# Команды задаются файлом sgui.cmd рядом со скриптом, по одной на строку:
#   shot                — снять окно приложения в sgui.png
#   click <x> <y>       — щёлкнуть по КЛИЕНТСКОЙ координате окна
#   key <VK>            — послать код клавиши (десятичный VK)
#   wait <мс>           — подождать
# Итог работы пишется в sgui.log.

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $dir 'sgui.log'
function Say($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding UTF8 }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SgUi {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  // ⚠️ SendInput, а НЕ mouse_event. Устаревший mouse_event доходит до окна
  // как движение (подсветка наведения появлялась), но нажатие Flutter не
  // видел вовсе. SendInput — единственный документированный способ вложить
  // ввод в очередь так, чтобы приложение не отличало его от настоящего.
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
    public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra;
  }
  // ⚠️ БЕЗ ЛИШНИХ ПОЛЕЙ. Здесь стояли два int «для выравнивания», и структура
  // вырастала до 48 байт вместо 40; SendInput сверяет размер и молча
  // отказывает — возвращает 0, ничего не сообщая. Настоящий INPUT на x64 —
  // ровно 40 байт: type(4) + выравнивание(4) + MOUSEINPUT(32).
  [StructLayout(LayoutKind.Sequential)] public struct INPUT {
    public uint type; public MOUSEINPUT mi;
  }
  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint n, INPUT[] p, int size);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);

  public static uint Click(int sx, int sy) {
    int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
    // Абсолютные координаты SendInput нормированы на 0..65535 по всему экрану.
    int ax = (int)((sx * 65535.0) / (w - 1));
    int ay = (int)((sy * 65535.0) / (h - 1));
    INPUT[] a = new INPUT[3];
    for (int i = 0; i < 3; i++) { a[i].type = 0; a[i].mi.dx = ax; a[i].mi.dy = ay; }
    a[0].mi.dwFlags = 0x8000 | 0x0001;  // ABSOLUTE | MOVE
    a[1].mi.dwFlags = 0x8000 | 0x0002;  // ABSOLUTE | LEFTDOWN
    a[2].mi.dwFlags = 0x8000 | 0x0004;  // ABSOLUTE | LEFTUP
    return SendInput(3, a, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@

function Find-AppWindow {
  # ⚠️ Перебором EnumWindows, а НЕ через MainWindowHandle: у окна Flutter он
  # бывает нулевым, и «окно не найдено» тогда означает лишь неудачный способ
  # спросить.
  #
  # $Name — имя процесса. Умолчание «silentgate», но снимать нужно и чужие окна:
  # диалог установщика при активном VPN проверяется только так.
  # $MinW/$MinH — порог отсева служебных окон. У Flutter их несколько нулевого
  # размера, зато диалог установщика заметно меньше главного окна, и жёсткие
  # 300×300 отсеяли бы как раз его.
  param(
    [string]$Name = 'silentgate',
    [int]$MinW = 300,
    [int]$MinH = 300
  )
  $procs = Get-Process $Name -ErrorAction SilentlyContinue
  if (-not $procs) { return [IntPtr]::Zero }
  $pids = @($procs | ForEach-Object { [uint32]$_.Id })
  # ⚠️ Именно $script:, и именно с инициализацией. Колбэк EnumWindows живёт в
  # своей области видимости: локальная переменная, присвоенная внутри него,
  # наружу не выходит. Без этой строки функция возвращала $null (а не нулевой
  # указатель), и сравнение с [IntPtr]::Zero падало на приведении типа.
  $script:found = [IntPtr]::Zero
  $cb = [SgUi+EnumProc] {
    param($h, $p)
    $pid2 = 0
    [void][SgUi]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pids -contains $pid2 -and [SgUi]::IsWindowVisible($h)) {
      $r = New-Object SgUi+RECT
      [void][SgUi]::GetClientRect($h, [ref]$r)
      # Отсекаем служебные окна нулевого размера: у Flutter их несколько.
      if (($r.R - $r.L) -gt $MinW -and ($r.B - $r.T) -gt $MinH) { $script:found = $h; return $false }
    }
    return $true
  }
  [void][SgUi]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:found
}

try {
  $h = Find-AppWindow
  if (-not $h -or $h -eq [IntPtr]::Zero) { Say 'ОКНО НЕ НАЙДЕНО (приложение свёрнуто в трей или не запущено)'; exit 2 }
  # Приложение сворачивается в трей — поднимаем перед любой работой.
  [void][SgUi]::ShowWindow($h, 9)   # SW_RESTORE
  [void][SgUi]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 700

  # ⚠️ ВПИСАТЬ ОКНО В ЭКРАН — ИНАЧЕ НАЖАТИЯ НЕ ДОХОДЯТ, А СНИМКИ ВРУТ.
  #
  # Экран гостя 1024x768, а окно приложения шире и стоит со сдвигом вправо:
  # его правая половина физически вне экрана. `PrintWindow` этого не замечает —
  # он рисует окно из его собственного буфера, — поэтому снимок выходил
  # правильный, а клик по правой части упирался в границу экрана: курсор за
  # её пределы не уходит, и SetCursorPos молча приводит координату к краю.
  # Симптом: щелчок «прошёл», а на экране ничего не изменилось.
  Add-Type -AssemblyName System.Windows.Forms
  $scr = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $wr = New-Object SgUi+RECT
  [void][SgUi]::GetWindowRect($h, [ref]$wr)
  if ($wr.L -lt 0 -or $wr.T -lt 0 -or $wr.R -gt $scr.Width -or $wr.B -gt $scr.Height) {
    [void][SgUi]::MoveWindow($h, 0, 0, $scr.Width, $scr.Height, $true)
    Start-Sleep -Milliseconds 600
    Say "окно вписано в экран $($scr.Width)x$($scr.Height) (было $($wr.L),$($wr.T)-$($wr.R),$($wr.B))"
  }

  $cmdFile = Join-Path $dir 'sgui.cmd'
  $cmds = if (Test-Path $cmdFile) { Get-Content $cmdFile } else { @('shot') }

  foreach ($line in $cmds) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    $a = $t -split '\s+'
    switch ($a[0].ToLower()) {
      'wait' { Start-Sleep -Milliseconds ([int]$a[1]); Say "wait $($a[1])" }
      # Текст буфера обмена сессии 1 — в журнал. Нужен проверкам «Экспорт
      # скопировал?»: из сессии 0 (PowerShell Direct) буфер сессии 1 не виден.
      'clip' {
        try { $c = Get-Clipboard -Raw -ErrorAction Stop } catch { $c = "<ошибка: $_>" }
        if ($null -eq $c) { $c = '<пусто>' }
        Say ("clip [{0}]: {1}" -f $c.Length, $c)
      }
      # Записать текст в буфер обмена сессии 1 (остаток строки — как есть).
      'setclip' {
        $txt = $t.Substring(7).Trim()
        Set-Clipboard -Value $txt
        Say ("setclip [{0}]" -f $txt.Length)
      }
      'key' {
        [SgUi]::keybd_event([byte][int]$a[1], 0, 0, [IntPtr]::Zero)
        [SgUi]::keybd_event([byte][int]$a[1], 0, 2, [IntPtr]::Zero)
        Say "key $($a[1])"
      }
      'click' {
        # ⚠️ КООРДИНАТЫ — ОКОННЫЕ, ТЕ ЖЕ, ЧТО НА СНИМКЕ. Здесь стояло
        # `ClientToScreen`, и клик уезжал на высоту заголовка вниз: снимок
        # делает `PrintWindow`, а он рисует окно ЦЕЛИКОМ — вместе с заголовком
        # и рамкой — в холст клиентского размера. То есть пиксель (x,y) на
        # картинке отсчитывается от угла ОКНА, а не клиентской области.
        # Считать их клиентскими значит промахиваться на каждый клик, причём
        # молча: курсор встаёт куда просили, окно на переднем плане, а нажатие
        # приходится на пустое место чуть ниже цели.
        $wr2 = New-Object SgUi+RECT
        [void][SgUi]::GetWindowRect($h, [ref]$wr2)
        $p = New-Object SgUi+POINT
        $p.X = $wr2.L + [int]$a[1]; $p.Y = $wr2.T + [int]$a[2]
        [void][SgUi]::SetCursorPos($p.X, $p.Y)
        Start-Sleep -Milliseconds 120
        # ⚠️ Диагностика ОБЯЗАТЕЛЬНА: «щёлкнул» и «щелчок дошёл» — разные
        # утверждения, и в журнале до этого стояло только первое. Курсор мог
        # быть приведён к краю экрана, а окно — не быть на переднем плане.
        $act = New-Object SgUi+POINT
        [void][SgUi]::GetCursorPos([ref]$act)
        $fg = [SgUi]::GetForegroundWindow()
        Say "курсор просили $($p.X),$($p.Y), встал $($act.X),$($act.Y); переднее окно $fg, наше $h"
        $sent = [SgUi]::Click($p.X, $p.Y)
        Say "click $($a[1]),$($a[2]) -> экран $($p.X),$($p.Y); SendInput принял событий: $sent из 3"
        Start-Sleep -Milliseconds 400
      }
      'shot' {
        # ⚠️ ОКОННЫЙ прямоугольник, а НЕ клиентский, и это не придирка.
        # `PrintWindow` рисует окно ЦЕЛИКОМ — вместе с заголовком и рамкой.
        # Пока холст брался по `GetClientRect`, каждый снимок терял нижние
        # ~31 px (высоту заголовка), и обрезанная последняя строка выглядела
        # как дефект вёрстки. 10.09.2026 на этом чуть не завели ложную находку
        # про «низ главного экрана снова не влезает».
        $r = New-Object SgUi+RECT
        [void][SgUi]::GetWindowRect($h, [ref]$r)
        $w = $r.R - $r.L; $ht = $r.B - $r.T
        $bmp = New-Object System.Drawing.Bitmap($w, $ht)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $dc = $g.GetHdc()
        # flags=2 (PW_RENDERFULLCONTENT): без него окна с аппаратной
        # отрисовкой (а Flutter именно такое) выходят пустыми.
        $ok = [SgUi]::PrintWindow($h, $dc, 2)
        $g.ReleaseHdc($dc); $g.Dispose()
        $out = Join-Path $dir 'sgui.png'
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Say "shot ${w}x${ht} PrintWindow=$ok -> $out"
      }
      'resize' {
        # `resize <ширина> <высота>` — задать РАЗМЕР ОКНА (не клиентской
        # области). Нужно, чтобы снимать вёрстку на минимальном окне 980×800:
        # именно на нём владелец и видит, что низ прячется, а окно по
        # умолчанию 1040×820 эту беду скрывает.
        $wr3 = New-Object SgUi+RECT
        [void][SgUi]::GetWindowRect($h, [ref]$wr3)
        [void][SgUi]::MoveWindow($h, $wr3.L, $wr3.T, [int]$a[1], [int]$a[2], $true)
        Start-Sleep -Milliseconds 700
        $wr4 = New-Object SgUi+RECT
        [void][SgUi]::GetWindowRect($h, [ref]$wr4)
        Say "resize $($a[1])x$($a[2]) -> вышло $($wr4.R - $wr4.L)x$($wr4.B - $wr4.T)"
      }
      'cmdid' {
        # ⚠️ САМЫЙ НАДЁЖНЫЙ СПОСОБ НАЖАТЬ КНОПКУ ДИАЛОГА — послать ему код
        # результата, а не искать окно кнопки и не двигать мышь.
        # Мышь и клавиатура в госте без VMConnect не доходят вовсе (рабочий
        # стол блокировки), а перечисление детей у диалога Inno возвращает
        # пусто. `WM_COMMAND` с идентификатором работает и там, и там.
        # Коды: 1=ОК, 2=Отмена, 6=Да, 7=Нет, 100+ — кнопки TaskDialog.
        $id = [int]$a[1]
        [void][SgUi]::SendMessage($h, 0x0111, [IntPtr]$id, [IntPtr]::Zero)  # WM_COMMAND
        Say "cmdid $id -> отправлено WM_COMMAND"
        Start-Sleep -Milliseconds 600
      }
      'press' {
        # ⚠️ НАЖАТИЕ СООБЩЕНИЕМ, А НЕ МЫШЬЮ — И ЭТО НЕ УДОБСТВО.
        # 10.09.2026 выяснилось: в госте без подключённого VMConnect сеанс
        # держит рабочий стол блокировки, и НИ `SendInput`, НИ `keybd_event`
        # до окон не доходят — при том что `PrintWindow` снимает их прекрасно.
        # Выглядит это молча: журнал говорит «SendInput принял 3 из 3», а на
        # экране ничего не меняется. `BM_CLICK` идёт прямо окну кнопки и от
        # фокуса ввода не зависит вовсе.
        #
        # Ищем среди ПРЯМЫХ детей окна кнопку, чья подпись содержит заданный
        # текст (амперсанды подчёркивания в подписях выкидываем).
        $want = ($a[1..($a.Count-1)] -join ' ')
        $child = [IntPtr]::Zero
        $hit = [IntPtr]::Zero
        $seen = @()
        while ($true) {
          $child = [SgUi]::FindWindowEx($h, $child, $null, $null)
          if ($child -eq [IntPtr]::Zero) { break }
          $sb = New-Object System.Text.StringBuilder 256
          [void][SgUi]::GetWindowText($child, $sb, 256)
          $txt = $sb.ToString().Replace('&','')
          $cb = New-Object System.Text.StringBuilder 128
          [void][SgUi]::GetClassName($child, $cb, 128)
          if ($txt) { $seen += "$($cb.ToString()):$txt" }
          if ($txt -and $txt -like "*$want*") { $hit = $child; break }
        }
        if ($hit -eq [IntPtr]::Zero) {
          Say "press '$want' -> КНОПКА НЕ НАЙДЕНА; на окне есть: $($seen -join ' | ')"
        } else {
          [void][SgUi]::SendMessage($hit, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)  # BM_CLICK
          Say "press '$want' -> отправлено BM_CLICK"
        }
        Start-Sleep -Milliseconds 500
      }
      'use' {
        # Переключить окно: `use <имя процесса>`. Порог размера снижен —
        # диалоги заметно меньше главного окна.
        $nm = if ($a.Count -gt 1) { $a[1] } else { 'silentgate' }
        # Порог можно задать: `use <имя> <minW> <minH>`. Диалог «закрыть
        # приложение?» у Inno меньше 200×100, и умолчание его отсеивало.
        $mw = if ($a.Count -gt 2) { [int]$a[2] } else { 200 }
        $mh = if ($a.Count -gt 3) { [int]$a[3] } else { 100 }
        $h2 = Find-AppWindow -Name $nm -MinW $mw -MinH $mh
        if (-not $h2 -or $h2 -eq [IntPtr]::Zero) { Say "use $nm -> ОКНО НЕ НАЙДЕНО" }
        else { $h = $h2; [void][SgUi]::ShowWindow($h, 9); [void][SgUi]::SetForegroundWindow($h); Say "use $nm -> окно найдено" }
      }
      default { Say "неизвестная команда: $t" }
    }
  }
  Say 'готово'
  exit 0
} catch {
  Say "СБОЙ: $($_.Exception.Message)"
  exit 1
}
