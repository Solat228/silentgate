import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/platform/app_cleanup.dart';
import 'core/platform/app_env.dart';
import 'core/platform/app_paths.dart';
import 'core/platform/platform_services.dart';
import 'core/platform/core_cleanup.dart';
import 'core/platform/incoming_links.dart';
import 'core/platform/single_instance.dart';
import 'core/platform/tray_window.dart';
import 'core/platform/url_scheme_windows.dart';
import 'core/url_scheme.dart';
import 'engine/android/platform_services_android.dart';
import 'engine/windows/platform_services_windows.dart';
import 'engine/windows/tun/tun_helper.dart';
import 'engine/windows/xray_paths.dart';
import 'state/app_state.dart';
import 'state/auto_config_controller.dart';
import 'state/probe_controller.dart';
import 'state/provider_wiring.dart';
import 'state/service_check_controller.dart';
import 'state/settings_controller.dart';

/// Снимок токена API для аутентификации управляющих команд через локальный
/// сокет (`SingleInstance`, порт 47654).
///
/// ⚠️ Не читать `AppSettings.apiToken` с диска на каждое сообщение сокета:
/// `SingleInstance.listen` вызывает колбэк `token()` в обработчике входящего
/// соединения, и файловый ввод-вывод там задержал бы как раз ту ссылку,
/// которую нетерпеливо ждёт пользователь (клик по silentgate://import из
/// браузера). Снимок живёт в памяти и обновляется слушателем на
/// `SettingsController` (см. его создание в `main()`) — при первой загрузке
/// настроек и при каждой их правке. До первой загрузки снимок пуст, и это
/// безопасно: пустой токен отклоняет ВСЕ управляющие команды (см.
/// `SingleInstance.listen`), а не пропускает их без проверки.
String _apiTokenSnapshot = '';

Future<void> main(List<String> args) async {
  // Служебные режимы запуска — Windows-специфика: там exe умеет работать
  // элевейтнутым хелпером и режимом очистки при удалении. На Android ни
  // аргументов запуска, ни этих ролей нет (туннель поднимает VpnService,
  // данные при удалении стирает система), поэтому весь блок под гейтом.
  if (Platform.isWindows && await _runWindowsCliMode(args)) return;

  WidgetsFlutterBinding.ensureInitialized();

  // Корень данных — до любых хранилищ и логов. На Windows путь вычислился бы и
  // синхронно, но на Android он известен только асинхронно, поэтому единая
  // точка инициализации для обеих платформ.
  await AppPaths.init();

  // Платформенные сервисы интерфейса (иконки приложений, каталог приложений,
  // версии ядер, лог туннеля, права, отчёт поддержки). UI знает только
  // контракты из core/platform/platform_services.dart и не импортирует
  // engine/windows/* напрямую.
  registerPlatformServices(Platform.isAndroid
      ? buildAndroidPlatformServices()
      : buildWindowsPlatformServices());

  // Принимаем и silentgate://, и одиночные ссылки серверов (vless/vmess/trojan/ss),
  // если пользователь включил их перехват (#10.2).
  //
  // На Windows ссылка приходит аргументом запуска (её передаёт реестр), на
  // Android — интентом; разбор общий (AppUrlScheme), различается только источник.
  final incomingUrl = args.firstWhere(
    AppUrlScheme.isSupportedLink,
    orElse: () => '',
  );

  if (Platform.isWindows) {
    // Single-instance: если приложение уже запущено — переслать ему ссылку и выйти.
    // На Android это даёт сама система (launchMode=singleTask + onNewIntent).
    final server = await SingleInstance.tryBecomePrimary();
    if (server == null) {
      if (incomingUrl.isNotEmpty) await SingleInstance.forward(incomingUrl);
      exit(0);
    }
    // Токен читается КАЖДЫЙ РАЗ через снимок в памяти (см. `_apiTokenSnapshot`),
    // а не захватывается один раз при старте: пользователь может обновить его
    // в настройках при живом приложении, и старое значение перестало бы
    // приниматься.
    SingleInstance.listen(server, IncomingLinks.add,
        token: () => _apiTokenSnapshot);

    // Ядра прошлого запуска, пережившие аварийное завершение, — в утиль.
    // Ждать незачем, поэтому фоном; убиваются только наши (по полному пути).
    final ourBin = XrayPaths.locate()?.assetDir;
    if (ourBin != null) unawaited(CoreCleanup.sweepOrphans(ourBin));
    // Изолированная копия не перехватывает silentgate:// у установленной версии.
    // На Android схемы объявляются в манифесте, регистрировать нечего.
    if (!AppEnv.skipSchemeRegistration) await UrlSchemeWindows.register();
    // Окно и трей — десктопные понятия; на Android их роль играет
    // foreground-сервис с постоянной нотификацией.
    await TrayWindow.instance.init();
  }

  // Android приносит ссылки интентом в Activity, а не через единственный
  // экземпляр. Подписка обязана стоять ДО runApp: ссылка холодного старта уже
  // лежит на нативной стороне и ждёт, когда её заберут.
  unawaited(IncomingLinks.bindPlatform());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              AppState(initialUrl: incomingUrl.isEmpty ? null : incomingUrl)..init(),
        ),
        ChangeNotifierProvider(create: (_) {
          final controller = SettingsController();
          // ⚠️ Слушатель вешаем ЗДЕСЬ, а не через отдельную provider-связку
          // (по образцу `shadeLayoutLinkProvider`/`apiSettingsLinkProvider`
          // ниже — `state/provider_wiring.dart`, обе с `lazy: false`): без
          // этого флага такие связки Provider строит ЛЕНИВО — только когда
          // их тип кто-то читает — а токен нужен обработчику сокета уже
          // сейчас, до первой перерисовки дерева виджетов
          // (`SingleInstance.listen` вызывается в `main()` ДО `runApp`),
          // независимо от того, читает ли что-то эту связку.
          // SettingsController читается напрямую (`app.dart`,
          // `context.watch<SettingsController>()`), поэтому его собственный
          // create гарантированно выполнится в любом случае.
          controller.addListener(
              () => _apiTokenSnapshot = controller.settings.apiToken);
          return controller..init();
        }),
        // Кнопка «Свернуть» на самом уведомлении меняет раскладку в обход
        // настроек — здесь выбор возвращается в них. Без этого приложение
        // прислало бы прежнюю раскладку со следующим обновлением счётчиков
        // (раз в секунду), и кнопка выглядела бы неработающей.
        //
        // ⚠️ Связываем ЗДЕСЬ, а не внутри `AppState`: настройки ему не
        // принадлежат, а лезть за чужим контроллером из состояния — прямой
        // путь к двум источникам правды.
        //
        // Сама связка и обязательный `lazy: false` — в `state/provider_wiring.dart`
        // (там же — почему; тот же файл переиспользует
        // `test/provider_wiring_test.dart`, чтобы страж проверял РЕАЛЬНОЕ
        // дерево, а не свою копию).
        shadeLayoutLinkProvider(),
        ChangeNotifierProvider(create: (_) => ProbeController()..init()),
        ChangeNotifierProvider(create: (_) => AutoConfigController()..init()),
        ChangeNotifierProvider(create: (_) => ServiceCheckController()),
        // Локальный API для автоматизации (см. `AppState.applyApiSettings`,
        // сам гейт «только Windows» — там же). Поднимается/гасится по
        // настройкам API — тумблеру, токену, списку выходов.
        //
        // ⚠️ Слушаем ТОЛЬКО SettingsController, а не AppState/ProbeController.
        // Сервер обязан перезапускаться по факту правки настроек API, а не
        // на каждый тик состояния приложения (счётчики раз в секунду) или
        // результат пинга — иначе локальный сокет пересоздавался бы
        // десятки раз в минуту, обрывая как раз тех, кто через него работает.
        //
        // Сама связка, гейт по `apiSettingsChanged` и обязательный
        // `lazy: false` — в `state/provider_wiring.dart`. Требует, чтобы
        // `ProbeController` был выше в дереве (см. порядок здесь) —
        // `applyIfChanged` читает его через `context.read`.
        apiSettingsLinkProvider(),
      ],
      child: const SilentGateApp(),
    ),
  );
}

/// Служебные режимы запуска Windows-сборки. Возвращает `true`, если процесс
/// отработал служебную роль и приложение поднимать не нужно.
///
/// Все три роли существуют только на Windows: там один и тот же exe работает и
/// интерфейсом, и элевейтнутым TUN-хелпером, и режимом очистки для
/// деинсталлятора. На Android аргументов запуска нет вовсе: туннель поднимает
/// `VpnService` внутри процесса приложения, а данные при удалении стирает
/// система.
Future<bool> _runWindowsCliMode(List<String> args) async {
  // Элевейтнутый TUN-хелпер: запускает sing-box и держит туннель до stop-файла.
  // --tun-task [config] [stop] — запуск из задачи Планировщика (без UAC).
  // Пути передаём ЯВНО (см. TunScheduledTask), фолбэк — %APPDATA% задачи.
  if (args.isNotEmpty && args.first == '--tun-task') {
    await TunHelper.runFromTask(
      configPath: args.length > 1 ? args[1] : null,
      stopPath: args.length > 2 ? args[2] : null,
    );
    exit(0);
  }
  // --tun <config> [stop-файл] — прямой запуск через UAC (fallback).
  if (args.isNotEmpty && args.first == '--tun') {
    await TunHelper.run(
      args.length > 1 ? args[1] : '',
      stopPath: args.length > 2 ? args[2] : '',
    );
    exit(0);
  }

  // Режим очистки при удалении (вызывается деинсталлятором Inno Setup).
  if (args.contains('--cleanup')) {
    await AppCleanup.runHeadless();
    exit(0);
  }

  return false;
}
