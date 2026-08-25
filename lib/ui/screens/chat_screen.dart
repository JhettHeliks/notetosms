import 'dart:async';
import 'package:flutter/material.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/bubble_service.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/p2p.dart';
import 'package:notetosms/src/rust/p2p_protocol.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/dialogs/backup_restore_dialog.dart';
import 'package:notetosms/ui/dialogs/room_dialogs.dart';
import 'package:notetosms/ui/dialogs/settings_dialog.dart';
import 'package:notetosms/ui/dialogs/version_history_dialog.dart';
import 'package:notetosms/ui/views/conversation_list_view.dart';
import 'package:notetosms/ui/widgets/chat_bubble.dart';
import 'package:notetosms/ui/widgets/date_header.dart';
import 'package:notetosms/ui/widgets/message_input_bar.dart';
import 'package:notetosms/ui/widgets/share_thread_card.dart';
import 'package:notetosms/ui/widgets/typing_indicator_bubble.dart';

class _TimelineAnnouncement {
  final String text;
  final DateTime timestamp;
  const _TimelineAnnouncement({required this.text, required this.timestamp});
}

class ChatScreen extends StatefulWidget {
  final String? initialRoomId;
  final String? initialInviteData;

  const ChatScreen({super.key, this.initialRoomId, this.initialInviteData});

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
  bool _isShareCardDismissed = false;

  // P2P Live Sync, Presence & Room Membership State
  int _totalMembers = 1;
  int _activeOnline = 1;
  bool _isRemoteTyping = false;
  String? _remoteTypingPeerName;
  Timer? _remoteTypingTimer;
  StreamSubscription? _p2pSubscription;
  StreamSubscription<RoomEvent>? _roomSubscription;
  final List<_TimelineAnnouncement> _joinAnnouncements = [];
  final Map<String, String> _remoteNoteAuthors = {};
  final Set<String> _announcedPeerIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialRoomId != null) {
      _currentRoomId = widget.initialRoomId!;
    }
    _loadInitialData();
    _initP2p();

    if (widget.initialInviteData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          RoomDialogs.showJoinRoomDialog(
            context,
            initialInviteData: widget.initialInviteData,
            onRoomJoined: (room) {
              _loadInitialData();
              _switchRoom(room.id);
            },
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _p2pSubscription?.cancel();
    _remoteTypingTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initP2p() async {
    try {
      await VaultService.instance.startP2PNode();
      _p2pSubscription = VaultService.instance.subscribeP2PEvents().listen((event) {
        if (event is P2pEvent) {
          _handleLegacyP2pEvent(event);
        }
      });
      _subscribeToCurrentRoomEvents();
    } catch (e) {
      debugPrint('P2P initialization note: $e');
    }
  }

  void _subscribeToCurrentRoomEvents() {
    _roomSubscription?.cancel();
    _remoteTypingTimer?.cancel();
    if (mounted) {
      setState(() {
        _isRemoteTyping = false;
        _remoteTypingPeerName = null;
      });
    }

    _roomSubscription = VaultService.instance
        .subscribeRoomEvents(_currentRoomId)
        .listen((event) {
      if (!mounted || event.roomId != _currentRoomId) return;

      if (event.eventType == 'active_peer_count') {
        setState(() {
          _totalMembers = event.totalMembers > 0 ? event.totalMembers : _totalMembers;
          _activeOnline = event.activeOnline > 0 ? event.activeOnline : _activeOnline;
        });
      } else if (event.eventType == 'peer_joined') {
        final peerKey = event.peerId ?? event.displayName ?? 'peer';
        final displayName = event.displayName ?? 'A device';
        final isNew = !_announcedPeerIds.contains(peerKey);
        if (isNew) {
          _announcedPeerIds.add(peerKey);
          setState(() {
            _activeOnline = event.activeOnline > 0 ? event.activeOnline : _activeOnline + 1;
            _totalMembers = event.totalMembers > 0 ? event.totalMembers : (_totalMembers < _activeOnline ? _activeOnline : _totalMembers);
            _joinAnnouncements.add(_TimelineAnnouncement(
              text: '$displayName joined the thread',
              timestamp: DateTime.now(),
            ));
          });
          _showSnackBar('$displayName joined #${_currentRoom?.name ?? _currentRoomId}');
        }
      } else if (event.eventType == 'peer_left') {
        setState(() {
          _activeOnline = event.activeOnline > 0 ? event.activeOnline : (_activeOnline > 1 ? _activeOnline - 1 : 1);
        });
      } else if (event.eventType == 'remote_typing') {
        final isTyping = event.isTyping ?? false;
        setState(() {
          _isRemoteTyping = isTyping;
          _remoteTypingPeerName = event.displayName;
        });
        _remoteTypingTimer?.cancel();
        if (isTyping) {
          _remoteTypingTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isRemoteTyping = false);
          });
        }
      } else if (event.eventType == 'note_received') {
        if (event.note != null) {
          final authorName = event.displayName ??
              (event.peerId != null ? 'Peer (${event.peerId!.substring(0, event.peerId!.length.clamp(0, 6))})' : 'Peer');
          _remoteNoteAuthors[event.note!.id] = authorName;
        }
        _remoteTypingTimer?.cancel();
        setState(() => _isRemoteTyping = false);
        _loadNotesForCurrentRoom();
      }
    });
  }

  void _handleLegacyP2pEvent(P2pEvent event) {
    if (!mounted) return;
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

  void _openShareSheet() {
    final currentRoom = _currentRoom;
    if (currentRoom == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: ShareThreadCard(
              room: currentRoom,
              onDismiss: () => Navigator.pop(ctx),
            ),
          ),
        ),
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

  void _switchRoom(String roomId) {
    if (_currentRoomId != roomId) {
      setState(() {
        _currentRoomId = roomId;
        _isShareCardDismissed = false;
        _totalMembers = 1;
        _activeOnline = 1;
        _isRemoteTyping = false;
        _remoteTypingPeerName = null;
        _joinAnnouncements.clear();
        _announcedPeerIds.clear();
        _remoteNoteAuthors.clear();
      });
      _subscribeToCurrentRoomEvents();
      _loadNotesForCurrentRoom();
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
          setState(() {
            _isShareCardDismissed = false;
          });
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(initialRoomId: roomId),
            ),
          ).then((_) {
            _loadInitialData();
            _subscribeToCurrentRoomEvents();
          });
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
                onSelectRoom: _switchRoom,
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
                  Row(
                    children: [
                      if (_activeOnline > 1) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          '$_totalMembers member${_totalMembers == 1 ? '' : 's'} • $_activeOnline online • E2E Encrypted',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _activeOnline > 1 ? Colors.greenAccent.shade400 : colorScheme.onSurfaceVariant,
                            fontWeight: _activeOnline > 1 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
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
          if (currentRoom != null)
            IconButton(
              icon: const Icon(Icons.qr_code_2_rounded),
              tooltip: 'Share Room via P2P',
              onPressed: () {
                if (_notes.isEmpty && _isShareCardDismissed) {
                  setState(() => _isShareCardDismissed = false);
                } else {
                  _openShareSheet();
                }
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: colorScheme.surfaceContainerHigh,
            onSelected: (value) {
              if (value == 'share') {
                if (currentRoom != null) {
                  _openShareSheet();
                }
              } else if (value == 'join_room') {
                RoomDialogs.showJoinRoomDialog(
                  context,
                  onRoomJoined: (room) {
                    _loadInitialData();
                    _switchRoom(room.id);
                  },
                );
              } else if (value == 'bubble') {
                if (currentRoom != null) {
                  BubbleService.instance
                      .showAsBubble(
                        roomId: currentRoom.id,
                        roomName: currentRoom.name,
                        icon: currentRoom.icon,
                      )
                      .then((success) {
                    if (!success && mounted) {
                      _showSnackBar('System bubbles are supported on Android 11+.');
                    } else if (success && mounted) {
                      _showSnackBar('Popped out #${currentRoom.name} as a floating bubble!');
                    }
                  });
                }
              } else if (value == 'backup_restore') {
                BackupRestoreDialog.show(
                  context,
                  onRestoreComplete: () {
                    _loadInitialData();
                  },
                );
              } else if (value == 'security') {
                SettingsDialog.showSecurityInfo(context);
              } else if (value == 'check_updates') {
                VersionHistoryDialog.show(context);
              } else if (value == 'delete') {
                if (currentRoom != null) {
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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'bubble',
                child: Row(
                  children: [
                    Icon(Icons.bubble_chart_rounded, size: 20, color: AppTheme.primary),
                    SizedBox(width: 10),
                    Text('Pop Out as Bubble'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.qr_code_rounded, size: 20, color: AppTheme.secondary),
                    SizedBox(width: 10),
                    Text('Share Thread / Invite'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'join_room',
                child: Row(
                  children: [
                    Icon(Icons.group_add_rounded, size: 20, color: AppTheme.tertiary),
                    SizedBox(width: 10),
                    Text('Join Shared Thread'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'backup_restore',
                child: Row(
                  children: [
                    Icon(Icons.backup_rounded, size: 20, color: AppTheme.tertiary),
                    SizedBox(width: 10),
                    Text('Backup & Restore'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'security',
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Security Specs'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'check_updates',
                child: Row(
                  children: [
                    Icon(Icons.system_update_rounded, size: 20, color: AppTheme.primary),
                    SizedBox(width: 10),
                    Text('Check for Updates'),
                  ],
                ),
              ),
              if (currentRoom != null && currentRoom.id != 'general') ...[
                const PopupMenuDivider(),
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
                decoration: InputDecoration(
                  hintText: 'Search within #${currentRoom?.name ?? _currentRoomId}...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _loadNotesForCurrentRoom();
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLow,
                  border: OutlineInputBorde                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _handleSearch,
              ),
            ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                : _notes.isEmpty
                    ? _buildEmptyState()
                    : _buildNotesTimeline(),
          ),
          if (_isRemoteTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: TypingIndicatorBubble(
                label: _remoteTypingPeerName != null
                    ? '$_remoteTypingPeerName is typing...'
                    : 'Peer is drafting note...',
              ),
            ),
          MessageInputBar(
            roomName: currentRoom?.name ?? _currentRoomId,
            onSendMessage: _handleSendMessage,
            onTypingChanged: (isTyping) {
              VaultService.instance.sendTypingStatus(
                roomId: _currentRoomId,
                isTyping: isTyping,
              );
              if (isTyping) _scrollToBottom();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {() {
    final colorScheme = Theme.of(context).colorScheme;
    final currentRoom = _currentRoom;

    if (!_isSearching && currentRoom != null && !_isShareCardDismissed) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ShareThreadCard(
                room: currentRoom,
                onDismiss: () => setState(() => _isShareCardDismissed = true),
              ),
              const SizedBox(height: 12),
              Text(
                'Type a private note or checklist below.',
                style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

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
                ? 'No matching notes in #${currentRoom?.name ?? _currentRoomId}'
                : 'No notes in #${currentRoom?.name ?? _currentRoomId}',
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
          if (!_isSearching && currentRoom != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: const Text('Show Invite QR Code', style: TextStyle(fontSize: 13)),
              onPressed: () => setState(() => _isShareCardDismissed = false),
            ),
          ],
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

        final isLocal = !_remoteNoteAuthors.containsKey(note.id);
        final senderName = _remoteNoteAuthors[note.id];

        return Column(
          children: [
            if (showDateHeader) DateHeader(date: noteDate),
            if (index == 0 && _joinAnnouncements.isNotEmpty) ...[
              for (final announcement in _joinAnnouncements)
                _JoinNotificationPill(text: announcement.text),
            ],
            ChatBubble(
              note: note,
              showRoomTag: false,
              isPreviousInCluster: isPreviousInCluster,
              isNextInCluster: isNextInCluster,
              isLocal: isLocal,
              senderName: senderName,
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

class _JoinNotificationPill extends StatelessWidget {
  final String text;
  const _JoinNotificationPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_add_rounded, size: 14, color: AppTheme.tertiary),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
