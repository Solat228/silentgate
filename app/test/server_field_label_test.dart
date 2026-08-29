import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/i18n/enum_labels.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';

/// Человекочитаемые имена полей для значка «обновлён» на карточке сервера.
///
/// ⚠️ ЗАДАЧА ЯВНО ТРЕБУЕТ: если у поля нет понятного человеку названия —
/// показываем техническое имя как есть, а не выдумываем перевод.
void main() {
  final l = AppLocalizationsRu();

  test('поля с понятным названием переводятся', () {
    expect(serverFieldLabel(l, 'address'), l.srvInfoParamAddress);
    expect(serverFieldLabel(l, 'sni'), 'SNI');
    expect(serverFieldLabel(l, 'shortId'), isNot('shortId'),
        reason: 'shortId — ровно тот пример, который нельзя показывать сырым');
    expect(serverFieldLabel(l, 'host'), isNot('host'));
    expect(serverFieldLabel(l, 'path'), isNot('path'));
  });

  test('поле без понятного названия остаётся техническим именем, а не '
      'выдуманным переводом', () {
    for (final tech in ['alterId', 'flow', 'headerType', 'authority',
        'xhttpMode', 'xPadding', 'spiderX', 'allowInsecure']) {
      expect(serverFieldLabel(l, tech), tech);
    }
  });

  test('неизвестное имя поля тоже возвращается как есть — не падает', () {
    expect(serverFieldLabel(l, 'совсемНеизвестноеПоле'), 'совсемНеизвестноеПоле');
  });

  group('updatedServerTooltip', () {
    test('перечисляет человеческие имена полей через запятую', () {
      final msg = updatedServerTooltip(l, ['address', 'shortId']);
      expect(msg, contains(l.srvInfoParamAddress));
      expect(msg, contains('Short ID'));
      expect(msg, isNot(contains('shortId')),
          reason: 'сырое имя поля не должно попасть в текст для человека');
    });

    test('пустой список полей — обобщённая фраза, а не пустая строка', () {
      final msg = updatedServerTooltip(l, const []);
      expect(msg, l.srvTileUpdatedGeneric);
      expect(msg, isNotEmpty);
    });
  });
}
