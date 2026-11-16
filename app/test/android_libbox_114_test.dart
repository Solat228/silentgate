import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ПЕРЕХОД ANDROID НА LIBBOX 1.14.3 — ЧТО ОБЯЗАНО ОСТАТЬСЯ В KOTLIN.
///
/// В 1.14 библиотека поменяла интерфейс платформы в трёх местах, и каждое
/// из них ломается молча, а не при компиляции Dart:
///
/// - `Libbox.redirectStderr` удалён. Раньше он же перекладывал журнал ядра
///   прошлой сессии в `.old` и направлял туда текст паники Go. Теперь паника
///   пишется в `CrashReport-<источник>.log` рабочего каталога, и без своего
///   переноса (`rotateCoreLog`) аварийное падение ядра в отчёт не попадёт.
/// - Адреса DNS туннеля приходят итератором, а рядом появился режим DNS. При
///   режиме `disabled` ядро DNS не обслуживает, и вписывать его адрес в
///   туннель нельзя: система будет спрашивать резолвер, которого нет.
/// - `systemCertificates` убран из `PlatformInterface`, зато добавлены методы
///   SSH-оболочки, мостов и Tailscale. Мы их не используем, но обязаны
///   отвечать «не поддерживается», а не делать вид, что поддерживаем.
///
/// Страж читает исходник, потому что `flutter test` Kotlin не компилирует.
void main() {
  const svc = 'android/app/src/main/kotlin/lol/silentgate/vpn/SilentGateVpnService.kt';

  /// Текст без строк-комментариев: пояснения в коде упоминают удалённые
  /// вызовы по имени, и страж не должен ловить сам себя.
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join(String.fromCharCode(10));

  test('удалённые в 1.14 вызовы не используются', () {
    final src = code(svc);
    expect(src, isNot(contains('redirectStderr')));
    expect(src, isNot(contains('systemCertificates')));
  });

  test('паника ядра попадает в журнал прошлой сессии', () {
    final src = code(svc);
    expect(src, contains('fun rotateCoreLog('));
    expect(src, contains('crashReportSource = CRASH_SOURCE'));
    // Перенос обязан стоять ДО Libbox.setup: setup сам архивирует прежний
    // CrashReport, и после него читать было бы уже нечего.
    final rotate = src.indexOf('rotateCoreLog(coreLog');
    final setup = src.indexOf('Libbox.setup(');
    expect(rotate, greaterThan(0));
    expect(setup, greaterThan(rotate));
  });

  test('DNS туннеля учитывает режим ядра', () {
    final src = code(svc);
    expect(src, contains('Libbox.DNSModeDisabled'));
    expect(src, contains('dnsServerAddress?.forEach'));
  });

  test('возможности, которых у нас нет, честно выключены', () {
    final src = code(svc);
    expect(src, contains('override fun usePlatformShell(): Boolean = false'));
    expect(src, contains('override fun usePlatformBridge(): Boolean = false'));
    expect(src, contains('override fun triggerNativeCrash()'));
  });

  test('патч libbox без SSH-оболочки Tailscale лежит в репозитории', () {
    final patch = File('../engine/android/libbox-1.14.3-no-platform-shell.patch');
    expect(patch.existsSync(), isTrue);
    expect(patch.readAsStringSync(), contains('with_platform_shell'));
  });
}
