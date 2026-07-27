import 'dart:io';

import 'android/android_engine.dart';
import 'vpn_engine.dart';
import 'windows/windows_engine.dart';

/// Создаёт реализацию движка под текущую платформу.
///
/// Диспетчеризация рантайм-ная, а не через условные импорты: те различают
/// доступность библиотек (`dart.library.io`), а не операционную систему,
/// поэтому развести Windows и Android на этапе компиляции ими нельзя.
///
/// Android-движок пока каркасный: общая половина работает, датапуть (ядра +
/// `VpnService`) — задачи фаз 2–3. Подключение там честно сообщает, что не
/// реализовано, вместо молчаливого «Подключено» без туннеля.
VpnEngine createVpnEngine() {
  if (Platform.isWindows) return WindowsEngine();
  if (Platform.isAndroid) return AndroidEngine();
  throw UnsupportedError(
    'Движок для ${Platform.operatingSystem} ещё не реализован. '
    'Порядок платформ — docs/ROADMAP.md.',
  );
}
