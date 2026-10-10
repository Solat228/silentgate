import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/ui/settings_screen.dart';

/// Страж текстов лицензий, которые едут ВНУТРИ приложения. На Android ядра
/// слинкованы в `libcores.so`, папки `licenses` рядом нет — значит, всё, что
/// требуют лицензии, обязано лежать в ассетах и открываться из «О программе».
void main() {
  test('каждый текст из диалога лежит на диске и непустой', () {
    for (final path in thirdPartyLicenseAssets.values) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: path);
      expect(f.lengthSync(), greaterThan(500), reason: path);
    }
  });

  test('ассеты лицензий объявлены в pubspec целой папкой', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/licenses/'));
  });

  test('MIT libXray: копирайт и текст разрешения на месте', () {
    final mit = File('assets/licenses/MIT-libXray.txt').readAsStringSync();
    expect(mit, contains('MIT License'));
    expect(mit, contains('XTLS'));
    expect(mit, contains('The above copyright notice and this permission notice'));
  });

  test('NOTICE ссылается на каждый файл с текстом лицензии', () {
    final notice = File('assets/licenses/NOTICE.txt').readAsStringSync();
    for (final path in thirdPartyLicenseAssets.values) {
      final name = path.split('/').last;
      if (name == 'NOTICE.txt') continue;
      expect(notice, contains(name), reason: name);
    }
  });
}
