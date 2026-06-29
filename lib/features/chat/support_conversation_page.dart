import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/support_api.dart';
import '../../models/support_conversation_model.dart';
import '../../state/support_conversation_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_pick_upload.dart';

/// 平台客服聊天页（员工 / 商家共用）
class SupportConversationPage extends StatefulWidget {
  final ApiClient? apiClient;

  const SupportConversationPage({super.key, this.apiClient});

  static Future<void> open(BuildContext context) {
    ApiClient? client;
    try {
      client = context.read<ApiClient>();
    } catch (_) {}
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => SupportConversationPage(apiClient: client),
      ),
    );
  }

  @override
  State<SupportConversationPage> createState() =>
      _SupportConversationPageState();
}

class _SupportConversationPageState extends State<SupportConversationPage> {
  static const Duration _pollInterval = Duration(seconds: 5);

  SupportApi? _api;
  SupportConversation? _conversation;
  List<SupportMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  static const List<String> _emojiList = [
    '😀', '😁', '😂', '🤣', '😊', '🙂', '😉', '😍',
    '😘', '🤔', '😎', '😅', '😢', '😭', '😡', '🥺',
    '👍', '👎', '👌', '🙏', '💪', '👏', '🤝', '✌️',
    '❤️', '💔', '🔥', '✨', '🎉', '🎁', '☕', '🍚',
  ];

  bool get _canSend => _conversation != null && _error == null;

  @override
  void initState() {
    super.initState();
    if (widget.apiClient != null) {
      _api = SupportApi(widget.apiClient!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_api == null) {
      try {
        _api = SupportApi(context.read<ApiClient>());
      } catch (_) {
        setState(() {
          _loading = false;
          _error = '无法连接客服服务';
        });
        return;
      }
    }
    try {
      final conv = await _api!.getOrCreateConversation();
      final msgs = await _api!.listMessages();
      await _api!.markRead();
      if (!mounted) return;
      context.read<SupportConversationState>().clearUnread();
      setState(() {
        _conversation = conv;
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      _startPolling();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请稍后重试';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollMessages());
  }

  Future<void> _pollMessages() async {
    if (_api == null || !mounted) return;
    try {
      final msgs = await _api!.listMessages();
      if (!mounted) return;
      setState(() => _messages = msgs);
      await _api!.markRead();
      context.read<SupportConversationState>().clearUnread();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _api == null || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await _api!.sendText(text);
      _inputCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, msg];
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息发送失败，请重试')),
      );
    }
  }

  Future<void> _sendEmoji(String emoji) async {
    if (_api == null || _sending) return;
    Navigator.of(context).pop();
    setState(() => _sending = true);
    try {
      final msg = await _api!.sendEmoji(emoji);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, msg];
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息发送失败，请重试')),
      );
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_api == null || _sending) return;
    final bytes = await pickImageBytes(context);
    if (bytes == null) return;
    setState(() => _sending = true);
    try {
      final msg = await _api!.uploadAndSendImage(bytes, 'support.jpg');
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, msg];
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息发送失败，请重试')),
      );
    }
  }

  void _showEmojiPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _emojiList.length,
            itemBuilder: (_, i) => InkWell(
              onTap: () => _sendEmoji(_emojiList[i]),
              child: Center(
                child: Text(_emojiList[i], style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('联系平台客服'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.primaryLight,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '平台客服',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '请描述你的问题，平台管理员会尽快处理',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildMessages()),
            const Divider(height: 1),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _bootstrap, child: const Text('重新加载')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '暂无消息，可以开始咨询',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        final showTime = i == 0 ||
            _messages[i].createdAt
                    .difference(_messages[i - 1].createdAt)
                    .inMinutes >=
                5;
        return _SupportMessageBubble(
          message: msg,
          showTime: showTime,
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Material(
      color: const Color(0xFFF6F7F9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: _canSend && !_sending ? _showEmojiPanel : null,
            ),
            IconButton(
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
            ElevatedButton(
              onPressed: _canSend && !_sending ? _sendText : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
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
          ],
        ),
      ),
    );
  }
}

class _SupportMessageBubble extends StatelessWidget {
  final SupportMessage message;
  final bool showTime;

  const _SupportMessageBubble({
    required this.message,
    required this.showTime,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.content ?? '',
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ),
      );
    }
    final isMine = message.senderType == SupportSenderType.user;
    final bg = isMine ? AppColors.primary : Colors.white;
    final fg = isMine ? Colors.white : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTime)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                DateFormat('HH:mm').format(message.createdAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: _content(bg, fg, isMine),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(Color bg, Color fg, bool isMine) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );
    if (message.messageType == SupportMessageType.image) {
      final url = resolveAssetUrl(message.imageUrl) ?? '';
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          url,
          width: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 120,
            height: 80,
            color: AppColors.divider,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }
    final fontSize =
        message.messageType == SupportMessageType.emoji ? 26.0 : 14.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: isMine ? null : Border.all(color: AppColors.divider),
      ),
      child: Text(
        message.content ?? '',
        style: TextStyle(fontSize: fontSize, color: fg, height: 1.35),
      ),
    );
  }
}
