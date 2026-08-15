import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../engine/windows/xray_paths.dart';
import '../platform/app_log.dart';
import '../platform/app_paths.dart';
import 'geo_bases_store.dart';
import 'geo_dat.dart';
import 'geo_usage.dart';
import 'sha256.dart';

/// Откуда берутся гео-базы. ⚠️ ЭТО ТОТ ЖЕ ИСТОЧНИК, ИЗ КОТОРОГО ОНИ ПРИЕЗЖАЮТ
/// В ПОСТАВКЕ, И ДРУГОГО ЗДЕСЬ БЫТЬ НЕ МОЖЕТ.
///
/// `tools/fetch-xray.ps1` распаковывает в `engine/windows/bin` архив
/// `Xray-windows-64.zip` из релиза XTLS/Xray-core — вместе с `geoip.dat` и
/// `geosite.dat`. А сам XTLS кладёт в этот архив не свои файлы: его воркфлоу
/// `.github/workflows/scheduled-assets-update.yml` берёт их так (проверено по
/// исходнику воркфлоу 15.08.2026):
///
/// ```
/// curl -L …raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat
/// curl -L …raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat
/// ```
///
/// ⚠️ ЧТО БЫЛО ДО 1.5.1 И ЧЕМ ЭТО КОНЧИЛОСЬ. Качали из `v2fly/geoip` и
/// `v2fly/domain-list-community` (`dlc.dat`) — ДРУГОЙ проект с другим составом,
/// а комментарий рядом утверждал, что это «те же файлы, что XTLS кладёт в свой
/// релизный архив». Размеры это опровергают: в поставке лежали `geoip.dat`
/// 18,85 МБ и `geosite.dat` 10,01 МБ, после обновления стало 22,01 МБ и
/// **2,18 МБ**. Ядро приняло замену без единой жалобы в лог, а маршрутизация
/// владельца развалилась: правила панели по российским категориям перестали
/// совпадать, и весь российский трафик поехал через VPN. Искал он причину в
/// серверах.
const _loyalsoldier =
    'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release';

/// Одна гео-база: имя файла, к какому файлу относятся ссылки на категории,
/// адрес файла и адрес его контрольной суммы.
enum GeoBase {
  geoip(
    fileName: 'geoip.dat',
    kind: GeoRefKind.ip,
    url: '$_loyalsoldier/geoip.dat',
    sumUrl: '$_loyalsoldier/geoip.dat.sha256sum',
  ),
  geosite(
    fileName: 'geosite.dat',
    kind: GeoRefKind.site,
    url: '$_loyalsoldier/geosite.dat',
    sumUrl: '$_loyalsoldier/geosite.dat.sha256sum',
  );

  const GeoBase({
    required this.fileName,
    required this.kind,
    required this.url,
    required this.sumUrl,
  });

  final String fileName;

  /// Какие ссылки конфигов резолвит этот файл: `geoip:` или `geosite:`.
  final GeoRefKind kind;

  final String url;

  /// ⚠️ ЦЕЛОСТНОСТЬ ПРОВЕРЯЕМ ТЕМ ЖЕ, ЧЕМ ЕЁ ПРОВЕРЯЕТ САМ XTLS: рядом с каждым
  /// файлом в той же ветке лежит `<имя>.sha256sum` (74 байта), и воркфлоу
  /// сборки Xray сверяет закачку именно с ним. Сумма считается по СОДЕРЖИМОМУ,
  /// а имя внутри `.sha256sum` не сравнивается ни с чем.
  final String sumUrl;
}

/// Резервная копия прежней базы: что можно вернуть и от какого числа.
class GeoBackup {
  final GeoBase base;
  final int bytes;
  final DateTime? at;

  const GeoBackup({required this.base, required this.bytes, this.at});
}

/// Состояние одного файла на диске.
enum GeoHealth {
  /// Файла нет вовсе.
  missing,

  /// Файл есть, но это не гео-база: обрезанная закачка, страница ошибки,
  /// нулевой размер. Для ядра это хуже отсутствия — оно отвергает конфиг
  /// целиком, а пользователю показывается «файлы на месте».
  corrupt,
  ok,
}

class GeoFileStatus {
  final GeoBase base;
  final GeoHealth health;
  final int bytes;
  final DateTime? updatedAt;

  const GeoFileStatus({
    required this.base,
    required this.health,
    this.bytes = 0,
    this.updatedAt,
  });

  bool get ok => health == GeoHealth.ok;
}

class GeoBasesStatus {
  final List<GeoFileStatus> files;
  final String dirPath;

  const GeoBasesStatus({required this.files, required this.dirPath});

  /// Обе базы на месте и читаемы.
  ///
  /// ⚠️ Именно ОБЕ. С одной половиной конфиг всё равно не соберётся, а
  /// «установлено наполовину» — состояние, которое пользователю не объяснить.
  bool get ready => files.isNotEmpty && files.every((f) => f.ok);

  bool get anyMissing => files.any((f) => f.health == GeoHealth.missing);
  bool get anyCorrupt => files.any((f) => f.health == GeoHealth.corrupt);

  int get bytes => files.fold(0, (a, f) => a + f.bytes);

  DateTime? get updatedAt {
    DateTime? out;
    for (final f in files) {
      final t = f.updatedAt;
      if (t == null) continue;
      if (out == null || t.isAfter(out)) out = t;
    }
    return out;
  }

  /// Что именно надо скачать: то, чего нет, и то, что испорчено.
  List<GeoBase> get needDownload =>
      [for (final f in files) if (!f.ok) f.base];
}

/// Итог по одному файлу после проверки обновлений.
class GeoFileCheck {
  final GeoBase base;
  final GeoHealth health;

  /// Сумма из релиза. `null` — узнать не удалось.
  final String? remoteSum;

  /// Сумма нашего файла. `null` — файла нет либо он испорчен.
  final String? localSum;

  /// Размер файла в релизе (из `Content-Length`). `null` — не спрашивали или
  /// сервер не сказал.
  final int? remoteBytes;

  const GeoFileCheck({
    required this.base,
    required this.health,
    this.remoteSum,
    this.localSum,
    this.remoteBytes,
  });

  /// Файла нет или он испорчен — это СКАЧИВАНИЕ, а не обновление.
  bool get needsDownload => health != GeoHealth.ok;

  /// Файл рабочий, но в релизе лежит другой.
  ///
  /// ⚠️ Обе суммы обязаны быть известны. Неизвестная сумма — это «мы не
  /// знаем», и выдавать её за «есть обновление» значило бы гонять 25 МБ
  /// каждый раз, когда GitHub не ответил.
  bool get needsUpdate =>
      health == GeoHealth.ok &&
      remoteSum != null &&
      localSum != null &&
      remoteSum != localSum;
}

/// Результат проверки обновлений.
class GeoCheckResult {
  final DateTime at;
  final List<GeoFileCheck> files;

  /// Почему проверка не удалась. Непусто — значит вердикт НЕ ВЫНЕСЕН, и делать
  /// вид, что базы актуальны, нельзя.
  final String? error;

  const GeoCheckResult({required this.at, required this.files, this.error});

  bool get failed => error != null;
  List<GeoBase> get toDownload =>
      [for (final f in files) if (f.needsDownload) f.base];
  List<GeoBase> get toUpdate =>
      [for (final f in files) if (f.needsUpdate) f.base];

  /// Всё, что реально поедет по сети.
  List<GeoBase> get pending => [...toDownload, ...toUpdate];

  /// Сколько байт придётся скачать. `null` — размер неизвестен хотя бы у
  /// одного файла, и обещать цифру нельзя.
  int? get pendingBytes {
    var sum = 0;
    for (final f in files) {
      if (!f.needsDownload && !f.needsUpdate) continue;
      final b = f.remoteBytes;
      if (b == null) return null;
      sum += b;
    }
    return sum;
  }

  /// Проверка прошла и обновлять нечего.
  bool get upToDate => !failed && pending.isEmpty;
}

/// Ход закачки — для полоски прогресса.
class GeoProgress {
  final GeoBase base;
  final int received;

  /// Сколько всего ждём. `null` — сервер не прислал `Content-Length`.
  final int? total;

  /// Какой файл по счёту из скольких.
  final int index;
  final int count;

  const GeoProgress({
    required this.base,
    required this.received,
    required this.index,
    required this.count,
    this.total,
  });
}

/// Гео-базы Xray (`geoip.dat` / `geosite.dat`): где лежат, целы ли, есть ли
/// новее, как скачать.
///
/// ⚠️ ЗАЧЕМ ОНИ. По ним ядро резолвит правила вида `geoip:ru`,
/// `geosite:category-ads`. Без файлов Xray отвергает конфиг ЦЕЛИКОМ
/// (`illegal ip rule: geoip:private > failed to open geoip.dat`), поэтому их
/// отсутствие обязано быть известным состоянием, а не аварией.
///
/// ⚠️ КАТАЛОГ — ТОТ, ИЗ КОТОРОГО ЧИТАЕТ ЯДРО, И НИКАКОЙ ДРУГОЙ.
/// На Android это `<filesDir>/SilentGate/geo`: путь ставит
/// `SilentGateApplication.kt` через `Os.setenv("XRAY_LOCATION_ASSET", …)` перед
/// `LibXray.invoke`. На Windows — каталог рядом с `xray.exe`
/// (`XrayProcess.start` передаёт его той же переменной), туда же их кладёт
/// `tools/fetch-xray.ps1` при сборке. Класть файлы «куда удобнее» и считать
/// дело сделанным нельзя: ядро их не увидит, а интерфейс покажет «скачаны».
class GeoBases {
  GeoBases._();

  static Directory? _dirOverride;

  /// Подменить каталог (тест либо изолированная копия).
  @visibleForTesting
  static void overrideDir(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dirOverride = dir;
  }

  /// Подменный «каталог ядра» — чтобы тест мог пройти ветку Windows, не
  /// прикасаясь к настоящему `engine/windows/bin` разработчика.
  @visibleForTesting
  static String? coreAssetDirForTests;

  @visibleForTesting
  static void resetForTests() {
    _dirOverride = null;
    coreAssetDirForTests = null;
  }

  static bool get _underTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Каталог, откуда гео-базы читает ядро.
  ///
  /// ⚠️ ПОД ТЕСТОМ БОЕВОЙ КАТАЛОГ ЯДРА НЕ ОТДАЁТСЯ. Иначе тест, проверяющий
  /// «удаление испорченных баз», стёр бы `engine/windows/bin/geoip.dat` в
  /// рабочей копии разработчика — 19 МБ, которые потом качать заново. Тому же
  /// правилу подчиняется [AppPaths]: под тестом он требует свой каталог.
  static String? _coreAssetDir() {
    final forTests = coreAssetDirForTests;
    if (forTests != null) return forTests;
    if (_underTest) return null;
    if (!Platform.isWindows) return null;
    return XrayPaths.locate()?.assetDir;
  }

  static Future<Directory> dir() async {
    final custom = _dirOverride;
    if (custom != null) {
      if (!await custom.exists()) await custom.create(recursive: true);
      return custom;
    }
    final core = _coreAssetDir();
    if (core != null) {
      final d = Directory(core);
      if (!await d.exists()) await d.create(recursive: true);
      return d;
    }
    final base = await AppPaths.supportDir();
    final d = Directory('${base.path}${Platform.pathSeparator}geo');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> fileOf(GeoBase base) async =>
      File('${(await dir()).path}${Platform.pathSeparator}${base.fileName}');

  /// Расширение резервной копии. Лежит РЯДОМ с базой, в том же каталоге ядра:
  /// ядро ищет там файлы по точным именам (`geoip.dat`, `geosite.dat`) и на
  /// `.bak` не смотрит, а держать резерв в другом месте значило бы, что при
  /// переустановке приложения он потеряется отдельно от того, что защищает.
  static const backupSuffix = '.bak';

  static Future<File> backupOf(GeoBase base) async =>
      File('${(await fileOf(base)).path}$backupSuffix');

  /// Что можно вернуть. Пусто — возвращать нечего.
  static Future<List<GeoBackup>> backups() async {
    final out = <GeoBackup>[];
    for (final base in GeoBase.values) {
      try {
        final f = await backupOf(base);
        if (await healthOf(f) != GeoHealth.ok) continue;
        final st = await f.stat();
        out.add(GeoBackup(base: base, bytes: st.size, at: st.modified));
      } catch (_) {}
    }
    return out;
  }

  /// Вернуть прежние базы. `null` — успех, иначе причина.
  ///
  /// ⚠️ ЭТО НЕ УДОБСТВО, А ГЛАВНЫЙ ВЫВОД ИЗ 15.08.2026. Обновление тогда
  /// перезаписало рабочие файлы на месте, и вернуться было НЕКУДА: единственным
  /// способом получить прежнюю маршрутизацию оставалась переустановка
  /// приложения. Поломку от гео-баз человек по симптомам не отличит («сайты не
  /// открываются», «выбрал не тот сервер»), поэтому откат обязан быть в один
  /// шаг и без сети.
  static Future<String?> restoreBackups() async {
    final problem = await writeProblem();
    if (problem != null) {
      final d = await dir();
      return 'нет доступа на запись в ${d.path}: $problem';
    }
    var done = 0;
    for (final base in GeoBase.values) {
      final backup = await backupOf(base);
      // Возвращаем только исправное: подсунуть вместо рабочей базы обрывок
      // хуже, чем не вернуть ничего.
      if (await healthOf(backup) != GeoHealth.ok) continue;
      final target = await fileOf(base);
      try {
        await _deleteQuiet(target);
        await backup.rename(target.path);
        done++;
        AppLog.i('Гео-база ${base.fileName}: возвращена прежняя версия');
      } catch (e) {
        return '${base.fileName}: $e';
      }
    }
    return done == 0 ? 'возвращать нечего: резервной копии нет' : null;
  }

  /// Можно ли вообще писать в каталог ядра. `null` — можно, иначе причина.
  ///
  /// ⚠️ СПРАШИВАЕМ ДО ЗАКАЧКИ, А НЕ ПОСЛЕ. На Windows установщик кладёт
  /// приложение в `%ProgramFiles%\SilentGate` (`{autopf}` в
  /// `installer/silentgate.iss`), а туда обычный пользователь писать не может.
  /// Узнать об этом после 25 МБ — худший вариант из возможных: трафик потрачен,
  /// результата нет.
  static Future<String?> writeProblem() async {
    try {
      final d = await dir();
      final probe =
          File('${d.path}${Platform.pathSeparator}.sg_write_probe');
      await probe.writeAsString('x', flush: true);
      await probe.delete();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Целостность файла: 0 байт и HTML-страница ошибки — не гео-база.
  ///
  /// ⚠️ ПОДПИСЬ, А НЕ ТОЛЬКО РАЗМЕР. Оба файла — protobuf, чьё первое поле
  /// `repeated … entry = 1`, поэтому первый байт всегда `0x0A` (проверено на
  /// поставочных `engine/windows/bin/*.dat`: `0a fc 2c …` и `0a 3a 0a …`).
  /// Страница ошибки начинается с `<`, JSON — с `{`: и то и другое ловится
  /// одним байтом. Полную проверку формата тут делать нечем, но «файл есть, а
  /// внутри HTML» — ровно тот случай, из-за которого ядро падало, а интерфейс
  /// показывал «скачано».
  static Future<GeoHealth> healthOf(File f) async {
    try {
      if (!await f.exists()) return GeoHealth.missing;
      final size = await f.length();
      // Настоящие файлы — единицы мегабайт. Ниже килобайта это заведомо не
      // гео-база, а обрывок или сообщение сервера.
      if (size < 1024) return GeoHealth.corrupt;
      final head = await f.openRead(0, 1).expand((c) => c).toList();
      if (head.isEmpty || head.first != 0x0a) return GeoHealth.corrupt;
      return GeoHealth.ok;
    } catch (_) {
      // Нет прав, файл занят — снаружи это неотличимо от «нечитаем».
      return GeoHealth.corrupt;
    }
  }

  /// Состояние обоих файлов.
  static Future<GeoBasesStatus> status() async {
    final d = await dir();
    final out = <GeoFileStatus>[];
    for (final base in GeoBase.values) {
      final f = File('${d.path}${Platform.pathSeparator}${base.fileName}');
      final health = await healthOf(f);
      if (health == GeoHealth.missing) {
        out.add(GeoFileStatus(base: base, health: health));
        continue;
      }
      FileStat? st;
      try {
        st = await f.stat();
      } catch (_) {
        st = null;
      }
      out.add(GeoFileStatus(
        base: base,
        health: health,
        bytes: st?.size ?? 0,
        updatedAt: st?.modified,
      ));
    }
    return GeoBasesStatus(files: out, dirPath: d.path);
  }

  /// Обе базы годны к работе (быстрая проверка для движка).
  static Future<bool> available() async => (await status()).ready;

  // ── Проверка обновлений ───────────────────────────────────────────────────

  /// Сравнить свои файлы с релизом.
  ///
  /// ⚠️ КАК ОТЛИЧАЕМ «ЕСТЬ ЧТО ОБНОВЛЯТЬ» — ПО SHA-256, А НЕ ПО ДАТЕ И НЕ ПО
  /// РАЗМЕРУ. Дата файла на диске — это дата НАШЕЙ закачки, она ничего не
  /// говорит о содержимом (перекачал тот же файл — дата новая, база та же).
  /// Дата релиза на GitHub меняется ежедневно, даже когда состав не изменился,
  /// и по ней пользователь качал бы 25 МБ каждый день впустую. Размер
  /// совпадает у разных сборок. Остаётся хэш — и он уже опубликован рядом с
  /// файлом (`*.sha256sum`, 74 байта), так что вопрос «нужно ли обновление»
  /// стоит два коротких запроса вместо целой базы.
  static Future<GeoCheckResult> check({
    http.Client? client,
    bool withSizes = true,
  }) async {
    final own = client == null;
    final c = client ?? http.Client();
    final now = DateTime.now();
    final store = await GeoBasesStore.load();
    final files = <GeoFileCheck>[];
    String? error;
    try {
      final d = await dir();
      for (final base in GeoBase.values) {
        final f = File('${d.path}${Platform.pathSeparator}${base.fileName}');
        final health = await healthOf(f);
        final localSum =
            health == GeoHealth.ok ? await _localSum(store, base, f) : null;

        String? remoteSum;
        try {
          remoteSum = _parseSumFile(await _getString(c, base.sumUrl));
        } catch (e) {
          // Первая же неудача — вердикта нет. Дальше продолжаем, чтобы
          // показать хотя бы то, что узнали про второй файл.
          error ??= '$e';
        }

        int? remoteBytes;
        final willFetch = health != GeoHealth.ok ||
            (remoteSum != null && localSum != null && remoteSum != localSum);
        if (withSizes && willFetch) {
          remoteBytes = await _remoteSize(c, base.url);
        }

        files.add(GeoFileCheck(
          base: base,
          health: health,
          remoteSum: remoteSum,
          localSum: localSum,
          remoteBytes: remoteBytes,
        ));
      }
      await store.saveCheck(
        at: now,
        remoteSums: {
          for (final f in files)
            if (f.remoteSum != null) f.base.fileName: f.remoteSum!,
        },
      );
    } catch (e) {
      error ??= '$e';
    } finally {
      if (own) c.close();
    }
    return GeoCheckResult(at: now, files: files, error: error);
  }

  /// Сумма нашего файла с кэшем по «размер + время правки».
  ///
  /// ⚠️ Кэш нужен не ради красоты: без него каждое открытие настроек считало бы
  /// хэш 25 МБ заново.
  static Future<String?> _localSum(
      GeoBasesStore store, GeoBase base, File f) async {
    try {
      final st = await f.stat();
      final cached = store.cachedSum(
        base.fileName,
        size: st.size,
        mtimeMs: st.modified.millisecondsSinceEpoch,
      );
      if (cached != null) return cached;
      final sum = await Sha256.ofFile(f);
      await store.rememberSum(
        base.fileName,
        size: st.size,
        mtimeMs: st.modified.millisecondsSinceEpoch,
        sum: sum,
      );
      return sum;
    } catch (_) {
      return null;
    }
  }

  /// `9c30bd…  geoip.dat` → `9c30bd…`.
  static String _parseSumFile(String body) {
    final token = body.trim().split(RegExp(r'\s+')).firstWhere(
          (t) => t.isNotEmpty,
          orElse: () => '',
        );
    final sum = token.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sum)) {
      // Сюда попадает страница-заглушка провайдера и HTML ошибки GitHub.
      // Принять такое за сумму значило бы вечное «есть обновление».
      throw const FormatException('в файле контрольной суммы не хэш');
    }
    return sum;
  }

  static Future<String> _getString(http.Client c, String url) async {
    final resp = await c.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
    }
    return resp.body;
  }

  /// Размер файла в релизе. Неудача — не ошибка: цифру просто не покажем.
  static Future<int?> _remoteSize(http.Client c, String url) async {
    try {
      final req = http.Request('HEAD', Uri.parse(url))..followRedirects = true;
      final resp = await c.send(req);
      await resp.stream.drain<void>();
      if (resp.statusCode != 200) return null;
      return resp.contentLength;
    } catch (_) {
      return null;
    }
  }

  // ── Скачивание ────────────────────────────────────────────────────────────

  /// Скачать перечисленные базы. `null` — успех, иначе причина отказа.
  ///
  /// [expectedSums] — суммы из проверки обновлений: скачанный файл сверяется с
  /// ними ДО того, как встанет на место рабочего.
  ///
  /// [requiredRefs] — категории, которые обязаны быть в новом файле. По
  /// умолчанию спрашиваются у [GeoUsage] (что реально упоминают наши конфиги);
  /// пустое множество отключает проверку — проверять нечего.
  ///
  /// ⚠️ ВРЕМЕННЫЙ ФАЙЛ И ПЕРЕИМЕНОВАНИЕ. Оборванная закачка иначе оставила бы
  /// обрезанный `geoip.dat`, который ядро принимает за настоящий: вместо
  /// честного «баз нет» получилась бы неверная маршрутизация, которую никто не
  /// заподозрит.
  static Future<String?> download({
    required List<GeoBase> files,
    Map<GeoBase, String>? expectedSums,
    Set<GeoRef>? requiredRefs,
    void Function(GeoProgress)? onProgress,
    http.Client? client,
  }) async {
    if (files.isEmpty) return null;
    final problem = await writeProblem();
    if (problem != null) {
      final d = await dir();
      return 'нет доступа на запись в ${d.path}: $problem';
    }
    final own = client == null;
    final c = client ?? http.Client();
    final store = await GeoBasesStore.load();
    final used = requiredRefs ?? await GeoUsage.fromDataDir();
    try {
      for (var i = 0; i < files.length; i++) {
        final base = files[i];
        final target = await fileOf(base);
        final tmp = File('${target.path}.part');
        try {
          final sum = await _fetchTo(
            c,
            base.url,
            tmp,
            (received, total) => onProgress?.call(GeoProgress(
                  base: base,
                  received: received,
                  total: total,
                  index: i,
                  count: files.length,
                )),
          );
          final expected = expectedSums?[base];
          if (expected != null && expected != sum) {
            await _deleteQuiet(tmp);
            return '${base.fileName}: контрольная сумма не совпала — '
                'закачка повреждена';
          }
          final health = await healthOf(tmp);
          if (health != GeoHealth.ok) {
            await _deleteQuiet(tmp);
            return '${base.fileName}: скачан не тот файл (${health.name})';
          }
          final lost = await missingCategories(tmp, base, used);
          if (lost != null) {
            await _deleteQuiet(tmp);
            return lost;
          }
          await _keepPrevious(target);
          try {
            await tmp.rename(target.path);
          } catch (e) {
            // Замена не удалась — прежний файл обязан вернуться на место, иначе
            // мы оставили бы человека вообще без гео-баз.
            final backup = File('${target.path}$backupSuffix');
            if (!await target.exists() && await backup.exists()) {
              await backup.rename(target.path);
            }
            rethrow;
          }
          final st = await target.stat();
          await store.rememberSum(
            base.fileName,
            size: st.size,
            mtimeMs: st.modified.millisecondsSinceEpoch,
            sum: sum,
          );
          AppLog.i('Гео-база ${base.fileName} обновлена: '
              '${st.size ~/ 1024} КБ');
        } catch (e) {
          await _deleteQuiet(tmp);
          return '${base.fileName}: $e';
        }
      }
      return null;
    } finally {
      if (own) c.close();
    }
  }

  /// ⚠️ ПРОВЕРКА КАТЕГОРИЙ ДО ЗАМЕНЫ. Возвращает `null`, если новый файл
  /// подходит, иначе — готовую причину отказа.
  ///
  /// Именно здесь ловится то, что случилось 15.08.2026: файл скачался целиком,
  /// сумма сошлась, ядро его примет — а категорий, на которые ссылается панель
  /// подписки, внутри нет. Ядро об этом молчит (правило просто перестаёт
  /// совпадать), поэтому спросить обязаны мы, и обязаны ДО того, как рабочий
  /// файл будет тронут.
  ///
  /// ⚠️ «НЕ РАЗОБРАЛСЯ» — ЭТО ТОЖЕ ОТКАЗ. Нечитаемый список категорий значит
  /// «мы не знаем, что внутри», а менять рабочий файл на неизвестный нельзя.
  ///
  /// Проверять нечего, если наши конфиги вообще не ссылаются на этот файл
  /// (обычный сервер без панельной маршрутизации, первая установка) — тогда
  /// терять нечего и разбор не нужен.
  @visibleForTesting
  static Future<String?> missingCategories(
      File candidate, GeoBase base, Set<GeoRef> used) async {
    final need = GeoUsage.namesFor(used, base.kind);
    if (need.isEmpty) return null;
    final scan = await GeoDat.scan(candidate);
    if (!scan.readable) {
      return '${base.fileName}: не удалось прочитать список категорий '
          'в скачанном файле — прежний файл оставлен на месте';
    }
    final lost = [for (final n in need) if (!scan.has(n)) n]..sort();
    if (lost.isEmpty) return null;
    return '${base.fileName}: в новом файле нет категорий, которые использует '
        'ваша подписка: ${lost.map((n) => '${base.kind == GeoRefKind.ip ? 'geoip' : 'geosite'}:$n').join(', ')}'
        ' — прежний файл оставлен на месте';
  }

  /// Убрать прежний рабочий файл в резерв.
  ///
  /// ⚠️ ПЕРЕИМЕНОВАНИЕМ, А НЕ КОПИЕЙ: 20 МБ копировать незачем, а на телефоне
  /// это ещё и лишняя запись во флеш-память.
  ///
  /// ⚠️ ХРАНИМ РОВНО ОДНО ПОКОЛЕНИЕ — то, что работало до последней замены.
  /// Держать больше значит держать на диске десятки мегабайт «на всякий
  /// случай»; держать меньше — вернуться к 15.08.2026, когда возвращаться было
  /// некуда. Испорченный файл в резерв НЕ идёт: тогда кнопка отката вернула бы
  /// обрывок и человек решил бы, что откат не помогает.
  static Future<void> _keepPrevious(File target) async {
    final backup = File('${target.path}$backupSuffix');
    if (await healthOf(target) == GeoHealth.ok) {
      await _deleteQuiet(backup);
      try {
        await target.rename(backup.path);
        return;
      } catch (_) {
        // Резерв не вышел (нет места, файл занят) — обновление из-за этого не
        // отменяем, но и тихо делать вид, что копия есть, нельзя.
        AppLog.i('Гео-базы: не удалось сохранить прежний '
            '${target.uri.pathSegments.last} — отката не будет');
      }
    }
    await _deleteQuiet(target);
  }

  /// Скачивание одного файла; возвращает sha256 скачанного.
  ///
  /// ⚠️ Хэш считается ПО ХОДУ. Второй проход по 25 МБ ради той же цифры — это
  /// лишняя секунда и лишнее чтение с флеш-памяти телефона.
  static Future<String> _fetchTo(
    http.Client c,
    String url,
    File to,
    void Function(int received, int? total) onBytes,
  ) async {
    // ⚠️ Переадресация обязательна: `releases/latest/download/…` отдаёт 302 на
    // конкретный релиз. Без неё в файл лёг бы HTML редиректа.
    final req = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..maxRedirects = 5;
    final resp = await c.send(req);
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>();
      throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
    }
    final total = resp.contentLength;
    final hash = Sha256Sink();
    var received = 0;
    final sink = to.openWrite();
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        hash.add(chunk);
        received += chunk.length;
        onBytes(received, total);
      }
    } finally {
      await sink.close();
    }
    if (received == 0) throw const HttpException('пустой ответ');
    if (total != null && received != total) {
      throw HttpException('получено $received из $total байт');
    }
    return hash.close();
  }

  static Future<void> _deleteQuiet(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Удалить базы (освободить место / заставить перекачать).
  ///
  /// Резервные копии уходят вместе с ними: человек просил освободить место, и
  /// оставить половину — значит не выполнить просьбу. Возвращать после этого
  /// нечего и не к чему.
  static Future<void> remove() async {
    final d = await dir();
    for (final base in GeoBase.values) {
      final path = '${d.path}${Platform.pathSeparator}${base.fileName}';
      await _deleteQuiet(File(path));
      await _deleteQuiet(File('$path$backupSuffix'));
    }
    await (await GeoBasesStore.load()).forgetSums();
  }
}
