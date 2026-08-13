import 'dart:io';

import 'android/probe_harness_android.dart';

import '../core/probe/icmp_pinger.dart';
import '../core/probe/probe_harness.dart';
import 'windows/icmp_ping_windows.dart';
import 'windows/probe/mixed_probe_harness.dart';

/// Есть ли на этой платформе проброс-харнесс — отдельный экземпляр ядра с
/// локальными http-inbound'ами, через который проверяется, реально ли сервер
/// проксирует трафик (фаза 2 пинга).
///
/// Есть на обеих платформах, но устроен по-разному. На Windows ядро — процесс,
/// и временный экземпляр просто запускается рядом с рабочим. На Android ядро —
/// библиотека в нашем же процессе, и `LibXray.ping` поднимает СВОЙ `core.New`
/// на время одного замера, не трогая глобальный экземпляр под живым туннелем.
///
/// ⚠️ ПРЕЖНЯЯ РЕДАКЦИЯ ЭТОГО КОММЕНТАРИЯ УТВЕРЖДАЛА ОБРАТНОЕ — «на Android
/// второй экземпляр не поднять, пинг остаётся одной фазой». Уже неверное, оно
/// пережило и появление андроидного харнесса, и правку ниже по коду
/// (`Platform.isAndroid` в самом выражении), и дыру, из-за которой инбаунд
/// харнесса там всё это время слушал 127.0.0.1 без пароля: комментарий
/// объяснял, почему инбаунда «нет», и его никто не искал.
bool get proxyProbeSupported => Platform.isWindows || Platform.isAndroid;

/// Умеет ли харнесс ПРОПУСКАТЬ ЗАПРОСЫ через кандидата, а не только мерить
/// задержку. От этого зависит вся автонастройка: она смотрит, открывается ли
/// сервис ЧЕРЕЗ сервер.
///
/// На Android — нет, и разница тонкая: инбаунд там ПОДНИМАЕТСЯ (настоящий
/// http-прокси на 127.0.0.1, потому и закрыт паролем — см.
/// `ProbeHarnessAndroid`), но его единственный потребитель — сам `LibXray.ping`
/// внутри вызова; порт наружу не отдаётся, послать через него свой запрос
/// неоткуда. Признак нужен ИНТЕРФЕЙСУ, чтобы сказать об этом сразу, а не после
/// того, как человек настроил стратегию и нажал «Начать».
bool get autoConfigSupported => Platform.isWindows;

/// Проброс-харнесс под текущую платформу.
/// Ядро выбирается по протоколу кандидата: hysteria2 — sing-box, остальное — Xray.
ProbeHarness createProbeHarness() {
  if (Platform.isWindows) return MixedProbeHarness();
  // ⚠️ Прежний вывод «на Android харнесса быть не может» неверен: он справедлив
  // для ТУННЕЛЯ (VpnService один), но не для замера — `LibXray.ping` поднимает
  // свой экземпляр ядра и гасит его сразу. Из-за этой ошибки hysteria2 и
  // панельные профили «Авто» не пингуались вообще.
  if (Platform.isAndroid) return ProbeHarnessAndroid();
  throw UnsupportedError(
      'Проброс-харнесс на ${Platform.operatingSystem} не поддерживается — '
      'проверяйте proxyProbeSupported перед вызовом');
}

/// Поддерживается ли ICMP-пинг.
///
/// На Android сырые ICMP-сокеты без root недоступны, а разбор вывода
/// `/system/bin/ping` — отдельная задача плана.
bool get icmpSupported => Platform.isWindows;

/// ICMP-пингер под текущую платформу.
IcmpPinger createIcmpPinger() {
  if (Platform.isWindows) return IcmpPingWindows();
  throw UnsupportedError('ICMP на ${Platform.operatingSystem} не поддерживается');
}
