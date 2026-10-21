/// Сборка пакета MSIX для Microsoft Store: чистая логика без процессов.
///
/// Запускает `tool/build_msix.dart`; здесь то, что можно проверить тестом —
/// версия пакета, подстановка в манифест, что не едет в пакет.
library;

/// Языки пакета — те же, что у интерфейса (`supportedLanguages`). Store
/// сверяет их со страницами описания: коды нейтральные, как языки описаний в
/// Partner Center («Русский», «Китайский, упрощённое письмо»). Первый —
/// язык по умолчанию.
const msixLanguages = [
  'en-us',
  'ru',
  'es',
  'fr',
  'de',
  'pt',
  'tr',
  'ar',
  'fa',
  'zh-hans',
];

/// Версия пакета из версии `pubspec.yaml`: `1.17.0+90` → `1.17.0.0`.
///
/// ⚠️ Четвёртое число у пакетов Store обязано быть нулём — оно занято
/// под служебную нумерацию Store. Номер сборки (`+90`) в пакет не идёт.
String msixVersion(String pubspecVersion) {
  final core = pubspecVersion.split('+').first.split('-').first;
  final parts = core.split('.');
  if (parts.length != 3 || parts.any((p) => int.tryParse(p) == null)) {
    throw FormatException('Версия не вида x.y.z: $pubspecVersion');
  }
  return '$core.0';
}

/// Файлы Release, которые в пакет не идут: следы запуска exe из каталога
/// сборки (`*.bak` гео-баз) и `uninstall.bat` ZIP-версии — пакет удаляет
/// Windows, а `--cleanup` из пакета стёр бы данные мимо его логики.
bool msixExcluded(String relativePath) {
  final name = relativePath.replaceAll('\\', '/').split('/').last.toLowerCase();
  return name.endsWith('.bak') || name == 'uninstall.bat';
}

/// Подставить значения в шаблон `installer/msix/AppxManifest.xml`.
///
/// Неизвестная или пропущенная метка — ошибка, а не пустое место: пакет с
/// `{{PUBLISHER}}` в манифесте Store отвергнет уже после загрузки.
String renderMsixManifest(
  String template, {
  required String identityName,
  required String publisher,
  required String publisherDisplayName,
  required String displayName,
  required String description,
  required String version,
  List<String> languages = msixLanguages,
}) {
  final values = <String, String>{
    'IDENTITY_NAME': identityName,
    'PUBLISHER': publisher,
    'PUBLISHER_DISPLAY_NAME': publisherDisplayName,
    'DISPLAY_NAME': displayName,
    'DESCRIPTION': description,
    'VERSION': version,
    'LANGUAGES':
        languages.map((l) => '    <Resource Language="$l"/>').join('\n'),
  };
  // Метки внутри XML-комментария — пояснение, не подстановка.
  final body = template.replaceAll(RegExp(r'<!--[\s\S]*?-->\s*'), '');
  final out = body.replaceAllMapped(RegExp(r'\{\{([A-Z_]+)\}\}'), (m) {
    final v = values[m[1]];
    if (v == null) throw FormatException('Неизвестная метка {{${m[1]}}}');
    if (m[1] != 'LANGUAGES' && v.trim().isEmpty) {
      throw FormatException('Пустое значение {{${m[1]}}}');
    }
    return m[1] == 'LANGUAGES' ? v : _xmlAttr(v);
  });
  return out;
}

String _xmlAttr(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
