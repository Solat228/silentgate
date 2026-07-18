import '../xray/outbound_variant.dart';

/// Пользовательская правка сервера (по ключу сервера), независимая от закрепления (пина):
///  - variant — рабочая вариация обхода (из автонастройки/умного подбора);
///  - rawJson — полный сырой Xray-JSON (из редактора JSON), применяется как есть при подключении.
class ServerOverride {
  final OutboundVariant? variant;
  final String? rawJson;

  const ServerOverride({this.variant, this.rawJson});

  bool get isEmpty => variant == null && (rawJson == null || rawJson!.isEmpty);

  ServerOverride copyWith({
    OutboundVariant? variant,
    String? rawJson,
    bool clearVariant = false,
    bool clearJson = false,
  }) {
    return ServerOverride(
      variant: clearVariant ? null : (variant ?? this.variant),
      rawJson: clearJson ? null : (rawJson ?? this.rawJson),
    );
  }

  Map<String, dynamic> toJson() => {
        if (variant != null) 'variant': variant!.toJson(),
        if (rawJson != null) 'rawJson': rawJson,
      };

  factory ServerOverride.fromJson(Map<String, dynamic> j) => ServerOverride(
        variant: j['variant'] is Map
            ? OutboundVariant.fromJson((j['variant'] as Map).cast<String, dynamic>())
            : null,
        rawJson: j['rawJson'] as String?,
      );
}
