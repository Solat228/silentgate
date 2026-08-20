import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/settings/split_tunnel.dart';
import '../../l10n/gen/app_localizations.dart';

/// Пометка правила «по пути», указывающего на несуществующий файл.
///
/// ⚠️ ЭТО НЕ УКРАШЕНИЕ, А ЗАКРЫТИЕ ДЫРЫ, ВОСПРОИЗВЕДЁННОЙ ОПЫТОМ (VM, 17.08.2026).
///
/// Программа обновилась, путь сменился (`…claude-code-2.1.228-win32…` →
/// `…2.1.233-win32…`) — и правило перестало совпадать. Замер на стенде:
/// по пути из правила трафик уходил «Прямо» и наружу шёл реальный адрес
/// `203.0.113.10`, а после переезда файла в логе ядра **не осталось ни одной
/// строки `match`** и тот же трафик ушёл в туннель (`185.130.226.42`).
///
/// Настройки при этом сообщали `enabled=True, action=direct` — то есть правило
/// выглядело совершенно здоровым. Владелец потерял время, разбираясь вслепую, и
/// решил, что сломано сопоставление по имени (оно исправно: в его же логе
/// `router: match process_name=Code.exe => route(proxy)`).
///
/// Тот же почерк, за который в этом проекте уже платили не раз: правило видно,
/// лежит в конфиге, выглядит рабочим — и не применяется. Ни компилятор, ни
/// `sing-box check` такого не ловят: конфиг валиден, просто ни с чем не совпадает.
class DeadPathBadge extends StatefulWidget {
  const DeadPathBadge({
    super.key,
    required this.rule,
    required this.onSwitchToName,
  });

  final AppRule rule;

  /// Перевести правило на сопоставление по имени файла. Для программ, у которых
  /// путь содержит версию, это единственный устойчивый вариант — проверено тем
  /// же опытом: `match process_name=myapp.exe => route(direct)` сработало при
  /// НАМЕРЕННО оставленном мёртвом пути в записи.
  final VoidCallback onSwitchToName;

  /// Проверять ли путь на этой платформе.
  ///
  /// ⚠️ На Android и iOS в `path` лежит ИМЯ ПАКЕТА, а не путь к файлу
  /// (`com.android.chrome`). Проверка существования файла там всегда давала бы
  /// «не найден» и пометила бы КАЖДОЕ правило — то есть предупреждение,
  /// кричащее всегда, а такое перестают замечать за день.
  static bool appliesOn() =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  State<DeadPathBadge> createState() => _DeadPathBadgeState();
}

class _DeadPathBadgeState extends State<DeadPathBadge> {
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    // В initState `setState` не зовём — состояние ещё не смонтировано.
    _missing = _isMissing(widget.rule);
  }

  /// Чистая проверка без побочных эффектов — её же зовёт [_check].
  static bool _isMissing(AppRule r) {
    if (r.byName || !DeadPathBadge.appliesOn() || r.path.trim().isEmpty) {
      return false;
    }
    try {
      return !File(r.path).existsSync();
    } catch (_) {
      // Нет доступа к каталогу — это не «файла нет». Ложная тревога здесь
      // дороже пропуска: чинить пользователю будет нечего.
      return false;
    }
  }

  @override
  void didUpdateWidget(covariant DeadPathBadge old) {
    super.didUpdateWidget(old);
    if (old.rule.path != widget.rule.path ||
        old.rule.byName != widget.rule.byName) {
      _check();
    }
  }

  /// ⚠️ ОБРАЩЕНИЕ К ДИСКУ — НЕ В `build`. Список правил перерисовывается на
  /// каждый кадр (галочки, чипы, наведение мыши), и проверка существования файла
  /// оттуда означала бы обращение к диску по числу правил каждый кадр. Считаем
  /// при появлении строки и при смене пути — то есть ровно тогда, когда ответ
  /// может измениться.
  ///
  /// ⚠️ ПРОВЕРКА СИНХРОННАЯ, И ЭТО ОСОЗНАННО. Асинхронная не успевала завершиться
  /// в виджет-тестах (`testWidgets` крутит фейковое время, и настоящий
  /// файловый ввод-вывод в нём не досчитывается) — страж был бы зелёным всегда,
  /// то есть не стерёг бы ничего. А цена синхронного вызова здесь ничтожна:
  /// одно обращение к диску на строку при её появлении, а не на каждый кадр.
  void _check() {
    final gone = _isMissing(widget.rule);
    if (gone != _missing) setState(() => _missing = gone);
  }

  @override
  Widget build(BuildContext context) {
    if (!_missing) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const Key('deadPathFix'),
      icon: Icon(Icons.report_problem_outlined, color: scheme.error),
      tooltip: '${l.splitDeadPath}\n${l.splitDeadPathFix}',
      onPressed: widget.onSwitchToName,
    );
  }
}
