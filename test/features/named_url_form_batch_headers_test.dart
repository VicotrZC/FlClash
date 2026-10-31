import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// 批量导入时「一套请求头应用到所有 URL」的行为。
///
/// 单独成文件的原因：批量模式以前根本不渲染高级选项，提交时把
/// userAgent/customHeaders 硬编码成空串，于是 vpncheap 这类必须带
/// `X-Client-Encrypt` 的机场，批量导入的每个订阅都会 403。
Future<void> _open(
  WidgetTester tester,
  NamedUrlForm form,
  ValueSetter<List<NamedUrl>?> onResult,
) async {
  const size = Size(1200, 1200);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TestApp(
      overrides: [viewSizeProvider.overrideWithBuild((_, _) => size)],
      child: Builder(
        builder: (context) => FilledButton(
          onPressed: () async => onResult(
            await showFormSheet<List<NamedUrl>>(
              context: context,
              builder: (_) => form,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder _field(String title) => find.descendant(
  of: find.widgetWithText(FormRow, title),
  matching: find.byType(TextFormField),
);

/// MultiLineHeaderField 是裸 TextField，不是 TextFormField，[_field] 找不到它。
Finder _headersField() => find.descendant(
  of: find.widgetWithText(FormRow, 'Custom headers'),
  matching: find.byType(TextField),
);

const _form = NamedUrlForm(
  title: 'Import',
  batch: true,
  withSubscriptionOptions: true,
);

Future<void> _expandAdvanced(WidgetTester tester) async {
  await tester.tap(find.text('Subscription options'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('批量导入把同一套请求头带到每个 url', (tester) async {
    List<NamedUrl>? result;
    await _open(tester, _form, (value) => result = value);

    await tester.tap(find.byTooltip('Batch import'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://a.example.com/sub\nhttps://b.example.com/sub',
    );
    await tester.pump();

    await _expandAdvanced(tester);
    await tester.enterText(_field('User-Agent'), 'vpncheap-android/2.3.27');
    await tester.enterText(_headersField(), 'X-Client-Encrypt: v1');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result, hasLength(2));
    for (final entry in result!) {
      expect(entry.userAgent, 'vpncheap-android/2.3.27');
      expect(entry.customHeaders, 'X-Client-Encrypt: v1');
    }
    expect(result!.map((e) => e.url), [
      'https://a.example.com/sub',
      'https://b.example.com/sub',
    ]);
  });

  testWidgets('批量导入的请求头写错时被拦下，不返回结果', (tester) async {
    List<NamedUrl>? result;
    await _open(tester, _form, (value) => result = value);

    await tester.tap(find.byTooltip('Batch import'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://a.example.com/sub');
    await tester.pump();

    await _expandAdvanced(tester);
    // 漏掉冒号，最典型的输错方式。以前会静默丢掉这一行并照常导入。
    await tester.enterText(_headersField(), 'X-Client-Encrypt v1');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.byType(NamedUrlForm), findsOneWidget);
  });

  testWidgets('请求头合法时不再误拦', (tester) async {
    List<NamedUrl>? result;
    await _open(tester, _form, (value) => result = value);

    await tester.tap(find.byTooltip('Batch import'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://a.example.com/sub');
    await tester.pump();

    await _expandAdvanced(tester);
    await tester.enterText(
      _headersField(),
      'X-Client-Encrypt: v1\nX-Client: android',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(
      result!.single.customHeaders,
      'X-Client-Encrypt: v1\nX-Client: android',
    );
  });
}
