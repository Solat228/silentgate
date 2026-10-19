import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/settings_backup.dart';
import 'settings_controller.dart';

/// Android: держит снимок для резервной копии Google свежим (P11).
///
/// Система копирует каталог снимка сама, примерно раз в сутки и когда
/// захочет, — поэтому снимок обязан быть актуальным в любой момент. Пишется
/// при уходе приложения в фон (после правок человек почти всегда сворачивает
/// приложение) и при смене выключателя «Сохранять подписки в резервной копии
/// Google» — выключили, и подписки уходят из снимка сразу, а не завтра.
/// Записи без изменений `SettingsBackup.writeSnapshot` пропускает сам.
class BackupSnapshotKeeper with WidgetsBindingObserver {
  BackupSnapshotKeeper(this._settings);

  final SettingsController _settings;
  bool? _lastIncludeSubs;

  /// Подключить. Только Android: на Windows копия — экспорт файлом и
  /// галочка деинсталлятора.
  static BackupSnapshotKeeper attach(SettingsController settings) {
    final k = BackupSnapshotKeeper(settings);
    WidgetsBinding.instance.addObserver(k);
    settings.addListener(k._onSettings);
    unawaited(settings.whenLoaded.then((_) => k._write()));
    return k;
  }

  void detach() {
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
