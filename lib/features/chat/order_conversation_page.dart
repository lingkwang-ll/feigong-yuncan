// ignore_for_file: unnecessary_underscores

// 订单沟通页（员工端 & 商家端共用）
//
// 设计原则：
// - 顶部显示订单上下文：商家名 / 顾客信息 / 订单号 / 订单状态
// - 自己 = 右侧绿色气泡，对方 = 左侧白色气泡，系统消息 = 居中灰色
// - 支持文字、emoji、图片消息；图片消息可点击预览
// - 进入页面时自动获取/创建会话并 markRead；
//   每 5 秒轮询一次消息列表，页面销毁时停止轮询
// - 文件选择基于 image_pick_upload（与付款截图、菜品图共用工具）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/conversation_api.dart';
import '../../models/conversation_message_model.dart';
import '../../models/conversation_model.dart';
import '../../models/order_model.dart';
import '../../models/user_model.dart';
import '../../state/app_state.dart';
import '../../state/employee_conversation_state.dart';
import '../../state/employee_notification_service.dart';
import '../../state/merchant_conversation_state.dart';
import '../../state/merchant_notification_service.dart';
import '../../state/merchant_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_display_util.dart';
import '../../utils/image_pick_upload.dart';

class OrderConversationPage extends StatefulWidget {
  /// 上下文订单（用于顶部展示和会话获取）
  final Order order;

  /// 是否以商家身份打开（true=商家端，false=员工端）
  final bool asMerchant;

  /// 可选：从外层注入 ApiClient（避免 rootNavigator push 时 Provider 未就绪）
  final ApiClient? apiClient;

  const OrderConversationPage({
    super.key,
    required this.order,
    required this.asMerchant,
    this.apiClient,
  });

  static Future<void> open(
    BuildContext context, {
    required Order order,
    required bool asMerchant,
  }) {
    ApiClient? client;
    try {
      client = context.read<ApiClient>();
    } catch (_) {
      client = null;
    }
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => OrderConversationPage(
          order: order,
          asMerchant: asMerchant,
          apiClient: client,
        ),
      ),
    );
  }

  @override
  State<OrderConversationPage> createState() => _OrderConversationPageState();
}

class _OrderConversationPageState extends State<OrderConversationPage> {
  static const Duration _pollInterval = Duration(seconds: 5);

  ConversationApi? _api;
  bool _bootstrapping = false;

  Conversation? _conversation;
  List<ConversationMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _pollTimer;

  // 简单常用 emoji 面板（不引入额外依赖）
  static const List<String> _emojiList = [
    '😀', '😁', '😂', '🤣', '😊', '🙂', '😉', '😍',
    '😘', '🤔', '😎', '😅', '😢', '😭', '😡', '🥺',
    '👍', '👎', '👌', '🙏', '💪', '👏', '🤝', '✌️',
    '❤️', '💔', '🔥', '✨', '🎉', '🎁', '☕', '🍚',
    '🍜', '🍱', '🍔', '🍟', '🍕', '🍣', '🍰', '🥤',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.asMerchant) {
      MerchantNotificationService.instance
          .setActiveChatOrder(widget.order.id);
    } else {
      EmployeeNotificationService.instance
          .setActiveChatOrder(widget.order.id);
    }
    if (widget.apiClient != null) {
      _api = ConversationApi(widget.apiClient!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  ConversationApi _conversationApi(BuildContext context) {
    return _api ??=
        ConversationApi(widget.apiClient ?? context.read<ApiClient>());
  }

  bool get _canSend =>
      _conversation != null && !_loading && _error == null && !_bootstrapping;

  @override
  void dispose() {
    if (widget.asMerchant) {
      MerchantNotificationService.instance.setActiveChatOrder(null);
    } else {
      EmployeeNotificationService.instance.setActiveChatOrder(null);
    }
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    final orderId = widget.order.id;
    debugPrint('[chat-load-start] orderId=$orderId');
    if (orderId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '订单信息异常，请返回重试';
        _bootstrapping = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _conversationApi(context);
      final conv = await _resolveConversation(api);
      debugPrint('[chat-load-success] conversationId=${conv.id}');
      if (widget.asMerchant) {
        debugPrint(
          '[merchant-chat-context] conversationId=${conv.id} '
          'orderId=${conv.orderId} merchantId=${conv.merchantId} '
          'employeeId=${conv.employeeId ?? 'null'}',
        );
      }
      if (!mounted) return;
      setState(() => _conversation = conv);
      await _refresh(api, initial: true);
      await _safeMarkRead(api);
      _startPolling(api);
      debugPrint(
        '[chat-load-success] messages=${_messages.length} loading=$_loading',
      );
    } catch (e, st) {
      _logError('bootstrap', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '消息加载失败，请重试';
      });
    } finally {
      _bootstrapping = false;
    }
  }

  Future<Conversation> _resolveConversation(ConversationApi api) async {
    if (!widget.asMerchant) {
      return api.getOrCreateForOrder(widget.order.id);
    }
    return api.getOrCreateForOrderAsMerchant(widget.order.id);
  }

  void _logError(String action, Object e, [StackTrace? st]) {
    if (e is ApiException) {
      debugPrint(
        '[chat-load-error] action=$action statusCode=${e.code} '
        'errorCode=${e.errorCode} message=${e.message}',
      );
    } else {
      debugPrint('[chat-load-error] action=$action error=$e');
    }
    if (st != null) debugPrint('$st');
  }

  void _startPolling(ConversationApi api) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      _refresh(api).catchError((_) {});
    });
  }

  Future<void> _refresh(ConversationApi api, {bool initial = false}) async {
    final conv = _conversation;
    if (conv == null) return;
    try {
      final before = _messages.length;
      final list = await api.listMessages(
        conv.id,
        asMerchant: widget.asMerchant,
      );
      debugPrint('[chat-load-success] messages count=${list.length}');
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
      });
      if (initial || list.length != before) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
      if (!initial && list.length != before) {
        _safeMarkRead(api);
      }
    } catch (e, st) {
      _logError('refresh', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_messages.isEmpty) {
          _error = '消息加载失败，请重试';
        }
      });
    }
  }

  Future<void> _safeMarkRead(ConversationApi api) async {
    final conv = _conversation;
    if (conv == null) return;
    try {
      final updated =
          await api.markRead(conv.id, asMerchant: widget.asMerchant);
      if (!mounted) return;
      setState(() => _conversation = updated);
      if (widget.asMerchant) {
        try {
          context
              .read<MerchantConversationState>()
              .applyLocalRead(widget.order.id);
        } catch (_) {}
      } else {
        try {
          context
              .read<EmployeeConversationState>()
              .applyLocalRead(widget.order.id);
        } catch (_) {}
      }
    } catch (_) {
      // 已读失败不影响主流程
    }
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending || !_canSend) return;
    final conv = _conversation;
    if (conv == null) return;
    final api = _conversationApi(context);
    setState(() => _sending = true);
    try {
      final msg = await api.sendText(
        conv.id,
        content: text,
        asMerchant: widget.asMerchant,
      );
      _inputCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, msg];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendEmoji(String emoji) async {
    final conv = _conversation;
    if (conv == null || _sending || !_canSend) return;
    final api = _conversationApi(context);
    setState(() => _sending = true);
    try {
      final msg = await api.sendEmoji(
        conv.id,
        emoji: emoji,
        asMerchant: widget.asMerchant,
      );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final conv = _conversation;
    if (conv == null || _sending || !_canSend) return;
    final api = _conversationApi(context);
    final bytes = await pickImageBytes(context);
    if (bytes == null) return;
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      final msg = await api.uploadAndSendImage(
        conv.id,
        bytes: bytes,
        filename: 'chat_${DateTime.now().millisecondsSinceEpoch}.png',
        asMerchant: widget.asMerchant,
      );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_formatError(e))),
    );
  }

  String _formatError(Object e) {
    if (e is ApiException) {
      return e.message;
    }
    return e.toString();
  }

  void _showEmojiPanel() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 8,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
            children: _emojiList
                .map(
                  (e) => InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _sendEmoji(e);
                    },
                    child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  String _merchantNameFromState(BuildContext context) {
    try {
      final merchantState = context.read<MerchantState>();
      for (final m in merchantState.nearbyMerchants) {
        if (m.id == widget.order.merchantId && m.name.isNotEmpty) {
          return m.name;
        }
      }
      if (merchantState.currentMerchant.id == widget.order.merchantId) {
        return merchantState.currentMerchant.name;
      }
    } catch (_) {
      // MerchantState 不可用时回退订单字段
    }
    return '';
  }

  String _counterpartyTitle(BuildContext context) {
    if (widget.asMerchant) {
      final raw = _conversation?.employeeName ??
          widget.order.customerName;
      final company = widget.order.customerCompany.trim();
      final phone = widget.order.phone.trim();
      final fallback = company.isNotEmpty
          ? company
          : (phone.isNotEmpty ? phone : '顾客');
      return resolveChatDisplayName(raw, fallback: fallback);
    }
    final fromState = _merchantNameFromState(context);
    final raw = _conversation?.merchantName ??
        (fromState.isNotEmpty ? fromState : widget.order.merchantName);
    return resolveChatDisplayName(raw, fallback: '商家');
  }

  String _contextSubtitle(BuildContext context) {
    if (widget.asMerchant) {
      final company = widget.order.customerCompany.trim();
      if (company.isNotEmpty) return company;
      final phone = widget.order.phone.trim();
      if (phone.isNotEmpty) return phone;
      return resolveChatDisplayName(
        _conversation?.employeeName ?? widget.order.customerName,
        fallback: '顾客',
      );
    }
    final fromState = _merchantNameFromState(context);
    final raw = _conversation?.merchantName ??
        (fromState.isNotEmpty ? fromState : widget.order.merchantName);
    return resolveChatDisplayName(raw, fallback: '商家');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[chat-page-build] loading=$_loading error=$_error '
      'conversationId=${_conversation?.id} messages=${_messages.length}',
    );
    final appState = context.watch<AppState>();
    final title = _counterpartyTitle(context);
    final subtitle = _contextSubtitle(context);
    final banner = _orderStatusBanner();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ContextStrip(order: widget.order, subtitle: subtitle),
            if (banner != null) banner,
            Expanded(child: _buildMessageContent(appState)),
            const Divider(height: 1, thickness: 1),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  /// 消息区：单层 Expanded 子节点，不再嵌套 Expanded / Column。
  Widget _buildMessageContent(AppState appState) {
    const panelColor = Colors.white;

    if (_loading) {
      return const ColoredBox(
        color: panelColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 12),
              Text('加载消息中…', style: TextStyle(color: AppColors.textTertiary)),
            ],
          ),
        ),
      );
    }

    if (_error != null && _messages.isEmpty) {
      return ColoredBox(
        color: panelColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 40, color: AppColors.textTertiary),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _bootstrapping
                      ? null
                      : () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _bootstrap();
                        },
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final emptyHint = widget.asMerchant
        ? '暂无消息，可以开始和顾客沟通'
        : '暂无消息，可以开始和商家沟通';

    if (_messages.isEmpty) {
      return ColoredBox(
        color: panelColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              emptyHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    final mineRole =
        widget.asMerchant ? ChatSenderType.merchant : ChatSenderType.employee;
    return ColoredBox(
      color: panelColor,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: _messages.length,
        itemBuilder: (_, i) {
          final msg = _messages[i];
          final showTime = _shouldShowTime(i);
          return _MessageBubble(
            message: msg,
            isMine: msg.senderType == mineRole,
            showTime: showTime,
            currentUser: appState.currentUser,
          );
        },
      ),
    );
  }

  Widget? _orderStatusBanner() {
    if (widget.order.status == OrderStatus.completed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.asMerchant
                ? '订单已完成，仍可联系顾客处理售后'
                : '订单已完成，仍可联系商家处理售后',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }
    if (widget.order.status == OrderStatus.cancelled) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '订单已取消，仍可查看历史消息',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return null;
  }

  bool _shouldShowTime(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1];
    final cur = _messages[index];
    return cur.createdAt.difference(prev.createdAt).inMinutes >= 5;
  }

  Widget _buildInputBar() {
    final hint = !_canSend && _loading
        ? '消息加载中…'
        : (!_canSend && _error != null
            ? '消息未加载，请先重新加载'
            : null);
    return Material(
      color: const Color(0xFFF6F7F9),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '表情',
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    onPressed: _canSend && !_sending ? _showEmojiPanel : null,
                  ),
                  IconButton(
                    tooltip: '图片',
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _canSend && !_sending ? _pickAndSendImage : null,
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: TextField(
                        controller: _inputCtrl,
                        minLines: 1,
                        maxLines: 4,
                        enabled: _canSend && !_sending,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: const InputDecoration(
                          hintText: '输入消息…',
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Theme(
                    data: Theme.of(context).copyWith(
                      elevatedButtonTheme: ElevatedButtonThemeData(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(56, 38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: _canSend && !_sending ? _sendText : null,
                      child: _sending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('发送'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部薄条：订单号 + 状态 + 简要信息
class _ContextStrip extends StatelessWidget {
  final Order order;
  final String subtitle;
  const _ContextStrip({required this.order, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final orderNo = order.displayOrderNo.isNotEmpty
        ? '订单 ${order.displayOrderNo}'
        : '订单';
    return Container(
      width: double.infinity,
      color: AppColors.primaryLight,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$orderNo · $subtitle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Text(
              order.status.label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 消息气泡
class _MessageBubble extends StatelessWidget {
  final ConversationMessage message;
  final bool isMine;
  final bool showTime;
  final User? currentUser;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showTime,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _systemRow();
    }
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMine ? AppColors.primary : Colors.white;
    final fg = isMine ? Colors.white : AppColors.textPrimary;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTime) _timeText(message.createdAt),
          Align(
            alignment: align,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: _bubbleContent(context, bg, fg, radius),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubbleContent(
    BuildContext context,
    Color bg,
    Color fg,
    BorderRadius radius,
  ) {
    if (message.isImage) {
      return _ImageMessage(
        url: resolveAssetUrl(message.imageUrl) ?? '',
        radius: radius,
      );
    }
    final isEmojiOnly =
        message.messageType == ChatMessageType.emoji && (message.content ?? '').isNotEmpty;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isEmojiOnly ? 10 : 12,
        vertical: isEmojiOnly ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: isMine ? null : Border.all(color: AppColors.divider),
      ),
      child: Text(
        message.content ?? '',
        style: TextStyle(
          color: fg,
          fontSize: isEmojiOnly ? 26 : 14,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _systemRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            message.content ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeText(DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    final fmt = sameDay
        ? DateFormat('HH:mm').format(t)
        : DateFormat('MM-dd HH:mm').format(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Text(
          fmt,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _ImageMessage extends StatelessWidget {
  final String url;
  final BorderRadius radius;
  const _ImageMessage({required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 160,
      height: 160,
      color: const Color(0xFFF1F3F5),
      child: const Icon(Icons.image_not_supported_outlined,
          color: AppColors.textTertiary),
    );
    return GestureDetector(
      onTap: url.isEmpty ? null : () => _preview(context),
      child: ClipRRect(
        borderRadius: radius,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
                width: 180,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 180,
                    height: 180,
                    color: const Color(0xFFF1F3F5),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
