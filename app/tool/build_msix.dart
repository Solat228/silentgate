// Пакет MSIX для Microsoft Store из готовой Release-сборки Windows.
//
// Запуск из `app/` ПОСЛЕ Store-сборки (`build-msix.bat` делает всё сам):
//   dart run tool/build_msix.dart [--identity-name <имя>] [--publisher <CN=…>]
//       [--publisher-display-name <имя>] [--release <каталог>] [--out <каталог>]
//       [--sign-pfx <файл>] [--version <x.y.z> — только для стенда]
//
// Identity Name, Publisher, PublisherDisplayName и DisplayName (зарезервированное
// имя продукта) берутся из Partner Center (продукт → Product identity) и обязаны
// совпасть дословно; без --display-name настоящая идентификация не собирается. Без них пакет собирается с ТЕСТОВОЙ
// идентификацией (`SilentGate.Test`, `CN=SilentGateTest`) — для VM, не для
// Store; имя файла тогда кончается на `-test.msix`.
//
// Подпись нужна только для установки вне Store (VM): Store подписывает пакет
// сам. Пароль pfx — из переменной MSIX_PFX_PASSWORD, в вывод не печатается.
//
// Логика — `lib/core/update/msix_packaging.dart`, здесь процессы и файлы.
import 'dart:io';

import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/update/msix_packaging.dart';

const _sdk = r'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64';
const _testIdentity = 'SilentGate.Test';
const _testPublisher = 'CN=SilentGateTest';

Future<void> main(List<String> args) async {
  final opt = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (!args[i].startsWith('--')) _fail('Непонятный аргумент: ${args[i]}');
    opt[args[i].substring(2)] = args[i + 1];
  }
  if (args.length.isOdd) _fail('У аргумента ${args.last} нет значения');

  final sep = Platform.pathSeparator;
  final release = Directory(opt['release'] ??
      'build${sep}windows${sep}x64${sep}runner${sep}Release');
  final out = Directory(opt['out'] ?? 'build${sep}msix');
  final identity = opt['identity-name'] ?? _testIdentity;
  final publisher = opt['publisher'] ?? _testPublisher;
  final test = identity == _testIdentity || publisher == _testPublisher;
  // DisplayName обязан совпасть с зарезервированным именем продукта — пакет
  // с умолчанием «SilentGate» Store не примет (продукт зовётся SilentGateVPN).
  if (!test && opt['display-name'] == null) {
    _fail('Для Store нужен --display-name (имя продукта в Partner Center)');
  }
  if (!File('${release.path}${sep}silentgate.exe').existsSync()) {
    _fail('Нет ${release.path}${sep}silentgate.exe — сначала сборка Windows');
  }
  for (final core in ['xray.exe', 'sing-box.exe', 'wintun.dll']) {
    if (!File('${release.path}$sep$core').existsSync()) {
      _fail('В Release нет $core — сборка без ядер (build-exe.bat кладёт их)');
    }
  }

  final pubspec = File('pubspec.yaml').readAsStringSync();
  final ver = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec)
      ?.group(1);
  if (ver == null) _fail('Нет версии в pubspec.yaml');
  // --version — только для стенда (пакет «новее» для проверки обновления).
  final version = msixVersion(opt['version'] ?? ver);

  final stage = Directory('${out.path}${sep}stage');
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  stage.createSync(recursive: true);
  var copied = 0;
  for (final e in release.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = e.path.substring(release.path.length + 1);
    if (msixExcluded(rel)) continue;
    final dst = File('${stage.path}$sep$rel');
    dst.parent.createSync(recursive: true);
    e.copySync(dst.path);
    copied++;
  }
  final assets = Directory('..${sep}installer${sep}msix${sep}Assets');
  for (final e in assets.listSync().whereType<File>()) {
    final dst = File('${stage.path}${sep}Assets$sep${e.uri.pathSegments.last}');
    dst.parent.createSync(recursive: true);
    e.copySync(dst.path);
  }

  final template =
      File('..${sep}installer${sep}msix${sep}AppxManifest.xml').readAsStringSync();
  final manifest = renderMsixManifest(
    template,
    identityName: identity,
    publisher: publisher,
    publisherDisplayName: opt['publisher-display-name'] ?? 'SilentGate',
    displayName: opt['display-name'] ?? 'SilentGate',
    description: 'SilentGate VPN',
    version: version,
  );
  File('${stage.path}${sep}AppxManifest.xml').writeAsStringSync(manifest);
  stdout.writeln('Пакет: $identity $version, файлов $copied');

  final priConfig = '${out.path}${sep}priconfig.xml';
  await _run('$_sdk${sep}makepri.exe', [
    'createconfig', '/cf', priConfig, '/dq', 'en-US', '/pv', '10.0.0', '/o'
  ]);
  await _run('$_sdk${sep}makepri.exe', [
    'new', '/pr', stage.path, '/cf', priConfig,
    '/mn', '${stage.path}${sep}AppxManifest.xml',
    '/of', '${stage.path}${sep}resources.pri', '/o',
  ]);

  final name =
      'SilentGate-${version.substring(0, version.length - 2)}-msstore${test ? '-test' : ''}.msix';
  final msix = File('${out.path}$sep$name');
  await _run('$_sdk${sep}makeappx.exe',
      ['pack', '/d', stage.path, '/p', msix.path, '/o']);

  final pfx = opt['sign-pfx'];
  if (pfx != null) {
    final pass = Platform.environment['MSIX_PFX_PASSWORD'];
    if (pass == null) _fail('Для подписи нужен MSIX_PFX_PASSWORD');
    await _run('$_sdk${sep}signtool.exe',
        ['sign', '/fd', 'SHA256', '/f', pfx, '/p', pass, msix.path],
        shown: ['sign', '/fd', 'SHA256', '/f', pfx, '/p', '***', msix.path]);
  }

  stdout
    ..writeln('Готово: ${msix.absolute.path}')
    ..writeln('Размер: ${msix.lengthSync()} байт')
    ..writeln('SHA-256: ${await Sha256.ofFile(msix)}');
  if (test) {
    stdout.writeln('⚠️ ТЕСТОВАЯ идентификация — для VM, НЕ для Store');
  }
}

Future<void> _run(String exe, List<String> args, {List<String>? shown}) async {
  stdout.writeln('> ${exe.split(Platform.pathSeparator).last} '
      '${(shown ?? args).join(' ')}');
  final r = await Process.run(exe, args);
  if (r.exitCode != 0) {
    stderr
      ..write(r.stdout)
      ..write(r.stderr);
    _fail('${exe.split(Platform.pathSeparator).last} вернул ${r.exitCode}');
  }
}

Never _fail(String msg) {
  stderr.writeln('ОШИБКА: $msg');
  exit(1);
}
