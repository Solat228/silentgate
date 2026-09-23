import 'dart:convert';
import 'dart:io';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/update_installer.dart';
import 'package:silentgate/core/update/update_installer_android.dart';
import 'package:silentgate/core/update/update_installer_fake.dart';
import 'package:silentgate/core/update/update_manifest.dart';
import 'package:silentgate/core/update/update_signature.dart';
import 'package:silentgate/state/app_update_controller.dart';

/// Контроллер самообновления — весь поток на ЛОКАЛЬНОМ сервере, с
/// собственной парой ключей и подменным установщиком.
///
/// ⚠️ Чего здесь нет намеренно: сети (сервер — `127.0.0.1` на случайном
/// порту), боевого `%APPDATA%` (`AppPaths.overrideRoot`), настоящего
/// установщика (`FakeUpdateInstaller`), вшитого ключа (пара генерируется в
/// `setUpAll`, публичный ключ внедряется в контроллер). Адреса в манифесте —
/// `http://127.0.0.1`, поэтому контроллер строится с `overridden: true`;
/// отдельный тест проверяет, что БЕЗ override `http://` отвергается до
/// первого запроса.
///
/// Что стережётся, и почему это важно:
///  * режим «спрашивать» не качает без согласия — иначе установщик на 60 МБ
///    качается у каждого при каждом запуске;
///  * «авто» не ставит при живом VPN — установщик закрывает приложение вместе
///    с ядрами, и человек остался бы без связи посреди работы;
///  * подпись проверяется ДО закачки установщика — иначе подменённый манифест
///    мог бы заставить качать что угодно;
///  * манифест другой версии (replay честно подписанного старого релиза)
///    отвергается;
///  * несовпавший хэш не оставляет файла — иначе `.part` или битый exe
///    подобрал бы следующий запуск;
///  * в журнале нет адресов — отчёт поддержки уходит посторонним.

/// Настройки в тесте — изменяемая ячейка вместо `SettingsController`, чтобы
/// не заводить хранилище на диске ради трёх полей.
class _Settings {
  AppSettings value;
  int updates = 0;
  _Settings(this.value);

  Future<void> update(AppSettings Function(AppSettings) mutate) async {
    value = mutate(value);
    updates++;
  }
}

/// Сигнал «состояние VPN поменялось» — то, что в приложении даёт `AppState`.
class _VpnSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Локальный сервер: путь → байты. `/slow` отдаёт первый кусок и молчит —
/// для теста отмены.
class _Server {
  late HttpServer _server;
  final Map<String, List<int>> routes = {};
  final List<String> requested = [];
  final List<HttpResponse> _hanging = [];
  int slowSize = 0;

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      requested.add(req.uri.path);
      final resp = req.response;
      if (req.uri.path == '/slow') {
        resp.headers.contentLength = slowSize;
        resp.add(List<int>.filled(1024, 7));
        await resp.flush();
        _hanging.add(resp);
        return;
      }
      final body = routes[req.uri.path];
      if (body == null) {
        resp.statusCode = HttpStatus.notFound;
        await resp.close();
        return;
      }
      resp.headers.contentLength = body.length;
      resp.add(body);
      await resp.close();
    });
  }

  Future<void> stop() async {
    for (final r in _hanging) {
      try {
        await r.close();
      } catch (_) {}
    }
    await _server.close(force: true);
  }
}

/// Один опубликованный релиз на локальном сервере: актив, манифест, подпись.
class _Published {
  final UpdateOffer offer;
  final List<int> body;
  final String sha;
  const _Published(this.offer, this.body, this.sha);
}

Future<void> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5), String? reason}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('не дождались: ${reason ?? 'условие'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory dir;
  late Directory staging;
  late _Server server;
  late FakeUpdateInstaller installer;
  late _Settings settings;
  late List<int> seed;
  late String publicKey;

  // Что вернёт проверка и как ответ превращается в предложение.
  late UpdateCheckResult Function() checkResult;
  final offers = <String, UpdateOffer>{};
  var checkerCalls = 0;
  final betaSeen = <bool>[];

  const current = '1.14.0';
  const next = '1.14.1';
  const assetName = 'SilentGateSetup-$next.exe';

  setUpAll(() {
    seed = List<int>.generate(32, (i) => (i * 37 + 11) & 0xff);
    publicKey = base64
        .encode(ed.public(ed.newKeyFromSeed(Uint8List.fromList(seed))).bytes);
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sg_app_update_ctl_');
    AppPaths.overrideRoot(dir);
    staging = Directory('${dir.path}${Platform.pathSeparator}updates');
    installer = FakeUpdateInstaller(staging: staging);
    settings = _Settings(AppSettings.defaults);
    server = _Server();
    await server.start();
    offers.clear();
    checkerCalls = 0;
    betaSeen.clear();
    checkResult = () => UpdateCheckResult.available(AppRelease(
        version: next,
        downloadUrl: '${server.base}/$assetName',
        pageUrl: '${server.base}/page'));
  });

  tearDown(() async {
    await server.stop();
    AppPaths.resetForTests();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Положить на сервер актив с манифестом и подписью. Параметры-«поломки»
  /// портят ровно одно звено, чтобы отказ был назван по имени.
  _Published publish({
    String version = next,
    String channel = UpdateManifest.channelStable,
    String name = assetName,
    List<int>? body,
    String? manifestVersion,
    String? manifestSha,
    int? manifestSize,
    bool badSignature = false,
    String? assetPath,
  }) {
    body ??= List<int>.generate(64 * 1024, (i) => (i * 131 + version.length) & 0xff);
    final sha = Sha256.ofBytes(body);
    final manifest = UpdateManifest(
      version: manifestVersion ?? version,
      channel: channel,
      assets: [
        UpdateAsset(
          name: name,
          size: manifestSize ?? body.length,
          sha256: manifestSha ?? sha,
        ),
      ],
    );
    final manifestBytes = utf8.encode(manifest.toJson());
    final sig = badSignature
        ? base64.encode(List<int>.filled(64, 1))
        : UpdateSignature.sign(manifestBytes, seed);
    server.routes['/$name'] = body;
    server.routes['/m-$version.json'] = manifestBytes;
    server.routes['/m-$version.sig'] = utf8.encode(sig);
    final offer = UpdateOffer(
      version: version,
      pageUrl: '${server.base}/page',
      assetName: name,
      assetSize: body.length,
      assetUrl: '${server.base}${assetPath ?? '/$name'}',
      manifestUrl: '${server.base}/m-$version.json',
      signatureUrl: '${server.base}/m-$version.sig',
    );
    offers[version] = offer;
    return _Published(offer, body, sha);
  }

  AppUpdateController make({
    bool overridden = true,
    bool Function()? isVpnActive,
    Listenable? vpnChanges,
    Future<void> Function()? openInstallPermission,
    String currentVersion = current,
  }) =>
      AppUpdateController(
        settings: () => settings.value,
        updateSettings: settings.update,
        installer: installer,
        checker: ({required bool beta}) async {
          checkerCalls++;
          betaSeen.add(beta);
          return checkResult();
        },
        offerOf: (r) => offers[r.version] ?? UpdateOffer.fromRelease(r),
        isVpnActive: isVpnActive,
        vpnChanges: vpnChanges,
        openInstallPermission: openInstallPermission,
        publicKeyBase64: publicKey,
        overridden: overridden,
        currentVersion: currentVersion,
      );

  File stagedFile(String name) =>
      File('${staging.path}${Platform.pathSeparator}$name');

  bool stagingHasAnything() =>
      staging.existsSync() &&
      staging.listSync().any((e) => !e.path.endsWith(PendingInstall.fileName));

  group('Режимы при запуске', () {
    test('«спрашивать»: доступно, но НИЧЕГО не качается без согласия',
        () async {
      publish();
      final c = make();
      final phases = <UpdatePhase>[];
      c.addListener(() {
        if (phases.isEmpty || phases.last != c.phase) phases.add(c.phase);
      });
      await c.startup();

      expect(c.phase, UpdatePhase.available);
      expect(c.offer?.version, next);
      expect(server.requested, isEmpty,
          reason: 'в режиме «спрашивать» до согласия ни манифест, ни '
              'установщик не запрашиваются');
      expect(installer.launches, isEmpty);
      expect(phases, containsAllInOrder([UpdatePhase.checking, UpdatePhase.available]),
          reason: 'смена фазы обязана уведомлять слушателей — по ней '
              'рисуется диалог');
      expect(installer.reconcileCalls, [current]);
      expect(installer.purgeCalls, [null]);
    });

    test('«авто» при выключенном VPN: скачано, проверено, установщик запущен',
        () async {
      final pub = publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make(isVpnActive: () => false);
      final progress = <double>[];
      c.addListener(() {
        final p = c.progress;
        if (p != null) progress.add(p);
      });
      await c.startup();

      expect(c.phase, UpdatePhase.installing);
      expect(c.launched, isTrue);
      expect(installer.launches, hasLength(1));
      final launch = installer.launches.single;
      expect(launch.version, next);
      expect(launch.expectedSha256, pub.sha);
      expect(launch.forceQuit, isFalse);
      expect(launch.allowDowngrade, isFalse);
      expect(launch.file.path, stagedFile(assetName).path,
          reason: 'файл лежит в каталоге закачек установщика под точным '
              'именем актива');
      expect(await Sha256.ofFile(launch.file), pub.sha);
      expect(progress, isNotEmpty, reason: 'ход закачки виден интерфейсу');
      expect(progress.every((p) => p >= 0 && p <= 1), isTrue);
      expect(c.progress, isNull, reason: 'после закачки полоска снимается');
      expect(server.requested, ['/m-$next.json', '/m-$next.sig', '/$assetName'],
          reason: 'манифест и подпись — ДО установщика');
    });

    test('«авто» при живом VPN: готово, но НЕ ставится; поставится по '
        'отключению VPN', () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      var vpn = true;
      final signal = _VpnSignal();
      final c = make(isVpnActive: () => vpn, vpnChanges: signal);
      await c.startup();

      expect(c.phase, UpdatePhase.ready);
      expect(c.waitingForVpnOff, isTrue);
      expect(installer.launches, isEmpty,
          reason: 'установщик закрывает приложение вместе с ядрами — при '
              'живом VPN сам не запускается');
      expect(stagedFile(assetName).existsSync(), isTrue);

      // Чужое уведомление при ВСЁ ЕЩЁ живом VPN ничего не запускает.
      signal.fire();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(installer.launches, isEmpty);

      vpn = false;
      signal.fire();
      await _waitFor(() => installer.launches.isNotEmpty,
          reason: 'установка по отключению VPN');
      expect(c.waitingForVpnOff, isFalse);
      expect(c.phase, UpdatePhase.installing);
      c.dispose();
    });

    test('«только сообщать»: ссылка, ни одного запроса за манифестом',
        () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.notifyOnly);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.linkOnly);
      expect(c.linkOnlyReason, LinkOnlyReason.notifyOnly);
      expect(c.offer?.pageUrl, '${server.base}/page');
      expect(server.requested, isEmpty);
      expect(installer.launches, isEmpty);
    });

    test('автопроверка выключена: проверки нет, но итог прошлой установки '
        'разобран', () async {
      publish();
      settings.value = settings.value.copyWith(appUpdateCheck: false);
      final c = make();
      await c.startup();

      expect(checkerCalls, 0);
      expect(c.phase, UpdatePhase.idle);
      expect(installer.reconcileCalls, [current],
          reason: '«не проверять» не значит «не узнать, чем кончилась '
              'установка, которую человек запустил вчера»');
      expect(installer.purgeCalls, [null]);
    });

    test('канал беты уходит в проверку как есть', () async {
      settings.value = settings.value.copyWith(betaChannel: true);
      checkResult = () => const UpdateCheckResult.upToDate();
      final c = make();
      await c.startup();
      expect(betaSeen, [true]);

      settings.value = settings.value.copyWith(betaChannel: false);
      await c.checkNow();
      expect(betaSeen, [true, false]);
    });

    test('startup идемпотентен: второй вызов не проверяет заново', () async {
      checkResult = () => const UpdateCheckResult.upToDate();
      final c = make();
      await c.startup();
      await c.startup();
      expect(checkerCalls, 1);
      expect(installer.reconcileCalls, hasLength(1));
    });
  });

  group('Пропущенная версия', () {
    test('на старте молчит, «Проверить сейчас» показывает', () async {
      publish();
      settings.value = settings.value.copyWith(appUpdateSkippedVersion: next);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.idle);
      expect(c.offerIsSkipped, isTrue);
      expect(c.offer?.version, next,
          reason: 'предложение хранится — интерфейс показывает, ЧТО пропущено');
      expect(server.requested, isEmpty);

      await c.checkNow();
      expect(c.phase, UpdatePhase.available);
      expect(c.lastCheckManual, isTrue);
    });

    test('пропуск в форме «v1.14.1» узнаётся как та же версия', () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateSkippedVersion: 'v$next');
      final c = make();
      await c.startup();
      expect(c.phase, UpdatePhase.idle);
      expect(c.offerIsSkipped, isTrue);
    });

    test('более новая версия снимает старый пропуск', () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateSkippedVersion: '1.14.0');
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.available);
      expect(settings.value.appUpdateSkippedVersion, isNull,
          reason: 'пропуск относился к 1.14.0 — 1.14.1 человек не видел');
    });

    test('skipVersion пишет настройку, убирает скачанное, молчит', () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make(isVpnActive: () => true);
      await c.startup();
      expect(c.phase, UpdatePhase.ready);
      installer.purgeCalls.clear();

      await c.skipVersion();

      expect(settings.value.appUpdateSkippedVersion, next);
      expect(c.phase, UpdatePhase.idle);
      expect(c.offerIsSkipped, isTrue);
      expect(c.downloadedFile, isNull);
      expect(c.waitingForVpnOff, isFalse);
      expect(installer.purgeCalls, [null],
          reason: 'скачанный установщик пропущенной версии — мусор');
    });

    test('postpone: фаза не меняется, автоустановка по VPN отменена',
        () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      var vpn = true;
      final signal = _VpnSignal();
      final c = make(isVpnActive: () => vpn, vpnChanges: signal);
      await c.startup();
      expect(c.waitingForVpnOff, isTrue);

      c.postpone();
      expect(c.postponed, isTrue);
      expect(c.phase, UpdatePhase.ready);
      expect(c.waitingForVpnOff, isFalse);

      vpn = false;
      signal.fire();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(installer.launches, isEmpty,
          reason: '«Позже» значит «не ставь сам»');
      c.dispose();
    });
  });

  group('Проверка манифеста — до единого байта установщика', () {
    test('плохая подпись: отказ, установщик не запрошен, файла нет',
        () async {
      publish(badSignature: true);
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.badSignature);
      expect(server.requested, isNot(contains('/$assetName')));
      expect(installer.launches, isEmpty);
      expect(stagingHasAnything(), isFalse);
    });

    test('манифест другой версии (replay старого релиза): отказ до закачки',
        () async {
      publish(manifestVersion: current);
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.manifestRejected);
      expect(c.error?.rejection, ManifestRejection.versionMismatch);
      expect(server.requested, isNot(contains('/$assetName')));
      expect(installer.launches, isEmpty);
    });

    test('бета-манифест при выключенном канале беты: отказ', () async {
      publish(channel: UpdateManifest.channelBeta);
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.rejection, ManifestRejection.channelMismatch);
      expect(server.requested, isNot(contains('/$assetName')));
    });

    test('манифест не JSON: отказ malformed', () async {
      publish();
      final junk = utf8.encode('{"version": ');
      server.routes['/m-$next.json'] = junk;
      server.routes['/m-$next.sig'] =
          utf8.encode(UpdateSignature.sign(junk, seed));
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.manifestRejected);
      expect(c.error?.rejection, ManifestRejection.malformed);
    });

    test('манифест недоступен (404): отказ manifestUnavailable', () async {
      publish();
      server.routes.remove('/m-$next.json');
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.manifestUnavailable);
      expect(server.requested, isNot(contains('/$assetName')));
    });
  });

  group('Закачка установщика', () {
    test('хэш не сошёлся: отказ, ни файла, ни .part', () async {
      publish(manifestSha: 'a' * 64);
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.downloadFailed);
      expect(server.requested, contains('/$assetName'));
      expect(installer.launches, isEmpty);
      expect(stagedFile(assetName).existsSync(), isFalse);
      expect(stagedFile('$assetName.part').existsSync(), isFalse);
      expect(c.downloadedFile, isNull);
    });

    test('размер в манифесте не сошёлся с ответом: отказ без файла',
        () async {
      publish(manifestSize: 12345);
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.downloadFailed);
      expect(stagingHasAnything(), isFalse);
    });

    test('портативная копия: только ссылка, запросов нет', () async {
      publish();
      installer.capabilityResult = InstallCapability.portable;
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.linkOnly);
      expect(c.linkOnlyReason, LinkOnlyReason.portable);
      expect(server.requested, isEmpty);
      expect(installer.launches, isEmpty);
    });

    test('релиз без манифеста/подписи: только ссылка (как до 1.14.0)',
        () async {
      // Предложение через штатный UpdateOffer.fromRelease — без полей
      // самообновления.
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.linkOnly);
      expect(c.linkOnlyReason, LinkOnlyReason.noSelfUpdate);
      expect(c.offer?.pageUrl, '${server.base}/page');
      expect(server.requested, isEmpty);
    });

    test('http:// без override отвергается ДО первого запроса', () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make(overridden: false);
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.insecureUrl);
      expect(server.requested, isEmpty);
      expect(c.overridden, isFalse);
    });

    test('имя актива с путём не подставляется в каталог', () async {
      final pub = publish();
      offers[next] = UpdateOffer(
        version: next,
        assetName: '..${Platform.pathSeparator}evil.exe',
        assetSize: pub.body.length,
        assetUrl: pub.offer.assetUrl,
        manifestUrl: pub.offer.manifestUrl,
        signatureUrl: pub.offer.signatureUrl,
      );
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make();
      await c.startup();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.unsafeAssetName);
      expect(server.requested, isEmpty);
      expect(File('${dir.path}${Platform.pathSeparator}evil.exe').existsSync(),
          isFalse);
    });

    test('отмена: фаза назад в available, .part убран, установка не идёт',
        () async {
      final pub = publish(assetPath: '/slow');
      server.slowSize = pub.body.length;
      final c = make();
      await c.startup();
      expect(c.phase, UpdatePhase.available);

      final downloading = c.download();
      await _waitFor(() => c.phase == UpdatePhase.downloading,
          reason: 'начало закачки');
      await _waitFor(() => server.requested.contains('/slow'),
          reason: 'запрос установщика ушёл');
      // Дать первому куску дойти — чтобы `.part` реально существовал.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      c.cancel();
      expect(c.phase, UpdatePhase.available);
      expect(c.progress, isNull);

      await downloading.timeout(const Duration(seconds: 5));
      expect(c.phase, UpdatePhase.available,
          reason: 'доматывающая отменённая закачка не имеет права менять фазу');
      expect(c.error, isNull);
      expect(stagedFile(assetName).existsSync(), isFalse);
      expect(stagedFile('$assetName.part').existsSync(), isFalse);
      expect(installer.launches, isEmpty);
      expect(c.busy, isFalse);

      // После отмены закачку можно начать заново (уже по нормальному адресу).
      publish();
      await c.checkNow();
      await c.download();
      expect(c.phase, UpdatePhase.ready);
    });

    test('повторная ручная проверка при готовом установщике не качает заново',
        () async {
      publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      final c = make(isVpnActive: () => true);
      await c.startup();
      expect(c.phase, UpdatePhase.ready);
      final requestsBefore = server.requested.length;

      await c.checkNow();
      expect(c.phase, UpdatePhase.ready);
      expect(server.requested.length, requestsBefore);
      expect(c.downloadedFile, isNotNull);
    });
  });

  group('Установка', () {
    test('версия не новее нашей: отказ notNewer; allowDowngrade ставит',
        () async {
      publish(version: current, name: 'SilentGateSetup-$current.exe');
      checkResult = () => UpdateCheckResult.available(
          AppRelease(version: current, downloadUrl: '${server.base}/page'));
      final c = make();
      await c.startup();
      expect(c.phase, UpdatePhase.available);
      await c.download();
      expect(c.phase, UpdatePhase.ready);

      await c.install();
      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.notNewer);
      expect(installer.launches, isEmpty,
          reason: 'честно подписанный СТАРЫЙ релиз — это откат; без явного '
              'согласия не ставится');

      await c.install(allowDowngrade: true);
      expect(c.phase, UpdatePhase.installing);
      expect(installer.launches, hasLength(1));
      expect(installer.launches.single.allowDowngrade, isTrue);
    });

    test('forceQuit при живом VPN ставит сразу и передаётся установщику',
        () async {
      publish();
      final c = make(isVpnActive: () => true);
      await c.startup();
      await c.download();
      expect(c.phase, UpdatePhase.ready);

      await c.install();
      expect(c.waitingForVpnOff, isTrue);
      expect(installer.launches, isEmpty);

      await c.install(forceQuit: true);
      expect(c.phase, UpdatePhase.installing);
      expect(installer.launches.single.forceQuit, isTrue);
      expect(c.waitingForVpnOff, isFalse);
    });

    test('Android: нет разрешения → needsPermission → экран → повтор',
        () async {
      publish();
      var opened = 0;
      installer.launchError = const NeedsInstallPermission();
      final c = make(openInstallPermission: () async => opened++);
      await c.startup();
      await c.download();
      await c.install();

      expect(c.phase, UpdatePhase.needsPermission);
      expect(c.error, isNull,
          reason: 'это не отказ, а шаг, который делает человек');
      expect(installer.launches, isEmpty);

      await c.openInstallPermission();
      expect(opened, 1);

      installer.launchError = null;
      await c.install();
      expect(c.phase, UpdatePhase.installing);
      expect(installer.launches, hasLength(1));
    });

    test('установщик не запустился: failed с installFailed', () async {
      publish();
      installer.launchError =
          const UpdateInstallException('файл обновления исчез');
      final c = make();
      await c.startup();
      await c.download();
      await c.install();

      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.installFailed);
      expect(c.error?.detail, 'файл обновления исчез');
    });

    test('install без скачанного файла — ничего не делает', () async {
      publish();
      final c = make();
      await c.startup();
      await c.install();
      expect(installer.launches, isEmpty);
      expect(c.phase, UpdatePhase.available);
    });
  });

  group('Итог прошлой установки', () {
    PendingResult pending(PendingOutcome outcome) => PendingResult(
          outcome: outcome,
          pending: PendingInstall(
            version: next,
            startedAt: DateTime.utc(2026, 9, 24),
            exePath: stagedFile(assetName).path,
            logPath: '',
          ),
          logTail: outcome == PendingOutcome.failed ? 'строка журнала' : null,
        );

    test('обновились: lastOutcome updated, каталог чистится целиком',
        () async {
      checkResult = () => const UpdateCheckResult.upToDate();
      installer.pendingResult = pending(PendingOutcome.updated);
      final c = make();
      await c.startup();

      expect(c.lastOutcome?.outcome, PendingOutcome.updated);
      expect(c.lastOutcome?.pending.version, next);
      expect(installer.purgeCalls, [null]);
      expect(c.phase, UpdatePhase.upToDate);
    });

    test('не завершилась: lastOutcome failed, журнал той версии сохранён',
        () async {
      checkResult = () => const UpdateCheckResult.upToDate();
      installer.pendingResult = pending(PendingOutcome.failed);
      final c = make();
      await c.startup();

      expect(c.lastOutcome?.outcome, PendingOutcome.failed);
      expect(c.lastOutcome?.logTail, 'строка журнала');
      expect(installer.purgeCalls, [next],
          reason: 'кнопке «Показать журнал» нужен файл этой версии');
    });
  });

  group('Проверка', () {
    test('последняя версия: upToDate, предложения нет', () async {
      checkResult = () => const UpdateCheckResult.upToDate();
      final c = make();
      await c.startup();
      expect(c.phase, UpdatePhase.upToDate);
      expect(c.offer, isNull);
      expect(c.error, isNull);
    });

    test('сервер недоступен: failed с checkFailed, без адресов в detail',
        () async {
      checkResult = () => const UpdateCheckResult.failed(
          'Не удалось связаться с сервером обновлений');
      final c = make();
      await c.startup();
      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.checkFailed);
      expect(c.lastCheckManual, isFalse,
          reason: 'отказ автопроверки интерфейс не показывает — её не просили');

      await c.checkNow();
      expect(c.lastCheckManual, isTrue);
    });

    test('проверка бросила исключение: failed, а не необработанная ошибка',
        () async {
      final c = AppUpdateController(
        settings: () => settings.value,
        updateSettings: settings.update,
        installer: installer,
        checker: ({required bool beta}) async =>
            throw StateError('сломано у ${server.base}/x'),
        publicKeyBase64: publicKey,
        overridden: true,
        currentVersion: current,
      );
      await c.startup();
      expect(c.phase, UpdatePhase.failed);
      expect(c.error?.kind, UpdateErrorKind.checkFailed);
    });

    test('offerRelease: явное предложение (для «Прежних версий»)', () async {
      final pub = publish(version: '1.13.9', name: 'SilentGateSetup-1.13.9.exe');
      checkResult = () => const UpdateCheckResult.upToDate();
      final c = make();
      await c.startup();
      expect(c.phase, UpdatePhase.upToDate);

      c.offerRelease(const AppRelease(version: '1.13.9'));
      expect(c.phase, UpdatePhase.available);
      expect(c.offer?.version, '1.13.9');
      await c.download();
      expect(c.phase, UpdatePhase.ready);
      expect(await Sha256.ofFile(c.downloadedFile!), pub.sha);

      await c.install();
      expect(c.error?.kind, UpdateErrorKind.notNewer);
      await c.install(allowDowngrade: true);
      expect(installer.launches.single.version, '1.13.9');
    });
  });

  group('UpdateOffer.fromRelease', () {
    test('полный релиз: поля самообновления переносятся, версия без v',
        () {
      final r = AppRelease(
        version: 'v1.14.1',
        downloadUrl: 'https://updates.example/SilentGateSetup-1.14.1.exe',
        assetName: 'SilentGateSetup-1.14.1.exe',
        assetSize: 100,
        manifestUrl: 'https://updates.example/SilentGate-1.14.1.manifest.json',
        signatureUrl: 'https://updates.example/SilentGate-1.14.1.manifest.sig',
        pageUrl: 'https://updates.example/page',
        notes: 'заметки',
        isBeta: true,
        publishedAt: DateTime.utc(2026, 9, 24),
      );
      expect(r.canSelfUpdate, isTrue, reason: 'предпосылка теста');
      final o = UpdateOffer.fromRelease(r);
      expect(o.version, '1.14.1');
      expect(o.canSelfUpdate, isTrue);
      expect(o.assetName, r.assetName);
      expect(o.assetSize, 100);
      expect(o.assetUrl, r.downloadUrl);
      expect(o.manifestUrl, r.manifestUrl);
      expect(o.signatureUrl, r.signatureUrl);
      expect(o.pageUrl, r.pageUrl);
      expect(o.notes, 'заметки');
      expect(o.isBeta, isTrue);
      expect(o.publishedAt, r.publishedAt);
    });

    test('релиз без подписи: самообновления нет, ссылка есть', () {
      const r = AppRelease(
        version: '1.14.1',
        downloadUrl: 'https://updates.example/SilentGateSetup-1.14.1.exe',
        assetName: 'SilentGateSetup-1.14.1.exe',
        assetSize: 100,
        manifestUrl: 'https://updates.example/m.json',
        pageUrl: 'https://updates.example/page',
      );
      expect(r.canSelfUpdate, isFalse, reason: 'предпосылка теста');
      final o = UpdateOffer.fromRelease(r);
      expect(o.canSelfUpdate, isFalse);
      expect(o.assetName, isNull,
          reason: 'половина набора бесполезна — не переносим ничего');
      expect(o.pageUrl, r.pageUrl);
      expect(o.assetUrl, r.downloadUrl);
    });
  });

  group('Безопасность имён и журнала', () {
    test('isSafeAssetName', () {
      expect(isSafeAssetName('SilentGateSetup-1.14.1.exe'), isTrue);
      expect(isSafeAssetName('SilentGate-1.14.1-arm64-v8a.apk'), isTrue);
      expect(isSafeAssetName(''), isFalse);
      expect(isSafeAssetName('..'), isFalse);
      expect(isSafeAssetName('.hidden'), isFalse);
      expect(isSafeAssetName('a/b.exe'), isFalse);
      expect(isSafeAssetName(r'a\b.exe'), isFalse);
      expect(isSafeAssetName('a b.exe'), isFalse);
      expect(isSafeAssetName('C:x.exe'), isFalse);
    });

    test('scrubUrls вырезает адреса любой схемы', () {
      expect(scrubUrls('ошибка https://h.example/p?token=1 дальше'),
          'ошибка <адрес> дальше');
      expect(scrubUrls('a http://127.0.0.1:8080/x b'), 'a <адрес> b');
      expect(scrubUrls('без адреса'), 'без адреса');
    });

    test('в журнале нет адресов после полного прогона и отказов', () async {
      final before = AppLog.entries.length;
      publish();
      settings.value =
          settings.value.copyWith(appUpdateMode: AppUpdateMode.auto);
      await make().startup();

      publish(badSignature: true);
      await make().startup();

      server.routes.remove('/m-$next.json');
      await make().startup();

      final lines = AppLog.entries
          .skip(before)
          .map((e) => e.message)
          .where((m) => m.contains('Обновление'))
          .toList();
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l, isNot(contains('://')), reason: l);
        expect(l, isNot(contains('127.0.0.1')), reason: l);
        expect(l, isNot(contains('${server.port}')), reason: l);
      }
    });
  });
}

extension on _Server {
  int get port => _server.port;
}
