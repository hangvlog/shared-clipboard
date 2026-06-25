import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clipboard_app/main.dart';

void main() {
  testWidgets('App launches and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ClipboardApp());

    // 未登录状态应显示登录页面
    expect(find.text('共享剪贴板'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
