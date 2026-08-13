import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/windows/support_report.dart';

/// ⚠️ УТЕЧКА ЖИЛА В ШАПКЕ ОТЧЁТА — НА ШЕСТЬДЕСЯТ СТРОК ВЫШЕ ОЧИЩЕННОГО ЖУРНАЛА.
///
/// Отчёт печатает «Выбран: <сервер>», а это `displayName`: у безымянного узла он
/// вырождается в боевой «адрес:порт». Строка собирается в интерфейсе и попадает
/// в буфер напрямую — мимо очистки журнала и мимо маскировки логов ядра. То есть
/// отчёт, который владелец отправляет постороннему человеку в чат, называл
/// адрес РОВНО ТОГО узла, о котором и пойдёт разговор.
///
/// Поэтому маска стоит там, где отчёт становится файлом, а не по секциям:
/// чинить по одной строке бессмысленно — следующая секция обойдёт очистку так
/// же, как обошли эта и логи ядер до неё.
void main() {
  const node = 'ru9.node.example';
  const port = 443;

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_report_');
    AppPaths.overrideRoot(tmp);
    SensitiveAddresses.remember(node);
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  SupportContext ctx({required String activeServer}) => SupportContext(
        statusLine: 'Подключено',
        subscriptionUrl: 'https://panel.example/sub/SECRET-TOKEN',
        serverCount: 12,
        activeServer: activeServer,
        activeCore: 'Xray',
        header: 'Отчёт SilentGate\nОпишите проблему:\n',
      );

  test('⚠️ адрес безымянного сервера не уходит в отчёт из шапки', () async {
    final path = await SupportReport.generate(
      settings: const AppSettings(),
      ctx: ctx(activeServer: '$node:$port'),
    );
    final text = await File(path).readAsString();

    expect(text, isNot(contains(node)),
        reason: 'ЗДЕСЬ БЫЛА ДЫРА: шапка шла в файл мимо всякой очистки');
    expect(text, contains('адрес №'),
        reason: 'место узла обязано остаться видимым, иначе отчёт не разобрать');
    expect(text, contains('Выбран:'), reason: 'строка сама по себе нужна');
    expect(text, contains('Xray'));
  });

  test('имя сервера, если оно есть, остаётся — по нему и разбирают', () async {
    final path = await SupportReport.generate(
      settings: const AppSettings(),
      ctx: ctx(activeServer: 'Германия 2.5'),
    );
    expect(await File(path).readAsString(), contains('Германия 2.5'));
  });

  test('шапка и журнал называют узел ОДНОЙ меткой', () async {
    // Иначе две секции одного отчёта нельзя сопоставить между собой — а ради
    // этого сопоставления отчёт и собирают.
    AppLog.i('Переключаюсь на запасной сервер: $node:$port');
    final path = await SupportReport.generate(
      settings: const AppSettings(),
      ctx: ctx(activeServer: '$node:$port'),
    );
    final text = await File(path).readAsString();

    final labels = RegExp(r'адрес №\d+').allMatches(text).map((m) => m[0]).toSet();
    expect(labels.length, 1,
        reason: 'один узел — одна метка на весь отчёт, а не по метке на секцию');
  });

  test('маскировка не съела маскировку токена подписки', () async {
    // Два барьера стоят рядом; проверяем, что второй проход не отменил первый.
    final path = await SupportReport.generate(
      settings: const AppSettings(),
      ctx: ctx(activeServer: 'Германия 2.5'),
    );
    expect(await File(path).readAsString(), isNot(contains('SECRET-TOKEN')));
  });
}
