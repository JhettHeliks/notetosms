import 'dart:async';
import 'package:notetosms/src/rust/api/notes.dart' as rust_api;
import 'package:notetosms/src/rust/p2p_protocol.dart';
import 'package:notetosms/src/rust/storage.dart';

/// Service managing peer-to-peer live thread synchronization, invitation tickets, and presence events
class P2pService {
  P2pService._();
  static final P2pService instance = P2pService._();

  /// Initialize and start the local Iroh endpoint
  Future<String> startP2PNode() async {
    return rust_api.startP2PNode();
  }

  /// Export a combined ticket containing encryption keys and Iroh endpoint dialing addresses
  Future<String> exportRoomTicket({required String roomId}) async {
    return rust_api.exportRoomTicket(roomId: roomId);
  }

  /// Import a combined ticket, connect to the peer, sync history, and register room in local SQLite
  Future<RoomItem> importRoomTicket({required String ticket}) async {
    return rust_api.importRoomTicket(ticket: ticket);
  }

  /// Send live typing indicator status for a room across connected P2P peers
  Future<void> sendTypingStatus({
    required String roomId,
    required bool isTyping,
  }) async {
    await rust_api.sendTypingStatus(roomId: roomId, isTyping: isTyping);
  }

  /// Subscribe to rich live room events (notes, typing, peer presence, member count)
  Stream<RoomEvent> subscribeRoomEvents(String roomId) {
    return rust_api.subscribeRoomEvents(roomId: roomId);
  }

  /// Set the local device display name for P2P presence
  Future<void> setP2PDisplayName(String displayName) async {
    await rust_api.setP2PDisplayName(displayName: displayName);
  }

  /// Get the local device display name
  Future<String> getP2PDisplayName() async {
    return rust_api.getP2PDisplayName();
  }
}
