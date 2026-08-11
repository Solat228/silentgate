import 'package:flutter/material.dart';

import '../../core/platform/platform_services.dart';

/// Человеческое имя приложения по ключу правила.
///
/// ## Зачем это понадобилось
///
/// Правило хранит только ключ: на Windows это путь к exe, на Android — имя
/// пакета. На Windows имя выводится из ключа само (`chrome.exe`), а на Android
/// вывести его неоткуда, и в списке правил стояло `com.google.android.youtube`
/// — причём ДВАЖДЫ, в имени и под ним. Иконка при этом подгружалась настоящая,
/// то есть пакет был опознан, и выглядело это просто как недоделка.
///
/// ⚠️ ПОЧЕМУ МЕТКА НЕ ХРАНИТСЯ В ПРАВИЛЕ. Записать её в `AppRule` при
/// добавлении соблазнительно, но подпись раздельного туннелирования
/// сравнивается целиком и решает, нужно ли ПЕРЕПОДКЛЮЧАТЬСЯ. Тогда заполнение
/// меток у старых правил рвало бы живой туннель, а смена языка телефона (метка
/// локализованная!) рвала бы его снова. Поэтому метка спрашивается на лету и
/// живёт только в памяти.
///
/// ⚠️ И ОТДЕЛЬНО: `AppRule.name` МЕНЯТЬ НЕЛЬЗЯ. Он не для показа — он уходит в
/// `process_name` конфига ядра. Подставь туда «Google Chrome» вместо
/// `chrome.exe`, и все правила «по имени» на Windows молча перестанут
/// срабатывать: правило видно, лежит в конфиге, ядро довольно, не применяется.
class AppLabel extends StatefulWidget {
  /// Ключ приложения: путь к exe (Windows) либо packageName (Android).
  final String path;

  /// Что показать, пока метки нет или её не удалось получить.
  final String fallback;
  final TextStyle? style;
  final int maxLines;

  const AppLabel({
    super.key,
    required this.path,
    required this.fallback,
    this.style,
    this.maxLines = 1,
  });

  @override
  State<AppLabel> createState() => _AppLabelState();
}

class _AppLabelState extends State<AppLabel> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AppLabel old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _label = null;
      _load();
    }
  }

  void _load() {
    if (!hasPlatformServices) return;
    final apps = platform.appCatalog;
    // Синхронно из кэша — иначе строка мигала бы именем пакета при каждой
    // прокрутке списка.
    final cached = apps.cachedLabel(widget.path);
    if (cached != null) {
      _label = cached;
      return;
    }
    final requested = widget.path;
    apps.labelFor(requested).then((name) {
      // Гвард: при быстрой смене ключа не подставляем чужое имя.
      if (mounted && widget.path == requested && name != null && name.isNotEmpty) {
        setState(() => _label = name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ Направление текста НЕ форсируем. Имя приложения — обычный человеческий
    // текст, и у арабского приложения принудительный LTR был бы уже дефектом.
    // Форс-LTR положен техническим строкам (пути, адреса), а не именам.
    return Text(
      _label ?? widget.fallback,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
