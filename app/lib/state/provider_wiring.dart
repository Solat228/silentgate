import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

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
