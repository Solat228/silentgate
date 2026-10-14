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
/// Windows и тесты собираются без флейвора — это [AppStore.github].
enum AppStore { github, play }

abstract final class AppStoreInfo {
  /// Имя флейвора: Flutter кладёт его в эту константу сам при
  /// `flutter build … --flavor <имя>`. Без флага — пустая строка.
  static const String flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  /// Сборка по имени флейвора. Всё, что не `play`, — GitHub: ошибиться в
  /// эту сторону безопаснее, чем молча лишить сборку обновлений.
  static AppStore storeOf(String flavor) =>
      flavor.trim().toLowerCase() == 'play' ? AppStore.play : AppStore.github;

  static AppStore get current => storeOf(flavor);

  static bool get isPlay => current == AppStore.play;

  /// Страница приложения в Google Play открыта всем (production).
  ///
  /// ⚠️ Пока это `false`, сборка GitHub НЕ предлагает обновиться через Play:
  /// на закрытом тесте страницу видят только тестировщики, остальным Play
  /// ответит «приложение не найдено». Переключить в `true` в выпуске,
  /// который выходит ПОСЛЕ публикации в Play.
  static const bool playListingLive = false;

  /// Пакет приложения — он же идентификатор страницы в Play.
  static const String packageName = 'lol.silentgate';

  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageName';

  /// Политика конфиденциальности. Её текст лежит на сайте
  /// (`docs/play/privacy-policy-*.md` в репозитории — исходник).
  static const String privacyPolicyUrl = 'https://silentgate.lol/privacy';
}
