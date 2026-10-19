import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/status_text.dart';
import 'package:silentgate/core/models/ui_message.dart';
import 'package:silentgate/core/net/network_error_hint.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/ui_message_l10n.dart';

/// MS1 S13: сообщения из `state/` и движка выходят на экран на языке
/// интерфейса, а не русской строкой.
///
/// Нашли проверяющие Google Play и прогон для Microsoft Store: при английском
/// интерфейсе — «Соединение восстановлено», «Выбран другой сервер —
/// переподключитесь», ошибка импорта про часы Windows.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ru = lookupAppLocalizations(const Locale('ru'));
  final cyr = RegExp('[А-Яа-яЁё]');

  // Все виды сообщений: каждый обязан дать НЕрусский текст в английском
  // интерфейсе. Новый вид без перевода роняет `switch` при компиляции, а
  // перевод, скопированный с русского, — этот тест.
  final all = <UiMessage>[
    const UiPingDone(verified: true, cancelled: false, ok: 3, total: 9, seconds: 4),
    const UiPingDone(verified: false, cancelled: true, ok: 1, total: 2, seconds: 0),
    const UiPingFailed(),
    const UiSpeedDone(cancelled: false, ok: 2, total: 3, seconds: 40),
    const UiSpeedDone(cancelled: true, ok: 0, total: 3, seconds: 1),
    const UiSpeedNeedsLive(),
    const UiAutoConfigDone(5),
    const UiAutoConfigDone(0),
    const UiAutoConfigUnsupported(),
    const UiAutoConfigUnsupported(long: true),
    const UiAutoConfigBadKey(),
    const UiAutoConfigNoneFound(),
    const UiAutoConfigError('SocketException'),
    const UiRestartServerChanged(),
    const UiRestartSubscriptionSwitched(),
    const UiServerNotFound('Germany 1'),
    for (final k in NetworkErrorKind.values) UiNetworkHint(k),
    const UiSubDeviceLimit('3'),
    const UiSubDeviceLimit(null),
    const UiSubHwidRequired(),
    const UiSubHttpCode(404),
    const UiSubNoServers(),
    const UiSubTooManyRedirects(),
  ];

  test('каждое сообщение переведено: в английском нет кириллицы', () {
    for (final m in all) {
      final t = uiMessageL10n(en, m);
      expect(t, isNotEmpty, reason: '$m');
      expect(cyr.hasMatch(t), isFalse, reason: '$m → $t');
    }
  });

  test('параметры доходят до текста и не путаются местами', () {
    final t = uiMessageL10n(en,
        const UiPingDone(verified: true, cancelled: false, ok: 3, total: 9, seconds: 4));
    expect(t, contains('3 of 9'));
    expect(t, contains('4 s'));
    expect(uiMessageL10n(ru, const UiServerNotFound('Germany 1')),
        'Сервер «Germany 1» не найден');
    expect(uiMessageL10n(en, const UiSubHttpCode(404)), contains('404'));
    expect(uiMessageL10n(en, const UiSubDeviceLimit('3')), contains('(3)'));
  });

  test('«рабочих» и «доступных» различаются по факту проверки', () {
    final v = uiMessageL10n(ru,
        const UiPingDone(verified: true, cancelled: false, ok: 1, total: 2, seconds: 1));
    final r = uiMessageL10n(ru,
        const UiPingDone(verified: false, cancelled: false, ok: 1, total: 2, seconds: 1));
    expect(v, contains('рабочих'));
    expect(r, contains('доступных'));
  });

  test('русский интерфейс совпадает с прежними строками движка', () {
    // Регресс: русский человек должен видеть ровно то же, что и раньше.
    expect(uiMessageL10n(ru, const UiRestartServerChanged()),
        'Выбран другой сервер — переподключитесь, чтобы применить');
    expect(uiMessageL10n(ru, const UiNetworkHint(NetworkErrorKind.noNetwork)),
        networkErrorHint('connection refused')?.text ??
            uiMessageL10n(ru, const UiNetworkHint(NetworkErrorKind.noNetwork)));
  });

  group('заметки движка', () {
    test('каждый вид даёт заголовок без кириллицы в английском', () {
      for (final kind in EngineNoticeKind.values) {
        // Эти два показываются своими ветками экрана, а не через перевод.
        if (kind == EngineNoticeKind.deadAppRule ||
            kind == EngineNoticeKind.geoAssetsBundled) {
          continue;
        }
        final t = engineNoticeL10n(
            en,
            EngineNotice(kind, 'Русский текст',
                detail: 'русская причина',
                reason: const StatusTrafficNotFlowing(),
                attempts: 8,
                subject: 'example.com'));
        expect(cyr.hasMatch(t.title), isFalse, reason: '$kind → ${t.title}');
        expect(cyr.hasMatch(t.detail ?? ''), isFalse,
            reason: '$kind → ${t.detail}');
      }
    });

    test('причина без кода не показывает русскую строку в английском', () {
      const n = EngineNotice(EngineNoticeKind.reconnecting,
          'Связь оборвалась, восстанавливаю',
          detail: 'ядро Xray остановилось (код 0)');
      expect(engineNoticeL10n(en, n).detail, isNull);
      // А в русском — показывает: там она и так понятна.
      expect(engineNoticeL10n(ru, n).detail, 'ядро Xray остановилось (код 0)');
    });

    test('причина кодом переводится', () {
      const n = EngineNotice(EngineNoticeKind.reconnecting, 'x',
          reason: StatusCoreStopped(core: 'Xray', code: 0));
      final t = engineNoticeL10n(en, n);
      expect(t.title, en.noticeReconnecting);
      expect(t.detail, contains('Xray'));
      expect(cyr.hasMatch(t.detail!), isFalse);
    });

    test('две ветки отказа различаются флагом, а не русским текстом', () {
      const still = EngineNotice(EngineNoticeKind.failed, 'x',
          attempts: 4, stillTrying: true);
      const gave = EngineNotice(EngineNoticeKind.failed, 'x', attempts: 8);
      expect(engineNoticeL10n(en, still).title, en.noticeStillDown);
      expect(engineNoticeL10n(en, gave).title, en.noticeRecoverFailed);
      expect(engineNoticeL10n(en, gave).detail, en.noticeAttemptsOnly(8));
    });

    test('блокировка показывает домен, выход — имя и что с трафиком', () {
      const b = EngineNotice(EngineNoticeKind.blocked, 'x', subject: 'ads.example');
      expect(engineNoticeL10n(en, b).detail, 'ads.example');
      const e = EngineNotice(EngineNoticeKind.exitDown, 'x',
          subject: 'Estonia', switched: true);
      final t = engineNoticeL10n(en, e);
      expect(t.title, contains('Estonia'));
      expect(t.detail, en.noticeExitDownSwitched);
    });
  });

  test('движок передаёт причину кодом на каждом пути переподключения', () {
    // Страж: вызов `scheduleRetry` без `why:` дал бы заметку, которую в
    // английском интерфейсе нечем пояснить.
    for (final f in [
      'lib/engine/engine_base.dart',
      'lib/engine/windows/windows_engine.dart',
      'lib/engine/android/android_engine.dart',
    ]) {
      final src = File(f).readAsStringSync();
      final calls = RegExp(r'scheduleRetry\(([^;]*?)\)\)?\s*[;{)]', dotAll: true)
          .allMatches(src)
          .map((m) => m.group(0)!)
          .where((c) => !c.contains('Future<bool>'))
          .toList();
      expect(calls, isNotEmpty, reason: f);
      for (final c in calls) {
        expect(c, contains('why'), reason: '$f: $c');
      }
    }
  });

  test('экраны не печатают русские литералы, найденные проверкой', () {
    final home = File('lib/ui/home_screen.dart').readAsStringSync();
    expect(home, isNot(contains("'Правила'")));
    final imp = File('lib/ui/import_screen.dart').readAsStringSync();
    expect(imp, isNot(contains("Text('Синхронизировать время')")));
    final route = File('lib/ui/widgets/route_diagram.dart').readAsStringSync();
    expect(route, contains('routeYourPhone'));
  });
}
