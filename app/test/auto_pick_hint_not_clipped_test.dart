import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/auto_pick_button.dart';

/// ПОЯСНЕНИЕ У КНОПКИ ПОДБОРА ВИДНО ЦЕЛИКОМ, А НЕ ДО МНОГОТОЧИЯ.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА, ЖИВОЙ ПРОГОН 10.09.2026: «текст не особо понятен из-за
/// сокращений». В режиме `wide` подпись и пояснение стояли в ОДНУ строку (`Row`
/// из двух `Flexible`), панель списка серверов на минимальном окне 980×800 —
/// 380 px, и пояснение обрезалось до «проверит все 1 и под…». То есть исчезал
/// ровно тот текст, ради которого кнопку и переносили к списку.
///
/// ⚠️ ПОЧЕМУ НЕДОСТАТОЧНО ПРОВЕРИТЬ, ЧТО ВИДЖЕТ НА МЕСТЕ. Обрезка не роняет
/// вёрстку и не бросает исключения: `TextOverflow.ellipsis` — штатное
/// поведение. Виджет есть, тест зелёный, текста нет. Поэтому здесь спрашивается
/// само отрисованное: `RenderParagraph.didExceedMaxLines` — то самое поле, по
/// которому Flutter решает рисовать многоточие.
void main() {
  late Directory tmp;

  /// Три сервера: число подставляется в пояснение.
  const links = [
    'vless://11111111-2222-3333-4444-555555555555'
        '@a.example.com:443?encryption=none#Germany',
    'vless://11111111-2222-3333-4444-555555555555'
        '@b.example.com:443?encryption=none#Netherlands',
    'vless://11111111-2222-3333-4444-555555555555'
        '@c.example.com:443?encryption=none#USA',
  ];

  setUp(() {
    // ⚠️ Боевой `%APPDATA%` тестам недоступен (`AppPaths`), и это не
    // формальность: тест уже переписывал владельцу `subscriptions.json`.
    tmp = Directory.systemTemp.createTempSync('sg_auto_hint_');
    AppPaths.overrideRoot(tmp);
    File('${tmp.path}${Platform.pathSeparator}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    File('${tmp.path}${Platform.pathSeparator}subscriptions.json')
        .writeAsStringSync(jsonEncode({
      'activeId': 'sub-test',
      'items': [
        {
          'id': 'sub-test',
          'url': 'https://panel.example/sub',
          'title': 'Test',
          'servers': links,
          'addedAt': '2026-09-01T00:00:00.000Z',
        },
      ],
    }));
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// ⚠️ ЧЕРЕЗ `runAsync`: `AppState.init()` читает файлы с диска, а в
  /// поддельном времени `testWidgets` настоящие файловые операции не
  /// завершаются НИКОГДА — тест не падает, а виснет.
  Future<AppState> boot(WidgetTester t) async {
    final state = AppState(engine: _FakeEngine());
    await t.runAsync(() => state.init());
    return state;
  }

  /// ⚠️ ШРИФТ ТЕСТА КВАДРАТНЫЙ, И БЕЗ ПОПРАВКИ НА ЭТО СТРАЖ ВРАЛ БЫ.
  ///
  /// В `flutter_test` подставляется тестовый шрифт, у которого КАЖДЫЙ знак
  /// шириной ровно в кегль. Настоящие пропорциональные шрифты (Segoe UI,
  /// Roboto) в среднем вдвое уже. То есть на тестовом шрифте не помещается
  /// текст, который в жизни помещается с запасом, — и страж требовал бы
  /// раскладки, которой на экране не нужно.
  ///
  /// Поправка вносится масштабом текста ×0,5: это приводит ширину знака
  /// тестового шрифта к средней ширине знака настоящего. Она НЕ ослабляет
  /// стража — прежняя раскладка (`Row`) на ней краснеет (проверено мутацией):
  /// там пояснение получало примерно половину ширины кнопки и ОДНУ строку,
  /// а не всю ширину и две.
  const fontCalibration = 0.5;

  Widget host(AppState state, Locale locale, double width) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<SettingsController>.value(
              value: SettingsController()),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(fontCalibration)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              // Панель списка серверов на широком окне — ровно 380 px
              // (`HomeBody`), и кнопка в ней растянута во всю ширину.
              child: SizedBox(
                  width: width, child: const AutoPickServerButton(wide: true)),
            ),
          ),
        ),
      );

  /// Отрисованный абзац с пояснением. `Text` строит `RichText`, а тот —
  /// `RenderParagraph`, который один и знает, дошло ли дело до многоточия.
  RenderParagraph paragraphOf(WidgetTester t, String needle) {
    final all = t.renderObjectList<RenderParagraph>(find.byType(RichText));
    final hit = all.where((p) => p.text.toPlainText() == needle);
    expect(hit, isNotEmpty,
        reason: 'пояснение «$needle» не отрисовано вовсе — кнопка перестала '
            'объяснять, что она сделает');
    return hit.first;
  }

  /// Ширины: 380 — панель списка на широком окне, 320 — запас на будущее
  /// (панель бывает уже, и обрезка вернётся первой именно там).
  const widths = [380.0, 320.0];

  /// Языки: русский — база, немецкий и турецкий — самые длинные подписи из
  /// десяти. Обрезка приходит с самого длинного языка, а не с базового.
  const locales = [Locale('ru'), Locale('de'), Locale('tr')];

  for (final locale in locales) {
    for (final width in widths) {
      testWidgets(
          'пояснение видно целиком: ${locale.languageCode}, панель '
          '${width.toInt()} px', (t) async {
        t.view.physicalSize = const Size(1024, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        final state = await boot(t);
        await t.pumpWidget(host(state, locale, width));
        await t.pump();
        expect(t.takeException(), isNull);

        final l = lookupAppLocalizations(locale);
        final hint = l.homeAutoBestHint(3);
        final para = paragraphOf(t, hint);

        // ⚠️ ГЛАВНОЕ УТВЕРЖДЕНИЕ ФАЙЛА.
        expect(para.didExceedMaxLines, isFalse,
            reason: 'пояснение «$hint» обрезано многоточием на панели '
                '${width.toInt()} px (${locale.languageCode}) — человек снова '
                'видит «проверит все 3 и под…»');

        // И заодно: подпись кнопки тоже целая. Обрезать глагол — значит
        // потерять само название действия.
        expect(paragraphOf(t, l.homeAutoBest).didExceedMaxLines, isFalse,
            reason: 'обрезана уже сама подпись кнопки');
      });
    }
  }

  testWidgets('⚠️ пояснение стоит ПОД подписью и получает всю ширину кнопки',
      (t) async {
    // Вторая сторона того же дефекта, и она font-независима: пока подпись и
    // пояснение делили ОДНУ строку, пояснению доставался остаток ширины —
    // тем меньший, чем длиннее подпись на языке пользователя. Стоя под
    // подписью, оно получает всю ширину панели, и обрезка возвращается только
    // вместе с этой правкой.
    t.view.physicalSize = const Size(1024, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final state = await boot(t);
    await t.pumpWidget(host(state, const Locale('ru'), 380));
    await t.pump();

    final l = lookupAppLocalizations(const Locale('ru'));
    final label = t.getRect(find.text(l.homeAutoBest));
    final hint = t.getRect(find.text(l.homeAutoBestHint(3)));

    expect(hint.top, greaterThanOrEqualTo(label.bottom - 0.5),
        reason: 'пояснение снова встало в строку с подписью — на панели в '
            '380 px они делят ширину, и пояснение обрежется');
    expect(hint.left, closeTo(label.left, 0.5),
        reason: 'пояснение и подпись обязаны начинаться от одного края');
  });
}

class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => const Stream.empty();

  @override
  VpnStatus get status => const VpnStatus.disconnected();

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
