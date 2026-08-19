import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/tun_scheduled_task.dart';

/// ЗАДАЧА ПЛАНИРОВЩИКА ОБЯЗАНА ЗАПУСКАТЬ ИМЕННО НАШУ ПРОГРАММУ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. Задача `SilentGateTun` создаётся один раз и не
/// пересматривается никогда: экран настроек первой строкой делает
/// `if (isConfigured()) return`. На машине владельца из-за этого живёт задача
/// от 20.07.2026 — она запускает **exe из папки сборки**
/// (`app\build\windows\x64\runner\Release`) и с голым `--tun-task`, без путей
/// конфига и stop-файла.
///
/// Последствия тихие и разные: после обновления интерфейс новый, а туннельное
/// ядро старое; правка с явными путями (#7 из 0.11.3) не применилась вовсе;
/// удалите папку сборки — и TUN перестанет подниматься, а выглядеть это будет
/// как «не работает VPN», потому что в журнале запуск задачи выглядит успешным.
///
/// ⚠️ Сравнение проверяется здесь, а не «живьём»: `isCurrent()` запускает
/// `schtasks`, и цена ошибки — запуск ЧУЖОГО бинаря под правами администратора.
void main() {
  /// Настоящий вывод `schtasks /Query /TN … /XML`, обрезанный до нужного.
  /// Кавычки в путях Планировщик хранит экранированными — как здесь.
  String xmlOf(String exe, String args) => '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Date>2026-07-20T00:00:00</Date></RegistrationInfo>
  <Principals><Principal id="Author"><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Actions Context="Author">
    <Exec>
      <Command>$exe</Command>
      <Arguments>$args</Arguments>
    </Exec>
  </Actions>
</Task>
''';

  const exe = r'C:\Users\User\AppData\Local\Programs\SilentGate\silentgate.exe';
  const args = r'--tun-task "C:\Users\User\AppData\Roaming\SilentGate\singbox_config.json" '
      r'"C:\Users\User\AppData\Roaming\SilentGate\tun_stop"';

  group('Совпадение задачи с ожидаемой командой', () {
    test('та же программа и те же пути — совпало', () {
      expect(TunScheduledTask.matches(xmlOf(exe, args), exe, args), isTrue);
    });

    test('⚠️ задача из папки сборки — НЕ совпало', () {
      // Ровно случай владельца: интерфейс установлен, а задача поднимает ядро
      // из каталога разработки, которого может уже не быть.
      const stale =
          r'I:\!Backup\!Projects\!VPN\SilentGateApp\app\build\windows\x64\runner\Release\silentgate.exe';
      expect(TunScheduledTask.matches(xmlOf(stale, args), exe, args), isFalse,
          reason: 'запуск чужого бинаря под правами администратора');
    });

    test('⚠️ голое --tun-task без путей — НЕ совпало', () {
      // Правка #7 (явные пути для учётки с отдельным админом) до установленной
      // задачи не доехала; без путей хелпер молча берёт СВОЙ %APPDATA%.
      expect(TunScheduledTask.matches(xmlOf(exe, '--tun-task'), exe, args),
          isFalse);
    });

    test('регистр пути значения не имеет', () {
      // Windows регистр не различает, а Планировщик отдаёт то, что записали.
      expect(TunScheduledTask.matches(xmlOf(exe.toUpperCase(), args), exe, args),
          isTrue);
    });

    test('⚠️ экранированные кавычки разворачиваются обратно', () {
      // Без этого сравнение не совпадало бы НИКОГДА: пути с пробелами
      // Планировщик хранит как &quot;. Задача всегда считалась бы устаревшей,
      // и запуск без UAC пропал бы у всех — то есть «починка» отняла бы
      // возможность, ради которой задача и заведена.
      final escaped = args.replaceAll('"', '&quot;');
      expect(TunScheduledTask.matches(xmlOf(exe, escaped), exe, args), isTrue);
    });

    test('мусор вместо XML — не совпало, а не исключение', () {
      // «Не знаю» обязано вести себя как «не подходит»: иначе на нечитаемом
      // ответе мы бы запустили что попало.
      expect(TunScheduledTask.matches('не xml вовсе', exe, args), isFalse);
      expect(TunScheduledTask.matches('', exe, args), isFalse);
    });
  });

  group('⚠️ Кодировка вывода schtasks', () {
    test('UTF-16LE с меткой порядка байт разбирается', () {
      // `schtasks /XML` печатает именно так. Прочитанный системной кодировкой,
      // он приходит мусором — и сравнение не совпадает ни разу.
      const text = '<Command>C:\\путь\\silentgate.exe</Command>';
      final bytes = <int>[0xFF, 0xFE];
      for (final u in text.codeUnits) {
        bytes..add(u & 0xFF)..add(u >> 8);
      }
      expect(TunScheduledTask.decodeUtf16(bytes), text);
      expect(TunScheduledTask.tag(TunScheduledTask.decodeUtf16(bytes), 'Command'),
          r'C:\путь\silentgate.exe');
    });

    test('без метки порядка байт тоже разбирается', () {
      const text = '<Arguments>--tun-task</Arguments>';
      final bytes = <int>[];
      for (final u in text.codeUnits) {
        bytes..add(u & 0xFF)..add(u >> 8);
      }
      expect(TunScheduledTask.decodeUtf16(bytes), text);
    });
  });
}
