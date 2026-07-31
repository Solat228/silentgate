# Как приложения узнаю́т про VPN и что с этим можно сделать

Исследование по просьбе владельца (первоочередной пункт `docs/BACKLOG.md`).
Дата: 01.08.2026. Все утверждения — со ссылками, тип источника помечен.

**Граница, которую держим явно:** цель — приватность пользователя, а не обман систем
безопасности банков и антифрода. Разбираем, какие следы VPN видны обычным приложениям и как
не отдавать лишнего. Приёмы, применимые только для обмана проверок безопасности, в план не
берём.

---

## Короткий вывод

Факт включённого VPN на Android **скрыть от приложения нельзя** — он отдаётся системой по
документированному API без единого разрешения. Всё, что предлагается в статьях «как спрятать
VPN», либо требует root с модулем ядра, либо путает «спрятать VPN» с «сменить выходной IP».

Единственный способ, работающий без root и подтверждённый документацией Android, —
**не пускать приложение в туннель вообще**. Тогда оно, по формулировке самой документации,
«использует системную сеть так, будто VPN не запущен». У SilentGate этот механизм уже есть —
раздельное туннелирование по приложениям.

Отдельно от факта VPN стоит вопрос заметности **трафика** для сервера на той стороне: тут
работают Reality и uTLS, и они у нас уже задействованы.

---

## Что видно приложению на Android

| Признак | Как обнаруживается | Разрешения | Скрыть без root |
|---|---|---|---|
| Активная сеть помечена VPN | `NetworkCapabilities.hasTransport(TRANSPORT_VPN)` | **не нужны** | нельзя |
| Отсутствие метки «не VPN» | `NET_CAPABILITY_NOT_VPN` | **не нужны** | нельзя |
| Чужой VPN держит интерфейс | `VpnService.prepare()` вернёт не-null | не нужны | нельзя |
| Интерфейс `tun0` в списке | `NetworkInterface.getNetworkInterfaces()` | не нужны | нет данных |
| Чтение `/proc/net` | закрыто системой с Android 10 | — | **уже закрыто** |
| Значок ключа в статусбаре | виден пользователю, не приложению | — | нельзя |

**Главное — первая строка.** Чтение состояния сети не требует разрешений вовсе:
«Using `NetworkCallback` and other ways of finding out about the connectivity state of the
device doesn't require any particular permission»
([документация Android](https://developer.android.com/develop/connectivity/network-ops/reading-network-state)).
Проверка сводится к двум строкам кода и доступна любому приложению из магазина.

С Android 9 система ещё и **сливает возможности нижележащих сетей** в описание VPN-сети, если
VPN-клиент вызвал `setUnderlyingNetworks()` — то есть приложение видит и VPN, и то, поверх чего
он поднят ([NetworkCapabilities](https://developer.android.com/reference/android/net/NetworkCapabilities)).

Про `/proc/net`: «On devices that run Android 10 or higher, apps cannot access `/proc/net`,
which includes information about a device's network state»
([изменения приватности Android 10](https://developer.android.com/about/versions/10/privacy/changes)).
Это закрывает часть низкоуровневых проверок, но не главную — та идёт через штатный API.
Работает ли после этого `NetworkInterface.getNetworkInterfaces()` для `tun0`, документация не
говорит; **проверять надо живым тестом на устройстве**, я этого не делал.

---

## Скрыть НЕЛЬЗЯ — и это надо говорить пользователю

Проект [`okhsunrog/vpnhide`](https://github.com/okhsunrog/vpnhide) *(репозиторий)* — самая
полная известная попытка спрятать VPN от выбранных приложений. Что она требует:

- **root**;
- модуль ядра (kmod для GKI, KPM для старых ядер) либо Zygisk как запасной вариант;
- LSPosed/Vector для перехвата на уровне Java;
- отдельный модуль для сокрытия локальных портов.

То есть: перехват на трёх уровнях сразу, с правами, которых у обычного пользователя нет.
**Вывод: без root факт VPN не прячется.** Обещать это в интерфейсе нельзя.

Статьи вида «как скрыть VPN на Android» *(популярные статьи, не документация)* — например
[AEANET](https://www.aeanet.org/how-to-hide-vpn-on-android-phone/) — под «сокрытием» понимают
обфускацию трафика и смену выходного IP. Это про другое: они помогают против блокировки по
адресу и против DPI, но приложение на телефоне всё равно увидит `TRANSPORT_VPN`.

---

## Что РАБОТАЕТ без root

**Исключить приложение из туннеля.** Документация Android прямо:

> «Disallowed apps use system networking as if the VPN wasn't running — all other apps use the VPN»
> ([VpnService.Builder](https://developer.android.com/reference/android/net/VpnService.Builder), *документация*)

Исключённое приложение работает так, будто VPN нет: его активная сеть — физическая, без метки
VPN. Это единственный документированный способ, и он у нас **уже реализован** — раздельное
туннелирование по приложениям (`include_package` / `exclude_package` в конфиге).

⚠️ Тонкость нашей реализации, которую стоит знать: в режиме «только отмеченные через VPN» в
туннель попадают ТОЛЬКО перечисленные приложения (`include_package`), остальные система туда не
заводит вовсе. То есть для неотмеченных приложений VPN уже невидим — без каких-либо
дополнительных усилий.

С Android 17 появился системный экран выбора исключений — `ACTION_VPN_APP_EXCLUSION_SETTINGS`
([документация](https://developer.android.com/reference/android/net/VpnService)); стоит
поддержать, когда дойдут руки: пользователю привычнее системный интерфейс.

---

## Заметность трафика для сервера на той стороне

Это отдельный вопрос: не «есть ли у тебя VPN», а «похож ли твой трафик на обычный».

**Reality + uTLS** — то, чем мы уже пользуемся. uTLS повторяет рукопожатие выбранного браузера
байт в байт, поэтому отпечаток JA3/JA4 совпадает с миллионами настоящих пользователей, и
отличить его, не заблокировав заодно живые браузеры, нельзя. Reality при этом подставляет
рукопожатие настоящего популярного сайта: на активную пробу сервер отдаёт подлинный ответ
чужого сайта ([разбор Reality](https://veepen.org/en/guides/what-is-utls) *(статья)*,
[DeepWiki по Xray-core](https://deepwiki.com/XTLS/Xray-core/3.2-tls-and-utls-configuration)
*(разбор репозитория)*).

⚠️ Не идеально: в самом Xray-core висит открытая проблема о том, что нормализация HTTP-заголовков
и модификация ClientHello создают отличимость по JA4
([issue #4900](https://github.com/XTLS/Xray-core/issues/4900) *(репозиторий)*). То есть «uTLS
включён» ≠ «неотличимо».

---

## Чего я НЕ проверил

Честно, чтобы не выдавать пробелы за результат:

- **Живой тест на устройстве**: видит ли `NetworkInterface.getNetworkInterfaces()` наш `tun0`
  на Android 11+. Документация об этом молчит, а проверка занимает десять минут на эмуляторе.
- **Windows**: аналогичное исследование не проводилось вовсе. Там адаптер wintun виден в
  системе, но какими API это читают обычные программы — не разбирал.
- **Сетевые признаки** (MTU/MSS, TTL, отпечаток стека gvisor против системного) — не
  исследованы. У нас есть выбор стека `system|gvisor|mixed`, и он теоретически влияет на
  отпечаток TCP/IP, но подтверждения этому я не искал.
- **Утечки** (WebRTC, рассогласование DNS и выходного IP) — не разбирал в этом заходе.

---

## Что сделать в SilentGate

По убыванию пользы:

1. **Объяснить пользователю правду в интерфейсе.** Сейчас нигде не сказано, что факт VPN виден
   приложениям. Написать прямо: спрятать VPN нельзя, но можно не пускать приложение в туннель —
   тогда оно VPN не увидит. Сложность: низкая, только тексты.
2. **Подсказка на экране правил:** если приложение помечено «Прямо», добавить пояснение, что оно
   вдобавок перестаёт видеть VPN. Это превращает существующую функцию в осознанный инструмент.
   Сложность: низкая.
3. **Живой тест `tun0`** на эмуляторе — закрыть пробел выше. Сложность: низкая.
4. **Поддержать `ACTION_VPN_APP_EXCLUSION_SETTINGS`** на Android 17+. Сложность: средняя.
5. **Исследовать сетевые признаки** (MTU/MSS, стек) отдельным заходом. Сложность: средняя,
   польза неясна до замеров.

Чего делать НЕ надо: обещать «невидимость VPN». Без root это неправда, и первый же пользователь,
проверивший приложением-детектором, поймает нас на слове.

---

## Источники

**Документация:**
- [Read network state](https://developer.android.com/develop/connectivity/network-ops/reading-network-state) — разрешения не нужны
- [NetworkCapabilities](https://developer.android.com/reference/android/net/NetworkCapabilities) — `TRANSPORT_VPN`, `NET_CAPABILITY_NOT_VPN`, слияние возможностей с Android 9
- [VpnService.Builder](https://developer.android.com/reference/android/net/VpnService.Builder) — `addDisallowedApplication`, `allowBypass`
- [VpnService](https://developer.android.com/reference/android/net/VpnService) — `prepare()`, экран исключений Android 17
- [Privacy changes in Android 10](https://developer.android.com/about/versions/10/privacy/changes) — закрытие `/proc/net`

**Репозитории:**
- [okhsunrog/vpnhide](https://github.com/okhsunrog/vpnhide) — сокрытие VPN требует root + модуль ядра
- [Xray-core issue #4900](https://github.com/XTLS/Xray-core/issues/4900) — отличимость по JA4
- [DeepWiki: Xray TLS/uTLS](https://deepwiki.com/XTLS/Xray-core/3.2-tls-and-utls-configuration)

**Статьи (проверять критически):**
- [What Is uTLS? TLS Fingerprinting and Reality Explained](https://veepen.org/en/guides/what-is-utls)
- [How to Hide VPN on Android Phone](https://www.aeanet.org/how-to-hide-vpn-on-android-phone/) — под «сокрытием» понимает обфускацию, не сокрытие факта VPN
