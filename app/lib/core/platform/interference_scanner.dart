import 'dart:io';

import '../../engine/windows/elevation.dart';
import '../../engine/windows/process_list_windows.dart';

class Interference {
  final String kind; // 'adapter' | 'process' | 'proxy'
  final String name;
  final String detail;
  final int? pid; // для процессов — чтобы можно было закрыть

  /// Приложение, которому принадлежит помеха, если его удалось опознать.
  ///
  /// У адаптера имя вроде «wintun» ничего не говорит пользователю: закрывать он
  /// будет не адаптер, а программу. Пусто — опознать не вышло, и тогда честнее
  /// не предлагать кнопку «закрыть», чем закрыть не то.
  final String? appName;
  final String? appPath;

  const Interference(this.kind, this.name, this.detail,
      {this.pid, this.appName, this.appPath});

  /// Можно ли предложить пользователю закрыть виновника.
  bool get closable => pid != null && (appName ?? '').isNotEmpty;
}

/// Обнаружение других VPN и вмешательств в сеть (чужие TUN-адаптеры, процессы VPN, zapret),
/// которые могут конфликтовать с SilentGate. Свои процессы/адаптер исключаются.
class InterferenceScanner {
  // Только АКТИВНЫЕ помехи (DPI-инструменты, реально вмешивающиеся в трафик). Обычные VPN-клиенты
  // сами по себе не мешают — их влияние ловим по активному TUN-адаптеру и системному прокси.
  static const _dpiProcNames = <String, String>{
    'winws.exe': 'zapret (winws)',
    'goodbyedpi.exe': 'GoodbyeDPI',
    'winws1.exe': 'zapret (winws)',
  };

  static Future<List<Interference>> scan() async {
    final result = <Interference>[];
    result.addAll(await _scanAdapters());
    result.addAll(_scanProcesses());
    result.addAll(await _scanProxy());
    return result;
  }

  static List<Interference> _scanProcesses() {
    final found = <Interference>[];
    try {
      for (final p in ProcessListWindows.enumerate()) {
        final label = _dpiProcNames[p.name.toLowerCase()];
        if (label != null) {
          // appName заполняем и здесь: иначе кнопку «закрыть» показать нельзя,
          // а закрывать DPI-инструмент нужно ровно так же, как чужой VPN.
          found.add(Interference('process', label, p.path,
              pid: p.pid, appName: label, appPath: p.path));
        }
      }
    } catch (_) {}
    return found;
  }

  /// Чужой системный прокси (включён, но не на наш локальный порт).
  static Future<List<Interference>> _scanProxy() async {
    try {
      final key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final en = await Process.run('reg', ['query', key, '/v', 'ProxyEnable']);
      if (!'${en.stdout}'.contains('0x1')) return [];
      final sv = await Process.run('reg', ['query', key, '/v', 'ProxyServer']);
      final out = '${sv.stdout}';
      // Наш прокси — 127.0.0.1:10809; любой другой активный прокси считаем помехой.
      if (out.contains('127.0.0.1:10809')) return [];
      final m = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(out);
      final val = m?.group(1)?.trim() ?? 'включён';
      return [Interference('proxy', 'Системный прокси', val)];
    } catch (_) {
      return [];
    }
  }

  /// Имена адаптеров, похожих на чужой туннель, и их адреса.
  ///
  /// ⚠️ БЕЗ PowerShell. Здесь стоял `Get-NetAdapter`, и на машине владельца он
  /// НЕ ВОЗВРАЩАЛСЯ ВООБЩЕ: замерено — обрывали на 90 секундах, при том что сам
  /// `powershell -Command "exit 0"` отрабатывает за 115 мс. Виноват модуль
  /// NetAdapter (CIM), а не оболочка. Последствия были не косметические: этот
  /// же вызов делается при проверке помех на старте и при разборе неудачного
  /// подъёма туннеля, то есть подвешивал ровно те места, где пользователь ждёт
  /// ответа. `NetworkInterface.list()` даёт те же дружественные имена
  /// («happ-tun», «Radmin VPN») за 7 мс и без запуска процессов.
  ///
  /// Возвращаются только ПОДНЯТЫЕ интерфейсы: у выключенного адаптера адресов
  /// нет, и в список он не попадает. Это важно — постоянно установленный, но
  /// спящий TAP-адаптер (их оставляет после себя OpenVPN) помехой не является.
  static Future<List<String>> _foreignTunnelAdapters() async {
    final names = <String>[];
    try {
      final list = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.any);
      for (final i in list) {
        if (_isOurs(i)) continue;
        if (_looksLikeTunnel(i.name)) names.add(i.name);
      }
    } catch (_) {}
    return names;
  }

  /// Наш собственный туннель — по АДРЕСУ, а не по имени.
  ///
  /// Имя адаптера пользователь может переименовать, адрес 172.19.0.1 задаём мы
  /// сами. На этом уже обжигались в 0.8.3: сверка по имени не срабатывала, и
  /// подъём собственного туннеля засчитывался как смена сети — приложение
  /// уходило в бесконечный цикл переподключений.
  static bool _isOurs(NetworkInterface i) {
    if (i.name.toLowerCase().contains('silentgate')) return true;
    for (final a in i.addresses) {
      final v = a.address.toLowerCase();
      if (v.startsWith('172.19.0.') || v.startsWith('fdfe:dcba:9876:')) {
        return true;
      }
    }
    return false;
  }

  /// Признаки того, что адаптер — ТУННЕЛЬ. Здесь намеренно нет имён клиентов.
  ///
  /// ⚠️ Раньше в списке стояли «happ», «nekobox», «hiddify», «clash». Это
  /// перечисление вендоров, а не признак: у одного пользователя такой клиент не
  /// установлен вовсе, у другого стоит пятый, которого в списке нет. Виновника
  /// мы всё равно определяем по РЕАЛЬНОМУ процессу, держащему адаптер, и его
  /// имя и показываем. Список должен отвечать на вопрос «это туннель?», а не
  /// «чей это туннель?».
  static const _tunnelHints = [
    'tun', 'tap', 'wintun', 'wireguard', 'wg', 'vpn', 'proxy',
  ];

  static bool _looksLikeTunnel(String name) {
    final n = name.toLowerCase();
    return _tunnelHints.any(n.contains);
  }

  static Future<List<Interference>> _scanAdapters() async {
    final adapters = await _foreignTunnelAdapters();
    if (adapters.isEmpty) return const [];

    // Список процессов берём ОДИН раз: перечисление с чтением модулей стоит
    // около полусекунды, а адаптеров бывает несколько.
    List<RunningProcess> procs;
    try {
      procs = ProcessListWindows.enumerate();
    } catch (_) {
      procs = const [];
    }
    // Запасной владелец — ТОЛЬКО когда чужой туннель ровно один. При двух и
    // более приписывать одного и того же виновника каждому — враньё: на машине
    // владельца рядом с happ-tun живёт Radmin VPN, к Happ отношения не имеющий,
    // и в списке помех он выглядел бы как второй адаптер Happ.
    final fallback = adapters.length == 1 ? _ownerByModuleOrName(procs) : null;

    // ⚠️ НИ ОДИН АДАПТЕР НЕ СЧИТАЕТСЯ ЧУЖИМ, ПОКА ЖИВО НАШЕ ЖЕ ЯДРО.
    //
    // Жалоба владельца: «выключить VPN и тут же включить — считает себя за
    // другой VPN и не даёт включиться». Так и было: наш туннель снимается не
    // мгновенно, адрес 172.19.0.x с адаптера уже пропал, а сам адаптер с именем
    // вида «…tun» ещё висит — и попадал в список чужих. Проверка по адресу
    // (`_isOurs`) этот промежуток не закрывает по построению: закрывать его
    // должен признак «наши ядра ещё не закончили».
    //
    // Тише — лучше: пропущенная чужая помеха приводит к внятной ошибке при
    // подъёме, а ложная запрещает подключение вовсе и не оставляет выхода.
    if (procs.any(_isOwnCore)) return const [];

    return [
      for (final name in adapters)
        () {
          // Точная привязка: имя адаптера содержит имя процесса-владельца
          // («happ-tun» → happ.exe). Приписать ОДНОГО владельца всем адаптерам
          // было бы враньём — на машине владельца рядом с таким адаптером живёт
          // ещё и Radmin VPN, к нему отношения не имеющий.
          final owner = _ownerByAdapterName(procs, name) ?? fallback;
          return Interference('adapter', name, '',
              pid: owner?.pid,
              appName: owner == null ? null : appLabel(owner),
              appPath: owner?.path);
        }(),
    ];
  }

  /// Чужой активный VPN-туннель, который можно предложить закрыть.
  ///
  /// Возвращает null, если помехи нет ИЛИ виновника не удалось опознать: без
  /// имени программы кнопка «закрыть» бессмысленна, а закрыть наугад — вредно.
  /// На платформах кроме Windows всегда null: там перечисление процессов
  /// системой не разрешено, и вопрос решается иначе.
  static Future<Interference?> activeForeignTunnel() async {
    if (!Platform.isWindows) return null;
    try {
      final all = await _scanAdapters();
      for (final i in all) {
        if (i.closable) return i;
      }
    } catch (_) {}
    return null;
  }

  /// Дождаться, пока чужой туннель реально пропадёт.
  ///
  /// Убить процесс мало: система снимает адаптер и его маршруты с задержкой, и
  /// подключение, начатое в этот промежуток, упирается в ровно ту же чужую
  /// таблицу маршрутизации. Возвращает false, если за отведённое время адаптер
  /// так и не исчез, — тогда честнее сказать «закрыл, но подожди», чем молча
  /// подключаться в заведомо плохой момент.
  static Future<bool> waitTunnelGone(
      {Duration timeout = const Duration(seconds: 6)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if ((await _foreignTunnelAdapters()).isEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  /// Процессы, которые ПОДНИМАЮТ туннель, — запасное опознание.
  ///
  /// ⚠️ Здесь ЯДРА И СЛУЖБЫ, а не витрины клиентов. Прежний список
  /// («happ.exe» → «Happ», «nekobox.exe» → «NekoBox», ещё полтора десятка) был
  /// перечислением вендоров: он врал на любом клиенте, которого в нём нет, и
  /// заодно приучал показывать имя, которое пользователь у себя не видел.
  ///
  /// Точный ответ всё равно даёт [ProcessListWindows.hasModule] — процесс,
  /// держащий `wintun.dll`. Этот список нужен ровно на случай, когда система не
  /// дала прочитать модули чужого (возвышенного) процесса. Имя показываем
  /// НАСТОЯЩЕЕ, как в диспетчере задач: выдуманное «Happ» вместо «happ.exe»
  /// человеку искать не по чему.
  static const _tunnelProcNames = <String>{
    'sing-box.exe',
    'xray.exe',
    'v2ray.exe',
    'clash.exe',
    'mihomo.exe',
    'clash-meta.exe',
    'hysteria.exe',
    'tun2socks.exe',
    'wireguard.exe',
    'wg.exe',
    'openvpn.exe',
    'wstunnel.exe',
  };

  /// Программа, которой принадлежит чужой TUN-адаптер.
  ///
  /// Сначала точно: адаптер поднимает процесс, держащий `wintun.dll`. Если
  /// система не дала прочитать модули (чужой процесс возвышен, а мы — нет),
  /// опознаём по имени исполняемого файла. Не опознали — возвращаем null:
  /// предложить закрыть НЕ ТО приложение хуже, чем не предложить ничего.
  /// Владелец по ИМЕНИ АДАПТЕРА: «happ-tun» → happ.exe.
  ///
  /// Самый точный и самый дешёвый признак: клиенты почти всегда называют свой
  /// адаптер собственным именем. Три символа минимум — иначе короткое имя вроде
  /// «wg» совпадало бы со случайными процессами.
  static RunningProcess? _ownerByAdapterName(
      List<RunningProcess> procs, String adapter) {
    final a = adapter.toLowerCase();
    for (final p in procs) {
      if (_isSelf(p)) continue;
      final low = p.name.toLowerCase();
      final base = low.endsWith('.exe') ? low.substring(0, low.length - 4) : low;
      if (base.length >= 3 && a.contains(base)) return p;
    }
    return null;
  }

  /// Владелец по загруженному модулю, иначе — по имени процесса ядра.
  ///
  /// Модуль `wintun.dll` держит именно тот процесс, который поднял адаптер, —
  /// но чтение чужих модулей требует прав, а VPN-клиенты обычно возвышены.
  /// Поэтому за точным способом идёт список ЯДЕР (см. [_tunnelProcNames]).
  static RunningProcess? _ownerByModuleOrName(List<RunningProcess> procs) {
    RunningProcess? byModule;
    RunningProcess? byName;
    for (final p in procs) {
      if (_isSelf(p)) continue;
      byModule ??=
          ProcessListWindows.hasModule(p.pid, const ['wintun.dll']) ? p : null;
      byName ??=
          _tunnelProcNames.contains(p.name.toLowerCase()) ? p : null;
      if (byModule != null) break; // точный ответ дальше искать незачем
    }
    return byModule ?? byName;
  }

  /// Наши собственные процессы: сам exe и ядра рядом с ним. Помехой быть не могут.
  /// НАШЕ ядро, ещё не завершившееся. Не само приложение, а именно ядро:
  /// пока оно живо, туннель на машине может быть нашим, и объявлять адаптер
  /// чужим нельзя.
  static bool _isOwnCore(RunningProcess p) {
    const cores = {'sing-box.exe', 'xray.exe'};
    return cores.contains(p.name.toLowerCase()) && _isSelf(p);
  }

  static bool _isSelf(RunningProcess p) {
    final self = Platform.resolvedExecutable.toLowerCase();
    final path = p.path.toLowerCase();
    if (path == self) return true;
    const mine = {'silentgate.exe', 'sing-box.exe', 'xray.exe'};
    if (!mine.contains(p.name.toLowerCase())) return false;
    // Ядро с таким же именем может принадлежать ЧУЖОМУ клиенту (sing-box и Xray
    // используют многие), поэтому «своим» считаем только то, что лежит в нашей
    // же папке. Каталог берём через утилиту пути, а не поиском разделителя
    // вручную: ручной вариант уже давал промах и падение на substring.
    return _dirOf(path) == _dirOf(self);
  }

  static String _dirOf(String filePath) {
    final i = filePath.lastIndexOf(Platform.pathSeparator);
    return i <= 0 ? filePath : filePath.substring(0, i);
  }

  /// Программа, которой принадлежит чужой TUN-адаптер. Null — не опознали, и
  /// тогда кнопку «закрыть» не предлагаем: закрыть НЕ ТО хуже, чем ничего.
  static RunningProcess? tunnelOwner({List<String> adapterNames = const []}) {
    List<RunningProcess> procs;
    try {
      procs = ProcessListWindows.enumerate();
    } catch (_) {
      return null;
    }
    for (final a in adapterNames) {
      final byAdapter = _ownerByAdapterName(procs, a);
      if (byAdapter != null) return byAdapter;
    }
    return _ownerByModuleOrName(procs);
  }

  /// Имя программы для показа — НАСТОЯЩЕЕ, как в диспетчере задач.
  ///
  /// ⚠️ Раньше здесь подставлялась «витрина» из списка вендоров: процесс
  /// `happ.exe` показывался как «Happ». Красивее, но искать по этому имени
  /// нечего — в диспетчере задач такой строки нет, а если в списке клиента не
  /// оказалось, показывалось третье имя. Берём имя файла без расширения: оно
  /// всегда верное и всегда находится.
  static String appLabel(RunningProcess p) =>
      p.name.toLowerCase().endsWith('.exe')
          ? p.name.substring(0, p.name.length - 4)
          : p.name;

  /// Закрыть процесс-помеху.
  ///
  /// zapret/GoodbyeDPI обычно запущены с правами администратора, и обычный taskkill
  /// их не берёт («Отказано в доступе») — молча ничего не происходило. Поэтому:
  /// сначала пробуем без прав, а если процесс жив — повторяем через UAC.
  /// Возвращает true, если процесс действительно исчез.
  static Future<bool> kill(int pid) async {
    try {
      await Process.run('taskkill', ['/F', '/PID', '$pid', '/T']);
    } catch (_) {}
    if (!await _alive(pid)) return true;

    // ⚠️ Только асинхронная элевация. Синхронный вызов через FFI умеет не
    // возвращаться вовсе (см. Elevation) — и тогда кнопка «закрыть приложение»
    // намертво вешала бы весь интерфейс.
    await Elevation.runElevatedAsync('taskkill.exe', '/F /PID $pid /T');
    // Элевейтнутый процесс завершается асинхронно — ждём результата.
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!await _alive(pid)) return true;
    }
    return false;
  }

  static Future<bool> _alive(int pid) async {
    try {
      final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
      return '${r.stdout}'.contains('$pid');
    } catch (_) {
      return false;
    }
  }
}
