import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Bubble & Deep Link Routing Tests', () {
    test('Parses /bubble?roomId=project-x route query correctly', () {
      final uri = Uri.parse('/bubble?roomId=project-x');
      expect(uri.path, equals('/bubble'));
      expect(uri.queryParameters['roomId'], equals('project-x'));
    });

    test('Parses /bubble/work-tasks path parameter correctly', () {
      final uri = Uri.parse('/bubble/work-tasks');
      expect(uri.pathSegments, equals(['bubble', 'work-tasks']));
      expect(uri.pathSegments[1], equals('work-tasks'));
    });

    test('Parses notetosms://room/ideas custom scheme URI correctly', () {
      final uri = Uri.parse('notetosms://room/ideas');
      expect(uri.scheme, equals('notetosms'));
      expect(uri.host, equals('room'));
      expect(uri.pathSegments, equals(['ideas']));
      expect(uri.pathSegments.last, equals('ideas'));
    });

    test('Parses chatnotes://room/finance legacy custom scheme URI correctly', () {
      final uri = Uri.parse('chatnotes://room/finance');
      expect(uri.scheme, equals('chatnotes'));
      expect(uri.host, equals('room'));
      expect(uri.pathSegments, equals(['finance']));
      expect(uri.pathSegments.last, equals('finance'));
    });
  });
}
