/// Параметры фрагментации TLS ClientHello (DPI-обход) для freedom-outbound.
class FragmentParams {
  final String packets; // напр. 'tlshello'
  final String length; // напр. '100-200'
  final String interval; // напр. '10-20'
  const FragmentParams({
    this.packets = 'tlshello',
    this.length = '100-200',
    this.interval = '10-20',
  });

  Map<String, dynamic> toJson() => {
        'packets': packets,
        'length': length,
        'interval': interval,
      };
}

/// Вариация настроек outbound для автонастройки: с фрагментацией и/или другим uTLS-fingerprint.
class OutboundVariant {
  final bool fragment;
  final String? fingerprint;
  final FragmentParams params;

  const OutboundVariant({
    this.fragment = false,
    this.fingerprint,
    this.params = const FragmentParams(),
  });

  static const OutboundVariant none = OutboundVariant();

  bool get isNone => !fragment && fingerprint == null;

  String get label {
    if (isNone) return 'обычный';
    final parts = <String>[];
    if (fragment) parts.add('fragment');
    if (fingerprint != null) parts.add('fp:$fingerprint');
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'fragment': fragment,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory OutboundVariant.fromJson(Map<String, dynamic> j) => OutboundVariant(
        fragment: j['fragment'] as bool? ?? false,
        fingerprint: j['fingerprint'] as String?,
      );
}
