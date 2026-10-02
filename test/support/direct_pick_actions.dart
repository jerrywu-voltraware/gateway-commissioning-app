import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the direct-pick actions using the same overflow entry as the installer.
Future<void> openDirectActions(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('direct-more')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> dismissDirectActions(WidgetTester tester) async {
  await tester.tapAt(const Offset(1, 1));
  await tester.pumpAndSettle();
}

Future<void> tapDirectAction(WidgetTester tester, String key) async {
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    await openDirectActions(tester);
  }
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

bool directActionEnabled(WidgetTester tester, String key) {
  final widget = tester.widget(find.byKey(Key(key)));
  return switch (widget) {
    ButtonStyleButton() => widget.enabled,
    IconButton() => widget.onPressed != null,
    PopupMenuButton() => widget.enabled,
    PopupMenuItem() => widget.enabled,
    _ => throw StateError('Unexpected action widget: ${widget.runtimeType}'),
  };
}

Future<void> closeIdentifyDetails(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text('關閉')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}
