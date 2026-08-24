import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2P Room Invite Payload Tests', () {
    test('Invites with notetosms:// URI scheme format correctly', () {
      final mockPayload = {
        'room_id': 'project-x',
        'room_name': 'Project X',
        'shared_key_b64': base64Encode(List.filled(32, 7)),
        'host_node_id': 'node-123456789',
        'relay_url': 'https://relay.notetosms.org',
        'direct_addrs': ['192.168.1.50:11223'],
      };

      final jsonStr = jsonEncode(mockPayload);
      final base64Invite = base64Encode(utf8.encode(jsonStr));
      final inviteUri = 'notetosms://invite?data=$base64Invite';

      expect(inviteUri.startsWith('notetosms://invite?data='), isTrue);

      final extractedBase64 = inviteUri.replaceFirst('notetosms://invite?data=', '');
      final decodedJson = jsonDecode(utf8.decode(base64Decode(extractedBase64))) as Map<String, dynamic>;

      expect(decodedJson['room_id'], equals('project-x'));
      expect(decodedJson['room_name'], equals('Project X'));
      expect(decodedJson['host_node_id'], equals('node-123456789'));
    });
  });
}
