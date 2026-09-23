import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// Настоящий Roboto из кэша Flutter SDK: тестовый шрифт по умолчанию рисует
/// каждую букву квадратом в кегль, и «ширина подписи» в нём ничего не значит.
/// `flutter_tester.exe` лежит в `bin/cache/artifacts/engine/<платформа>/`.
File? _roboto() {
  final engineDir = File(Platform.resolvedExecutable).parent;
  final f =
      File('${engineDir.parent.parent.path}/material_fonts/roboto-regular.ttf');
  return f.existsSync() ? f : null;
}

/// ПОДПИСИ ГРУПП У КНОПКИ CONNECT ЗАНИМАЮТ ПУСТУЮЩУЮ ШИРИНУ.
///
/// ⚠️ Жалоба владельца 24.09.2026: «имена и сами сервисы СЛИШКОМ маленькие,
/// хотя места полно». По его журналу: место 535×225, масштаб 0,70 — упирается
/// ВЫСОТА, а подпись была зажата в ширину ячейки и рисовалась кеглем
/// 9 × 0,70 ≈ 6 px при пустых полях по бокам.
void main() {
  final roboto = _roboto();
  setUpAll(() async {
    if (roboto == null) return;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(roboto.readAsBytesSync())));
    await loader.load();
  });
  setUp(() => AppPaths.overrideRoot(
      Directory.systemTemp.createTempSync('sg_label_size_')));
  tearDown(AppPaths.resetForTests);

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ServiceCheckController(),
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: const ServiceChecksSides(
              services: ServiceChecks.catalog,
              httpPort: 10809,
              button: SizedBox(width: 148, height: 148),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  double renderedHeight(WidgetTester tester, String text) =>
      tester.getRect(find.text(text)).height;

  testWidgets('⚠️ окно владельца 535×225: подпись крупнее прежних ~6 px',
      skip: roboto == null, (tester) async {
    await pump(tester, const Size(535, 225));
    expect(tester.takeException(), isNull);
    // Прежний кегль 9 при масштабе 0,70 и интерлиньяже 1.15 давал строку
    // ~7,2 px. Теперь одна строка кеглем до 14 при том же масштабе.
    expect(renderedHeight(tester, 'ИИ'), greaterThan(9.5));
  });

  testWidgets('кегль один на все группы — ни одна не мельче соседей',
      (tester) async {
    await pump(tester, const Size(535, 225));
    final heights = [
      for (final t in ['Мессенджеры', 'ИИ', 'Соцсети', 'Прочее'])
        renderedHeight(tester, t),
    ];
    for (final h in heights) {
      expect(h, closeTo(heights.first, 0.5),
          reason: 'подписи вразброс: $heights');
    }
  });

  testWidgets('подпись не шире своей половины и не вылезает за окно',
      (tester) async {
    for (final size in const [Size(535, 225), Size(393, 330), Size(900, 420)]) {
      await pump(tester, size);
      expect(tester.takeException(), isNull, reason: '$size');
      for (final t in ['Мессенджеры', 'Видео и музыка', 'Прочее']) {
        final r = tester.getRect(find.text(t));
        expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$t при $size');
        expect(r.right, lessThanOrEqualTo(size.width + 0.5),
            reason: '$t при $size');
      }
    }
  });

  test('одной строкой, когда ширина позволяет; двумя — когда нет', () {
    final rows = ServiceChecks.grouped(ServiceChecks.catalog);
    final l = lookupAppLocalizations(const Locale('ru'));
    final wide = ServiceChecksSides.labelFontFor(rows, l, width: 400);
    expect(wide.oneLine, isTrue);
    expect(wide.size, ServiceChecksSides.labelFontMax);
    final narrow = ServiceChecksSides.labelFontFor(rows, l, width: 40);
    expect(narrow.oneLine, isFalse);
    expect(
        narrow.size, lessThanOrEqualTo(ServiceChecksSides.labelFontTwoLines));
  });
}
