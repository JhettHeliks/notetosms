import 'package:flutter_test/flutter_test.dart';
import 'package:notetosms/main.dart';
import 'package:notetosms/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Can load NoteToSmsApp', (WidgetTester tester) async {
    await tester.pumpWidget(const NoteToSmsApp());
    expect(find.text('notetosms'), findsWidgets);
  });
}
