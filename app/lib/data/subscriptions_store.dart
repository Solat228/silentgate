import 'dart:convert';
import 'dart:io';

import '../core/models/subscription_profile.dart';
import '../core/platform/app_paths.dart';

/// Что лежит на диске: список подписок и какая из них активна.
class SubscriptionsSnapshot {
  final List<SubscriptionProfile> items;
  final String? activeId;
  const SubscriptionsSnapshot(this.items, this.activeId);

  bool get isEmpty => items.isEmpty;
}

/// Хранилище подписок (`subscriptions.json`).
///
/// Отдельный файл, а не ключ в общем состоянии: подписок теперь несколько,
/// и каждая тянет за собой свой список серверов, карточку и логотип.
class SubscriptionsStore {
  static const _fileName = 'subscriptions.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<SubscriptionsSnapshot> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const SubscriptionsSnapshot([], null);
      final data = jsonDecode(await f.readAsString());
      if (data is! Map) return const SubscriptionsSnapshot([], null);
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => SubscriptionProfile.fromJson(m.cast<String, dynamic>()))
          .where((p) => p.url.isNotEmpty)
          .toList();
      return SubscriptionsSnapshot(items, data['activeId'] as String?);
    } catch (_) {
      return const SubscriptionsSnapshot([], null);
    }
  }

  Future<void> save(SubscriptionsSnapshot snapshot) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'activeId': snapshot.activeId,
        'items': snapshot.items.map((p) => p.toJson()).toList(),
      }));
    } catch (_) {}
  }
}
