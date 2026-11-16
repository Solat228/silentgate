import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/app_launcher.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/support_chat_controller.dart';
import 'support_report_dialog.dart';

/// Внутреннее всплывающее окно поддержки поверх главного экрана приложения
/// и плавающий значок со счётчиком непрочитанных ответов оператора в свёрнутом
/// состоянии.
///
///  * Клик мимо окна сворачивает его (`minimize()`), а не уничтожает;
///  * Все введённые поля («Ваше имя», «Ваш вопрос», вложения) сохраняются на
///    диск мгновенно при каждом нажатии клавиши;
///  * Когда оператор отвечает в тикет, на свёрнутом значке (и на кнопке
///    «Поддержка» в карточке подписки) загорается бейдж с количеством новых
///    сообщений.
class SupportChatOverlay extends StatefulWidget {
  final SupportChatController? controller;

  const SupportChatOverlay({super.key, this.controller});

  @override
  State<SupportChatOverlay> createState() => _SupportChatOverlayState();
}

class _SupportChatOverlayState extends State<SupportChatOverlay> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _questionCtrl;
  final ScrollController _scrollCtrl = ScrollController();
  String? _lastBoundUrl;

  SupportChatController get _ctrl =>
      widget.controller ?? SupportChatController.instance;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _ctrl.draftName);
    _questionCtrl = TextEditingController(text: _ctrl.draftText);
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SupportChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCtrl = oldWidget.controller ?? SupportChatController.instance;
    if (oldCtrl != _ctrl) {
      oldCtrl.removeListener(_onControllerChanged);
      _ctrl.addListener(_onControllerChanged);
      _syncTextControllersFromState();
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _nameCtrl.dispose();
    _questionCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncTextControllersFromState();
    setState(() {});
  }

  void _syncTextControllersFromState() {
    if (_nameCtrl.text != _ctrl.draftName) {
      _nameCtrl.value = TextEditingValue(
        text: _ctrl.draftName,
        selection: TextSelection.collapsed(offset: _ctrl.draftName.length),
      );
    }
    if (_questionCtrl.text != _ctrl.draftText) {
      _questionCtrl.value = TextEditingValue(
        text: _ctrl.draftText,
        selection: TextSelection.collapsed(offset: _ctrl.draftText.length),
      );
    }
  }

  Future<void> _pickAttachments() async {
    try {
      const group = XTypeGroup(
        label: 'Файлы и скриншоты',
        extensions: <String>[
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'mp4',
          'webm',
          'mov',
          'pdf',
          'txt',
          'log',
          'json',
          'zip',
        ],
      );
      final files = await openFiles(acceptedTypeGroups: const <XTypeGroup>[group]);
      if (files.isEmpty) return;
      _ctrl.addPendingFiles(files.map((f) => f.path));
    } catch (_) {}
  }

  Future<void> _attachDiagnosticReport() async {
    final res = await showSupportReportForChatDialog(context);
    if (res == null || !mounted) return;
    _ctrl.addPendingFiles(<String>[res.filePath]);
    if (_ctrl.draftText.trim().isEmpty && res.summaryLine.trim().isNotEmpty) {
      _ctrl.updateDraftText(res.summaryLine);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState?>();
    if (appState != null) {
      _ctrl.onMigrateSubscriptionUrl = appState.migrateSubscriptionUrl;
      final subUrl = appState.subscriptionUrl;
      if (subUrl != _lastBoundUrl) {
        _lastBoundUrl = subUrl;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_ctrl.bindSubscriptionUrl(subUrl));
          }
        });
      }
    }

    if (_ctrl.isExpanded) {
      return _buildExpandedModal(context);
    }
    if (_ctrl.shouldShowFloatingBadge) {
      return _buildFloatingMinimizedBadge(context);
    }
    return const SizedBox.shrink();
  }

  Widget _buildFloatingMinimizedBadge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = _ctrl.unreadCount;
    final hasDraft = _ctrl.draftText.trim().isNotEmpty ||
        _ctrl.pendingFilePaths.isNotEmpty;

    return Positioned(
      right: 18,
      bottom: 18,
      child: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          key: const Key('supportFloatingBadgeButton'),
          borderRadius: BorderRadius.circular(28),
          onTap: () => unawaited(_ctrl.open()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: unread > 0
                  ? scheme.primary
                  : scheme.secondaryContainer.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: unread > 0
                    ? scheme.primaryContainer
                    : scheme.primary.withValues(alpha: 0.45),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.support_agent,
                  size: 20,
                  color: unread > 0
                      ? scheme.onPrimary
                      : scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Поддержка',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: unread > 0
                            ? scheme.onPrimary
                            : scheme.onSecondaryContainer,
                      ),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    key: const Key('supportUnreadBadgeText'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        color: scheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ] else if (hasDraft) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedModal(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final openTicket = _ctrl.openTicket;
    final tickets = _ctrl.tickets;

    return Positioned.fill(
      child: Stack(
        children: [
          // Полупрозрачная подложка: клик мимо окна СВОРАЧИВАЕТ его, а не закрывает.
          GestureDetector(
            key: const Key('inAppSupportBackdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: _ctrl.minimize,
            child: Container(
              color: Colors.black.withValues(alpha: 0.52),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 500,
                  maxHeight: 620,
                ),
                child: GestureDetector(
                  // Перехватываем тап внутри карточки, чтобы он не уходил в подложку.
                  onTap: () {},
                  child: Material(
                    key: const Key('inAppSupportModalCard'),
                    elevation: 16,
                    color: const Color(0xFF101522),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: scheme.primary.withValues(alpha: 0.32),
                        width: 1.2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight.isFinite
                                  ? box.maxHeight
                                  : 620,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeader(context, openTicket),
                                const Divider(
                                    height: 1, color: Color(0xFF232C42)),
                                Flexible(
                                  child: _buildThreadArea(context, tickets),
                                ),
                                if (_ctrl.errorText != null)
                                  _buildErrorBanner(context, _ctrl.errorText!),
                                if (_ctrl.replyToId != null)
                                  _buildReplyBanner(context),
                                if (_ctrl.pendingFilePaths.isNotEmpty)
                                  _buildPendingFilesBar(context),
                                const Divider(
                                    height: 1, color: Color(0xFF232C42)),
                                _buildComposer(context, openTicket),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SupportTicketItem? openTicket) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      color: const Color(0xFF151C2E),
      child: Row(
        children: [
          Icon(Icons.support_agent, size: 19, color: scheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Поддержка',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
            ),
          ),
          if (openTicket != null && openTicket.no.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#W${openTicket.no}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (openTicket != null)
            TextButton(
              key: const Key('supportCloseTicketButton'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: Colors.white70,
              ),
              onPressed: () => unawaited(_ctrl.closeTicket(openTicket.id)),
              child: const Text(
                'Вопрос решён',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          IconButton(
            key: const Key('supportRefreshButton'),
            tooltip: 'Обновить',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(6),
            icon: _ctrl.loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 17, color: Colors.white70),
            onPressed: _ctrl.loading
                ? null
                : () => unawaited(_ctrl.fetchTickets(silent: false)),
          ),
          IconButton(
            key: const Key('supportMinimizeButton'),
            tooltip: 'Свернуть окно поддержки',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(6),
            icon: const Icon(Icons.minimize, size: 17, color: Colors.white70),
            onPressed: _ctrl.minimize,
          ),
          IconButton(
            key: const Key('supportCloseModalButton'),
            tooltip: 'Закрыть',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(6),
            icon: const Icon(Icons.close, size: 17, color: Colors.white70),
            onPressed: _ctrl.closeToHidden,
          ),
        ],
      ),
    );
  }

  Widget _buildThreadArea(
      BuildContext context, List<SupportTicketItem> tickets) {
    if (_ctrl.loading && tickets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (tickets.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D2842),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '📱 Связь из приложения SilentGate',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF93B4FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Опишите вопрос или проблему — оператор ответит прямо здесь.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Если вы свернёте окно или перезапустите приложение, набранный текст '
              'не пропадёт, а при новом ответе оператора на значке поддержки '
              'загорится уведомление.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      itemCount: tickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, idx) {
        final t = tickets[idx];
        return _buildTicketCard(context, t);
      },
    );
  }

  Widget _buildTicketCard(BuildContext context, SupportTicketItem ticket) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF151C2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ticket.isOpen
              ? scheme.primary.withValues(alpha: 0.35)
              : const Color(0xFF252F45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                ticket.no.isNotEmpty ? 'Обращение #W${ticket.no}' : 'Обращение',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: ticket.isOpen
                      ? const Color(0xFF173B2E)
                      : const Color(0xFF282F40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ticket.isOpen ? 'Открыто' : 'Закрыто',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ticket.isOpen
                        ? const Color(0xFF5CE1A6)
                        : Colors.white54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in ticket.messages) _buildMessageBubble(context, m),
          if (!ticket.isOpen) _buildCsatBar(context, ticket),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, SupportMessageItem msg) {
    final isOp = msg.isOperator;
    final target = _ctrl.target;
    return Align(
      alignment: isOp ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: isOp ? const Color(0xFF212B42) : const Color(0xFF2554C7),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isOp ? 3 : 12),
            bottomRight: Radius.circular(isOp ? 12 : 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOp ? 'Оператор поддержки' : 'Вы',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isOp ? const Color(0xFF8AB4F8) : Colors.white70,
                  ),
                ),
                if (isOp && msg.id > 0) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _ctrl.setReplyTo(msg.id, msg.text),
                    child: const Text(
                      'Ответить',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8AB4F8),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (msg.replyText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF8AB4F8), width: 2.5),
                  ),
                ),
                child: Text(
                  msg.replyText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ],
            if (msg.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                msg.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            if (msg.files.isNotEmpty && target != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in msg.files)
                    InkWell(
                      onTap: () => unawaited(UrlOpener.open(target.fileUrl(f.id))),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.attachment,
                                size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                f.name.isEmpty ? 'Вложение' : f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCsatBar(BuildContext context, SupportTicketItem ticket) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Text(
            'Оцените ответ:',
            style: TextStyle(fontSize: 11.5, color: Colors.white60),
          ),
          const SizedBox(width: 8),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.thumb_up_alt_outlined,
              size: 16,
              color: ticket.csat == 1
                  ? const Color(0xFF5CE1A6)
                  : Colors.white54,
            ),
            onPressed: () => unawaited(_ctrl.rateTicket(ticket.id, 1)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.thumb_down_alt_outlined,
              size: 16,
              color: ticket.csat == 0
                  ? const Color(0xFFFF6B6B)
                  : Colors.white54,
            ),
            onPressed: () => unawaited(_ctrl.rateTicket(ticket.id, 0)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF421C24),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFFF8A8A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(fontSize: 12, color: Color(0xFFFFB3B3)),
            ),
          ),
          InkWell(
            onTap: _ctrl.clearError,
            child: const Icon(Icons.close, size: 16, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: const Color(0xFF1A233A),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 15, color: Color(0xFF8AB4F8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _ctrl.replyToText.isEmpty
                  ? 'Ответ на сообщение #${_ctrl.replyToId}'
                  : _ctrl.replyToText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          InkWell(
            onTap: () => _ctrl.setReplyTo(null),
            child: const Icon(Icons.close, size: 15, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingFilesBar(BuildContext context) {
    final files = _ctrl.pendingFilePaths;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: const Color(0xFF151C2E),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < files.length; i++)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(
                files[i].split(RegExp(r'[\\/]')).last,
                style: const TextStyle(fontSize: 11.5),
              ),
              onDeleted: () => _ctrl.removePendingFileAt(i),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, SupportTicketItem? openTicket) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (openTicket == null) ...[
            TextField(
              key: const Key('supportNameInput'),
              controller: _nameCtrl,
              onChanged: _ctrl.updateDraftName,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Ваше имя (необязательно)',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF161D2F),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF28324B)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF28324B)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const Key('supportQuestionInput'),
            controller: _questionCtrl,
            onChanged: _ctrl.updateDraftText,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: openTicket == null
                  ? 'Ваш вопрос'
                  : 'Написать сообщение в обращение #W${openTicket.no}…',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF161D2F),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF28324B)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF28324B)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton(
                    key: const Key('supportSendButton'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2962FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _ctrl.sending
                        ? null
                        : () => unawaited(_ctrl.sendMessage()),
                    child: _ctrl.sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Отправить',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: Tooltip(
                  message: Localizations.of<AppLocalizations>(
                        context,
                        AppLocalizations,
                      )?.supportAttachDiagButton ??
                      'Отчёт диагностики',
                  child: OutlinedButton.icon(
                    key: const Key('supportAttachDiagReportButton'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      side: const BorderSide(color: Color(0xFF28324B)),
                      backgroundColor: const Color(0xFF161D2F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _ctrl.sending ? null : _attachDiagnosticReport,
                    icon: const Icon(
                      Icons.assignment_outlined,
                      size: 17,
                      color: Color(0xFF8AB4F8),
                    ),
                    label: const Text(
                      'Отчёт',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 40,
                height: 40,
                child: OutlinedButton(
                  key: const Key('supportAttachButton'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: Color(0xFF28324B)),
                    backgroundColor: const Color(0xFF161D2F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _ctrl.sending ? null : _pickAttachments,
                  child: const Icon(
                    Icons.attach_file,
                    size: 18,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
