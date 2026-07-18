import '../models/vpn_server.dart';

/// Строит outbound sing-box из [VpnServer].
///
/// Нужен ровно для протоколов, которых нет в Xray — сейчас это **hysteria2**
/// (QUIC + собственный congestion control). Xray его не поддерживает и не
/// планирует, поэтому такие серверы поднимает sing-box, который уже лежит рядом
/// ради TUN. Лицензия sing-box (GPL) допускает только запуск отдельным
/// процессом — так он и запускается, без линковки (см. CLAUDE.md).
class SingboxOutboundFactory {
  /// Умеем ли мы построить outbound для этого сервера.
  static bool supports(VpnServer s) => s.protocol == 'hysteria2';

  static Map<String, dynamic> build(VpnServer s, {String tag = 'proxy'}) {
    if (s.protocol != 'hysteria2') {
      throw ArgumentError('sing-box-outbound не умеет протокол ${s.protocol}');
    }

    final ports = _serverPorts(s.hopPorts);
    final obfs = _obfs(s);
    final out = <String, dynamic>{
      'type': 'hysteria2',
      'tag': tag,
      'server': s.address,
      // Порт-хоппинг: sing-box требует ЛИБО server_port, ЛИБО server_ports.
      if (ports == null) 'server_port': s.port else 'server_ports': ports,
      if (ports != null) 'hop_interval': '30s',
      if (s.id.isNotEmpty) 'password': s.id,
      if (obfs != null) 'obfs': obfs,
      // У hysteria2 транспорт — QUIC, TLS есть всегда и отключить его нельзя.
      'tls': {
        'enabled': true,
        if ((s.sni ?? '').isNotEmpty) 'server_name': s.sni,
        if (s.allowInsecure) 'insecure': true,
        if ((s.alpn ?? '').isNotEmpty)
          'alpn': s.alpn!.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
      },
    };
    return out;
  }

  /// Блок обфускации — или null, если её нет.
  ///
  /// Проверять обязательно: sing-box валит **весь конфиг**, а не один outbound,
  /// если тип не `salamander` или пароль пуст (`FATAL initialize outbound[0]:
  /// missing obfs password` / `unknown obfs type: none`). А написать `obfs=none`
  /// в ссылке — обычный способ сказать «без обфускации», и такая ссылка не должна
  /// убивать подключение ко всем остальным серверам сразу.
  static Map<String, dynamic>? _obfs(VpnServer s) {
    final type = (s.obfs ?? '').trim().toLowerCase();
    final password = (s.obfsPassword ?? '').trim();
    if (type != 'salamander' || password.isEmpty) return null;
    return {'type': 'salamander', 'password': password};
  }

  /// `mport=1000-2000,3000` → `["1000:2000", "3000:3000"]` (формат sing-box).
  /// null — хоппинг не задан или задан мусором, тогда используется обычный
  /// server_port: это лучше, чем `bad port range` и мёртвый конфиг целиком.
  static List<String>? _serverPorts(String? mport) {
    final raw = (mport ?? '').trim();
    if (raw.isEmpty) return null;
    final ranges = <String>[];
    for (final part in raw.split(RegExp(r'[,\s]+'))) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final m = RegExp(r'^(\d+)\s*[-:]\s*(\d+)$').firstMatch(p);
      if (m != null) {
        final a = int.tryParse(m.group(1)!);
        final b = int.tryParse(m.group(2)!);
        final range = _range(a, b);
        if (range != null) ranges.add(range);
        continue;
      }
      final single = int.tryParse(p);
      final one = _range(single, single);
      if (one != null) ranges.add(one);
    }
    return ranges.isEmpty ? null : ranges;
  }

  /// Диапазон портов в границах uint16; перевёрнутый разворачиваем, а не
  /// отдаём как есть — иначе хоппинг молча не работает.
  static String? _range(int? a, int? b) {
    if (a == null || b == null) return null;
    final lo = a <= b ? a : b;
    final hi = a <= b ? b : a;
    if (lo < 1 || hi > 65535) return null;
    return '$lo:$hi';
  }
}
