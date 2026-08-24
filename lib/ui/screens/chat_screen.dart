import 'package:flutter/material.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/dialogs/room_dialogs.dart';
import 'package:notetosms/ui/dialogs/settings_dialog.dart';
import 'package:notetosms/ui/views/conversation_list_view.dart';
import 'package:notetosms/ui/widgets/chat_bubble.dart';
import 'package:notetosms/ui/widgets/date_header.dart';
import 'package:notetosms/ui/widgets/message_input_bar.dart';

class ChatScreen extends StatefulWidget {
  final String? initialRoomId;

  const ChatScreen({super.key, this.initialRoomId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<RoomItem> _rooms = [];
  String _currentRoomId = 'general';
  List<NoteItem> _notes = [];

  bool _isLoading = true;
  bool _isSearching = false;
  bool _showSearchBar = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRoomId != null) {
      _currentRoomId = widget.initialRoomId!;
    }
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final rooms = await VaultService.instance.listRooms();
      setState(() {
        _rooms = rooms;
        if (!_rooms.any((r) => r.id == _currentRoomId) && _rooms.isNotEmpty) {
          _currentRoomId = _rooms.first.id;
        }
      });
      await _loadNotesForCurrentRoom();
    } catch (e) {
      _showSnackBar('Failed to load vault data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNotesForCurrentRoom() async {
    try {
      final notes = await VaultService.instance.getNotes(_currentRoomId);
      if (mounted) {
        setState(() {
          _notes = notes;
          _isSearching = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      _showSnackBar('Failed to load notes: $e');
    }
  }

  Future<void> _handleSendMessage(String text) async {
    try {
      final newNote = await VaultService.instance.saveNote(
        roomId: _currentRoomId,
        content: text,
      );
      setState(() {
        _notes.add(newNote);
      });
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Error saving encrypted note: $e');
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
        if (index != -1) {
          _notes[index] = updated;
        }
      });
    } catch (e) {
      _showSnackBar('Failed to update todo: $e');
    }
  }

  Future<void> _handleTogglePin(NoteItem note, bool isPinned) async {
    try {
      await VaultService.instance.pinNote(
        noteId: note.id,
        isPinned: isPinned,
      );
      await _loadNotesForCurrentRoom();
      _showSnackBar(isPinned ? 'Note pinned to top' : 'Note unpinned');
    } catch (e) {
      _showSnackBar('Failed to pin note: $e');
    }
  }

  Future<void> _handleEditNote(NoteItem note, String newContent) async {
    try {
      final updated = await VaultService.instance.updateNote(
        noteId: note.id,
        content: newContent,
      );
      setState(() {
        final index = _notes.indexWhere((n) => n.id == note.id);
        if (index != -1) {
          _notes[index] = updated;
        }
      });
      _showSnackBar('Note updated');
    } catch (e) {
      _showSnackBar('Failed to edit note: $e');
    }
  }

  Future<void> _handleDeleteNote(NoteItem note) async {
    try {
      await VaultService.instance.deleteNote(note.id);
      setState(() {
        _notes.removeWhere((n) => n.id == note.id);
      });
      _showSnackBar('Note deleted');
    } catch (e) {
      _showSnackBar('Failed to delete note: $e');
    }
  }

  Future<void> _handleSearch(String query) async {
    if (query.trim().isEmpty) {
      await _loadNotesForCurrentRoom();
      return;
    }

    try {
      final results = await VaultService.instance.searchNotes(
        query: query.trim(),
        roomIdFilter: _currentRoomId,
      );
      setState(() {
        _notes = results;
        _isSearching = true;
      });
    } catch (e) {
      _showSnackBar('Search failed: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  RoomItem? get _currentRoom {
    if (_rooms.isEmpty) return null;
    return _rooms.firstWhere(
      (r) => r.id == _currentRoomId,
      orElse: () => _rooms.first,
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'lock':
        return Icons.lock_outline;
      case 'lightbulb':
        return Icons.lightbulb_outline;
      case 'work':
        return Icons.work_outline;
      case 'code':
        return Icons.code;
      case 'star':
        return Icons.star_outline;
      case 'fitness':
        return Icons.fitness_center;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWideScreen = screenWidth >= 700;

    if (!isWideScreen && widget.initialRoomId == null) {
      return ConversationListView(
        selectedRoomId: _currentRoomId,
        onSelectRoom: (roomId) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(initialRoomId: roomId),
            ),
          ).then((_) => _loadInitialData());
        },
      );
    }

    if (isWideScreen) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 340,
              child: ConversationListView(
                selectedRoomId: _currentRoomId,
                isMasterDetail: true,
                onSelectRoom: (roomId) {
                  if (_currentRoomId != roomId) {
                    setState(() => _currentRoomId = roomId);
                    _loadNotesForCurrentRoom();
                  }
                },
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: _buildChatDetail(showBackButton: false),
            ),
          ],
        ),
      );
    }

    return _buildChatDetail(showBackButton: true);
  }

  Widget _buildChatDetail({required bool showBackButton}) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentRoom = _currentRoom;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        leadingWidth: showBackButton ? 48 : 16,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(currentRoom?.color ?? 0xFF1A73E8).withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIconData(currentRoom?.icon ?? 'chat_bubble'),
                color: Color(currentRoom?.color ?? 0xFF1A73E8),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '#${currentRoom?.name ?? _currentRoomId}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.verified_user_rounded,
                        size: 14,
                        color: colorScheme.tertiary,
                      ),
                    ],
                  ),
                  Text(
                    '${_notes.length} note${_notes.length == 1 ? '' : 's'} • End-to-end encrypted',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showSearchBar ? Icons.close : Icons.search_rounded),
            tooltip: 'Search in conversation',
            onPressed: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  _searchController.clear();
                  _loadNotesForCurrentRoom();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Security Specs',
            onPressed: () => SettingsDialog.showSecurityInfo(context),
          ),
          if (currentRoom != null && currentRoom.id != 'general')
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: colorScheme.surfaceContainerHigh,
              onSelected: (value) {
                if (value == 'delete') {
                  RoomDialogs.showDeleteRoom(
                    context,
                    currentRoom.id,
                    currentRoom.name,
                    () {
                      if (showBackButton) {
                        Navigator.pop(context);
                      } else {
                        _loadInitialData();
                      }
                    },
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: AppTheme.accentRose, size: 20),
                      SizedBox(width: 10),
                      Text('Delete Channel', style: TextStyle(color: AppTheme.accentRose)),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (_showSearchBar)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colorScheme.surface,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: colorScheme.onSurface, fontSize: 14.5),
                onChanged: _handleSearch,
                decoration: InputDecoration(
                  hintText: 'Search within #${currentRoom?.name ?? _currentRoomId}...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _loadNotesForCurrentRoom();
                          },
                        )
                      : null,
                ),
              ),
            ),
          if (_isSearching)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: colorScheme.primary.withValues(alpha: 0.15),
              width: double.infinity,
              child: Row(
                children: [
                  Icon(Icons.manage_search, color: colorScheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Found ${_notes.length} match${_notes.length == 1 ? '' : 'es'} in #${currentRoom?.name ?? _currentRoomId}',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                : _notes.isEmpty
                    ? _buildEmptyState()
                    : _buildNotesTimeline(),
          ),
          MessageInputBar(
            roomName: currentRoom?.name ?? _currentRoomId,
            onSendMessage: _handleSendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_chat_unread_outlined,
              size: 40,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isSearching
                ? 'No matching notes in #${_currentRoom?.name ?? _currentRoomId}'
                : 'No notes in #${_currentRoom?.name ?? _currentRoomId}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Type a private note or checklist below.',
            style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesTimeline() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

        bool isPreviousInCluster = false;
        bool isNextInCluster = false;

        if (index > 0) {
          final prevNote = _notes[index - 1];
          final diff = (note.timestampMs.toInt() - prevNote.timestampMs.toInt()).abs();
          if (prevNote.roomId == note.roomId && diff <= 120000 && !showDateHeader) {
            isPreviousInCluster = true;
          }
        }

        if (index < _notes.length - 1) {
          final nextNote = _notes[index + 1];
          final nextDate = DateTime.fromMillisecondsSinceEpoch(nextNote.timestampMs.toInt());
          final isSameDay = noteDate.year == nextDate.year &&
              noteDate.month == nextDate.month &&
              noteDate.day == nextDate.day;
          final diff = (nextNote.timestampMs.toInt() - note.timestampMs.toInt()).abs();
          if (nextNote.roomId == note.roomId && diff <= 120000 && isSameDay) {
            isNextInCluster = true;
          }
        }

        return Column(
          children: [
            if (showDateHeader) DateHeader(date: noteDate),
            ChatBubble(
              note: note,
              showRoomTag: false,
              isPreviousInCluster: isPreviousInCluster,
              isNextInCluster: isNextInCluster,
              onToggleTodo: (isCompleted) => _handleToggleTodo(note, isCompleted),
              onTogglePin: (isPinned) => _handleTogglePin(note, isPinned),
              onEdit: (newContent) => _handleEditNote(note, newContent),
              onDelete: () => _handleDeleteNote(note),
            ),
          ],
        );
      },
    );
  }
}
