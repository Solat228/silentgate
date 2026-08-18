import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/probe_controller.dart';
import 'app_toast.dart';

/// Почему пинг сейчас запустить НЕЛЬЗЯ.
///
/// Порядок значений повторяет порядок проверок в `ProbeController._pingBatch`:
/// первая сработавшая и есть причина, которую видит человек.
enum PingBlocker {
  /// Прогон пинга уже идёт.
  pinging,

  /// Идёт замер скорости. Он держит ТОТ ЖЕ харнесс и те же локальные порты,
  /// поэтому пинг поверх него не запускается.
  measuringSpeed,

  /// Идёт автопрогон проверки сервисов у кнопки Connect.
  ///
  /// ⚠️ ЗАНЯТ ОДИН И ТОТ ЖЕ ПОРТ ЖИВОГО ЯДРА. Пробы сервисов идут через него, и
  /// через него же пинг проверяет подключённый сервер; на Windows в режиме по
  /// умолчанию туда смотрит ещё и системный прокси всей машины. Владелец
  /// включил все 14 сервисов и получил «всё сломалось и не пингуется с самого
  /// начала» — пинг, начатый поверх такой пачки, добавляет к ней свои
  /// соединения ровно в ту же секунду.
  servicesChecking,

  /// Пинговать нечего: пустой список серверов (или поиск ничего не нашёл).
  noTargets,
}

/// «Можно ли сейчас пинговать, а если нет — почему», одним объектом на все
/// точки входа.
///
/// ⚠️ ЗАЧЕМ ОБЩИЙ ГЕЙТ, А НЕ `if` ПО ЭКРАНАМ.
/// `ProbeController._pingBatch` выходит первой же строкой
/// (`if (_running || _speedRunning || serviceChecksRunning || servers.isEmpty)
/// return;`), а условие
/// «идёт замер скорости» повторяла у себя не каждая точка входа: кнопка на
/// экране серверов и пункт «Пинг» в контекстном меню строки спрашивали только
/// `probe.running` и выглядели совершенно живыми — замер сотни серверов идёт
/// десятки минут, и всё это время человек жал и не получал ни действия, ни
/// объяснения. Ровно эта жалоба правку и породила.
///
/// ⚠️ ЧТО ГЕЙТ ЗАКРЫВАЕТ НА САМОМ ДЕЛЕ — ДВЕ ТОЧКИ ВХОДА, И ТОЛЬКО ИХ:
///  * кнопку пинга в шапке `ui/servers_screen.dart`;
///  * пункт «Пинг» в контекстном меню `ui/widgets/server_tile.dart`.
///
/// Остальные места, откуда начинается прогон, сюда ещё НЕ переведены и
/// спрашивают исполнителя своим кодом: кнопка «Пинг серверов» на главном
/// (`ui/home_screen.dart`), пункт «Пинг серверов» в меню переключателя
/// подписок (`ui/widgets/subscription_switcher.dart`) и `POST /v1/ping`
/// локального API (`state/api_handlers.dart`, интерфейса у него нет вовсе).
/// Перечислять их как закрытые нельзя: обещание в комментарии — ровно то, из-за
/// чего расхождение и живёт незамеченным.
///
/// ⚠️ РАЗРЕШЕНИЕ И ИСПОЛНЕНИЕ ОБЯЗАНЫ СПРАШИВАТЬ ОДНО И ТО ЖЕ. Здесь условия
/// исполнителя ПОВТОРЕНЫ, а не выведены заново, и совпадение с ним проверяется
/// на НАСТОЯЩЕМ `ProbeController` в `test/ping_gate_test.dart` — не на словах:
/// разойдись они, интерфейс снова обещал бы то, чего исполнитель не делает.
@immutable
class PingGate {
  /// `null` — пинг разрешён.
  final PingBlocker? blocker;

  const PingGate._(this.blocker);

  /// Гейт по ЖИВОМУ состоянию контроллера.
  ///
  /// [hasTargets] — есть ли что пинговать именно в этой точке входа (кнопка
  /// экрана серверов пингует найденное поиском, пункт меню строки — один
  /// сервер, пункт меню переключателя — все подписки).
  factory PingGate.of(ProbeController probe, {bool hasTargets = true}) =>
      PingGate.from(
        pinging: probe.running,
        measuringSpeed: probe.speedRunning,
        // ⚠️ Спрашиваем ИСПОЛНИТЕЛЯ, а не проверку сервисов напрямую: ровно то
        // же поле читает `ProbeController._pingBatch`, отказывая в прогоне.
        servicesChecking: probe.serviceChecksRunning,
        hasTargets: hasTargets,
      );

  /// Тот же гейт из голых признаков — для тестов и мест, где контроллера нет.
  ///
  /// [servicesChecking] со значением по умолчанию — не послабление: у голых
  /// признаков нет источника этого флага, а места, которые его знают, идут
  /// через [PingGate.of].
  factory PingGate.from({
    required bool pinging,
    required bool measuringSpeed,
    required bool hasTargets,
    bool servicesChecking = false,
  }) {
    if (pinging) return const PingGate._(PingBlocker.pinging);
    if (measuringSpeed) return const PingGate._(PingBlocker.measuringSpeed);
    if (servicesChecking) {
      return const PingGate._(PingBlocker.servicesChecking);
    }
    if (!hasTargets) return const PingGate._(PingBlocker.noTargets);
    return const PingGate._(null);
  }

  bool get allowed => blocker == null;

  /// Причина словами; `null` — пинг разрешён, объяснять нечего.
  ///
  /// [noTargets] — своя формулировка «пинговать нечего»: на экране серверов при
  /// активном поиске правда звучит как «Ничего не найдено», а не «список пуст».
  /// Не задана — общий текст про пустой список.
  ///
  /// Лишних формулировок гейт не заводит: где строка уже есть в переводах, он
  /// берёт её, а не сочиняет четвёртый способ сказать то же самое.
  String? reason(AppLocalizations l, {String? noTargets}) {
    final b = blocker;
    if (b == null) return null;
    return switch (b) {
      PingBlocker.pinging => l.serversPinging,
      PingBlocker.measuringSpeed => l.subSwitcherPingBusySpeed,
      PingBlocker.servicesChecking => l.pingBusyServiceChecks,
      PingBlocker.noTargets => noTargets ?? l.serversEmpty,
    };
  }

  /// Подпись действия: причина, когда нельзя, и [idle], когда можно. Годится и
  /// как подсказка к кнопке, и как текст строки меню.
  String label(AppLocalizations l, String idle, {String? noTargets}) =>
      reason(l, noTargets: noTargets) ?? idle;

  /// Для обработчика нажатия: `true` — пинговать можно; `false` — нельзя, и
  /// причина УЖЕ показана уведомлением.
  ///
  /// ⚠️ Проверка `context.mounted` внутри: этот путь зовут после закрытия
  /// контекстного меню, то есть через `await`, и к тому моменту виджета может
  /// уже не быть. Вызывающему на пути с `await` всё равно нужен свой
  /// `context.mounted` — иначе анализатор справедливо ругается на использование
  /// контекста через асинхронный разрыв.
  bool allowOrExplain(BuildContext context, {String? noTargets}) {
    if (allowed) return true;
    if (context.mounted) {
      final why = reason(AppLocalizations.of(context), noTargets: noTargets);
      if (why != null) {
        AppToast.show(context, why, kind: ToastKind.warning);
      }
    }
    return false;
  }
}
