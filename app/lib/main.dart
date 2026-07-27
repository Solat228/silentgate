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
import 'engine/windows/platform_services_windows.dart';
import 'engine/windows/tun/tun_helper.dart';
import 'engine/windows/xray_paths.dart';
import 'state/app_state.dart';
import 'state/auto_config_controller.dart';
import 'state/probe_controller.dart';
import 'state/service_check_controller.dart';
import 'state/settings_controller.dart';

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
  registerPlatformServices(buildWindowsPlatformServices());

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
    SingleInstance.listen(server, IncomingLinks.add);
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              AppState(initialUrl: incomingUrl.isEmpty ? null : incomingUrl)..init(),
        ),
        ChangeNotifierProvider(create: (_) => SettingsController()..init()),
        ChangeNotifierProvider(create: (_) => ProbeController()..init()),
        ChangeNotifierProvider(create: (_) => AutoConfigController()..init()),
        ChangeNotifierProvider(create: (_) => ServiceCheckController()),
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
