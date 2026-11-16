import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_info.dart';
import '../core/platform/app_paths.dart';
import '../core/support/dev_report_service.dart';

/// Режим отображения встроенного окна поддержки внутри приложения.
enum SupportWindowMode {
  /// Окно ещё не открывали (плавающий значок показывается, только если есть
  /// непрочитанные сообщения от оператора или черновик).
  hidden,

  /// Свёрнуто (по клику мимо окна или кнопкой «—») в плавающий значок поддержки
  /// со счётчиком непрочитанных ответов оператора.
  minimized,

  /// Развёрнуто поверх главного экрана внутри окна приложения.
  expanded,
}

class SupportFileItem {
  final String id;
  final String kind;
  final String name;
  final int? size;
  final String mime;

  const SupportFileItem({
    required this.id,
    required this.kind,
    required this.name,
    this.size,
    this.mime = '',
  });

  factory SupportFileItem.fromJson(Map<String, dynamic> j) => SupportFileItem(
        id: '${j['id'] ?? ''}',
        kind: '${j['kind'] ?? 'document'}',
        name: '${j['name'] ?? ''}',
        size: j['size'] is num ? (j['size'] as num).toInt() : null,
        mime: '${j['mime'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        if (size != null) 'size': size,
        'mime': mime,
      };
}

class SupportMessageItem {
  final int id;
  final String dir; // 'in' (от пользователя) | 'out' (от оператора)
  final String text;
  final int? at;
  final int? replyTo;
  final String replyText;
  final String offer;
  final List<SupportFileItem> files;

  const SupportMessageItem({
    required this.id,
    required this.dir,
    required this.text,
    this.at,
    this.replyTo,
    this.replyText = '',
    this.offer = '',
    this.files = const [],
  });

  bool get isOperator => dir == 'out';

  factory SupportMessageItem.fromJson(Map<String, dynamic> j) =>
      SupportMessageItem(
        id: (j['id'] is num)
            ? (j['id'] as num).toInt()
            : int.tryParse('${j['id'] ?? 0}') ?? 0,
        dir: '${j['dir'] ?? 'in'}',
        text: '${j['text'] ?? ''}',
        at: j['at'] is num
            ? (j['at'] as num).toInt()
            : int.tryParse('${j['at'] ?? ''}'),
        replyTo: j['reply_to'] is num
            ? (j['reply_to'] as num).toInt()
            : int.tryParse('${j['reply_to'] ?? ''}'),
        replyText: '${j['reply_text'] ?? ''}',
        offer: '${j['offer'] ?? ''}',
        files: (j['files'] is List)
            ? (j['files'] as List)
                .whereType<Map>()
                .map((m) => SupportFileItem.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'dir': dir,
        'text': text,
        if (at != null) 'at': at,
        if (replyTo != null) 'reply_to': replyTo,
        if (replyText.isNotEmpty) 'reply_text': replyText,
        if (offer.isNotEmpty) 'offer': offer,
        if (files.isNotEmpty) 'files': files.map((f) => f.toJson()).toList(),
      };
}

class SupportTicketItem {
  final int id;
  final String no;
  final String status; // 'open' | 'closed'
  final int? createdAt;
  final int? closedAt;
  final String name;
  final int? csat;
  final int? csatAt;
  final String csatComment;
  final int seen;
  final List<SupportMessageItem> messages;

  const SupportTicketItem({
    required this.id,
    required this.no,
    required this.status,
    this.createdAt,
    this.closedAt,
    this.name = '',
    this.csat,
    this.csatAt,
    this.csatComment = '',
    this.seen = 0,
    this.messages = const [],
  });

  bool get isOpen => status != 'closed';

  factory SupportTicketItem.fromJson(Map<String, dynamic> j) =>
      SupportTicketItem(
        id: (j['id'] is num)
            ? (j['id'] as num).toInt()
            : int.tryParse('${j['id'] ?? 0}') ?? 0,
        no: '${j['no'] ?? ''}',
        status: '${j['status'] ?? 'open'}',
        createdAt: j['created_at'] is num
            ? (j['created_at'] as num).toInt()
            : int.tryParse('${j['created_at'] ?? ''}'),
        closedAt: j['closed_at'] is num
            ? (j['closed_at'] as num).toInt()
            : int.tryParse('${j['closed_at'] ?? ''}'),
        name: '${j['name'] ?? ''}',
        csat: j['csat'] is num
            ? (j['csat'] as num).toInt()
            : int.tryParse('${j['csat'] ?? ''}'),
        csatAt: j['csat_at'] is num
            ? (j['csat_at'] as num).toInt()
            : int.tryParse('${j['csat_at'] ?? ''}'),
        csatComment: '${j['csat_comment'] ?? ''}',
        seen: (j['seen'] is num)
            ? (j['seen'] as num).toInt()
            : int.tryParse('${j['seen'] ?? 0}') ?? 0,
        messages: (j['messages'] is List)
            ? (j['messages'] as List)
                .whereType<Map>()
                .map((m) =>
                    SupportMessageItem.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'no': no,
        'status': status,
        if (createdAt != null) 'created_at': createdAt,
        if (closedAt != null) 'closed_at': closedAt,
        'name': name,
        if (csat != null) 'csat': csat,
        if (csatAt != null) 'csat_at': csatAt,
        'csat_comment': csatComment,
        'seen': seen,
        'messages': messages.map((m) => m.toJson()).toList(),
      };
}

/// Разбор ссылки подписки на `(baseHostUrl, shortUuid)` для веб-витрины и API
/// поддержки `/<shortUuid>/support`.
///
/// Корректно переводит как сырые ссылки `sub.silentgate.lol/sub/<id>`, так и
/// редиректные ссылки `/silentgate/<id>`, `/happ/<id>` и др. на чистый токен
/// `<id>` без диплинк-редиректов `silentgate://`.
class SupportEndpointTarget {
  final String baseHostUrl; // например, 'https://s.silentgate.lol'
  final String shortUuid; // например, 'EXAMPLE_TOKEN_01'

  const SupportEndpointTarget({
    required this.baseHostUrl,
    required this.shortUuid,
  });

  String get pageUrl => '$baseHostUrl/$shortUuid';
  String get supportApiUrl => '$baseHostUrl/$shortUuid/support';
  String get presenceApiUrl => '$baseHostUrl/$shortUuid/support/presence';
  String get closeApiUrl => '$baseHostUrl/$shortUuid/support/close';
  String get rateApiUrl => '$baseHostUrl/$shortUuid/support/rate';

  String fileUrl(String fileId) =>
      '$baseHostUrl/${Uri.encodeComponent(shortUuid)}/support/file/${Uri.encodeComponent(fileId)}';

  static final RegExp _shortUuidRe = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  static const Set<String> _knownRedirectPrefixes = <String>{
    'sub',
    'silentgate',
    'happ',
    'v2raytun',
    'v2rayng',
    'streisand',
    'karing',
    'v2box',
    'foxray',
    'clash',
    'hiddify',
    'singbox',
    'nekobox',
    'incy',
  };

  static SupportEndpointTarget? parse(String? rawSubscriptionUrl) {
    final trimmed = (rawSubscriptionUrl ?? '').trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;

    String? token;
    if (segs.length >= 2 &&
        _knownRedirectPrefixes.contains(segs.first.toLowerCase())) {
      token = segs[1];
    } else {
      token = segs.first;
    }
    if (!_shortUuidRe.hasMatch(token)) return null;

    final rawHost = uri.host.toLowerCase();
    final String pageHost;
    if (rawHost == 'sub.silentgate.lol' ||
        rawHost == 'my.silentgate.lol' ||
        rawHost == 'silentgate.lol') {
      pageHost = 's.silentgate.lol';
    } else {
      pageHost = rawHost;
    }
    final portSuffix =
        uri.hasPort && uri.port != 80 && uri.port != 443 ? ':${uri.port}' : '';
    return SupportEndpointTarget(
      baseHostUrl: '${uri.scheme}://$pageHost$portSuffix',
      shortUuid: token,
    );
  }
}

/// Контроллер встроенного окна поддержки внутри приложения.
///
///  * Работает напрямую с JSON API сайта (`/<short_uuid>/support`);
///  * При клике мимо окна сворачивается (`minimized`) в плавающий значок
///    со счётчиком непрочитанных сообщений от оператора;
///  * Каждое изменение текста/имени/вложений/состояния мгновенно сохраняется
///    в `SharedPreferences` и атомарно сбрасывается на диск в
///    `support_chat_state.json`, поэтому при закрытии окна, перезапуске
///    приложения или отключении питания ничего не пропадает;
///  * Во всех запросах передаёт заголовки `X-SilentGate-App`, `X-SilentGate-OS`,
///    `X-SilentGate-Initiator` и поля `client_app`/`client_version`/`client_os`
///    для отображения плашки «Пишет из приложения» у оператора в desk и для
///    бесшовного перевыпуска ссылки подписки.
class SupportChatController extends ChangeNotifier {
  static const String _diskFileName = 'support_chat_state.json';
  static final Map<String, Map<String, dynamic>> _memoryStore =
      <String, Map<String, dynamic>>{};
  static String _memoryGlobalName = '';

  Future<bool> Function(String oldUrl, String newUrl)?
      onMigrateSubscriptionUrl;

  String? _rawSubscriptionUrl;
  SupportEndpointTarget? _target;

  SupportWindowMode _windowMode = SupportWindowMode.hidden;
  String _draftText = '';
  String _draftName = '';
  List<String> _pendingFilePaths = <String>[];
  int? _replyToId;
  String _replyToText = '';
  int _seenMsgId = 0;
  String _initiatorToken = '';
  List<String> _sentReportFingerprints = <String>[];
  List<SupportTicketItem> _tickets = <SupportTicketItem>[];

  bool _loading = false;
  bool _fetchInFlight = false;
  bool _sending = false;
  String? _errorText;
  int? _banUntilUnix;
  Timer? _pollTimer;
  Timer? _typingTimer;
  bool _disposed = false;

  SupportChatController({this.onMigrateSubscriptionUrl});

  static final SupportChatController instance = SupportChatController();

  SupportWindowMode get windowMode => _windowMode;
  bool get isExpanded => _windowMode == SupportWindowMode.expanded;
  bool get isMinimized => _windowMode == SupportWindowMode.minimized;
  bool get hasSubscriptionSupport => _target != null;
  SupportEndpointTarget? get target => _target;

  String get draftText => _draftText;
  String get draftName => _draftName;
  List<String> get pendingFilePaths => List.unmodifiable(_pendingFilePaths);
  int? get replyToId => _replyToId;
  String get replyToText => _replyToText;
  int get seenMsgId => _seenMsgId;
  String get initiatorToken => _initiatorToken;
  List<String> get sentReportFingerprints =>
      List.unmodifiable(_sentReportFingerprints);
  List<SupportTicketItem> get tickets => List.unmodifiable(_tickets);

  static bool _looksLikeLogOrReportPath(String path) {
    final lower = path.trim().toLowerCase();
    return lower.endsWith('.txt') || lower.endsWith('.log');
  }

  /// Детерминированный отпечаток текстового файла отчёта/лога (или `null`,
  /// если это картинка/видео/архив или файл недоступен).
  static String? fingerprintForLogOrReportFile(String filePath) {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty || !_looksLikeLogOrReportPath(trimmed)) return null;
    try {
      final f = File(trimmed);
      if (!f.existsSync()) return null;
      final len = f.lengthSync();
      if (len <= 0 || len > 10 * 1024 * 1024) return null;
      final raw = utf8.decode(f.readAsBytesSync(), allowMalformed: true);
      if (raw.trim().isEmpty) return null;
      return DevReportService.computeReportContentFingerprint(raw);
    } catch (_) {
      return null;
    }
  }

  /// Совпадает ли содержимое отчёта «1 в 1» с уже отправленным ранее в этот
  /// чат поддержки (или с уже прикреплённым в черновике файлом).
  bool isDuplicateReportContent(String rawReportText, {String? ignorePath}) {
    if (rawReportText.trim().isEmpty) return false;
    final fp = DevReportService.computeReportContentFingerprint(rawReportText);
    if (_sentReportFingerprints.contains(fp)) return true;
    for (final existing in _pendingFilePaths) {
      if (ignorePath != null && existing == ignorePath) continue;
      if (fingerprintForLogOrReportFile(existing) == fp) return true;
    }
    return false;
  }

  /// Совпадает ли файл отчёта/лога «1 в 1» с уже отправленным в чат поддержки
  /// (или с другим уже прикреплённым в черновике файлом).
  bool isDuplicateReportFile(String filePath) {
    final fp = fingerprintForLogOrReportFile(filePath);
    if (fp == null) return false;
    if (_sentReportFingerprints.contains(fp)) return true;
    for (final existing in _pendingFilePaths) {
      if (existing == filePath) continue;
      if (fingerprintForLogOrReportFile(existing) == fp) return true;
    }
    return false;
  }

  void _recordSentReportFingerprint(String fp) {
    if (fp.isEmpty) return;
    _sentReportFingerprints.remove(fp);
    _sentReportFingerprints.add(fp);
    if (_sentReportFingerprints.length > 25) {
      _sentReportFingerprints.removeRange(
          0, _sentReportFingerprints.length - 25);
    }
  }

  bool get loading => _loading;
  bool get sending => _sending;
  String? get errorText => _errorText;
  int? get banUntilUnix => _banUntilUnix;

  /// Активное открытое обращение (если есть).
  SupportTicketItem? get openTicket {
    for (final t in _tickets) {
      if (t.isOpen) return t;
    }
    return null;
  }

  /// Количество непрочитанных ответов от оператора (`dir == 'out'` и `id > seenMsgId`).
  int get unreadCount {
    var count = 0;
    for (final t in _tickets) {
      for (final m in t.messages) {
        if (m.isOperator && m.id > _seenMsgId) {
          count++;
        }
      }
    }
    return count;
  }

  /// Показывать ли плавающий значок поддержки в углу окна:
  /// когда окно свёрнуто, либо есть непрочитанные ответы от оператора, либо
  /// есть несохранённый черновик / открытое обращение.
  bool get shouldShowFloatingBadge =>
      _target != null &&
      _windowMode != SupportWindowMode.expanded &&
      (_windowMode == SupportWindowMode.minimized ||
          unreadCount > 0 ||
          _draftText.trim().isNotEmpty ||
          _pendingFilePaths.isNotEmpty ||
          openTicket != null);

  /// Привязать контроллер к текущей активной ссылке подписки.
  Future<void> bindSubscriptionUrl(String? rawUrl) async {
    final normalized = (rawUrl ?? '').trim();
    if (_rawSubscriptionUrl == normalized) return;
    _rawSubscriptionUrl = normalized;
    _target = SupportEndpointTarget.parse(normalized);
    _errorText = null;
    if (_target == null) {
      _stopPolling();
      _notify();
      return;
    }
    await _loadPersistedState(_target!.shortUuid);
    _restartPolling();
    if (_canDoNetworkInCurrentEnv) {
      unawaited(fetchTickets(silent: true));
    }
  }

  bool get _canDoNetworkInCurrentEnv {
    final tgt = _target;
    if (tgt == null) return false;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) return true;
    return tgt.baseHostUrl.contains('127.0.0.1') ||
        tgt.baseHostUrl.contains('localhost');
  }

  /// Открыть встроенное окно поддержки поверх главного экрана.
  Future<void> open() async {
    if (_target == null) return;
    _windowMode = SupportWindowMode.expanded;
    _errorText = null;
    _persistImmediately();
    _restartPolling();
    _markAllOperatorMessagesSeen();
    _notify();
    if (_canDoNetworkInCurrentEnv) {
      await fetchTickets(silent: false);
    }
  }

  /// Свернуть окно поддержки (например, при клике мимо окна или кнопкой «—»).
  void minimize() {
    if (_windowMode == SupportWindowMode.minimized) return;
    _windowMode = SupportWindowMode.minimized;
    _persistImmediately();
    _restartPolling();
    _notify();
  }

  /// Скрыть окно поддержки кнопкой «×» (все черновики и сообщения при этом
  /// остаются сохранёнными на диске).
  void closeToHidden() {
    _windowMode = (unreadCount > 0 || _draftText.trim().isNotEmpty)
        ? SupportWindowMode.minimized
        : SupportWindowMode.hidden;
    _persistImmediately();
    _restartPolling();
    _notify();
  }

  void updateDraftText(String value) {
    if (_draftText == value) return;
    _draftText = value;
    _persistImmediately();
    _scheduleTypingPresence();
  }

  void updateDraftName(String value) {
    if (_draftName == value) return;
    _draftName = value;
    _persistImmediately();
  }

  void addPendingFiles(Iterable<String> paths) {
    var changed = false;
    for (final p in paths) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;
      if (_pendingFilePaths.length >= 10) {
        _errorText = 'Можно прикрепить не более 10 файлов за раз.';
        changed = true;
        break;
      }
      if (!_pendingFilePaths.contains(trimmed)) {
        _pendingFilePaths.add(trimmed);
        changed = true;
      }
    }
    if (changed) {
      _persistImmediately();
      _notify();
    }
  }

  void removePendingFileAt(int index) {
    if (index < 0 || index >= _pendingFilePaths.length) return;
    _pendingFilePaths.removeAt(index);
    _persistImmediately();
    _notify();
  }

  void setReplyTo(int? msgId, [String previewText = '']) {
    _replyToId = msgId;
    _replyToText = previewText;
    _persistImmediately();
    _notify();
  }

  void clearError() {
    if (_errorText == null) return;
    _errorText = null;
    _notify();
  }

  /// Загрузить свежую историю тикетов с `/<short_uuid>/support`.
  Future<void> fetchTickets({bool silent = true}) async {
    final tgt = _target;
    if (tgt == null) return;
    if (silent && _fetchInFlight) return;
    _fetchInFlight = true;
    if (!silent) {
      _loading = true;
      _notify();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(tgt.supportApiUrl));
      _applyAppHeaders(req);
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final body = await utf8.decodeStream(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          await _applyServerPayload(tgt, decoded);
        }
      } else if (!silent) {
        _errorText = 'Не удалось обновить переписку (HTTP ${resp.statusCode}).';
      }
    } catch (_) {
      if (!silent && _tickets.isEmpty) {
        _errorText =
            'Нет связи с сервером поддержки. Черновик сохранён локально.';
      }
    } finally {
      _fetchInFlight = false;
      client.close(force: true);
      if (!silent) {
        _loading = false;
      }
      _notify();
    }
  }

  /// Отправить сообщение (и вложения, если выбраны) в `/<short_uuid>/support`.
  Future<bool> sendMessage() async {
    final tgt = _target;
    if (tgt == null || _sending) return false;
    final text = _draftText.trim();
    final name = _draftName.trim();
    final validFiles = <File>[];
    for (final p in _pendingFilePaths) {
      final f = File(p);
      if (f.existsSync()) validFiles.add(f);
    }
    if (text.isEmpty && validFiles.isEmpty) {
      _errorText = 'Введите ваш вопрос или прикрепите файл.';
      _notify();
      return false;
    }

    _sending = true;
    _errorText = null;
    _notify();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(tgt.supportApiUrl);
      final req = await client.postUrl(uri);
      _applyAppHeaders(req);

      final activeId = openTicket?.id;
      if (validFiles.isEmpty) {
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        final payload = <String, dynamic>{
          'text': text,
          if (name.isNotEmpty) 'name': name,
          if (activeId != null && activeId > 0) 'ticket_id': activeId,
          if (_replyToId != null && _replyToId! > 0) 'reply_to': _replyToId,
          'client_app': AppInfo.name,
          'client_version': AppInfo.fullVersion,
          'client_os': Platform.operatingSystem,
          'initiator_token': _initiatorToken,
        };
        req.add(utf8.encode(jsonEncode(payload)));
      } else {
        final boundary =
            '----SilentGateBoundary${DateTime.now().microsecondsSinceEpoch}';
        req.headers.set(
          HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary',
        );
        final fields = <String, String>{
          'text': text,
          if (name.isNotEmpty) 'name': name,
          if (activeId != null && activeId > 0) 'ticket_id': '$activeId',
          if (_replyToId != null && _replyToId! > 0) 'reply_to': '$_replyToId',
          'client_app': AppInfo.name,
          'client_version': AppInfo.fullVersion,
          'client_os': Platform.operatingSystem,
          'initiator_token': _initiatorToken,
        };
        for (final entry in fields.entries) {
          req.add(utf8.encode(
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'
            '${entry.value}\r\n',
          ));
        }
        for (final file in validFiles) {
          final fileName =
              file.path.split(RegExp(r'[\\/]')).last.replaceAll('"', '_');
          final bytes = await file.readAsBytes();
          req.add(utf8.encode(
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="files"; filename="$fileName"\r\n'
            'Content-Type: application/octet-stream\r\n\r\n',
          ));
          req.add(bytes);
          req.add(utf8.encode('\r\n'));
        }
        req.add(utf8.encode('--$boundary--\r\n'));
      }

      final resp = await req.close().timeout(const Duration(seconds: 30));
      final body = await utf8.decodeStream(resp);
      Map<String, dynamic>? decoded;
      try {
        final raw = jsonDecode(body);
        if (raw is Map<String, dynamic>) decoded = raw;
      } catch (_) {}

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        for (final f in validFiles) {
          final fp = fingerprintForLogOrReportFile(f.path);
          if (fp != null) {
            _recordSentReportFingerprint(fp);
          }
        }
        _draftText = '';
        _pendingFilePaths.clear();
        _replyToId = null;
        _replyToText = '';
        if (decoded != null) {
          await _applyServerPayload(tgt, decoded);
        }
        _persistImmediately();
        _sending = false;
        _notify();
        return true;
      } else {
        final errCode = decoded?['error']?.toString() ?? '';
        _errorText = _humanizeSupportError(errCode, resp.statusCode);
      }
    } catch (_) {
      _errorText =
          'Не удалось отправить сообщение. Ваш текст сохранён в поле ввода.';
    } finally {
      client.close(force: true);
      _sending = false;
      _notify();
    }
    return false;
  }

  /// Закрыть активное обращение (`/support/close`).
  Future<bool> closeTicket(int ticketId) async {
    final tgt = _target;
    if (tgt == null) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(tgt.closeApiUrl));
      _applyAppHeaders(req);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(jsonEncode({
        'ticket_id': ticketId,
        'client_app': AppInfo.name,
        'client_version': AppInfo.fullVersion,
        'client_os': Platform.operatingSystem,
        if (_initiatorToken.isNotEmpty) 'initiator_token': _initiatorToken,
      })));
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final body = await utf8.decodeStream(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          await _applyServerPayload(tgt, decoded);
        }
        return true;
      }
    } catch (_) {
      _errorText = 'Не удалось закрыть обращение.';
      _notify();
    } finally {
      client.close(force: true);
    }
    return false;
  }

  /// Оценить закрытое обращение (`rating`: `1` = 👍, `0` = 👎).
  Future<bool> rateTicket(int ticketId, int rating,
      {String comment = ''}) async {
    final tgt = _target;
    if (tgt == null) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(tgt.rateApiUrl));
      _applyAppHeaders(req);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(jsonEncode({
        'ticket_id': ticketId,
        'rating': rating,
        if (comment.trim().isNotEmpty) 'comment': comment.trim(),
        'client_app': AppInfo.name,
        'client_version': AppInfo.fullVersion,
        'client_os': Platform.operatingSystem,
        if (_initiatorToken.isNotEmpty) 'initiator_token': _initiatorToken,
      })));
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final body = await utf8.decodeStream(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          await _applyServerPayload(tgt, decoded);
        }
        return true;
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return false;
  }

  void _applyAppHeaders(HttpClientRequest req) {
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(
      HttpHeaders.userAgentHeader,
      '${AppInfo.name}/${AppInfo.version} (${Platform.operatingSystem})',
    );
    req.headers.set('X-SilentGate-App', AppInfo.fullVersion);
    req.headers.set('X-SilentGate-OS', Platform.operatingSystem);
    if (_initiatorToken.isNotEmpty) {
      req.headers.set('X-SilentGate-Initiator', _initiatorToken);
    }
  }

  Future<void> _applyServerPayload(
    SupportEndpointTarget tgt,
    Map<String, dynamic> decoded,
  ) async {
    // Бесшовный перевыпуск ссылки подписки (если инициирован этим клиентом
    // или оператором по тикету этого клиента).
    final migratedUrl =
        (decoded['migrated_sub_url'] ?? decoded['new_sub_url'] ?? '')
            .toString()
            .trim();
    if (migratedUrl.isNotEmpty &&
        _rawSubscriptionUrl != null &&
        migratedUrl != _rawSubscriptionUrl) {
      final oldUrl = _rawSubscriptionUrl!;
      if (onMigrateSubscriptionUrl != null) {
        await onMigrateSubscriptionUrl!(oldUrl, migratedUrl);
      }
      await bindSubscriptionUrl(migratedUrl);
      return;
    }

    final hadOpenTicket = openTicket != null;
    final rawTickets = decoded['tickets'];
    if (rawTickets is List) {
      _tickets = rawTickets
          .whereType<Map>()
          .map((m) => SupportTicketItem.fromJson(m.cast<String, dynamic>()))
          .toList();
    }
    if ((openTicket != null) != hadOpenTicket) {
      _restartPolling();
    }
    final ban = decoded['ban'];
    if (ban is Map && ban['until'] is num) {
      _banUntilUnix = (ban['until'] as num).toInt();
    } else {
      _banUntilUnix = null;
    }
    if (_windowMode == SupportWindowMode.expanded) {
      _markAllOperatorMessagesSeen();
    }
    _persistImmediately();
    _notify();
  }

  void _markAllOperatorMessagesSeen() {
    var best = _seenMsgId;
    int? activeTicketId;
    for (final t in _tickets) {
      if (t.isOpen) activeTicketId = t.id;
      for (final m in t.messages) {
        if (m.isOperator && m.id > best) {
          best = m.id;
        }
      }
    }
    if (_seenMsgId != best) {
      _seenMsgId = best;
      _persistImmediately();
      final tid =
          activeTicketId ?? (_tickets.isNotEmpty ? _tickets.last.id : null);
      if (tid != null && tid > 0 && _canDoNetworkInCurrentEnv) {
        unawaited(_sendPresence(ticketId: tid, typing: false, seen: best));
      }
    }
  }

  void _scheduleTypingPresence() {
    if (!_canDoNetworkInCurrentEnv) return;
    final open = openTicket;
    if (open == null) return;
    if (_typingTimer?.isActive ?? false) return;
    _typingTimer = Timer(const Duration(seconds: 4), () {});
    unawaited(_sendPresence(ticketId: open.id, typing: true, seen: _seenMsgId));
  }

  Future<void> _sendPresence({
    required int ticketId,
    required bool typing,
    required int seen,
  }) async {
    final tgt = _target;
    if (tgt == null || ticketId <= 0) return;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(Uri.parse(tgt.presenceApiUrl));
      _applyAppHeaders(req);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(jsonEncode({
        'ticket_id': ticketId,
        'typing': typing,
        if (seen > 0) 'seen': seen,
        'client_app': AppInfo.name,
        'client_version': AppInfo.fullVersion,
        'client_os': Platform.operatingSystem,
        if (_initiatorToken.isNotEmpty) 'initiator_token': _initiatorToken,
      })));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      await resp.drain<void>();
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }

  String _humanizeSupportError(String code, int status) {
    switch (code) {
      case 'too-long':
        return 'Сообщение слишком длинное (максимум 2000 символов).';
      case 'too-many-files':
        return 'Можно прикрепить не более 10 файлов.';
      case 'too-big':
        return 'Файл слишком большой (максимум 10 МБ на файл).';
      case 'file-kind':
        return 'Такой тип файла не поддерживается (разрешены фото, видео и документы).';
      case 'too-often':
        return 'Слишком частая отправка сообщений. Подождите минуту.';
      case 'empty':
        return 'Введите текст сообщения или прикрепите файл.';
      default:
        return 'Ошибка отправки ($status). Текст сохранён.';
    }
  }

  void _restartPolling() {
    _stopPolling();
    if (_target == null ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    // При открытом окне опрашиваем каждые 3 с для доставки ответов оператора
    // практически в реальном времени; в свёрнутом при активном тикете — раз в 10 с.
    final period = _windowMode == SupportWindowMode.expanded
        ? const Duration(seconds: 3)
        : (openTicket != null
            ? const Duration(seconds: 10)
            : const Duration(seconds: 30));
    _pollTimer = Timer.periodic(period, (_) {
      unawaited(fetchTickets(silent: true));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _loadPersistedState(String shortUuid) async {
    Map<String, dynamic>? loaded;

    // 1) Чтение из атомарного файла на диске (AppPaths.supportDirSync)
    try {
      final dir = AppPaths.supportDirSync();
      final file = File('${dir.path}${Platform.pathSeparator}$_diskFileName');
      if (file.existsSync()) {
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is Map<String, dynamic>) {
          final bySub = raw['subs'];
          if (bySub is Map && bySub[shortUuid] is Map) {
            loaded = (bySub[shortUuid] as Map).cast<String, dynamic>();
          }
          if (_draftName.isEmpty && raw['globalName'] is String) {
            _draftName = raw['globalName'] as String;
          }
        }
      }
    } catch (_) {}

    // 2) Резервное чтение из памяти (для unit-тестов без overrideRoot)
    loaded ??= _memoryStore[shortUuid];
    if (_draftName.isEmpty && _memoryGlobalName.isNotEmpty) {
      _draftName = _memoryGlobalName;
    }

    if (loaded != null) {
      _draftText = '${loaded['draftText'] ?? ''}';
      final savedName = '${loaded['draftName'] ?? ''}';
      if (savedName.isNotEmpty) _draftName = savedName;
      _pendingFilePaths = (loaded['pendingFiles'] is List)
          ? (loaded['pendingFiles'] as List)
              .map((e) => '$e')
              .where((s) => s.isNotEmpty)
              .toList()
          : <String>[];
      _replyToId = loaded['replyToId'] is num
          ? (loaded['replyToId'] as num).toInt()
          : null;
      _replyToText = '${loaded['replyToText'] ?? ''}';
      _seenMsgId = loaded['seenMsgId'] is num
          ? (loaded['seenMsgId'] as num).toInt()
          : 0;
      _initiatorToken = '${loaded['initiatorToken'] ?? ''}';
      _sentReportFingerprints = (loaded['sentReportFingerprints'] is List)
          ? (loaded['sentReportFingerprints'] as List)
              .map((e) => '$e')
              .where((s) => s.isNotEmpty)
              .toList()
          : <String>[];
      final modeStr = '${loaded['windowMode'] ?? 'hidden'}';
      if (modeStr == 'expanded') {
        _windowMode = SupportWindowMode.expanded;
      } else if (modeStr == 'minimized') {
        _windowMode = SupportWindowMode.minimized;
      } else {
        _windowMode = SupportWindowMode.hidden;
      }
      if (loaded['tickets'] is List) {
        _tickets = (loaded['tickets'] as List)
            .whereType<Map>()
            .map((m) => SupportTicketItem.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } else {
      _draftText = '';
      _pendingFilePaths = <String>[];
      _replyToId = null;
      _replyToText = '';
      _seenMsgId = 0;
      _initiatorToken = '';
      _sentReportFingerprints = <String>[];
      _tickets = <SupportTicketItem>[];
      _windowMode = SupportWindowMode.hidden;
    }

    if (_initiatorToken.isEmpty) {
      _initiatorToken = _generateRandomHex(24);
      _persistImmediately();
    }
    _notify();
  }

  void _persistImmediately() {
    final tgt = _target;
    if (tgt == null) return;
    final subKey = tgt.shortUuid;
    final data = <String, dynamic>{
      'draftText': _draftText,
      'draftName': _draftName,
      'pendingFiles': List<String>.from(_pendingFilePaths),
      if (_replyToId != null) 'replyToId': _replyToId,
      if (_replyToText.isNotEmpty) 'replyToText': _replyToText,
      'seenMsgId': _seenMsgId,
      'initiatorToken': _initiatorToken,
      if (_sentReportFingerprints.isNotEmpty)
        'sentReportFingerprints': List<String>.from(_sentReportFingerprints),
      'windowMode': _windowMode.name,
      'tickets': _tickets.map((t) => t.toJson()).toList(),
    };

    _memoryStore[subKey] = data;
    if (_draftName.trim().isNotEmpty) {
      _memoryGlobalName = _draftName.trim();
    }

    // Синхронная атомарная запись в файл на диске с flush: true
    // (переживает внезапное закрытие окна, перезапуск и отключение питания).
    try {
      final dir = AppPaths.supportDirSync();
      final file = File('${dir.path}${Platform.pathSeparator}$_diskFileName');
      Map<String, dynamic> root = <String, dynamic>{};
      if (file.existsSync()) {
        try {
          final existing = jsonDecode(file.readAsStringSync());
          if (existing is Map<String, dynamic>) root = existing;
        } catch (_) {}
      }
      final subs = (root['subs'] is Map)
          ? Map<String, dynamic>.from(root['subs'] as Map)
          : <String, dynamic>{};
      subs[subKey] = data;
      root['subs'] = subs;
      if (_draftName.trim().isNotEmpty) {
        root['globalName'] = _draftName.trim();
      }
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(root), flush: true);
      tmp.renameSync(file.path);
    } catch (_) {}
  }

  @visibleForTesting
  static void clearMemoryStoreForTests() {
    _memoryStore.clear();
    _memoryGlobalName = '';
  }

  @visibleForTesting
  void injectTicketsForTest(List<SupportTicketItem> tickets) {
    _tickets = List<SupportTicketItem>.from(tickets);
    if (_windowMode == SupportWindowMode.expanded) {
      _markAllOperatorMessagesSeen();
    }
    _persistImmediately();
    _notify();
  }

  @visibleForTesting
  void resetForTest() {
    _stopPolling();
    _typingTimer?.cancel();
    _rawSubscriptionUrl = null;
    _target = null;
    _windowMode = SupportWindowMode.hidden;
    _draftText = '';
    _draftName = '';
    _pendingFilePaths = <String>[];
    _replyToId = null;
    _replyToText = '';
    _seenMsgId = 0;
    _initiatorToken = '';
    _sentReportFingerprints = <String>[];
    _fetchInFlight = false;
    _tickets = <SupportTicketItem>[];
    _loading = false;
    _sending = false;
    _errorText = null;
    _banUntilUnix = null;
    _notify();
  }

  static String _generateRandomHex(int byteCount) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _typingTimer?.cancel();
    super.dispose();
  }
}
