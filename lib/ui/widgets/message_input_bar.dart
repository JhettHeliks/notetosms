import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notetosms/core/theme/app_theme.dart';

class MessageInputBar extends StatefulWidget {
  final String roomName;
  final Function(String text) onSendMessage;
  final Function(bool isTyping)? onTypingChanged;

  const MessageInputBar({
    super.key,
    required this.roomName,
    required this.onSendMessage,
    this.onTypingChanged,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;
  bool _showTools = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final canSend = _controller.text.trim().isNotEmpty;
      if (canSend != _canSend) {
        setState(() => _canSend = canSend);
        widget.onTypingChanged?.call(canSend);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.onSendMessage(text);
    _controller.clear();
    widget.onTypingChanged?.call(false);
    setState(() => _showTools = false);
  }

  void _insertPrefix(String prefix) {
    final text = _controller.text;
    if (!text.startsWith(prefix)) {
      _controller.text = '$prefix$text';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
    _focusNode.requestFocus();
  }

  void _insertTextAtCursor(String insertion) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    final newText = text.replaceRange(start, end, insertion);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom + 6
            : 12,
      ),
      color: colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                _showTools ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildToolButton(
                    icon: Icons.check_box_outlined,
                    label: 'Todo',
                    color: colorScheme.tertiary,
                    onTap: () {
                      _insertPrefix('[ ] ');
                      setState(() => _showTools = false);
                    },
                  ),
                  _buildToolButton(
                    icon: Icons.tag,
                    label: 'Tag',
                    color: colorScheme.primary,
                    onTap: () {
                      _insertTextAtCursor('#');
                      setState(() => _showTools = false);
                    },
                  ),
                  _buildToolButton(
                    icon: Icons.format_list_bulleted,
                    label: 'List',
                    color: AppTheme.accentAmber,
                    onTap: () {
                      _insertPrefix('- ');
                      setState(() => _showTools = false);
                    },
                  ),
                  _buildToolButton(
                    icon: Icons.shield_outlined,
                    label: 'Encrypted',
                    color: colorScheme.primary,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All notes are encrypted with ChaCha20-Poly1305 AEAD.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      setState(() => _showTools = false);
                    },
                  ),
                ],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: IconButton(
                          icon: AnimatedRotation(
                            turns: _showTools ? 0.125 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              _showTools ? Icons.add_circle : Icons.add_circle_outline,
                              color: _showTools
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              size: 26,
                            ),
                          ),
                          tooltip: 'Add note attachments & tags',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            setState(() => _showTools = !_showTools);
                          },
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15.5,
                            ),
                            maxLines: 5,
                            minLines: 1,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: 'Note in #${widget.roomName}...',
                              hintStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                fontSize: 15,
                              ),
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 14,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: Material(
                  color: _canSend ? colorScheme.primary : colorScheme.surfaceContainerHigh,
                  shape: const CircleBorder(),
                  elevation: _canSend ? 2 : 0,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _canSend
                        ? _send
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Type a note or checklist item above.'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: child,
                        ),
                        child: _canSend
                            ? Icon(
                                Icons.arrow_upward_rounded,
                                key: const ValueKey('send_icon'),
                                color: colorScheme.onPrimary,
                                size: 24,
                              )
                            : Icon(
                                Icons.mic_rounded,
                                key: const ValueKey('mic_icon'),
                                color: colorScheme.onSurfaceVariant,
                                size: 22,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
