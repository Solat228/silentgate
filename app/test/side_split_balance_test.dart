import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// СТОРОНЫ ДЕЛЯТСЯ ПОРОВНУ, А НЕ «КАК ПОЛУЧИТСЯ».
///
/// ⚠️ ЖИВОЙ СНИМОК ИЗ VM 04.09.2026: слева оказался ОДИН блок, справа ЧЕТЫРЕ,
/// и экран выглядел перекошенным. Тесты при этом были зелёными, потому что
/// проверяли отсутствие переполнения, а не равновесие.
///
/// Причина в том, что высота стороны считается ПО РЯДАМ (в ряду берётся самый
/// высокий блок), а блоков в ряду два. Сторона из одного блока и сторона из
/// двух дают ОДНУ И ТУ ЖЕ высоту — по высоте все разрезы равны, и выигрывал
/// просто первый по счёту.
///
/// ⚠️ Порядок групп при этом НЕ перетасовывается: ищется точка разреза, а не
/// лучшее сочетание. Перетасовка означала бы, что привычное место сервиса
/// меняется от набора к набору.
void main() {
  test('⚠️ пять групп делятся 2/3 или 3/2, а не 1/4', () {
    final split = ServiceChecks.grouped(ServiceChecks.catalog);
    expect(split.length, 5, reason: 'групп в приложении пять — см. ServiceGroup');

    final sides = ServiceChecksSides.splitForTest(split, dense: false);
    final l = sides.left.length;
    final r = sides.right.length;
    expect(l + r, 5, reason: 'группа потерялась при делении');
    expect((l - r).abs(), lessThanOrEqualTo(1),
        reason: 'стороны разошлись: слева $l, справа $r');
  });

  test('порядок групп сохраняется — сервис не меняет привычное место', () {
    final split = ServiceChecks.grouped(ServiceChecks.catalog);
    final sides = ServiceChecksSides.splitForTest(split, dense: false);
    expect([...sides.left, ...sides.right].map((g) => g.group).toList(),
        split.map((g) => g.group).toList());
  });

  test('одна группа — вся слева, справа пусто', () {
    final one = ServiceChecks.grouped(const [ProbeService.youtube]);
    final sides = ServiceChecksSides.splitForTest(one, dense: false);
    expect(sides.left, hasLength(1));
    expect(sides.right, isEmpty);
  });

  test('⚠️ в режиме «сетка» формулы описывают то, что рисуется', () {
    // Найдено ревью 05.09.2026 замером: формула ширины умножала блок на
    // число блоков В РЯДУ (то есть блоки бок о бок), а `_SideColumn` в этом
    // режиме строит колонку из `Wrap`-ов — каждая группа своей строкой, и
    // внутри строки иконки идут в одну линию.
    //
    // Расхождение стоило дорого: обе стороны получали коробки не по своему
    // содержимому, общий коэффициент переставал быть общим, и значки левой
    // половины выходили 25 px против 39 у правой — стоя в одной строке
    // вокруг кнопки.
    const three = [ProbeService.youtube, ProbeService.telegram,
        ProbeService.chatgpt];
    const two = [ProbeService.claude, ProbeService.gemini];
    final rows = ServiceChecks.grouped([...three, ...two]);
    expect(rows, isNotEmpty);

    // Ширину задаёт САМАЯ ДЛИННАЯ группа, а не число групп.
    final w = ServiceChecksSides.sideWidthOf(rows, dense: true, perRow: 2);
    final longest = rows
        .map((r) => r.services.length)
        .reduce((a, b) => a > b ? a : b);
    expect(w, closeTo(32.0 * longest + 6.0 * (longest - 1), 0.01),
        reason: 'ширина сетки снова считается по числу блоков, а не по '
            'самой длинной группе');

    // Высота — по строке на группу, а не по «две иконки в ряд».
    final h = ServiceChecksSides.sideHeightOf(rows, dense: true, perRow: 2);
    expect(h, closeTo((32.0 + 6.0 + 6.0) * rows.length, 0.01),
        reason: 'высота сетки снова считается с переносом, которого нет');
  });
}
