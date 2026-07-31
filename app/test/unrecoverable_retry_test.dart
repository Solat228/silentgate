import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/engine_base.dart';

/// Повтор лечит обрыв связи, но не отсутствующий файл. Случай из жизни:
/// исполняемый файл ядра пропал, и приложение перезапускалось 31 раз за сутки,
/// показывая «Переподключение…». Настоящую причину видел только тот, кто
/// открывал лог.
void main() {
  group('Неустранимые отказы не повторяются', () {
    test('пропавший файл ядра распознаётся на обоих языках', () {
      for (final r in [
        'ProcessException: Не удается найти указанный файл',
        'ProcessException: Не удаётся найти указанный файл',
        'ProcessException: The system cannot find the file specified',
        'ProcessException: The system cannot find the path specified',
        'FileSystemException: No such file or directory',
        'OS Error: ..., errno = 2',
      ]) {
        expect(VpnEngineBase.isUnrecoverableForTest(r), isTrue, reason: r);
      }
    });

    test('обычные сетевые обрывы повторять НАДО', () {
      for (final r in [
        'ядро завершилось',
        'сменилось сетевое окружение',
        'connection reset by peer',
        'i/o timeout',
        'connectex: No connection could be made because the target machine '
            'actively refused it',
      ]) {
        expect(VpnEngineBase.isUnrecoverableForTest(r), isFalse, reason: r);
      }
    });
  });
}
