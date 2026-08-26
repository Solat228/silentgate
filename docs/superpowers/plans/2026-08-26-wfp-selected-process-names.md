# Поддержка правил приложений по имени в WFP kill switch — план реализации

> **Для агентских исполнителей:** перед началом обязательно используйте `superpowers:subagent-driven-development` (рекомендуется) или `superpowers:executing-plans` для выполнения этого плана по задачам. Шаги отмечаются чекбоксами (`- [ ]`).

**Цель:** дополнить Windows WFP kill switch материализацией выбранных пользователем правил `byName=true` в текущие полные пути процессов, не меняя уже рабочую маршрутизацию `sing-box`.

**Архитектура:** `AppRule.byName=true` передаётся помощнику TUN как отдельный селектор basename (`blockedAppNames`/`allowedAppNames`), а `byName=false` — как прежний полный путь. Помощник периодически получает `ProcessListWindows.enumerate()`, материализует только выбранные имена в пути и передаёт готовый план в существующий `KillSwitchHold.reengage()`. Замена WFP-фильтров остаётся одной транзакцией: при ошибке старый рабочий набор сохраняется.

**Стек:** Flutter/Dart, `flutter_test`, Windows Filtering Platform через `dart:ffi`, существующий `ProcessListWindows`.

## Глобальные ограничения

- `FWPM_CONDITION_ALE_APP_ID` не поддерживает basename или маску пути; в WFP передаются только существующие полные пути.
- `sing-box` не переписывается: `process_name` для `byName=true` и `process_path_regex` для `byName=false` уже имеют правильную семантику.
- Наблюдаются только basename из `blockedAppNames` и `allowedAppNames`; глобального сканирования или wildcard-правила для всех программ не будет.
- Правило `byName=false` остаётся точным полным путём и не получает динамических замен.
- Старые `tun_killswitch.json` без новых полей должны читаться как планы с пустыми списками имён.
- Отсутствие запущенного процесса с выбранным именем не должно запрещать подключение; пустой материализованный план в `onlySelected` остаётся законным пустым планом.
- Обновление набора WFP выполняется только через существующий `KillSwitchHold.reengage()`, без отдельного снятия старого набора.
- Ни один WFP-фильтр и ни один VPN/TUN не включать на хосте; живые проверки выполнять только в disposable Hyper-V VM `SG-Test`.
- После живой проверки VM остановить командой `Stop-VM -Name SG-Test -Force`.
- Реальные IP, адреса серверов, токены и пользовательские секреты не записывать в тесты, логи, коммиты и общие артефакты.

---

## Карта файлов

- Modify: `app/lib/engine/windows/wfp_rules.dart` — поля селекторов имён, чистая материализация в пути и сохранение полей при копировании плана.
- Modify: `app/lib/engine/windows/tun/kill_switch_plan_file.dart` — JSON-поля `blockedAppNames` и `allowedAppNames` с обратной совместимостью.
- Create: `app/lib/engine/windows/kill_switch_app_selectors.dart` — чистое разделение правил `AppRule` на имя/путь для проверки без WFP.
- Modify: `app/lib/engine/windows/windows_engine.dart` — запись разделённых селекторов в план.
- Modify: `app/lib/engine/windows/tun/tun_helper.dart` — материализация при старте, наблюдение в общем цикле и атомарное обновление держателя.
- Reuse: `app/lib/engine/windows/process_list_windows.dart` — существующий `RunningProcess` и `ProcessListWindows.enumerate()`; API не менять.
- Modify: `app/test/wfp_rules_test.dart` — сохранение селекторов при `withOwnBinaries`/`withTunnelLuid` и пустота плана до материализации.
- Modify: `app/test/kill_switch_plan_file_test.dart` — round-trip и совместимость JSON.
- Create: `app/test/kill_switch_selected_names_test.dart` — классификация, материализация, дедупликация и инварианты наблюдателя.
- Create: `app/test/kill_switch_engine_selectors_test.dart` — защита интеграции селекторов с `WindowsEngine`.
- Modify: `app/test/kill_switch_missing_app_test.dart` — проверка, что очистка путей не удаляет селекторы имён.
- Modify: `app/test/tun_alive_watch_test.dart` — стражи порядка динамического обновления и поведения при отсутствии начального процесса.

---

### Task 1: Модель плана и чистая материализация имён

**Файлы:**
- Modify: `app/lib/engine/windows/wfp_rules.dart:22-195`
- Modify: `app/test/wfp_rules_test.dart`
- Create: `app/test/kill_switch_selected_names_test.dart`

**Интерфейсы:**
- Потребляет: `KillSwitchPlan`, `RunningProcess` из `process_list_windows.dart`.
- Производит: `KillSwitchPlan.blockedAppNames`, `KillSwitchPlan.allowedAppNames` и чистую функцию/метод `withMaterializedAppPaths(Iterable<RunningProcess> processes)` для использования `TunHelper`.

- [ ] **Шаг 1: Добавить падающие тесты на поля и материализацию.**

  В `kill_switch_selected_names_test.dart` создать план с:
  - `blockedAppNames: ['claude.exe']`;
  - `allowedAppNames: ['browser.exe']`;
  - одним явным `blockedAppPaths`;
  - процессами `C:\one\claude.exe`, `D:\two\claude.exe`, `C:\one\browser.exe` и `C:\other\editor.exe`.

  Проверить:
  ```dart
  final materialized = plan.withMaterializedAppPaths([
    const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
    const RunningProcess(2, 'CLAUDE.EXE', r'D:\two\claude.exe'),
    const RunningProcess(3, 'browser.exe', r'C:\one\browser.exe'),
    const RunningProcess(4, 'editor.exe', r'C:\other\editor.exe'),
  ]);

  expect(materialized.blockedAppPaths, [
    r'C:\explicit\fixed.exe',
    r'C:\one\claude.exe',
    r'D:\two\claude.exe',
  ]);
  expect(materialized.allowedAppPaths, [r'C:\one\browser.exe']);
  expect(materialized.blockedAppNames, ['claude.exe']);
  expect(materialized.allowedAppNames, ['browser.exe']);
  ```

  Добавить отдельные проверки: basename сравнивается без учёта регистра; одинаковое имя из двух каталогов даёт оба пути; `editor.exe` не попадает; повтор одного пути не дублируется; селектор имени без живого процесса не делает план непустым (`blockAll: false`, `blockedAppPaths: []`, `isEmpty == true`).

- [ ] **Шаг 2: Запустить новые тесты и убедиться, что они падают.**

  Запустить из `app`:
  ```text
  flutter test test/kill_switch_selected_names_test.dart test/wfp_rules_test.dart
  ```
  Ожидание: ошибка компиляции/отсутствие `blockedAppNames` или `withMaterializedAppPaths`.

- [ ] **Шаг 3: Реализовать поля и материализацию.**

  В `KillSwitchPlan` добавить:
  ```dart
  final List<String> blockedAppNames;
  final List<String> allowedAppNames;
  ```
  с пустыми значениями по умолчанию в конструкторе. `isEmpty` оставить зависящим от `blockAll` и **материализованных** `blockedAppPaths`; наличие только селектора имени не должно запрещать запуск до появления процесса.

  Реализовать `withMaterializedAppPaths` так, чтобы он:
  1. построил регистронезависимые множества из `blockedAppNames` и `allowedAppNames`;
  2. прошёл только по переданным `RunningProcess`;
  3. добавил `process.path` к соответствующему списку, если `process.name` совпал с выбранным basename;
  4. сохранил явные пути первыми;
  5. удалил дубликаты путей без учёта регистра;
  6. сохранил оба списка имён и все остальные поля плана.

  Не добавлять никаких правил в `buildWfpRules` по самим именам: WFP получает только результирующие `_appId(path)`.

  В `withOwnBinaries`, `withTunnelLuid` и ветке копирования `withoutMissingApps` явно перенести `blockedAppNames` и `allowedAppNames`, чтобы новое поле не обнулялось.

- [ ] **Шаг 4: Обновить тесты копирования плана.**

  В `wfp_rules_test.dart` заполнить оба списка имён в фабрике полного плана и добавить проверки:
  ```dart
  expect(copy.blockedAppNames, base.blockedAppNames);
  expect(copy.allowedAppNames, base.allowedAppNames);
  ```
  для `withOwnBinaries` и `withTunnelLuid`. В `kill_switch_missing_app_test.dart` проверить, что `withoutMissingApps` удаляет только устаревшие пути и сохраняет оба списка имён.

- [ ] **Шаг 5: Запустить тесты задачи.**

  ```text
  flutter test test/kill_switch_selected_names_test.dart test/wfp_rules_test.dart test/kill_switch_missing_app_test.dart
  ```
  Ожидание: PASS.

- [ ] **Шаг 6: Зафиксировать самостоятельный результат.**

  ```text
  git add app/lib/engine/windows/wfp_rules.dart app/test/wfp_rules_test.dart app/test/kill_switch_selected_names_test.dart app/test/kill_switch_missing_app_test.dart
  git commit -m "feat: materialize selected app names for WFP"
  ```

---

### Task 2: Передача селекторов через файл плана

**Файлы:**
- Modify: `app/lib/engine/windows/tun/kill_switch_plan_file.dart:28-103`
- Modify: `app/test/kill_switch_plan_file_test.dart`

**Интерфейсы:**
- Потребляет: `KillSwitchPlan.blockedAppNames` и `allowedAppNames` из задачи 1.
- Производит: JSON-ключи `blockedAppNames` и `allowedAppNames`; `KillSwitchPlanFile.write` принимает оба списка, а `read` восстанавливает их.

- [ ] **Шаг 1: Написать падающий round-trip-тест.**

  Расширить тестовый helper `put` параметрами `blockedNames` и `allowedNames`, передать их в `KillSwitchPlanFile.write`, затем добавить проверку:
  ```dart
  await put(
    blockAll: true,
    blockedNames: const ['unused.exe'],
    allowedNames: const ['browser.exe', 'BROWSER.EXE'],
  );
  final p = KillSwitchPlanFile.read(tmp)!;
  expect(p.blockedAppNames, ['unused.exe']);
  expect(p.allowedAppNames, ['browser.exe', 'BROWSER.EXE']);
  ```

  Добавить тест чтения старого JSON без этих ключей и ожидать пустые списки. Добавить тест, что числа, `null` и пустые строки в новых списках отбрасываются, а остальные данные сохраняются.

- [ ] **Шаг 2: Запустить тест и проверить отказ до реализации.**

  ```text
  flutter test test/kill_switch_plan_file_test.dart
  ```
  Ожидание: ошибка из-за отсутствующих параметров/полей.

- [ ] **Шаг 3: Реализовать запись и чтение.**

  В `write` добавить необязательные параметры:
  ```dart
  List<String> blockedAppNames = const [],
  List<String> allowedAppNames = const [],
  ```
  и записывать их в JSON рядом с соответствующими `*AppPaths`. Не менять формат и смысл существующих ключей.

  В `read` использовать тот же фильтр `x is String && x.isNotEmpty`, что и для путей, и передать списки в `KillSwitchPlan`. Отсутствующее поле трактовать как `const []`; битый JSON по-прежнему возвращает `null` целиком.

- [ ] **Шаг 4: Запустить тесты файла плана.**

  ```text
  flutter test test/kill_switch_plan_file_test.dart test/kill_switch_selected_names_test.dart
  ```
  Ожидание: PASS.

- [ ] **Шаг 5: Зафиксировать результат.**

  ```text
  git add app/lib/engine/windows/tun/kill_switch_plan_file.dart app/test/kill_switch_plan_file_test.dart
  git commit -m "feat: persist selected app name selectors"
  ```

---

### Task 3: Разделение правил приложения на имена и пути

**Файлы:**
- Create: `app/lib/engine/windows/kill_switch_app_selectors.dart`
- Modify: `app/lib/engine/windows/windows_engine.dart:662-714`
- Create: `app/test/kill_switch_engine_selectors_test.dart`

**Интерфейсы:**
- Потребляет: `SplitTunnelConfig.mode`, `SplitTunnelConfig.apps`, `AppRule.byName`, `AppRule.name`, `AppRule.path`, `AppAction`.
- Производит: `KillSwitchAppSelectors.fromSplitTunnel(SplitTunnelConfig)` с четырьмя списками `blockedAppPaths`, `blockedAppNames`, `allowedAppPaths`, `allowedAppNames`.

- [ ] **Шаг 1: Написать тесты классификации.**

  В `kill_switch_engine_selectors_test.dart` создать правила:
  ```dart
  const AppRule(r'C:\old\claude.exe', byName: true, action: AppAction.tunnel),
  const AppRule(r'C:\exact\game.exe', byName: false, action: AppAction.tunnel),
  const AppRule(r'C:\old\browser.exe', byName: true, action: AppAction.direct),
  const AppRule(r'C:\exact\proxy.exe', byName: false, action: AppAction.direct),
  const AppRule(r'C:\disabled\ignored.exe', byName: true, action: AppAction.tunnel, enabled: false),
  ```
  Проверить для `onlySelected`, что имя `claude.exe` попало только в `blockedAppNames`, а `exact\game.exe` — только в `blockedAppPaths`; отключенное правило не попало никуда. Для `exceptSelected` проверить аналогичное разделение в `allowed*`. Для `all` проверить, что списки блокируемых приложений пусты, потому что действует `blockAll`.

- [ ] **Шаг 2: Запустить тест до реализации.**

  ```text
  flutter test test/kill_switch_engine_selectors_test.dart
  ```
  Ожидание: отсутствует `KillSwitchAppSelectors`.

- [ ] **Шаг 3: Реализовать чистый классификатор.**

  Создать `KillSwitchAppSelectors` с константным конструктором и фабрикой `fromSplitTunnel`. Для `onlySelected` включать только `enabled && action == AppAction.tunnel`; для `exceptSelected` — только `enabled && action == AppAction.direct`; для `all` не включать app selectors. При `byName == true` использовать `rule.name`, при `false` — `rule.path`. Пустые значения не добавлять. Сохранять порядок правил и не смешивать имя с полным путём.

- [ ] **Шаг 4: Подключить классификатор к `_writeKillSwitchPlan`.**

  В `windows_engine.dart` один раз получить `final selectors = KillSwitchAppSelectors.fromSplitTunnel(s.splitTunnel);` и передать:
  ```dart
  blockedAppPaths: selectors.blockedAppPaths,
  blockedAppNames: selectors.blockedAppNames,
  allowedAppPaths: selectors.allowedAppPaths,
  allowedAppNames: selectors.allowedAppNames,
  ```
  Удалить старые inline-циклы по `r.path`. `blockAll: !onlySelected` оставить без изменений. Не менять `singbox_config_builder.dart`.

- [ ] **Шаг 5: Добавить исходный страж интеграции.**

  В тесте проверить, что `_writeKillSwitchPlan` вызывает `KillSwitchAppSelectors.fromSplitTunnel` и передаёт все четыре списка в `KillSwitchPlanFile.write`; страж должен также проверять отсутствие прежней прямой передачи `r.path` в `blockedAppPaths`/`allowedAppPaths`, чтобы будущая правка не начала снова игнорировать `byName`.

- [ ] **Шаг 6: Запустить тесты задачи.**

  ```text
  flutter test test/kill_switch_engine_selectors_test.dart test/kill_switch_plan_file_test.dart test/wfp_rules_test.dart
  ```
  Ожидание: PASS.

- [ ] **Шаг 7: Зафиксировать результат.**

  ```text
  git add app/lib/engine/windows/kill_switch_app_selectors.dart app/lib/engine/windows/windows_engine.dart app/test/kill_switch_engine_selectors_test.dart
  git commit -m "feat: persist app name selectors in kill switch plan"
  ```

---

### Task 4: Материализация и наблюдение в `TunHelper`

**Файлы:**
- Modify: `app/lib/engine/windows/tun/tun_helper.dart:200-318,328-418`
- Modify: `app/test/tun_alive_watch_test.dart`
- Modify: `app/test/kill_switch_selected_names_test.dart`

**Интерфейсы:**
- Потребляет: `KillSwitchPlanFile.read`, `KillSwitchPlan.withMaterializedAppPaths`, `ProcessListWindows.enumerate`, `KillSwitchWfp.engage`, `KillSwitchHold.reengage`.
- Производит: начальный WFP-набор с материализованными именами и периодическое обновление только при изменении найденных путей.

- [ ] **Шаг 1: Зафиксировать ожидаемый жизненный цикл тестами/стражами.**

  В `kill_switch_selected_names_test.dart` добавить чистую проверку, что при смене списка процессов:
  ```dart
  final first = plan.withMaterializedAppPaths([
    const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
  ]);
  final second = plan.withMaterializedAppPaths([
    const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
    const RunningProcess(2, 'claude.exe', r'D:\two\claude.exe'),
  ]);
  expect(first.blockedAppPaths, isNot(contains(r'D:\two\claude.exe')));
  expect(second.blockedAppPaths, contains(r'D:\two\claude.exe'));
  ```

  В `tun_alive_watch_test.dart` добавить исходные стражи, требующие в общем `while (true)` вызов `ProcessListWindows.enumerate()`, повторное получение материализованного плана и ветку, которая при наличии нового пути вызывает `hold.reengage(...)`. Страж должен проверять, что отсутствует отдельное снятие `hold` перед обновлением и что ошибка обновления логируется, а цикл не завершается только из-за неудачного `reengage`.

- [ ] **Шаг 2: Ввести единый путь чтения и материализации плана.**

  Импортировать `ProcessListWindows`. Перед `_planFor`/`_engageBase` добавить внутренний метод, который:
  1. читает план с `expectToken`;
  2. вызывает `withMaterializedAppPaths(ProcessListWindows.enumerate())`;
  3. добавляет `withOwnBinaries(_ownBinaries())`;
  4. возвращает `null`, если файл невалиден.

  `_mustHaveKillSwitch` должен проверять `isEmpty` уже после материализации. `_engageBase` должен вычищать устаревшие **полные пути** после материализации, писать пропуски в существующий журнал и передавать `cleaned.plan` в `KillSwitchWfp.engage`. Селекторы имён не считать устаревшими файлами и не удалять.

- [ ] **Шаг 3: Обновить стартовый hold и разрешение LUID.**

  Сделать `hold` в `run` изменяемым (`KillSwitchHold? hold`). Сохранить текущий порядок: базовый план поднимается до запуска sing-box; после появления LUID строится свежий материализованный план с LUID и передаётся в `hold.reengage`. При `hold == null` из-за пустого onlySelected-плана не запрещать запуск ядра.

- [ ] **Шаг 4: Добавить периодический мониторинг выбранных имён в существующий тик.**

  Внутри уже существующего цикла после проверок stop/alive и в том же интервале 400 мс:
  1. прочитать и материализовать свежий план;
  2. сравнить наборы материализованных `blockedAppPaths`/`allowedAppPaths` с последним успешно применённым набором без учёта порядка и регистра;
  3. если набор не изменился — не трогать WFP;
  4. если `hold != null`, вызвать `hold.reengage(freshPlan, log: ...)` одной транзакцией;
  5. только после `true` обновить снимок успешно применённых путей;
  6. при `false` оставить старый снимок и старый hold, записать причину и повторить попытку на следующем тике с ограничением повторной записи одинаковой ошибки, чтобы лог не рос сотнями строк в секунду.

  Если начальный `onlySelected`-план был пустым из-за отсутствия процесса, а следующий тик нашёл выбранный процесс, вызвать `KillSwitchWfp.engage(freshPlan)` и сохранить новый hold; это единственный допустимый случай создания hold после старта ядра. Если процесс появился после того, как LUID уже известен, передать в свежий план текущий LUID.

  Не удалять фильтры завершившегося процесса отдельно: если путь остаётся существующим, сохранённый фильтр может жить до конца сессии; если путь исчез, обычная очистка полных путей удаляет его только в рамках следующей успешной транзакционной замены.

- [ ] **Шаг 5: Не менять поведение смерти ядра и остановки.**

  Сохранить текущие инварианты:
  - stop-файл и смерть UI проверяются на каждом тике;
  - смерть sing-box не снимает активный hold;
  - при явной остановке вызывается `hold.release()`;
  - если hold отсутствует и ядро завершилось, помощник может выйти как раньше для пустого плана.

- [ ] **Шаг 6: Запустить статические тесты помощника.**

  ```text
  flutter test test/kill_switch_selected_names_test.dart test/tun_alive_watch_test.dart test/kill_switch_missing_app_test.dart
  ```
  Ожидание: PASS. Ни один тест не должен открывать WFP, запускать sing-box или менять системный прокси.

- [ ] **Шаг 7: Зафиксировать результат.**

  ```text
  git add app/lib/engine/windows/tun/tun_helper.dart app/test/tun_alive_watch_test.dart app/test/kill_switch_selected_names_test.dart
  git commit -m "feat: watch selected process names for WFP updates"
  ```

---

### Task 5: Полная статическая проверка и регрессионный аудит

**Файлы:**
- Проверить все изменённые файлы из задач 1–4.
- При необходимости дополнить: `app/test/wfp_rules_test.dart`, `app/test/kill_switch_plan_file_test.dart`, `app/test/kill_switch_selected_names_test.dart`.

- [ ] **Шаг 1: Проверить, что обычная маршрутизация не изменилась.**

  Поискать изменения только в `singbox_config_builder.dart` и убедиться, что файл не изменён. Отдельно проверить, что существующие тесты `process_name`/`process_path_regex` остались без изменений и проходят.

- [ ] **Шаг 2: Запустить анализатор.**

  Из `app`:
  ```text
  flutter analyze
  ```
  Ожидание: ноль ошибок и предупреждений.

- [ ] **Шаг 3: Запустить полный набор тестов.**

  ```text
  flutter test
  ```
  Ожидание: все тесты зелёные; диагностические тесты с сетью не включать автоматически, если они скипаются штатным `dart_test.yaml`.

- [ ] **Шаг 4: Проверить итоговый diff и отсутствие секретов.**

  ```text
  git diff --check
  git status --short
  git diff HEAD~4..HEAD -- app/lib/engine/windows app/test
  ```
  Проверить, что нет реальных IP, URL подписки, токенов, временных файлов и изменений в `app/lib/core/singbox/singbox_config_builder.dart`.

- [ ] **Шаг 5: Сделать один итоговый коммит после зелёных проверок, если остались только мелкие тестовые правки.**

  ```text
  git add app
  git commit -m "test: verify WFP process-name materialization"
  ```
  Если после задачи 4 рабочее дерево уже чистое и все тесты прошли, новый пустой коммит не создавать.

---

### Task 6: Живая проверка только в `SG-Test`

**Предусловия:**
- Все статические проверки из задачи 5 зелёные.
- Есть свежая Windows Release-сборка; переносить в VM минимум `silentgate.exe` и `data\app.so`, предпочтительно всю папку `Release`.
- Использовать только документационные тестовые данные; боевые URL и секреты не класть в логи и артефакты.
- Убедиться, что команды выполняются внутри гостя, а не на хосте.

- [ ] **Шаг 1: Подготовить два тестовых процесса с одинаковым basename.**

  В disposable VM создать две временные папки и запустить два разрешённых тестовых exe, одинаково названных `claude.exe`, из разных каталогов. В список правил приложения добавить одно правило `byName=true` для `claude.exe`; не добавлять эти реальные пути вручную.

- [ ] **Шаг 2: Проверить материализацию обоих путей.**

  В журнале помощника или диагностическом выводе убедиться, что в свежем плане/наборе WFP присутствуют оба полных пути и отсутствует путь стороннего basename. Не публиковать полные пути, если они содержат пользовательское имя или секретные каталоги.

- [ ] **Шаг 3: Проверить запуск нового экземпляра после подключения.**

  Сначала поднять туннель с одним `claude.exe`, затем запустить второй `claude.exe` из другого каталога. Дождаться следующего прохода наблюдателя и убедиться по журналу/диагностике, что выполнено обновление держателя одной транзакцией и второй путь добавлен без снятия старого набора.

- [ ] **Шаг 4: Проверить точное правило по пути.**

  Повторить тест с `byName=false` для одного полного пути. Запустить одинаковый basename из двух каталогов и убедиться, что WFP-план содержит только выбранный путь, а второй не материализуется.

- [ ] **Шаг 5: Проверить отказ обновления без потери старой защиты.**

  В госте воспроизвести недоступный путь/ошибку добавления только в тестовой disposable-сессии и проверить, что журнал сообщает об ошибке, предыдущий набор не снимается, а цикл продолжает наблюдение. Не использовать для этого хост и не оставлять включённые фильтры после эксперимента.

- [ ] **Шаг 6: Проверить остановку ядра и явное отключение.**

  В VM остановить ядро и убедиться, что активная WFP-блокировка не снимается до штатной команды отключения/смерти интерфейса. Затем выполнить disconnect, убедиться по журналу, что hold освобождён и сеть восстановилась.

- [ ] **Шаг 7: Погасить стенд и сохранить только безопасные результаты.**

  После завершения проверки выполнить:
  ```text
  Stop-VM -Name SG-Test -Force
  ```
  Не коммитить журналы с полными путями, IP или токенами. В итоговом сообщении указать только PASS/FAIL и безопасное краткое описание.

---

## Итоговые критерии готовности

1. Правило `byName=true` сохраняется как basename и матчится со всеми текущими полными путями этого имени, независимо от каталога.
2. Правило `byName=false` по-прежнему покрывает только сохранённый полный путь.
3. Другие basename не попадают в WFP-план.
4. Новый процесс после подключения добавляется через `KillSwitchHold.reengage()` атомарно.
5. Ошибка обновления оставляет старый рабочий набор фильтров.
6. Пустой `onlySelected` без запущенного выбранного процесса не блокирует запуск туннеля.
7. Старые JSON-планы читаются без миграции и получают пустые списки имён.
8. `flutter analyze` и полный `flutter test` проходят.
9. Живая проверка выполнена только в `SG-Test`, после чего VM остановлена.
10. Релиз не выпускается без отдельной команды владельца.
