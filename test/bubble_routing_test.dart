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

    test('Parses notetosms://join?data=... and chatnotes://join deep links correctly', () {
      final uri1 = Uri.parse('notetosms://join?data=eyJ2ZXJzaW9uIjoxLCJyb29tX2lkIjoidGVzdCJ9');
      expect(uri1.scheme, equals('notetosms'));
      expect(uri1.host, equals('join'));
      expect(uri1.queryParameters['data'], equals('eyJ2ZXJzaW9uIjoxLCJyb29tX2lkIjoidGVzdCJ9'));

      final uri2 = Uri.parse('chatnotes://join?data=eyJ2ZXJzaW9uIjoxLCJyb29tX2lkIjoidGVzdCJ9');
      expect(uri2.scheme, equals('chatnotes'));
      expect(uri2.host, equals('join'));
      expect(uri2.queryParameters['data'], equals('eyJ2ZXJzaW9uIjoxLCJyb29tX2lkIjoidGVzdCJ9'));
    });
  });
}
