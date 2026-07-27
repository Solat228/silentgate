package lol.silentgate

import io.flutter.embedding.android.FlutterActivity

/// Единственная Activity приложения.
///
/// ⚠️ По решению 4а (`docs/platforms/ANDROID.md`) на фазе 3 она обязана
/// переиспользовать КЭШИРОВАННЫЙ `FlutterEngine` из `FlutterEngineCache`,
/// а не создавать свой: иначе появится второй Dart-изолят, а с ним гонка
/// записи в хранилища и смерть автопереподключения при свайпе UI.
class MainActivity : FlutterActivity()
