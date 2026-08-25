import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/p2p.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/widgets/chat_bubble.dart';
import 'package:notetosms/ui/widgets/date_header.dart';
import 'package:notetosms/ui/widgets/message_input_bar.dart';

class BubbleChatView extends StatefulWidget {
  final String roomId;

  const BubbleChatView({super.key, required this.roomId});

  @override
  State<BubbleChatView> createState() => _BubbleChatViewState();
}

class _BubbleChatViewState extends State<BubbleChatView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _passphraseController = TextEditingController();

  bool _isVaultUnlocked = false;
  bool _isLoading = true;
  bool _isUnlocking = false;
  String? _unlockError;

  RoomItem? _room;
  List<NoteItem> _notes = [];
  StreamSubscription? _p2pSubscription;

  @override
  void initState() {
    super.initState();
    _checkVaultStatus();
  }

  @override
  void dispose() {
    _p2pSubscription?.cancel();
    _scrollController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _checkVaultStatus() async {
    setState(() => _isLoading = true);
    try {
      final status = await VaultService.instance.getStatus();
      if (status.isUnlocked) {
        setState(() => _isVaultUnlocked = true);
        await _loadRoomAndNotes();
        _subscribeToP2p();
      } else {
        setState(() => _isVaultUnlocked = false);
      }
    } catch (e) {
      debugPrint('Vault check in bubble failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToP2p() {
    _p2pSubscription?.cancel();
    _p2pSubscription = VaultService.instance.subscribeP2PEvents().listen((event) {
      if (!mounted) return;
      if (event is P2pEvent && event.eventType == 'note_received' && event.roomId == widget.roomId) {
        _loadRoomAndNotes();
      }
    });
  }

  Future<void> _handleUnlock() async {
    final pass = _passphraseController.text.trim();
    if (pass.isEmpty) return;

    setState(() {
      _isUnlocking = true;
      _unlockError = null;
    });

    try {
      await VaultService.instance.unlockOrInit(pass);
      setState(() {
        _isVaultUnlocked = true;
        _isUnlocking = false;
      });
      await _loadRoomAndNotes();
      _subscribeToP2p();
    } catch (e) {
      setState(() {
        _unlockError = 'Incorrect passphrase. Please try again.';
        _isUnlocking = false;
      });
    }
  }

  Future<void> _loadRoomAndNotes() async {
    try {
      final rooms = await VaultService.instance.listRooms();
      final currentRoom = rooms.firstWhere(
        (r) => r.id == widget.roomId,
        orElse: () => RoomItem(
          id: widget.roomId,
          name: widget.roomId,
          icon: 'chat_bubble',
          color: 0xFF1A73E8,
          createdAt: 0,
          sortOrder: 0,
        ),
      );

      final notes = await VaultService.instance.getNotes(widget.roomId);

      if (mounted) {
        setState(() {
          _room = currentRoom;
          _notes = notes;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Failed to load notes in bubble: $e');
    }
  }

  Future<void> _handleSendMessage(String text) async {
    try {
      final newNote = await VaultService.instance.saveNote(
        roomId: widget.roomId,
        content: text,
      );
      setState(() {
        _notes.add(newNote);
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _handleToggleTodo(NoteItem note, bool isCompleted) async {
    try {
      final updated = await VaultService.instance.toggleTodo(
        noteId: note.id,
        isCompleted: isCompleted,
      );
      setState(() {
        final index = _notes.indexWhere((n) => n.id == note.id);
        if (index != -1) _notes[index] = updated;
      });
    } catch (e) {
      debugPrint('Failed to update todo: $e');
    }
  }

  Future<void> _handleTogglePin(NoteItem note, bool isPinned) async {
    try {
      await VaultService.instance.pinNote(noteId: note.id, isPinned: isPinned);
      await _loadRoomAndNotes();
    } catch (e) {
      debugPrint('Failed to pin note: $e');
    }
  }

  Future<void> _handleEditNote(NoteItem note, String newContent) async {
    try {
      final updated = await VaultService.instance.updateNote(noteId: note.id, content: newContent);
      setState(() {
        final index = _notes.indexWhere((n) => n.id == note.id);
        if (index != -1) _notes[index] = updated;
      });
    } catch (e) {
      debugPrint('Failed to edit note: $e');
    }
  }

  Future<void> _handleDeleteNote(NoteItem note) async {
    try {
      await VaultService.instance.deleteNote(note.id);
      setState(() {
        _notes.removeWhere((n) => n.id == note.id);
      });
    } catch (e) {
      debugPrint('Failed to delete note: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(_room?.color ?? 0xFF1A73E8).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bubble_chart_rounded, size: 18, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '#${_room?.name ?? widget.roomId}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Icon(Icons.lock, size: 10, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text(
                              _isVaultUnlocked ? 'Encrypted Bubble' : 'Locked Vault',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_fullscreen_rounded, size: 20),
                    tooltip: 'Minimize Bubble',
                    onPressed: () => SystemNavigator.pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : !_isVaultUnlocked
              ? _buildUnlockScreen()
              : _buildTimelineAndInput(),
    );
  }

  Widget _buildUnlockScreen() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, size: 36, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Unlock Vault to Chat',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your master passphrase to decrypt #${widget.roomId}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passphraseController,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _handleUnlock(),
              decoration: InputDecoration(
                hintText: 'Master Passphrase',
                prefixIcon: const Icon(Icons.key_rounded, size: 20),
                errorText: _unlockError,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              onPressed: _isUnlocking ? null : _handleUnlock,
              child: _isUnlocking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Unlock & Open'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineAndInput() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: _notes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notes_rounded, size: 36, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text(
                        'No notes in #${_room?.name ?? widget.roomId}',
                        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    final noteDate = DateTime.fromMillisecondsSinceEpoch(note.timestampMs.toInt());

                    bool showDateHeader = false;
                    if (index == 0) {
                      showDateHeader = true;
                    } else {
                      final prevDate = DateTime.fromMillisecondsSinceEpoch(
                        _notes[index - 1].timestampMs.toInt(),
                      );
                      if (noteDate.year != prevDate.year ||
                          noteDate.month != prevDate.month ||
                          noteDate.day != prevDate.day) {
                        showDateHeader = true;
                      }
                    }

                    return Column(
                      children: [
                        if (showDateHeader) DateHeader(date: noteDate),
                        ChatBubble(
                          note: note,
                          showRoomTag: false,
                          onToggleTodo: (isCompleted) => _handleToggleTodo(note, isCompleted),
                          onTogglePin: (isPinned) => _handleTogglePin(note, isPinned),
                          onEdit: (newContent) => _handleEditNote(note, newContent),
                          onDelete: () => _handleDeleteNote(note),
                        ),
                      ],
                    );
                  },
                ),
        ),
        MessageInputBar(
          roomName: _room?.name ?? widget.roomId,
          onSendMessage: _handleSendMessage,
          onTypingChanged: (isTyping) {
            if (isTyping) _scrollToBottom();
          },
        ),
      ],
    );
  }
}
