import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/update_service.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/dialogs/backup_restore_dialog.dart';
import 'package:notetosms/ui/dialogs/room_dialogs.dart';
import 'package:notetosms/ui/dialogs/settings_dialog.dart';
import 'package:notetosms/ui/dialogs/update_dialog.dart';
import 'package:notetosms/ui/dialogs/version_history_dialog.dart';
import 'package:notetosms/ui/screens/unlock_vault_screen.dart';

class RoomPreview {
  final RoomItem room;
  final NoteItem? latestNote;
  final int noteCount;

  const RoomPreview({
    required this.room,
    this.latestNote,
    required this.noteCount,
  });
}

class ConversationListView extends StatefulWidget {
  final String? selectedRoomId;
  final Function(String roomId) onSelectRoom;
  final bool isMasterDetail;

  const ConversationListView({
    super.key,
    this.selectedRoomId,
    required this.onSelectRoom,
    this.isMasterDetail = false,
  });

  @override
  State<ConversationListView> createState() => _ConversationListViewState();
}

class _ConversationListViewState extends State<ConversationListView> {
  final TextEditingController _searchController = TextEditingController();
  List<RoomPreview> _previews = [];
  bool _isLoading = true;
  String _searchQuery = '';
  AppUpdateInfo? _availableUpdate;
  bool _dismissedUpdateBanner = false;

  @override
  void initState() {
    super.initState();
    _loadPreviews();
    _checkSilentlyForUpdates();
  }

  Future<void> _checkSilentlyForUpdates() async {
    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (mounted && info.hasUpdate) {
        setState(() {
          _availableUpdate = info;
        });
      }
    } catch (_) {
      // Ignore background check network errors silently
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPreviews() async {
    setState(() => _isLoading = true);
    try {
      final rooms = await VaultService.instance.listRooms();
      final List<RoomPreview> loaded = [];

      for (final room in rooms) {
        final notes = await VaultService.instance.getNotes(room.id);
        loaded.add(RoomPreview(
          room: room,
          latestNote: notes.isNotEmpty ? notes.last : null,
          noteCount: notes.length,
        ));
      }

      if (mounted) {
        setState(() {
          _previews = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load conversations: $e')),
        );
      }
    }
  }

  Future<void> _handleLockVault() async {
    await VaultService.instance.lock();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const UnlockVaultScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
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

  String _formatTimestamp(int timestampMs) {
    if (timestampMs == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final noteDay = DateTime(date.year, date.month, date.day);

    if (noteDay == today) {
      return DateFormat('h:mm a').format(date);
    } else if (noteDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (now.year == date.year) {
      return DateFormat('MMM d').format(date);
    } else {
      return DateFormat('MM/dd/yy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final filteredPreviews = _previews.filter((preview) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final nameMatches = preview.room.name.toLowerCase().contains(q);
      final noteMatches =
          preview.latestNote?.content.toLowerCase().contains(q) ?? false;
      return nameMatches || noteMatches;
    });

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top Search Bar (Google Messages Pill Header)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.search_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search notes & tags...',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                            fontSize: 15,
                          ),
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        color: colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      color: colorScheme.surfaceContainerHigh,
                      onSelected: (value) {
                        if (value == 'security') {
                          SettingsDialog.showSecurityInfo(context);
                        } else if (value == 'passphrase') {
                          SettingsDialog.showChangePassphrase(context);
                        } else if (value == 'new_room') {
                          RoomDialogs.showCreateRoom(context, _loadPreviews);
                        } else if (value == 'join_room') {
                          RoomDialogs.showJoinRoomDialog(
                            context,
                            onRoomJoined: (room) {
                              _loadPreviews();
                              widget.onSelectRoom(room.id);
                            },
                          );
                        } else if (value == 'backup_restore') {
                          BackupRestoreDialog.show(
                            context,
                            onRestoreComplete: _loadPreviews,
                          );
                        } else if (value == 'security') {
                          SettingsDialog.showSecurityInfo(context);
                        } else if (value == 'check_updates') {
                          VersionHistoryDialog.show(context);
                        } else if (value == 'lock') {
                          _handleLockVault();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'new_room',
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline, size: 20),
                              SizedBox(width: 10),
                              Text('New Channel'),
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
                          value: 'passphrase',
                          child: Row(
                            children: [
                              Icon(Icons.key_outlined, size: 20, color: AppTheme.accentAmber),
                              SizedBox(width: 10),
                              Text('Change Passphrase'),
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
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'lock',
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline, size: 20, color: AppTheme.accentRose),
                              SizedBox(width: 10),
                              Text('Lock Vault', style: TextStyle(color: AppTheme.accentRose)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),

            // In-App Update Notification Banner
            if (_availableUpdate != null && !_dismissedUpdateBanner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.system_update_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Update Available: v${_availableUpdate!.latestVersion}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              _availableUpdate!.isPrerelease ? 'New beta build ready' : 'New release ready to install',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => UpdateDialog.show(context, _availableUpdate!),
                        child: const Text('Update', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.close, size: 16, color: colorScheme.onPrimaryContainer),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _dismissedUpdateBanner = true),
                      ),
                    ],
                  ),
                ),
              ),

            // Conversation List
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                  : filteredPreviews.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 48,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                     ? 'No conversations match "$_searchQuery"'
                                    : 'No channels yet',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadPreviews,
                          color: colorScheme.primary,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: filteredPreviews.length,
                            itemBuilder: (context, index) {
                              final preview = filteredPreviews[index];
                              final room = preview.room;
                              final isSelected =
                                  widget.isMasterDetail && room.id == widget.selectedRoomId;
                              final roomColor = Color(room.color);
                              final latestText = preview.latestNote?.content ?? 'No notes yet';
                              final timestampStr = preview.latestNote != null
                                  ? _formatTimestamp(preview.latestNote!.timestampMs.toInt())
                                  : '';

                              return Material(
                                color: isSelected
                                    ? colorScheme.secondaryContainer
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () => widget.onSelectRoom(room.id),
                                  onLongPress: () {
                                    if (room.id != 'general') {
                                      RoomDialogs.showDeleteRoom(
                                        context,
                                        room.id,
                                        room.name,
                                        _loadPreviews,
                                      );
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        // Circular Avatar with room icon & tint
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: roomColor.withValues(alpha: 0.18),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _getIconData(room.icon),
                                            color: roomColor,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // Title and Snippet
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      '#${room.name}',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: isSelected ||
                                                                preview.noteCount > 0
                                                            ? FontWeight.w700
                                                            : FontWeight.w600,
                                                        color: isSelected
                                                            ? colorScheme.onSecondaryContainer
                                                            : colorScheme.onSurface,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (timestampStr.isNotEmpty)
                                                    Text(
                                                      timestampStr,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: colorScheme.onSurfaceVariant,
                                                        fontWeight: FontWeight.w400,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      latestText,
                                                      style: TextStyle(
                                                        fontSize: 13.5,
                                                        color: colorScheme.onSurfaceVariant,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (preview.noteCount > 0) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.surfaceContainerHighest,
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        '${preview.noteCount}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: colorScheme.onSurfaceVariant,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'join_p2p_btn',
            tooltip: 'Join Shared Room',
            onPressed: () => RoomDialogs.showJoinRoomDialog(
              context,
              onRoomJoined: (room) {
                _loadPreviews();
                widget.onSelectRoom(room.id);
              },
            ),
            backgroundColor: colorScheme.surfaceContainerHigh,
            foregroundColor: colorScheme.primary,
            child: const Icon(Icons.group_add_rounded, size: 20),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            heroTag: 'new_thread_btn',
            onPressed: () => RoomDialogs.showCreateRoom(context, _loadPreviews),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            elevation: 2,
            icon: const Icon(Icons.edit_outlined, size: 20),
            label: const Text('New Thread', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

extension _ListFilter<T> on List<T> {
  List<T> filter(bool Function(T) test) {
    final result = <T>[];
    for (final element in this) {
      if (test(element)) {
        result.add(element);
      }
    }
    return result;
  }
}
