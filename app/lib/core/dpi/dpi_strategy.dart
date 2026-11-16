import 'dart:typed_data';

import '../settings/app_settings.dart';
import 'dpi_bypass_proxy.dart';

/// Один TCP-сегмент, отправляемый при десинхронизации первого пакета (`ClientHello` / HTTP).
class DpiDesyncSegment {
  /// Байты сегмента. Если [isOob] равен `true`, последний байт — это срочный
  /// байт `MSG_OOB` (`0x61` `'a'`), который стандартные TLS/HTTP-серверы без
  /// `SO_OOBINLINE` отбрасывают вне потока, а анализатор ТСПУ склеивает прямо
  /// внутрь имени хоста SNI.
  final Uint8List bytes;

  /// Отправлять ли сегмент с флагом `MSG_OOB` (TCP Urgent Pointer на последнем байте).
  final bool isOob;

  const DpiDesyncSegment(this.bytes, {this.isOob = false});

  /// Безопасная копия без OOB-байта для платформ/сокетов, не поддерживающих `MSG_OOB`.
  Uint8List bytesWithoutOob() {
    if (!isOob) return bytes;
    if (bytes.length <= 1) return Uint8List(0);
    return Uint8List.sublistView(bytes, 0, bytes.length - 1);
  }
}

/// Смещения расширения `server_name` (`0x0000`) внутри payload первой записи TLS `ClientHello`.
class TlsSniOffsets {
  /// Начало ASCII-имени хоста внутри `payload` (`data[5 + hostStart]`).
  final int hostStart;

  /// Длина ASCII-имени хоста.
  final int hostLength;

  /// Рекомендуемая точка разреза внутри имени хоста.
  final int splitOffset;

  const TlsSniOffsets({
    required this.hostStart,
    required this.hostLength,
    required this.splitOffset,
  });
}

/// Конфигурация стратегии обхода DPI (встроенный движок класса `Zapret` / `ByeDPI`).
class DpiDesyncConfig {
  final DpiStrategyPreset preset;
  final bool useOob;
  final bool tlsRecordSplit;
  final int firstSplitPos;
  final bool httpHostMixedCase;

  const DpiDesyncConfig({
    this.preset = DpiStrategyPreset.tlsrecSplit2Sni,
    this.useOob = false,
    this.tlsRecordSplit = true,
    this.firstSplitPos = 2,
    this.httpHostMixedCase = false,
  });

  /// Классическая совместимая конфигурация по умолчанию (для вызовов без настроек).
  static const DpiDesyncConfig legacyDefault = DpiDesyncConfig(
    preset: DpiStrategyPreset.tlsrecSplit2Sni,
    useOob: false,
    tlsRecordSplit: true,
    firstSplitPos: 2,
    httpHostMixedCase: false,
  );

  /// Список всех боевых пресетов для автоподбора (в порядке убывания пробивной силы на ТСПУ РФ).
  static const List<DpiStrategyPreset> autoTuneOrder = [
    DpiStrategyPreset.tlsrecSniOob,
    DpiStrategyPreset.tcpOobSni,
    DpiStrategyPreset.tcpMultisplitSni,
    DpiStrategyPreset.tlsrecSniSplit,
    DpiStrategyPreset.tcpMicroSplitHostCase,
    DpiStrategyPreset.tlsrecSplit2Sni,
  ];

  factory DpiDesyncConfig.fromPreset(DpiStrategyPreset preset) {
    switch (preset) {
      case DpiStrategyPreset.auto:
      case DpiStrategyPreset.tlsrecSniOob:
        return DpiDesyncConfig(
          preset: preset,
          useOob: true,
          tlsRecordSplit: true,
          firstSplitPos: 1,
          httpHostMixedCase: true,
        );
      case DpiStrategyPreset.tcpOobSni:
        return const DpiDesyncConfig(
          preset: DpiStrategyPreset.tcpOobSni,
          useOob: true,
          tlsRecordSplit: false,
          firstSplitPos: 2,
          httpHostMixedCase: true,
        );
      case DpiStrategyPreset.tlsrecSniSplit:
        return const DpiDesyncConfig(
          preset: DpiStrategyPreset.tlsrecSniSplit,
          useOob: false,
          tlsRecordSplit: true,
          firstSplitPos: 1,
          httpHostMixedCase: true,
        );
      case DpiStrategyPreset.tcpMultisplitSni:
        return const DpiDesyncConfig(
          preset: DpiStrategyPreset.tcpMultisplitSni,
          useOob: false,
          tlsRecordSplit: false,
          firstSplitPos: 1,
          httpHostMixedCase: true,
        );
      case DpiStrategyPreset.tcpMicroSplitHostCase:
        return const DpiDesyncConfig(
          preset: DpiStrategyPreset.tcpMicroSplitHostCase,
          useOob: false,
          tlsRecordSplit: false,
          firstSplitPos: 2,
          httpHostMixedCase: true,
        );
      case DpiStrategyPreset.tlsrecSplit2Sni:
        return legacyDefault;
      case DpiStrategyPreset.custom:
        return const DpiDesyncConfig(
          preset: DpiStrategyPreset.custom,
          useOob: true,
          tlsRecordSplit: true,
          firstSplitPos: 2,
          httpHostMixedCase: true,
        );
    }
  }

  factory DpiDesyncConfig.fromSettings(AppSettings s) {
    if (s.dpiStrategy == DpiStrategyPreset.custom) {
      return DpiDesyncConfig(
        preset: DpiStrategyPreset.custom,
        useOob: s.dpiUseOob,
        tlsRecordSplit: s.dpiTlsRecordSplit,
        firstSplitPos: s.dpiFirstSplitPos.clamp(1, 32),
        httpHostMixedCase: s.dpiHttpHostMixedCase,
      );
    }
    return DpiDesyncConfig.fromPreset(s.dpiStrategy);
  }

  static String presetTitleRu(DpiStrategyPreset p) {
    switch (p) {
      case DpiStrategyPreset.auto:
        return 'Авто (TLS Record + OOB в SNI)';
      case DpiStrategyPreset.tlsrecSniOob:
        return 'Zapret OOB + TLS Record Split';
      case DpiStrategyPreset.tcpOobSni:
        return 'ByeDPI TCP Disorder / OOB в SNI';
      case DpiStrategyPreset.tlsrecSniSplit:
        return 'TLS 4-Record Multisplit по SNI (без OOB)';
      case DpiStrategyPreset.tcpMultisplitSni:
        return 'TCP Multisplit по SNI (сырые сегменты)';
      case DpiStrategyPreset.tcpMicroSplitHostCase:
        return 'TCP Micro-Split + hOsT Case';
      case DpiStrategyPreset.tlsrecSplit2Sni:
        return 'Классический TLS Split (pos=2 + SNI)';
      case DpiStrategyPreset.custom:
        return 'Своя настройка параметров';
    }
  }

  static String presetSubtitleRu(DpiStrategyPreset p) {
    switch (p) {
      case DpiStrategyPreset.auto:
        return 'Рекомендуется: дробление TLS-рекордов по началу и середине SNI + срочный байт MSG_OOB';
      case DpiStrategyPreset.tlsrecSniOob:
        return 'Максимальная пробивная сила на ТСПУ РФ (YouTube, Discord, Rutracker)';
      case DpiStrategyPreset.tcpOobSni:
        return 'Сырой разрез TCP на 2-м байте и внутри SNI с байтом MSG_OOB (как ciadpi -o 2 --oob)';
      case DpiStrategyPreset.tlsrecSniSplit:
        return '4 легитимных TLS-рекорда вокруг SNI — подходит, если роутер режет TCP URG/OOB';
      case DpiStrategyPreset.tcpMultisplitSni:
        return '4 отдельных TCP-сегмента без дополнительных заголовков TLS';
      case DpiStrategyPreset.tcpMicroSplitHostCase:
        return 'Мелкая нарезка первых 10 байт по 2 байта + разрез SNI + смена регистра Host';
      case DpiStrategyPreset.tlsrecSplit2Sni:
        return 'Базовый 3-рекордный сплит (совместимый режим)';
      case DpiStrategyPreset.custom:
        return 'Ручной выбор OOB, TLS-рекордов, позиции разреза и HTTP Host';
    }
  }

  String get titleRu => presetTitleRu(preset);
  String get subtitleRu => presetSubtitleRu(preset);

  /// Найти точные смещения имени хоста внутри расширения `server_name` (`0x0000`)
  /// относительно `payload` (`data[5..]`).
  static TlsSniOffsets? inspectSniOffsets(Uint8List payload) {
    if (payload.length < 42 || payload[0] != 0x01) return null;
    var pos = 38;

    final sidLen = payload[pos];
    pos += 1 + sidLen;
    if (pos + 2 > payload.length) return null;

    final csLen = (payload[pos] << 8) | payload[pos + 1];
    pos += 2 + csLen;
    if (pos + 1 > payload.length) return null;

    final compLen = payload[pos];
    pos += 1 + compLen;
    if (pos + 2 > payload.length) return null;

    final extTotalLen = (payload[pos] << 8) | payload[pos + 1];
    pos += 2;
    final extEnd = (pos + extTotalLen).clamp(0, payload.length);

    while (pos + 4 <= extEnd) {
      final extType = (payload[pos] << 8) | payload[pos + 1];
      final extLen = (payload[pos + 2] << 8) | payload[pos + 3];
      pos += 4;
      if (pos + extLen > extEnd) break;
      if (extType == 0x0000 && extLen >= 6) {
        final hostLen = (payload[pos + 3] << 8) | payload[pos + 4];
        final hostStart = pos + 5;
        if (hostStart + 1 < payload.length && hostLen >= 2) {
          final mid = (hostStart + (hostLen > 4 ? 2 : 1)).clamp(
            hostStart + 1,
            payload.length - 1,
          );
          return TlsSniOffsets(
            hostStart: hostStart,
            hostLength: hostLen,
            splitOffset: mid,
          );
        }
      }
      pos += extLen;
    }
    return null;
  }

  /// Разбить первый пакет (`ClientHello` или plain HTTP) на список сегментов
  /// согласно выбранной стратегии.
  List<DpiDesyncSegment> buildSegments(
    Uint8List data, {
    required bool socketSupportsOob,
  }) {
    if (data.isEmpty) return const [];
    final canOob = useOob && socketSupportsOob;

    if (TlsClientHelloFragmenter.isTlsClientHello(data)) {
      if (preset == DpiStrategyPreset.tlsrecSplit2Sni) {
        return [
          for (final c in TlsClientHelloFragmenter.fragmentFirstPacket(data))
            DpiDesyncSegment(c),
        ];
      }

      final recordLen = (data[3] << 8) | data[4];
      if (recordLen > 6 && 5 + recordLen <= data.length) {
        final major = data[1];
        final minor = data[2];
        final payload = Uint8List.sublistView(data, 5, 5 + recordLen);
        final tail = data.length > 5 + recordLen
            ? Uint8List.fromList(Uint8List.sublistView(data, 5 + recordLen))
            : null;
        final sni = inspectSniOffsets(payload);

        switch (preset) {
          case DpiStrategyPreset.auto:
          case DpiStrategyPreset.tlsrecSniOob:
            return _buildTlsRecSniOob(
              major: major,
              minor: minor,
              payload: payload,
              sni: sni,
              tail: tail,
              canOob: canOob,
            );
          case DpiStrategyPreset.tcpOobSni:
            return _buildTcpOobSni(
              data: data,
              recordEnd: 5 + recordLen,
              sni: sni,
              canOob: canOob,
              firstPos: 2,
            );
          case DpiStrategyPreset.tlsrecSniSplit:
            return _buildTlsRecSniOob(
              major: major,
              minor: minor,
              payload: payload,
              sni: sni,
              tail: tail,
              canOob: false,
            );
          case DpiStrategyPreset.tcpMultisplitSni:
            return _buildTcpMultisplit(
              data: data,
              recordEnd: 5 + recordLen,
              sni: sni,
            );
          case DpiStrategyPreset.tcpMicroSplitHostCase:
            return _buildTcpMicroSplit(
              data: data,
              recordEnd: 5 + recordLen,
              sni: sni,
            );
          case DpiStrategyPreset.custom:
            if (tlsRecordSplit) {
              return _buildCustomTlsRec(
                major: major,
                minor: minor,
                payload: payload,
                sni: sni,
                tail: tail,
                firstPos: firstSplitPos,
                canOob: canOob,
              );
            } else {
              return _buildTcpOobSni(
                data: data,
                recordEnd: 5 + recordLen,
                sni: sni,
                canOob: canOob,
                firstPos: firstSplitPos,
              );
            }
          case DpiStrategyPreset.tlsrecSplit2Sni:
            break;
        }
      }
    }

    return _buildHttpSegments(data, canOob: canOob);
  }

  List<DpiDesyncSegment> _buildTlsRecSniOob({
    required int major,
    required int minor,
    required Uint8List payload,
    required TlsSniOffsets? sni,
    required Uint8List? tail,
    required bool canOob,
  }) {
    final len = payload.length;
    final p1 = 1.clamp(1, len - 1);
    final hostStart = sni != null && sni.hostStart > p1 + 1 && sni.hostStart < len - 1
        ? sni.hostStart
        : (len ~/ 3).clamp(p1 + 1, len - 1);
    final hostMid = sni != null && sni.splitOffset > hostStart && sni.splitOffset < len
        ? sni.splitOffset
        : ((hostStart + len) ~/ 2).clamp(hostStart + 1, len);

    final out = <DpiDesyncSegment>[];
    if (canOob && hostMid > hostStart && hostMid < len) {
      // Рекорд 1: до начала SNI; Рекорд 2: первые символы SNI + срочный байт 0x61;
      // Рекорд 3: хвост SNI и остаток ClientHello.
      out.add(DpiDesyncSegment(
        _wrapTls(major, minor, Uint8List.sublistView(payload, 0, hostStart)),
      ));
      final rec2 = _wrapTls(
        major,
        minor,
        Uint8List.sublistView(payload, hostStart, hostMid),
      );
      out.add(DpiDesyncSegment(_appendOobByte(rec2), isOob: true));
      out.add(DpiDesyncSegment(
        _wrapTls(major, minor, Uint8List.sublistView(payload, hostMid)),
      ));
    } else {
      // 4 валидных TLS-рекорда: [0..1], [1..hostStart], [hostStart..hostMid], [hostMid..end]
      final cuts = <int>{0, p1, hostStart, hostMid, len}.toList()..sort();
      for (var i = 0; i + 1 < cuts.length; i++) {
        if (cuts[i + 1] > cuts[i]) {
          out.add(DpiDesyncSegment(_wrapTls(
            major,
            minor,
            Uint8List.sublistView(payload, cuts[i], cuts[i + 1]),
          )));
        }
      }
    }
    if (tail != null && tail.isNotEmpty) {
      out.add(DpiDesyncSegment(tail));
    }
    return out;
  }

  List<DpiDesyncSegment> _buildCustomTlsRec({
    required int major,
    required int minor,
    required Uint8List payload,
    required TlsSniOffsets? sni,
    required Uint8List? tail,
    required int firstPos,
    required bool canOob,
  }) {
    final len = payload.length;
    final p1 = firstPos.clamp(1, len - 1);
    final mid = sni != null && sni.splitOffset > p1 && sni.splitOffset < len
        ? sni.splitOffset
        : (len ~/ 2 > p1 ? len ~/ 2 : null);

    final out = <DpiDesyncSegment>[];
    if (mid != null) {
      out.add(DpiDesyncSegment(
        _wrapTls(major, minor, Uint8List.sublistView(payload, 0, p1)),
      ));
      final rec2 = _wrapTls(major, minor, Uint8List.sublistView(payload, p1, mid));
      if (canOob) {
        out.add(DpiDesyncSegment(_appendOobByte(rec2), isOob: true));
      } else {
        out.add(DpiDesyncSegment(rec2));
      }
      out.add(DpiDesyncSegment(
        _wrapTls(major, minor, Uint8List.sublistView(payload, mid)),
      ));
    } else {
      final rec1 = _wrapTls(major, minor, Uint8List.sublistView(payload, 0, p1));
      out.add(canOob
          ? DpiDesyncSegment(_appendOobByte(rec1), isOob: true)
          : DpiDesyncSegment(rec1));
      out.add(DpiDesyncSegment(
        _wrapTls(major, minor, Uint8List.sublistView(payload, p1)),
      ));
    }
    if (tail != null && tail.isNotEmpty) {
      out.add(DpiDesyncSegment(tail));
    }
    return out;
  }

  List<DpiDesyncSegment> _buildTcpOobSni({
    required Uint8List data,
    required int recordEnd,
    required TlsSniOffsets? sni,
    required bool canOob,
    required int firstPos,
  }) {
    final p1 = (5 + firstPos.clamp(1, 32)).clamp(1, data.length - 1);
    final sniWire = sni != null ? (5 + sni.splitOffset) : (recordEnd ~/ 2);
    final p2 = sniWire.clamp(p1 + 1, data.length);

    final out = <DpiDesyncSegment>[];
    out.add(DpiDesyncSegment(
      Uint8List.fromList(Uint8List.sublistView(data, 0, p1)),
    ));
    if (p2 < data.length) {
      final midSlice = Uint8List.fromList(Uint8List.sublistView(data, p1, p2));
      out.add(canOob
          ? DpiDesyncSegment(_appendOobByte(midSlice), isOob: true)
          : DpiDesyncSegment(midSlice));
      out.add(DpiDesyncSegment(
        Uint8List.fromList(Uint8List.sublistView(data, p2)),
      ));
    } else {
      final rest = Uint8List.fromList(Uint8List.sublistView(data, p1));
      out.add(canOob
          ? DpiDesyncSegment(_appendOobByte(rest), isOob: true)
          : DpiDesyncSegment(rest));
    }
    return out;
  }

  List<DpiDesyncSegment> _buildTcpMultisplit({
    required Uint8List data,
    required int recordEnd,
    required TlsSniOffsets? sni,
  }) {
    final cuts = <int>{
      0,
      2.clamp(1, data.length),
      6.clamp(1, data.length),
      if (sni != null) (5 + sni.hostStart).clamp(1, data.length),
      if (sni != null) (5 + sni.splitOffset).clamp(1, data.length),
      data.length,
    }.toList()
      ..sort();

    final out = <DpiDesyncSegment>[];
    for (var i = 0; i + 1 < cuts.length; i++) {
      if (cuts[i + 1] > cuts[i]) {
        out.add(DpiDesyncSegment(
          Uint8List.fromList(Uint8List.sublistView(data, cuts[i], cuts[i + 1])),
        ));
      }
    }
    return out;
  }

  List<DpiDesyncSegment> _buildTcpMicroSplit({
    required Uint8List data,
    required int recordEnd,
    required TlsSniOffsets? sni,
  }) {
    final cuts = <int>{
      0,
      for (var p = 2; p <= 10 && p < data.length; p += 2) p,
      if (sni != null) (5 + sni.hostStart).clamp(1, data.length),
      if (sni != null) (5 + sni.splitOffset).clamp(1, data.length),
      data.length,
    }.toList()
      ..sort();

    final out = <DpiDesyncSegment>[];
    for (var i = 0; i + 1 < cuts.length; i++) {
      if (cuts[i + 1] > cuts[i]) {
        out.add(DpiDesyncSegment(
          Uint8List.fromList(Uint8List.sublistView(data, cuts[i], cuts[i + 1])),
        ));
      }
    }
    return out;
  }

  List<DpiDesyncSegment> _buildHttpSegments(Uint8List data, {required bool canOob}) {
    var working = data;
    var splitAt = _findHttpHostSplit(working);
    if (splitAt != null && httpHostMixedCase) {
      working = Uint8List.fromList(working);
      // splitAt указывает на позицию между "Ho" и "st:" -> индексы h=splitAt-2, o=splitAt-1, s=splitAt, t=splitAt+1
      final hIdx = splitAt - 2;
      if (hIdx >= 0 && hIdx + 3 < working.length) {
        working[hIdx] = 0x68; // 'h'
        working[hIdx + 1] = 0x4F; // 'O'
        working[hIdx + 2] = 0x73; // 's'
        working[hIdx + 3] = 0x54; // 'T'
      }
    }
    splitAt ??= _findHttpHostSplit(working);
    if (splitAt != null && splitAt > 0 && splitAt < working.length) {
      final first = Uint8List.fromList(Uint8List.sublistView(working, 0, splitAt));
      final second = Uint8List.fromList(Uint8List.sublistView(working, splitAt));
      return [
        canOob
            ? DpiDesyncSegment(_appendOobByte(first), isOob: true)
            : DpiDesyncSegment(first),
        DpiDesyncSegment(second),
      ];
    }
    return [DpiDesyncSegment(working)];
  }

  static Uint8List _wrapTls(int major, int minor, Uint8List slice) {
    final len = slice.length;
    final out = Uint8List(5 + len);
    out[0] = 0x16;
    out[1] = major;
    out[2] = minor;
    out[3] = (len >> 8) & 0xFF;
    out[4] = len & 0xFF;
    out.setRange(5, 5 + len, slice);
    return out;
  }

  static Uint8List _appendOobByte(Uint8List src) {
    final out = Uint8List(src.length + 1);
    out.setRange(0, src.length, src);
    out[src.length] = 0x61; // 'a' — отбрасывается сервером при MSG_OOB
    return out;
  }

  static int? _findHttpHostSplit(Uint8List data) {
    if (data.length < 16) return null;
    final b0 = data[0];
    if (b0 != 0x47 && b0 != 0x50 && b0 != 0x48 && b0 != 0x4F) return null;
    final limit = data.length < 1024 ? data.length - 7 : 1024 - 7;
    for (var i = 0; i < limit; i++) {
      if (data[i] == 0x0D &&
          data[i + 1] == 0x0A &&
          (data[i + 2] | 0x20) == 0x68 &&
          (data[i + 3] | 0x20) == 0x6F &&
          (data[i + 4] | 0x20) == 0x73 &&
          (data[i + 5] | 0x20) == 0x74 &&
          data[i + 6] == 0x3A) {
        return i + 4;
      }
    }
    return null;
  }
}
