import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_info.dart';
import '../core/net/file_download.dart';
import '../core/platform/app_log.dart';
import '../core/settings/app_settings.dart';
import '../core/update/app_update.dart';
import '../core/update/update_installer.dart';
import '../core/update/update_installer_android.dart'
    show NeedsInstallPermission;
import '../core/update/update_manifest.dart';
import '../core/update/update_pubkey.dart';
import '../core/update/update_signature.dart';

/// САМООБНОВЛЕНИЕ — КОНТРОЛЛЕР. Единственная машина состояний между
/// «проверить», «скачать», «проверить подпись и хэш» и «поставить».
///
/// До 1.14.0 приложение при новой версии только открывало ссылку. Теперь оно
/// само качает установщик, проверяет его по ПОДПИСАННОМУ манифесту релиза
/// (`core/update/update_manifest.dart`, `update_signature.dart`) и передаёт
/// платформенному установщику (`core/update/update_installer*.dart`).
///
/// ⚠️ ЧТО ЗДЕСЬ НЕ ДОЛЖНО СЛОМАТЬСЯ МОЛЧА, И ЧЕМ ЭТО СТЕРЕЖЁТСЯ.
///
///  * **Ни байта установщика до подписи.** Порядок жёсткий: манифест и подпись
///    (маленькие, с потолком байт) → `UpdateSignature.verify` →
///    `UpdateManifest.parse` → `validateManifest` (версия РЕЛИЗА, канал, ТОЧНОЕ
///    имя актива) → только потом `downloadToFile` с размером и хэшем ИЗ
///    МАНИФЕСТА. Любой отказ на этой лестнице — [UpdatePhase.failed] с именем
///    причины ([UpdateError]) и без закачки.
///  * **Replay старого релиза не ставится.** Честно подписанный манифест 1.14.0
///    вместо 1.14.1 — откат с валидной подписью; [install] отказывает, если
///    версия предложения не новее нашей (кроме явного `allowDowngrade` из
///    «Прежних версий»).
///  * **Режим «спрашивать» не качает без согласия.** [startup] в режиме
///    [AppUpdateMode.ask] останавливается на [UpdatePhase.available]; закачку
///    начинает только [download], который зовёт интерфейс после «Обновить».
///  * **`auto` не рвёт живой VPN.** Установщик закрывает приложение, а с ним
///    ядра и системный прокси; при активном VPN контроллер остаётся в
///    [UpdatePhase.ready] с [waitingForVpnOff] и ставит сам, когда VPN
///    отключат ([vpnChanges]).
///  * **Все зависимости внедряемы** — проверка, закачка, установщик, признак
///    «VPN активен», публичный ключ. Тест (`test/app_update_controller_test.dart`)
///    гоняет ВЕСЬ поток на локальном сервере, не касаясь ни сети, ни боевого
///    `%APPDATA%`, ни настоящего установщика.
///  * **В журнал не попадают адреса.** Пишутся версии, размеры, фазы и
///    причины; текст исключений проходит через [scrubUrls]. Адрес закачки —
///    это адрес с токеном стенда или редиректом CDN, отчёт поддержки уходит
///    посторонним.

/// Фаза самообновления — ровно то, что рисует интерфейс.
enum UpdatePhase {
  /// Ничего не происходит: не проверяли, отложили либо версия пропущена
  /// (тогда [AppUpdateController.offerIsSkipped]).
  idle,

  /// Идёт запрос к серверу обновлений.
  checking,

  /// Проверили: у нас последняя.
  upToDate,

  /// Новее есть; установщик ещё не скачан.
  available,

  /// Качаем установщик ([AppUpdateController.progress]).
  downloading,

  /// Качаем и проверяем манифест с подписью (перед установщиком).
  verifying,

  /// Установщик скачан, хэш и подпись сошлись — можно ставить.
  ready,

  /// Установщик запущен (Windows) либо передан системному (Android).
  installing,

  /// Отказ — причина в [AppUpdateController.error].
  failed,

  /// Android: нет разрешения «устанавливать из этого приложения».
  needsPermission,

  /// Ставить самим нельзя или не просили — интерфейс показывает ссылку,
  /// причина — [AppUpdateController.linkOnlyReason].
  linkOnly,
}

/// Почему вместо кнопки «Установить» — ссылка.
enum LinkOnlyReason {
  /// Режим [AppUpdateMode.notifyOnly]: человек просил только сообщать.
  notifyOnly,

  /// В релизе нет манифеста/подписи/актива под эту платформу
  /// ([UpdateOffer.canSelfUpdate] == false) — самообновление невозможно.
  noSelfUpdate,

  portable,
  isolated,
  notInstalled,
  locationMismatch,
  elevated,
  unsupported,
}

/// Причина отказа — ТИПОМ, а не строкой исключения. Интерфейс подбирает
/// объяснение по [kind] и [rejection]; [detail] — только для журнала и
/// «подробностей», без адресов (см. [scrubUrls]).
enum UpdateErrorKind {
  /// Сервер обновлений не ответил или ответил непонятно.
  checkFailed,

  /// Адрес не `https://` при неподменённом источнике.
  insecureUrl,

  /// Имя актива из релиза содержит путь — подставлять его в каталог нельзя.
  unsafeAssetName,

  /// Манифест или подпись не скачались.
  manifestUnavailable,

  /// Подпись манифеста не сошлась с вшитым ключом.
  badSignature,

  /// Манифест подписан, но не подходит: см. [UpdateError.rejection].
  manifestRejected,

  /// Установщик не скачался или не совпал по размеру/хэшу.
  downloadFailed,

  /// Установщик не запустился.
  installFailed,

  /// Версия предложения не новее нашей — откат без явного согласия.
  notNewer,
}

class UpdateError {
  final UpdateErrorKind kind;

  /// Только у [UpdateErrorKind.manifestRejected].
  final ManifestRejection? rejection;

  /// Человеческий текст без адресов; может быть `null`.
  final String? detail;

  const UpdateError(this.kind, {this.rejection, this.detail});

  @override
  String toString() {
    final r = rejection == null ? '' : ' (${rejection!.name})';
    final d = detail == null || detail!.isEmpty ? '' : ': $detail';
    return '${kind.name}$r$d';
  }
}

/// Предложение обновиться — узкий срез [AppRelease], который нужен потоку
/// закачки и установки.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ТИП. Поля `assetName`/`assetSize`/`manifestUrl`/
/// `signatureUrl` в [AppRelease] добавляет параллельная задача (2A), и
/// контроллер не должен зависеть от её готовности: он строится из
/// [UpdateOffer], а единственная точка стыковки — [fromRelease]. Тесты
/// внедряют собственный [OfferBuilder], поэтому проверяют весь поток
/// независимо от того, что уже умеет разбор релиза.
class UpdateOffer {
  /// Версия без ведущего `v` — с ней сверяется манифест ([validateManifest]).
  final String version;
  final String? notes;

  /// Страница релиза для кнопки «Открыть» в [UpdatePhase.linkOnly].
  final String? pageUrl;
  final bool isBeta;
  final DateTime? publishedAt;

  /// Имя актива под эту платформу — ТОЧНО как в манифесте.
  final String? assetName;

  /// Размер актива по данным релиза; при расхождении верим манифесту.
  final int? assetSize;
  final String? assetUrl;
  final String? manifestUrl;
  final String? signatureUrl;

  const UpdateOffer({
    required this.version,
    this.notes,
    this.pageUrl,
    this.isBeta = false,
    this.publishedAt,
    this.assetName,
    this.assetSize,
    this.assetUrl,
    this.manifestUrl,
    this.signatureUrl,
  });

  /// Есть всё, чтобы поставить самим: актив, манифест и подпись. Иначе —
  /// прежнее поведение «ссылка».
  bool get canSelfUpdate =>
      assetName != null &&
      assetName!.isNotEmpty &&
      assetUrl != null &&
      manifestUrl != null &&
      signatureUrl != null;

  /// Единственная точка стыковки с разбором релиза.
  ///
  /// Поля самообновления переносятся ТОЛЬКО когда релиз собран целиком
  /// ([AppRelease.canSelfUpdate]: адрес, имя, размер, манифест, подпись — и
  /// каждый адрес допустим по схеме). Половина набора не имеет смысла: без
  /// подписи файл не проверить, без имени — не найти в манифесте. Тогда
  /// предложение честно не умеет самообновления ([canSelfUpdate] == false), и
  /// приложение ведёт себя как до 1.14.0 — показывает ссылку.
  static UpdateOffer fromRelease(AppRelease r) {
    final self = r.canSelfUpdate;
    return UpdateOffer(
      version: normalizeVersion(r.version),
      notes: r.notes,
      pageUrl: r.pageUrl,
      isBeta: r.isBeta,
      publishedAt: r.publishedAt,
      assetUrl: r.downloadUrl,
      assetName: self ? r.assetName : null,
      assetSize: self ? r.assetSize : null,
      manifestUrl: self ? r.manifestUrl : null,
      signatureUrl: self ? r.signatureUrl : null,
    );
  }
}

/// Проверка обновлений: `AppUpdate.check(beta: …)` либо подмена в тесте.
typedef UpdateChecker = Future<UpdateCheckResult> Function(
    {required bool beta});

/// Как из ответа сервера получить [UpdateOffer].
typedef OfferBuilder = UpdateOffer Function(AppRelease release);

/// Маленькая закачка целиком в память (манифест, подпись) с потолком байт.
/// [client] — тот же, что у закачки установщика: [AppUpdateController.cancel]
/// закрывает его и рвёт обе.
typedef BytesFetcher = Future<List<int>> Function(
  Uri url, {
  required int maxBytes,
  http.Client? client,
});

/// Закачка файла — сигнатура [downloadToFile] (лишние именованные параметры
/// у настоящей функции допустимы: тип функции их не требует).
typedef FileDownloader = Future<String> Function(
  Uri url,
  File target, {
  int? expectedSize,
  String? expectedSha256,
  void Function(int received, int? total)? onProgress,
  http.Client? client,
  int maxBytes,
});

/// Потолок манифеста: настоящий — сотни байт, десятки активов — единицы КБ.
const kUpdateManifestMaxBytes = 64 * 1024;

/// Потолок подписи: base64 от 64 байт — 88 символов.
const kUpdateSignatureMaxBytes = 4 * 1024;

/// Потолок установщика — тот же, что умолчание [downloadToFile].
const kUpdateAssetMaxBytes = 600 * 1024 * 1024;

/// Имя актива годится как имя файла в каталоге закачек: без путей, без
/// точек в начале, только безопасные символы. Имя приходит из ответа сервера
/// релизов, а подставляется в путь на диске — `..\..\x.exe` сюда не пройдёт.
bool isSafeAssetName(String name) =>
    name.isNotEmpty &&
    name.length <= 200 &&
    !name.startsWith('.') &&
    RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name);

final _urlRe = RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false);

/// Вырезать адреса из текста исключения перед журналом и интерфейсом.
String scrubUrls(String text) => text.replaceAll(_urlRe, '<адрес>');

/// Платформа, где самообновления нет: всё, кроме [capability], — общая
/// механика `updates/` (разбор `pending.json` там всё равно ничего не найдёт).
class UnsupportedUpdateInstaller extends StagedUpdateInstaller {
  UnsupportedUpdateInstaller({super.clock});

  @override
  Future<InstallCapability> capability() async => InstallCapability.unsupported;

  @override
  Future<void> launch(
    File verified, {
    required String version,
    required String expectedSha256,
    bool forceQuit = false,
    bool allowDowngrade = false,
  }) async {
    throw const UpdateInstallException(
        'самообновление на этой платформе не поддерживается');
  }
}

/// Одна закачка: поколение, клиент и признак отмены. Отменённая закачка
/// доматывает своё (удаляет `.part`) уже после того, как [cancel] сменил
/// фазу, — и не имеет права трогать состояние: все её записи гейтятся по
/// поколению.
class _DownloadRun {
  final int gen;
  final http.Client client;
  final Completer<void> done = Completer<void>();
  bool cancelled = false;

  _DownloadRun(this.gen, this.client);
}

class AppUpdateController extends ChangeNotifier {
  final AppSettings Function() _settings;
  final Future<void> Function(AppSettings Function(AppSettings)) _updateSettings;
  final UpdateInstaller _installer;
  final UpdateChecker _checker;
  final OfferBuilder _offerOf;
  final BytesFetcher _fetchBytes;
  final FileDownloader _downloader;
  final bool Function() _isVpnActive;
  final Listenable? _vpnChanges;
  final Future<void> Function() _openInstallPermission;
  final String _publicKey;
  final bool _overridden;
  final bool Function()? _overriddenOf;
  final Future<void> Function()? _loadOverride;
  final String _currentVersion;
  final Duration _purgeRetryDelay;
  final DateTime Function() _clock;

  /// Все зависимости внедряемы — умолчания боевые.
  ///
  /// [settings] и [updateSettings] — доступ к настройкам через
  /// `SettingsController` (единственный источник правды, свой экземпляр
  /// `SettingsStorage` здесь не заводится). [vpnChanges] — что слушать, чтобы
  /// узнать о смене состояния VPN (в приложении — `AppState`); [isVpnActive]
  /// — само состояние. [publicKeyBase64] — ТОЛЬКО для теста с собственной
  /// парой ключей; в приложении ключ вшит и не переопределяется ничем.
  /// [overridden] — источник подменён стендом (`SILENTGATE_UPDATE_API`):
  /// тогда допустим `http://`, и интерфейс показывает плашку.
  /// [overriddenOf] — то же, но ЖИВЫМ вопросом (важнее [overridden]), а
  /// [loadOverride] — чем прочитать подмену до первой проверки.
  /// [purgeRetryDelay] — через сколько после старта повторить чистку
  /// `updates/` (см. [startup]); [clock] — часы для срока [ConsentMarker].
  ///
  /// ⚠️ ПОЧЕМУ НЕ ХВАТАЕТ ФЛАГА НА КОНСТРУКТОРЕ. На Android подмена лежит
  /// файлом (`update_api.txt`) и читается асинхронно
  /// (`AppUpdate.loadApiOverride`) — а контроллер строится раньше. Флаг,
  /// снятый в конструкторе, на Android был бы `false` ВСЕГДА: стенд получал
  /// отказ `insecureUrl` на свой `http://`, а плашка «источник подменён» не
  /// появлялась ни разу.
  AppUpdateController({
    required AppSettings Function() settings,
    required Future<void> Function(AppSettings Function(AppSettings))
        updateSettings,
    required UpdateInstaller installer,
    UpdateChecker? checker,
    OfferBuilder? offerOf,
    BytesFetcher? fetchBytes,
    FileDownloader? downloader,
    bool Function()? isVpnActive,
    Listenable? vpnChanges,
    Future<void> Function()? openInstallPermission,
    String publicKeyBase64 = kUpdatePublicKeyBase64,
    bool overridden = false,
    bool Function()? overriddenOf,
    Future<void> Function()? loadOverride,
    String? currentVersion,
    Duration purgeRetryDelay = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : _settings = settings,
        _updateSettings = updateSettings,
        _installer = installer,
        _checker = checker ?? _defaultChecker,
        _offerOf = offerOf ?? UpdateOffer.fromRelease,
        _fetchBytes = fetchBytes ?? _noFetcher,
        _downloader = downloader ?? downloadToFile,
        _isVpnActive = isVpnActive ?? _neverActive,
        _vpnChanges = vpnChanges,
        _openInstallPermission = openInstallPermission ?? _noPermissionScreen,
        _publicKey = publicKeyBase64,
        _overridden = overridden,
        _overriddenOf = overriddenOf,
        _loadOverride = loadOverride,
        _currentVersion = currentVersion ?? AppUpdate.installedVersion,
        _purgeRetryDelay = purgeRetryDelay,
        _clock = clock ?? DateTime.now {
    _vpnChanges?.addListener(_onVpnChanged);
  }

  static Future<UpdateCheckResult> _defaultChecker({required bool beta}) =>
      AppUpdate.check(beta: beta);

  static bool _neverActive() => false;

  static Future<void> _noPermissionScreen() async {}

  /// Заглушка-маркер: настоящий [BytesFetcher] по умолчанию — [_fetchSmall],
  /// ему нужен каталог закачек, которого в списке инициализации ещё нет.
  static Future<List<int>> _noFetcher(Uri url,
          {required int maxBytes, http.Client? client}) =>
      throw StateError('fetchBytes не задан');

  // ── Состояние ─────────────────────────────────────────────────────────────

  UpdatePhase _phase = UpdatePhase.idle;
  UpdateOffer? _offer;
  double? _progress;
  UpdateError? _error;
  PendingResult? _lastOutcome;
  LinkOnlyReason? _linkOnlyReason;
  bool _awaitingVpnOff = false;

  /// Предложение выбрано человеком из «Прежних версий» ([offerRelease]), а
  /// не найдено проверкой. Такой выбор — явный: бета из истории ставится и
  /// при выключенном бета-канале (иначе откат на бету упирался бы в
  /// `channelMismatch`, хотя человек сам ткнул именно в неё).
  bool _explicitRelease = false;
  bool _postponed = false;
  bool _lastCheckManual = false;
  bool _started = false;
  bool _installing = false;
  bool _launched = false;
  bool _disposed = false;

  /// Скачанный и проверенный установщик (с версией и хэшем из манифеста).
  File? _verified;
  String? _verifiedVersion;
  String? _expectedSha;

  _DownloadRun? _run;
  int _generation = 0;

  /// Повторная чистка `updates/` после успешного обновления ([startup]).
  Timer? _purgeRetry;

  /// Намерение человека для текущей закачки ([downloadAndInstall]): поставить
  /// сразу после проверки и с каким согласием. `null` — просто скачать.
  ({bool forceQuit, bool allowDowngrade})? _intent;

  /// Согласие прошлой жизни процесса ([ConsentMarker]): версия, которую
  /// человек уже решил ставить, когда система убила нас за выдачу разрешения.
  ConsentMarker? _resumeConsent;

  UpdatePhase get phase => _phase;

  /// Что предлагается; остаётся и после «Позже»/«Пропустить» (интерфейс
  /// показывает, ЧТО именно пропущено).
  UpdateOffer? get offer => _offer;

  /// Доля закачки установщика 0..1; `null` — не качаем или размер неизвестен.
  double? get progress => _progress;

  UpdateError? get error => _error;

  /// Итог установки, запущенной в прошлой жизни процесса (`pending.json`).
  /// Заполняется в [startup]; `null` — ставить ничего не пытались.
  PendingResult? get lastOutcome => _lastOutcome;

  /// Источник обновлений подменён стендом — интерфейс показывает плашку.
  bool get overridden => _overriddenOf?.call() ?? _overridden;

  LinkOnlyReason? get linkOnlyReason => _linkOnlyReason;

  /// Установщик готов, но живой VPN не даём рвать: поставим, когда отключат.
  bool get waitingForVpnOff => _awaitingVpnOff;

  /// Человек нажал «Позже» — диалог второй раз в эту сессию не показывать.
  bool get postponed => _postponed;

  /// Последняя проверка была ручной («Проверить сейчас»): её отказ показывают,
  /// отказ автопроверки на старте — нет (человек её не просил).
  bool get lastCheckManual => _lastCheckManual;

  /// Текущее предложение равно версии, которую человек пропустил.
  bool get offerIsSkipped {
    final o = _offer;
    final skipped = _settings().appUpdateSkippedVersion;
    return o != null && skipped != null && _sameVersion(skipped, o.version);
  }

  /// Скачанный установщик — для «показать в папке» и журнала.
  File? get downloadedFile => _verified;

  /// Установщик уже запускали в этой сессии.
  bool get launched => _launched;

  String get currentVersion => _currentVersion;

  bool get started => _started;

  /// VPN сейчас активен — тем же выражением, что решает отложить установку.
  /// Интерфейсу нужно ДО нажатия: предупредить, что установка разорвёт VPN,
  /// и только после этого звать [install] с `forceQuit: true`.
  bool get vpnActive => _isVpnActive();

  /// Может ли эта копия ставить обновления сама ([InstallCapability.ready])
  /// — для «Прежних версий»: кнопка «Установить» там, где она сработает, и
  /// «Открыть» там, где нет. Решает установщик, а не интерфейс своим кодом:
  /// разрешение и исполнение обязаны спрашивать одно и то же.
  Future<InstallCapability> installCapability() => _installer.capability();

  /// Зовётся перед установкой, которую человек НЕ нажимал сам (режим «авто»
  /// и отложенная до отключения VPN): интерфейс показывает системное
  /// уведомление, если окно свёрнуто, — иначе приложение просто исчезло бы
  /// из трея без объяснений. Ошибка и зависание обработчика установку не
  /// останавливают (потолок — [_hookTimeout]).
  Future<void> Function(UpdateOffer offer)? beforeUnattendedInstall;

  static const _hookTimeout = Duration(seconds: 5);

  /// Идёт проверка, закачка или запуск установки.
  bool get busy =>
      _installing ||
      (_run != null && !_run!.cancelled) ||
      _phase == UpdatePhase.checking;

  @override
  void dispose() {
    _disposed = true;
    _vpnChanges?.removeListener(_onVpnChanged);
    _purgeRetry?.cancel();
    _run?.client.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setPhase(UpdatePhase p) {
    _phase = p;
    _notify();
  }

  void _fail(UpdateErrorKind kind,
      {ManifestRejection? rejection, String? detail}) {
    _progress = null;
    _error = UpdateError(kind,
        rejection: rejection, detail: detail == null ? null : scrubUrls(detail));
    AppLog.w('Обновление: отказ — $_error');
    _setPhase(UpdatePhase.failed);
  }

  void _linkOnly(LinkOnlyReason reason) {
    _linkOnlyReason = reason;
    AppLog.i('Обновление: только ссылка — ${reason.name}');
    _setPhase(UpdatePhase.linkOnly);
  }

  static bool _sameVersion(String a, String b) =>
      normalizeVersion(a) == normalizeVersion(b);

  // ── Запуск ────────────────────────────────────────────────────────────────

  /// Один раз после загрузки настроек: разобрать итог прошлой установки,
  /// вычистить `updates/`, при включённой автопроверке — проверить и
  /// поступить по режиму ([AppUpdateMode]).
  ///
  /// ⚠️ Пропущенная версия ([AppSettings.appUpdateSkippedVersion]) на старте
  /// молчит ([UpdatePhase.idle] + [offerIsSkipped]); [checkNow] её показывает
  /// — её спросили. Более новая версия снимает пропуск.
  Future<void> startup() async {
    if (_started || _disposed) return;
    _started = true;
    // Подмена источника (Android: файл в каталоге данных) — ДО всего
    // остального: от неё зависят и плашка, и допустимость `http://`.
    final load = _loadOverride;
    if (load != null) {
      try {
        await load();
      } catch (e) {
        AppLog.w('Обновление: подмена источника не прочитана: '
            '${scrubUrls('$e')}');
      }
      if (_disposed) return;
    }
    // Метку согласия — ДО чистки: чистка каталога закачек её бы стёрла.
    _resumeConsent = await _takeConsent();
    if (_disposed) return;
    try {
      _lastOutcome =
          await _installer.reconcileAfterStart(currentVersion: _currentVersion);
    } catch (e) {
      AppLog.w('Обновление: итог прошлой установки не разобран: '
          '${scrubUrls('$e')}');
    }
    try {
      // Журнал неудачной установки нужен кнопке «Показать журнал» — его
      // версию не трогаем; всё остальное в каталоге закачек — мусор.
      final outcome = _lastOutcome;
      final keep = outcome != null && outcome.outcome == PendingOutcome.failed
          ? outcome.pending.version
          : null;
      await _installer.purgeStaging(keepVersion: keep);
    } catch (e) {
      AppLog.w('Обновление: каталог закачек не вычищен: ${scrubUrls('$e')}');
    }
    // ⚠️ ПОСЛЕ ОБНОВЛЕНИЯ ЧИСТКА ПОВТОРЯЕТСЯ. Новую версию запускает сам
    // установщик (Inno, `ShouldRelaunch`) и ещё несколько секунд держит свой
    // exe открытым: первая чистка его не удаляет, и 90 МБ установщика лежали
    // в `updates/` до следующего запуска (живой прогон в VM 24.09.2026).
    if (_lastOutcome?.outcome == PendingOutcome.updated) {
      _purgeRetry = Timer(_purgeRetryDelay, _retryPurge);
    }
    _notify();
    if (_disposed) return;
    if (!_settings().appUpdateCheck) {
      AppLog.i('Обновление: автопроверка при запуске выключена');
      return;
    }
    await _check(manual: false);
  }

  /// «Проверить сейчас»: показывает и пропущенную версию, и причину отказа.
  Future<void> checkNow() => _check(manual: true);

  Future<void> _check({required bool manual}) async {
    if (_disposed) return;
    // Закачка или установка идут — проверка сверху перепутала бы состояние.
    if (_installing || (_run != null && !_run!.cancelled)) return;
    _lastCheckManual = manual;
    _error = null;
    _postponed = false;
    _setPhase(UpdatePhase.checking);
    final beta = _settings().betaChannel;
    UpdateCheckResult result;
    try {
      result = await _checker(beta: beta);
    } catch (e) {
      // `AppUpdate.check` сам не бросает; это на случай чужой реализации.
      AppLog.w('Обновление: проверка упала: ${scrubUrls('$e')}');
      result = const UpdateCheckResult.failed(
          'Не удалось связаться с сервером обновлений');
    }
    if (_disposed) return;
    await _applyCheck(result, manual: manual);
  }

  Future<void> _applyCheck(UpdateCheckResult result,
      {required bool manual}) async {
    final release = result.release;
    switch (result.state) {
      case UpdateCheckState.failed:
        _error = UpdateError(UpdateErrorKind.checkFailed,
            detail: result.failure == null ? null : scrubUrls(result.failure!));
        AppLog.i('Обновление: проверка не удалась — '
            '${scrubUrls(result.failure ?? '')}');
        _setPhase(UpdatePhase.failed);
        return;
      case UpdateCheckState.upToDate:
        // Скачанного установщика больше нет смысла держать: последняя — у нас.
        await _dropVerified(purge: _verified != null);
        _offer = null;
        _linkOnlyReason = null;
        _setPhase(UpdatePhase.upToDate);
        return;
      case UpdateCheckState.available:
        break;
    }
    if (release == null) {
      _error = const UpdateError(UpdateErrorKind.checkFailed,
          detail: 'Сервер обновлений ответил непонятным образом');
      _setPhase(UpdatePhase.failed);
      return;
    }

    final offer = _offerOf(release);
    _linkOnlyReason = null;
    _explicitRelease = false;
    // Тот же установщик уже скачан и проверен (повторная проверка руками) —
    // качать заново нечего.
    if (_verified != null && _sameVersion(_verifiedVersion ?? '', offer.version)) {
      _offer = offer;
      _setPhase(UpdatePhase.ready);
      return;
    }
    await _dropVerified(purge: _verified != null);
    _offer = offer;
    AppLog.i('Обновление: доступна версия ${offer.version} '
        '(у нас $_currentVersion)');

    final skipped = _settings().appUpdateSkippedVersion;
    if (skipped != null && skipped.isNotEmpty) {
      if (_sameVersion(skipped, offer.version)) {
        if (!manual) {
          AppLog.i('Обновление: версия ${offer.version} пропущена — молчу');
          _setPhase(UpdatePhase.idle);
          return;
        }
      } else if (AppUpdate.isNewer(offer.version, skipped)) {
        // Пропуск относился к прежней версии — новее её человек не видел.
        await _updateSettings(
            (s) => s.copyWith(clearAppUpdateSkippedVersion: true));
      }
    }
    final consent = _resumeConsent;
    _resumeConsent = null;
    if (consent != null &&
        _sameVersion(consent.version, offer.version) &&
        _settings().appUpdateMode != AppUpdateMode.notifyOnly) {
      // Человек уже нажал «Обновить» в прошлой жизни процесса, а система
      // убила нас, когда он выдал разрешение на установку. Спрашивать второй
      // раз — то же нажатие дважды; продолжаем с того места.
      AppLog.i('Обновление: продолжаю ${offer.version} после выдачи '
          'разрешения на установку');
      if (consent.install) {
        await downloadAndInstall(forceQuit: consent.forceQuit);
      } else {
        await download();
      }
      return;
    }
    await _applyMode();
  }

  Future<void> _applyMode() async {
    switch (_settings().appUpdateMode) {
      case AppUpdateMode.ask:
        _setPhase(UpdatePhase.available);
      case AppUpdateMode.notifyOnly:
        _linkOnly(LinkOnlyReason.notifyOnly);
      case AppUpdateMode.auto:
        _setPhase(UpdatePhase.available);
        await download();
        // Установщик сам решит, ждать ли отключения VPN.
        if (_phase == UpdatePhase.ready) await _install(unattended: true);
    }
  }

  /// «Прежние версии»: предложить конкретный релиз (например, для отката).
  /// Дальше — [download] и [install] с `allowDowngrade: true`.
  void offerRelease(AppRelease release) {
    if (_disposed || busy) return;
    _offer = _offerOf(release);
    _explicitRelease = true;
    _intent = null;
    _verified = null;
    _verifiedVersion = null;
    _expectedSha = null;
    _error = null;
    _linkOnlyReason = null;
    _awaitingVpnOff = false;
    _setPhase(UpdatePhase.available);
  }

  // ── Закачка ───────────────────────────────────────────────────────────────

  /// Согласие на установку получено: скачать (если ещё не скачано) и
  /// поставить. [forceQuit] — человек видел предупреждение о разрыве VPN;
  /// [allowDowngrade] — осознанный откат из «Прежних версий».
  ///
  /// Намерение запоминается: если закачка упрётся в разрешение Android, оно
  /// переживёт и возврат из настроек ([resumeAfterPermission]), и смерть
  /// процесса ([ConsentMarker]).
  Future<void> downloadAndInstall(
      {bool forceQuit = false, bool allowDowngrade = false}) async {
    if (_disposed) return;
    _intent = (forceQuit: forceQuit, allowDowngrade: allowDowngrade);
    if (_phase != UpdatePhase.ready || _verified == null) await download();
    if (_phase == UpdatePhase.ready) {
      await _install(forceQuit: forceQuit, allowDowngrade: allowDowngrade);
    }
  }

  /// Android: человек вернулся с экрана разрешения, а процесс выжил (не
  /// выдал разрешение либо система нас не тронула). Повторить то, на чём
  /// остановились, с тем же согласием.
  Future<void> resumeAfterPermission() async {
    if (_disposed || _phase != UpdatePhase.needsPermission) return;
    final intent = _intent;
    if (_verified != null) {
      await _install(
          forceQuit: intent?.forceQuit ?? false,
          allowDowngrade: intent?.allowDowngrade ?? false);
    } else if (intent != null) {
      await downloadAndInstall(
          forceQuit: intent.forceQuit, allowDowngrade: intent.allowDowngrade);
    } else {
      await download();
    }
  }

  /// Скачать и проверить установщик текущего предложения. Итог —
  /// [UpdatePhase.ready], [UpdatePhase.linkOnly] (ставить самим нельзя) или
  /// [UpdatePhase.failed]. Согласие человека уже получено вызывающим.
  Future<void> download() async {
    if (_disposed) return;
    final offer = _offer;
    if (offer == null || _installing) return;
    final prev = _run;
    if (prev != null) {
      if (!prev.cancelled) return; // уже качаем — второй клик по кнопке
      // Отменённая доматывает своё (`.part` удаляется в downloadToFile) —
      // не начинать поверх, иначе двое пишут один файл.
      await prev.done.future;
      if (_disposed) return;
    }
    final run = _DownloadRun(++_generation, _newClient());
    _run = run;
    _error = null;
    _progress = null;
    _awaitingVpnOff = false;
    try {
      await _runDownload(run, offer);
    } finally {
      run.client.close();
      if (identical(_run, run)) _run = null;
      run.done.complete();
      _notify();
    }
  }

  Future<void> _runDownload(_DownloadRun run, UpdateOffer offer) async {
    bool live() => !_disposed && run.gen == _generation && !run.cancelled;

    final cap = await _installer.capability();
    if (!live()) return;
    if (cap != InstallCapability.ready) {
      _linkOnly(_reasonFor(cap));
      return;
    }
    if (!offer.canSelfUpdate) {
      _linkOnly(LinkOnlyReason.noSelfUpdate);
      return;
    }
    final assetName = offer.assetName!;
    if (!isSafeAssetName(assetName)) {
      _fail(UpdateErrorKind.unsafeAssetName);
      return;
    }
    final manifestUri = Uri.tryParse(offer.manifestUrl!);
    final signatureUri = Uri.tryParse(offer.signatureUrl!);
    final assetUri = Uri.tryParse(offer.assetUrl!);
    if (manifestUri == null ||
        signatureUri == null ||
        assetUri == null ||
        !_schemeAllowed(manifestUri) ||
        !_schemeAllowed(signatureUri) ||
        !_schemeAllowed(assetUri)) {
      _fail(UpdateErrorKind.insecureUrl);
      return;
    }

    // Разрешение на установку — ДО единого байта (см.
    // [UpdateInstaller.canInstallNow]): на Android его выдача убивает процесс.
    var allowed = true;
    try {
      allowed = await _installer.canInstallNow();
    } catch (e) {
      // Не узнали — качаем: [launch] спросит ещё раз и скажет честно.
      AppLog.w('Обновление: разрешение на установку не узнано: '
          '${scrubUrls('$e')}');
    }
    if (!live()) return;
    if (!allowed) {
      AppLog.w('Обновление: нет разрешения на установку — прошу его до '
          'закачки ${offer.version}');
      final intent = _intent;
      await _writeConsent(ConsentMarker(
        version: offer.version,
        install: intent != null,
        forceQuit: intent?.forceQuit ?? false,
        at: _clock().toUtc(),
      ));
      if (!live()) return;
      _setPhase(UpdatePhase.needsPermission);
      return;
    }

    _setPhase(UpdatePhase.verifying);
    final List<int> manifestBytes;
    final String signature;
    try {
      manifestBytes = await _fetch(manifestUri,
          maxBytes: kUpdateManifestMaxBytes, client: run.client);
      final sigBytes = await _fetch(signatureUri,
          maxBytes: kUpdateSignatureMaxBytes, client: run.client);
      signature = utf8.decode(sigBytes, allowMalformed: true).trim();
    } catch (e) {
      if (!live()) return;
      _fail(UpdateErrorKind.manifestUnavailable, detail: '$e');
      return;
    }
    if (!live()) return;

    if (!UpdateSignature.verify(manifestBytes, signature,
        publicKeyBase64: _publicKey)) {
      AppLog.e('Обновление: подпись манифеста ${offer.version} НЕ прошла — '
          'установщик качать не буду');
      _fail(UpdateErrorKind.badSignature);
      return;
    }
    final manifest =
        UpdateManifest.parse(utf8.decode(manifestBytes, allowMalformed: true));
    if (manifest == null) {
      _fail(UpdateErrorKind.manifestRejected,
          rejection: ManifestRejection.malformed);
      return;
    }
    final rejection = validateManifest(
      manifest,
      expectedVersion: offer.version,
      assetName: assetName,
      betaAllowed: _settings().betaChannel || _explicitRelease,
    );
    if (rejection != null) {
      AppLog.e('Обновление: манифест ${manifest.version} (${manifest.channel}) '
          'не подходит к релизу ${offer.version}: ${rejection.name}');
      _fail(UpdateErrorKind.manifestRejected, rejection: rejection);
      return;
    }
    final asset = manifest.assetNamed(assetName)!;
    if (offer.assetSize != null && offer.assetSize != asset.size) {
      AppLog.w('Обновление: размер актива в релизе (${offer.assetSize}) '
          'не равен манифесту (${asset.size}) — верю манифесту');
    }

    final Directory dir;
    try {
      dir = await _installer.stagingDir();
    } catch (e) {
      _fail(UpdateErrorKind.downloadFailed, detail: '$e');
      return;
    }
    final target = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    // Остаток прошлой закачки под тем же именем — не доверяем, качаем заново.
    _deleteQuiet(target);
    if (!live()) return;

    _setPhase(UpdatePhase.downloading);
    AppLog.i('Обновление: качаю установщик ${offer.version} '
        '(${asset.size} байт)');
    try {
      await _downloader(
        assetUri,
        target,
        expectedSize: asset.size,
        expectedSha256: asset.sha256,
        maxBytes: kUpdateAssetMaxBytes,
        client: run.client,
        onProgress: (received, total) {
          // Вторая линия отмены: закрытый клиент рвёт сокет, а это — на
          // случай, если кусок уже был в буфере. Исключение из onProgress
          // уходит в downloadToFile, и тот удаляет `.part`.
          if (!live()) throw const DownloadException('закачка отменена');
          final denom = total != null && total > 0 ? total : asset.size;
          _progress = (received / denom).clamp(0.0, 1.0);
          _notify();
        },
      );
    } catch (e) {
      _progress = null;
      if (!live()) {
        // Отмена: фазу уже сменил cancel(); `.part` удалил downloadToFile.
        _deleteQuiet(target);
        return;
      }
      _fail(UpdateErrorKind.downloadFailed, detail: '$e');
      return;
    }
    if (!live()) {
      _deleteQuiet(target);
      return;
    }
    _verified = target;
    _verifiedVersion = offer.version;
    _expectedSha = asset.sha256;
    _progress = null;
    AppLog.i('Обновление: установщик ${offer.version} скачан и проверен '
        '(${asset.size} байт, sha256 сошёлся)');
    _setPhase(UpdatePhase.ready);
  }

  /// `https://` всегда; `http://` — только при подменённом источнике (стенд):
  /// целостность там доказывает подпись, а не TLS.
  bool _schemeAllowed(Uri u) =>
      u.scheme == 'https' || (overridden && u.scheme == 'http');

  Future<List<int>> _fetch(Uri url,
      {required int maxBytes, http.Client? client}) {
    if (!identical(_fetchBytes, _noFetcher)) {
      return _fetchBytes(url, maxBytes: maxBytes, client: client);
    }
    return _fetchSmall(url, maxBytes: maxBytes, client: client);
  }

  /// Умолчание [BytesFetcher]: через ту же закачку, что и установщик, —
  /// редиректы с нашим UA на каждом хопе, потолок байт, `.part`. Файл живёт
  /// в каталоге закачек мгновение и читается в память.
  Future<List<int>> _fetchSmall(Uri url,
      {required int maxBytes, http.Client? client}) async {
    final dir = await _installer.stagingDir();
    final f = File('${dir.path}${Platform.pathSeparator}'
        '.fetch-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await _downloader(url, f, maxBytes: maxBytes, client: client);
      return await f.readAsBytes();
    } finally {
      _deleteQuiet(f);
    }
  }

  /// Клиент закачки: напрямую, мимо системного прокси (та же идиома, что у
  /// [downloadToFile] по умолчанию, — см. там, почему), с нашим UA. Свой,
  /// а не умолчание [downloadToFile], ради одного: [cancel] закрывает его и
  /// рвёт соединение немедленно, а не на следующем куске.
  static http.Client _newClient() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = AppInfo.userAgent;
    io.findProxy = (_) => 'DIRECT';
    return IOClient(io);
  }

  static LinkOnlyReason _reasonFor(InstallCapability cap) =>
      linkOnlyReasonFor(cap);

  /// Почему ставить самим нельзя — для интерфейса, который спрашивает
  /// [installCapability] заранее (диалог, «Прежние версии»): объяснение то же,
  /// что дал бы [download], без закачки ради него.
  static LinkOnlyReason linkOnlyReasonFor(InstallCapability cap) =>
      switch (cap) {
        InstallCapability.ready => LinkOnlyReason.noSelfUpdate,
        InstallCapability.portable => LinkOnlyReason.portable,
        InstallCapability.isolated => LinkOnlyReason.isolated,
        InstallCapability.notInstalled => LinkOnlyReason.notInstalled,
        InstallCapability.locationMismatch => LinkOnlyReason.locationMismatch,
        InstallCapability.elevated => LinkOnlyReason.elevated,
        InstallCapability.unsupported => LinkOnlyReason.unsupported,
      };

  /// Прервать закачку. Фаза — обратно в [UpdatePhase.available], `.part`
  /// удаляет [downloadToFile] по исключению от закрытого клиента.
  void cancel() {
    _awaitingVpnOff = false;
    final run = _run;
    if (run == null || run.cancelled) {
      _notify();
      return;
    }
    run.cancelled = true;
    _generation++;
    run.client.close();
    _progress = null;
    AppLog.i('Обновление: закачка ${_offer?.version} отменена');
    _setPhase(UpdatePhase.available);
  }

  // ── Установка ─────────────────────────────────────────────────────────────

  /// Запустить установщик скачанного и проверенного файла.
  ///
  /// [forceQuit] — человек согласился на разрыв живого VPN (Windows:
  /// `/FORCEQUIT`). Без него при активном VPN установка ОТКЛАДЫВАЕТСЯ:
  /// [waitingForVpnOff] и запуск сам по [vpnChanges]. [allowDowngrade] —
  /// осознанный откат из «Прежних версий»; без него версия не новее нашей —
  /// отказ [UpdateErrorKind.notNewer] (replay старого релиза).
  Future<void> install({bool forceQuit = false, bool allowDowngrade = false}) =>
      _install(forceQuit: forceQuit, allowDowngrade: allowDowngrade);

  /// [unattended] — установку никто не нажимал (режим «авто», отложенная до
  /// отключения VPN): перед запуском зовётся [beforeUnattendedInstall].
  Future<void> _install({
    bool forceQuit = false,
    bool allowDowngrade = false,
    bool unattended = false,
  }) async {
    if (_disposed) return;
    final offer = _offer;
    final file = _verified;
    final sha = _expectedSha;
    if (offer == null || file == null || sha == null) return;
    if (_installing || (_run != null && !_run!.cancelled)) return;
    _awaitingVpnOff = false;

    if (!allowDowngrade && !AppUpdate.isNewer(offer.version, _currentVersion)) {
      AppLog.e('Обновление: ${offer.version} не новее $_currentVersion — '
          'установка отклонена (защита от отката)');
      _fail(UpdateErrorKind.notNewer);
      return;
    }
    if (!forceQuit && _isVpnActive()) {
      _awaitingVpnOff = true;
      AppLog.i('Обновление: ${offer.version} готова, жду отключения VPN');
      _setPhase(UpdatePhase.ready);
      return;
    }

    _installing = true;
    _error = null;
    _setPhase(UpdatePhase.installing);
    try {
      final hook = beforeUnattendedInstall;
      if (unattended && hook != null) {
        try {
          await hook(offer).timeout(_hookTimeout);
        } catch (e) {
          AppLog.w('Обновление: уведомление перед установкой не показано: '
              '${scrubUrls('$e')}');
        }
        if (_disposed) return;
      }
      await _installer.launch(
        file,
        version: offer.version,
        expectedSha256: sha,
        forceQuit: forceQuit,
        allowDowngrade: allowDowngrade,
      );
      _launched = true;
    } on NeedsInstallPermission {
      _setPhase(UpdatePhase.needsPermission);
    } on UpdateInstallException catch (e) {
      _fail(UpdateErrorKind.installFailed, detail: e.message);
    } catch (e) {
      _fail(UpdateErrorKind.installFailed, detail: '$e');
    } finally {
      _installing = false;
      _notify();
    }
  }

  /// Android: открыть системный экран «устанавливать из этого приложения».
  /// По возвращении интерфейс зовёт [install] снова.
  Future<void> openInstallPermission() => _openInstallPermission();

  void _onVpnChanged() {
    if (_disposed || !_awaitingVpnOff) return;
    if (_phase != UpdatePhase.ready || _isVpnActive()) return;
    _awaitingVpnOff = false;
    AppLog.i('Обновление: VPN отключён — ставлю ${_offer?.version}');
    unawaited(_install(unattended: true));
  }

  // ── Решения человека ──────────────────────────────────────────────────────

  /// «Пропустить версию»: записать в настройки, убрать скачанное, замолчать
  /// до следующей — более новой — версии.
  Future<void> skipVersion() async {
    if (_disposed) return;
    final offer = _offer;
    if (offer == null) return;
    if (_run != null && !_run!.cancelled) cancel();
    await _updateSettings(
        (s) => s.copyWith(appUpdateSkippedVersion: offer.version));
    _awaitingVpnOff = false;
    _postponed = false;
    _intent = null;
    await _dropVerified(purge: true);
    AppLog.i('Обновление: версия ${offer.version} пропущена по просьбе '
        'пользователя');
    _setPhase(UpdatePhase.idle);
  }

  /// «Позже»: ничего не удалять и не забывать — только не показывать диалог
  /// повторно в эту сессию и не ставить самому по отключению VPN.
  void postpone() {
    if (_disposed) return;
    _postponed = true;
    _awaitingVpnOff = false;
    _notify();
  }

  Future<void> _dropVerified({required bool purge}) async {
    _verified = null;
    _verifiedVersion = null;
    _expectedSha = null;
    if (!purge) return;
    try {
      await _installer.purgeStaging();
    } catch (e) {
      AppLog.w('Обновление: каталог закачек не вычищен: ${scrubUrls('$e')}');
    }
  }

  static void _deleteQuiet(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Занят установщиком — уберёт purgeStaging следующего старта.
    }
  }

  void _retryPurge() {
    _purgeRetry = null;
    // Идёт своя закачка или лежит проверенный установщик — чистка снесла бы
    // его; остатки уберёт следующий старт.
    if (_disposed || busy || _verified != null) return;
    unawaited(_installer.purgeStaging().catchError((Object e) {
      AppLog.w('Обновление: повторная чистка каталога закачек не удалась: '
          '${scrubUrls('$e')}');
    }));
  }

  Future<File> _consentFile() async {
    final dir = await _installer.stagingDir();
    return File('${dir.path}${Platform.pathSeparator}${ConsentMarker.fileName}');
  }

  Future<void> _writeConsent(ConsentMarker m) async {
    try {
      await (await _consentFile())
          .writeAsString(jsonEncode(m.toJson()), flush: true);
    } catch (e) {
      AppLog.w('Обновление: метка согласия не записана: ${scrubUrls('$e')}');
    }
  }

  /// Прочитать и СРАЗУ удалить метку: второй старт её уже не увидит.
  Future<ConsentMarker?> _takeConsent() async {
    try {
      final f = await _consentFile();
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      _deleteQuiet(f);
      final m = ConsentMarker.tryParse(raw);
      if (m == null) return null;
      if (_clock().toUtc().difference(m.at).abs() > ConsentMarker.ttl) {
        AppLog.i('Обновление: метка согласия на ${m.version} устарела');
        return null;
      }
      return m;
    } catch (e) {
      AppLog.w('Обновление: метка согласия не прочитана: ${scrubUrls('$e')}');
      return null;
    }
  }
}

/// Согласие на установку, пережившее смерть процесса.
///
/// ⚠️ ЗАЧЕМ. На Android выдача разрешения «устанавливать из этого приложения»
/// убивает процесс (`am_kill … REQUEST_INSTALL_PACKAGES changed`). Человек
/// нажал «Обновить», выдал разрешение, вернулся — и видел то же окно заново.
/// Метка в каталоге закачек говорит следующему старту: эту версию уже решили
/// ставить. Живёт [ttl] — вернувшийся через сутки человек мог и передумать.
class ConsentMarker {
  static const fileName = 'consent.json';
  static const ttl = Duration(hours: 1);

  final String version;

  /// Просили поставить ([AppUpdateController.downloadAndInstall]), а не
  /// только скачать.
  final bool install;

  /// Человек видел предупреждение о разрыве VPN.
  final bool forceQuit;
  final DateTime at;

  const ConsentMarker({
    required this.version,
    required this.install,
    required this.forceQuit,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'install': install,
        'forceQuit': forceQuit,
        'at': at.toUtc().toIso8601String(),
      };

  static ConsentMarker? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final v = m['version'];
      final at = DateTime.tryParse('${m['at']}');
      if (v is! String || v.isEmpty || at == null) return null;
      return ConsentMarker(
        version: v,
        install: m['install'] == true,
        forceQuit: m['forceQuit'] == true,
        at: at.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}
