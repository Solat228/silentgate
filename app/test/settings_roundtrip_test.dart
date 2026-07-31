import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

/// Класс багов «поле пишется в файл, но не читается обратно».
///
/// Компилятор его не видит: `toJson` и `fromJson` — независимые списки, и
/// забытая строка в одном из них проявляется только тем, что настройка молча
/// возвращается к умолчанию при следующем запуске, хотя в файле лежит выбор
/// пользователя. Так уже потерялась настройка DNS `tunnelDnsForAll`.
///
/// Тест не перечисляет поля руками (такой список устаревает ровно так же) —
/// он берёт ВСЕ ключи из `toJson` и проверяет каждый.
void main() {
  test('каждое булево поле переживает сохранение и загрузку', () {
    const base = AppSettings();
    final json = base.toJson();

    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! bool) continue;

      final flipped = Map<String, dynamic>.of(json)..[entry.key] = !v;
      final loaded = AppSettings.fromJson(flipped).toJson();

      expect(loaded[entry.key], !v,
          reason: 'настройка «${entry.key}» сохраняется, но не читается обратно:'
              ' fromJson её пропускает, и выбор пользователя теряется');
    }
  });

  test('каждое числовое поле переживает сохранение и загрузку', () {
    const base = AppSettings();
    final json = base.toJson();

    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! int) continue;
      // Значения-перечисления хранятся строкой, а не числом, так что здесь
      // только настоящие числа (порты, размеры, интервалы).
      final changed = Map<String, dynamic>.of(json)..[entry.key] = v + 1;
      final loaded = AppSettings.fromJson(changed).toJson();

      expect(loaded[entry.key], v + 1,
          reason: 'настройка «${entry.key}» сохраняется, но не читается обратно');
    }
  });

  // ⚠️ ВЛОЖЕННЫЕ объекты страж выше НЕ покрывал: он идёт по полям `AppSettings`,
  // а `splitTunnel` там — целая Map, и её содержимое пропускалось. Ровно через
  // эту дыру проскочило `overrideSites` у AppRule: писалось в файл и не читалось
  // обратно, то есть галочка сбрасывалась при каждом запуске. Правила — такие же
  // настройки пользователя, и терять их нельзя.
  test('каждое булево поле ПРАВИЛА ПРИЛОЖЕНИЯ переживает сохранение', () {
    const base = AppRule(r'C:pp.exe');
    final json = base.toJson();
    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! bool) continue;
      final flipped = Map<String, dynamic>.of(json)..[entry.key] = !v;
      final loaded = AppRule.fromJson(flipped).toJson();
      expect(loaded[entry.key], !v,
          reason: 'поле правила «${entry.key}» сохраняется, но не читается: '
              'выбор пользователя теряется при перезапуске');
    }
  });

  test('каждое булево поле ПРАВИЛА САЙТА переживает сохранение', () {
    const base = SiteRule('example.com');
    final json = base.toJson();
    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! bool) continue;
      final flipped = Map<String, dynamic>.of(json)..[entry.key] = !v;
      final loaded = SiteRule.fromJson(flipped).toJson();
      expect(loaded[entry.key], !v,
          reason: 'поле правила «${entry.key}» сохраняется, но не читается');
    }
  });

  test('правила переживают сохранение ВНУТРИ настроек целиком', () {
    // Путь, которым настройки реально ходят на диск: AppSettings → splitTunnel →
    // списки правил. Проверяем сквозь все слои, а не по отдельности.
    const settings = AppSettings(
      splitTunnel: SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [
          AppRule(r'C:.exe',
              byName: true,
              action: AppAction.tunnel,
              allowRealIp: true,
              overrideSites: true),
        ],
        sites: [SiteRule('x.com', port: 8443, action: AppAction.direct, allowRealIp: true)],
      ),
    );
    final back = AppSettings.fromJson(settings.toJson());
    final app = back.splitTunnel.apps.single;
    expect(app.byName, isTrue);
    expect(app.action, AppAction.tunnel);
    expect(app.allowRealIp, isTrue);
    expect(app.overrideSites, isTrue);
    final site = back.splitTunnel.sites.single;
    expect(site.port, 8443);
    expect(site.allowRealIp, isTrue);
    expect(site.action, AppAction.direct);
  });
}
