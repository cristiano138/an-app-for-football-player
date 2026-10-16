import 'package:flutter_test/flutter_test.dart';

import 'package:football/main.dart';

void main() {
  testWidgets('App 能正常启动并显示标题', (WidgetTester tester) async {
    await tester.pumpWidget(const FootballApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('足球速报'), findsWidgets);
  });
}
