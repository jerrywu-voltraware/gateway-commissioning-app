import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openDoneSection(WidgetTester tester, String key) async {
  final section = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    section,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  final title = find.descendant(
    of: section,
    matching: find.text(key == 'commission-details' ? '設備與連線資訊' : '進階檢查'),
  );
  await tester.ensureVisible(title);
  await tester.pumpAndSettle();
  await tester.tap(title);
  await tester.pumpAndSettle();
}
