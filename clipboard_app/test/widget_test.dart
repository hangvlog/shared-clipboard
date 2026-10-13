import 'package:flutter/material.dart';
import 'package:clipboard_app/widgets/glass_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_app/main.dart';
import 'package:clipboard_app/widgets/clipboard_detail.dart';
import 'package:clipboard_app/widgets/clipboard_item_tile.dart';
import 'package:clipboard_core/clipboard_core.dart';

void main() {
  testWidgets('Long text detail is selectable and history tile fits a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final content = List.generate(30, (i) => '完整内容第 $i 行').join('\n');
    final item = ClipboardItem(
      id: 'fixture',
      content: content,
      contentType: 'text',
      deviceId: 'mac',
      deviceName: 'A long desktop device name for layout',
      createdAt: DateTime.now().toIso8601String(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ClipboardItemTile(
              item: item,
              onCopy: () {},
              onDelete: () {},
              onView: () => showClipboardDetail(
                context,
                read: () async => item,
                copy: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('查看完整内容'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      content,
    );
    expect(tester.takeException(), isNull);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
  });
  testWidgets('Glass cards remain readable with large text and dark mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = ClipboardItem(
      id: 'large',
      content: '完整内容与跨设备同步',
      contentType: 'text',
      deviceId: 'phone',
      deviceName: 'A very long Android device name',
      createdAt: '2026-10-13T00:00:00Z',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: clipboardTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: GlassBackground(
            child: Scaffold(
              body: SingleChildScrollView(
                child: ClipboardItemTile(
                  item: item,
                  onCopy: () {},
                  onDelete: () {},
                  onView: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('复制'), findsOneWidget);
  });
  for (final viewport in <Size>[
    const Size(320, 640),
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
