import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Страж значков.
///
/// ⚠️ ЗАЧЕМ ЭТО СУЩЕСТВУЕТ. Расширение `.ico` не проверяется НИГДЕ: ни Flutter,
/// ни плагин трея не смотрят внутрь файла. PNG, переименованный в `.ico`, даёт
/// `LoadImage -> NULL`, плагин всё равно рапортует успех, а трей оказывается
/// ПУСТЫМ — без исключения и без строчки в журнале. Такую поломку ищут часами,
/// хотя причина лежит в первых четырёх байтах файла.
///
/// Поэтому проверяем содержимое, а не имя.
void main() {
  /// Разбор ICONDIR: сигнатура, размеры кадров и целостность самих кадров.
  ///
  /// ⚠️ Заголовка НЕДОСТАТОЧНО. Он описывает кадры смещением и длиной, но ничем
  /// не связан с тем, что там лежит на самом деле: файл, обрезанный на середине,
  /// и файл со сбитыми смещениями имеют совершенно здоровый заголовок. Поэтому
  /// каждый кадр проверяется отдельно — попадает ли он в границы файла и
  /// начинается ли как PNG или как BITMAPINFOHEADER.
  ///
  /// Кадры у нас PNG-сжатые, и это НЕ ошибка: Windows понимает их с Vista, а наш
  /// сборщик значков кладёт PNG целиком. Проверено вызовом `LoadImageW` по всем
  /// трём файлам и трём размерам — шесть из шести вернули ненулевой HICON.
  /// ⚠️ При этом `System.Drawing` из .NET такие кадры НЕ читает и рисует шум —
  /// не принимать это за поломку значка, инструмент виноват, а не файл.
  ({bool isIcon, List<int> sizes, String? damage}) readIco(File f) {
    final b = f.readAsBytesSync();
    if (b.length < 6) return (isIcon: false, sizes: const [], damage: 'файл короче заголовка');
    final d = ByteData.sublistView(Uint8List.fromList(b));
    // ICONDIR: reserved=0, type=1 (значок), затем число кадров.
    final reserved = d.getUint16(0, Endian.little);
    final type = d.getUint16(2, Endian.little);
    final count = d.getUint16(4, Endian.little);
    if (reserved != 0 || type != 1 || count == 0) {
      return (isIcon: false, sizes: const [], damage: 'не ICONDIR');
    }
    final sizes = <int>[];
    String? damage;
    for (var i = 0; i < count; i++) {
      final o = 6 + i * 16;
      if (o + 16 > b.length) {
        return (isIcon: false, sizes: const [], damage: 'обрезан список кадров');
      }
      // 0 в поле ширины означает 256 — так задумано форматом.
      final w = b[o] == 0 ? 256 : b[o];
      sizes.add(w);

      final size = d.getUint32(o + 8, Endian.little);
      final off = d.getUint32(o + 12, Endian.little);
      if (size == 0 || off + size > b.length) {
        damage ??= 'кадр $w выходит за границы файла (смещение $off, длина $size, '
            'файл ${b.length})';
        continue;
      }
      // PNG (89 50 4E 47) либо DIB (первое поле BITMAPINFOHEADER = 40).
      final isPng = b[off] == 0x89 &&
          b[off + 1] == 0x50 &&
          b[off + 2] == 0x4E &&
          b[off + 3] == 0x47;
      final isDib = d.getUint32(off, Endian.little) == 40;
      if (!isPng && !isDib) {
        damage ??= 'кадр $w — ни PNG, ни DIB';
      }
    }
    return (isIcon: true, sizes: sizes, damage: damage);
  }

  final files = {
    'значок приложения и окна': File('windows/runner/resources/app_icon.ico'),
    'трей: VPN включён': File('assets/tray_icon.ico'),
    'трей: VPN выключен': File('assets/tray_icon_off.ico'),
  };

  files.forEach((name, f) {
    test('$name — настоящий .ico, а не переименованная картинка', () {
      expect(f.existsSync(), isTrue, reason: 'нет файла ${f.path}');
      final ico = readIco(f);
      expect(ico.isIcon, isTrue,
          reason: '${f.path} не начинается с ICONDIR — Windows его не загрузит, '
              'а трей останется пустым БЕЗ ошибки');
      // 16 нужен трею и заголовку окна, 32 — панели задач, 256 — крупным видам
      // проводника. Без мелких кадров Windows масштабирует 256-й и мылит.
      expect(ico.sizes, containsAll(<int>[16, 32, 256]),
          reason: 'в ${f.path} размеры ${ico.sizes} — не хватает обязательных');
      expect(ico.damage, isNull,
          reason: 'в ${f.path} повреждён кадр: ${ico.damage}. Заголовок при этом '
              'здоров — такую поломку видно только по самим кадрам');
    });
  });

  test('оба значка трея различаются — иначе состояние не видно', () {
    // Одинаковые файлы означали бы, что смена значка при подключении ничего не
    // меняет на экране, хотя код отработал и в журнале всё хорошо.
    final on = File('assets/tray_icon.ico').readAsBytesSync();
    final off = File('assets/tray_icon_off.ico').readAsBytesSync();
    expect(on, isNot(equals(off)));
  });

  test('значок трея не совпадает со значком приложения', () {
    // Ловит возврат к состоянию, когда оба файла были одной и той же
    // копией шаблонного значка Flutter.
    final tray = File('assets/tray_icon.ico').readAsBytesSync();
    final app = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    expect(tray, isNot(equals(app)),
        reason: 'у трея свой знак без подложки — если файлы совпали, значит '
            'кто-то скопировал один поверх другого');
  });

  test('значок трея объявлен в поставке', () {
    // Файл на диске, не попавший в pubspec, до пользователя не доедет: рядом с
    // exe его не окажется, и трей останется пустым.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final a in ['assets/tray_icon.ico', 'assets/tray_icon_off.ico']) {
      expect(pubspec, contains(a), reason: '$a не объявлен в pubspec.yaml');
    }
  });

  test('векторные значки Android на месте и без обрезки по краю', () {
    final stat = File('android/app/src/main/res/drawable/ic_stat_vpn.xml');
    expect(stat.existsSync(), isTrue);
    final xml = stat.readAsStringSync();
    expect(xml, contains('viewportWidth="24"'));
    // Знак обязан держаться внутри холста: форма, доходящая до края, срезается
    // системой, и правка самой фигуры этого не лечит — обрезка снаружи.
    //
    // ⚠️ Берём ТОЛЬКО абсолютные координаты команд M и L. Первая версия проверки
    // хватала все числа подряд из pathData — вместе с радиусами дуг и
    // относительными смещениями — и падала на здоровом значке. Проверка,
    // которая ругается на верную работу, хуже отсутствующей: её отключают.
    final data = RegExp(r'pathData="([^"]*)"')
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .join(' ');
    final points = RegExp(r'[ML](-?\d+\.?\d*),(-?\d+\.?\d*)')
        .allMatches(data)
        .expand((m) => [double.parse(m.group(1)!), double.parse(m.group(2)!)])
        .toList();
    expect(points, isNotEmpty, reason: 'в значке не нашлось ни одной точки');
    expect(points.every((v) => v >= 3.0 && v <= 21.0), isTrue,
        reason: 'координаты ${points.where((v) => v < 3 || v > 21)} выходят за '
            'безопасную область 3…21 из 24 — система срежет край');

    expect(
        File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
            .existsSync(),
        isTrue,
        reason: 'без адаптивного значка Android 8+ сам вписывает PNG в маску');
  });
}
