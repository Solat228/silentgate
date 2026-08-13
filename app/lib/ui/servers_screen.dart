import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/util/server_search.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../state/probe_controller.dart';
import '../state/settings_controller.dart';
import 'widgets/ping_gate.dart';
import 'widgets/server_search_field.dart';
import 'widgets/server_tile.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final probe = context.watch<ProbeController>();
    final settings = context.read<SettingsController>().settings;
    final servers = state.servers;
    // Исходные индексы: выбор идёт по позиции в AppState.servers.
    final shown = ServerSearch.matchIndices(servers, _query);
    // ⚠️ ГЕЙТ ОБЩИЙ С ОСТАЛЬНЫМИ ТОЧКАМИ ВХОДА, А НЕ «ИДЁТ ЛИ ПИНГ».
    // Здесь стояло одно условие `probe.running`, а прогон пинга не начинается
    // ещё и во время замера скорости — тот держит те же локальные порты.
    // Замер сотни серверов идёт десятки минут, и всё это время кнопка
    // выглядела живой: нажатие не делало ничего и ничего не объясняло.
    final gate = PingGate.of(probe, hasTargets: shown.isNotEmpty);
    // «Пинговать нечего» на этом экране бывает двух разных сортов, и путать их
    // нельзя: пустой список — это «импортируйте подписку», а вот при активном
    // поиске серверы есть, просто под запрос не подошёл ни один.
    //
    // ⚠️ РАЗВИЛКА — ПО НАЛИЧИЮ СЕРВЕРОВ, ТА ЖЕ, ЧТО У ТЕЛА ЭКРАНА (см. ниже:
    // `servers.isEmpty` → «список пуст», иначе `shown.isEmpty` → «ничего не
    // найдено»). Здесь стоял `_query.isEmpty`, и это расходилось с телом в
    // живом случае: строка поиска набрана, а обновление подписки очистило
    // список — экран говорил «импортируйте подписку», подсказка кнопки в тот
    // же момент «ничего не найдено». Два ответа на один вопрос.
    final nothingToPing =
        servers.isEmpty ? l.serversEmpty : l.serversNothingFound;

    return Scaffold(
      appBar: AppBar(
        title: Text(_query.isEmpty
            ? l.serversTitle
            : l.serversFound(shown.length, servers.length)),
        actions: [
          IconButton(
            tooltip: l.serversRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: state.subscriptionUrl == null || state.loading
                ? null
                : state.refreshSubscription,
          ),
          IconButton(
            // Подсказка называет ПРИЧИНУ, по которой кнопка погашена: нажатий
            // выключенная кнопка не принимает, и наведение — единственный
            // оставшийся способ узнать, почему. Что подсказка при этом
            // действительно всплывает (её рисует `Tooltip` поверх кнопки, а не
            // сама кнопка), проверено наведением мыши в `ping_gate_test`, а не
            // принято на веру.
            tooltip: gate.label(
                l, _query.isEmpty ? l.serversPingAll : l.serversPingFound,
                noTargets: nothingToPing),
            icon: probe.running
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            onPressed: gate.allowed
                ? () => probe.pingAll(
                    [for (final i in shown) servers[i]], settings)
                : null,
          ),
        ],
      ),
      body: servers.isEmpty
          ? Center(child: Text(l.serversEmpty))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: ServerSearchField(
                    value: _query,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(child: Text(l.serversNothingFound))
                      : ListView.separated(
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final idx = shown[i];
                            return ServerTile(
                              server: servers[idx],
                              selected: idx == state.selectedIndex,
                              onTap: () {
                                state.selectServer(idx);
                                Navigator.of(context).pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
