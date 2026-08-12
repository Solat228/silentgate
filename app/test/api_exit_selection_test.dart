import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/state/app_state.dart';

/// Кому достаётся отдельный outbound (`exit-…`) — правилам и портам API.
///
/// ⚠️ НАХОДКА ФИНАЛЬНОГО РЕВЬЮ (5). Активный сервер удалялся из списка выходов
/// ЦЕЛИКОМ — и для правил, и для портов API. Для правил это верно: «сайт через
/// сервер X», где X и есть текущий сервер, и так идёт тем же узлом через тег
/// `proxy`. Для порта API — неверно: инбаунда не создавалось (построитель
/// проверяет живые теги), а `GET /v1/exits` порт публиковал, и скрипт получал
/// отказ соединения на адрес, который ему только что назвали. Стоило
/// переключить основной сервер — «сломанный» порт переезжал на другой.
void main() {
  const germany = 'vless://uuid@de.example:443#Германия';
  const usa = 'vless://uuid@us.example:443#США';

  AppSettings base(CaptureMode mode) => const AppSettings().copyWith(
        captureMode: mode,
        apiEnabled: true,
        apiToken: 'secret',
      );

  group('Порты API', () {
    test('⚠️ активный сервер СВОЙ порт получает', () {
      final keys = AppState.exitServerKeysFor(
        settings: base(CaptureMode.tun)
            .copyWith(apiExitServerKeys: const [germany, usa]),
        selectedKey: germany,
      );
      expect(keys, containsAll(const [germany, usa]),
          reason: 'сервер, выбранный на главном, обязан получить свой outbound '
              '— иначе его порт из /v1/exits никуда не ведёт');
    });

    test('переключение основного сервера ничего не ломает', () {
      // Раньше «сломанный» порт просто переезжал на другой сервер.
      for (final selected in const [germany, usa, null]) {
        final keys = AppState.exitServerKeysFor(
          settings: base(CaptureMode.tun)
              .copyWith(apiExitServerKeys: const [germany, usa]),
          selectedKey: selected,
        );
        expect(keys, containsAll(const [germany, usa]),
            reason: 'основной = $selected');
      }
    });

    test('гейт: выключенный API, пустой токен и системный прокси — ничего', () {
      for (final s in [
        base(CaptureMode.tun)
            .copyWith(apiEnabled: false, apiExitServerKeys: const [germany]),
        base(CaptureMode.tun)
            .copyWith(apiToken: '', apiExitServerKeys: const [germany]),
        // ⚠️ Системный прокси — умолчание на Windows: инбаундов там нет ни
        // одного, значит и outbound-ы под них были бы мусором в конфиге.
        base(CaptureMode.systemProxy)
            .copyWith(apiExitServerKeys: const [germany]),
      ]) {
        expect(
            AppState.exitServerKeysFor(settings: s, selectedKey: null), isEmpty,
            reason: 'режим ${s.captureMode}, тумблер ${s.apiEnabled}, '
                'токен "${s.apiToken}"');
      }
    });

    test('пустые ключи в настройке игнорируются', () {
      final keys = AppState.exitServerKeysFor(
        settings:
            base(CaptureMode.tun).copyWith(apiExitServerKeys: const ['', usa]),
        selectedKey: null,
      );
      expect(keys, const {usa});
    });
  });

  group('Правила раздельного туннелирования — прежнее поведение', () {
    SplitTunnelConfig withSite(String? serverKey) => SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          sites: [
            SiteRule('example.com',
                action: AppAction.tunnel, serverKey: serverKey),
          ],
        );

    test('⚠️ активный сервер из ПРАВИЛ по-прежнему исключается', () {
      final keys = AppState.exitServerKeysFor(
        settings: base(CaptureMode.tun).copyWith(splitTunnel: withSite(germany)),
        selectedKey: germany,
      );
      expect(keys, isEmpty,
          reason: 'второй outbound к тому же узлу — второе соединение без '
              'единой выгоды: правило и так пойдёт тегом proxy');
    });

    test('другой сервер в правиле выход получает', () {
      final keys = AppState.exitServerKeysFor(
        settings: base(CaptureMode.tun).copyWith(splitTunnel: withSite(usa)),
        selectedKey: germany,
      );
      expect(keys, const {usa});
    });

    test('правило приложения учитывается только включённое', () {
      SplitTunnelConfig withApp(bool enabled) => SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            apps: [
              AppRule(r'C:\chrome.exe',
                  action: AppAction.tunnel,
                  enabled: enabled,
                  serverKey: usa),
            ],
          );
      expect(
          AppState.exitServerKeysFor(
              settings:
                  base(CaptureMode.tun).copyWith(splitTunnel: withApp(true)),
              selectedKey: germany),
          const {usa});
      expect(
          AppState.exitServerKeysFor(
              settings:
                  base(CaptureMode.tun).copyWith(splitTunnel: withApp(false)),
              selectedKey: germany),
          isEmpty);
    });

    test('⚠️ активный сервер, ОТМЕЧЕННЫЙ под порт, всё равно попадает', () {
      // Смешанный случай: правило на него исключается, а порт — нет. Это два
      // разных источника с разными правилами, и объединение обязано быть
      // объединением, а не пересечением.
      final keys = AppState.exitServerKeysFor(
        settings: base(CaptureMode.tun).copyWith(
            splitTunnel: withSite(germany),
            apiExitServerKeys: const [germany]),
        selectedKey: germany,
      );
      expect(keys, const {germany});
    });
  });

  /// ⚠️ РЕГРЕССИЯ ПРЕДЫДУЩЕЙ ВОЛНЫ. Состав ключей выше — верный, а вот эффект
  /// был неверным: как только активный сервер начал получать outbound ради
  /// порта, его тег ожил, и правило «сайт через него» ушло ВТОРЫМ соединением
  /// к тому же узлу (панель показывает удвоенный «онлайн», а канал собран
  /// sing-box из разобранных полей, а не из панельного outbound'а Xray).
  /// Прежний тест этого не ловил: он проверял только СОСТАВ.
  group('⚠️ Два источника разводятся, а не сливаются', () {
    SplitTunnelConfig withSite(String serverKey) => SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          sites: [
            SiteRule('example.com',
                action: AppAction.tunnel, serverKey: serverKey),
          ],
        );

    test('КОМБИНАЦИЯ: сервер активный + отмечен под порт + указан в правиле',
        () {
      final settings = base(CaptureMode.tun).copyWith(
          splitTunnel: withSite(germany), apiExitServerKeys: const [germany]);

      // Outbound ему нужен — иначе порт из /v1/exits никуда не ведёт.
      expect(
          AppState.exitServerKeysFor(
              settings: settings, selectedKey: germany),
          const {germany});
      // Но правилам он не адресат: они обязаны идти тегом `proxy`.
      expect(
          AppState.ruleExitServerKeysFor(
              settings: settings, selectedKey: germany),
          isEmpty);
      expect(
          AppState.apiOnlyExitKeysFor(
              settings: settings, selectedKey: germany),
          const {germany},
          reason: 'ключ попал в выходы ТОЛЬКО ради порта — построитель обязан '
              'спрятать его тег от правил');
    });

    test('тот же сервер, но НЕ активный — правилам он адресат', () {
      // Контроль: без этого предыдущая проверка прошла бы и на коде,
      // прячущем от правил вообще все серверы с портом.
      final settings = base(CaptureMode.tun).copyWith(
          splitTunnel: withSite(usa), apiExitServerKeys: const [usa]);
      expect(
          AppState.ruleExitServerKeysFor(settings: settings, selectedKey: germany),
          const {usa});
      expect(
          AppState.apiOnlyExitKeysFor(settings: settings, selectedKey: germany),
          isEmpty,
          reason: 'сервер, на который ссылается правило, живёт не только ради '
              'порта — прятать его тег от правил нельзя');
    });

    test('порт без единого правила — «только ради порта» по определению', () {
      final settings =
          base(CaptureMode.tun).copyWith(apiExitServerKeys: const [germany]);
      expect(
          AppState.apiOnlyExitKeysFor(settings: settings, selectedKey: null),
          const {germany});
    });

    test('закрытый гейт портов не оставляет «api-only» ключей', () {
      // Системный прокси: инбаундов нет вовсе, значит и прятать нечего.
      final settings = base(CaptureMode.systemProxy).copyWith(
          splitTunnel: withSite(usa), apiExitServerKeys: const [germany, usa]);
      expect(AppState.apiOnlyExitKeysFor(settings: settings, selectedKey: null),
          isEmpty);
      expect(
          AppState.exitServerKeysFor(settings: settings, selectedKey: null),
          const {usa},
          reason: 'правила продолжают работать и там, где портов не бывает');
    });
  });
}
