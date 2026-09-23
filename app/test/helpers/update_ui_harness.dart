import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/update_installer_fake.dart';
import 'package:silentgate/core/update/update_manifest.dart';
import 'package:silentgate/core/update/update_signature.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_update_controller.dart';
import 'package:silentgate/state/settings_controller.dart';

/// ОБВЯЗКА ДЛЯ ВИДЖЕТ-ТЕСТОВ ИНТЕРФЕЙСА САМООБНОВЛЕНИЯ.
///
/// Контроллер — НАСТОЯЩИЙ [AppUpdateController], подменены только его
/// зависимости: проверка (возвращает заданный релиз), установщик
/// ([FakeUpdateInstaller]), закачка манифеста/подписи/установщика (из памяти,
/// синхронной записью на диск — внутри `testWidgets` асинхронный ввод-вывод
/// зависает на подменных часах). Подпись настоящая, на своей паре ключей.
///
/// Каталог данных — временный (`AppPaths.overrideRoot`): боевой `%APPDATA%`
/// тесты не трогают никогда.
class UpdateUiHarness {
  UpdateUiHarness._(this.root);

  final Directory root;
  late final FakeUpdateInstaller installer;
  late final SettingsController settings;
  late final AppUpdateController controller;

  /// Что вернёт проверка.
  late UpdateCheckResult Function() checkResult;

  /// Байты по адресу — манифесты, подписи, установщики.
  final Map<String, List<int>> routes = {};

  /// Если задано — закачка установщика ждёт его (фаза «загрузка» видна).
  Completer<void>? downloadGate;

  bool vpnActive = false;

  /// Источник обновлений «подменён стендом» — читается контроллером ЖИВЬЁМ.
  bool overridden = false;
  final vpnSignal = _Signal();

  static const base = 'https://updates.test';
  static final _seed = List<int>.generate(32, (i) => (i * 37 + 11) & 0xff);
  static final publicKey = base64
      .encode(ed.public(ed.newKeyFromSeed(Uint8List.fromList(_seed))).bytes);

  /// Собрать обвязку. [current] — «установленная» версия.
  static UpdateUiHarness create({String current = '1.14.0'}) {
    final root = Directory.systemTemp.createTempSync('sg_update_ui_');
    AppPaths.overrideRoot(root);
    final h = UpdateUiHarness._(root);
    h.installer = FakeUpdateInstaller(
        staging: Directory('${root.path}${Platform.pathSeparator}updates'));
    h.settings = SettingsController();
    h.checkResult = () => const UpdateCheckResult.upToDate();
    h.controller = AppUpdateController(
      settings: () => h.settings.settings,
      // ⚠️ Без `await`: запись настроек на диск асинхронна и на подменных
      // часах `testWidgets` не завершается никогда; сама правка синхронна.
      updateSettings: (m) async => unawaited(h.settings.update(m)),
      installer: h.installer,
      checker: ({required bool beta}) async => h.checkResult(),
      fetchBytes: (url, {required int maxBytes, client}) async {
        final b = h.routes[url.toString()];
        if (b == null) throw HttpException('404', uri: url);
        return b;
      },
      downloader: (url, target,
          {expectedSize, expectedSha256, onProgress, client, maxBytes = 0}) async {
        final b = h.routes[url.toString()];
        if (b == null) throw HttpException('404', uri: url);
        onProgress?.call(b.length ~/ 2, b.length);
        final gate = h.downloadGate;
        if (gate != null) await gate.future;
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(b);
        onProgress?.call(b.length, b.length);
        return target.path;
      },
      isVpnActive: () => h.vpnActive,
      vpnChanges: h.vpnSignal,
      publicKeyBase64: publicKey,
      overriddenOf: () => h.overridden,
      currentVersion: current,
    );
    return h;
  }

  void dispose() {
    controller.dispose();
    AppPaths.resetForTests();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Опубликовать релиз с подписанным манифестом. Возвращает [AppRelease],
  /// который отдаст проверка (или «Прежние версии»).
  AppRelease publish(
    String version, {
    bool beta = false,
    String notes = '',
    bool selfUpdate = true,
  }) {
    final name = 'SilentGateSetup-$version.exe';
    final body = List<int>.generate(4096, (i) => (i * 131 + version.length) & 0xff);
    final manifest = UpdateManifest(
      version: version,
      channel: beta ? UpdateManifest.channelBeta : UpdateManifest.channelStable,
      assets: [UpdateAsset(name: name, size: body.length, sha256: Sha256.ofBytes(body))],
    );
    final manifestBytes = utf8.encode(manifest.toJson());
    routes['$base/$name'] = body;
    routes['$base/m-$version.json'] = manifestBytes;
    routes['$base/m-$version.sig'] =
        utf8.encode(UpdateSignature.sign(manifestBytes, _seed));
    return AppRelease(
      version: version,
      notes: notes,
      isBeta: beta,
      pageUrl: '$base/page/$version',
      downloadUrl: '$base/$name',
      assetName: selfUpdate ? name : null,
      assetSize: selfUpdate ? body.length : null,
      manifestUrl: selfUpdate ? '$base/m-$version.json' : null,
      signatureUrl: selfUpdate ? '$base/m-$version.sig' : null,
    );
  }

  /// Дерево с провайдерами и локализацией вокруг [child].
  Widget wrap(Widget child, {Locale locale = const Locale('ru')}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AppUpdateController>.value(value: controller),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: child,
        ),
      );
}

class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}
