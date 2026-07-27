import 'dart:io';

import 'vpn_engine.dart';
import 'windows/windows_engine.dart';

/// Создаёт реализацию движка под текущую платформу.
///
/// Диспетчеризация рантайм-ная, а не через условные импорты: те различают
/// доступность библиотек (`dart.library.io`), а не операционную систему,
/// поэтому развести Windows и Android на этапе компиляции ими нельзя.
///
/// Android-ветка появится в фазе 3 (`android/android_engine.dart`) — до тех пор
/// там сознательно падаем с внятным текстом, а не отдаём заглушку: молчаливая
/// заглушка выглядела бы как «подключение просто не работает».
VpnEngine createVpnEngine() {
  if (Platform.isWindows) return WindowsEngine();
  throw UnsupportedError(
    'Движок для ${Platform.operatingSystem} ещё не реализован. '
    'Android — этап M7, см. docs/platforms/ANDROID.md.',
  );
}
