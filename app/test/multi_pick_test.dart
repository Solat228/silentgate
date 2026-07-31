import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

/// Пакетное добавление приложений. Диалог выбора раньше отдавал ОДНО имя и
/// закрывался на первом тапе — пользователь отмечал несколько, добавлялось
/// одно. Из-за этого в правилах владельца не оказалось браузера, и в режиме
/// «только отмеченные» весь веб уходил мимо VPN.
void main() {
  /// Повторяет логику пакетного добавления из split_tunnel_screen.
  SplitTunnelConfig addAll(SplitTunnelConfig st, List<String> paths) {
    final apps = [...st.apps];
    final have = {for (final a in apps) a.path.toLowerCase()};
    for (final p in paths) {
      if (have.contains(p.toLowerCase())) continue;
      have.add(p.toLowerCase());
      apps.add(AppRule(p, byName: true, action: st.defaultAction));
    }
    return st.copyWith(apps: apps);
  }

  test('добавляются ВСЕ выбранные, а не первое', () {
    const st = SplitTunnelConfig(mode: SplitMode.onlySelected);
    final r = addAll(st, [
      r'C:\chrome.exe',
      r'C:\Telegram.exe',
      r'C:\Code.exe',
    ]);
    expect(r.apps, hasLength(3));
    expect(r.apps.map((a) => a.path), containsAll([
      r'C:\chrome.exe',
      r'C:\Telegram.exe',
      r'C:\Code.exe',
    ]));
  });

  test('уже добавленные не дублируются, регистр не обманывает', () {
    final st = addAll(
        const SplitTunnelConfig(mode: SplitMode.onlySelected), [r'C:\chrome.exe']);
    final r = addAll(st, [r'c:\CHROME.exe', r'C:\firefox.exe']);
    expect(r.apps, hasLength(2), reason: 'дубль по регистру не должен пройти');
  });

  test('действие берётся из режима: в «только отмеченные» это туннель', () {
    final r = addAll(
        const SplitTunnelConfig(mode: SplitMode.onlySelected), [r'C:\chrome.exe']);
    expect(r.apps.single.action, AppAction.tunnel,
        reason: 'иначе отмеченное приложение всё равно пойдёт мимо VPN');
  });

  test('пустой выбор ничего не меняет', () {
    const st = SplitTunnelConfig(mode: SplitMode.onlySelected);
    expect(addAll(st, const []).apps, isEmpty);
  });
}
