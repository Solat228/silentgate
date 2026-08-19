import 'dart:async';
import 'dart:io';

import '../engine/probe_factory.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'api_screen.dart';
import '../core/app_info.dart';
import '../core/i18n/enum_labels.dart';
import '../l10n/gen/app_localizations.dart';
import '../core/platform/device_id.dart';
import '../core/platform/interference_scanner.dart';
import '../core/platform/network_recovery.dart';
import '../core/platform/app_launcher.dart';
import '../core/platform/vpn_lockdown.dart';
import '../core/net/speed_test.dart';
import '../core/update/app_update.dart';
import '../core/models/vpn_server.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/subscription/subscription_service.dart';
import '../core/platform/platform_services.dart';
import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'logs_screen.dart';
import 'split_tunnel_screen.dart';
import 'geo_bases_screen.dart';
import 'tun_settings_screen.dart';
import 'url_schemes_screen.dart';
import 'widgets/app_toast.dart';
import 'widgets/geo_bases_section.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/sel_text.dart';
import 'widgets/language_button.dart';
import 'widgets/selection_outline.dart';
import 'widgets/service_checks_row.dart';
import 'widgets/site_favicon.dart';
import 'widgets/speed_traffic_note.dart';
import 'widgets/subscription_avatar.dart';

/// Глобальный ключ раздела «Поддержка» — чтобы «перекинуть» сюда по кнопке
/// «Поддержка» из любого места (карточка подписки и т.п.) и прокрутить.
final GlobalKey supportSectionKey = GlobalKey();

/// Якорь строки гео-баз: на неё ведёт плашка с главного экрана.
final GlobalKey geoAssetsKey = GlobalKey();

class SettingsScreen extends StatefulWidget {
  /// Открыть настройки и сразу прокрутить к разделу «Поддержка».
  final bool scrollToSupport;

  /// Открыть настройки и подвести к строке гео-баз. Нужно плашке с главного
  /// экрана: сказать «скачайте в настройках» и бросить искать самому — то же
  /// самое, что промолчать.
  final bool scrollToGeo;
  const SettingsScreen(
      {super.key, this.scrollToSupport = false, this.scrollToGeo = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _scroll = ScrollController();

  /// Строка поиска по настройкам. Живёт только в памяти: сохранённый запрос
  /// означал бы, что человек открывает настройки и видит их наполовину
  /// спрятанными без понятной причины.
  final _search = TextEditingController();
  String _query = '';

  /// Развернуть раздел, если он свёрнут.
  ///
  /// Нужно переходам «извне»: плашка гео-баз и кнопка поддержки ведут в
  /// КОНКРЕТНУЮ строку, а свёрнутый раздел её не строит вовсе — переход молча
  /// приводил бы в никуда.
  Future<void> _ensureExpanded(String id) async {
    final controller = context.read<SettingsController>();
    if (!controller.settings.collapsedSections.contains(id)) return;
    await controller.update((s) => s.copyWith(
        collapsedSections:
            s.collapsedSections.where((e) => e != id).toList()));
  }

  @override
  void initState() {
    super.initState();
    if (widget.scrollToSupport) {
      // Раздел «Поддержка» — внизу: мотаем страницу вниз и сразу показываем
      // всплывающее окно поддержки (как будто пользователь сам нажал кнопку).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _ensureExpanded(SettingsSectionIds.about);
        if (_scroll.hasClients) {
          await _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
        }
        if (mounted) await _support(context);
      });
    }
    if (widget.scrollToGeo) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Строка гео-баз живёт в разделе «Захват трафика»: свёрнутым он её не
        // строит, и `ensureVisible` не находил бы ничего.
        await _ensureExpanded(SettingsSectionIds.capture);
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        final ctx = geoAssetsKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              alignment: 0.3);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
        // Переключатель языка — отдельно в шапке (флаг + значок перевода).
        actions: const [LanguageButton()],
        // Поиск — прямой ответ на жалобу «как искать версию непонятно».
        // Он в шапке, а не строкой списка: искать начинают до того, как
        // прокрутят, и поле должно быть видно сразу.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: l.settingsSearchHint,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.commonClear,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: SettingsBody(
        sections: buildSettingsSections(context, s, controller),
        query: _query,
        collapsed: s.collapsedSections.toSet(),
        onToggleSection: (id) {
          final next = s.collapsedSections.toList();
          next.contains(id) ? next.remove(id) : next.add(id);
          controller.update((st) => st.copyWith(collapsedSections: next));
        },
        scrollController: _scroll,
      ),
    );
  }
}

// ── Каркас экрана настроек ───────────────────────────────────────────────────

/// Идентификаторы разделов. ⚠️ СТАБИЛЬНЫЕ СТРОКИ: они ложатся на диск
/// (`AppSettings.collapsedSections`), поэтому переименование здесь молча
/// «развернёт» раздел у всех, кто его свернул.
abstract final class SettingsSectionIds {
  static const appearance = 'appearance';
  static const capture = 'capture';
  static const reliability = 'reliability';

  /// Бесшовность — три отдельных переключателя.
  ///
  /// ⚠️ СВОЙ РАЗДЕЛ, А НЕ ХВОСТ «НАДЁЖНОСТИ». Требование владельца — уметь
  /// быстро сказать, КОТОРАЯ из трёх правок сломала туннель; смешанные с
  /// автопереподключением и kill switch, они читались бы как одна общая
  /// «надёжность», и на вопрос «что выключить» ответа бы не нашлось.
  static const seamless = 'seamless';
  static const ping = 'ping';

  /// Проверка сервисов при подключении (чипы под кнопкой Connect).
  static const checks = 'checks';

  /// Автонастройка: сколько серверов мерить скоростью и сколько кандидатов
  /// проверять разом.
  static const autotune = 'autotune';
  static const identity = 'identity';
  static const network = 'network';
  static const api = 'api';
  static const about = 'about';
}

/// Максимальная ширина содержимого настроек.
///
/// ⚠️ ЗАЧЕМ ОГРАНИЧЕНИЕ ВООБЩЕ. До него ширины не было вовсе, и на широком
/// окне Windows подпись тянулась через весь экран, а переключатель уезжал к
/// правому краю — глазу не за что зацепиться, связь «подпись ↔ тумблер»
/// теряется. 760 — примерно 90 символов в строке, верхняя граница читаемости.
const double kSettingsContentMaxWidth = 760;

/// Сколько держится рамка вокруг раздела, к которому только что перешли.
///
/// ⚠️ ЭТО ПОДСКАЗКА «ВОТ КУДА ТЫ ПРИЕХАЛ», А НЕ СОСТОЯНИЕ. Постоянная рамка
/// вокруг блока спорила бы с пометкой в боковом меню (та и означает «ты
/// здесь») и через минуту работы перестала бы что-либо значить — глаз
/// перестаёт замечать то, что не меняется. Поэтому она гаснет сама.
///
/// Три секунды набраны из наблюдаемых величин, а не «на глаз»: прокрутка к
/// разделу идёт 280 мс, сама линия чертится 420 мс ([SelectionOutline]), то
/// есть полностью замкнутой рамка становится примерно через 0,7 с после
/// нажатия. Остаётся больше двух секунд на то, чтобы её заметить, — и столько
/// же занимает обратный ход, так что исчезновение читается как движение, а не
/// как мигание.
const Duration kSettingsHighlightHold = Duration(seconds: 3);

/// С какой ширины показываем боковое меню разделов.
///
/// ⚠️ ВЫШЕ, чем `SgWidth.expanded` (840). Меню съедает 240 dp, и на 840
/// содержимому осталось бы 600 — уже, чем на телефоне в ландшафте. Порог
/// подобран так, чтобы содержимое не сужалось ощутимо: 900 − 240 = 660.
const double kSettingsSidebarMinWidth = 900;

/// Строка настроек, участвующая в поиске.
///
/// ⚠️ Виджет строится ЛЕНИВО (`build`), а не передаётся готовым. Причина не в
/// экономии: строки скрытого поиском или свёрнутого раздела не должны вообще
/// создаваться — иначе раздел «О программе» на каждый ввод буквы в поиске
/// заново спрашивал бы версию ядра у диска, а раздел API — состояние портов.
class SettingsRow {
  /// Текст, по которому ищем: заголовок плюс подпись, как их видит человек.
  final String search;
  final WidgetBuilder build;

  const SettingsRow({required this.search, required this.build});
}

/// Раздел настроек как ДАННЫЕ — чтобы каркас (ширина, меню, сворачивание,
/// поиск) не знал ничего о содержимом, а содержимое — о раскладке.
class SettingsSectionData {
  final String id;
  final String title;
  final IconData icon;
  final List<SettingsRow> rows;

  /// Раздел рисует заголовок сам.
  ///
  /// ⚠️ ВРЕМЕННОЕ ИСКЛЮЧЕНИЕ ДЛЯ `_ApiSection`: он переезжает на отдельный
  /// экран отдельной задачей, и трогать его содержимое здесь нельзя. Без флага
  /// заголовок нарисовался бы дважды.
  final bool ownHeader;

  const SettingsSectionData({
    required this.id,
    required this.title,
    required this.icon,
    required this.rows,
    this.ownHeader = false,
  });
}

/// Приведение к виду, пригодному для сравнения: регистр и «ё».
///
/// ⚠️ «ё» → «е» не украшательство: половина клавиатур её не ставит, и поиск
/// «надежность» не нашёл бы «Надёжность соединения» — то есть ровно тот раздел,
/// который человек и искал.
String _searchNorm(String s) => s.toLowerCase().replaceAll('ё', 'е');

/// Оставить только то, что подходит под запрос.
///
/// Раздел, чей ЗАГОЛОВОК подошёл, остаётся целиком: спросили «пинг» — логично
/// увидеть весь раздел «Пинг», а не одну строку из него.
List<SettingsSectionData> filterSettingsSections(
    List<SettingsSectionData> sections, String query) {
  final q = _searchNorm(query.trim());
  if (q.isEmpty) return sections;
  final out = <SettingsSectionData>[];
  for (final s in sections) {
    if (_searchNorm(s.title).contains(q)) {
      out.add(s);
      continue;
    }
    final rows =
        s.rows.where((r) => _searchNorm(r.search).contains(q)).toList();
    if (rows.isEmpty) continue;
    out.add(SettingsSectionData(
      id: s.id,
      title: s.title,
      icon: s.icon,
      rows: rows,
      ownHeader: s.ownHeader,
    ));
  }
  return out;
}

/// Каркас: ограниченная по ширине колонка разделов плюс боковое меню на
/// широком окне.
class SettingsBody extends StatefulWidget {
  const SettingsBody({
    super.key,
    required this.sections,
    required this.collapsed,
    required this.onToggleSection,
    this.query = '',
    this.scrollController,
  });

  final List<SettingsSectionData> sections;

  /// Идентификаторы свёрнутых разделов.
  final Set<String> collapsed;
  final ValueChanged<String> onToggleSection;
  final String query;
  final ScrollController? scrollController;

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  /// Якоря разделов для бокового меню. Ключи стабильны по идентификатору
  /// раздела: пересоздавать их на каждый кадр значило бы терять позицию.
  final _anchors = <String, GlobalKey>{};

  GlobalKey _anchor(String id) => _anchors.putIfAbsent(id, () => GlobalKey());

  /// Раздел, выбранный в боковом меню. Помечается в самом меню и держится до
  /// следующего выбора — это ответ на вопрос «где я сейчас».
  String? _activeId;

  /// Раздел, вокруг КОТОРОГО СЕЙЧАС ГОРИТ РАМКА, — это другое: она отвечает на
  /// вопрос «куда меня перенесло» и гаснет через [kSettingsHighlightHold].
  ///
  /// ⚠️ ПОЧЕМУ ДВА ПОЛЯ, А НЕ ОДНО. Владелец просил обводить сам блок раздела
  /// («на скриншоте обвёл блок „О программе“ целиком») и отдельно — оставить
  /// полосу в боковом меню как есть. Гаси мы `_activeId`, вместе с рамкой
  /// пропала бы и пометка в меню, то есть отметка «ты здесь».
  String? _highlightId;
  Timer? _highlightTimer;

  @override
  void dispose() {
    // Без отмены таймер доживает до `setState` на снятом виджете (в тестах это
    // ещё и «A Timer is still pending» на выходе).
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _jumpTo(SettingsSectionData s) async {
    _highlightTimer?.cancel();
    setState(() {
      _activeId = s.id;
      _highlightId = s.id;
    });
    // Свёрнутый раздел разворачиваем: иначе меню приводит к пустому месту.
    if (widget.collapsed.contains(s.id)) widget.onToggleSection(s.id);
    // Ждём кадр: раздел мог только что развернуться, и его высота ещё не
    // посчитана — прицел по старой раскладке промахнулся бы.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      final ctx = _anchor(s.id).currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: 0.0);
      }
    }
    // ⚠️ Отсчёт заводится ПОСЛЕ прокрутки и на ЛЮБОМ пути — в том числе когда
    // цели не нашлось. Ранний `return` посреди метода оставил бы рамку гореть
    // вечно, а это ровно то состояние, которого здесь быть не должно.
    if (!mounted) return;
    _highlightTimer = Timer(kSettingsHighlightHold, () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final searching = widget.query.trim().isNotEmpty;
    final visible = filterSettingsSections(widget.sections, widget.query);

    final content = visible.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(l.settingsSearchEmpty(widget.query.trim()),
                  textAlign: TextAlign.center),
            ),
          )
        // ⚠️ РАЗДЕЛЫ СТРОЯТСЯ ВСЕ СРАЗУ, И ЭТО ОСОЗНАННО. Раньше здесь был
        // ленивый `ListView.separated`, и переход из бокового меню работал
        // рвано: `Scrollable.ensureVisible` целится в виджет по `GlobalKey`, а
        // у неё есть контекст ТОЛЬКО если элемент уже построен. Близкие разделы
        // ехали ступенями — список достраивался прямо во время анимации, и цель
        // уползала; дальние не ехали ВОВСЕ — `currentContext` был null, и метод
        // молча выходил. Владелец описал это как «переключение ступенчатое,
        // очень странно и неприятно».
        //
        // Разделов девять, строки внутри свёрнутых и отфильтрованных всё равно
        // не создаются (ленивость осталась там, где она что-то экономит), так
        // что цена — незаметна, а прокрутка становится ровной и попадает
        // с первого раза.
        : SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const Divider(),
                  Builder(builder: (context) {
                    final s = visible[i];
                    // ⚠️ ПРИ ПОИСКЕ СВЁРНУТОСТЬ ИГНОРИРУЕТСЯ. Иначе найденная
                    // строка лежала бы в свёрнутом разделе и человек видел бы
                    // пустой результат при непустом совпадении — худший исход
                    // из возможных.
                    final collapsed =
                        !searching && widget.collapsed.contains(s.id);
                    // ⚠️ ОБВОДИТСЯ БЛОК РАЗДЕЛА, А НЕ ПУНКТ МЕНЮ. Просьба
                    // владельца, повторённая дважды: после перехода из левого
                    // меню подсвечивался только сам пункт, и глаз оставался
                    // слева, хотя содержимое уехало справа. Рамка — тот же
                    // виджет, что у выбранного сервера и у пункта меню
                    // (`SelectionOutline`): три копии одной анимации разошлись
                    // бы на первой правке цвета.
                    //
                    // Отступ внутрь — чтобы линия не ложилась на `Divider`
                    // между разделами и не читалась как его утолщение.
                    return SelectionOutline(
                      selected: s.id == _highlightId,
                      radius: 12,
                      inset: 3,
                      child: Column(
                        key: _anchor(s.id),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!s.ownHeader)
                            _SectionHeader(
                              title: s.title,
                              collapsed: collapsed,
                              // Во время поиска сворачивать нечего — заголовок
                              // не должен обещать действие, которое ни на что
                              // не влияет.
                              onTap: searching
                                  ? null
                                  : () => widget.onToggleSection(s.id),
                            ),
                          if (!collapsed)
                            for (final r in s.rows) r.build(context),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          );

    final centered = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kSettingsContentMaxWidth),
        child: content,
      ),
    );

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < kSettingsSidebarMinWidth) return centered;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 240,
            child: ListView(
              key: const ValueKey('settings-rail'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final s in visible)
                  SettingsRailTile(
                    section: s,
                    selected: s.id == _activeId,
                    onTap: () => _jumpTo(s),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: centered),
        ],
      );
    });
  }
}

/// Заголовок раздела: он же кнопка «свернуть/развернуть».
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.collapsed,
    this.onTap,
  });

  final String title;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final head = _sectionHeader(context, title);
    if (onTap == null) return head;
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: head),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: collapsed ? l.settingsExpand : l.settingsCollapse,
              child: Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                  size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// Разделы настроек как данные. Порядок — тот же, что был у списка.
///
/// ⚠️ Строки собираются здесь, а виджеты строятся лениво (см. [SettingsRow]),
/// поэтому вызов сам по себе ничего не запускает: ни версии ядра, ни состояние
/// портов API. На это опирается тест поиска.
List<SettingsSectionData> buildSettingsSections(
    BuildContext context, AppSettings s, SettingsController controller) {
  final l = AppLocalizations.of(context);
  return [
    SettingsSectionData(
      id: SettingsSectionIds.appearance,
      title: l.sectionAppearance,
      icon: Icons.palette_outlined,
      rows: _appearanceRows(l, s, controller),
    ),
    SettingsSectionData(
      id: SettingsSectionIds.capture,
      title: l.sectionCapture,
      icon: Icons.alt_route,
      rows: _captureRows(l, s, controller),
    ),
    SettingsSectionData(
      id: SettingsSectionIds.reliability,
      title: l.sectionReliability,
      icon: Icons.shield_outlined,
      rows: _reliabilityRows(l, s, controller),
    ),
    SettingsSectionData(
      id: SettingsSectionIds.seamless,
      title: l.settingsSectionSeamless,
      icon: Icons.swap_horizontal_circle_outlined,
      rows: _seamlessRows(l, s, controller),
    ),
    SettingsSectionData(
      id: SettingsSectionIds.ping,
      title: l.sectionPing,
      icon: Icons.network_ping,
      rows: _pingRows(l, s, controller),
    ),
    SettingsSectionData(
      id: SettingsSectionIds.checks,
      title: l.settingsSectionChecks,
      icon: Icons.fact_check_outlined,
      rows: _connectCheckRows(l, s, controller),
    ),
    // ⚠️ ГЕЙТ ПО `autoConfigSupported`, А НЕ ПО ПЛАТФОРМЕ «НА ГЛАЗОК».
    // Автонастройка работает там, где харнесс умеет ПРОПУСКАТЬ запросы через
    // кандидата (`ProbeHarness.supportsProxyRequests`), то есть сегодня только
    // на Windows. Показать на Android «сколько серверов мерить скоростью» и
    // «сколько проверок разом» значило бы дать крутить ручки прогона, который
    // там не начнётся никогда, — ровно та обманка, за которую с экранов
    // Android уже убирали права, строгую маршрутизацию и тумблеры URL-схем.
    if (autoConfigSupported)
      SettingsSectionData(
        id: SettingsSectionIds.autotune,
        title: l.settingsSectionAutotune,
        icon: Icons.speed,
        rows: _autotuneRows(l, s, controller),
      ),
    SettingsSectionData(
      id: SettingsSectionIds.identity,
      title: l.sectionIdentity,
      icon: Icons.badge_outlined,
      rows: _identityRows(l),
    ),
    // «Восстановление сети» и «проверка помех» — про netsh, чужие
    // TUN-адаптеры и системный прокси Windows. На Android ни одного из
    // этих понятий нет: туннель рвётся системой сам, а перечислять чужие
    // процессы приложение не может.
    if (!Platform.isAndroid)
      SettingsSectionData(
        id: SettingsSectionIds.network,
        title: l.sectionNetwork,
        icon: Icons.lan_outlined,
        rows: _networkRows(l),
      ),
    // Локальный API для скриптов (Python и т.п.). Работает ТОЛЬКО на
    // Windows — на Android слушатель не поднимается (см.
    // `AppState.applyApiSettings`), и видимый раздел, который ничего
    // не делает, был бы обманом.
    if (Platform.isWindows)
      SettingsSectionData(
        id: SettingsSectionIds.api,
        title: l.apiSectionTitle,
        icon: Icons.terminal,
        ownHeader: true,
        rows: [
          SettingsRow(
            search: '${l.apiSectionTitle} ${l.apiSectionSub}',
            // ⚠️ Раздел переехал на СВОЙ экран (`ui/api_screen.dart`): он
            // занимал настройки целиком — тумблер, токен, таблица портов и
            // список серверов с чекбоксами. Здесь остаётся одна строка со
            // стрелкой, ровно как у URL-схем.
            build: (_) => ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(l.apiSectionTitle),
              subtitle: Text(l.apiSectionSub),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ApiScreen()),
              ),
            ),
          ),
        ],
      ),
    // «URL-схемы» переехали в раздел «Представление панели» (как приложение
    // общается с панелью), «Логи» — к «Поддержке» (внутри «О программе»).
    SettingsSectionData(
      id: SettingsSectionIds.about,
      title: l.sectionAbout,
      icon: Icons.info_outline,
      rows: _aboutRows(l),
    ),
  ];
}

// ── Надёжность соединения ────────────────────────────────────────────────────
List<SettingsRow> _reliabilityRows(
    AppLocalizations l, AppSettings settings, SettingsController controller) {
  return [
    SettingsRow(
      search: '${l.autoReconnectTitle} ${l.autoReconnectSub}',
      build: (context) => SwitchListTile(
          value: settings.autoReconnect,
          onChanged: (v) => controller.update((s) => s.copyWith(
                autoReconnect: v,
                // Kill switch без автопереподключения оставил бы трафик
                // заблокированным навсегда — гасим вместе. Вместе с ним гасим и
                // зависимый noRealIp: иначе он оставался включённым, продолжал
                // действовать и при этом ИСЧЕЗАЛ из настроек — снять его было
                // нечем.
                killSwitch: v ? s.killSwitch : false,
                noRealIp: v ? s.noRealIp : false,
              )),
          title: Row(children: [
            Expanded(child: Text(l.autoReconnectTitle)),
            InfoTooltip(l.infoAutoReconnect, title: l.autoReconnectTitle),
          ]),
          subtitle: Text(l.autoReconnectSub),
        ),
    ),
    // ⚠️ В режиме «Только прокси» kill switch смысла не имеет
    // (`AppSettings.killSwitchApplies`): удерживать он может только
    // трафик МАШИНЫ, а в этом режиме машина и так ходит мимо туннеля.
    // Тумблер, который виден и ничего не делает, хуже отсутствующего.
    if (settings.killSwitchApplies)
      SettingsRow(
        search: '${l.killSwitchTitle} ${l.killSwitchSubTun}',
        build: (context) => SwitchListTile(
            value: settings.killSwitch,
            // Без автопереподключения восстанавливать нечего — переключатель неактивен.
            onChanged: settings.autoReconnect
                ? (v) {
                    controller.update((s) =>
                        s.copyWith(killSwitch: v, noRealIp: v ? s.noRealIp : false));
                    // ⚠️ Системный always-on НАДЁЖНЕЕ нашего kill switch и об этом
                    // надо сказать в момент, когда человек о защите и думает.
                    // Наш работает, только пока живо приложение; системный держит
                    // блокировку и когда оно убито, и при обновлении, и до первого
                    // запуска после перезагрузки. Предлагаем один раз, при
                    // включении, и не навязываем — просто открываем нужный экран.
                    if (v && Platform.isAndroid) _offerAlwaysOn(context);
                  }
                : null,
            title: Row(children: [
              Expanded(child: Text(l.killSwitchTitle)),
              InfoTooltip(l.infoKillSwitch, title: l.killSwitchTitle),
            ]),
            // ⚠️ В РЕЖИМЕ СИСТЕМНОГО ПРОКСИ ЭТО НЕ БЛОКИРОВКА, И ТЕПЕРЬ ТАК И
            // НАПИСАНО. Настоящая блокировка требует прав администратора
            // (фильтры), а в этом режиме их не берут вовсе: всё удержание —
            // это оставленный в реестре прокси. Программа, которая прокси
            // игнорирует, и весь UDP уходят напрямую. Прежняя подпись
            // («защищает только приложения, уважающие прокси») говорила о
            // границе, но не говорила, что герметичности нет в принципе.
            subtitle: Text(
              settings.autoReconnect
                  ? (settings.captureMode == CaptureMode.tun
                      ? l.killSwitchSubTun
                      : l.killSwitchSubProxyNoAdmin)
                  : l.killSwitchSubOff,
            ),
          ),
      ),
    // ⚠️ ЧЕГО KILL SWITCH НЕ УМЕЕТ ВООБЩЕ — ПРАВИЛА ПО САЙТАМ. Он удерживает
    // ЗАХВАТ, то есть работает по программам; домены разбирает ядро, а на
    // время восстановления ядра нет. Условие спрашиваем у общей чистой функции
    // (`splitHonestyWarnings`), чтобы экран настроек и экран правил не
    // разъехались в том, что считают правдой.
    if (splitHonestyWarnings(settings).contains(SplitHonesty.killSwitchIsPerApp))
      SettingsRow(
        search: '${l.killSwitchTitle} ${l.splitKillSwitchIsPerApp}',
        build: (context) => Padding(
          key: const Key('killSwitchIsPerAppNote'),
          padding: const EdgeInsetsDirectional.fromSTEB(72, 0, 16, 12),
          child: Text(l.splitKillSwitchIsPerApp,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    // Выход из положения рядом с оговоркой: сказать «полностью держит только
    // TUN» и оставить человека искать переключатель — то же самое, что
    // промолчать. Кнопка ведёт через `_enableTun`, то есть вместе с разовой
    // настройкой запуска без UAC.
    // ⚠️ СПРАШИВАЕМ ОБЩИЙ КОД, А НЕ РАЗБИРАЕМ УСЛОВИЕ ЗАНОВО. Здесь стоял свой
    // предикат, и он уже разошёлся с тем, что считает `splitHonestyWarnings`.
    // Два независимых ответа на один вопрос — это всегда расхождение, вопрос
    // только когда; тот же урок в проекте уже записан про разрешение и
    // исполнение url-схем.
    if (splitHonestyWarnings(settings)
        .contains(SplitHonesty.killSwitchWeakInSystemProxy))
      SettingsRow(
        search: '${l.killSwitchTitle} ${l.killSwitchOfferTun}',
        build: (context) => ListTile(
          key: const Key('killSwitchOfferTun'),
          dense: true,
          leading: Icon(Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error),
          title: Text(l.killSwitchOfferTun),
          trailing: TextButton(
            key: const Key('killSwitchOfferTunButton'),
            onPressed: () => _enableTun(context, controller),
            child: Text(l.splitEnableTun),
          ),
        ),
      ),
    // Системный Always-on — надёжнее любого нашего kill switch: он держит
    // блокировку и когда приложение убито, и во время обновления, и до
    // первого запуска после перезагрузки. Наш собственный закрывает только
    // окно между попытками переподключения, поэтому они дополняют друг
    // друга, а не заменяют.
    // Раскладка уведомления. Переключатель заводился временным — на время
    // сравнения двух вариантов на живом телефоне; выбор сделан, и он стал
    // постоянной настройкой.
    if (Platform.isAndroid)
      SettingsRow(
        search: '${l.notifCompactTitle} ${l.notifCompactSub}',
        build: (context) => SwitchListTile(
            value: settings.compactNotification,
            onChanged: (v) async {
              final state = context.read<AppState>();
              // Ждём запись: без await следующая строка читала бы прежнее
              // значение, и раскладка не менялась бы вовсе.
              await controller.update((s) => s.copyWith(compactNotification: v));
              await state.publishNotificationLayout(
                  settings: controller.settings);
            },
            title: Text(l.notifCompactTitle),
            subtitle: Text(l.notifCompactSub),
          ),
      ),
    // ⚠️ СИСТЕМНАЯ ЗАЩИТА — НЕ ТО ЖЕ САМОЕ, ЧТО НАШ KILL SWITCH.
    //
    // Наш держит трафик, пока жив наш сервис. Система убила процесс —
    // туннель снялся вместе с ним, и трафик пошёл открыто. Этот случай
    // закрывает только «Блокировать соединения без VPN» в настройках
    // Android, а включить её из приложения платформа запрещает.
    //
    // Поэтому здесь не просто ссылка, а СОСТОЯНИЕ: пользователь имеет право
    // видеть, защищён он на самом деле или только думает, что защищён.
    if (Platform.isAndroid)
      SettingsRow(
        search: '${l.lockdownOnTitle} ${l.lockdownOffTitle}',
        build: (_) => const _LockdownTile(),
      ),
    // Пароль на локальные прокси ядра. Общий для платформ.
    //
    // ⚠️ ПОЧЕМУ ЭТО ВООБЩЕ ВИДНО ПОЛЬЗОВАТЕЛЮ. Умолчание (пароль включён)
    // верное для всех, и трогать его не нужно. Но локальный прокси —
    // законный способ пустить в VPN стороннюю программу, и тому, кто так
    // делает, нужны предсказуемые логин с паролем вместо случайных.
    // Прятать такую возможность значит вынуждать выключать защиту целиком.
    SettingsRow(
      search: '${l.localProxyAuthTitle} ${l.localProxyAuthRandom}',
      build: (context) => SwitchListTile(
          value: settings.localProxyAuth,
          onChanged: (v) =>
              controller.update((s) => s.copyWith(localProxyAuth: v)),
          title: Row(children: [
            Expanded(child: Text(l.localProxyAuthTitle)),
            InfoTooltip(l.localProxyAuthInfo, title: l.localProxyAuthTitle),
          ]),
          subtitle: Text(!settings.localProxyAuth
              ? l.localProxyAuthOff
              : settings.captureMode == CaptureMode.systemProxy &&
                      !Platform.isAndroid
                  // ⚠️ Честно говорим, что настройка сейчас не действует.
                  // Молчание здесь означало бы «защита включена», хотя её нет.
                  ? l.localProxyAuthSystemProxy
                  : (settings.localProxyUser.trim().isEmpty ||
                          settings.localProxyPassword.isEmpty)
                      ? l.localProxyAuthRandom
                      : l.localProxyAuthCustom),
        ),
    ),
    if (settings.localProxyAuth)
      SettingsRow(
        search: '${l.localProxyCredsTitle} ${l.localProxyCredsUnset}',
        build: (context) => ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(l.localProxyCredsTitle),
            subtitle: Text(settings.localProxyUser.trim().isEmpty ||
                    settings.localProxyPassword.isEmpty
                ? l.localProxyCredsUnset
                : l.localProxyCredsUser(settings.localProxyUser)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editLocalProxyCreds(context, controller, settings),
          ),
      ),
    // «Не выходить под реальным IP» — только при включённом kill switch,
    // и только там, где kill switch вообще имеет смысл (не «Только прокси»).
    //
    // ⚠️ ПОДПИСЬ ОБЕЩАЛА БОЛЬШЕ, ЧЕМ ДЕЛАЕТ КОД, И ЭТО СТОИЛО ВЛАДЕЛЬЦУ
    // РЕАЛЬНОГО IP НАРУЖУ. Старый текст: «Даже при рабочем VPN весь „прямой“
    // трафик идёт через VPN». На самом деле `noRealIp` переписывает только
    // ЯВНЫЕ правила «Прямо» и панельный `direct`; БАЗА маршрута не меняется
    // (`SingboxConfigBuilder`: `finalOutbound = onlySelected ? 'direct' :
    // 'proxy'`). В режиме «Только отмеченные» всё неотмеченное выходит под
    // настоящим адресом при любом положении этой галочки — а человек читал
    // «весь прямой трафик» и считал себя закрытым.
    if (settings.killSwitch && settings.killSwitchApplies)
      SettingsRow(
        search: '${l.noRealIpTitle} ${l.noRealIpSubRulesOnly}',
        build: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              value: settings.noRealIp,
              onChanged: (v) =>
                  controller.update((s) => s.copyWith(noRealIp: v)),
              title: Row(children: [
                Expanded(child: Text(l.noRealIpTitle)),
                InfoTooltip(l.infoNoRealIp, title: l.noRealIpTitle),
              ]),
              subtitle: Text(l.noRealIpSubRulesOnly),
            ),
            // Оговорка ровно там, где она перестаёт быть теорией: в этом
            // режиме галочка не закрывает главную дыру, и молчать нельзя.
            if (settings.splitTunnel.mode == SplitMode.onlySelected &&
                settings.captureMode == CaptureMode.tun)
              Padding(
                key: const Key('noRealIpOnlySelectedNote'),
                padding: const EdgeInsetsDirectional.fromSTEB(72, 0, 16, 12),
                child: Text(
                  l.noRealIpOnlySelectedNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    // ⚠️ ЭТОГО ПЕРЕКЛЮЧАТЕЛЯ ЗДЕСЬ НЕ БЫЛО, И ЭТО МЕНЯЛО МАРШРУТЫ ВСЕМ.
    //
    // Поле `myRulesOverridePanel` завели вместе с переведёнными на десять
    // языков подписями, движок его читает — а контрол забыли. Умолчание
    // `true`, изменить нечем, значит условие реврайта панельных правил
    // (`engine_base`: mode == all || noRealIp || myRulesOverridePanel) было
    // истинным ВСЕГДА: у каждого пользователя панельного профиля российские
    // сайты уходили кругом через зарубежный сервер, и объяснения этому в
    // настройках не находилось. Заодно два первых слагаемых условия были
    // мертвы — любой их разбор вводил бы в заблуждение.
    SettingsRow(
      search:
          '${l.settingsMyRulesOverridePanel} ${l.settingsMyRulesOverridePanelSub}',
      build: (_) => SwitchListTile(
        value: settings.myRulesOverridePanel,
        onChanged: (v) =>
            controller.update((s) => s.copyWith(myRulesOverridePanel: v)),
        title: Text(l.settingsMyRulesOverridePanel),
        subtitle: Text(l.settingsMyRulesOverridePanelSub),
      ),
    ),
  ];
}


// ── Бесшовность ──────────────────────────────────────────────────────────────
/// Три переключателя, каждый со своей ценой.
///
/// ⚠️ ПОДПИСИ НЕ ОБЕЩАЮТ, ЧТО СОЕДИНЕНИЯ ПЕРЕЖИВУТ СМЕНУ СЕРВЕРА. Живое TCP
/// смену внешнего IP не переживает — это физика, а не недоделка: удалённая
/// сторона видит другой адрес. Обещание «звонок продолжится» было бы обманом,
/// который вскрывается на первом же звонке, поэтому вводная строка говорит об
/// этом прямо, ДО переключателей, а не после.
List<SettingsRow> _seamlessRows(
    AppLocalizations l, AppSettings settings, SettingsController controller) {
  return [
    SettingsRow(
      search: l.settingsSeamlessNote,
      build: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.settingsSeamlessNote,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    ),
    SettingsRow(
      search: '${l.settingsSeamlessServerTitle} ${l.settingsSeamlessServerSub}',
      build: (_) => SwitchListTile(
        key: const Key('seamlessServerSwitch'),
        value: settings.seamlessServerSwitch,
        onChanged: (v) =>
            controller.update((s) => s.copyWith(seamlessServerSwitch: v)),
        title: Text(l.settingsSeamlessServerTitle),
        subtitle: Text(l.settingsSeamlessServerSub),
      ),
    ),
    SettingsRow(
      search:
          '${l.settingsSeamlessNetworkTitle} ${l.settingsSeamlessNetworkSub}',
      build: (_) => SwitchListTile(
        key: const Key('seamlessNetworkChange'),
        value: settings.seamlessNetworkChange,
        onChanged: (v) =>
            controller.update((s) => s.copyWith(seamlessNetworkChange: v)),
        title: Text(l.settingsSeamlessNetworkTitle),
        subtitle: Text(l.settingsSeamlessNetworkSub),
      ),
    ),
    SettingsRow(
      search:
          '${l.settingsSeamlessKeepTunTitle} ${l.settingsSeamlessKeepTunSub}',
      build: (_) => SwitchListTile(
        key: const Key('seamlessKeepTun'),
        value: settings.seamlessKeepTun,
        onChanged: (v) =>
            controller.update((s) => s.copyWith(seamlessKeepTun: v)),
        title: Text(l.settingsSeamlessKeepTunTitle),
        // ⚠️ «Это НЕ kill switch» — прямо в подписи. Название «держать
        // адаптер» само по себе читается как защита от утечки, а защиты тут
        // нет: трафик мимо VPN не блокируется, удерживается только адаптер.
        subtitle: Text(l.settingsSeamlessKeepTunSub),
      ),
    ),
  ];
}

// ── Проверка сервисов при подключении ────────────────────────────────────────
/// Галочка «проверять» и СВОЙ набор сервисов.
///
/// ⚠️ НАБОР ОТДЕЛЬНЫЙ ОТ АВТОНАСТРОЙКИ НАМЕРЕННО (см. `AppSettings
/// .connectCheckServices`): автонастройка ИЩЕТ рабочий сервер и ради этого
/// готова перебирать долго, а чипы под кнопкой отвечают на вопрос «работает ли
/// прямо сейчас». Свести их в одну настройку значило бы, что выбор для поиска
/// сервера навязывается повседневным чипам, и наоборот.
List<SettingsRow> _connectCheckRows(
    AppLocalizations l, AppSettings settings, SettingsController controller) {
  return [
    SettingsRow(
      search: '${l.settingsConnectChecksTitle} ${l.settingsConnectChecksSubOn}',
      build: (_) => SwitchListTile(
        key: const Key('connectChecksEnabled'),
        value: settings.connectChecksEnabled,
        onChanged: (v) =>
            controller.update((s) => s.copyWith(connectChecksEnabled: v)),
        title: Row(children: [
          Expanded(child: Text(l.settingsConnectChecksTitle)),
          InfoTooltip(l.serviceChecksInfo, title: l.serviceChecksTitle),
        ]),
        subtitle: Text(settings.connectChecksEnabled
            ? l.settingsConnectChecksSubOn
            : l.settingsConnectChecksSubOff),
      ),
    ),
    // Набор виден только при включённой проверке: выбирать, ЧТО проверять,
    // когда не проверяется ничего, — работа впустую.
    if (settings.connectChecksEnabled)
      SettingsRow(
        search: '${l.settingsConnectCheckServices} '
            '${l.settingsConnectCheckServicesSub}',
        build: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(l.settingsConnectCheckServices,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton(
                  key: const Key('connectChecksAll'),
                  onPressed: () => controller.update((st) => st.copyWith(
                      connectCheckServices: ServiceChecks.catalog.toSet())),
                  child: Text(l.autoSelectAll),
                ),
                TextButton(
                  key: const Key('connectChecksNone'),
                  onPressed: () => controller.update(
                      (st) => st.copyWith(connectCheckServices: const {})),
                  child: Text(l.autoDeselectAll),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l.settingsConnectCheckServicesSub,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              // ⚠️ ИСТОЧНИК СПИСКА — `ServiceChecks.catalog`, А НЕ
              // `ProbeService.values`. Каталог задаёт и порядок чипов под
              // кнопкой Connect: возьми мы здесь перечисление, настройки
              // показывали бы свой порядок, а главный экран — свой (человек
              // ищет «Telegram» на третьем месте, а он на седьмом). И хуже
              // того — сервис, забытый в каталоге, здесь бы выбирался, а на
              // главном не появлялся: настройка, которая молча ничего не
              // делает.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: ServiceChecks.catalog.map((service) {
                  final on = settings.connectCheckServices.contains(service);
                  return FilterChip(
                    key: Key('connectCheck-${service.name}'),
                    avatar: SiteFavicon(
                        domain: service.domain, size: 18, builtIn: true),
                    label: Text(service.label),
                    selected: on,
                    onSelected: (v) => controller.update((st) {
                      final set = {...st.connectCheckServices};
                      v ? set.add(service) : set.remove(service);
                      return st.copyWith(connectCheckServices: set);
                    }),
                  );
                }).toList(),
              ),
              // Пустой набор при включённой галочке — законное состояние
              // (флаг и набор независимы), но молча оно выглядит как поломка:
              // «проверка включена, а чипов нет». Говорим прямо.
              if (settings.connectCheckServices.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.settingsConnectChecksEmpty,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
  ];
}

// ── Автонастройка ────────────────────────────────────────────────────────────
List<SettingsRow> _autotuneRows(
    AppLocalizations l, AppSettings settings, SettingsController controller) {
  return [
    SettingsRow(
      search: '${l.settingsSpeedRankTitle} ${l.settingsSpeedTopNLabel} '
          '${l.settingsSpeedTrafficNote(settings.speedTestTrafficMb)}',
      build: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('speedInAutoSelect'),
            value: settings.speedInAutoSelect,
            // ⚠️ ПРИ ВКЛЮЧЕНИИ — ОБЯЗАТЕЛЬНОЕ ПРЕДУПРЕЖДЕНИЕ С ЧИСЛОМ.
            // Требование владельца: замер платит трафиком ПОДПИСКИ, и человек
            // должен увидеть, сколько именно, ДО того как согласится. Молчание
            // (или подпись мелким шрифтом) здесь означало бы, что мегабайты
            // спишутся у него незаметно.
            onChanged: (v) async {
              if (!v) {
                await controller
                    .update((s) => s.copyWith(speedInAutoSelect: false));
                return;
              }
              if (!await _confirmSpeedTraffic(context, settings)) return;
              await controller
                  .update((s) => s.copyWith(speedInAutoSelect: true));
            },
            title: Text(l.settingsSpeedRankTitle),
            subtitle: Text(l.settingsSpeedRankSub),
          ),
          // Поле «сколько серверов» существует только при включённом замере:
          // без него оно ни на что не влияет.
          if (settings.speedInAutoSelect) ...[
            _StepperRow(
              keyPrefix: 'speedTopN',
              label: l.settingsSpeedTopNLabel,
              // Показываем ЭФФЕКТИВНОЕ значение: с диска может приехать что
              // угодно (правка файла руками, старая версия), а движок всё
              // равно зажимает его в 1..speedTopNMax — расхождение цифры на
              // экране с реальным прогоном хуже, чем «неточно сохранённое».
              value: settings.effectiveSpeedTopN,
              min: 1,
              max: AppSettings.speedTopNMax,
              onChanged: (v) =>
                  controller.update((s) => s.copyWith(speedTopN: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l.settingsSpeedTopNSub,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              // Число — из `speedTestTrafficMb`, ЕДИНСТВЕННОГО места, где
              // считается расход: и здесь, и в диалоге подтверждения.
              child: SpeedTrafficNote(
                key: const Key('speedTrafficNote'),
                text: l.settingsSpeedTrafficNote(settings.speedTestTrafficMb),
              ),
            ),
          ],
        ],
      ),
    ),
    SettingsRow(
      search: '${l.settingsConcurrencyTitle} ${l.settingsConcurrencySub}',
      build: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepperRow(
            keyPrefix: 'autoConfigConcurrency',
            label: l.settingsConcurrencyTitle,
            value: settings.effectiveAutoConfigConcurrency,
            min: 1,
            max: AppSettings.autoConfigConcurrencyMax,
            onChanged: (v) =>
                controller.update((s) => s.copyWith(autoConfigConcurrency: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            // ⚠️ Подпись обязана называть путь отката (1 = строго по очереди):
            // распараллеливание поднимает несколько ядер сразу, и если замеры
            // «поплыли», человеку нужно знать, куда вернуться, а не гадать.
            child: Text(l.settingsConcurrencySub,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    ),
  ];
}

/// Предупреждение о трафике перед включением замера скорости.
///
/// Возвращает `true`, только если человек согласился. Отказ оставляет настройку
/// выключенной — это и есть смысл предупреждения: у него должна быть кнопка
/// «нет».
Future<bool> _confirmSpeedTraffic(
    BuildContext context, AppSettings settings) async {
  final l = AppLocalizations.of(context);
  final mb = settings.speedTestTrafficMb;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.settingsSpeedWarnTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsSpeedWarnBody(mb)),
          const SizedBox(height: 12),
          SpeedTrafficNote(text: l.settingsSpeedTrafficNote(mb), dense: true),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.settingsSpeedWarnEnable)),
      ],
    ),
  );
  return ok == true;
}

/// Числовое поле «минус — значение — плюс».
///
/// ⚠️ НЕ ТЕКСТОВОЕ ПОЛЕ. У обоих наших чисел жёсткий потолок (10 серверов,
/// 5 проверок), и в поле ввода человек набирает 50, видит своё число на экране
/// и получает молча зажатое значение при прогоне. Кнопки физически не дают
/// выйти за границы, а неактивная кнопка сама показывает, что упёрлись.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('$keyPrefix-minus'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              key: Key('$keyPrefix-value'),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: Key('$keyPrefix-plus'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

// ── Сеть / помехи ────────────────────────────────────────────────────────────
List<SettingsRow> _networkRows(AppLocalizations l) {
  return [
    SettingsRow(
      search: '${l.networkRecoverTitle} ${l.networkRecoverSub}',
      build: (context) => ListTile(
        leading: const Icon(Icons.restart_alt),
        title: Row(children: [
          Expanded(child: Text(l.networkRecoverTitle)),
          InfoTooltip(l.infoNetworkRecover, title: l.networkRecoverTitle),
        ]),
        subtitle: Text(l.networkRecoverSub),
        onTap: () => _recoverNetwork(context),
      ),
    ),
    SettingsRow(
      search: l.interferenceTitle,
      build: (context) => ListTile(
        leading: const Icon(Icons.travel_explore),
        title: Row(children: [
          Expanded(child: Text(l.interferenceTitle)),
          InfoTooltip(l.infoInterference),
        ]),
        onTap: () => scanInterferenceDialog(context),
      ),
    ),
  ];
}

Future<void> _recoverNetwork(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.networkRecoverConfirmTitle),
        content: Text(l.networkRecoverConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.networkRecoverConfirmOk)),
        ],
      ),
    );
    if (ok == true) await NetworkRecovery.run();
}

/// Диалог сканирования помех (используется и из настроек, и со старта).
Future<void> scanInterferenceDialog(BuildContext context) async {
  final found = await InterferenceScanner.scan();
  if (!context.mounted) return;
  final l = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.interferenceDialogTitle),
      content: SizedBox(
        width: 460,
        child: found.isEmpty
            ? Text(l.interferenceNoneFound)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: found
                    .map((i) => ListTile(
                          dense: true,
                          leading: Icon(i.kind == 'adapter'
                              ? Icons.settings_ethernet
                              : Icons.warning_amber),
                          // Первой строкой — ПРОГРАММА, если опознана: имя
                          // адаптера («happ-tun») пользователю ничего не
                          // говорит, а закрывать он будет именно программу.
                          title: Text(i.appName ?? i.name,
                              textDirection: TextDirection.ltr),
                          subtitle: Text(
                              i.appName == null
                                  ? i.detail
                                  : [i.name, i.appPath ?? '']
                                      .where((e) => e.isNotEmpty)
                                      .join(' · '),
                              textDirection: TextDirection.ltr,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: i.closable
                              ? TextButton(
                                  onPressed: () async {
                                    await InterferenceScanner.kill(i.pid!);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                  child: Text(l.errorCloseApp(i.appName!)),
                                )
                              : null,
                        ))
                    .toList(),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l.interferenceIgnore)),
      ],
    ),
  );
}

/// Как приложение представляется панели. От User-Agent зависит ФОРМАТ подписки:
/// известным клиентам Remnawave отдаёт XRAY_JSON с готовыми конфигами.
List<SettingsRow> _identityRows(AppLocalizations l) {
  // UA собирается из имени и версии приложения и НЕ редактируется: раньше здесь
  // было поле переопределения, и сохранённое в нём значение «замораживало» версию
  // (у пользователя UA застрял на 0.8.0 после обновлений).
  final effective = SubscriptionService.defaultUserAgent;
  return [
    SettingsRow(
      search: '${l.identityUserAgent} $effective',
      build: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.badge_outlined),
            title: Row(children: [
              Expanded(child: Text(l.identityUserAgent)),
              InfoTooltip(l.infoUserAgent),
            ]),
            subtitle:
                SelectableText(effective, textDirection: TextDirection.ltr),
            trailing: IconButton(
              tooltip: l.commonCopy,
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => Clipboard.setData(ClipboardData(text: effective)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SelectableText(
              l.identityUaAutoNote(AppInfo.version),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
    // URL-схемы — тоже про то, как приложение общается со «внешним миром».
    // Сноска «Для владельца панели» переехала ВНУТРЬ экрана URL-схем (внизу).
    SettingsRow(
      search: '${l.urlSchemesTitle} ${l.urlSchemesSub}',
      build: (context) => ListTile(
        leading: const Icon(Icons.link),
        title: Text(l.urlSchemesTitle),
        subtitle: Text(l.urlSchemesSub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UrlSchemesScreen()),
        ),
      ),
    ),
  ];
}

/// ⚠️ КАЖДОЕ ЗНАЧЕНИЕ — СВОЯ СТРОКА И СВОЙ ЗАПРОС. Раньше версия приложения,
/// версия ядра и HWID приезжали ОДНИМ `FutureBuilder`: до его готовности все
/// три показывали «…», а поиск по слову «версия» не мог оставить одну строку —
/// строк как таковых не существовало, был один общий блок. Ровно из-за него
/// владелец и не находил версию.
List<SettingsRow> _aboutRows(AppLocalizations l) {
  return [
    SettingsRow(
      search: l.aboutVersion,
      build: (_) => _ValueTile(
        title: l.aboutVersion,
        load: () async => 'v${(await PackageInfo.fromPlatform()).version}',
      ),
    ),
    SettingsRow(
      search: l.aboutXrayCore,
      build: (_) => _ValueTile(
        title: l.aboutXrayCore,
        // ⚠️ `async`, хотя тело — один вызов. `platform` бросает StateError,
        // если платформенные сервисы не зарегистрированы, и синхронный бросок
        // прилетел бы прямо в `build` — вместо строки со значением «…» экран
        // получил бы красный прямоугольник ошибки.
        load: () async => platform.coreVersions.xray(),
      ),
    ),
    // Обновление приложения: только проверка и открытие ссылки —
    // ставит пользователь сам (установщик не подписан).
    SettingsRow(
      search: '${l.appUpdateCheckTitle} ${l.appUpdateEndpointLabel}',
      build: (_) => const _AppUpdateTile(),
    ),
    SettingsRow(
      search: l.aboutHwid,
      build: (_) => const _HwidTile(),
    ),
    // Обязательное раскрытие: вместе с приложением поставляются
    // xray.exe (MPL-2.0), sing-box.exe (GPL-3.0) и wintun.dll —
    // их лицензии требуют передавать текст и указывать исходники.
    SettingsRow(
      search: '${l.aboutThirdPartyTitle} ${l.aboutThirdPartySub}',
      build: (context) => ListTile(
        leading: const Icon(Icons.workspaces_outline),
        title: Text(l.aboutThirdPartyTitle),
        // На Android ядра ВСТРОЕНЫ в APK — прежний текст про
        // «отдельные процессы» там просто неверен.
        subtitle: Text(Platform.isAndroid
            ? l.aboutThirdPartySubEmbedded
            : l.aboutThirdPartySub),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => _showThirdParty(context),
      ),
    ),
    // Логи — рядом с поддержкой: при обращении в поддержку сюда же
    // заглядывают (формат подписки, пинг, ошибки).
    SettingsRow(
      search: '${l.logsTitle} ${l.logsSub}',
      build: (context) => ListTile(
        leading: const Icon(Icons.article_outlined),
        title: Text(l.logsTitle),
        subtitle: Text(l.logsSub),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LogsScreen()),
        ),
      ),
    ),
    SettingsRow(
      search: '${l.sectionSupport} ${l.supportButtonTitle}',
      build: (_) => _SupportSection(key: supportSectionKey),
    ),
  ];
}

/// Строка «название — значение», где значение приезжает асинхронно.
///
/// ⚠️ Запрос стартует ОДИН РАЗ, в `initState`, а не в `build`. Версию ядра
/// приходится спрашивать у диска (на Windows — запуском `xray.exe --version`),
/// и с появлением поиска экран перестраивается на каждую нажатую букву: futures
/// из `build` означали бы запуск процесса на каждый символ запроса.
class _ValueTile extends StatefulWidget {
  const _ValueTile({required this.title, required this.load});

  final String title;
  final Future<String> Function() load;

  @override
  State<_ValueTile> createState() => _ValueTileState();
}

class _ValueTileState extends State<_ValueTile> {
  late final Future<String> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) => ListTile(
        dense: true,
        title: Text(widget.title),
        trailing: Text(snap.data ?? '…', textDirection: TextDirection.ltr),
      ),
    );
  }
}

/// Идентификатор устройства: отдельной строкой, потому что его копируют.
class _HwidTile extends StatefulWidget {
  const _HwidTile();

  @override
  State<_HwidTile> createState() => _HwidTileState();
}

class _HwidTileState extends State<_HwidTile> {
  late final Future<String> _future = Hwid.get();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        final hwid = snap.data ?? '…';
        return ListTile(
          title: Text(l.aboutHwid),
          subtitle: SelectableText(hwid,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          trailing: IconButton(
            tooltip: l.commonCopy,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: hwid));
              AppToast.copied(context);
            },
          ),
        );
      },
    );
  }
}

const _supportChat = 'https://t.me/silentgate_vpn_help';

/// Поддержка. НИЧЕГО не генерируем и не открываем сразу — открываем диалог, где
/// пользователь СНАЧАЛА жмёт «Сгенерировать лог», и ТОЛЬКО ПОСЛЕ этого видит,
/// куда отправить. Так юзер не пугается, что у него «сама пооткрывалась хрень».
Future<void> _support(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _SupportDialog(),
  );
}

/// Диалог поддержки со строгой последовательностью:
/// 1) объяснение + кнопка «Сгенерировать лог для поддержки»;
/// 2) по нажатию — сборка отчёта и показ (СНАЧАЛА папка, ПОТОМ сам файл);
/// 3) только теперь — меню «кому отправить» (с именем сервиса в скобках).
class _SupportDialog extends StatefulWidget {
  const _SupportDialog();

  @override
  State<_SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<_SupportDialog> {
  bool _busy = false;
  String? _path; // путь к готовому отчёту (null, пока не сгенерирован)
  String? _error;

  /// Описание проблемы словами пользователя.
  ///
  /// На Windows его вписывают прямо в открывшийся txt — там файл виден в
  /// Проводнике. На Android открывать нечего: отчёт уезжает в буфер обмена
  /// целиком, поэтому описание собираем ДО генерации, иначе в поддержку
  /// приходит один голый лог без единого слова о проблеме.
  final _description = TextEditingController();
  bool _descriptionMissing = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final l = AppLocalizations.of(context);
    // Пустое описание пропускаем только там, где его можно вписать в сам файл.
    final described = _description.text.trim().isNotEmpty;
    if (!described && _descriptionRequired) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final state = context.read<AppState>();
    final settings = context.read<SettingsController>().settings;
    final server = state.selectedServer;
    // Локализованная шапка отчёта (только её и переводим — техчасть ниже как есть).
    final header = (StringBuffer()
          ..writeln('==================================================')
          ..writeln('  ${l.reportTitle}')
          ..writeln('==================================================')
          ..writeln()
          // Описание, введённое в приложении, идёт первым — читающему
          // обращение не нужно искать его среди сотен строк лога. Если поля не
          // было (десктоп), остаётся прежняя болванка для заполнения в файле.
          ..writeln(described ? '[${l.supportDescriptionSection}]' : l.reportDescribeHere)
          ..writeln()
          ..writeln(described
              ? _description.text.trim()
              : '  ${l.reportWhatDid}\n'
                  '  ${l.reportWhatExpected}\n'
                  '  ${l.reportWhatHappened}\n'
                  '  ${l.reportWhenStarted}')
          ..writeln()
          ..writeln(l.supportNoScreenshots)
          ..writeln()
          ..writeln('--------------------------------------------------')
          ..writeln(l.reportTechNoticeLine1)
          ..writeln(l.reportTechNoticeLine2)
          ..writeln('--------------------------------------------------'))
        .toString();
    final ctx = SupportContext(
      statusLine: state.status.label,
      subscriptionUrl: state.subscriptionUrl,
      serverCount: state.servers.length,
      activeServer: server == null ? '(нет)' : server.displayName,
      activeCore: server == null
          ? '—'
          : (server.core == ProxyCore.singbox ? 'sing-box' : 'Xray'),
      header: header,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await platform.support.generate(settings: settings, ctx: ctx);
      // Строгий порядок: сперва открыть папку, затем сам txt-файл (см. reveal).
      await platform.support.reveal(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  /// Поле описания ОБЯЗАТЕЛЬНО там, где готовый отчёт нельзя дописать руками:
  /// он уходит файлом через «Поделиться» как есть.
  bool get _descriptionRequired => Platform.isAndroid;

  /// А ПОКАЗЫВАЕМ его везде.
  ///
  /// ⚠️ На Windows поля не было вовсе: считалось, что человек допишет описание
  /// прямо в открытом txt. На деле файл открывается уже после генерации, и
  /// владелец присылал отчёты с нетронутой болванкой «Что делали: / Что
  /// ожидали:». Спрашивать надо ТАМ, ГДЕ ЧЕЛОВЕК ЕЩЁ В КОНТЕКСТЕ, — то есть в
  /// диалоге, до генерации. Обязательным на десктопе не делаем: дописать файл
  /// руками там всё ещё можно, и запрет мешал бы быстрой отправке лога.
  bool get _descriptionShown => true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    // Имя сервиса VPN (владельца подписки) — для подписи «кому отправить».
    final serviceName = (state.info.title ?? '').trim();
    final vpnSupport = (state.info.supportUrl ?? '').trim();
    final done = _path != null;

    return AlertDialog(
      // ⚠️ Без этого диалог с полем ввода рвётся при клавиатуре: Dialog
      // ужимается, а Column внутри — нет. Именно так ломался отчёт поддержки.
      scrollable: true,
      title: Text(done ? l.supportDialogTitleDone : l.supportDialogTitle),
      content: SizedBox(
        width: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!done) ...[
              Text(l.supportWhatWillHappen,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(l.supportBullet1),
              const SizedBox(height: 4),
              // На Android отчёт уходит файлом через системное «Поделиться»,
              // на Windows открывается папка и сам файл. Инструкция, зовущая
              // искать папку на телефоне, отправляет человека в никуда.
              Text(Platform.isAndroid ? l.supportBullet2Android : l.supportBullet2),
              // Поле описания — там, где готовый отчёт нельзя дописать руками
              // (Android: он копируется в буфер целиком и уходит как есть).
              // Без него в поддержку приезжает голый лог без слова о проблеме.
              if (_descriptionShown) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) {
                    if (_descriptionMissing) {
                      setState(() => _descriptionMissing = false);
                    }
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l.supportDescribeLabel,
                    hintText: l.supportDescribeHint,
                    errorText:
                        _descriptionMissing ? l.supportDescribeRequired : null,
                  ),
                ),
                const SizedBox(height: 8),
                // Скриншоты в текстовый отчёт не вставить — говорим об этом
                // сразу, а не после того, как пользователь попробует.
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.supportNoScreenshots,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(l.supportError(_error!),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ],
            ] else ...[
              Text(Platform.isAndroid ? l.supportDoneTextAndroid : l.supportDoneText),
              const SizedBox(height: 8),
              SelectableText(_path!.split(RegExp(r'[\\/]')).last,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 14),
              Text(l.supportWhoTo,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SupportRecipients(
                serviceName: serviceName,
                supportUrl: vpnSupport,
                logoPath: state.logoPath,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (done)
          // На Windows отчёт «показывается» — открывается папка с выделенным
          // файлом. На Android показывать нечего: приватный каталог приложения
          // недоступен файловым менеджерам, поэтому текст отчёта копируется в
          // буфер обмена и сразу вставляется в чат поддержки.
          TextButton.icon(
            icon: Icon(
                Platform.isAndroid ? Icons.copy_all : Icons.folder_open,
                size: 18),
            onPressed: () async {
              await platform.support.reveal(_path!);
              if (Platform.isAndroid && context.mounted) {
                AppToast.copied(context, message: l.supportReportCopied);
              }
            },
            label: Text(
                Platform.isAndroid ? l.supportCopyReport : l.supportShowOnPc),
          ),
        if (done)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _path!));
              AppToast.copied(context, message: l.commonPathCopied);
            },
            label: Text(l.supportCopyPath),
          ),
        if (!done)
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.description_outlined, size: 18),
            onPressed: _busy ? null : _generate,
            label: Text(_busy ? l.supportGenerating : l.supportGenerateButton),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(done ? l.commonDone : l.commonCancel),
        ),
      ],
    );
  }
}

/// «Кому отправить» — два РАЗНЫХ адресата.
///
/// ⚠️ ЗАЧЕМ ЗДЕСЬ АВАТАРКА ПОДПИСКИ. У обеих кнопок стояли безликие значки, и
/// первая («написать в Silentgate VPN») ничем не отличалась от второй, кроме
/// слова в скобках. Логотип подписки уже скачан и закэширован — это самый
/// быстрый способ узнать «свой» сервис, и человек не отправит лог не туда.
///
/// ⚠️ И РОВНО У ОДНОЙ КНОПКИ. У разработчика клиента аватарки подписки быть не
/// должно: это другой адресат, и чужой логотип рядом с ним прямо врал бы.
/// Стережёт тест.
///
/// Вынесено отдельным ПУБЛИЧНЫМ виджетом ради проверяемости: сами кнопки живут
/// в диалоге, который показывает их только после генерации отчёта (а она пишет
/// файлы и лезет в платформу), — из теста туда не добраться.
class SupportRecipients extends StatelessWidget {
  const SupportRecipients({
    super.key,
    required this.serviceName,
    required this.supportUrl,
    required this.logoPath,
  });

  /// Название сервиса из подписки (может быть пустым — тогда общая подпись).
  final String serviceName;

  /// Ссылка на поддержку сервиса. Пусто — кнопки нет вовсе: отправлять некуда.
  final String supportUrl;

  /// Путь к кэшированному логотипу подписки; null — [SubscriptionAvatar]
  /// нарисует букву на градиенте, то есть кнопка всё равно останется своей.
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(spacing: 8, runSpacing: 6, children: [
      if (supportUrl.isNotEmpty)
        FilledButton.tonalIcon(
          icon: SubscriptionAvatar(
              path: logoPath, label: serviceName, size: 18),
          // В скобках — НАЗВАНИЕ СЕРВИСА, а не «владельцу».
          label: Text(serviceName.isNotEmpty
              ? l.supportContactNamed(serviceName)
              : l.supportContact),
          onPressed: () => UrlOpener.openTelegram(supportUrl),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.developer_mode, size: 18),
        label: Text(l.supportContactNamed(l.supportDevServiceName)),
        onPressed: () => UrlOpener.openTelegram(_supportChat),
      ),
    ]);
  }
}

/// Раздел «Поддержка». Никакой ПРЯМОЙ ссылки здесь нет: единственная кнопка
/// запускает флоу выше — юзер сам генерирует лог, и уже там появляется редирект
/// в поддержку. Сюда же «перекидывает» кнопка «Поддержка» из карточки подписки.
class _SupportSection extends StatelessWidget {
  const _SupportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionSupport),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l.supportSectionNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ListTile(
          leading: Icon(Icons.support_agent, color: scheme.primary),
          title: Text(l.supportButtonTitle),
          subtitle: Text(l.supportButtonSub),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _support(context),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Список стороннего кода в поставке.
///
/// ⚠️ Тексты лицензий ЕДУТ В САМОМ ПРИЛОЖЕНИИ (`assets/licenses/`), а не
/// «лежат рядом в папке licenses»: у APK такой папки нет. На Android ядра
/// встроены внутрь (`libcores.so`), и sing-box под GPL-3.0 — передавать текст
/// лицензии вместе с бинарником обязательно. Поэтому диалог показывает не
/// только перечисление, но и сами тексты.
void _showThirdParty(BuildContext context) {
  final l = AppLocalizations.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.thirdPartyTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                Platform.isAndroid ? l.thirdPartyBodyEmbedded : l.thirdPartyBody,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final e in const {
                'NOTICE': 'assets/licenses/NOTICE.txt',
                'GPL-3.0': 'assets/licenses/GPL-3.0.txt',
                'MPL-2.0': 'assets/licenses/MPL-2.0.txt',
              }.entries)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: Text(e.key),
                    onPressed: () => _showLicenseText(context, e.key, e.value),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
      ],
    ),
  );
}

/// Полный текст лицензии из ассетов. Читается по требованию: GPL-3.0 — 34 КБ,
/// держать это в памяти постоянно незачем.
void _showLicenseText(BuildContext context, String title, String asset) {
  final l = AppLocalizations.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              child: SelectableText(
                snap.data ?? '',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
      ],
    ),
  );
}


/// Открыть системный раздел VPN — там включается Always-on и «блокировать
/// соединения без VPN». Прямого экрана «Always-on для приложения X» в Android
/// нет, поэтому ведём в общий раздел.
Future<void> _openVpnSettings(BuildContext context) async {
  final l = AppLocalizations.of(context);
  var ok = false;
  try {
    ok = await const MethodChannel('lol.silentgate/device')
            .invokeMethod<bool>('openVpnSettings') ??
        false;
  } catch (_) {}
  if (!ok && context.mounted) {
    AppToast.show(context, l.alwaysOnSub, kind: ToastKind.info);
  }
}

Widget _sectionHeader(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        // Заголовок не лежит в кликабельной строке, поэтому его безопасно
        // делать выделяемым: тапы у соседних настроек не пострадают.
        SelText(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                )),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );
}

Widget _badge(BuildContext context, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSecondaryContainer)),
  );
}

// ── Оформление и поведение ───────────────────────────────────────────────────
List<SettingsRow> _appearanceRows(
    AppLocalizations l, AppSettings settings, SettingsController controller) {
  return [
    SettingsRow(
      search: '${l.appearanceTheme} ${l.themeSystem} ${l.themeLight} '
          '${l.themeDark}',
      build: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text(l.appearanceTheme),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppThemeMode>(
              segments: [
                ButtonSegment(
                    value: AppThemeMode.system, label: Text(l.themeSystem)),
                ButtonSegment(
                    value: AppThemeMode.light, label: Text(l.themeLight)),
                ButtonSegment(
                    value: AppThemeMode.dark, label: Text(l.themeDark)),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  controller.update((st) => st.copyWith(themeMode: s.first)),
            ),
          ),
        ],
      ),
    ),
    // Трея на Android нет: приложение сворачивается системой, а VPN
    // продолжает жить в foreground-сервисе с постоянной нотификацией —
    // она и играет роль значка в трее.
    if (!Platform.isAndroid)
      SettingsRow(
        search: '${l.closeToTrayTitle} ${l.closeToTraySubtitle}',
        build: (_) => SwitchListTile(
          value: settings.closeToTray,
          onChanged: (v) => controller.update((s) => s.copyWith(closeToTray: v)),
          title: Text(l.closeToTrayTitle),
          subtitle: Text(l.closeToTraySubtitle),
        ),
      ),
    SettingsRow(
      search: '${l.updateOnStartTitle} ${l.updateOnStartSub}',
      build: (_) => SwitchListTile(
        value: settings.updateSubscriptionOnStart,
        onChanged: (v) => controller
            .update((s) => s.copyWith(updateSubscriptionOnStart: v)),
        title: Text(l.updateOnStartTitle),
        subtitle: Text(l.updateOnStartSub),
      ),
    ),
    SettingsRow(
      search: '${l.autoUpdateSubTitle} ${l.autoUpdateSubText} '
          '${l.autoUpdateIntervalLabel}',
      build: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: settings.autoUpdateEnabled,
            onChanged: (v) =>
                controller.update((s) => s.copyWith(autoUpdateEnabled: v)),
            title: Text(l.autoUpdateSubTitle),
            subtitle: Text(l.autoUpdateSubText),
          ),
          // #10 — интервал автообновления: поле (наше значение, приоритет выше
          // подписки) + галочка «брать из подписки».
          if (settings.autoUpdateEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: Text(l.autoUpdateIntervalLabel)),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: '${settings.autoUpdateIntervalHours}',
                    enabled: !settings.autoUpdatePreferSubscription,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    onChanged: (v) {
                      final h = int.tryParse(v.trim());
                      if (h != null && h > 0) {
                        controller.update(
                            (s) => s.copyWith(autoUpdateIntervalHours: h));
                      }
                    },
                  ),
                ),
              ]),
            ),
            SwitchListTile(
              dense: true,
              value: settings.autoUpdatePreferSubscription,
              onChanged: (v) => controller
                  .update((s) => s.copyWith(autoUpdatePreferSubscription: v)),
              title: Text(l.autoUpdatePreferSub),
            ),
          ],
        ],
      ),
    ),
  ];
}

/// Включение TUN: сразу предлагаем настроить запуск без UAC (один раз),
/// иначе Windows будет спрашивать права при КАЖДОМ подключении.
Future<void> _enableTun(BuildContext context, SettingsController controller) async {
  final l = AppLocalizations.of(context);
  controller.update((s) => s.copyWith(captureMode: CaptureMode.tun));
  if (await platform.privileges.isConfigured()) return;
  if (!context.mounted) return;

  final setup = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.tunUacTitle),
      content: Text(l.tunUacBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.tunUacLater),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.tunUacSetup),
        ),
      ],
    ),
  );
  if (setup != true) return;

  final ok = await platform.privileges.configure();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ok ? l.tunUacDone : l.tunUacFail),
  ));
}

// ── Захват трафика ───────────────────────────────────────────────────────────
List<SettingsRow> _captureRows(
    AppLocalizations l, AppSettings settings, SettingsController controller) {
  return [
    // Выбор режима — ОДНА строка поиска на все варианты: по отдельности они
    // бессмысленны (переключатель с одним вариантом не переключает).
    SettingsRow(
      search: '${l.captureSystemProxy} ${l.captureSystemProxySub} '
          '${l.captureTun} ${l.captureTunSub} '
          '${l.captureProxyOnly} ${l.captureProxyOnlySub}',
      build: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // Выбора режима на Android нет: глобального системного прокси там не
        // существует, весь трафик идёт через VpnService. Показывать
        // переключатель с единственным вариантом незачем.
        if (!Platform.isAndroid) ...[
          RadioListTile<CaptureMode>(
            value: CaptureMode.systemProxy,
            groupValue: settings.captureMode,
            onChanged: (v) => controller.update((s) => s.copyWith(captureMode: v)),
            title: Text(l.captureSystemProxy),
            subtitle: Text(l.captureSystemProxySub),
          ),
          RadioListTile<CaptureMode>(
            value: CaptureMode.tun,
            groupValue: settings.captureMode,
            onChanged: (v) => _enableTun(context, controller),
            title: Row(children: [
              Text(l.captureTun),
              const SizedBox(width: 8),
              _badge(context, l.captureTunBadgeUac),
              InfoTooltip(l.pingInfoTunStage),
            ]),
            subtitle: Text(l.captureTunSub),
          ),
        ],
        // Задача 3b/7: режим для локального API — ядро поднято, порты
        // серверов слушают, но ни системный прокси, ни TUN не ставятся.
        // Не нужен UAC (в отличие от TUN выше), поэтому смена режима — сразу.
        //
        // ⚠️ ГЕЙТ БУКВАЛЬНО `Platform.isWindows`, А НЕ УНАСЛЕДОВАННЫЙ
        // `!Platform.isAndroid` соседних пунктов выше. Оба сегодня совпадают
        // (кроме Windows/Android в дереве никого нет), но соседний гейт
        // кодирует чужое допущение «не Android = Windows» — оно перестанет
        // быть верным в день, когда появится iOS-движок (заглушки
        // `Platform.isIOS` уже встречаются рядом, см. `tunRoutingSub` ниже).
        // Наш контрол работает ТОЛЬКО там, где поднимается локальный API
        // (`AppState.applyApiSettings`, тоже `Platform.isWindows`), поэтому
        // берём тот же буквальный гейт, а не молчаливо наследуем чужой.
        // Секцию «Захват» в остальном не трогаем — это не наша зона.
        if (Platform.isWindows)
          RadioListTile<CaptureMode>(
            value: CaptureMode.proxyOnly,
            groupValue: settings.captureMode,
            onChanged: (v) => controller.update((s) => s.copyWith(captureMode: v)),
            title: Text(l.captureProxyOnly),
            subtitle: Text(l.captureProxyOnlySub),
          ),
        ],
      ),
    ),
    // ⚠️ ДРАЙВЕР ТУННЕЛЯ — СРАЗУ ПОД ВЫБОРОМ РЕЖИМА (просьба владельца
    // 20.08.2026: «провайдер TUN выведи на самый верх, рядом с тремя
    // галочками»). Раньше строка стояла ниже гео-баз, то есть в полуэкране от
    // переключателя, к которому относится, — и читалась как параметр чего-то
    // другого.
    //
    // Гейт по режиму сохранён: в системном прокси и в «Только прокси» никакого
    // туннеля нет, и сообщать про его драйвер значило бы говорить о том, чего
    // сейчас не существует. На Android драйвер даёт сама система (VpnService),
    // выбирать нечего — строки там нет вовсе.
    if (!Platform.isAndroid && settings.captureMode == CaptureMode.tun)
      SettingsRow(
        search: '${l.tunProvider} wintun',
        build: (_) => ListTile(
          dense: true,
          leading: const Icon(Icons.usb),
          title: Text(l.tunProvider),
          trailing: const Text('wintun', textDirection: TextDirection.ltr),
        ),
      ),
    // Гео-базы — ВНЕ ветки TUN и БЕЗ гейта по платформе, и то и другое
    // намеренно.
    //
    // ⚠️ ПО ПЛАТФОРМЕ: раньше строка была под `if (Platform.isAndroid)` с
    // объяснением «на Windows они приезжают вместе с ядром, и кнопка была бы
    // обманкой». Файлы действительно приезжают — и устаревают: списки
    // `v2fly/geoip` обновляются еженедельно, а поставочные лежат с даты
    // сборки. Кнопка «проверить/обновить» на Windows — не обманка, обманкой
    // была её невидимость. Каталог берётся тот, из которого читает ядро
    // (`GeoBases.dir`), на обеих платформах.
    //
    // ⚠️ ПО РЕЖИМУ ЗАХВАТА: гео-базы разбирает Xray по конфигу ПАНЕЛИ, а он
    // одинаков и в системном прокси, и в TUN, и в «Только прокси». Под веткой
    // TUN строка не строилась вовсе в режиме системного прокси — то есть в
    // умолчании Windows, — и переход «плашка на главном → настройки»
    // (`scrollToGeo` → `geoAssetsKey`) молча приводил в никуда: у ключа не
    // было контекста.
    SettingsRow(
      search: '${l.geoTitle} geoip.dat geosite.dat ${l.geoWhy}',
      build: (context) => ListTile(
        key: geoAssetsKey,
        dense: true,
        leading: const Icon(Icons.public),
        title: Text(l.geoTitle),
        subtitle: Text(l.geoSubShort),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GeoBasesScreen()),
        ),
      ),
    ),
    // #14 — всё, что относится к TUN, показываем ТОЛЬКО когда он выбран:
    // в режиме системного прокси эти настройки ни на что не влияют.
    // На Android туннель — единственный режим, поэтому показываем всегда.
    if (Platform.isAndroid || settings.captureMode == CaptureMode.tun) ...[
      // Все параметры TUN/DNS/прав — на отдельном экране (их стало много).
      SettingsRow(
        search: '${l.tunRoutingTitle} ${l.dnsShortVpn}',
        build: (context) => ListTile(
            dense: true,
            leading: const Icon(Icons.settings_ethernet),
            title: Text(l.tunRoutingTitle),
            // ⚠️ Стек на Android не выбирается: он форсится в gvisor
            // (SingboxConfigBuilder), а переключатель с экрана TUN убран —
            // system/mixed там не форвардят TCP без прав, и получалось
            // «Подключено» с мёртвым интернетом. Показывать здесь «auto» из
            // настроек значило сообщать пользователю неверный факт о его же
            // туннеле и посылать искать переключатель, которого нет.
            subtitle: Text(l.tunRoutingSub(
                (Platform.isAndroid || Platform.isIOS)
                    ? 'gvisor'
                    : settings.tunStack.name,
                settings.tunMtu,
                _dnsShort(l, settings.dnsMode))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TunSettingsScreen()),
            ),
          ),
      ),
      SettingsRow(
        search: l.splitTunnelTitle,
        build: (context) => ListTile(
            dense: true,
            leading: const Icon(Icons.alt_route),
            title: Text(l.splitTunnelTitle),
            subtitle: Text(_splitLabel(l, settings)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SplitTunnelScreen()),
            ),
          ),
      ),
    ] else ...[
      SettingsRow(
        search: l.captureTunHint,
        build: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              l.captureTunHint,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
      ),
      // Задача 3b: в «Только прокси» раздельное туннелирование не
      // действует ни для одной программы машины (ничего не
      // перехватывается), поэтому тумблер виден ТОЛЬКО в этом режиме —
      // иначе он был бы виден и ничего не делал бы.
      // ⚠️ `Platform.isWindows` буквально, как и у пункта режима выше —
      // тот же довод: это НАШ контрол, а не унаследованный `else`
      // соседней секции.
      if (Platform.isWindows &&
          settings.captureMode == CaptureMode.proxyOnly) ...[
        SettingsRow(
          search: '${l.apiRulesInProxyOnly} ${l.apiRulesInProxyOnlySub}',
          build: (_) => SwitchListTile(
              value: settings.applyRulesInProxyOnly,
              onChanged: (v) => controller
                  .update((s) => s.copyWith(applyRulesInProxyOnly: v)),
              title: Text(l.apiRulesInProxyOnly),
              subtitle: Text(l.apiRulesInProxyOnlySub),
            ),
        ),
        // ⚠️ БЕЗ ЭТОЙ СТРОКИ ТУМБЛЕР ВЁЛ В НИКУДА. Он оперирует списком
        // «Блок», а список редактируется на экране раздельного
        // туннелирования — который в этом режиме из настроек НЕ ОТКРЫТЬ:
        // пункт «Раздельное туннелирование» живёт в ветке `captureMode ==
        // tun` выше. Человек включал галочку и не мог завести ни одного
        // правила. (Сам экран в этом режиме больше не заблокирован — см.
        // `split_tunnel_screen.dart`.)
        SettingsRow(
          search: '${l.splitTunnelTitle} ${l.apiRulesInProxyOnlyEdit}',
          build: (context) => ListTile(
              dense: true,
              leading: const Icon(Icons.alt_route),
              title: Text(l.splitTunnelTitle),
              subtitle: Text(l.apiRulesInProxyOnlyEdit),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SplitTunnelScreen()),
              ),
            ),
        ),
      ],
    ],
  ];
}

String _dnsShort(AppLocalizations l, DnsMode m) {
  switch (m) {
    case DnsMode.vpn:
      return l.dnsShortVpn;
    case DnsMode.system:
      return l.dnsShortSystem;
    case DnsMode.custom:
      return l.dnsShortCustom;
  }
}

String _splitLabel(AppLocalizations l, AppSettings settings) {
  final st = settings.splitTunnel;
  final modeLabel = splitModeLabel(l, st.mode);
  // «Все через VPN» — правила не применяются, счётчики не показываем.
  if (st.mode == SplitMode.all) return modeLabel;
  final a = st.apps.length, s = st.sites.length;
  final n = a + s;
  return '$modeLabel${n > 0 ? ' · ${l.splitRulesCount(n, a, s)}' : ''}';
}

// ── Пинг ─────────────────────────────────────────────────────────────────────
/// Все четыре метода доступны для обеих фаз (#4.1).
List<SettingsRow> _pingRows(
    AppLocalizations l, AppSettings settings, SettingsController controller) {
  return [
    SettingsRow(
      search: '${l.pingTwoPhaseTitle} ${l.pingTwoPhaseSubOn} '
          '${l.pingMethodCheck} ${l.pingMethodPing}',
      build: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        SwitchListTile(
          dense: true,
          value: settings.pingTwoPhase,
          onChanged: (v) => controller.update((s) => s.copyWith(pingTwoPhase: v)),
          title: Row(children: [
            Expanded(child: Text(l.pingTwoPhaseTitle)),
            InfoTooltip(l.pingInfoTwoPhase),
          ]),
          subtitle: Text(settings.pingTwoPhase
              ? l.pingTwoPhaseSubOn
              : l.pingTwoPhaseSubOff),
        ),
        if (settings.pingTwoPhase) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l.pingMethodCheck),
          ),
          _choice<bool>(
            context,
            current: settings.pingFallback == PingMethod.proxyHead ||
                settings.pingPrimary == PingMethod.proxyHead,
            options: const {false: 'GET', true: 'HEAD'},
            // TCP — первая фаза, фиксирована; выбор влияет только на метод проверки.
            onChanged: (head) => controller.update((s) => s.copyWith(
                  pingPrimary: PingMethod.tcp,
                  pingFallback:
                      head ? PingMethod.proxyHead : PingMethod.proxyGet,
                )),
          ),
          // «!» и для TCP (первая фаза), и для метода проверки — что проверяется.
          _methodLegend({
            'TCP': l.pingInfoTcp,
            'GET': l.pingInfoProxyGet,
            'HEAD': l.pingInfoProxyHead,
          }),
        ] else ...[
          // Галочка отжата — один метод на выбор (TCP/ICMP/GET/HEAD), как раньше.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l.pingMethodPing),
          ),
          // ICMP требует сырых сокетов (нет без root), GET/HEAD — проброс-харнесс
          // (второй экземпляр ядра рядом с живым туннелем не поднять). Показывать
          // методы, которые заведомо не отработают, нечестно.
          _choice<PingMethod>(
            context,
            current: settings.pingPrimary,
            options: {
              PingMethod.tcp: 'TCP',
              if (icmpSupported) PingMethod.icmp: 'ICMP',
              if (proxyProbeSupported) ...{
                PingMethod.proxyGet: 'GET',
                PingMethod.proxyHead: 'HEAD',
              },
            },
            onChanged: (m) => controller.update((s) => s.copyWith(pingPrimary: m)),
          ),
          _methodLegend({
            'TCP': l.pingInfoTcp,
            if (icmpSupported) 'ICMP': l.pingInfoIcmp,
            if (proxyProbeSupported) ...{
              'GET': l.pingInfoProxyGet,
              'HEAD': l.pingInfoProxyHead,
            },
          }),
        ],
        ],
      ),
    ),
    // #11 — объём пробы теста скорости (ПКМ по серверу → «Информация о сервере»).
    SettingsRow(
      search: '${l.speedTestProbe} ${l.speedTestFull} ${l.speedTestLight}',
      build: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text(l.speedTestProbe),
              InfoTooltip(l.infoSpeedTest),
            ]),
          ),
          _choice<SpeedTestSize>(
            context,
            current: settings.speedTestSize,
            options: {
              SpeedTestSize.full: l.speedTestFull,
              SpeedTestSize.light: l.speedTestLight,
            },
            onChanged: (v) =>
                controller.update((s) => s.copyWith(speedTestSize: v)),
          ),
        ],
      ),
    ),
    SettingsRow(
      search: '${l.testUrlLabel} ${settings.testUrl}',
      build: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextFormField(
          initialValue: settings.testUrl,
          decoration: InputDecoration(
            labelText: l.testUrlLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => controller.update((s) => s.copyWith(testUrl: v)),
        ),
      ),
    ),
  ];
}

/// Легенда методов: у каждого имени — своя «! info» рядом (#4/#4.1).
Widget _methodLegend(Map<String, String> methods) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: Wrap(
      spacing: 12,
      children: methods.entries
          .map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.key, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
                  InfoTooltip(e.value, title: e.key),
                ],
              ))
          .toList(),
    ),
  );
}

Widget _choice<T>(
  BuildContext context, {
  required T current,
  required Map<T, String> options,
  required ValueChanged<T> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SegmentedButton<T>(
      segments: options.entries
          .map((e) => ButtonSegment<T>(value: e.key, label: Text(e.value)))
          .toList(),
      selected: {current},
      showSelectedIcon: false,
      onSelectionChanged: (sel) => onChanged(sel.first),
    ),
  );
}

/// Проверка обновлений приложения: статус + ручная проверка + переключатель.
class _AppUpdateTile extends StatefulWidget {
  const _AppUpdateTile();

  @override
  State<_AppUpdateTile> createState() => _AppUpdateTileState();


}

class _AppUpdateTileState extends State<_AppUpdateTile> {
  bool _checking = false;
  String? _status;

  Future<void> _check() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _status = null;
    });
    final result = await AppUpdate.check();
    if (!mounted) return;
    final release = result.release;
    setState(() {
      _checking = false;
      // ⚠️ ТРИ ИСХОДА, А НЕ ДВА. Раньше отказ проверки был неотличим от «у вас
      // последняя версия», и человек с отключённой сетью получал успокоительное
      // «обновлений нет». Здесь причину показываем прямо: кнопку нажали, чтобы
      // узнать ответ, а «не смогли проверить» — это ответ.
      _status = switch (result.state) {
        UpdateCheckState.available => l.appUpdateAvailable(release!.version),
        UpdateCheckState.upToDate => l.appUpdateLatest,
        UpdateCheckState.failed =>
          result.failure ?? l.appUpdateServerUnavailable,
      };
    });
    if (!result.isAvailable || release == null) return;
    // Ссылки под платформу в релизе может не быть (собрали только под одну) —
    // тогда ведём на страницу релиза, а не прячем кнопку: версию мы узнали.
    final target = (release.downloadUrl ?? '').isNotEmpty
        ? release.downloadUrl!
        : (release.pageUrl ?? AppUpdate.releasesPage);
    if (!mounted) return;
    AppToast.show(
      context,
      l.appUpdateAvailable(release.version),
      actionLabel: l.appUpdateDownload,
      onAction: () => UrlOpener.open(target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    return Column(children: [
      SwitchListTile(
        dense: true,
        value: settings.appUpdateCheck,
        onChanged: (v) => controller.update((s) => s.copyWith(appUpdateCheck: v)),
        title: Row(children: [
          Expanded(child: Text(l.appUpdateCheckTitle)),
          InfoTooltip(l.infoAppUpdate),
        ]),
        subtitle: Text(_status ?? l.appUpdateManual),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        // ⚠️ ПОЛЯ «ЭНДПОИНТ ВЕРСИИ» ЗДЕСЬ БОЛЬШЕ НЕТ. Оно просило пользователя
        // настроить то, чего он знать не может, а пустым вело на панельные
        // адреса, из которых андроидного не существует до сих пор — телефон
        // молча не находил ничего вообще. Источник теперь один и вшит: релизы
        // GitHub, одинаковые для обеих платформ.
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: _checking ? null : _check,
            child: Text(_checking ? '…' : l.commonCheck),
          ),
        ),
      ),
    ]);
  }
}

/// Разовое предложение включить системный always-on VPN (Android).
///
/// Показывается при включении kill switch: именно тогда человек думает о том,
/// чтобы трафик не утёк, и именно тогда уместно сказать, что у системы есть
/// более сильный механизм. Отказ ничего не ломает — наш kill switch работает.
Future<void> _offerAlwaysOn(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.alwaysOnTitle),
      content: Text(l.alwaysOnSub),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.commonOpen)),
      ],
    ),
  );
  if (go == true && context.mounted) await _openVpnSettings(context);
}

/// Диалог «свои логин и пароль локального прокси».
///
/// ⚠️ Пустые поля — это НЕ ошибка, а осознанный выбор «пусть будет случайный».
/// Поэтому кнопка сохранения активна всегда, а очистка полей возвращает режим
/// посессионного пароля. Требовать заполнения значило бы навязывать худший
/// вариант: заданный вручную пароль ложится на диск и переживает перезапуск.
Future<void> _editLocalProxyCreds(BuildContext context,
    SettingsController controller, AppSettings settings) async {
  final user = TextEditingController(text: settings.localProxyUser);
  final pass = TextEditingController(text: settings.localProxyPassword);
  var obscure = true;
  // Локализация берётся ОДИН раз здесь: внутри builder контекст другой,
  // а строка нужна и заголовку, и полям.
  final l = AppLocalizations.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(l.localProxyDialogTitle),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SelText(l.localProxyDialogBody),
          const SizedBox(height: 12),
          TextField(
            controller: user,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
                labelText: l.localProxyFieldUser,
                hintText: l.localProxyFieldHint),
          ),
          TextField(
            controller: pass,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.localProxyFieldPassword,
              hintText: l.localProxyFieldHint,
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setLocal(() => obscure = !obscure),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx).commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx).commonDone)),
        ],
      ),
    ),
  );
  if (saved != true) return;
  await controller.update((s) => s.copyWith(
        localProxyUser: user.text.trim(),
        localProxyPassword: pass.text,
      ));
}

/// Строка «Системная защита»: показывает РЕАЛЬНОЕ состояние, а не ссылку.
///
/// ⚠️ ЗАЧЕМ СОСТОЯНИЕ, А НЕ ПРОСТО КНОПКА «ОТКРЫТЬ НАСТРОЙКИ».
///
/// Наш kill switch на Android настоящий: ядро перезагружается конфигом-
/// заглушкой, и трафик умирает в `reject`. Но живёт это ровно столько, сколько
/// живёт наш сервис. Система убила процесс — туннель снялся вместе с ним, и
/// трафик пошёл открыто. Закрывает такой случай только сама Android, а включить
/// её настройку из приложения платформа запрещает намеренно.
///
/// Владелец сформулировал проблему точно: «неизвестно, работает или нет, без
/// настроек в самом телефоне». Значит показывать надо факт, а не намёк.
class _LockdownTile extends StatefulWidget {
  const _LockdownTile();

  @override
  State<_LockdownTile> createState() => _LockdownTileState();
}

class _LockdownTileState extends State<_LockdownTile> with WidgetsBindingObserver {
  VpnLockdown _state = VpnLockdown.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Пользователь уходил в системные настройки и вернулся — перечитываем.
    // Без этого строка показывала бы старое состояние до перезапуска, и
    // человек, только что включивший защиту, видел бы «выключена».
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final st = await VpnLockdown.query();
    if (mounted) setState(() => _state = st);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = _state;
    final l = AppLocalizations.of(context);

    final (IconData icon, Color color, String title, String sub) = switch (st) {
      // Полная защита: и постоянная VPN, и блокировка без неё.
      _ when st.fullyProtected => (
          Icons.verified_user,
          scheme.primary,
          l.lockdownOnTitle,
          l.lockdownOnSub
        ),
      // Назначены постоянной VPN, но блокировки нет — половина дела.
      _ when st.supported && st.alwaysOn => (
          Icons.gpp_maybe,
          scheme.tertiary,
          l.lockdownHalfTitle,
          l.lockdownHalfSub
        ),
      // Знаем точно, что защиты нет.
      _ when st.supported => (
          Icons.gpp_bad,
          scheme.error,
          l.lockdownOffTitle,
          l.lockdownOffSub
        ),
      // ⚠️ Не знаем — так и говорим. Зелёная птица здесь была бы враньём.
      _ => (
          Icons.help_outline,
          scheme.outline,
          l.lockdownUnknownTitle,
          l.lockdownUnknownSub
        ),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(sub),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () async {
        final ok = await VpnLockdown.openSettings();
        if (!context.mounted) return;
        if (!ok) {
          // Экрана нет — бывает на прошивках. Молча ничего не делать хуже:
          // пользователь решит, что сломалась кнопка.
          AppToast.show(
            context,
            AppLocalizations.of(context).lockdownOpenFailed,
            kind: ToastKind.error,
          );
        }
      },
    );
  }
}

/// Строка бокового меню разделов с подсветкой выбранного.
///
/// ⚠️ САМ РОСЧЕРК ЖИВЁТ В [SelectionOutline] — общем виджете. Владелец попросил
/// такую же обводку для выбранного сервера («сделай такую же обводку для
/// выбранного сервера») и отдельно велел меню оставить как есть («но оставь
/// его»), поэтому рисование вынесено в один виджет на оба места: две копии
/// анимации разошлись бы на первой правке цвета или скорости.
class SettingsRailTile extends StatelessWidget {
  const SettingsRailTile({
    super.key,
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSectionData section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SelectionOutline(
        selected: selected,
        child: ListTile(
          dense: true,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(section.icon, size: 20),
          title: Text(section.title, overflow: TextOverflow.ellipsis),
          onTap: onTap,
        ),
      ),
    );
  }
}
