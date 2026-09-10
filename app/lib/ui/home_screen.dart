import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;

import 'layout/adaptive.dart';
import 'package:provider/provider.dart';

import '../core/geo/geo_bases_controller.dart';
import '../core/models/traffic_stats.dart';
import '../core/models/vpn_server.dart';
import '../core/models/vpn_status.dart';
import '../core/net/speed_test.dart';
import '../core/platform/interference_scanner.dart';
import '../core/app_info.dart';
import '../core/platform/app_log.dart';
import '../core/platform/app_launcher.dart';
import '../core/platform/notification_access.dart';
import '../core/platform/platform_services.dart';
import '../core/settings/split_tunnel.dart';
import '../core/update/app_update.dart';
import '../core/settings/app_settings.dart';
import '../core/probe/clash_delay.dart';
import '../core/probe/ping_result.dart';
import '../core/util/country_flag.dart';
import '../core/util/server_search.dart';
import '../core/i18n/enum_labels.dart';
import '../core/i18n/text_direction.dart';
import '../l10n/gen/app_localizations.dart';
import 'widgets/info_tooltip.dart';
import '../state/app_state.dart';
import '../core/models/engine_notice.dart';
import 'split_tunnel_screen.dart';
import '../state/auto_config_controller.dart';
import '../state/probe_controller.dart';
import '../state/service_check_controller.dart';
import '../state/settings_controller.dart';
import 'auto_config_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'widgets/app_toast.dart';
import 'widgets/auto_pick_button.dart';
import 'widgets/connect_guard.dart';
import 'widgets/flag_cell.dart';
import 'widgets/server_search_field.dart';
import 'widgets/server_tile.dart';
import 'widgets/service_checks_row.dart';
import 'widgets/update_notes_dialog.dart';
import 'widgets/subscription_bar.dart';
import 'widgets/ping_chip.dart';
import 'widgets/ping_gate.dart';
import 'server_info_screen.dart';
import 'servers_screen.dart';
import '../engine/probe_factory.dart';

/// Что сделать с карточкой подбора стека/MTU TUN на этом такте перерисовки.
enum TunToastStep { progress, summary, dismiss, none }

/// ⚠️ Дефект, который лечит шаг [TunToastStep.dismiss]: отменённый подбор
/// оставлял карточку висеть НАВСЕГДА. `TunAutotuneTracking.next` на отмене
/// (disconnected/disconnecting) гасит `running` и НЕ ставит `finishedAt` —
/// в самом ядре так и написано «гасим прогресс без тоста-итога», но гасить было
/// некому: главный экран просто не попадал ни в одну из двух веток, а карточка
/// с крутящейся полоской сама не уходит — обратный отсчёт заводится только
/// у `finished: true`. Так же вело себя завершение с уже показанным итогом,
/// поэтому отличаем их по [cardLive]: снимаем только НЕЗАВЕРШЁННУЮ карточку,
/// иначе итог исчезал бы, не дав себя прочитать.
///
/// Вынесено отдельной функцией, чтобы это решение проверялось тестом, а не
/// поднятием всего главного экрана с движком.
TunToastStep tunToastStep({
  required bool running,
  required DateTime? finishedAt,
  required DateTime? shownFinishedAt,
  required bool cardLive,
}) {
  if (running) return TunToastStep.progress;
  if (finishedAt != null && finishedAt != shownFinishedAt) {
    return TunToastStep.summary;
  }
  return cardLive ? TunToastStep.dismiss : TunToastStep.none;
}

/// Что будет сделано при прогоне скорости по списку и во что это обойдётся.
class SpeedRunPlan {
  /// Кого реально померим.
  final List<VpnServer> targets;

  /// Сколько серверов пропущено, потому что скорость у них уже есть (в том
  /// числе из автонастройки): повторный замер стоил бы трафика ни за что.
  final int alreadyMeasured;

  /// Сколько байт скачает прогон целиком.
  final int bytes;

  const SpeedRunPlan({
    required this.targets,
    required this.alreadyMeasured,
    required this.bytes,
  });

  bool get isEmpty => targets.isEmpty;
}

/// Сколько серверов пойдёт в замер и сколько это трафика ПОДПИСКИ.
///
/// ⚠️ Вынесено отдельной функцией не ради красоты: у владельца 101 сервер, и
/// прогон по списку — это до двух гигабайт его подписки. Число, которым мы
/// пугаем человека в диалоге, обязано считаться тем же кодом, что потом
/// действительно качает, и обязано проверяться тестом.
SpeedRunPlan speedRunPlan(
  List<VpnServer> servers,
  ProbeController probe,
  SpeedTestSize size,
) {
  final targets = probe.speedTargets(servers);
  final eligible =
      servers.where((s) => probe.resultFor(s).speedMeasurable).length;
  return SpeedRunPlan(
    targets: targets,
    alreadyMeasured: eligible - targets.length,
    bytes: targets.length * size.bytes,
  );
}

/// Подтверждение прогона по списку с честным объёмом трафика.
///
/// ⚠️ БЕЗ НЕГО НЕЛЬЗЯ. Замер качает данные из подписки пользователя, и случайное
/// нажатие кнопки рядом с «Пинг серверов» стоило бы ему сотен мегабайт, о
/// которых он не просил.
Future<bool> confirmSpeedRun(BuildContext context, SpeedRunPlan plan,
    SpeedTestSize size) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.speedConfirmTitle),
      content: Text([
        l.speedConfirmBody(
          plan.targets.length,
          TrafficStats.formatBytes(size.bytes),
          TrafficStats.formatBytes(plan.bytes),
        ),
        if (plan.alreadyMeasured > 0)
          l.speedConfirmSkipped(plan.alreadyMeasured),
      ].join('\n\n')),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.speedConfirmRun)),
      ],
    ),
  );
  return ok ?? false;
}

/// Кнопка «измерить скорость всех» целиком: план → подтверждение → прогон.
///
/// Вся последовательность живёт в одной функции намеренно — чтобы тест проверял
/// ИМЕННО ТОТ путь, по которому идёт нажатие, а не свою копию рядом. Разойдись
/// они, и подтверждение можно было бы потерять, не уронив ни одного теста.
Future<void> startSpeedRun(
  BuildContext context,
  ProbeController probe,
  List<VpnServer> servers,
  AppSettings settings,
) async {
  final l = AppLocalizations.of(context);
  final plan = speedRunPlan(servers, probe, settings.speedTestSize);
  if (plan.isEmpty) {
    AppToast.show(context, l.speedNoTargets, kind: ToastKind.warning);
    return;
  }
  if (!await confirmSpeedRun(context, plan, settings.speedTestSize)) return;
  if (!context.mounted) return;
  unawaited(probe.measureSpeedAll(plan.targets, settings));
}

/// Намерение «скопировать ключ выбранного сервера» (Ctrl+C).
class CopyServerKeyIntent extends Intent {
  const CopyServerKeyIntent();
}

/// Ctrl+C копирует ключ сервера, ВЫБРАННОГО В СПИСКЕ (на macOS — Cmd+C).
///
/// ⚠️ ЭТО ПЕРВЫЙ ОБРАБОТЧИК КЛАВИШ В ПРИЛОЖЕНИИ, поэтому здесь подробно про
/// три вещи, каждая из которых по отдельности превращает клавишу в мину.
///
/// (1) ⚠️ ГЛОБАЛЬНЫЙ Ctrl+C ОТБИРАЕТ КОПИРОВАНИЕ У ПОЛЕЙ ВВОДА. Событие
/// клавиши идёт от сфокусированного узла НАРУЖУ, а наш `Shortcuts` стоит
/// ближе к полю, чем `DefaultTextEditingShortcuts` приложения — значит
/// отвечаем мы, и штатное копирование текста до поля бы не доехало. Сломались
/// бы поиск по серверам, поле ссылки на экране импорта, редактор JSON и
/// выделенный `SelText`. Лечение — [focusInsideTextInput]: пока фокус внутри
/// текста, действие ВЫКЛЮЧЕНО, а выключенное действие отдаёт
/// `KeyEventResult.ignored`, и событие уходит выше, туда где его ждут.
/// (Оборачивать приложение в `SelectionArea` ради выделения нельзя — она
/// съедает правый клик и прокрутку, см. `SelText`.)
///
/// (2) ⚠️ БЕЗ СОБСТВЕННОГО ФОКУСА КЛАВИША НЕ РАБОТАЕТ ВОВСЕ. Пока в поддереве
/// никто не сфокусирован, основной фокус держит `FocusScope` МАРШРУТА — а он
/// наш ПРЕДОК; поиск действия идёт от сфокусированного узла вверх и наш
/// `Actions` в этом обходе не встречается. Отсюда `Focus(autofocus: true)`
/// внутри: он же возвращает себе фокус после закрытия диалога (сцена помнит
/// последнего сфокусированного ребёнка).
///
/// (3) ⚠️ Копируем ВЫБРАННЫЙ сервер, а не подключённый: клик по другому
/// серверу живой туннель не трогает, и человек ждёт того, что у него
/// подсвечено в списке. Ничего не выбрано — действие выключено, а не «молча
/// ничего не делает»: тогда Ctrl+C хотя бы достанется тому, кто его ждёт.
class CopyServerKeyShortcut extends StatefulWidget {
  final Widget child;

  /// Чем копировать. Подменяется только тестом; в приложении всегда работает
  /// умолчание — [serverClipboardPayload], та же функция, что и у пункта
  /// «Скопировать ключ» в меню строки сервера (клавиша и меню обязаны класть
  /// в буфер одно и то же).
  final void Function(BuildContext context, VpnServer server)? onCopy;

  const CopyServerKeyShortcut({super.key, required this.child, this.onCopy});

  /// Клавиатура есть только на десктопе — на телефоне вешать нечего.
  static bool get hasKeyboard =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Фокус сейчас внутри поля ввода или выделяемого текста?
  ///
  /// Признак — `EditableText` среди предков сфокусированного узла: на нём
  /// стоят и `TextField`, и `SelectableText` (то есть `SelText`), так что
  /// одна проверка закрывает оба случая.
  @visibleForTesting
  static bool focusInsideTextInput([FocusNode? node]) {
    final ctx = (node ?? primaryFocus)?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  State<CopyServerKeyShortcut> createState() => _CopyServerKeyShortcutState();
}

class _CopyServerKeyShortcutState extends State<CopyServerKeyShortcut> {
  late final _CopyServerKeyAction _action = _CopyServerKeyAction(this);

  /// Есть что копировать и не мешаем ли мы полю ввода.
  bool get canCopy =>
      !CopyServerKeyShortcut.focusInsideTextInput() && _target != null;

  VpnServer? get _target => context.read<AppState>().selectedServer;

  Future<void> copySelected() async {
    final server = _target;
    if (server == null) return;
    final custom = widget.onCopy;
    if (custom != null) {
      custom(context, server);
      return;
    }
    // ⚠️ Ни ссылку, ни конфиг не пишем ни в журнал, ни в текст уведомления:
    // внутри логин сервера. Уведомление — общее «Скопировано», как и у меню.
    await Clipboard.setData(
        ClipboardData(text: serverClipboardPayload(server)));
    if (mounted) AppToast.copied(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!CopyServerKeyShortcut.hasKeyboard) return widget.child;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // На macOS копирование — Cmd+C; Ctrl+C там означает другое, и вешать
        // его значило бы спорить с системной привычкой.
        if (Platform.isMacOS)
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
              const CopyServerKeyIntent()
        else
          const SingleActivator(LogicalKeyboardKey.keyC, control: true):
              const CopyServerKeyIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{CopyServerKeyIntent: _action},
        child: Focus(autofocus: true, child: widget.child), // см. (2)
      ),
    );
  }
}

class _CopyServerKeyAction extends Action<CopyServerKeyIntent> {
  _CopyServerKeyAction(this._host);

  final _CopyServerKeyShortcutState _host;

  /// ⚠️ Именно ОТКЛЮЧЕНИЕ, а не пустой `invoke`: выключенное действие пропускает
  /// событие выше по дереву фокуса (см. (1) в описании виджета), а вызванное
  /// и ничего не сделавшее — съедает его.
  @override
  bool get isActionEnabled => _host.canCopy;

  @override
  Object? invoke(CopyServerKeyIntent intent) => _host.copySelected();
}

/// Сколько высоты отдать блоку «проверки + кнопка», чтобы под ним уместилось
/// то, что идёт ниже: строка статуса, «Информация о сервере», кнопки режима и
/// счётчики трафика.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНАЯ ФУНКЦИЯ, А НЕ ВЫРАЖЕНИЕ В `build`. Жалоба владельца
/// 03.09.2026: при четырнадцати сервисах блока с информацией о подключении
/// внизу не видно ВООБЩЕ, при шести срезаны счётчики. Стражи вёрстки этого не
/// поймали и поймать не могли: они поднимают публичный `ConnectCenterpiece`, а
/// переполнялась ПАНЕЛЬ, которая приватна и в тест не поднимается. Значит
/// единственное, что здесь можно проверить тестом, — сам расчёт; его и выносим.
///
/// ⚠️ ПЕРВАЯ ПОПЫТКА ПОЧИНИТЬ ЭТО БЫЛА НЕВЕРНОЙ И ОТКАЧЕНА. Блок оборачивали в
/// `Flexible`, рассчитывая, что включится его собственное сжатие. Включилось
/// другое: `Flexible` сжал блок НИЖЕ его минимума, и на снимке из VM
/// «Автонастройка» легла поверх кнопки Connect. Потолок и доля остатка — разные
/// вещи: здесь нужен именно потолок.
///
/// [reserveBelow] по умолчанию — [kChecksReserveBelow]; измерен на настоящем
/// окне (снимки из VM, 980×800).
///
/// [blockingNotice] и [errorLine] — то, что появляется под потолком НЕ ВСЕГДА:
/// плашка kill switch и строка ошибки. Считаются [blockingNoticeHeight] и
/// [errorLineHeight] по фактическому тексту; нет врезки — ноль.
///
/// ⚠️ ЗАЧЕМ ОНИ ОТДЕЛЬНЫМИ СЛАГАЕМЫМИ, А НЕ ЧАСТЬЮ [kChecksReserveBelow].
/// Обе врезки стоят НИЖЕ `ConstrainedBox`, то есть в резерв обязаны входить, —
/// но появляются в аварии, а не всегда. Заложить их в постоянный резерв значило
/// бы держать 80 пустых пикселей всё остальное время, а это ровно те пиксели,
/// из-за которых значки сервисов и сжимались. Пока их не было в расчёте,
/// панель с четырнадцатью сервисами и поднятым kill switch переполнялась НА
/// ВСЕХ окнах (замер: 964×761 — на 61 px, 980×800 — на 37, 1024×781 — на 9), и
/// ломалась она ровно в тот момент, когда интерфейс обязан быть понятным:
/// человек видит пропавший интернет и решает, не выключить ли VPN.
///
/// ⚠️ ИСТОРИЯ ЗНАЧЕНИЯ ПО УМОЛЧАНИЮ — ПО КОММИТАМ, А НЕ ПО ПАМЯТИ: 210 (до
/// 04.09.2026) → 214 (до 10.09.2026) → [kChecksReserveBelow]. Числа 254 в коде
/// не было НИКОГДА: оно появилось в комментарии как «сколько 214 должно было бы
/// быть» и развело раскладку с арифметикой. Прежние значения складывались на
/// глаз (собственная расшифровка 214 давала 162) и «работали» лишь потому, что
/// блок никогда не дорастал до потолка: рост был зажат, см. `ServiceChecksSides`.
/// Отсюда правило: число даёт ЗАМЕР в тесте, комментарий его только поясняет.
@visibleForTesting
double checksHeightBudget({
  required double paneHeight,
  double reserveBelow = kChecksReserveBelow,
  double textScale = 1.0,
  double blockingNotice = 0,
  double errorLine = 0,
}) {
  if (!paneHeight.isFinite || paneHeight <= 0) return double.infinity;
  // ⚠️ РЕЗЕРВ РАСТЁТ ВМЕСТЕ С СИСТЕМНЫМ ШРИФТОМ. Всё, что лежит ниже потолка,
  // — это текст: строка статуса, подпись кнопки, счётчики трафика. При
  // масштабе 1,3 они занимают на треть больше, а потолок остался бы прежним —
  // и низ уехал бы за край ровно у того, кто увеличил шрифт, чтобы читать.
  // Уменьшать резерв ниже единицы НЕЛЬЗЯ: мелкий шрифт не сжимает ни кнопку
  // (её высота — область нажатия), ни отступы.
  final k = textScale.isFinite && textScale > 1 ? textScale : 1.0;
  // ⚠️ ВРЕЗКИ НА `k` НЕ УМНОЖАЮТСЯ: их высота уже посчитана настоящим
  // `TextScaler`-ом по настоящему тексту. Умножить ещё раз значило бы отобрать
  // у блока проверок треть высоты врезки дважды.
  final left = paneHeight - reserveBelow * k - _finite(blockingNotice) - _finite(errorLine);
  // ⚠️ НИЖЕ ЭТОГО НЕ ОПУСКАЕМСЯ. Отдать блоку меньше, чем занимает сама кнопка,
  // значит получить наложение — ровно то, что дала первая попытка. Пусть лучше
  // срежется низ, чем интерфейс сложится сам на себя. 186 = плашка активного
  // сервера 38 + кнопка 148: меньше этого кнопка не помещается физически.
  const floor = 186.0;
  return left < floor ? floor : left;
}

/// Отрицательное/`NaN` слагаемое не должно РАСШИРЯТЬ потолок: расчёт врезки
/// приходит извне, и ошибка в нём обязана стоить лишних пикселей, а не
/// наложения кнопки на счётчики.
double _finite(double v) => v.isFinite && v > 0 ? v : 0;

/// Высота плашки kill switch ВМЕСТЕ с её отступом сверху.
///
/// ⚠️ СЧИТАЕТСЯ, А НЕ БЕРЁТСЯ КОНСТАНТОЙ. Текст сообщения приходит от движка,
/// длина его не задана ничем, и при системном шрифте ×1,3 он переносится на
/// вторую строку уже на минимальном окне. Константа «на одну строку» дала бы
/// переполнение ровно у того, кто увеличил шрифт, чтобы читать.
///
/// Слагаемые берутся из самой [KillSwitchNotice] — один источник правды:
/// разъедутся виджет и расчёт, и потолок отступит не на столько, на сколько
/// нужно. Стережёт `test/auto_pick_placement_test.dart` («резерв под врезки
/// замерен, а не прикинут»): он сверяет это число с НАСТОЯЩЕЙ высотой плашки.
@visibleForTesting
double blockingNoticeHeight({
  required double paneWidth,
  required TextStyle style,
  required TextScaler scaler,
  required String text,
}) {
  final textWidth = paneWidth -
      KillSwitchNotice.paddingH * 2 -
      KillSwitchNotice.iconSize -
      KillSwitchNotice.gap;
  final textHeight = _textHeight(text, textWidth, style, scaler);
  // Значок в шрифте не растёт (`Icon` без `applyTextScaling`), поэтому строка
  // не бывает ниже него.
  final content =
      textHeight > KillSwitchNotice.iconSize ? textHeight : KillSwitchNotice.iconSize;
  return KillSwitchNotice.marginTop + KillSwitchNotice.paddingV * 2 + content;
}

/// Высота строки ошибки под статусом ВМЕСТЕ с её отступом сверху.
///
/// Текст ошибки движка бывает длинным (имя сервера, код, причина) — считаем
/// перенос так же, как у плашки.
@visibleForTesting
double errorLineHeight({
  required double paneWidth,
  required TextStyle style,
  required TextScaler scaler,
  required String text,
}) =>
    ConnectErrorLine.paddingTop + _textHeight(text, paneWidth, style, scaler);

/// Высота текста с учётом переноса по [maxWidth] и системного масштаба шрифта.
double _textHeight(
    String text, double maxWidth, TextStyle style, TextScaler scaler) {
  if (!maxWidth.isFinite || maxWidth <= 0) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    // Направление на метрики не влияет, а настоящее приходит из содержимого
    // (`autoTextDirection`) и здесь неизвестно.
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

/// Сколько высоты панели лежит НИЖЕ блока «плашка + проверки + кнопка».
///
/// ⚠️ ЧИСЛО ЗАМЕРЕНО, А НЕ ПРИКИНУТО — `test/auto_pick_placement_test.dart`
/// считает его по настоящей вёрстке панели (низ счётчиков трафика минус низ
/// блока минус распорка между ними) и краснеет, если оно разойдётся с
/// реальностью. Врать в этом комментарии дороже, чем ошибиться в вёрстке:
/// по нему принимают решения о размере значков.
///
/// Раскладка ПОСЛЕ сжатия низа (10.09.2026), сверху вниз:
///   16  — просвет под блоком;
///   24  — строка статуса (`titleMedium`: 16 × 1,5);
///   20  — просвет перед кнопками;
///   48  — ОДНА строка `Wrap` с кнопками («Подобрать настройки», на узком
///         окне рядом с ней «Подобрать сервер»). ⚠️ 48, а не 40: Material
///         дотягивает кнопку до области нажатия (`tapTargetSize: padded`),
///         и на глаз здесь ошибаются ровно на эти 8 px;
///   58  — счётчики трафика.
///   ---
///   166 итого — сумма сходится, и она же подтверждена замером.
///
/// ⚠️ ЧТО УШЛО ИЗ ЭТОЙ ОБЛАСТИ 10.09.2026: строка «Информация о сервере»
/// (8 отступа + 40 кнопки = 48) уехала значком в полосу плашки, а вторая
/// кнопка своей строкой (8 отступа + 48 кнопки = 56) встала в ту же строку
/// `Wrap`. Итого прежней раскладке под потолком было нужно 166 + 48 + 56 = 270.
/// ⚠️ И ЭТО НЕ ТО ЖЕ, ЧТО СТОЯЛО В КОДЕ: там было 214, то есть на 56 меньше
/// нужного. Числа 254 не было НИКОГДА — оно появилось в комментарии как
/// промежуточная прикидка и не сходилось ни с 214, ни с 270, ни с суммой
/// слагаемых. Раскладка, которая не сходится, хуже отсутствующей: ей
/// перестают верить, а она здесь единственный рычаг размера значков.
///
/// ⚠️ ПЛАШКА KILL SWITCH И СТРОКА ОШИБКИ В ЭТО ЧИСЛО НЕ ВХОДЯТ — они бывают не
/// всегда и приходят отдельными слагаемыми [checksHeightBudget]
/// ([blockingNoticeHeight] / [errorLineHeight]).
///
/// ⚠️ ИМЕНОВАННАЯ КОНСТАНТА, А НЕ ЛИТЕРАЛ В УМОЛЧАНИИ — НАМЕРЕННО: это
/// главный рычаг размера значков сервисов (каждые 40 px резерва — около 3 px
/// значка на окне 980×800), и менять его должно быть можно одной строкой.
const double kChecksReserveBelow = 166;

/// Сколько висит заметка движка, прежде чем уехать вниз сама.
///
/// ⚠️ ТОП-УРОВНЕВАЯ ФУНКЦИЯ, А НЕ ЛИТЕРАЛ ВНУТРИ `_showEngineNotices` —
/// иначе таймаут в 1 минуту для мёртвого правила приложения (решение
/// владельца) нечем проверить без подъёма всего `HomeScreen` с `Provider`.
@visibleForTesting
Duration engineNoticeDuration(EngineNoticeKind kind, {required bool isProblem}) {
  switch (kind) {
    case EngineNoticeKind.deadAppRule:
      // Решение владельца: минута, а не общие 6/10 секунд — правило касается
      // защиты конкретной программы, отмахнуться от него в спешке хуже, чем
      // от обычной заметки.
      return const Duration(minutes: 1);
    case EngineNoticeKind.exitDown:
      // Правила, привязанные к этому серверу, сейчас не работают, и решать
      // человеку. Красной ошибкой это не является: основной туннель и
      // остальные выходы живы — проверено живым прогоном в VM 02.09.2026.
      return const Duration(seconds: 20);
    case EngineNoticeKind.staleScheduledTask:
      // Требует прочитать и решить («Исправить» или нет) — обычных 6 секунд
      // для этого мало, а красной ошибкой (10 с) это не является.
      return const Duration(seconds: 15);
    default:
      return Duration(seconds: isProblem ? 10 : 6);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // #5 — проверка активных помех на старте (один раз).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Замер «до» — на старте приложения, пока VPN выключен. Это половина
      // сравнения у кнопки: без него видно только «сейчас работает», но не
      // видно, VPN ли это сделал. Второй замер снимется сам при подъёме
      // туннеля (`ServiceChecksColumn`), и рядом встанут два кружка.
      //
      // ⚠️ Только при выключенном VPN: на живом туннеле проба ушла бы через
      // него и записалась в графу «без VPN» — сравнение стало бы ложью.
      // Приложение умеет подхватывать уже поднятое соединение, так что
      // «на старте» и «без VPN» — не одно и то же.
      final state = context.read<AppState>();
      // Состав — из настроек: пусто (проверки выключены или не выбрано ни
      // одного сервиса) означает, что и замера «до» делать не нужно.
      final checks = ServiceChecks.selected(
          context.read<SettingsController>().settings);
      if (!state.status.isConnected) {
        unawaited(
            context.read<ServiceCheckController>().autoBaseline(checks));
      }

      final found = await InterferenceScanner.scan();
      if (found.isNotEmpty && mounted) {
        await scanInterferenceDialog(context);
      }
      await _checkAppUpdate();
    });
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  /// Обновление приложения: только сообщаем и открываем страницу загрузки.
  /// Молча ничего не качаем и не запускаем — см. комментарий в [AppUpdate].
  Future<void> _checkAppUpdate() async {
    final settings = context.read<SettingsController>().settings;
    if (!settings.appUpdateCheck) return;
    final result = await AppUpdate.check();
    // ⚠️ АВТОПРОВЕРКА МОЛЧИТ ОБО ВСЁМ, КРОМЕ НАЙДЕННОГО ОБНОВЛЕНИЯ, и это не
    // то же самое, что прежнее «не отличаем отказ от отсутствия». Отказ теперь
    // ОТЛИЧИМ (`UpdateCheckState.failed`) — мы просто не дёргаем им человека на
    // старте: он этой проверки не просил. Ручная кнопка в настройках причину
    // показывает, потому что там её спросили.
    final release = result.release;
    if (!result.isAvailable || release == null || !mounted) return;
    AppLog.i('Доступна версия ${release.version} (у вас ${AppInfo.version})');
    final l = AppLocalizations.of(context);
    final notes = release.notes ?? '';
    final settingsCtrl = context.read<SettingsController>();
    final url = release.downloadUrl ?? '';

    // ⚠️ ОПИСАНИЕ РЕЛИЗА — В ОКНО, А НЕ В ТОСТ.
    //
    // Раньше здесь стояло `AppToast.show(..., 'Доступна версия X — ' + notes)`,
    // а `notes` — это тело релиза с GitHub, то есть весь раздел changelog:
    // тысячи символов сырого markdown. На телефоне владельца (снимок
    // 19.08.2026) оно заняло весь экран стеной со звёздочками и дефисами, без
    // кнопки закрытия и без возможности отказаться от показа. Сообщение,
    // которое нельзя ни прочитать, ни убрать, хуже отсутствующего.
    //
    // Человек, попросивший «больше не показывать», гасит ОКНО, а не проверку
    // обновлений: иначе он тихо остался бы без новых версий, о чём не просил.
    if (settings.appUpdateNotesHidden) {
      // Окно скрыто — но сообщить о новой версии всё равно надо, коротко.
      AppToast.show(
        context,
        l.homeUpdateAvailable(release.version),
        kind: ToastKind.info,
        actionLabel: url.isEmpty ? null : l.homeDownload,
        onAction: url.isEmpty ? null : () => UrlOpener.open(url),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => UpdateNotesDialog(
        version: release.version,
        notes: notes,
        onDownload: url.isEmpty ? null : () => UrlOpener.open(url),
        onNeverShow: () => unawaited(settingsCtrl
            .update((c) => c.copyWith(appUpdateNotesHidden: true))),
      ),
    );
  }

  // Что уже показали, чтобы один и тот же тост не всплывал на каждой перерисовке.
  String? _shownError;
  DateTime? _shownSyncAt;
  String? _shownRestart;

  /// Временные сообщения — тостами поверх интерфейса (#2.2).
  /// Показать ошибку и, если мешает чужой VPN, дать кнопку закрыть ЕГО.
  ///
  /// Раньше сообщение называло адаптер («wintun»), а что с этим делать —
  /// пользователь догадывался сам. Ищем именно программу; не опознали —
  /// показываем обычную ошибку, потому что предложить закрыть НЕ ТО приложение
  /// хуже, чем не предложить ничего.
  Future<void> _showError(BuildContext context, String err) async {
    final l = AppLocalizations.of(context);
    final conflict = await InterferenceScanner.activeForeignTunnel();
    if (!mounted) return;
    if (conflict == null) {
      AppToast.show(context, err, kind: ToastKind.error);
      return;
    }
    final app = conflict.appName!;
    AppToast.show(
      context,
      '$err\n\n${l.errorVpnConflictApp(app)}',
      kind: ToastKind.error,
      // Дольше обычного: пользователю нужно успеть прочитать и нажать.
      duration: const Duration(seconds: 20),
      actionLabel: l.errorCloseApp(app),
      onAction: () async {
        final ok = await InterferenceScanner.kill(conflict.pid!);
        if (!context.mounted) return;
        AppToast.show(
          context,
          ok ? l.toastAppClosed(app) : l.toastAppCloseFailed(app),
          kind: ok ? ToastKind.success : ToastKind.error,
        );
      },
    );
  }

  /// Второй автозамер — по живому туннелю, сразу после подключения.
  ///
  /// ⚠️ Живёт здесь, а не в колонке проверок. Колонок ДВЕ (слева и справа от
  /// кнопки), у каждой своя половина сервисов, и запуск изнутри означал бы, что
  /// первая колонка займёт «эпоху», а вторая молча пропустит свои три сервиса —
  /// ровно это и происходило: правые кружки оставались серыми. Экран один,
  /// значит и прогон один, сразу по всем шести.
  ///
  /// [services] — состав из настроек (`ServiceChecks.selected`). Пусто =
  /// проверок при подключении нет вовсе; отметку «подъём отработан» пустой
  /// набор не тратит (см. `ServiceCheckController.autoCheckAll`).
  void _autoCheckServices(
      BuildContext context, AppState state, List<ProbeService> services) {
    final ctrl = context.read<ServiceCheckController>();
    // ⚠️ ПРИЗНАК — ФАКТ ПОДЪЁМА ТУННЕЛЯ, А НЕ ВЫБРАННЫЙ СЕРВЕР.
    //
    // Здесь стоял ключ выбранного сервера, и клик по другой строке списка стирал
    // готовые вердикты и гонял шесть проб заново. Причём через ТОТ ЖЕ канал:
    // `AppState.selectServer` живой туннель не трогает, он лишь просит
    // переподключиться. Перепроверять нечего — канал не менялся.
    final connected = state.status.isConnected;
    final port = connected ? state.httpProxyPort : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Смену состояния канала контроллер вычисляет сам, повторы отсекает молча.
      ctrl.setTunnelUp(connected);
      if (!connected) return;
      unawaited(ctrl.autoCheckAll(port, services));
    });
  }

  void _showTransientMessages(
      BuildContext context, AppState state, AppSettings settings) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);

      // Распознанные ошибки переводятся по коду; динамические (текст
      // исключения от сети или ядра) показываются как есть.
      final code = state.errorCode;
      final err = code != null ? appErrorText(l, code) : state.error;
      if (err != null && err != _shownError) {
        _shownError = err;
        state.clearError();
        _showError(context, err);
        return;
      }
      if (err == null) _shownError = null;

      final sync = state.lastSync;
      if (sync != null && sync.at != _shownSyncAt) {
        _shownSyncAt = sync.at;
        // Состав изменений раскрывается по клику — с флагами стран.
        AppToast.show(
          context,
          l.homeSubscriptionUpdated(syncSummary(l, sync)),
          kind: sync.hasChanges ? ToastKind.success : ToastKind.info,
          details: [
            for (final name in sync.added)
              ToastDetail(FlagUtil.strip(name),
                  added: true, leading: FlagCell(name, width: 20, height: 14)),
            for (final name in sync.removed)
              ToastDetail(FlagUtil.strip(name),
                  added: false, leading: FlagCell(name, width: 20, height: 14)),
          ],
        );
        return;
      }

      // #13 — смена сервера/настройки при живом VPN применится только после
      // переподключения: предлагаем сделать это одной кнопкой.
      final restart = state.pendingRestart;
      if (restart != null && restart != _shownRestart) {
        _shownRestart = restart;
        AppToast.show(
          context,
          restart,
          kind: ToastKind.warning,
          actionLabel: l.homeReconnect,
          onAction: () => state.reconnect(settings),
        );
      }
      if (restart == null) _shownRestart = null;
    });
  }

  // Завершения, о которых уже отчитались (иначе итог всплывал бы каждую перерисовку).
  DateTime? _shownPingDone;
  DateTime? _shownAutoDone;
  DateTime? _shownTunDone;
  DateTime? _shownSpeedDone;

  /// Карточка подбора TUN сейчас показывает НЕЗАВЕРШЁННЫЙ прогресс. Нужно,
  /// чтобы отличить «подбор отменили» (карточку снять) от «итог показан и
  /// досчитывает свои 10 секунд» (карточку не трогать) — снаружи оба выглядят
  /// как «не бежит и нового `finishedAt` нет».
  bool _tunCardLive = false;

  /// Ход пинга и автонастройки — карточками слева снизу: пока идёт, карточка
  /// висит и показывает прогресс; после завершения ещё 10 секунд показывает итог
  /// с убывающей полоской и уезжает вниз.
  /// Заметки движка: обрыв, восстановление, отказ, блокировка.
  ///
  /// ⚠️ ПОКАЗЫВАЕМ НЕ КАЖДУЮ ПОПЫТКУ. Их бывает до восьми подряд, и всплывашка
  /// на каждую раздражает сильнее, чем помогает — человек начинает их
  /// отмахивать не читая, а вместе с ними пропустит и важную. Поэтому событий
  /// ровно три: связь оборвалась, связь восстановилась, восстановить не
  /// удалось. Решение владельца от 08.08.2026.
  ///
  /// Заметку снимаем СРАЗУ после показа: иначе при каждой перерисовке всплывало
  /// бы одно и то же сообщение — на этих граблях уже стояли с итогами пинга.
  void _showEngineNotices(BuildContext context) {
    final state = context.watch<AppState>();
    final notice = state.pendingNotice;
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      state.clearNotice();
      final l = AppLocalizations.of(context);
      final detail = (notice.detail ?? '').trim();

      // ⚠️ ДВА НОВЫХ ВИДА ПОКАЗАНЫ ОТДЕЛЬНОЙ ВЕТКОЙ, А НЕ ЧЕРЕЗ `notice.text`.
      //
      // Заметки движка исторически не локализованы (`notice.text` — готовая
      // русская строка: движок не имеет доступа к `AppLocalizations`). Для
      // НОВОГО текста, который видит человек, интерфейс переводит сам по
      // `kind` — старые виды поведения не трогаем.
      if (notice.kind == EngineNoticeKind.staleScheduledTask) {
        AppToast.show(
          context,
          l.tunAutoFixNoticeText,
          kind: ToastKind.warning,
          duration: engineNoticeDuration(notice.kind, isProblem: notice.isProblem),
          actionLabel: l.tunAutoFixAction,
          onAction: () => _fixStaleScheduledTask(context),
        );
        return;
      }
      if (notice.kind == EngineNoticeKind.deadAppRule) {
        // Путь пришёл в `detail`; имя для текста — то же, что покажет строка
        // правила на экране раздельного туннелирования ([AppRule.name]).
        final appName = detail.isEmpty ? notice.text : AppRule(detail).name;
        AppToast.show(
          context,
          l.splitDeadPathNoticeText(appName),
          kind: ToastKind.warning,
          duration: engineNoticeDuration(notice.kind, isProblem: notice.isProblem),
          actionLabel: l.splitDeadPathNoticeAction,
          // «К ЭТОМУ ПРАВИЛУ», А НЕ ПРОСТО НА ЭКРАН — см. `openRulePath`.
          onAction: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SplitTunnelScreen(openRulePath: detail))),
        );
        return;
      }

      AppToast.show(
        context,
        detail.isEmpty ? notice.text : '${notice.text} · $detail',
        kind: notice.isProblem ? ToastKind.error : ToastKind.info,
        duration: engineNoticeDuration(notice.kind, isProblem: notice.isProblem),
        // У блокировки — путь к правилу: сообщение без «а где это менять»
        // заставляет искать настройку самому.
        actionLabel: notice.kind == EngineNoticeKind.blocked
            ? 'Правила'
            : null,
        onAction: notice.kind == EngineNoticeKind.blocked
            ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SplitTunnelScreen()))
            : null,
      );
    });
  }

  /// Действие кнопки заметки [EngineNoticeKind.staleScheduledTask]: одно окно
  /// UAC пересоздаёт задачу Планировщика — дальше подключения идут без него.
  ///
  /// ⚠️ ТОТ ЖЕ ВЫЗОВ, ЧТО И В НАСТРОЙКАХ («TUN и маршрутизация» → «Настроить»,
  /// см. `tun_settings_screen.dart`). Второго способа починить задачу в
  /// проекте нет и не должно появиться.
  Future<void> _fixStaleScheduledTask(BuildContext context) async {
    AppLog.i('Пользователь согласился пересоздать задачу Планировщика '
        'по предложению из уведомления');
    final ok = await platform.privileges.configure();
    AppLog.i(ok
        ? 'Задача Планировщика пересоздана — дальше подключения пойдут без UAC'
        : 'Пересоздать задачу Планировщика не удалось '
            '(UAC отклонён или запрещено политикой)');
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    AppToast.show(context, ok ? l.tunTaskDone : l.tunTaskFailed,
        kind: ok ? ToastKind.success : ToastKind.error);
  }

  void _showProgressToasts(BuildContext context) {
    final probe = context.watch<ProbeController>();
    final auto = context.watch<AutoConfigController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);

      // Скорость, которую автонастройка уже замерила (три лучших кандидата),
      // показываем в строке сервера сразу и повторно не меряем — за неё уже
      // заплачено трафиком подписки. Метод молчит, когда ничего не изменилось,
      // иначе получился бы цикл «notify → build → notify».
      probe.adoptSpeeds({
        for (final r in auto.found)
          if (r.mbps != null && r.mbps! > 0)
            r.server.key: ServerSpeed(
              mbps: r.mbps!,
              measuredAt: r.measuredAt,
              fromAutoConfig: true,
            ),
      });

      if (probe.running) {
        _shownPingDone = null;
        final total = probe.total;
        AppToast.progress(
          context,
          id: 'ping',
          message: l.homePingProgress(probe.done, total),
          value: total > 0 ? probe.done / total : null,
        );
      } else if (probe.finishedAt != null &&
          probe.finishedAt != _shownPingDone &&
          probe.lastSummary != null) {
        _shownPingDone = probe.finishedAt;
        AppToast.progress(context,
            id: 'ping',
            message: probe.lastSummary!,
            finished: true,
            kind: ToastKind.success);
      }

      // Замер скорости — своя карточка: он идёт десятками секунд на сервер, и
      // без хода прогона экран выглядит зависшим.
      if (probe.speedRunning) {
        _shownSpeedDone = null;
        final total = probe.speedTotal;
        AppToast.progress(
          context,
          id: 'speed',
          message: l.speedProgress(probe.speedDone, total),
          value: total > 0 ? probe.speedDone / total : null,
        );
      } else if (probe.speedWaitsForPing) {
        // ⚠️ ОЖИДАНИЕ ТОЖЕ НАДО ПОКАЗАТЬ. Ручной замер, пришедший во время
        // прогона пинга, честно ждёт своей очереди (харнесс один на процесс) —
        // но без карточки это неотличимо от прежнего молчаливого отказа:
        // человек нажал пункт меню и по экрану не понимает, принято ли нажатие.
        // Полоски нет намеренно: сколько ждать, мы не знаем.
        _shownSpeedDone = null;
        AppToast.progress(context, id: 'speed', message: l.speedWaitsForPing);
      } else if (probe.speedFinishedAt != null &&
          probe.speedFinishedAt != _shownSpeedDone &&
          probe.speedSummary != null) {
        _shownSpeedDone = probe.speedFinishedAt;
        AppToast.progress(context,
            id: 'speed',
            message: probe.speedSummary!,
            finished: true,
            kind: ToastKind.success);
      }

      final p = auto.progress;
      if (auto.running) {
        _shownAutoDone = null;
        final total = p?.total ?? 0;
        AppToast.progress(
          context,
          id: 'autoconfig',
          message: p == null
              ? l.homeAutoConfigStarting
              : '${l.homeAutoConfigProgress(p.index + 1, total, p.candidateName)}'
                  ' · ${outboundVariantLabel(l, p.variant)}',
          value: total > 0 ? (p!.index + 1) / total : null,
          // Закреплённая карточка: держится у самого низа, нажатие открывает
          // саму автонастройку, а свернуть её можно кнопкой. Ход подбора идёт
          // минутами — до этого посмотреть, что там происходит, можно было
          // только вспомнив, где лежит кнопка.
          pinned: true,
          onTap: () => _openAutoConfig(context),
          tapTooltip: l.toastOpenAutoConfig,
        );
      } else if (auto.finishedAt != null &&
          auto.finishedAt != _shownAutoDone &&
          auto.lastSummary != null) {
        _shownAutoDone = auto.finishedAt;
        AppToast.progress(context,
            id: 'autoconfig',
            message: auto.lastSummary!,
            finished: true,
            pinned: true,
            onTap: () => _openAutoConfig(context),
            tapTooltip: l.toastOpenAutoConfig,
            kind: auto.found.isEmpty ? ToastKind.warning : ToastKind.success);
      }

      // #8 — перебор стека/MTU TUN: пока идёт — прогресс-тост, по завершении —
      // итог (успех/неудача), а не только строка статуса под кнопкой.
      final state = context.read<AppState>();
      switch (tunToastStep(
        running: state.tunAutotuning,
        finishedAt: state.tunAutotuneFinishedAt,
        shownFinishedAt: _shownTunDone,
        cardLive: _tunCardLive,
      )) {
        case TunToastStep.progress:
          _shownTunDone = null;
          _tunCardLive = true;
          AppToast.progress(
            context,
            id: 'tun-autotune',
            message: state.tunAutotuneMessage ?? l.homeTunAutotuneProgress,
          );
        case TunToastStep.summary:
          _shownTunDone = state.tunAutotuneFinishedAt;
          _tunCardLive = false;
          AppToast.progress(context,
              id: 'tun-autotune',
              message: state.tunAutotuneSucceeded
                  ? l.homeTunAutotuneDone
                  : l.homeTunAutotuneFailed,
              finished: true,
              kind: state.tunAutotuneSucceeded
                  ? ToastKind.success
                  : ToastKind.warning);
        case TunToastStep.dismiss:
          _tunCardLive = false;
          AppToast.dismissProgress('tun-autotune');
        case TunToastStep.none:
          break;
      }
    });
  }

  /// Открыть автонастройку — ровно один экземпляр экрана. Карточка прогресса
  /// живёт в Overlay навигатора и обновляется поверх уже открытых экранов,
  /// поэтому «просто push» на каждое нажатие клал бы на стек копию за копией.
  void _openAutoConfig(BuildContext context) => unawaited(AppToast.openOnce(
        context,
        key: 'autoconfig',
        builder: (_) => const AutoConfigScreen(),
      ));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final status = state.status;
    final settings = context.watch<SettingsController>().settings;
    // #6 — пинг применяет сохранённую вариацию сервера (fragment/fingerprint),
    // иначе серверы, работающие только с обходом, показывают «n/a».
    // Правка настройки, запекаемой в конфиг ядра, должна честно сказать, что
    // применится только после переподключения. Без этого правка правил при
    // живом соединении проходила молча, и пользователь был уверен, что она
    // работает. Ставим здесь: тут доступны оба контроллера.
    context.read<SettingsController>().onRequiresReconnect = (before, after) =>
        state.notePendingRestart(l.homeSettingsNeedReconnect,
            // На экране — общая фраза, в журнале — имена изменённых настроек:
            // без них перезапуск туннеля неотличим от обрыва связи.
            fields: before.reconnectReasons(after));

    final probe = context.read<ProbeController>();
    probe.variantFor = state.variantFor;
    // Там, где отдельный харнесс не поднять (Android — VpnService один),
    // проверить hysteria2 и профили «Авто» можно только по ЖИВОМУ каналу:
    // у них нет осмысленного TCP-адреса, а без второй фазы они оставались
    // непроверенными навсегда. Честно это работает ровно для подключённого
    // сервера — его и отдаём.
    probe.liveProxyPort =
        () => state.status.isConnected ? state.httpProxyPort : 0;
    // ⚠️ ПОДНЯТЫЙ сервер, а не выбранный в списке: клик по другому серверу
    // живой туннель не трогает, и вердикт живого канала уехал бы чужому.
    probe.activeServerKey = () => state.connectedServerKey;
    // Поднятый TUN затягивает сокеты приложения — TCP-цифры фазы 1 с этого
    // момента про локальный туннель, а не про серверы. Пометка идёт по самому
    // ФАКТУ захвата (в том числе пока канал ещё поднимается)…
    probe.captureActive = () => state.captureCoreApi != null;
    // …а честный замер ядром — только при «Подключено»: во время подъёма
    // outbound уже слушает, но никуда не доставляет, и тест дал бы ложный
    // провал (та же граница, что у liveProxyPort выше).
    probe.liveCoreDelay = () {
      final api = state.captureCoreApi;
      if (api == null || !state.status.isConnected) return null;
      return ClashDelayProbe(
          port: api.port, secret: api.secret, tag: api.proxyTag);
    };
    // #2.2 — всё временное показываем ПОВЕРХ интерфейса: раньше эти сообщения
    // жили в компоновке и сдвигали большую кнопку Connect.
    _showTransientMessages(context, state, settings);
    _autoCheckServices(context, state, ServiceChecks.selected(settings));
    _showProgressToasts(context);
    _showEngineNotices(context);

    // #1.2 — первый запуск: пока нет ни подписки, ни серверов, показываем экран
    // импорта целиком. Возвращаться некуда, поэтому и кнопки «назад» у него нет.
    if (!state.hasServers && state.subscriptionUrl == null) {
      return const ImportScreen(initialSetup: true);
    }

    // Ctrl+C копирует ключ выбранного сервера. Обёртка снаружи Scaffold, чтобы
    // клавиша работала и над списком серверов, и над панелью подключения.
    return CopyServerKeyShortcut(
        child: Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // Имя из AppInfo, а не литералом: бренд ещё может смениться, и тогда
        // правки не должны расползаться по интерфейсу.
        // ⚠️ Версии здесь НЕТ намеренно (решение владельца): она стоит в
        // заголовке окна и в подсказке значка в трее — см. `TrayWindow`.
        title: const Text(AppInfo.name),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add, size: 20),
            label: Text(l.homeImport),
            onPressed: () => _open(context, const ImportScreen()),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l.homeSettings,
            icon: const Icon(Icons.settings),
            onPressed: () => _open(context, const SettingsScreen()),
          ),
        ],
      ),
      // Ход пинга/автонастройки показывается ТОЛЬКО карточкой слева снизу
      // (AppToast.progress). Верхней плашки больше нет: она двигала интерфейс.
      //
      // Компоновка выбирается по ШИРИНЕ, а не по платформе: узкое окно на
      // Windows получает ту же одноколоночную раскладку, что и телефон, и это
      // правильно — две панели по 380 px там просто не помещаются.
      body: HomeBody(
        status: status,
        settings: settings,
        onOpen: (w) => _open(context, w),
      ),
    ));
  }
}

/// Тело главного экрана: одна колонка на узком окне, две — на широком.
///
/// ⚠️ ОТДЕЛЬНЫЙ ПУБЛИЧНЫЙ ВИДЖЕТ РАДИ СТРАЖЕЙ, и это не украшательство. Пока
/// выбор раскладки жил прямо в `Scaffold.body`, проверить его можно было только
/// подъёмом всего `HomeScreen` — с `AppBar`, проверкой обновлений по сети и
/// автозамером сервисов на первом же кадре. Ровно поэтому переполнение панели
/// в тесном окне не поймал ни один страж: они поднимали публичный
/// `ConnectCenterpiece`, а переполнялась панель. Здесь поднимается то самое
/// место, где кнопка подбора либо есть, либо её нет.
class HomeBody extends StatelessWidget {
  const HomeBody({
    super.key,
    required this.status,
    required this.settings,
    required this.onOpen,
  });

  final VpnStatus status;
  final AppSettings settings;
  final void Function(Widget screen) onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < _twoPaneMinWidth) {
          return ConnectPane(
            status: status,
            settings: settings,
            onOpen: onOpen,
            compact: true,
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ConnectPane(
                status: status,
                settings: settings,
                onOpen: onOpen,
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(width: 380, child: ServerPane(onOpen: onOpen)),
          ],
        );
      },
    );
  }
}

/// Ниже этой ширины список серверов уезжает на отдельный экран: панель в 380 px
/// плюс осмысленная колонка подключения рядом уже не помещаются.
const double _twoPaneMinWidth = 760;

/// Ширина МЕСТА ПОД КНОПКОЙ, с которой колонки проверок помещаются по бокам.
///
/// ⚠️ ОТДЕЛЬНАЯ КОНСТАНТА, А НЕ [_twoPaneMinWidth], И ЭТО СУТЬ ПРАВКИ. Раньше
/// выбор раскладки спрашивал ту, что выше, — а она отвечает на ДРУГОЙ вопрос:
/// «когда список серверов уезжает на отдельный экран», и меряет ширину ОКНА.
/// Здесь же меряется ширина ЛЕВОЙ ПАНЕЛИ, то есть окно МИНУС список (380 px).
/// Из-за подмены бока включались только при окне шире 1140: владелец с окном
/// 964 видел ряды, «хотя место точно есть» — панель у него около 584 px.
///
/// Число не придумано, а ЗАМЕРЕНО (`test/service_checks_sides_width_test.dart`):
/// на 520 px и выше раскладка «по бокам» строится без переполнения, на 360 px
/// (телефон) — нет, и там ряды остаются правильным ответом. Меняя число, гоняйте
/// тот тест: он проверяет ФАКТ раскладки, а не веру в него.
const double _sidesMinWidth = 520;

/// Левая (на узком окне — единственная) колонка главного экрана.
///
/// Публична ради стражей вёрстки: пока она была приватной, переполнение низа
/// панели не мог поймать ни один тест — см. шапку [HomeBody].
class ConnectPane extends StatelessWidget {
  final VpnStatus status;
  final AppSettings settings;
  final void Function(Widget screen) onOpen;

  /// Узкий экран: список серверов уехал на отдельный маршрут, поэтому здесь
  /// появляется строка выбранного сервера, а содержимое становится
  /// прокручиваемым — гарантии минимального размера окна на телефоне нет.
  final bool compact;

  const ConnectPane({
    super.key,
    required this.status,
    required this.settings,
    required this.onOpen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    // Что проверяем при подключении — выбор пользователя (подменю у колонок).
    // Пусто = проверок нет вовсе, и место на главном они не занимают.
    final checks = ServiceChecks.selected(settings);
    return Column(
      children: [
        // Карточка подписки показывается целиком: место под неё даёт увеличенная
        // минимальная высота окна и компактная кнопка Connect (скролл тут мешал).
        const SubscriptionBar(),
        const GeoOfferBanner(),
        const NotificationsOffBanner(),
        if (compact) _SelectedServerBar(onOpen: onOpen),
        Expanded(
          child: Padding(
            // На телефоне 24 dp с каждой стороны — это 13 % ширины экрана,
            // которых не хватает содержимому. На десктопе остаётся 24.
            padding: EdgeInsets.all(context.sg.pagePadding),
            // На широком окне раскладка держится распорками и не прокручивается
            // (минимальный размер окна это гарантирует). На узком гарантии нет:
            // при крупном системном шрифте, в ландшафте или в разделённом
            // экране жёсткая колонка даёт overflow, поэтому там — прокрутка.
            child: _MaybeScroll(
              enabled: compact,
              // ⚠️ ПОТОЛОК ВЫСОТЫ ПРИХОДИТ СВЕРХУ, И БЕЗ НЕГО СЖАТИЕ НЕ
              // РАБОТАЕТ. Дети `Column` получают maxHeight = infinity, а
              // сжатие по высоте (`_estimateScale`) включается только при
              // `c.hasBoundedHeight`. Механизм был написан и подключён — и не
              // срабатывал НИ РАЗУ: при четырнадцати сервисах блок с
              // информацией о подключении уезжал за край окна.
              child: LayoutBuilder(builder: (context, paneBox) {
                // ⚠️ ВРЕЗКИ ПОД ПОТОЛКОМ СЧИТАЮТСЯ ЗДЕСЬ, А НЕ ВНУТРИ БЛОКА.
                // Плашка kill switch и строка ошибки стоят НИЖЕ
                // `ConstrainedBox`, и пока их не было в расчёте, панель с
                // четырнадцатью сервисами и поднятой защитой переполнялась на
                // всех окнах. Ширина и стиль берутся те же, что достанутся
                // самим врезкам, — иначе перенос текста посчитается не так.
                final noticeStyle = DefaultTextStyle.of(context).style;
                final scaler = MediaQuery.textScalerOf(context);
                final blockingText = status.blocking ? status.message ?? '' : null;
                final errorText =
                    status.state == VpnConnectionState.error ? status.message : null;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    if (!compact) const Spacer(),
                    // Плашка активного сервера, кнопка и колонки проверок — одним
                    // виджетом: ровно то, что проверяет страж вёрстки.
                    //
                    // ⚠️ ЛЕГЕНДЫ «СЛЕВА — БЕЗ VPN, СПРАВА — ЧЕРЕЗ VPN» БОЛЬШЕ НЕТ —
                    // решение владельца (08.09.2026): «совсем убрать, оставить
                    // только i». Её строка с отступами стоила 42 px, и на
                    // минимальном окне ровно этих пикселей не хватало низу экрана:
                    // плашка 38 + легенда 42 + кнопка 148 + низ 270 = 498 против
                    // панели 427–447 в VM. ⚠️ 270 — сколько НУЖНО было тогдашней
                    // раскладке (см. [kChecksReserveBelow]); в коде на тот момент
                    // стояло 214, и расходились они молча. Весь её смысл несёт подсказка
                    // «i» (`serviceChecksInfo`), а сама «i» вместе с подменю
                    // переехала в правый край полосы плашки: та держит высоту
                    // всегда, и кнопки собственного ряда не стоят.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: checksHeightBudget(
                              paneHeight: paneBox.maxHeight,
                              // Крупный системный шрифт растит низ панели —
                              // потолок обязан отступить на столько же.
                              textScale: scaler.scale(1),
                              blockingNotice: blockingText == null
                                  ? 0
                                  : blockingNoticeHeight(
                                      paneWidth: paneBox.maxWidth,
                                      style: noticeStyle,
                                      scaler: scaler,
                                      text: blockingText),
                              errorLine: errorText == null
                                  ? 0
                                  : errorLineHeight(
                                      paneWidth: paneBox.maxWidth,
                                      style: noticeStyle,
                                      scaler: scaler,
                                      text: errorText))),
                      child: ConnectCenterpiece(
                        serverName: activeServerName(
                          connected: status.isConnected,
                          connectedKey: state.connectedServerKey,
                          servers: state.servers,
                          // ⚠️ ЗДЕСЬ ИМЯ СЕССИИ, А НЕ ЯРЛЫК КНОПКИ. Кнопка
                          // подбора называется глаголом («Подобрать сервер»), а
                          // плашка отвечает на вопрос «через что идёт трафик» —
                          // глагол в ней читался бы как незавершённое действие.
                          autoLabel: l.homeAutoSession,
                        ),
                        httpPort: status.isConnected ? state.httpProxyPort : 0,
                        services: checks,
                        layout: settings.serviceChecksLayout,
                        // Подменю набора — здесь, у самих проверок (требование
                        // владельца). Видно ВСЕГДА: когда проверки выключены,
                        // включить их больше неоткуда.
                        bannerTrailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InfoTooltip(l.serviceChecksInfo, compact: true),
                            const SizedBox(width: 2),
                            const ServiceChecksMenuButton(),
                          ],
                        ),
                        // «Информация о сервере» — значком в левом краю той же
                        // полосы. Своей строкой под статусом она стоила 48 px, и
                        // ровно их не хватало низу экрана на минимальном окне.
                        bannerLeading: const ServerInfoButton(),
                        // Диаметр передан ЯВНО (то же число, что дал бы умолчание):
                        // раскладки колонок по бокам сжимают ВЕСЬ блок кнопки одним
                        // виджетом (`ServiceChecksSides` → `FittedBox`), но опорный
                        // размер, от которого считается их коэффициент, должен
                        // совпадать с тем, что здесь реально нарисовано.
                        button: ConnectButton(
                            status: status,
                            diameter: context.sg.isShort ? 116 : 148,
                            onTap: () => connectWithConflictCheck(context,
                                state, () => state.toggleConnection(settings))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(vpnStatusLabel(l, status.state),
                        style: Theme.of(context).textTheme.titleMedium),
                    // ⚠️ «ИНФОРМАЦИЯ О СЕРВЕРЕ» УЕХАЛА ОТСЮДА ЗНАЧКОМ В ПОЛОСУ
                    // ПЛАШКИ (`bannerLeading` выше). Своей строкой она стоила
                    // 48 px, а на минимальном окне 980×800 не хватало ровно их.
                    // Экран не потерян — он открывается тем же значком.
                    //
                    // ⚠️ ОБЕ ВРЕЗКИ НИЖЕ — ВНЕ ПОТОЛКА, и их высота уже вычтена
                    // из него выше (`blockingNotice`/`errorLine`). Добавишь
                    // сюда третью, не тронув расчёт, — панель переполнится ровно
                    // на её высоту, и именно в аварии, когда читать важнее всего.
                    if (blockingText != null)
                      KillSwitchNotice(message: blockingText),
                    if (errorText != null) ConnectErrorLine(message: errorText),
                    const SizedBox(height: 20),
                    // ⚠️ `Wrap`, А НЕ `Row`: на узком окне с крупным системным
                    // шрифтом две подписи в строку не влезают, и `Row` дал бы
                    // переполнение вместо переноса.
                    //
                    // ⚠️ «Подобрать сервер» остаётся здесь ТОЛЬКО в узкой
                    // раскладке. На широком окне список серверов виден справа, и
                    // кнопка стоит над ним (`ServerPane`); внизу она была бы
                    // вторым таким же входом в паре сантиметров от первого.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (compact) const AutoPickServerButton(),
                        // Автонастройка стоит на проброс-харнессе. На Android он
                        // ПОЯВИЛСЯ (`LibXray.ping` поднимает свой экземпляр ядра,
                        // не трогая туннель), поэтому кнопка снова на месте. Гейт
                        // оставлен: на платформе без харнесса нажатие показывало бы
                        // сырое «Unsupported operation», а обещать несуществующее
                        // хуже, чем не показывать.
                        if (proxyProbeSupported)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.auto_fix_high),
                            label: Text(l.homeAutoConfig),
                            // Через ту же точку, что и нажатие на карточку
                            // прогресса: один экземпляр экрана на оба пути (и
                            // двойное нажатие по самой кнопке второй копии тоже не
                            // откроет).
                            onPressed: () => AppToast.openOnce(
                              context,
                              key: 'autoconfig',
                              builder: (_) => const AutoConfigScreen(),
                            ),
                          ),
                      ],
                    ),
                    if (!compact)
                      const Spacer()
                    else
                      const SizedBox(height: 24),
                    // Всегда на месте: при отключённом VPN — нули (иначе блок появлялся
                    // рывком и двигал кнопки, а цифры не помещались).
                    TrafficRow(
                      stats:
                          status.isConnected ? state.stats : TrafficStats.zero,
                      sessionUp: state.sessionUplinkBytes,
                      sessionDown: state.sessionDownlinkBytes,
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

/// ⚠️ KILL SWITCH ДЕРЖИТ ТРАФИК — СКАЗАТЬ ЭТО ЗАМЕТНО.
///
/// Пропавший интернет без объяснения выглядит поломкой, и самое естественное
/// действие человека — выключить VPN, то есть ровно то, от чего защита
/// оберегала. Строки статуса мало: она мелкая и теряется среди прочего.
///
/// ⚠️ ОТДЕЛЬНЫЙ ВИДЖЕТ, А НЕ КУСОК `build`, — не ради красоты. Плашка лежит
/// НИЖЕ потолка блока проверок, значит её высота обязана входить в резерв
/// ([blockingNoticeHeight]). Пока и геометрия, и расчёт жили в разных местах,
/// расчёта просто не было: панель с четырнадцатью сервисами и поднятой защитой
/// переполнялась на всех окнах. Числа ниже — единственный их источник, и по ним
/// же считает [blockingNoticeHeight]; страж сверяет расчёт с настоящей высотой.
class KillSwitchNotice extends StatelessWidget {
  const KillSwitchNotice({super.key, required this.message});

  final String message;

  /// Отступ от блока проверок сверху.
  static const double marginTop = 12;

  /// Внутренние поля рамки.
  static const double paddingV = 10;
  static const double paddingH = 12;

  /// Значок щита. В системном шрифте НЕ растёт (`Icon` без `applyTextScaling`),
  /// поэтому строка не бывает ниже него.
  static const double iconSize = 20;

  /// Просвет между значком и текстом.
  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: marginTop),
      padding: const EdgeInsets.symmetric(
          horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.shield_outlined,
            size: iconSize, color: scheme.onErrorContainer),
        const SizedBox(width: gap),
        Expanded(
          child: Text(
            message,
            textDirection: autoTextDirection(message),
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      ]),
    );
  }
}

/// Текст ошибки под строкой статуса.
///
/// ⚠️ ОТДЕЛЬНЫЙ ВИДЖЕТ ПО ТОЙ ЖЕ ПРИЧИНЕ, ЧТО И [KillSwitchNotice]: строка
/// лежит ниже потолка, её высота входит в резерв ([errorLineHeight]), а текст
/// приходит от движка и переносится на вторую строку тем охотнее, чем крупнее
/// системный шрифт. [paddingTop] — единственный источник отступа.
class ConnectErrorLine extends StatelessWidget {
  const ConnectErrorLine({super.key, required this.message});

  final String message;

  /// Отступ сверху — от плашки блокировки либо от строки статуса.
  static const double paddingTop = 8;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: paddingTop),
        child: Text(message,
            textAlign: TextAlign.center,
            // Статус/ошибка: направление по содержимому — локализованный текст
            // читается верно, вложенные технические фрагменты (имена
            // exe/серверов) — по bidi.
            textDirection: autoTextDirection(message),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

/// Оборачивает содержимое в прокрутку только когда это нужно.
///
/// На широком окне колонка держится `Spacer`-ами и обязана занимать всю высоту;
/// обернув её в скролл безусловно, мы сломали бы эту раскладку.
class _MaybeScroll extends StatelessWidget {
  final bool enabled;
  final Widget child;
  const _MaybeScroll({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) => enabled
      ? SingleChildScrollView(child: child)
      : child;
}

/// Строка выбранного сервера — вход в список на узком экране.
///
/// На широком окне список всегда виден справа, здесь его нет, и без этой
/// строки сменить сервер было бы негде.
class _SelectedServerBar extends StatelessWidget {
  final void Function(Widget screen) onOpen;
  const _SelectedServerBar({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final server = state.selectedServer;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onOpen(const ServersScreen()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              if (server != null)
                FlagCell(server.remark, auto: server.isPanelProfile, width: 28, height: 20)
              else
                const Icon(Icons.dns_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      server == null
                          ? l.homeServersCount(state.servers.length)
                          : FlagUtil.strip(server.displayName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Имя сервера — технический текст: в ar/fa не зеркалим.
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(l.homeServersCount(state.servers.length),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (server != null)
                PingChip(result: context.watch<ProbeController>().resultFor(server)),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Высота строки сервера вместе с разделителем.
///
/// ⚠️ ЭТО ОЦЕНКА, А НЕ ИЗМЕРЕНИЕ, и другого способа тут нет. `ensureVisible`
/// целится в виджет по контексту, а у НЕПОСТРОЕННОЙ строки ленивого списка
/// контекста не существует — метод молча выходит, ничего не сделав. В настройках
/// эту же задачу решили постройкой всего списка целиком, но серверов бывает
/// сотня с лишним, и так делать нельзя. Поэтому смещение считается по номеру
/// строки, а `clamp` по `maxScrollExtent` не даёт промахнуться за конец списка.
const double kServerRowExtent = 73.0;

/// Повод промотать список серверов к выбранному.
enum ServerScrollTrigger {
  none,

  /// Первый показ списка после запуска приложения.
  ///
  /// Просьба владельца: «при запуске приложения если не видно мотай до него в
  /// списке серверов чтобы показать юзеру какой сервер был запомнен». Раньше
  /// список всегда открывался на первой строке, и запомненный сервер где-нибудь
  /// на 80-й позиции выглядел как «ничего не выбрано».
  startup,

  /// Момент подключения: после нажатия «Подключить» видно, что именно поднялось.
  connected,
}

/// Нужно ли мотать список на ЭТОМ такте перерисовки.
///
/// Вынесено отдельной функцией (как `tunToastStep` выше), чтобы решение
/// проверялось тестом, а не поднятием всего главного экрана с движком.
///
/// [hasServers] — список уже пришёл: серверы читаются с диска асинхронно, и на
/// первых кадрах прокручивать нечего. [startupDone] — стартовую прокрутку уже
/// делали, второй раз она бы дёргала список под рукой.
ServerScrollTrigger serverScrollTrigger({
  required bool hasServers,
  required bool connected,
  required bool wasConnected,
  required bool startupDone,
}) {
  if (!hasServers) return ServerScrollTrigger.none;
  if (!startupDone) return ServerScrollTrigger.startup;
  // Только ПЕРЕХОД в «Подключено»: статус тикает раз в секунду на счётчиках
  // трафика, и без сравнения с прошлым состоянием список ездил бы постоянно.
  if (connected && !wasConnected) return ServerScrollTrigger.connected;
  return ServerScrollTrigger.none;
}

/// Смещение, на которое надо промотать список, чтобы строка [pos] попала на
/// экран ЦЕЛИКОМ. `null` — строка уже видна, список трогать НЕЛЬЗЯ.
///
/// ⚠️ Проверка видимости здесь не украшение: без неё «прокрутка к выбранному»
/// на первой же строке дёргала бы список, который и так стоит на нужном месте.
double? serverRowScrollTarget({
  required int pos,
  required double rowExtent,
  required double pixels,
  required double viewport,
  required double maxScrollExtent,
}) {
  if (pos < 0) return null;
  final top = pos * rowExtent;
  if (top >= pixels && top + rowExtent <= pixels + viewport) return null;
  final target = top.clamp(0.0, maxScrollExtent);
  // Список уже упёрт в конец (или в начало) — мотать некуда.
  if ((target - pixels).abs() < 0.5) return null;
  return target;
}

/// Промотать [c] к строке [pos], если она не видна. Возвращает `true`, если
/// прокрутка реально понадобилась.
///
/// [onlyIfUntouched] — не вмешиваться, когда пользователь листает список сам
/// или уже увёл его от начала: стартовая прокрутка не должна выдёргивать список
/// из-под пальца.
bool scrollListToRow(
  ScrollController c, {
  required int pos,
  double rowExtent = kServerRowExtent,
  bool onlyIfUntouched = false,
  Duration duration = const Duration(milliseconds: 400),
}) {
  if (!c.hasClients) return false;
  final p = c.position;
  if (onlyIfUntouched && (p.isScrollingNotifier.value || p.pixels > 0)) {
    return false;
  }
  final target = serverRowScrollTarget(
    pos: pos,
    rowExtent: rowExtent,
    pixels: p.pixels,
    viewport: p.viewportDimension,
    maxScrollExtent: p.maxScrollExtent,
  );
  if (target == null) return false;
  c.animateTo(target, duration: duration, curve: Curves.easeOut);
  return true;
}

/// Правая панель широкого окна: список серверов с поиском и кнопкой подбора.
///
/// Публична по той же причине, что и [ConnectPane], — см. шапку [HomeBody].
class ServerPane extends StatefulWidget {
  final void Function(Widget screen) onOpen;
  const ServerPane({super.key, required this.onOpen});

  @override
  State<ServerPane> createState() => _ServerPaneState();
}

class _ServerPaneState extends State<ServerPane> {
  String _query = '';

  /// Прокрутка к активному серверу: при запуске приложения и при подключении.
  ///
  /// В списке из сотни строк выбранный сервер почти всегда за пределами экрана:
  /// после запуска непонятно, какой сервер запомнился, а после «Подключить» —
  /// что именно поднялось. Листаем к нему сами — но только в эти два момента,
  /// иначе список дёргался бы под рукой у пользователя, который его листает.
  final _listCtrl = ScrollController();
  bool _wasConnected = false;
  bool _startupScrolled = false;

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  /// Ключ ПЕРВОЙ строки списка — по нему меряется настоящая высота строки.
  ///
  /// ⚠️ Именно первой, и ключ никуда не переезжает: GlobalKey на «выбранной»
  /// строке кочевал бы по списку при каждом выборе, а это верный способ
  /// получить «Duplicate GlobalKey» на ровном месте. Первая строка построена
  /// всегда, пока список стоит в начале, — то есть ровно в момент стартовой
  /// прокрутки, когда точность и нужна.
  final _firstRowKey = GlobalKey();
  double? _measuredRowExtent;

  /// Высота строки: измеренная, если получилось, иначе оценка.
  double _rowExtent() {
    final box = _firstRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.height > 0) {
      // +1 — разделитель между строками (`Divider(height: 1)`).
      _measuredRowExtent = box.size.height + 1;
    }
    return _measuredRowExtent ?? kServerRowExtent;
  }

  void _scrollToSelected(List<int> shown, int selected,
      {required bool onlyIfUntouched}) {
    scrollListToRow(_listCtrl,
        pos: shown.indexOf(selected),
        rowExtent: _rowExtent(),
        onlyIfUntouched: onlyIfUntouched);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final probe = context.watch<ProbeController>();
    final settings = context.read<SettingsController>().settings;
    final servers = state.servers;
    // Индексы исходного списка: выбор сервера идёт по индексу в AppState.servers.
    final shown = ServerSearch.matchIndices(servers, _query);

    // Запуск приложения и момент подключения — два случая, когда листать
    // уместно. ⚠️ Прокрутку назначаем на ПОСЛЕ кадра: до него у списка нет
    // ни клиентов у контроллера, ни высоты области просмотра.
    final connected = state.status.isConnected;
    final trigger = serverScrollTrigger(
      hasServers: servers.isNotEmpty,
      connected: connected,
      wasConnected: _wasConnected,
      startupDone: _startupScrolled,
    );
    if (trigger != ServerScrollTrigger.none) {
      final startup = trigger == ServerScrollTrigger.startup;
      if (startup) _startupScrolled = true;
      final sel = state.selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Стартовая прокрутка уступает пользователю: если он уже листает или
        // увёл список сам (серверы приходят с диска не мгновенно), не лезем.
        if (mounted) _scrollToSelected(shown, sel, onlyIfUntouched: startup);
      });
    }
    _wasConnected = connected;

    // Один гейт на обе точки, где с этого экрана начинается пинг: кнопку в
    // шапке списка и подсказку к ней. Считается один раз — два вызова
    // разошлись бы на первой же правке условия.
    final pingGate = PingGate.of(probe, hasTargets: shown.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (servers.isEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Onboarding(onOpen: widget.onOpen),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                    _query.isEmpty
                        ? l.homeServersCount(servers.length)
                        : l.homeFoundCount(shown.length, servers.length),
                    // ⚠️ ОДНА СТРОКА С МНОГОТОЧИЕМ. При крупном системном
                    // шрифте соседи съедали всю ширину, `Expanded` получал
                    // ноль, и счётчик разворачивался в десять строк по букве —
                    // шапка списка становилась высотой 260 px.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              // ⚠️ ЧЕРЕЗ ОБЩИЙ ГЕЙТ, А НЕ СВОИМ УСЛОВИЕМ. Здесь стояло
              // `probe.running || probe.speedRunning || shown.isEmpty`, а
              // исполнитель отказывает ещё и во время автопрогона проверки
              // сервисов — они делят порт живого ядра. Кнопка при этом
              // выглядела совершенно живой: нажатие не делало ничего и ничего
              // не объясняло. Это самая заметная точка входа из четырёх, и
              // расхождение здесь стоило дороже всего.
              // ⚠️ `Flexible` — ПРАВО УЖАТЬСЯ, А НЕ УКРАШЕНИЕ. Подпись кнопки
              // не резиновая: при системном шрифте ×1,3 три соседа в этой
              // строке не помещались в панель 380 px, и она переполнялась на
              // 4,7 px — жёлто-чёрные полосы у человека, увеличившего шрифт,
              // чтобы читать.
              Flexible(
                child: Tooltip(
                  message: pingGate.label(
                      l, _query.isEmpty ? l.homePingServers : l.homePingFound,
                      noTargets: servers.isEmpty
                          ? l.serversEmpty
                          : l.serversNothingFound),
                  child: TextButton.icon(
                    icon: probe.running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check, size: 18),
                    // Пингуем то, что видно: при поиске — только найденное.
                    label: Text(
                        _query.isEmpty ? l.homePingServers : l.homePingFound,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onPressed: pingGate.allowed
                        ? () => probe.pingAll(
                            [for (final i in shown) servers[i]], settings)
                        : null,
                  ),
                ),
              ),
              // Замер скорости — ИКОНКОЙ, а не второй текстовой кнопкой: панель
              // шириной 380 px, и две подписи рядом с «!» уже не помещаются.
              IconButton(
                tooltip: l.speedRunTooltip,
                visualDensity: VisualDensity.compact,
                icon: probe.speedRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.speed, size: 20),
                onPressed: probe.running || probe.speedRunning || shown.isEmpty
                    ? null
                    // Тот же список, что и у пинга: при активном поиске меряем
                    // только найденное — иначе кнопка тратила бы трафик на то,
                    // чего человек сейчас не видит.
                    : () => startSpeedRun(context, probe,
                        [for (final i in shown) servers[i]], settings),
              ),
              // #4 — видимая «!»: понятно, что у пинга есть подсказка (что значат
              // цвета плашек). Текст выделяемый (см. InfoTooltip).
              InfoTooltip(l.pingLegendInfo, title: l.sectionPing),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: ServerSearchField(
              value: _query,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // ⚠️ КНОПКА ЗАКРЕПЛЕНА НАД СПИСКОМ, А НЕ ЛЕЖИТ В НЁМ ПЕРВОЙ СТРОКОЙ.
          // Она стоит ВНЕ `Expanded` ниже, поэтому список прокручивается под
          // ней, а сама она остаётся на месте: у владельца сотня серверов, и
          // уехавшая наверх кнопка означала бы «её нет».
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 12, 8),
            child: AutoPickServerButton(wide: true),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(l.homeNothingFound))
                : ListView.separated(
                    controller: _listCtrl,
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final idx = shown[i];
                      final tile = ServerTile(
                        server: servers[idx],
                        selected: idx == state.selectedIndex,
                        onTap: () => state.selectServer(idx),
                      );
                      // Первая строка — линейка для прокрутки по номеру строки
                      // (см. `_rowExtent`). Обёртка ничего не рисует и на
                      // раскладку не влияет.
                      return i == 0
                          ? KeyedSubtree(key: _firstRowKey, child: tile)
                          : tile;
                    },
                  ),
          ),
        ],
      ],
    );
  }
}

/// Имя сервера, ЧЕРЕЗ КОТОРЫЙ РЕАЛЬНО ИДЁТ ТРАФИК. `null` — VPN выключен.
///
/// ⚠️ Спрашиваем [AppState.connectedServerKey], а не выбранную строку списка.
/// Клик по другому серверу живой туннель не трогает (появляется лишь плашка
/// «переподключитесь»), поэтому подпись над кнопкой показывала сервер, через
/// который не прошло ни байта, — при живом соединении с совсем другим.
///
/// Ключ, которому не нашлось сервера, и пустой ключ дают [autoLabel]: пустой —
/// это режим «Авто (лучший)», где сессию держит балансировщик, а не отдельный
/// узел. ⚠️ Сам ключ показывать НЕЛЬЗЯ ни при каких обстоятельствах — это
/// share-ссылка с логином сервера внутри.
@visibleForTesting
String? activeServerName({
  required bool connected,
  required String? connectedKey,
  required List<VpnServer> servers,
  required String autoLabel,
}) {
  if (!connected) return null;
  for (final s in servers) {
    if (s.key == connectedKey) return s.displayName;
  }
  return autoLabel;
}

/// Центр главного экрана: плашка активного сервера, кнопка Connect и колонки
/// проверок сервисов по бокам.
///
/// ⚠️ ОТДЕЛЬНЫЙ ВИДЖЕТ РАДИ СТРАЖА. Плашку правят третьим заходом, и оба
/// прошлых раза её проверяли на КОПИИ раскладки — руками собранной в тесте
/// строке с заглушкой вместо колонок. Копия расходится с оригиналом молча:
/// тест оставался зелёным, а владелец второй раз писал «ты так и не исправил».
/// Теперь страж поднимает ЭТОТ виджет, то есть ровно то, что видно на экране.
class ConnectCenterpiece extends StatelessWidget {
  const ConnectCenterpiece({
    super.key,
    required this.serverName,
    required this.httpPort,
    required this.button,
    this.services = ServiceChecks.services,
    this.layout = ServiceChecksLayout.rows,
    this.bannerTrailing,
    this.bannerLeading,
  });

  /// Что стоит в ЛЕВОМ краю полосы плашки — на экране это «Информация о
  /// сервере». `null` — место под кнопку всё равно держится (см.
  /// [ActiveServerBanner.leading]).
  final Widget? bannerLeading;

  /// Что стоит в правом краю полосы плашки — на экране это «i» с подсказкой
  /// и кнопка подменю проверок. `null` — полоса без хвоста (стражи вёрстки).
  ///
  /// ⚠️ Умолчание `null` означает, что забытый параметр компилятор не поймает;
  /// страж по исходнику — в `active_server_banner_test`.
  final Widget? bannerTrailing;

  /// Имя активного сервера (см. [activeServerName]); `null` — плашка пустая.
  final String? serverName;

  /// http-порт живого ядра для проверок; 0 — VPN выключен.
  final int httpPort;

  /// Какие сервисы показывать у кнопки. Пусто — проверок нет вовсе, и места
  /// они не занимают (проверки выключены в подменю).
  ///
  /// Умолчание — прежняя зашитая шестёрка: стражам вёрстки настройки не нужны,
  /// им нужна раскладка. Экран передаёт сюда `ServiceChecks.selected(settings)`.
  final List<ProbeService> services;

  /// Кнопка приходит снаружи: ей нужен `AppState`, а стражу вёрстки — нет.
  final Widget button;

  /// Раскладка проверок относительно кнопки (решение владельца 27.08.2026).
  ///
  /// ⚠️ УМОЛЧАНИЕ — `rows`, А НЕ `adaptive` (настройка по умолчанию для
  /// пользователя, см. [ServiceChecksLayout]). Действующий страж вёрстки
  /// (`connect_centerpiece_layout_test.dart`) поднимает виджет БЕЗ этого
  /// параметра и ждёт ряды на всех одиннадцати разрешениях, включая широкое
  /// окно Windows 880×680 — при умолчании `adaptive` там включились бы колонки,
  /// и страж, написанный ДО этой настройки, покраснел бы не по своей вине.
  /// Настоящий экран передаёт сюда `settings.serviceChecksLayout` явно.
  final ServiceChecksLayout layout;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠️ ПЛАШКА — СВОЕЙ СТРОКОЙ, А НЕ НАКЛАДКОЙ ПОВЕРХ КНОПКИ.
        //
        // Накладка не занимала места в потоке, и это ровно то, на что владелец
        // жаловался дважды: она лежала на верхней кромке круга и свисала на
        // 24 px в каждую сторону — прямо на проверки. Ужимать свес некуда: круг
        // 148 px, и любая плашка, вписанная в него, режет имя после трёх букв.
        // Строка выше кнопки не пересекается ни с кругом, ни с чипами по
        // определению — пересекаться нечему.
        ActiveServerBanner(
            name: serverName, trailing: bannerTrailing, leading: bannerLeading),
        // ⚠️ РАСКЛАДКА ВЫБИРАЕТСЯ ЗДЕСЬ, ПО ШИРИНЕ РОДИТЕЛЯ — И ЭТО ЕДИНСТВЕННОЕ
        // МЕСТО, ГДЕ ЭТОТ ВЫБОР ДЕЛАЕТСЯ. Прошлый регресс (см. шапку файла) был
        // ровно в том, что раскладка существовала в коде, но вызов её не
        // подставлял — здесь `LayoutBuilder` смотрит на РЕАЛЬНЫЕ ограничения
        // этого места на экране, а не на копию.
        // ⚠️ `Flexible` ДОВОДИТ ПОТОЛОК ДО БЛОКА. Дети `Column` получают
        // `maxHeight: infinity`, поэтому `LayoutBuilder` ниже видел бы
        // бесконечность даже когда сам блок стоит в `ConstrainedBox` от
        // панели, — и сжатие по высоте, включающееся только при
        // `hasBoundedHeight`, не включалось бы никогда. Симптом с живого
        // окна: подпись «Доступность сервисов…» ложится ПОВЕРХ последнего
        // ряда значков (`centerpiece_reports_its_height_test`).
        //
        // ⚠️ ПРОШЛАЯ ПОПЫТКА ЭТОГО ЖЕ БЫЛА ОТКАЧЕНА (1b9560e, 36229ab) —
        // и правильно: тогда сервисы стояли одной длинной колонкой, при
        // ограничении высоты оценка уводила раскладку в РЯДЫ, у которых
        // сжатия нет вовсе, и весь экран складывался в кучу. С сеткой
        // блоков высота нужна лишь немногим больше выданной (266 против
        // 237), сжатие остаётся в пределах читаемого, и в ряды раскладка
        // не падает.
        Flexible(
          child: LayoutBuilder(builder: (context, c) {
            final effective = layout == ServiceChecksLayout.adaptive
                ? (c.maxWidth >= _sidesMinWidth
                    ? ServiceChecksLayout.sides
                    : ServiceChecksLayout.rows)
                : layout;
            switch (effective) {
              case ServiceChecksLayout.hidden:
                // ⚠️ Проверок нет ВООБЩЕ — ни рядов, ни плашки «канал не готов»:
                // ей нечего было бы объяснять, раз человек сам их выключил.
                return button;
              case ServiceChecksLayout.rows:
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    button,
                    // ⚠️ Пустой набор не строится ВОВСЕ, а не рисуется пустым:
                    // владелец просил галочку «полного отключения», и
                    // выключенные проверки не должны занимать место у кнопки.
                    ServiceChecksRows(services: services, httpPort: httpPort),
                    ServiceChecksNotReadyBanner(
                        httpPort: httpPort, services: services),
                  ],
                );
              case ServiceChecksLayout.sides:
              case ServiceChecksLayout.grid:
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ⚠️ ТРЕТИЙ СЛОЙ. Потолок надо проводить через КАЖДУЮ
                    // колонку на пути: панель → центральный блок → эта.
                    // Пропусти любую — и ограничение снова станет
                    // бесконечным, а сжатие внизу не включится.
                    Flexible(
                      child: ServiceChecksSides(
                        services: services,
                        httpPort: httpPort,
                        button: button,
                        dense: effective == ServiceChecksLayout.grid,
                      ),
                    ),
                    ServiceChecksNotReadyBanner(
                        httpPort: httpPort, services: services),
                  ],
                );
              case ServiceChecksLayout.adaptive:
                // Недостижимо: adaptive разрешён в sides/rows выше.
                return button;
            }
          }),
        ),
      ],
    );
  }
}

/// Плашка «канал ещё не готов» под кнопкой Connect.
///
/// Показывается, только когда автопрогон проверок НЕ СОСТОЯЛСЯ из-за того, что
/// сквозной запрос через живое ядро не прошёл. Это не то же самое, что «сервисы
/// не открываются»: там пробы отработали и дали ответ, а здесь их не было вовсе.
/// Разница для человека принципиальная — во втором случае помогает подождать и
/// нажать повтор, в первом менять надо сервер.
class ServiceChecksNotReadyBanner extends StatelessWidget {
  const ServiceChecksNotReadyBanner({
    super.key,
    required this.httpPort,
    required this.services,
  });

  final int httpPort;
  final List<ProbeService> services;

  @override
  Widget build(BuildContext context) {
    // Читаем НЕОБЯЗАТЕЛЬНО: стражи вёрстки поднимают эту часть экрана без
    // провайдеров, и строгое чтение уронило бы их `ProviderNotFoundException`.
    final ctrl = context.watch<ServiceCheckController?>();
    if (ctrl == null || !ctrl.channelNotReady || httpPort <= 0) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_empty, size: 14, color: scheme.outline),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l.serviceChecksChannelNotReady,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const Key('serviceChecksRetry'),
            onPressed: () =>
                unawaited(ctrl.retryAutoCheck(httpPort, services)),
            child: Text(l.serviceChecksRetryCheck),
          ),
        ],
      ),
    );
  }
}

/// Строка с плашкой активного сервера над кнопкой Connect.
///
/// Место под плашку занято ВСЕГДА, даже когда имени нет: иначе кнопка и обе
/// колонки проверок прыгали бы вверх-вниз на каждом подключении и отключении.
/// Тот же приём, что у строки трафика ниже, — она тоже висит с нулями.
class ActiveServerBanner extends StatelessWidget {
  const ActiveServerBanner(
      {super.key, required this.name, this.trailing, this.leading});

  /// Имя активного сервера. `null`/пусто — плашка невидима, но место держит.
  final String? name;

  /// Хвост полосы — кнопки в правом краю. Виден ВСЕГДА, независимо от того,
  /// есть ли имя: кнопкой подменю проверки включают обратно, и прятать её
  /// вместе с плашкой значило бы оставить человека без пути назад.
  final Widget? trailing;

  /// Левый край полосы — на экране это «Информация о сервере».
  ///
  /// ⚠️ МЕСТО ПОД НЕГО ДЕРЖИТСЯ ВСЕГДА, даже когда кнопки нет (сервер не
  /// выбран): распорка слева симметрична хвосту, и без неё плашка съезжала бы
  /// с оси кнопки Connect ровно в тот момент, когда человек выбирает сервер.
  final Widget? leading;

  /// Просвет между плашкой и кнопкой.
  static const double gap = 10;

  /// Ширина места под хвост — и РОВНО ТАКОЙ ЖЕ распорки слева.
  ///
  /// ⚠️ РАСПОРКА СИММЕТРИЧНАЯ, И ЭТО НЕ КРАСОТА. Плашка центрируется в том,
  /// что осталось от строки; хвост без пары слева сдвигал бы её от оси кнопки
  /// на половину своей ширины — 30 px, заметно глазом. Две кнопки по 28 и
  /// просвет 2 — 58; запас 2.
  static const double trailingWidth = 60;

  @override
  Widget build(BuildContext context) {
    final n = name;
    final shown = n != null && n.isNotEmpty;
    final label = Visibility(
      visible: shown,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      // Пробел, а не пустая строка: место резервируется РОВНО той же
      // вёрсткой, что потом рисует имя, поэтому оно не зависит ни от размера
      // системного шрифта, ни от будущих правок отступов плашки.
      child: ActiveServerLabel(name: shown ? n : ' '),
    );
    final tail = trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      // Без хвоста — прежняя одиночная плашка: `Row` с `Expanded` требует
      // конечной ширины, а без хвоста ему нечего делить.
      child: tail == null && leading == null
          ? label
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: trailingWidth,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: leading ?? const SizedBox.shrink(),
                  ),
                ),
                Expanded(child: Center(child: label)),
                SizedBox(
                  width: trailingWidth,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: tail,
                  ),
                ),
              ],
            ),
    );
  }
}

/// «Информация о сервере» — значком в левом краю полосы плашки.
///
/// ⚠️ РЕГРЕСС-ОПАСНОЕ МЕСТО. Экран информации о сервере открывался с главного
/// отдельной строкой-кнопкой под статусом; строка стоила 48 px, и ровно их не
/// хватало низу экрана на минимальном окне 980×800. Убрать её было можно
/// только вместе с новым входом: до этого экран открывался ещё лишь из
/// контекстного меню в списке серверов, где его никто не находил.
///
/// ⚠️ ТУГАЯ КОРОБКА 28 px, как у кнопок хвоста. Область нажатия Material тянет
/// `IconButton` до 40 px, если родитель не зажал, — полоса плашки поднялась бы
/// на 12 px, и весь выигрыш от переезда ушёл бы обратно.
class ServerInfoButton extends StatelessWidget {
  const ServerInfoButton({super.key});

  /// Сторона кнопки — совпадает с `ServiceChecksMenuButton.size` и
  /// `InfoTooltip.compactSize`.
  static const double size = 28;

  /// ⚠️ НЕ `Icons.info_outline` — И ЭТО НЕ ПРИДИРКА К ОФОРМЛЕНИЮ.
  ///
  /// В той же полосе плашки, у правого её края, стоит `InfoTooltip` — тоже
  /// кружок «i». Два одинаковых значка в полусотне пикселей друг от друга
  /// вели бы в совершенно разные места: этот — на целый экран с внешним
  /// адресом, страной, провайдером и скоростью, тот — во всплывающее
  /// пояснение про проверки сервисов. Подписей на полосе нет, и раньше вход
  /// сюда был кнопкой СО СЛОВАМИ «Информация о сервере»; после переезда
  /// значком назначение стало угадываться только тыком.
  ///
  /// `travel_explore` — глобус с лупой, «посмотреть, откуда выходит этот
  /// сервер». В проекте он занят ещё одним местом (строка поиска помех в
  /// настройках), но это другой экран, и на одной полосе они не встречаются;
  /// «i» же обязано остаться за подсказкой, потому что это буквально она.
  static const IconData icon = Icons.travel_explore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Необязательное чтение: стражи вёрстки поднимают полосу без провайдеров.
    final server = context.watch<AppState?>()?.selectedServer;
    // ⚠️ Место под кнопку держит РОДИТЕЛЬ (`ActiveServerBanner.leading`), а не
    // эта пустышка: иначе плашка прыгала бы при выборе сервера.
    if (server == null) return const SizedBox(width: size, height: size);
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: const Icon(icon, size: 18),
        // ⚠️ ПОДСКАЗКА ОБЯЗАТЕЛЬНА: на полосе нет подписей, и без неё
        // назначение значка выясняется только нажатием. Соседняя «i» держит
        // свою (`serviceChecksInfo`), и тексты у них разные — по ним и видно,
        // куда ведёт каждый.
        tooltip: l.homeServerInfo,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: size, height: size),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ServerInfoScreen(server: server),
        )),
      ),
    );
  }
}

/// Подпись «какой сервер сейчас включён» — плашкой над кнопкой.
///
/// Флаг рисуется картинкой и вырезается из текста — иначе на Windows он
/// выглядел бы чёрным прямоугольником и дублировался.
class ActiveServerLabel extends StatelessWidget {
  const ActiveServerLabel({super.key, required this.name});

  final String? name;

  /// Потолок ширины плашки.
  ///
  /// Родитель ужимает её и сильнее (на узком экране — до своей ширины), а этот
  /// предел держит её осмысленной на широком окне: пилюля во весь экран из-за
  /// стосимвольного имени выглядит поломкой.
  static const double maxWidth = 360;

  /// Сколько строк отдаём имени.
  ///
  /// Две, а не одна: у владельца имена вида «🇩🇪 🚀Германия 2.7 (edge)», и
  /// длинные встречаются регулярно. На одной строке хвост уезжал в многоточие
  /// ровно там, где начинается отличие одного узла от другого (номер, метка
  /// edge/premium), — то есть обрезалось самое нужное.
  static const int maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final n = name;
    if (n == null || n.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      // Имя целиком: в плашку помещается не всякое, а знать, куда подключён,
      // нужно точно.
      message: n,
      child: Container(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Флаг — только если в имени действительно есть страна. У панельного
          // профиля имя начинается с 🌐, и запасной значок вставал рядом с ним
          // вторым «глобусом»: два одинаковых кружка вместо одного.
          if (FlagUtil.isoFromName(n) != null) ...[
            FlagCell(n, width: 20, height: 14),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              FlagUtil.strip(n),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}

/// #8 — индикатор идущих проверок; тап → на соответствующий экран.
class _Onboarding extends StatelessWidget {
  final void Function(Widget screen) onOpen;
  const _Onboarding({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_download_outlined,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(l.homeOnboardingTitle, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l.homeOnboardingSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l.homeImportSubscription),
              onPressed: () => onOpen(const ImportScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Публичная, а не `_ConnectButton` — 27.08.2026 понадобилась настоящая (не
/// скопированная) кнопка в страже `test/connect_button_content_test.dart`:
/// он проверяет, что значок и таймер вписаны в круг на всех пяти раскладках
/// `ServiceChecksLayout`. Приватный класс тест увидеть не может (приватность
/// в Dart — по файлу), а рисовать копию кнопки в тесте — ровно та ошибка, на
/// которой этот файл уже обжигался (см. шапку `ConnectCenterpiece`). Само имя
/// вызывающего кода при этом не поменялось ни строкой.
class ConnectButton extends StatelessWidget {
  final VpnStatus status;
  final VoidCallback onTap;

  /// Диаметр круга. `null` — прежнее поведение: 148, а на коротком экране
  /// (`context.sg.isShort`) — 116, СОХРАНЕНО КАК ЗНАЧЕНИЕ ПО УМОЛЧАНИЮ, чтобы
  /// не задеть места, где диаметр не передают. Раскладка колонок по бокам
  /// (`ServiceChecksSides`) считает нужный диаметр сама через `LayoutBuilder` и
  /// подставляет его явно.
  final double? diameter;

  const ConnectButton({
    required this.status,
    required this.onTap,
    this.diameter,
  });

  /// Диаметр, на котором посчитаны исходные размеры значка (68/56 px) —
  /// опорная точка коэффициента масштаба ниже.
  static const double _baseline = 148;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final connected = status.isConnected;
    final busy = status.isBusy;
    final color = connected ? scheme.primary : scheme.surfaceContainerHighest;
    // ⚠️ Кнопка ужимается ТОЛЬКО когда высоты реально нет (телефон в
    // ландшафте, открытая клавиатура) — И ТОЛЬКО пока диаметр не передан
    // явно. Окно Windows не ниже 800 dp, поэтому там всегда 148.
    final d = diameter ?? (context.sg.isShort ? 116.0 : 148.0);
    // ⚠️ ВСЁ ВНУТРИ КРУГА СЧИТАЕТСЯ ОТ ЭТОГО КОЭФФИЦИЕНТА, А НЕ ФИКСИРОВАННЫМИ
    // ПИКСЕЛЯМИ. Раньше значок питания и таймер сессии были одного размера
    // независимо от диаметра круга — не страшно, пока диаметр было ровно два
    // значения (148/116, разница небольшая), но колонки по бокам сжимают круг
    // сильнее, и значок крупнее уменьшенного круга просто вылез бы за край.
    final scale = d / _baseline;

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: connected
              ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 4)]
              : null,
        ),
        child: Center(
          child: busy
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.power_settings_new,
                        // Значок ужимается, когда под ним появляются слово и
                        // время, и масштабируется вместе со всем кругом.
                        size: (connected ? 46 : 56) * scale,
                        color: connected ? scheme.onPrimary : scheme.onSurface),
                    // ⚠️ СЛОВО ВНУТРИ КРУГА, А НЕ ПОД НИМ — требование
                    // владельца (04.09.2026). До этого состояние читалось
                    // только по цвету круга и по слову «Отключено» сбоку, а
                    // цвет сам по себе не говорит, ЧТО СЛУЧИТСЯ ПО НАЖАТИЮ.
                    //
                    // Надпись называет ДЕЙСТВИЕ, а не состояние: на живом
                    // канале написано «Отключить». Написать там состояние
                    // («Подключено») значило бы, что кнопка обещает сделать
                    // то, что уже сделано.
                    SizedBox(
                      // Круг узкий, а «Bağlantıyı kes» и «Déconnecter»
                      // длинные: без ограничения ширины слово вылезло бы за
                      // край круга на турецком и французском, и увидели бы
                      // это только на этих языках.
                      width: d * 0.78,
                      // ⚠️ УЖИМАЕМ, НО НЕ УСЕКАЕМ. Найдено ревью 05.09.2026, и
                      // это худший из возможных отказов: турецкое
                      // «Bağlantıyı kes» («отключить») усекалось до
                      // «Bağlan…», а «Bağlan» по-турецки значит ПОДКЛЮЧИТЬ.
                      // То есть на живом канале кнопка предлагала бы ровно
                      // противоположное тому, что сделает.
                      //
                      // Многоточие в надписи действия недопустимо в принципе:
                      // усечённый глагол легко превращается в другой глагол.
                      // Поэтому вместо `ellipsis` — перенос на вторую строку и
                      // сжатие целиком: слово остаётся читаемым и правдивым
                      // при любом языке и любом системном укрупнении текста.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: d * 0.78,
                          child: Text(
                            connected
                                ? l.connectButtonDisconnect
                                : l.connectButtonConnect,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.w600,
                              color: connected
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (connected) _UptimeLabel(scale: scale),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Сколько длится подключение — прямо в кнопке.
///
/// Отдельный виджет с собственным таймером: перерисовывать раз в секунду весь
/// экран расточительно. Точка отсчёта живёт в [AppState], а не здесь: кнопка
/// пересоздаётся на каждом обновлении статуса, и время начиналось бы заново.
class _UptimeLabel extends StatefulWidget {
  /// Множитель от `ConnectButton._baseline` — таймер обязан ужиматься вместе
  /// с кругом, иначе на сжатой кнопке (колонки по бокам) он не влезал бы.
  const _UptimeLabel({this.scale = 1.0});

  final double scale;

  @override
  State<_UptimeLabel> createState() => _UptimeLabelState();
}

class _UptimeLabelState extends State<_UptimeLabel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// «7:12» до часа, дальше «1:07:12» — как в плеере: ведущий ноль у минут не
  /// нужен, а у секунд обязателен, иначе цифры прыгают при переходе через 10.
  static String format(Duration d) {
    final total = d.inSeconds;
    final hh = total ~/ 3600;
    final mm = (total ~/ 60) % 60;
    final ss = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return hh > 0 ? '$hh:${two(mm)}:${two(ss)}' : '$mm:${two(ss)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = context.select<AppState, Duration?>((s) => s.connectedFor);
    if (d == null) return const SizedBox.shrink();
    final baseSize = Theme.of(context).textTheme.labelLarge?.fontSize ?? 14;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        format(d),
        textDirection: TextDirection.ltr,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: baseSize * widget.scale,
              // Моноширинные цифры: иначе строка дёргается на каждой секунде,
              // потому что «1» уже остальных.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}

/// Трафик: скорость и объём текущего подключения + итог за сессию приложения.
/// Показывается ВСЕГДА (нулями при отключённом VPN), чтобы блок не появлялся
/// рывком и не сдвигал кнопки.
/// Счётчики трафика — последняя строка панели.
///
/// Публична ради замера: именно её нижняя кромка задаёт резерв
/// [kChecksReserveBelow], и число в комментарии рядом с константой обязано
/// сверяться с настоящей вёрсткой, а не переписываться на глаз.
class TrafficRow extends StatelessWidget {
  final TrafficStats stats;
  final int sessionUp;
  final int sessionDown;
  const TrafficRow({
    super.key,
    required this.stats,
    required this.sessionUp,
    required this.sessionDown,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _metric(context, Icons.arrow_downward,
                TrafficStats.formatSpeed(stats.downlinkSpeed),
                TrafficStats.formatBytes(stats.downlinkBytes)),
            _metric(context, Icons.arrow_upward,
                TrafficStats.formatSpeed(stats.uplinkSpeed),
                TrafficStats.formatBytes(stats.uplinkBytes)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l.homeSessionTraffic(
            TrafficStats.formatBytes(sessionDown),
            TrafficStats.formatBytes(sessionUp),
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _metric(BuildContext context, IconData icon, String speed, String total) {
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(speed,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleSmall),
      ]),
      Text(total,
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}


/// Плашка «нужны гео-базы» на главном экране.
///
/// ⚠️ ПОЧЕМУ НЕ ХВАТИЛО ВСПЛЫВАЮЩЕГО СООБЩЕНИЯ. Вердикт о гео-базах ядро выносит
/// в момент подъёма туннеля — а на Android это ровно тот момент, когда
/// приложение чаще всего НЕ на экране: сверху диалог согласия VPN, стартует
/// сервис. Всплывашка, показанная в эту секунду, до человека не доходит.
/// Владелец так и сказал: «предложение докачать гео-файлы как будто не
/// происходит».
///
/// ⚠️ И ПОЧЕМУ НЕ ХВАТИЛО ВЕРДИКТА ЯДРА. Его ставит `_guardGeodata`, а он
/// существует ТОЛЬКО в андроидном движке и только на пути подключения. То есть
/// до первого подключения плашки не бывало нигде, а на Windows — никогда
/// вообще: жалоба владельца «ни на телефоне, ни на ПК не предлагает докачать
/// геобазы, если их нет». Поэтому повод считается сам, из двух фактов: лежат ли
/// файлы (спрашиваем `GeoBasesController` — тот же источник, что рисует кнопку
/// в настройках) и есть ли кому их читать ([AppState.geoRulesInUse]).
///
/// ⚠️ ЗДЕСЬ НЕТ РЕШЕНИЯ, ТОЛЬКО ПОКАЗ. Что предлагать — считает
/// [geoOfferReason]; своей копии этой логики в виджете быть не должно, иначе
/// плашка и настройки разойдутся в первой же правке.
class GeoOfferBanner extends StatefulWidget {
  const GeoOfferBanner({super.key});

  @override
  State<GeoOfferBanner> createState() => _GeoOfferBannerState();
}

class _GeoOfferBannerState extends State<GeoOfferBanner> {
  /// Состояние файлов на диске. Экземпляр свой, но правда — общая: контроллер
  /// её не хранит, а перечитывает с диска, поэтому «второго мнения» тут не
  /// заводится. Сети он не касается, пока не позвали `check`/`download`.
  final GeoBasesController _geo = GeoBasesController();

  /// Диск спрашивали хотя бы раз. Не `bool busy`: [GeoBasesController.refresh]
  /// зовётся из `build`, и без отметки он звался бы на каждой перерисовке.
  bool _asked = false;

  @override
  void dispose() {
    _geo.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const SettingsScreen(scrollToGeo: true)));
    // Вернулись из настроек — базы могли появиться. Перечитываем диск сами: у
    // раздела настроек свой экземпляр контроллера, ждать от него уведомления
    // нельзя.
    await _geo.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // ⚠️ ДИСКА НЕ КАСАЕМСЯ, ПОКА НЕ ВЫЯСНЕНО, ЧТО БАЗЫ ЧЕЛОВЕКУ НУЖНЫ. У кого
    // ссылок `geoip:`/`geosite:` нет ни в одном конфиге, тому эта плашка не
    // покажется никогда — и лишнего чтения диска на каждом запуске у него тоже
    // не будет.
    if (!state.geoRulesInUse && state.geoVerdict == null) {
      return const SizedBox.shrink();
    }
    if (!_asked) {
      _asked = true;
      unawaited(_geo.refresh());
    }
    return ListenableBuilder(
      listenable: _geo,
      builder: (context, _) => _card(context, state),
    );
  }

  Widget _card(BuildContext context, AppState state) {
    final reason = geoOfferReason(
      filesAction: _geo.action,
      rulesInUse: state.geoRulesInUse,
      verdict: state.geoVerdict,
      dismissed: state.geoOfferDismissedFor,
    );
    if (reason == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Два РАЗНЫХ случая: файлов нет — предлагаем скачать; файлы есть, а ядро их
    // не открыло — предлагать «скачайте» бессмысленно, там нужно перекачать.
    final missing = reason == EngineNoticeKind.geoAssetsMissing;
    // ⚠️ И ДВЕ РАЗНЫЕ ПОДПИСИ У ОДНОГО ПОВОДА. Ядро уже жаловалось — говорим о
    // том, что происходит («правила сейчас отключены»); предлагаем заранее —
    // о том, что будет. Прошедшее время в предложении, сделанном до первого
    // подключения, читалось бы как рассказ о поломке, которой не было.
    final sub = missing
        ? (state.geoVerdict == EngineNoticeKind.geoAssetsMissing
            ? l.geoVerdictMissingSub
            : l.geoOfferMissingSub)
        : l.geoVerdictUnusableSub;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          Icon(Icons.public_off, size: 20, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    missing
                        ? l.geoVerdictMissingTitle
                        : l.geoVerdictUnusableTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onTertiaryContainer)),
                Text(sub,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onTertiaryContainer)),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('geoOfferAct'),
            // Ведём в настройки, а не качаем отсюда. Закачка требует согласия с
            // размером, полоски хода, разбора ошибки и отдельного случая «нет
            // прав на запись в каталог ядра» — всё это уже есть в разделе
            // настроек, и вторая копия того же разошлась бы с первой.
            onPressed: _openSettings,
            child: Text(missing ? l.geoDownload : l.geoUpdate),
          ),
          IconButton(
            key: const ValueKey('geoOfferDismiss'),
            // ⚠️ Не «закрыть», а «больше не предлагать»: плашка показывается
            // при каждом запуске, и закрытие на один раз было бы отсрочкой до
            // завтра, а не ответом. Отказ запоминается по ПОВОДУ — см.
            // [AppState.dismissGeoOffer].
            tooltip: l.geoOfferDismiss,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.notifications_off_outlined, size: 18),
            onPressed: () => state.dismissGeoOffer(reason),
          ),
        ]),
      ),
    );
  }
}

/// ПЛАШКА «УВЕДОМЛЕНИЯ ВЫКЛЮЧЕНЫ» (Android).
///
/// ⚠️ ЗАЧЕМ. При отказе теряются две вещи, и обе замечаются не сразу:
/// постоянное уведомление сервиса с кнопкой «Отключить» (единственный способ
/// снять туннель при закрытом приложении) и разовое сообщение об обрыве связи.
/// Второе хуже: человек считает, что за каналом следят, а сообщить ему не
/// может никто.
///
/// ⚠️ ПОЧЕМУ ПЛАШКА, А НЕ ПОВТОРНЫЙ ЗАПРОС РАЗРЕШЕНИЯ. Android показывает
/// системный запрос ОДИН раз; дальше `requestPermissions` возвращается молча,
/// ничего не показав. То есть просить второй раз — значит ничего не делать и
/// думать, что сделал. Включить уведомления может только человек и только
/// руками, поэтому единственный честный ход — сказать и довести до экрана.
///
/// ⚠️ ПРОВЕРЯЕТСЯ ПРИ КАЖДОМ ВОЗВРАТЕ В ПРИЛОЖЕНИЕ, а не один раз на старте:
/// человек уходит по нашей же кнопке в настройки и возвращается — плашка
/// обязана исчезнуть сама. Иначе она выглядит как «я включил, а оно не
/// заметило», и следующий её показ уже не читают.
class NotificationsOffBanner extends StatefulWidget {
  const NotificationsOffBanner({super.key});

  @override
  State<NotificationsOffBanner> createState() => _NotificationsOffBannerState();
}

class _NotificationsOffBannerState extends State<NotificationsOffBanner>
    with WidgetsBindingObserver {
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    final b = await NotificationAccess.blocked();
    if (mounted && b != _blocked) setState(() => _blocked = b);
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocked) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          Icon(Icons.notifications_off_outlined,
              size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.notifOffTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onErrorContainer)),
                Text(l.notifOffSub,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onErrorContainer)),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('notifOffAct'),
            onPressed: () async {
              final ok = await NotificationAccess.openSettings();
              // ⚠️ Экрана может не быть на экзотической прошивке. Молча ничего
              // не делать нельзя: человек нажал и ждёт.
              if (!ok && context.mounted) {
                AppToast.show(context, l.notifOffNoScreen, kind: ToastKind.info);
              }
            },
            child: Text(l.notifOffOpen),
          ),
        ]),
      ),
    );
  }
}
