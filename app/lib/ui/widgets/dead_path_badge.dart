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
/// `***.***.***.***`, а после переезда файла в логе ядра **не осталось ни одной
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

  /// ⚠️ ПУТЬ С НОМЕРОМ ВЕРСИИ СЛОМАЕТСЯ ПРИ СЛЕДУЮЩЕМ ОБНОВЛЕНИИ.
  ///
  /// Прежняя пометка ждала, пока файл ИСЧЕЗНЕТ. Для программ, которые ставят
  /// каждую версию в свой каталог, это опоздание ровно на один цикл: пока
  /// стоит `…claude-code-2.1.238-win32-x64\…`, правило совпадает и выглядит
  /// исправным, а наутро программа обновилась — и оно молча перестало
  /// работать. Владелец 21.08.2026: «мне абсолютно похуй, с какой папки будет
  /// этот файл, ВСЕ файлы с этим именем должны быть найдены».
  ///
  /// Признак намеренно узкий — сегмент КАТАЛОГА, содержащий номер вида
  /// `<цифры>.<цифры>`:
  ///  * ловит `anthropic.claude-code-2.1.238-win32-x64`, `app-1.2.3`,
  ///    `Python3.10` — то есть ровно раскладку «версия в имени папки»;
  ///  * не трогает `Microsoft VS Code`, `Telegram Desktop`,
  ///    `Program Files (x86)` — эти программы обновляются на месте, и
  ///    предупреждение там было бы ложной тревогой.
  ///
  /// ⚠️ ИМЯ ФАЙЛА НЕ СМОТРИМ. `claude.exe` не меняется — меняется папка; а
  /// проверять имя значило бы ругаться на `python3.10.exe`, у которого путь
  /// как раз устойчив.
  ///
  /// ⚠️ РАЗДЕЛИТЕЛЬ — И ОБРАТНЫЙ СЛЭШ ТОЖЕ. Первая редакция этого разбора
  /// делила путь по `[\/]`, где `\/` — это экранированная косая черта, то есть
  /// обратный слэш в класс НЕ ПОПАДАЛ. На Windows путь не делился вовсе,
  /// сегментов выходило меньше двух, и функция всегда возвращала «нет» —
  /// проверка, которая никогда не срабатывает.
  static bool pathLooksVersioned(String path) {
    final p = path.trim();
    if (p.isEmpty) return false;
    final parts = p.split(RegExp(r'[\\/]'));
    if (parts.length < 2) return false;
    final dirs = parts.sublist(0, parts.length - 1);
    final version = RegExp(r'\d+\.\d+');
    for (final d in dirs) {
      if (version.hasMatch(d)) return true;
    }
    return false;
  }

  @override
  State<DeadPathBadge> createState() => _DeadPathBadgeState();
}

class _DeadPathBadgeState extends State<DeadPathBadge> {
  bool _missing = false;

  /// Путь ещё жив, но в нём номер версии — сломается при обновлении.
  bool _fragile = false;

  @override
  void initState() {
    super.initState();
    // В initState `setState` не зовём — состояние ещё не смонтировано.
    _missing = _isMissing(widget.rule);
    _fragile = _isFragile(widget.rule);
  }

  /// ⚠️ ТОЛЬКО КОГДА ФАЙЛ НА МЕСТЕ. Исчезнувший путь — уже не предупреждение о
  /// будущем, а поломка сейчас, и говорить о ней надо строже: пометки не
  /// складываются, старшая вытесняет младшую.
  static bool _isFragile(AppRule r) {
    if (r.byName || !DeadPathBadge.appliesOn() || r.path.trim().isEmpty) {
      return false;
    }
    if (_isMissing(r)) return false;
    return DeadPathBadge.pathLooksVersioned(r.path);
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
    final fragile = _isFragile(widget.rule);
    if (gone != _missing || fragile != _fragile) {
      setState(() {
        _missing = gone;
        _fragile = fragile;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_missing && !_fragile) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // ⚠️ Порядок важен: сломанное сейчас старше того, что сломается завтра.
    // Две пометки на одной строке спорили бы за место и за внимание.
    final broken = _missing;
    return IconButton(
      key: Key(broken ? 'deadPathFix' : 'fragilePathFix'),
      icon: Icon(
        broken ? Icons.report_problem_outlined : Icons.update_disabled,
        color: broken ? scheme.error : scheme.tertiary,
      ),
      tooltip: broken
          ? '${l.splitDeadPath}\n${l.splitDeadPathFix}'
          : '${l.splitVersionedPath}\n${l.splitDeadPathFix}',
      onPressed: widget.onSwitchToName,
    );
  }
}
