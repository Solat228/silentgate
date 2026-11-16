import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/settings_backup.dart';
import 'settings_controller.dart';

/// Держит снимок свежим: резервная копия Google на Android (P11) и копия в
/// «Документах» у пакета Microsoft Store (`SettingsBackup.usesDocumentsCopy`).
///
/// Система копирует каталог снимка сама, примерно раз в сутки и когда
/// захочет, — поэтому снимок обязан быть актуальным в любой момент. Пишется
/// при уходе приложения в фон (после правок человек почти всегда сворачивает
/// приложение) и при смене выключателя «Сохранять подписки в резервной копии
/// Google» — выключили, и подписки уходят из снимка сразу, а не завтра.
/// Записи без изменений `SettingsBackup.writeSnapshot` пропускает сам.
///
/// Windows (пакет Store): окно почти всегда свёрнуто в трей, а удаляют
/// приложение из «Параметров», не закрывая его по-человечески, — поэтому
/// снимок пишется ещё и по таймеру ([period]). Подписки обновляются в фоне
/// без участия человека, и без таймера копия отставала бы на дни.
class BackupSnapshotKeeper with WidgetsBindingObserver {
  BackupSnapshotKeeper(this._settings);

  /// Как часто переписывать снимок на Windows.
  static const period = Duration(minutes: 10);

  final SettingsController _settings;
  bool? _lastIncludeSubs;
  Timer? _timer;

  /// Подключить там, где снимок ведётся (`SettingsBackup.keepsSnapshot`).
  /// Обычная установка Windows его не ведёт: там копия — экспорт файлом и
  /// галочка деинсталлятора.
  static BackupSnapshotKeeper attach(SettingsController settings,
      {bool periodic = false}) {
    final k = BackupSnapshotKeeper(settings);
    WidgetsBinding.instance.addObserver(k);
    settings.addListener(k._onSettings);
    unawaited(settings.whenLoaded.then((_) => k._write()));
    if (periodic) {
      k._timer = Timer.periodic(period, (_) => unawaited(k._write()));
    }
    return k;
  }

  void detach() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettings);
  }

  void _onSettings() {
    final now = _settings.settings.backupSubscriptionsToGoogle;
    if (_lastIncludeSubs != null && _lastIncludeSubs != now) {
      unawaited(_write());
    }
    _lastIncludeSubs = now;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_write());
    }
  }

  Future<void> _write() async {
    _lastIncludeSubs = _settings.settings.backupSubscriptionsToGoogle;
    await SettingsBackup.writeSnapshot(
        includeSubscriptions: _lastIncludeSubs!);
  }
}
