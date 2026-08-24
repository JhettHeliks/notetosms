import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:notetosms/src/rust/api/notes.dart' as rust_api;
import 'package:notetosms/src/rust/storage.dart';

class VaultService {
  VaultService._();
  static final VaultService instance = VaultService._();

  String? _dbPath;

  Future<String> getDatabasePath() async {
    if (_dbPath != null) return _dbPath!;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      _dbPath = '${docDir.path}${Platform.pathSeparator}notetosms_vault.db';
    } catch (e) {
      debugPrint('Path provider unavailable, falling back to local relative path: $e');
      _dbPath = 'notetosms_vault.db';
    }
    return _dbPath!;
  }

  Future<VaultStatus> getStatus() async {
    return rust_api.getVaultStatus();
  }

  Future<VaultStatus> unlockOrInit(String passphrase) async {
    final path = await getDatabasePath();
    return rust_api.initVaultAtPath(dbPath: path, passphrase: passphrase);
  }

  Future<void> lock() async {
    await rust_api.lockVault();
  }

  Future<void> changePassphrase({
    required String oldPass,
    required String newPass,
  }) async {
    await rust_api.changePassphrase(oldPass: oldPass, newPass: newPass);
  }

  Future<List<RoomItem>> listRooms() async {
    return rust_api.listRooms();
  }

  Future<RoomItem> createRoom({
    required String id,
    required String name,
    required String icon,
    required int color,
  }) async {
    return rust_api.createRoom(
      id: id,
      name: name,
      icon: icon,
      color: color,
    );
  }

  Future<void> deleteRoom(String id) async {
    await rust_api.deleteRoom(roomId: id);
  }

  Future<List<NoteItem>> getNotes(String roomId) async {
    return rust_api.getNotes(roomId: roomId);
  }

  Future<NoteItem> saveNote({
    required String roomId,
    required String content,
  }) async {
    return rust_api.saveNote(roomId: roomId, content: content);
  }

  Future<NoteItem> toggleTodo({
    required String noteId,
    required bool isCompleted,
  }) async {
    return rust_api.toggleTodo(noteId: noteId, isCompleted: isCompleted);
  }

  Future<NoteItem> pinNote({
    required String noteId,
    required bool isPinned,
  }) async {
    return rust_api.pinNote(noteId: noteId, isPinned: isPinned);
  }

  Future<NoteItem> updateNote({
    required String noteId,
    required String content,
  }) async {
    return rust_api.updateNote(noteId: noteId, content: content);
  }

  Future<void> deleteNote(String noteId) async {
    await rust_api.deleteNote(noteId: noteId);
  }

  Future<List<NoteItem>> searchNotes({
    required String query,
    String? roomIdFilter,
  }) async {
    return rust_api.searchNotes(query: query, roomIdFilter: roomIdFilter);
  }
}
