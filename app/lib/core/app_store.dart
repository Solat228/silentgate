import 'package:meta/meta.dart';

/// Откуда пришла эта копия приложения: с GitHub (и сайта) или из Google Play.
///
/// Это две СБОРКИ одного приложения (Gradle `productFlavors` в
/// `android/app/build.gradle.kts`): пакет, подпись и данные у них общие, и
/// они обновляют друг друга. Различаются только обновлением:
///
/// * [AppStore.github] — обновляется сама (подписанный манифест, закачка APK).
///   На Android при новой версии сначала предлагает Google Play, если он
///   установлен, и только потом — скачать APK.
/// * [AppStore.play] — обновляется ТОЛЬКО через Google Play. Правило Play
///   «Device and Network Abuse» запрещает приложению из Play обновлять себя
///   любым другим способом, поэтому проверки обновлений там нет вовсе.
///
/// * [AppStore.msstore] — Windows-сборка для Microsoft Store. Пакет MSIX
///   обновляет только Store (признак — идентификация пакета у процесса,
///   `PackageIdentity`); та же сборка вне пакета обновляется сама, как GitHub.
///   Данные устройства отправляет только с явного согласия человека (правило
///   Store 10.5.1; решение владельца 19.10.2026). Собирается с
///   `--dart-define=SILENTGATE_STORE=msstore`: флейворов у Flutter на Windows нет.
///
/// Windows и тесты собираются без флейвора — это [AppStore.github].
enum AppStore { github, play, msstore }

abstract final class AppStoreInfo {
  /// Имя флейвора: Flutter кладёт его в эту константу сам при
  /// `flutter build … --flavor <имя>`. Без флага — пустая строка.
  static const String flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  /// Магазин Windows-сборки: `--dart-define=SILENTGATE_STORE=msstore`.
  static const String storeDefine = String.fromEnvironment('SILENTGATE_STORE');

  /// Сборка по имени флейвора и [storeDefine]. Всё неизвестное — GitHub:
  /// ошибиться в эту сторону безопаснее, чем молча лишить сборку обновлений.
  static AppStore storeOf(String flavor, {String store = ''}) {
    if (flavor.trim().toLowerCase() == 'play') return AppStore.play;
    if (store.trim().toLowerCase() == 'msstore') return AppStore.msstore;
    return AppStore.github;
  }

  static AppStore get current => storeOf(flavor, store: storeDefine);

  /// Сборка без драйвера туннеля: `--dart-define=SILENTGATE_NO_TUN=true`.
  ///
  /// Установщик EXE для Microsoft Store (MS3, команда владельца 27.10.2026):
  /// правило 10.2.4.2 запрещает сторонние драйверы, а их несут `wintun.dll` и
  /// `sing-box.exe` (sing-tun встраивает wintun). Оба файла в поставку не
  /// кладутся, а интерфейс прячет всё, что без них не работает: TUN,
  /// смешанный режим, «Только прокси», раздельное туннелирование, порты
  /// выходов API и серверы hysteria2. Остаётся системный прокси через Xray.
  static const bool noTunDefine = bool.fromEnvironment('SILENTGATE_NO_TUN');

  /// Подмена [noTunDefine] для тестов интерфейса.
  @visibleForTesting
  static bool? tunAvailableOverride;

  /// В поставке есть TUN и sing-box. `false` только у сборки без драйвера.
  static bool get tunAvailable => tunAvailableOverride ?? !noTunDefine;

  static bool get isPlay => current == AppStore.play;

  /// Сборка спрашивает согласие на данные устройства (Play и Microsoft
  /// Store). Сборка GitHub только сообщает о них — см. `DeviceInfoConsent`.
  static bool asksDataConsent(AppStore store) =>
      store == AppStore.play || store == AppStore.msstore;

  /// Страница приложения в Google Play открыта всем (production).
  ///
  /// ⚠️ Пока это `false`, сборка GitHub НЕ предлагает обновиться через Play:
  /// на закрытом тесте страницу видят только тестировщики, остальным Play
  /// ответит «приложение не найдено». Переключить в `true` в выпуске,
  /// который выходит ПОСЛЕ публикации в Play.
  static const bool playListingLive = false;

  /// Пакет приложения — он же идентификатор страницы в Play.
  static const String packageName = 'lol.silentgate';

  /// «Загрузки и обновления» Microsoft Store. Страница самого приложения
  /// требует его ID в Store, а он известен только после публикации; этот
  /// экран обновляет пакет и без него.
  static const String msStoreUpdatesUri =
      'ms-windows-store://downloadsandupdates';

  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageName';

  /// Политика конфиденциальности. Её текст лежит на сайте
  /// (`docs/play/privacy-policy-*.md` в репозитории — исходник).
  static const String privacyPolicyUrl = 'https://silentgate.lol/privacy';
}
