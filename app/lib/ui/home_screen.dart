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
import '../core/update/app_update.dart';
import '../core/settings/app_settings.dart';
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
import 'widgets/connect_guard.dart';
import 'widgets/flag_cell.dart';
import 'widgets/server_search_field.dart';
import 'widgets/server_tile.dart';
import 'widgets/service_checks_row.dart';
import 'widgets/update_notes_dialog.dart';
import 'widgets/subscription_bar.dart';
import 'widgets/ping_chip.dart';
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
      final detail = (notice.detail ?? '').trim();
      AppToast.show(
        context,
        detail.isEmpty ? notice.text : '${notice.text} · $detail',
        kind: notice.isProblem ? ToastKind.error : ToastKind.info,
        duration: Duration(seconds: notice.isProblem ? 10 : 6),
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
      body: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < _twoPaneMinWidth) {
            return _ConnectPane(
              status: status,
              settings: settings,
              onOpen: (w) => _open(context, w),
              compact: true,
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ConnectPane(
                  status: status,
                  settings: settings,
                  onOpen: (w) => _open(context, w),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                  width: 380, child: _ServerPane(onOpen: (w) => _open(context, w))),
            ],
          );
        },
      ),
    ));
  }
}

/// Ниже этой ширины список серверов уезжает на отдельный экран: панель в 380 px
/// плюс осмысленная колонка подключения рядом уже не помещаются.
const double _twoPaneMinWidth = 760;

class _ConnectPane extends StatelessWidget {
  final VpnStatus status;
  final AppSettings settings;
  final void Function(Widget screen) onOpen;

  /// Узкий экран: список серверов уехал на отдельный маршрут, поэтому здесь
  /// появляется строка выбранного сервера, а содержимое становится
  /// прокручиваемым — гарантии минимального размера окна на телефоне нет.
  final bool compact;

  const _ConnectPane({
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (!compact) const Spacer(),
                // Плашка активного сервера, кнопка и колонки проверок — одним
                // виджетом: ровно то, что проверяет страж вёрстки.
                ConnectCenterpiece(
                  serverName: activeServerName(
                    connected: status.isConnected,
                    connectedKey: state.connectedServerKey,
                    servers: state.servers,
                    autoLabel: l.homeAutoBest,
                  ),
                  httpPort: status.isConnected ? state.httpProxyPort : 0,
                  services: checks,
                  button: _ConnectButton(
                      status: status,
                      onTap: () => connectWithConflictCheck(context, state,
                          () => state.toggleConnection(settings))),
                ),
                // Без подписи два кружка у каждого значка — ребус. Говорим
                // прямо, что слева замер без VPN, справа — через VPN, и что
                // оба снимаются сами.
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ⚠️ Строка ужимается: рядом встала кнопка подменю, и на
                    // узком телефоне подпись без этого уезжала за край.
                    Flexible(
                      child: Text(
                        checks.isEmpty
                            // Проверки выключены — врать «проверено» нельзя,
                            // а строку не убираем: она объясняет пустое место
                            // и стоит рядом с кнопкой, которой их включают.
                            ? l.serviceChecksLegendOff
                            : status.isConnected
                                ? l.serviceChecksLegendAfter
                                : l.serviceChecksLegendBefore,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).hintColor),
                      ),
                    ),
                    InfoTooltip(l.serviceChecksInfo),
                    // Подменю набора — здесь, у самих проверок (требование
                    // владельца). Видно ВСЕГДА: когда проверки выключены,
                    // включить их больше неоткуда.
                    const ServiceChecksMenuButton(),
                  ],
                ),
                const SizedBox(height: 16),
                Text(vpnStatusLabel(l, status.state),
                    style: Theme.of(context).textTheme.titleMedium),
                // «Информация о сервере» прямо у кнопки: раньше экран
                // открывался только из контекстного меню в списке серверов,
                // где его никто не находил.
                if (state.selectedServer != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: Text(l.homeServerInfo),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ServerInfoScreen(server: state.selectedServer!),
                        )),
                  ),
                ],
                // ⚠️ KILL SWITCH ДЕРЖИТ ТРАФИК — СКАЗАТЬ ЭТО ЗАМЕТНО.
                //
                // Пропавший интернет без объяснения выглядит поломкой, и самое
                // естественное действие человека — выключить VPN, то есть ровно
                // то, от чего защита оберегала. Строки статуса мало: она
                // мелкая и теряется среди прочего.
                if (status.blocking)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.shield_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status.message ?? '',
                          textDirection: autoTextDirection(status.message),
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.onErrorContainer),
                        ),
                      ),
                    ]),
                  ),
                if (status.state == VpnConnectionState.error &&
                    status.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(status.message!,
                        textAlign: TextAlign.center,
                        // Статус/ошибка: направление по содержимому — локализованный
                        // текст читается верно, вложенные технические фрагменты (имена
                        // exe/серверов) — по bidi.
                        textDirection: autoTextDirection(status.message),
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 20),
                if (state.hasServers)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.bolt),
                    label: Text(l.homeAutoBest),
                    onPressed: () => connectWithConflictCheck(
                        context,
                        state,
                        () => state.connectAuto(
                            context.read<SettingsController>().settings)),
                  ),
                // Автонастройка стоит на проброс-харнессе. На Android он
                // ПОЯВИЛСЯ (`LibXray.ping` поднимает свой экземпляр ядра, не
                // трогая туннель), поэтому кнопка снова на месте. Гейт оставлен:
                // на платформе без харнесса нажатие показывало бы сырое
                // «Unsupported operation», а обещать несуществующее хуже, чем
                // не показывать.
                if (proxyProbeSupported) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(l.homeAutoConfig),
                    // Через ту же точку, что и нажатие на карточку прогресса:
                    // один экземпляр экрана на оба пути (и двойное нажатие по
                    // самой кнопке второй копии тоже не откроет).
                    onPressed: () => AppToast.openOnce(
                      context,
                      key: 'autoconfig',
                      builder: (_) => const AutoConfigScreen(),
                    ),
                  ),
                ],
                  if (!compact) const Spacer() else const SizedBox(height: 24),
                  // Всегда на месте: при отключённом VPN — нули (иначе блок появлялся
                  // рывком и двигал кнопки, а цифры не помещались).
                  _TrafficRow(
                    stats: status.isConnected ? state.stats : TrafficStats.zero,
                    sessionUp: state.sessionUplinkBytes,
                    sessionDown: state.sessionDownlinkBytes,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
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

class _ServerPane extends StatefulWidget {
  final void Function(Widget screen) onOpen;
  const _ServerPane({required this.onOpen});

  @override
  State<_ServerPane> createState() => _ServerPaneState();
}

class _ServerPaneState extends State<_ServerPane> {
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
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton.icon(
                icon: probe.running
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check, size: 18),
                // Пингуем то, что видно: при активном поиске — только найденное.
                label: Text(_query.isEmpty ? l.homePingServers : l.homePingFound),
                onPressed: probe.running || probe.speedRunning || shown.isEmpty
                    ? null
                    : () => probe.pingAll(
                        [for (final i in shown) servers[i]], settings),
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
  });

  /// Имя активного сервера (см. [activeServerName]); `null` — плашка пустая.
  final String? serverName;

  /// http-порт живого ядра для проверок; 0 — VPN выключен.
  final int httpPort;

  /// Какие сервисы показывать по бокам кнопки. Пусто — колонок нет вовсе, и
  /// места они не занимают (проверки выключены в подменю).
  ///
  /// Умолчание — прежняя зашитая шестёрка: стражам вёрстки настройки не нужны,
  /// им нужна раскладка. Экран передаёт сюда `ServiceChecks.selected(settings)`.
  final List<ProbeService> services;

  /// Кнопка приходит снаружи: ей нужен `AppState`, а стражу вёрстки — нет.
  final Widget button;

  @override
  Widget build(BuildContext context) {
    final split = ServiceChecks.columns(services);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠️ ПЛАШКА — СВОЕЙ СТРОКОЙ, А НЕ НАКЛАДКОЙ ПОВЕРХ КНОПКИ.
        //
        // Накладка не занимала места в потоке, и это ровно то, на что владелец
        // жаловался дважды: она лежала на верхней кромке круга и свисала на
        // 24 px в каждую сторону — прямо на колонки проверок. Ужимать свес
        // некуда: круг 148 px, и любая плашка, вписанная в него, режет имя
        // после трёх букв. Строка выше кнопки не пересекается ни с кругом, ни
        // с чипами по определению — пересекаться нечему.
        ActiveServerBanner(name: serverName),
        // Проверка сервисов — КОЛОНКАМИ ПО БОКАМ кнопки, а не строкой снизу:
        // так «до» и «после» видно рядом, и ряд не уезжает под край экрана на
        // телефоне. Показывается и до подключения — иначе сравнивать было бы
        // не с чем.
        //
        // ⚠️ Пустая колонка не строится ВОВСЕ, а не рисуется пустой: владелец
        // просил галочку «полного отключения», и выключенные проверки не
        // должны занимать место у кнопки.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (split.left.isNotEmpty)
              Flexible(
                child: ServiceChecksColumn(
                  services: split.left,
                  httpPort: httpPort,
                  alignEnd: true,
                ),
              ),
            button,
            if (split.right.isNotEmpty)
              Flexible(
                child: ServiceChecksColumn(
                  services: split.right,
                  httpPort: httpPort,
                  alignEnd: false,
                ),
              ),
          ],
        ),
        // ⚠️ «КАНАЛ НЕ ГОТОВ» — ОТДЕЛЬНОЕ СОСТОЯНИЕ, А НЕ 14 КРАСНЫХ КРУЖКОВ.
        //
        // Раньше при неготовом канале пачка проб уходила в пустоту, и человек
        // видел ряд красных кружков — то есть читал «VPN не работает», хотя
        // туннель просто не успел прогреться. Теперь пробы в этом случае не
        // запускаются вовсе, а причина называется словами и даётся кнопка
        // повтора. Плашка стоит ЗДЕСЬ, а не в колонке: колонок две, и в колонке
        // она задвоилась бы.
        ServiceChecksNotReadyBanner(httpPort: httpPort, services: services),
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
  const ActiveServerBanner({super.key, required this.name});

  /// Имя активного сервера. `null`/пусто — плашка невидима, но место держит.
  final String? name;

  /// Просвет между плашкой и кнопкой.
  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    final n = name;
    final shown = n != null && n.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      child: Visibility(
        visible: shown,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        // Пробел, а не пустая строка: место резервируется РОВНО той же
        // вёрсткой, что потом рисует имя, поэтому оно не зависит ни от размера
        // системного шрифта, ни от будущих правок отступов плашки.
        child: ActiveServerLabel(name: shown ? n : ' '),
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

class _ConnectButton extends StatelessWidget {
  final VpnStatus status;
  final VoidCallback onTap;
  const _ConnectButton({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = status.isConnected;
    final busy = status.isBusy;
    final color = connected ? scheme.primary : scheme.surfaceContainerHighest;

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        // ⚠️ Кнопка ужимается ТОЛЬКО когда высоты реально нет: телефон в
        // ландшафте или открытая клавиатура. По ширине не гейтим — на узком,
        // но высоком экране большая кнопка правильна, она главная на экране.
        // Окно Windows не ниже 800 dp, поэтому там всегда 148.
        width: context.sg.isShort ? 116 : 148,
        height: context.sg.isShort ? 116 : 148,
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
                        // Значок ужимается, когда под ним появляется время:
                        // иначе пара «значок + таймер» не влезает в круг и
                        // обрезается по краям.
                        size: connected ? 56 : 68,
                        color: connected ? scheme.onPrimary : scheme.onSurface),
                    if (connected) const _UptimeLabel(),
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
  const _UptimeLabel();

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
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        format(d),
        textDirection: TextDirection.ltr,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
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
class _TrafficRow extends StatelessWidget {
  final TrafficStats stats;
  final int sessionUp;
  final int sessionDown;
  const _TrafficRow({
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
