# Локальный API SilentGate — план реализации

> **Для агентов:** ОБЯЗАТЕЛЬНЫЙ САБ-СКИЛЛ: `superpowers:subagent-driven-development`
> (рекомендуется) либо `superpowers:executing-plans`. Шаги помечены чекбоксами (`- [ ]`).

**Цель:** дать возможность гонять трафик через SilentGate из стороннего кода, выбирая сервер
для каждого запроса, и управлять клиентом по локальному HTTP-API с токеном.

**Архитектура:** новый режим захвата `proxyOnly` поднимает ядро без TUN и без системного прокси.
На каждый выбранный сервер добавляется свой локальный inbound с правилом
`inboundTag → outboundTag`, поверх уже работающей механики мульти-VPN. Управление — отдельный
`HttpServer` на loopback с токеном в `Authorization: Bearer`.

**Стек:** Dart/Flutter, `dart:io` (`HttpServer`, `ServerSocket`), Xray/sing-box как ядра.

**Спека:** `docs/LOCAL_API_DESIGN.md` — читать перед началом.

## Глобальные ограничения

- **Только Windows.** На Android API не поднимается: `Platform.isWindows` — обязательное условие
  старта слушателя и портов серверов. Правило проекта: где нет аутентификации или изоляции,
  канал не поднимается вовсе, а не поднимается «пока без пароля».
- **Только loopback.** `InternetAddress.loopbackIPv4`, никаких привязок к `0.0.0.0`.
- **Пустой токен = слушатель не поднимается.** Не «поднимается без проверки».
- **Токен выдаётся в одной точке и ДО старта слушателя.**
- **Запрос с заголовком `Origin` → 403.** Заголовков `Access-Control-Allow-*` не выдавать.
- **VPN на хосте не включать.** Проверки — статические (`flutter analyze`, `flutter test`,
  `sing-box check`). Живой прогон — за владельцем, в Hyper-V VM.
- **Все строки интерфейса — через ARB во все 10 языков.** Хардкод по-русски не допускается.
- **Комментарии и UI — на русском.**
- Порты: API `10870`, «Прямо» `10819`, серверы `10820…10859`.

---

### Задача 1: Настройки API

**Файлы:**
- Изменить: `app/lib/core/settings/app_settings.dart`
- Тест: `app/test/api_settings_test.dart` (создать)

**Интерфейсы:**
- Производит: `AppSettings.apiEnabled` (bool, умолчание `false`), `AppSettings.apiToken`
  (String, умолчание `''`), `AppSettings.apiExitServerKeys` (`List<String>`, умолчание `const []`).
  Ими пользуются задачи 3, 4, 8.

- [ ] **Шаг 1: Написать падающий тест**

Создать `app/test/api_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Настройки локального API.
///
/// ⚠️ Класс багов, ради которого этот тест существует: поле пишется в toJson,
/// но не читается в fromJson (или наоборот) — и молча сбрасывается при каждом
/// запуске. Компилятор такое не ловит, потому что toJson и fromJson независимы.
void main() {
  group('Умолчания', () {
    test('API выключен, токена нет, серверов нет', () {
      const s = AppSettings();
      expect(s.apiEnabled, isFalse, reason: 'API обязан быть ВЫКЛ по умолчанию');
      expect(s.apiToken, isEmpty);
      expect(s.apiExitServerKeys, isEmpty);
    });
  });

  group('Переживают диск', () {
    test('все три поля возвращаются как есть', () {
      const s = AppSettings(
        apiEnabled: true,
        apiToken: 'abc123',
        apiExitServerKeys: ['vless://a', 'vless://b'],
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.apiEnabled, isTrue);
      expect(back.apiToken, 'abc123');
      expect(back.apiExitServerKeys, ['vless://a', 'vless://b']);
    });

    test('старый файл без полей читается умолчаниями', () {
      final back = AppSettings.fromJson({'captureMode': 'tun'});
      expect(back.apiEnabled, isFalse);
      expect(back.apiToken, isEmpty);
      expect(back.apiExitServerKeys, isEmpty);
    });
  });

  group('copyWith не теряет поля', () {
    test('правка соседнего поля не сбрасывает настройки API', () {
      const s = AppSettings(
          apiEnabled: true, apiToken: 't', apiExitServerKeys: ['k']);
      final next = s.copyWith(killSwitch: true);
      expect(next.apiEnabled, isTrue);
      expect(next.apiToken, 't');
      expect(next.apiExitServerKeys, ['k']);
    });
  });

  group('Требуют переподключения', () {
    test('все три поля названы в reconnectReasons', () {
      // Поля запекаются в конфиг ядра при подъёме. Без строки здесь правка
      // не применялась бы до ручного переподключения, а плашка «переподключитесь»
      // не появлялась бы — пользователь считал бы настройку сломанной.
      const a = AppSettings();
      expect(a.reconnectReasons(a.copyWith(apiEnabled: true)),
          contains('API для автоматизации'));
      expect(a.reconnectReasons(a.copyWith(apiToken: 'x')),
          contains('токен API'));
      expect(a.reconnectReasons(a.copyWith(apiExitServerKeys: ['k'])),
          contains('серверы с отдельным портом'));
    });
  });
}
```

- [ ] **Шаг 2: Убедиться, что тест падает**

Запустить: `cd app && flutter test test/api_settings_test.dart`
Ожидается: ошибка компиляции «The named parameter 'apiEnabled' isn't defined».

- [ ] **Шаг 3: Добавить поля**

В `app/lib/core/settings/app_settings.dart` рядом с `localProxyAuth` (строка ~221) добавить:

```dart
  /// Локальный API для автоматизации: HTTP на 127.0.0.1 с токеном.
  ///
  /// ⚠️ ВЫКЛ ПО УМОЛЧАНИЮ И ЭТО НЕ ОСТОРОЖНИЧАНЬЕ. Управляющий порт опаснее
  /// прокси-порта: он умеет переключать сервер и читает состояние подписки.
  /// Кому он не нужен — у того ничего не слушает, и дыры нет.
  final bool apiEnabled;

  /// Токен API. Он же пароль портов отдельных серверов.
  ///
  /// ⚠️ ПУСТОЙ ТОКЕН ОЗНАЧАЕТ «КАНАЛ НЕ ПОДНИМАЕТСЯ», а не «поднимается без
  /// проверки». Полумера здесь опаснее отсутствия: порт, про который в
  /// интерфейсе написано «закрыт», а на деле пускающий кого угодно, хуже
  /// честно выключенного. То же правило уже закреплено для инбаундов ядра.
  ///
  /// ⚠️ Лежит на диске в открытом виде — это осознанный размен ради
  /// предсказуемого ключа между перезапусками, и он назван пользователю в
  /// интерфейсе. Тот же размен уже сделан для своих логина и пароля прокси.
  final String apiToken;

  /// Ключи серверов, которым выдан отдельный локальный порт.
  ///
  /// ⚠️ Отдельный список, а НЕ «все серверы подписки»: сотня серверов дала бы
  /// сотню инбаундов в конфиге ядра. И не «серверы из правил»: заводить
  /// фиктивное правило ради порта — костыль.
  final List<String> apiExitServerKeys;
```

В конструкторе (рядом со строкой ~452):

```dart
    this.apiEnabled = false,
    this.apiToken = '',
    this.apiExitServerKeys = const [],
```

В сигнатуре `copyWith` (рядом со строкой ~521):

```dart
    bool? apiEnabled,
    String? apiToken,
    List<String>? apiExitServerKeys,
```

В теле `copyWith` (рядом со строкой ~580):

```dart
      apiEnabled: apiEnabled ?? this.apiEnabled,
      apiToken: apiToken ?? this.apiToken,
      apiExitServerKeys: apiExitServerKeys ?? this.apiExitServerKeys,
```

В `toJson` (рядом со строкой ~641):

```dart
        'apiEnabled': apiEnabled,
        'apiToken': apiToken,
        'apiExitServerKeys': apiExitServerKeys,
```

В `fromJson` (рядом со строкой ~759):

```dart
      apiEnabled: j['apiEnabled'] as bool? ?? defaults.apiEnabled,
      apiToken: j['apiToken'] as String? ?? defaults.apiToken,
      apiExitServerKeys:
          (j['apiExitServerKeys'] as List?)?.cast<String>() ??
              defaults.apiExitServerKeys,
```

В `reconnectReasons` (рядом со строкой ~886):

```dart
    // Все три запекаются в конфиг ядра при подъёме: тумблер решает, поднимать
    // ли инбаунды серверов, токен становится их паролем, список — их составом.
    diff('API для автоматизации', apiEnabled, other.apiEnabled);
    diff('токен API', apiToken, other.apiToken);
    diff('серверы с отдельным портом', apiExitServerKeys.join(','),
        other.apiExitServerKeys.join(','));
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Запустить: `cd app && flutter test test/api_settings_test.dart`
Ожидается: PASS, 6 тестов.

- [ ] **Шаг 5: Прогнать страж роундтрипа**

Запустить: `cd app && flutter test test/settings_roundtrip_test.dart`
Ожидается: PASS. Этот тест перебирает ВСЕ ключи `toJson` и упадёт, если поле не читается обратно.

- [ ] **Шаг 6: Коммит**

```bash
git add app/lib/core/settings/app_settings.dart app/test/api_settings_test.dart
git commit -m "API: настройки — тумблер, токен и список серверов с отдельным портом"
```

---

### Задача 2: Режим захвата «Только прокси»

**Файлы:**
- Изменить: `app/lib/core/settings/app_settings.dart` (enum `CaptureMode`, строка 11)
- Изменить: `app/lib/engine/windows/windows_engine.dart` (`systemProxyModeFor`, строки 68-77;
  ветка захвата в `startSession`, строки ~315-330)
- Тест: `app/test/proxy_only_mode_test.dart` (создать)

**Интерфейсы:**
- Потребляет: ничего из задачи 1.
- Производит: `CaptureMode.proxyOnly`. Им пользуются задачи 3 и 8.

- [ ] **Шаг 1: Написать падающий тест**

Создать `app/test/proxy_only_mode_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Режим захвата «Только прокси».
///
/// Смысл режима: ядро поднимается, локальные порты слушают, а машина при этом
/// НЕ в туннеле — через VPN идёт только тот, кто явно целится в порт.
void main() {
  group('Значение перечисления', () {
    test('proxyOnly существует и не ломает разбор старых файлов', () {
      expect(CaptureMode.values, contains(CaptureMode.proxyOnly));
      // Старый файл со значением 'tun' обязан читаться как прежде: добавление
      // значения в конец перечисления не должно сдвигать разбор.
      expect(AppSettings.fromJson({'captureMode': 'tun'}).captureMode,
          CaptureMode.tun);
      expect(AppSettings.fromJson({'captureMode': 'systemProxy'}).captureMode,
          CaptureMode.systemProxy);
    });

    test('переживает диск', () {
      const s = AppSettings(captureMode: CaptureMode.proxyOnly);
      expect(AppSettings.fromJson(s.toJson()).captureMode,
          CaptureMode.proxyOnly);
    });
  });

  group('Kill switch недоступен в этом режиме', () {
    test('killSwitchApplies ложно только для proxyOnly', () {
      // Он держит трафик МАШИНЫ, а машина здесь и так не в туннеле. Включённый
      // тумблер, который ничего не делает, — ровно тот класс дефектов, за
      // который в этом проекте платили дороже всего.
      expect(
          const AppSettings(captureMode: CaptureMode.proxyOnly)
              .killSwitchApplies,
          isFalse);
      expect(
          const AppSettings(captureMode: CaptureMode.tun).killSwitchApplies,
          isTrue);
      expect(
          const AppSettings(captureMode: CaptureMode.systemProxy)
              .killSwitchApplies,
          isTrue);
    });
  });
}
```

- [ ] **Шаг 2: Убедиться, что тест падает**

Запустить: `cd app && flutter test test/proxy_only_mode_test.dart`
Ожидается: ошибка «The getter 'proxyOnly' isn't defined for the type 'CaptureMode'».

- [ ] **Шаг 3: Добавить значение и геттер**

В `app/lib/core/settings/app_settings.dart` строка 11 заменить:

```dart
/// Как перехватывается трафик.
///
/// ⚠️ `proxyOnly` ДОБАВЛЯЕТСЯ В КОНЕЦ. Разбор идёт по имени (`pick(...)`), но
/// порядок значений всё равно менять нельзя: на него смотрят сравнения и
/// сортировки, а старые файлы настроек хранят имя.
///
/// * `systemProxy` — прописываем прокси в реестр WinINET, программы идут через
///   него сами;
/// * `tun` — виртуальный адаптер забирает весь трафик машины;
/// * `proxyOnly` — ядро поднято, локальные порты слушают, но машина НЕ в
///   туннеле: через VPN идёт только тот, кто явно целится в порт.
enum CaptureMode { systemProxy, tun, proxyOnly }
```

Рядом с полем `captureMode` (строка ~157) добавить геттер в класс `AppSettings`:

```dart
  /// Имеет ли kill switch смысл при текущем захвате.
  ///
  /// ⚠️ В режиме «только прокси» — нет. Kill switch удерживает трафик МАШИНЫ на
  /// время переподключения, а машина здесь и так ходит мимо туннеля. Тумблер,
  /// который виден и ничего не делает, хуже отсутствующего.
  bool get killSwitchApplies => captureMode != CaptureMode.proxyOnly;
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Запустить: `cd app && flutter test test/proxy_only_mode_test.dart`
Ожидается: PASS, 3 теста.

- [ ] **Шаг 5: Научить движок новому режиму**

В `app/lib/engine/windows/windows_engine.dart` заменить `systemProxyModeFor` (строки 68-77):

```dart
  /// ⚠️ СМЕШАННЫЙ РЕЖИМ — ТОЖЕ СИСТЕМНЫЙ ПРОКСИ. При `alsoSetSystemProxy`
  /// прокси прописывается ДОПОЛНИТЕЛЬНО к туннелю, и в локальный порт снова
  /// смотрит WinINET, который креденшелов не передаёт.
  ///
  /// ⚠️ А `proxyOnly` — НЕ системный прокси, хотя туннеля там тоже нет. В порт
  /// смотрит не WinINET, а конкретная программа, умеющая передать логин и
  /// пароль. Верни здесь `true` — и порт откроется без пароля именно в том
  /// режиме, который заведён ради стороннего кода.
  @override
  bool systemProxyModeFor(ConnectionOptions options) =>
      options.captureMode == CaptureMode.systemProxy ||
      options.settings.alsoSetSystemProxy;
```

В `startSession`, в ветке выбора захвата (строки ~315-330), заменить условие поднятия
системного прокси:

```dart
      // ⚠️ `proxyOnly` не ставит НИ системный прокси, НИ туннель. Прежнее
      // условие `!= CaptureMode.tun` считало бы его системным прокси и прописало
      // бы адрес в реестр — то есть увело бы туда весь трафик машины, ровно
      // против смысла режима.
      final wantProxy = options.captureMode == CaptureMode.systemProxy ||
          options.settings.alsoSetSystemProxy;
```

- [ ] **Шаг 6: Прогнать весь набор**

Запустить: `cd app && flutter analyze && flutter test`
Ожидается: анализатор без ошибок; все тесты зелёные.

⚠️ Если упадут тесты, перебирающие `CaptureMode.values` и ожидающие ровно два значения, —
это не регресс, а устаревшее ожидание. Правь ожидание, а не перечисление.

- [ ] **Шаг 7: Коммит**

```bash
git add app/lib/core/settings/app_settings.dart app/lib/engine/windows/windows_engine.dart app/test/proxy_only_mode_test.dart
git commit -m "Режим захвата «Только прокси»: ядро без туннеля и без системного прокси"
```

---

### Задача 3: Порт на каждый выбранный сервер

**Файлы:**
- Создать: `app/lib/core/net/api_ports.dart`
- Изменить: `app/lib/core/singbox/singbox_config_builder.dart` (инбаунды и правила)
- Изменить: `app/lib/state/app_state.dart` (`_exitServers`, строка ~1587)
- Тест: `app/test/api_ports_test.dart` (создать)

**Интерфейсы:**
- Потребляет: `AppSettings.apiExitServerKeys`, `AppSettings.apiToken` (задача 1),
  `exitTagFor(String serverKey)` из `core/singbox/exit_tags.dart`.
- Производит: `ApiPorts.control` (int, 10870), `ApiPorts.direct` (int, 10819),
  `ApiPorts.forServer(List<String> sortedKeys, String key)` → `int?`,
  `apiExitInboundTag(String serverKey)` → `String`. Ими пользуются задачи 4, 5, 8.

- [ ] **Шаг 1: Написать падающий тест**

Создать `app/test/api_ports_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_ports.dart';

/// Раскладка портов локального API.
///
/// ⚠️ Порядок обязан быть детерминированным: скрипт хардкодит номер порта, и
/// «дышащая» между запусками раскладка увела бы запрос в другую страну — молча
/// и без единой ошибки.
void main() {
  group('Раскладка', () {
    test('управляющий порт и порт «Прямо» фиксированы', () {
      expect(ApiPorts.control, 10870);
      expect(ApiPorts.direct, 10819);
    });

    test('серверы получают порты по возрастанию ключа', () {
      // Ключи нарочно переданы НЕ по порядку: функция обязана отсортировать их
      // сама, тем же способом, что и ExitOutbounds.build.
      final keys = ['vless://c', 'vless://a', 'vless://b'];
      expect(ApiPorts.forServer(keys, 'vless://a'), 10820);
      expect(ApiPorts.forServer(keys, 'vless://b'), 10821);
      expect(ApiPorts.forServer(keys, 'vless://c'), 10822);
    });

    test('неизвестный ключ порта не получает', () {
      expect(ApiPorts.forServer(['vless://a'], 'vless://zzz'), isNull);
    });

    test('сверх диапазона порта нет', () {
      // 40 портов — 10820..10859. Сорок первый обязан вернуть null, а не 10860:
      // молча заехать в чужой диапазон хуже, чем честно отказать.
      final keys = [for (var i = 0; i < 41; i++) 'vless://${i.toString().padLeft(3, '0')}'];
      expect(ApiPorts.forServer(keys, keys[39]), 10859);
      expect(ApiPorts.forServer(keys, keys[40]), isNull);
    });

    test('пустой список никому ничего не даёт', () {
      expect(ApiPorts.forServer(const [], 'vless://a'), isNull);
    });
  });

  group('Теги инбаундов', () {
    test('тег выводится из ключа и стабилен', () {
      final a = apiExitInboundTag('vless://a');
      expect(a, apiExitInboundTag('vless://a'));
      expect(a, isNot(apiExitInboundTag('vless://b')));
      expect(a, startsWith('api-exit-'));
    });
  });
}
```

- [ ] **Шаг 2: Убедиться, что тест падает**

Запустить: `cd app && flutter test test/api_ports_test.dart`
Ожидается: «Target of URI doesn't exist: 'package:silentgate/core/net/api_ports.dart'».

- [ ] **Шаг 3: Написать раскладку портов**

Создать `app/lib/core/net/api_ports.dart`:

```dart
import '../singbox/exit_tags.dart';

/// Раскладка локальных портов API.
///
/// ⚠️ ПОРЯДОК — ЧАСТЬ КОНТРАКТА. Скрипт хардкодит номер порта; «дышащая» между
/// запусками раскладка увела бы запрос в другую страну молча и без ошибки.
/// Поэтому ключи сортируются тем же способом, что в `ExitOutbounds.build`.
class ApiPorts {
  /// Управляющий HTTP-API.
  static const int control = 10870;

  /// «Прямо» — мимо VPN, реальный IP. Нужен, чтобы сравнивать «через VPN» и
  /// «без VPN» одной строкой кода, не выключая туннель.
  static const int direct = 10819;

  /// Первый порт диапазона серверов.
  static const int firstServer = 10820;

  /// Сколько серверов могут получить порт.
  ///
  /// ⚠️ Ограничение осмысленное, а не круглое число: каждый порт — это ещё один
  /// inbound в конфиге ядра. Сорок с запасом покрывает любой реальный набор.
  static const int maxServers = 40;

  /// Порт сервера [key] среди [keys]. `null` — ключа нет или он сверх диапазона.
  static int? forServer(List<String> keys, String key) {
    final sorted = [...keys]..sort();
    final i = sorted.indexOf(key);
    if (i < 0 || i >= maxServers) return null;
    return firstServer + i;
  }

  /// Ключи, которым порт реально достанется (первые [maxServers] по порядку).
  static List<String> withinRange(List<String> keys) {
    final sorted = [...keys]..sort();
    return sorted.length <= maxServers
        ? sorted
        : sorted.sublist(0, maxServers);
  }
}

/// Тег inbound-а, ведущего в сервер [serverKey].
///
/// ⚠️ Выводится из ТОГО ЖЕ ключа, что и тег outbound-а (`exitTagFor`), поэтому
/// правило `inboundTag → outboundTag` не может разъехаться. Разойдись они хоть
/// на символ — правило сослалось бы на несуществующий outbound, а `sing-box
/// check` этого НЕ ловит: конфиг принимается с кодом 0, а трафик уходит в
/// `route.final`, то есть мимо выбранного сервера.
String apiExitInboundTag(String serverKey) =>
    'api-${exitTagFor(serverKey)}';
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Запустить: `cd app && flutter test test/api_ports_test.dart`
Ожидается: PASS, 6 тестов.

- [ ] **Шаг 5: Коммит раскладки**

```bash
git add app/lib/core/net/api_ports.dart app/test/api_ports_test.dart
git commit -m "API: детерминированная раскладка локальных портов"
```

- [ ] **Шаг 6: Написать падающий тест на конфиг**

Дописать в `app/test/api_ports_test.dart` новую группу:

```dart
  group('Конфиг ядра', () {
    test('на каждый живой сервер есть inbound и правило', () {
      const keyA = 'vless://a';
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        apiExitServerKeys: const [keyA],
        apiToken: 'secret',
      );
      final cfg = builder.buildMap();
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      final mine = ins.firstWhere((i) => i['tag'] == apiExitInboundTag(keyA));
      expect(mine['listen'], '127.0.0.1');
      expect(mine['listen_port'], 10820);
      expect(mine['users'], [
        {'username': 'sg', 'password': 'secret'}
      ]);
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();
      expect(
          rules.any((r) =>
              (r['inbound'] as List?)?.contains(apiExitInboundTag(keyA)) == true &&
              r['outbound'] == exitTagFor(keyA)),
          isTrue,
          reason: 'нет правила inboundTag -> outboundTag');
    });

    test('⚠️ ссылка на НЕсобравшийся сервер порта не создаёт', () {
      // Сервер могли удалить из подписки, а его протокол может не подниматься
      // вторым туннелем. Оба случая обязаны привести к отсутствию порта, а не к
      // висячему тегу: висячий sing-box check пропускает молча, и трафик уходит
      // в route.final — то есть НЕ туда, куда целился скрипт.
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: const [], // outbound не собрался
        apiExitServerKeys: const ['vless://a'],
        apiToken: 'secret',
      );
      final cfg = builder.buildMap();
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => '${i['tag']}'.startsWith('api-exit-')), isFalse);
    });

    test('пустой токен инбаундов не создаёт', () {
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: [
          {'tag': exitTagFor('vless://a'), 'type': 'vless'},
        ],
        apiExitServerKeys: const ['vless://a'],
        apiToken: '',
      );
      final cfg = builder.buildMap();
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => '${i['tag']}'.startsWith('api-exit-')), isFalse,
          reason: 'пустой токен означает «канал не поднимается»');
    });
  });
```

Добавить в шапку файла импорты:

```dart
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
```

- [ ] **Шаг 7: Убедиться, что тест падает**

Запустить: `cd app && flutter test test/api_ports_test.dart`
Ожидается: «The named parameter 'apiExitServerKeys' isn't defined».

- [ ] **Шаг 8: Научить построитель конфига**

В `app/lib/core/singbox/singbox_config_builder.dart` в поля класса (рядом с `exitOutbounds`,
строка ~481) добавить:

```dart
  /// Ключи серверов, которым выдаётся отдельный локальный порт (см. `ApiPorts`).
  final List<String> apiExitServerKeys;

  /// Токен API — он же пароль этих инбаундов. Пусто — инбаунды не создаются.
  final String apiToken;
```

В конструктор:

```dart
    this.apiExitServerKeys = const [],
    this.apiToken = '',
```

Добавить метод сборки инбаундов (рядом с `_liveExitTags`):

```dart
  /// Инбаунды отдельных портов: по одному на сервер из [apiExitServerKeys].
  ///
  /// ⚠️ ТОЛЬКО ЖИВЫЕ. Сервер, чей outbound не собрался, порта не получает —
  /// иначе правило сослалось бы на несуществующий тег, `sing-box check`
  /// пропустил бы это молча, и трафик скрипта ушёл бы в `route.final`, то есть
  /// мимо выбранного сервера. Источник правды — `_liveExitTags`.
  List<Map<String, dynamic>> get _apiExitInbounds {
    if (apiToken.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    final keys = ApiPorts.withinRange(apiExitServerKeys);
    for (final key in keys) {
      if (!_liveExitTags.contains(exitTagFor(key))) continue;
      final port = ApiPorts.forServer(apiExitServerKeys, key);
      if (port == null) continue;
      out.add({
        'type': 'mixed',
        'tag': apiExitInboundTag(key),
        'listen': '127.0.0.1',
        'listen_port': port,
        'users': [
          {'username': 'sg', 'password': apiToken}
        ],
      });
    }
    return out;
  }

  /// Правила «этот порт — в этот сервер».
  List<Map<String, dynamic>> get _apiExitRules => [
        for (final i in _apiExitInbounds)
          {
            'inbound': [i['tag']],
            'action': 'route',
            'outbound': _outboundForApiInbound('${i['tag']}'),
          },
      ];

  /// Обратное преобразование тега инбаунда в тег outbound-а.
  String _outboundForApiInbound(String inboundTag) =>
      inboundTag.substring('api-'.length);
```

Подмешать в список инбаундов (там, где собираются остальные) `..._apiExitInbounds`, а в
`route.rules` — `..._apiExitRules` **ВЫШЕ пользовательских правил, но НИЖЕ блок-правил**.

⚠️ Порядок обязателен: выход выбран явно, поэтому правила «этот сайт — прямо» к нему не
применяются; но правила «Блок» применяются, иначе служебный вход стал бы способом обойти
собственные запреты пользователя.

Добавить импорт в шапку файла:

```dart
import '../net/api_ports.dart';
```

- [ ] **Шаг 9: Убедиться, что тесты проходят**

Запустить: `cd app && flutter test test/api_ports_test.dart`
Ожидается: PASS, 9 тестов.

- [ ] **Шаг 10: Подмешать серверы API в `exitServers`**

В `app/lib/state/app_state.dart` в `_exitServers` (строка ~1587) после сборки `wanted` добавить:

```dart
    // Серверы, которым пользователь выдал отдельный порт, тоже обязаны получить
    // outbound — иначе порт не создастся (построитель проверяет живые теги).
    for (final key in settings.apiExitServerKeys) {
      if (key.isNotEmpty) wanted.add(key);
    }
```

⚠️ Строку `wanted.remove(selectedServer?.key)` НЕ трогать: основной сервер сессии уже живёт под
тегом `proxy`, и дублировать его значило бы держать два соединения к одному узлу.

- [ ] **Шаг 11: Проверить порты перед стартом ядра**

Спека требует, чтобы новые порты проходили `PortCheck` наравне с остальными: конфликт обязан
называть процесс-держатель, а не падать с «Bad state».

В `app/lib/engine/windows/windows_engine.dart` в `startSession`, где собирается `corePorts`
(строка ~137), добавить порты API:

```dart
    // ⚠️ Новые порты проверяются НАРАВНЕ с портами ядра. Иначе занятый порт
    // сервера дал бы отказ подъёма без единого внятного слова: «Bad state»
    // вместо имени программы, которая порт держит.
    final apiPorts = <int>[
      if (options.settings.apiEnabled) ...[
        for (final k in ApiPorts.withinRange(options.settings.apiExitServerKeys))
          ApiPorts.forServer(options.settings.apiExitServerKeys, k)!,
      ],
    ];
    final corePorts = [ports.socks, ports.http, ports.api, ...apiPorts];
```

Добавить импорт `../../core/net/api_ports.dart`.

⚠️ Управляющий порт (`ApiPorts.control`) сюда НЕ добавлять: он живёт независимо от подъёма
ядра, и его занятость не должна мешать подключению. Его отказ обрабатывает
`LocalApiServer.start()`, возвращая `false`.

- [ ] **Шаг 12: Проверить конфиг настоящим ядром**

Запустить: `cd app && flutter test test/multi_exit_emit_test.dart`
Ожидается: PASS. Если тест эмитит конфиги в `build/`, прогнать их через
`../engine/windows/bin/sing-box.exe check -c <файл>` — ожидается код 0 по каждому.

⚠️ Код 0 НЕ доказывает, что теги существуют: `sing-box check` висячие ссылки пропускает.
Целостность стережёт тест из шага 6, а не ядро.

- [ ] **Шаг 13: Коммит**

```bash
git add app/lib/core/singbox/singbox_config_builder.dart app/lib/engine/windows/windows_engine.dart app/lib/state/app_state.dart app/test/api_ports_test.dart
git commit -m "API: отдельный локальный порт на каждый выбранный сервер"
```

---

### Задача 4: Каркас управляющего сервера и аутентификация

**Файлы:**
- Создать: `app/lib/core/net/api_server.dart`
- Тест: `app/test/api_server_auth_test.dart` (создать)

**Интерфейсы:**
- Потребляет: `ApiPorts.control` (задача 3).
- Производит: класс `LocalApiServer` с конструктором
  `LocalApiServer({required String token, required ApiHandlers handlers, int port = ApiPorts.control})`,
  методами `Future<bool> start()` и `Future<void> stop()`, геттером `bool get running`.
  Абстракция `ApiHandlers` — задача 5 её реализует.

- [ ] **Шаг 1: Написать падающий тест**

Создать `app/test/api_server_auth_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_server.dart';

/// Аутентификация локального API.
///
/// ⚠️ Три правила ниже взяты из уже случившихся в этом проекте аварий, а не
/// придуманы: пустой секрет однажды означал «открыто всем», секрет выдавался
/// лишь на одном пути из нескольких, а порт без правильных заголовков читала
/// любая открытая вкладка браузера.
class _StubHandlers implements ApiHandlers {
  @override
  Future<Map<String, dynamic>> status() async => {'state': 'disconnected'};
  @override
  Future<List<Map<String, dynamic>>> servers() async => const [];
  @override
  Future<List<Map<String, dynamic>>> exits() async => const [];
  @override
  Future<Map<String, dynamic>> traffic() async => const {};
  @override
  Future<Map<String, dynamic>> subscription() async => const {};
  @override
  Future<ApiResult> connect({String? serverKey, String? name, bool auto = false}) async =>
      const ApiResult.ok();
  @override
  Future<ApiResult> disconnect() async => const ApiResult.ok();
  @override
  Future<ApiResult> ping() async => const ApiResult.ok();
}

void main() {
  late LocalApiServer server;

  Future<HttpClientResponse> req(String path,
      {String? token, String? origin, String method = 'GET'}) async {
    final c = HttpClient();
    final r = await c.openUrl(
        method, Uri.parse('http://127.0.0.1:${ApiPortsForTest.port}$path'));
    if (token != null) r.headers.set('Authorization', 'Bearer $token');
    if (origin != null) r.headers.set('Origin', origin);
    final resp = await r.close();
    return resp;
  }

  tearDown(() async => server.stop());

  test('пустой токен — сервер НЕ поднимается', () async {
    server = LocalApiServer(
        token: '', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    expect(await server.start(), isFalse);
    expect(server.running, isFalse);
  });

  test('без токена — 401', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    expect(await server.start(), isTrue);
    expect((await req('/v1/status')).statusCode, 401);
  });

  test('неверный токен — 401', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect((await req('/v1/status', token: 'bad')).statusCode, 401);
  });

  test('верный токен — 200 и JSON', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    final r = await req('/v1/status', token: 'good');
    expect(r.statusCode, 200);
    final body = jsonDecode(await utf8.decoder.bind(r).join());
    expect(body['state'], 'disconnected');
  });

  test('⚠️ запрос с Origin отвергается даже с верным токеном', () async {
    // Локальный HTTP-порт без этого атакуется не только процессом на машине, но
    // и любой открытой вкладкой браузера: sing-box с пустым секретом отдавал
    // метаданные соединений с CORS `*` — ровно тот же класс.
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    final r = await req('/v1/status',
        token: 'good', origin: 'https://evil.example');
    expect(r.statusCode, 403);
  });

  test('OPTIONS отвергается — preflight не пройдёт', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect((await req('/v1/status', method: 'OPTIONS')).statusCode, 403);
  });

  test('неизвестный путь — 404', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect((await req('/v1/nope', token: 'good')).statusCode, 404);
  });

  test('слушает ТОЛЬКО loopback', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect(server.address, InternetAddress.loopbackIPv4.address);
  });
}

/// Порт для тестов — не штатный, чтобы прогон не спорил с живым приложением.
class ApiPortsForTest {
  static const int port = 18770;
}
```

- [ ] **Шаг 2: Убедиться, что тест падает**

Запустить: `cd app && flutter test test/api_server_auth_test.dart`
Ожидается: «Target of URI doesn't exist: 'package:silentgate/core/net/api_server.dart'».

- [ ] **Шаг 3: Написать сервер**

Создать `app/lib/core/net/api_server.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform/app_log.dart';
import 'api_ports.dart';

/// Итог команды: успех либо причина отказа.
class ApiResult {
  const ApiResult.ok()
      : code = null,
        message = null;
  const ApiResult.fail(this.code, this.message);

  /// `null` — успех.
  final String? code;
  final String? message;

  bool get isOk => code == null;
}

/// Что умеет отдавать и делать API. Реализация живёт в состоянии приложения —
/// сервер про него ничего не знает и потому тестируется отдельно.
abstract interface class ApiHandlers {
  Future<Map<String, dynamic>> status();
  Future<List<Map<String, dynamic>>> servers();
  Future<List<Map<String, dynamic>>> exits();
  Future<Map<String, dynamic>> traffic();
  Future<Map<String, dynamic>> subscription();
  Future<ApiResult> connect({String? serverKey, String? name, bool auto = false});
  Future<ApiResult> disconnect();
  Future<ApiResult> ping();
}

/// Локальный HTTP-API для автоматизации.
///
/// ⚠️ ТРИ ПРАВИЛА, ВЗЯТЫЕ ИЗ УЖЕ СЛУЧИВШИХСЯ АВАРИЙ.
///
/// 1. Пустой токен означает «канал не поднимается», а не «поднимается без
///    проверки». Полумера опаснее отсутствия: порт, про который написано
///    «закрыт», а на деле пускающий кого угодно, хуже честно выключенного.
/// 2. Токен приходит готовым, одним значением, ДО старта слушателя. Секрет
///    Clash API однажды выдавался лишь на одном пути из нескольких — и порт
///    месяцами стоял открытым при обычных подключениях.
/// 3. Запрос с заголовком `Origin` отвергается. Локальный порт без этого
///    доступен не только процессу на машине, но и любой открытой вкладке
///    браузера.
class LocalApiServer {
  LocalApiServer({
    required this.token,
    required this.handlers,
    this.port = ApiPorts.control,
  });

  final String token;
  final ApiHandlers handlers;
  final int port;

  HttpServer? _server;

  bool get running => _server != null;
  String get address => _server?.address.address ?? '';

  /// Поднять слушатель. `false` — не поднялся (нет токена либо порт занят).
  Future<bool> start() async {
    await stop();
    if (token.isEmpty) {
      AppLog.w('API не поднят: токен не задан. Пустой токен означает '
          '«канал выключен», а не «открыт всем».');
      return false;
    }
    try {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = s;
      s.listen(_handle, onError: (Object e) => AppLog.w('API: сбой приёма: $e'));
      AppLog.i('API для автоматизации слушает 127.0.0.1:$port');
      return true;
    } catch (e) {
      AppLog.w('API не поднят на порту $port: $e');
      return false;
    }
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s == null) return;
    try {
      await s.close(force: true);
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    // ⚠️ Никаких Access-Control-Allow-*: заголовки, разрешающие браузеру читать
    // ответ, здесь были бы прямой выдачей состояния в веб.
    try {
      // Браузер всегда шлёт Origin для кросс-доменных запросов, а обычный
      // клиент (requests, curl) — нет. Это и есть граница.
      if (req.headers.value('origin') != null ||
          req.method == 'OPTIONS') {
        await _fail(res, HttpStatus.forbidden, 'browser_not_allowed',
            'Запросы из браузера не принимаются');
        return;
      }
      final auth = req.headers.value('authorization') ?? '';
      if (auth != 'Bearer $token') {
        await _fail(res, HttpStatus.unauthorized, 'unauthorized',
            'Нужен заголовок Authorization: Bearer <токен>');
        return;
      }
      await _route(req, res);
    } catch (e) {
      await _fail(res, HttpStatus.internalServerError, 'internal', '$e');
    }
  }

  Future<void> _route(HttpRequest req, HttpResponse res) async {
    final path = req.uri.path;
    if (req.method == 'GET') {
      switch (path) {
        case '/v1/status':
          return _ok(res, await handlers.status());
        case '/v1/servers':
          return _ok(res, {'servers': await handlers.servers()});
        case '/v1/exits':
          return _ok(res, {'exits': await handlers.exits()});
        case '/v1/traffic':
          return _ok(res, await handlers.traffic());
        case '/v1/subscription':
          return _ok(res, await handlers.subscription());
      }
    }
    if (req.method == 'POST') {
      final body = await _body(req);
      switch (path) {
        case '/v1/connect':
          return _result(
              res,
              await handlers.connect(
                serverKey: body['server'] as String?,
                name: body['name'] as String?,
                auto: body['auto'] == true,
              ));
        case '/v1/disconnect':
          return _result(res, await handlers.disconnect());
        case '/v1/ping':
          return _result(res, await handlers.ping());
      }
    }
    await _fail(res, HttpStatus.notFound, 'not_found', 'Нет такого пути');
  }

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    try {
      final text = await utf8.decoder.bind(req).join();
      if (text.trim().isEmpty) return const {};
      final v = jsonDecode(text);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _ok(HttpResponse res, Map<String, dynamic> body) async {
    res.statusCode = HttpStatus.ok;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _result(HttpResponse res, ApiResult r) async {
    if (r.isOk) return _ok(res, {'ok': true});
    return _fail(res, HttpStatus.conflict, r.code!, r.message ?? '');
  }

  Future<void> _fail(
      HttpResponse res, int status, String code, String message) async {
    res.statusCode = status;
    res.write(jsonEncode({
      'error': {'code': code, 'message': message}
    }));
    await res.close();
  }
}
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Запустить: `cd app && flutter test test/api_server_auth_test.dart`
Ожидается: PASS, 8 тестов.

- [ ] **Шаг 5: Коммит**

```bash
git add app/lib/core/net/api_server.dart app/test/api_server_auth_test.dart
git commit -m "API: слушатель с токеном, отказ браузеру и пустому токену"
```

---

### Задача 5: Обработчики — чтение и команды

**Файлы:**
- Создать: `app/lib/state/api_handlers.dart`
- Изменить: `app/lib/state/app_state.dart` (подъём и остановка сервера)
- Тест: `app/test/api_handlers_test.dart` (создать)

**Интерфейсы:**
- Потребляет: `ApiHandlers`, `ApiResult`, `LocalApiServer` (задача 4); `ApiPorts` (задача 3).
- Производит: `AppStateApiHandlers implements ApiHandlers` с конструктором
  `AppStateApiHandlers(AppState state, ProbeController probe, SettingsController settings)`.

- [ ] **Шаг 1: Написать падающий тест на чёрный список**

Создать `app/test/api_handlers_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/state/api_handlers.dart';

/// Что API НЕ отдаёт наружу.
///
/// ⚠️ ЭТО НЕ ПЕРЕСТРАХОВКА. Креды локального прокси лежат в глобальных
/// статиках процесса, а последний сегмент URL подписки у Remnawave — это
/// секрет. «Отдать состояние» без явного чёрного списка означало бы отдать
/// ключ от туннеля и от подписки одним GET-запросом.
void main() {
  test('чёрный список полей соблюдается', () {
    // Список ведётся ЗДЕСЬ и в apiSecretMarkers — двух копий быть не должно.
    expect(apiSecretMarkers, containsAll(<String>[
      'apiToken',
      'localProxyPassword',
      'localProxyUser',
      'subscriptionUrl',
      'rawJsonOverride',
      'rawPanelConfig',
    ]));
  });

  test('проверка ответа ловит запрещённое поле', () {
    final dirty = jsonEncode({'localProxyPassword': 'hunter2'});
    expect(() => assertNoSecrets(dirty), throwsA(isA<StateError>()));
  });

  test('чистый ответ проходит', () {
    final clean = jsonEncode({'state': 'connected', 'server': 'Германия'});
    expect(() => assertNoSecrets(clean), returnsNormally);
  });
}
```

- [ ] **Шаг 2: Убедиться, что тест падает**

Запустить: `cd app && flutter test test/api_handlers_test.dart`
Ожидается: «Target of URI doesn't exist».

- [ ] **Шаг 3: Написать чёрный список и обработчики**

Создать `app/lib/state/api_handlers.dart`:

```dart
import 'dart:convert';

import '../core/net/api_ports.dart';
import '../core/net/api_server.dart';
import '../core/util/country_flag.dart';
import 'app_state.dart';
import 'probe_controller.dart';
import 'settings_controller.dart';

/// Поля, которых в ответах API быть НЕ ДОЛЖНО.
///
/// ⚠️ Явный список, а не «по умолчанию не отдаём». Креды локального прокси
/// лежат в глобальных статиках процесса, а последний сегмент URL подписки у
/// Remnawave — это секрет: «отдать состояние» без списка означало бы отдать
/// ключ от туннеля и от подписки одним GET-запросом.
const apiSecretMarkers = <String>[
  'apiToken',
  'localProxyPassword',
  'localProxyUser',
  'subscriptionUrl',
  'rawJsonOverride',
  'rawPanelConfig',
];

/// Бросает [StateError], если в сериализованном ответе встретилось запрещённое.
void assertNoSecrets(String json) {
  for (final m in apiSecretMarkers) {
    if (json.contains(m)) {
      throw StateError('В ответе API запрещённое поле: $m');
    }
  }
}

/// Обработчики API поверх состояния приложения.
class AppStateApiHandlers implements ApiHandlers {
  AppStateApiHandlers(this.state, this.probe, this.settings);

  final AppState state;
  final ProbeController probe;
  final SettingsController settings;

  @override
  Future<Map<String, dynamic>> status() async => {
        'state': state.status.state.name,
        'server': state.selectedServer?.displayName,
        'captureMode': settings.settings.captureMode.name,
        'connectedSeconds': state.connectedFor?.inSeconds,
      };

  @override
  Future<List<Map<String, dynamic>>> servers() async => [
        for (final s in state.servers)
          {
            'key': s.key,
            'name': s.displayName,
            'country': FlagUtil.isoFromName(s.remark),
            'protocol': s.protocol,
            'pingMs': probe.resultFor(s).latencyMs,
            'working': probe.resultFor(s).working,
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> exits() async {
    final keys = settings.settings.apiExitServerKeys;
    return [
      for (final s in state.servers)
        if (keys.contains(s.key))
          {
            'serverKey': s.key,
            'name': s.displayName,
            'country': FlagUtil.isoFromName(s.remark),
            'port': ApiPorts.forServer(keys, s.key),
          },
      {'serverKey': null, 'name': 'Прямо', 'port': ApiPorts.direct},
    ];
  }

  @override
  Future<Map<String, dynamic>> traffic() async => {
        'uplinkBytes': state.sessionUplinkBytes,
        'downlinkBytes': state.sessionDownlinkBytes,
      };

  @override
  Future<Map<String, dynamic>> subscription() async => {
        'title': state.info.title,
        'usedBytes': state.info.usedBytes,
        'totalBytes': state.info.totalBytes,
        'unlimited': state.info.unlimitedTraffic,
        'expiresAt': state.info.expiresAt?.toIso8601String(),
      };

  @override
  Future<ApiResult> connect(
      {String? serverKey, String? name, bool auto = false}) async {
    if (auto) {
      await state.connectAuto(settings.settings);
      return const ApiResult.ok();
    }
    // ⚠️ КЛЮЧ, А НЕ ИМЯ. Ключ (share-ссылка) стабилен и переживает
    // переименование на панели; имя панель меняет когда угодно, и скрипт,
    // написанный по имени, тихо сломался бы.
    if ((serverKey ?? '').isNotEmpty) {
      final i = state.servers.indexWhere((s) => s.key == serverKey);
      if (i < 0) {
        return const ApiResult.fail('server_not_found', 'Сервер не найден');
      }
      state.selectServer(i);
      await state.toggleConnection(settings.settings);
      return const ApiResult.ok();
    }
    if ((name ?? '').isNotEmpty) {
      final matches = [
        for (var i = 0; i < state.servers.length; i++)
          if (state.servers[i].displayName == name) i,
      ];
      if (matches.isEmpty) {
        return const ApiResult.fail('server_not_found', 'Сервер не найден');
      }
      // ⚠️ Молча выбрать первый значило бы подключить не туда.
      if (matches.length > 1) {
        return const ApiResult.fail(
            'ambiguous_name', 'Под это имя подходит несколько серверов');
      }
      state.selectServer(matches.first);
      await state.toggleConnection(settings.settings);
      return const ApiResult.ok();
    }
    return const ApiResult.fail(
        'server_required', 'Укажите server, name или auto');
  }

  @override
  Future<ApiResult> disconnect() async {
    await state.disconnect();
    return const ApiResult.ok();
  }

  @override
  Future<ApiResult> ping() async {
    await probe.pingAll(state.servers, settings.settings);
    return const ApiResult.ok();
  }
}
```

⚠️ **Перед написанием сверить три имени с кодом** — они взяты из существующего состояния, и
если хоть одно называется иначе, править надо вызов, а не заводить новое:
`AppState.selectServer(int)` (выбор сервера по индексу), `AppState.disconnect()`,
`AppState.sessionDownlinkBytes`. Найти их: `grep -n "selectServer\|Future<void> disconnect\|sessionDownlinkBytes" lib/state/app_state.dart`.

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Запустить: `cd app && flutter test test/api_handlers_test.dart`
Ожидается: PASS, 3 теста.

- [ ] **Шаг 5: Дописать тест, который перебирает ВСЕ эндпоинты**

Дописать в `app/test/api_handlers_test.dart`:

```dart
  test('⚠️ ни один эндпоинт не отдаёт секретов', () async {
    // Перебор по списку, а не выборочно: новый эндпоинт, забытый в проверке,
    // и есть самый вероятный способ отдать секрет наружу.
    final h = _FakeHandlers();
    final bodies = <String>[
      jsonEncode(await h.status()),
      jsonEncode(await h.servers()),
      jsonEncode(await h.exits()),
      jsonEncode(await h.traffic()),
      jsonEncode(await h.subscription()),
    ];
    for (final b in bodies) {
      expect(() => assertNoSecrets(b), returnsNormally);
    }
  });
```

Добавить в тот же файл заглушку `_FakeHandlers`, повторяющую форму ответов
`AppStateApiHandlers` без зависимости от состояния (поля-константы).

- [ ] **Шаг 6: Поднять сервер из состояния приложения**

В `app/lib/state/app_state.dart` добавить поле и методы:

```dart
  LocalApiServer? _api;

  /// Поднять или погасить API по настройкам.
  ///
  /// ⚠️ ТОЛЬКО WINDOWS. На Android локальные порты видит любое установленное
  /// приложение, и отдельная история по безопасности там ещё не проработана.
  /// Правило проекта: где нет изоляции, канал не поднимается вовсе.
  Future<void> applyApiSettings(AppSettings s, ProbeController probe,
      SettingsController settings) async {
    await _api?.stop();
    _api = null;
    if (!Platform.isWindows || !s.apiEnabled) return;
    final srv = LocalApiServer(
      token: s.apiToken,
      handlers: AppStateApiHandlers(this, probe, settings),
    );
    if (await srv.start()) _api = srv;
    notifyListeners();
  }
```

Вызвать `applyApiSettings` в `init()` после загрузки настроек и при каждой правке настроек
(там же, где вызывается `publishNotificationLayout`).

- [ ] **Шаг 7: Прогнать весь набор**

Запустить: `cd app && flutter analyze && flutter test`
Ожидается: анализатор чист, все тесты зелёные.

- [ ] **Шаг 8: Коммит**

```bash
git add app/lib/state/api_handlers.dart app/lib/state/app_state.dart app/test/api_handlers_test.dart
git commit -m "API: обработчики чтения и команд, чёрный список секретов"
```

---

### Задача 6: Закрытие порта 47654

**Файлы:**
- Изменить: `app/lib/core/platform/single_instance.dart`
- Изменить: `app/lib/main.dart` (передача токена в `listen`)
- Тест: `app/test/single_instance_auth_test.dart` (создать)

**Интерфейсы:**
- Потребляет: `AppSettings.apiToken` (задача 1).
- Производит: `SingleInstance.listen(ServerSocket server, void Function(String url) onUrl, {required String token})`
  и статический `SingleInstance.splitMessage(String raw)` → `({String? token, String url})`.

- [ ] **Шаг 1: Написать падающий тест**

Создать `app/test/single_instance_auth_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/single_instance.dart';

/// Порт single-instance принимал произвольную строку без аутентификации.
///
/// ⚠️ Это тот самый «путь БЕЗ подтверждения пользователя», который владелец
/// сам записал условием пересмотра принятого риска url-схем: через браузер
/// переход подтверждает человек, а через сокет — никто. Любой локальный
/// процесс мог переключить сервер или подменить подписку.
void main() {
  group('Разбор сообщения', () {
    test('строка с токеном разбирается на две части', () {
      final m = SingleInstance.splitMessage('tok123\nsilentgate://connect');
      expect(m.token, 'tok123');
      expect(m.url, 'silentgate://connect');
    });

    test('строка без перевода строки — это просто ссылка', () {
      final m = SingleInstance.splitMessage('silentgate://import?url=https://x');
      expect(m.token, isNull);
      expect(m.url, 'silentgate://import?url=https://x');
    });
  });

  group('Что требует токена', () {
    test('команды управления требуют', () {
      for (final a in ['connect', 'disconnect', 'toggle', 'update']) {
        expect(SingleInstance.needsToken('silentgate://$a'), isTrue,
            reason: '$a обязано требовать токен');
      }
    });

    test('⚠️ импорт НЕ требует — его инициировал человек', () {
      // Второй экземпляр приложения передаёт ссылку, по которой пользователь
      // щёлкнул в браузере или проводнике. Сломать этот путь нельзя.
      expect(SingleInstance.needsToken('silentgate://import?url=https://x'),
          isFalse);
      expect(SingleInstance.needsToken('https://panel.example/sub/abc'),
          isFalse);
    });
  });
}
```

- [ ] **Шаг 2: Убедиться, что тест падает**

Запустить: `cd app && flutter test test/single_instance_auth_test.dart`
Ожидается: «The method 'splitMessage' isn't defined».

- [ ] **Шаг 3: Реализовать**

В `app/lib/core/platform/single_instance.dart` добавить:

```dart
  /// Разобрать сообщение сокета: `<токен>\n<ссылка>` либо просто `<ссылка>`.
  static ({String? token, String url}) splitMessage(String raw) {
    final i = raw.indexOf('\n');
    if (i < 0) return (token: null, url: raw.trim());
    return (token: raw.substring(0, i).trim(), url: raw.substring(i + 1).trim());
  }

  /// Требует ли эта ссылка токена.
  ///
  /// ⚠️ Управляющие команды — да, импорт — НЕТ. Импортную ссылку передаёт
  /// второй экземпляр приложения, запущенный человеком двойным кликом; требовать
  /// у него токен значило бы сломать штатный путь ради защиты от самого
  /// пользователя.
  static bool needsToken(String url) {
    final u = url.trim().toLowerCase();
    if (!u.startsWith('silentgate://')) return false;
    final rest = u.substring('silentgate://'.length);
    for (final a in ['connect', 'disconnect', 'toggle', 'update']) {
      if (rest == a || rest.startsWith('$a?') || rest.startsWith('$a/')) {
        return true;
      }
    }
    return false;
  }
```

Заменить `listen`:

```dart
  /// Первичный экземпляр: принимать входящие URL.
  ///
  /// [token] — токен API. Управляющие команды без него отбрасываются.
  static void listen(ServerSocket server, void Function(String url) onUrl,
      {required String Function() token}) {
    server.listen((socket) {
      final buf = <int>[];
      socket.listen(
        buf.addAll,
        onDone: () {
          final raw = utf8.decode(buf, allowMalformed: true).trim();
          socket.destroy();
          if (raw.isEmpty) return;
          final m = splitMessage(raw);
          if (needsToken(m.url)) {
            final want = token();
            if (want.isEmpty || m.token != want) {
              // ⚠️ Молчать нельзя: «команда отвергнута» и «команда выполнена»
              // снаружи неотличимы, и разбор жалобы начинался бы с нуля.
              AppLog.w('Команда через локальный сокет отвергнута: '
                  'неверный или отсутствующий токен');
              return;
            }
          }
          onUrl(m.url);
        },
        onError: (_) => socket.destroy(),
      );
    });
  }
```

Добавить импорт `app_log.dart`.

В `app/lib/main.dart` заменить вызов (строка ~68):

```dart
    // Токен читается КАЖДЫЙ РАЗ, а не захватывается один: пользователь может
    // обновить его в настройках при живом приложении.
    SingleInstance.listen(server, IncomingLinks.add,
        token: () => _apiTokenSnapshot);
```

и завести `_apiTokenSnapshot`, обновляемый при загрузке и правке настроек.

⚠️ `SingleInstance.forward` не менять: второй экземпляр передаёт импортную ссылку, ему токен
не нужен.

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Запустить: `cd app && flutter test test/single_instance_auth_test.dart`
Ожидается: PASS, 4 теста.

- [ ] **Шаг 5: Коммит**

```bash
git add app/lib/core/platform/single_instance.dart app/lib/main.dart app/test/single_instance_auth_test.dart
git commit -m "Закрыт порт 47654: управляющие команды требуют токена, импорт — нет"
```

---

### Задача 7: Интерфейс настроек и локализация

**Файлы:**
- Изменить: `app/lib/ui/settings_screen.dart` (новый раздел)
- Изменить: `app/lib/l10n/app_ru.arb` и остальные девять `app_*.arb`
- Тест: `app/test/l10n_test.dart` (уже есть, должен остаться зелёным)

**Интерфейсы:**
- Потребляет: `AppSettings.apiEnabled|apiToken|apiExitServerKeys` (задача 1), `ApiPorts` (задача 3).

- [ ] **Шаг 1: Добавить ключи в русский ARB**

В `app/lib/l10n/app_ru.arb` добавить:

```json
  "apiSectionTitle": "API для автоматизации",
  "apiEnableTitle": "Включить локальный API",
  "apiEnableSub": "HTTP на 127.0.0.1:{port} — управление клиентом из скриптов",
  "apiTokenTitle": "Токен",
  "apiTokenUnset": "Не задан — API не поднимается",
  "apiTokenRegenerate": "Обновить токен",
  "apiTokenWarning": "Токен хранится в файле настроек открытым текстом и попадает в резервные копии. Тот, у кого он есть, может переключать сервер и читать состояние подписки.",
  "apiExitsTitle": "Серверы с отдельным портом",
  "apiExitsSub": "Каждому выдаётся свой локальный порт — запрос в него идёт через этот сервер",
  "apiCopyPythonExample": "Скопировать пример для Python",
  "apiPortsHint": "Управление — порт {control}. «Прямо» — порт {direct}. Серверы — с {first}."
```

Плейсхолдеры объявить явно:

```json
  "@apiEnableSub": {"placeholders": {"port": {"type": "int"}}},
  "@apiPortsHint": {"placeholders": {"control": {"type": "int"}, "direct": {"type": "int"}, "first": {"type": "int"}}}
```

⚠️ Порядок плейсхолдеров объявлять обязательно: без `@ключ.placeholders` кодогенератор
сортирует параметры метода ПО АЛФАВИТУ, а вызовы пишутся в порядке появления в строке — значения
молча меняются местами.

- [ ] **Шаг 2: Перевести на девять языков**

Перевести те же ключи в `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_de.arb`, `app_pt.arb`,
`app_tr.arb`, `app_ar.arb`, `app_fa.arb`, `app_zh.arb`. Плейсхолдеры сохранять дословно;
переставлять их по правилам языка можно — они именованные.

- [ ] **Шаг 3: Сгенерировать и проверить паритет**

Запустить: `cd app && flutter gen-l10n && flutter test test/l10n_test.dart`
Ожидается: PASS. Тест динамически сверяет все `app_*.arb` с русским и упадёт при неполном переводе.

- [ ] **Шаг 4: Добавить раздел в настройки**

В `app/lib/ui/settings_screen.dart` добавить `_ApiSection` по образцу соседних разделов:
тумблер `apiEnabled`; строка токена с кнопками «Скопировать» и «Обновить токен» (генерировать
через `VpnEngineBase.randomSecret()`); подсказка `apiTokenWarning` в `InfoTooltip`; список
серверов с чекбоксами, пишущий в `apiExitServerKeys`; строка `apiPortsHint`; кнопка
«Скопировать пример для Python», кладущая в буфер готовый фрагмент с подставленными портом и
токеном.

⚠️ Раздел показывать только на Windows (`if (Platform.isWindows)`) — на Android API не
поднимается, и видимый тумблер, который ничего не делает, был бы обманом.

- [ ] **Шаг 5: Проверить**

Запустить: `cd app && flutter analyze && flutter test`
Ожидается: анализатор без ошибок и предупреждений; все тесты зелёные.

- [ ] **Шаг 6: Коммит**

```bash
git add app/lib/ui/settings_screen.dart app/lib/l10n/
git commit -m "API: раздел настроек, токен и выбор серверов с отдельным портом"
```

---

### Задача 8: Документация и пример для Python

**Файлы:**
- Создать: `docs/API.md`
- Создать: `tools/silentgate.py`
- Изменить: `CHANGELOG.md`, `README.md`, `CLAUDE.md`, `app/pubspec.yaml`,
  `app/lib/core/app_info.dart`

- [ ] **Шаг 1: Написать `docs/API.md`**

Разделы: раскладка портов; включение и токен; все восемь эндпоинтов с примерами `curl` и
Python; коды ошибок; раздел «Безопасность» — что даёт токен держателю, почему его не стоит
класть в общий репозиторий, почему запросы из браузера отвергаются.

- [ ] **Шаг 2: Написать `tools/silentgate.py`**

```python
"""Минимальная обёртка над локальным API SilentGate.

Требует только `requests`. Токен и порт берутся из настроек приложения:
Настройки -> API для автоматизации.
"""
import requests

class SilentGate:
    def __init__(self, token: str, host: str = "127.0.0.1", port: int = 10870):
        self._base = f"http://{host}:{port}/v1"
        self._headers = {"Authorization": f"Bearer {token}"}
        self._token = token
        self._host = host

    def _get(self, path: str):
        r = requests.get(self._base + path, headers=self._headers, timeout=5)
        r.raise_for_status()
        return r.json()

    def _post(self, path: str, body: dict | None = None):
        r = requests.post(self._base + path, headers=self._headers,
                          json=body or {}, timeout=30)
        r.raise_for_status()
        return r.json()

    def status(self):        return self._get("/status")
    def servers(self):       return self._get("/servers")["servers"]
    def exits(self):         return self._get("/exits")["exits"]
    def traffic(self):       return self._get("/traffic")
    def subscription(self):  return self._get("/subscription")

    def connect(self, server_key: str | None = None, auto: bool = False):
        return self._post("/connect", {"server": server_key, "auto": auto})

    def disconnect(self):    return self._post("/disconnect")

    def proxies_for(self, server_key: str | None) -> dict:
        """Прокси-словарь для requests. None — порт «Прямо» (мимо VPN)."""
        for e in self.exits():
            if e["serverKey"] == server_key:
                url = f"http://sg:{self._token}@{self._host}:{e['port']}"
                return {"http": url, "https": url}
        raise KeyError(f"нет порта для сервера {server_key!r}")


if __name__ == "__main__":
    sg = SilentGate(token="ВСТАВЬТЕ_ТОКЕН")
    print(sg.status())
    for e in sg.exits():
        print(e["name"], "->", e["port"])
```

- [ ] **Шаг 3: Обновить документы проекта**

Версия — **MINOR** (`1.4.0`): появилась новая подсистема в `core/` и новая возможность.
Бампить синхронно: `app/pubspec.yaml`, `app/lib/core/app_info.dart`, раздел в `CHANGELOG.md`,
статус в `README.md`, текущий этап в `CLAUDE.md`.

⚠️ В `CLAUDE.md` отдельно записать поправку: именованных выходов (`VpnExit`,
`AppSettings.exits`) в коде НЕТ, они мигрированы; правило указывает ключ сервера напрямую.
Сейчас файл описывает прежнюю редакцию и вводит в заблуждение.

- [ ] **Шаг 4: Финальная проверка**

Запустить: `cd app && flutter analyze && flutter test`
Ожидается: анализатор без ошибок и предупреждений; все тесты зелёные.

- [ ] **Шаг 5: Коммит**

```bash
git add docs/API.md tools/silentgate.py CHANGELOG.md README.md CLAUDE.md app/pubspec.yaml app/lib/core/app_info.dart
git commit -m "API: документация, пример для Python, версия 1.4.0"
```

---

## Живая проверка (за владельцем)

VPN на хосте не включаю. В Hyper-V VM `SG-Test`, на реальной подписке:

1. Включить API, задать токен, выдать порты трём серверам разных стран.
2. Из Python три запроса к `ipinfo.io` в три разных порта **одновременно** — три разных
   выходных IP, совпадающих со странами серверов.
3. Запрос в порт «Прямо» — реальный IP провайдера.
4. `GET /v1/status` из браузера — ожидается 403 (проверка отказа браузеру).
5. `POST /v1/connect {"auto": true}` — подключается режим «Авто», недостижимый через url-схемы.
6. Обновить токен при живом API — старый клиент получает 401, новый работает.
7. Режим «Только прокси»: интернет машины идёт напрямую (проверить `2ip.ru` в браузере),
   а Python через порт — через VPN.
8. Послать `silentgate://connect` в сокет 47654 без токена — команда обязана быть отвергнута,
   в журнале строка об этом.
