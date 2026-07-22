import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application/main.dart';

void main() {
  testWidgets('App renders bottom nav bar', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('蓝牙'), findsOneWidget);
    expect(find.text('扫码'), findsOneWidget);
    expect(find.text('扩展'), findsOneWidget);
  });
}
