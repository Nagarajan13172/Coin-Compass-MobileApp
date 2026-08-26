import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// **7.3 — the overflow the device found, and only the device could.**
///
/// Every widget test in this repo runs in English, where these labels fit. The
/// import screen was walked on the phone with Tamil switched on and overflowed
/// three buttons at once — 1.3px, 12px and 126px — because `AppButton` centred
/// a `Row` of icon + *unconstrained* `Text`. A `Row` sized to its children hands
/// an unbounded width to that `Text`, so a long label paints past the button
/// instead of ellipsising.
///
/// These are the real strings, at the real width (360dp), so the regression
/// cannot come back through a translation nobody ran locally.
void main() {
  const Size phone = Size(360, 800);

  Future<void> pumpButton(
    WidgetTester tester,
    Widget button, {
    double width = 360,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: button),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The Tamil the device actually rendered.
  const skipRows = 'இந்த வரிசைகளைத் தவிர்க்கவும்';
  const importThree = 'இறக்குமதி 3 பரிவர்த்தனைகள்';
  const importAnother = 'மற்றொரு கோப்பை இறக்குமதி செய்யவும்';

  group('a label wider than the button ellipsises rather than overflowing', () {
    testWidgets('"Skip these rows" — overflowed by 1.3px on the device',
        (tester) async {
      await pumpButton(
        tester,
        const AppButton(label: skipRows, variant: AppButtonVariant.outlined),
        width: 328,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Import 3 transactions" — overflowed by 12px', (tester) async {
      await pumpButton(
        tester,
        const AppButton(label: importThree, icon: LucideIcons.fileUp),
        width: 328,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Import another file" — overflowed by 126px', (tester) async {
      await pumpButton(
        tester,
        const AppButton(
          label: importAnother,
          icon: LucideIcons.fileUp,
          variant: AppButtonVariant.outlined,
        ),
        width: 328,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an absurd label still cannot overflow', (tester) async {
      await pumpButton(
        tester,
        AppButton(label: 'x' * 400, icon: LucideIcons.fileUp),
        width: 200,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow button with a long label survives', (tester) async {
      await pumpButton(
        tester,
        const AppButton(label: importAnother, expand: false),
        width: 120,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('what must not change', () {
    testWidgets('a short label still renders in full', (tester) async {
      await pumpButton(tester, const AppButton(label: 'Save'));
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the icon still renders beside the label', (tester) async {
      await pumpButton(
        tester,
        const AppButton(label: 'Import', icon: LucideIcons.fileUp),
      );
      expect(find.byIcon(LucideIcons.fileUp), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('a busy button shows a spinner, not a label', (tester) async {
      await pumpButton(tester, const AppButton(label: 'Save', busy: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });
}
