import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/geo/geo_bases_controller.dart';
import '../core/settings/app_settings.dart';
import 'app_state.dart';
import 'probe_controller.dart';
import 'settings_controller.dart';

/// Провайдер-связки, существующие РАДИ ПОБОЧНОГО ЭФФЕКТА, а не ради значения,
/// которое кто-то читает.
///
/// ⚠️ Вынесены из `main.dart` в отдельный файл НЕ ради красоты — ради того,
/// чтобы `test/provider_wiring_test.dart` мог собрать РОВНО ТЕ ЖЕ виджеты,
/// что уходят в боевой `runApp`, а не свою параллельную копию. Копия в тесте
/// ловила бы только собственную опечатку, а не регресс в этом файле — тест
/// обязан читать код, а не дублировать его.
///
/// ⚠️ КЛЮЧЕВАЯ ЛОВУШКА, НА КОТОРУЮ УЖЕ НАСТУПИЛИ ДВАЖДЫ: `ProxyProvider` /
/// `ProxyProvider2` строят значение ЛЕНИВО — `create`/`update` вызываются
/// ТОЛЬКО когда их тип читает `context.watch`/`context.read` ГДЕ-ТО в дереве.
/// Обе связки ниже (`ShadeLayoutLink`, `ApiSettingsLink`) — приватные по
/// смыслу типы, их не читает никто и не должен: единственная причина их
/// существования — сработавший конструктор/`update`. Без `lazy: false` они
/// не строились бы вообще, а находка выглядела бы как «рабочий код» —
/// компилятор и `flutter analyze` такое не ловят. НЕ убирать `lazy: false`
/// и НЕ чинить это чтением типа в каком-нибудь виджете «просто чтобы
/// сработало»: такая связь держится на том, что конкретный виджет ничего не
/// поменяет в будущем, и рвётся на первой же его правке.

/// Связка «кнопка в шторке → настройка приложения».
///
/// Существует ради одного побочного эффекта и ничего не хранит: нажатие
/// «Свернуть»/«Развернуть» на самом уведомлении обязано попасть в настройки,
/// иначе приложение вернёт прежнюю раскладку со следующим тактом счётчиков
/// (раз в секунду), и кнопка выглядела бы неработающей.
///
/// ⚠️ Связываем ЗДЕСЬ, а не внутри `AppState`: настройки ему не принадлежат,
/// а лезть за чужим контроллером из состояния — прямой путь к двум
/// источникам правды.
class ShadeLayoutLink {
  ShadeLayoutLink(AppState state, SettingsController settings) {
    state.onCompactToggledInShade = (compact) {
      if (settings.settings.compactNotification == compact) return;
      settings.update((s) => s.copyWith(compactNotification: compact));
    };
  }
}

/// Провайдер [ShadeLayoutLink] — `lazy: false` обязателен, см. комментарий
/// вверху файла.
ProxyProvider2<AppState, SettingsController, ShadeLayoutLink>
    shadeLayoutLinkProvider() =>
        ProxyProvider2<AppState, SettingsController, ShadeLayoutLink>(
          lazy: false,
          update: (_, state, settings, __) =>
              ShadeLayoutLink(state, settings),
        );

/// Связка «настройки API → локальный сервер автоматизации».
///
/// ⚠️ В ОТЛИЧИЕ ОТ [ShadeLayoutLink] — ХРАНИТ СОСТОЯНИЕ, И ЭТО НАМЕРЕННО.
/// `ProxyProvider.update` зовётся на КАЖДУЮ правку любых настроек (тема,
/// язык, MTU, правила — что угодно), а `AppState.applyApiSettings` гасит и
/// заново поднимает слушающий сокет безусловно. Без гейта локальный API
/// перезапускался бы на любую не связанную с ним правку, обрывая тех, кто
/// через него в этот момент работает (раунд ревью 1, находка 4). Тот же
/// экземпляр [ApiSettingsLink] переживает все перестройки провайдера
/// (`previous` в [apiSettingsLinkProvider]), поэтому есть, с чем сравнивать.
class ApiSettingsLink {
  AppSettings? _lastApplied;

  /// AppState и ProbeController берём БЕЗ подписки (`context.read`): нам
  /// нужна только ссылка, а не реакция на их собственные изменения — иначе
  /// сокет пересоздавался бы на каждый их чих, а не только на правку настроек.
  void applyIfChanged(BuildContext context, SettingsController settings) {
    final s = settings.settings;
    final prev = _lastApplied;
    if (prev != null && !prev.apiSettingsChanged(s)) return;
    _lastApplied = s;
    final state = context.read<AppState>();
    final probe = context.read<ProbeController>();
    unawaited(state.applyApiSettings(s, probe, settings));
  }
}

/// Провайдер [ApiSettingsLink] — `lazy: false` обязателен, см. комментарий
/// вверху файла. Требует `ProbeController` доступным ВЫШЕ этого провайдера
/// в дереве (`applyIfChanged` читает его через `context.read`).
ProxyProvider<SettingsController, ApiSettingsLink> apiSettingsLinkProvider() =>
    ProxyProvider<SettingsController, ApiSettingsLink>(
      lazy: false,
      update: (context, settings, previous) =>
          (previous ?? ApiSettingsLink())..applyIfChanged(context, settings),
    );

/// Состояние гео-баз (`geoip.dat`/`geosite.dat`) для настроек и главного
/// экрана.
///
/// ⚠️ `lazy: false` ЗДЕСЬ — НЕ КОПИРОВАНИЕ СОСЕДНЕГО ПРАВИЛА. У
/// `ChangeNotifierProvider` ленивость означает, что контроллер появляется на
/// свет в момент ПЕРВОГО чтения его типа. Сегодня такое чтение ровно одно —
/// раздел гео-баз в настройках, — и это ровно та связь, на которой в 1.4.0 уже
/// сгорел локальный API: пока читатель есть, всё работает, а в день, когда
/// единственного читателя переименуют или уберут, провайдер молча перестаёт
/// существовать, и ни компилятор, ни `flutter analyze` про это не скажут.
///
/// Плюс к тому [GeoBasesController.refresh] — это чтение каталога с диска:
/// сделанное при запуске, оно даёт настройкам готовое состояние на ПЕРВОМ
/// кадре, а не «неизвестно» с последующим прыжком строки.
///
/// [create] существует ради стража (`test/geo_bases_ui_test.dart`): он собирает
/// РОВНО ЭТУ функцию, что уходит в `runApp`, и проверяет, что контроллер
/// создаётся в дереве, где его тип не читает никто. В боевом коде параметр не
/// передаётся.
ChangeNotifierProvider<GeoBasesController> geoBasesProvider({
  GeoBasesController Function()? create,
}) =>
    ChangeNotifierProvider<GeoBasesController>(
      lazy: false,
      create: (_) => (create?.call() ?? GeoBasesController())..refresh(),
    );

/// Связка «состав серверов поменялся → почистить пометки незаконченного прогона».
///
/// ⚠️ РАДИ ЧЕГО ЗАВЕДЕНА. Чистку `ping_unfinished.json` звал переключатель
/// подписок при открытии меню — а он рисуется ТОЛЬКО при двух и более
/// подписках (`subscription_bar.dart`). У владельца ОДНОЙ подписки, то есть у
/// большинства, чистка не срабатывала никогда: файл рос без предела, а узел,
/// вернувшийся в подписку с прежним ключом, помечал её неполной по прогону,
/// которого в этой её жизни не было.
///
/// ⚠️ ОБЕ СТОРОНЫ СВЯЗЫВАЮТСЯ ЗДЕСЬ, И ПОРЯДОК НЕ ВАЖЕН НАРОЧНО. Состояние
/// сообщает о смене состава, контроллер проб предоставляет ответ «что вообще
/// известно» — но пометки читаются с диска своим чередом, и кто успеет первым,
/// не задано ничем. Поэтому чистка отложенная: пока поставщик списка не
/// известен, признак «состав менялся» не снимается, и она случится позже.
/// Ровно на такой гонке в 1.4.3 терялись профили «Авто».
class UnfinishedPruneLink {
  UnfinishedPruneLink(AppState state, ProbeController probe) {
    // ⚠️ Поставщик, а не готовый список: собрать его — это разбор сотни ссылок
    // и декодирование панельных конфигов. Ради ответа «чистить нечего» такое
    // делать нельзя, а связка пересобирается на каждое уведомление состояния.
    probe.knownServerKeys =
        () => [for (final s in state.allSubscriptionServers()) s.key];
    state.onServersChanged = probe.markServersChanged;
    unawaited(probe.pruneUnfinished());
  }
}

/// Провайдер [UnfinishedPruneLink] — `lazy: false` обязателен, см. комментарий
/// вверху файла.
ProxyProvider2<AppState, ProbeController, UnfinishedPruneLink>
    unfinishedPruneLinkProvider() =>
        ProxyProvider2<AppState, ProbeController, UnfinishedPruneLink>(
          lazy: false,
          update: (_, state, probe, __) => UnfinishedPruneLink(state, probe),
        );
