import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_app/main.dart';

void main() {
  for (final viewport in <Size>[
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1366, 1024),
  ]) {
    testWidgets('Login fits phone and iPad $viewport', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ClipboardApp());
      expect(find.text('共享剪贴板'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TextFormField).first).width,
        lessThanOrEqualTo(440),
      );
    });
  }
}
