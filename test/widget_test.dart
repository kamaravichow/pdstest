import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdstest/main.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SmartHomeApp());
    await tester.pumpAndSettle();
  }

  testWidgets('desktop dashboard renders source sections', (tester) async {
    await pumpAt(tester, const Size(1440, 1000));

    expect(find.text('Smart CCTV'), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);
    expect(find.text('Power Statistics'), findsOneWidget);
    expect(find.text('Add Devices'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Raspberry Pi landscape layout remains scrollable and usable', (
    tester,
  ) async {
    await pumpAt(tester, const Size(800, 480));

    expect(find.byKey(const Key('device-search')), findsOneWidget);
    expect(find.text('Smart CCTV'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('dashboard-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone layout uses bottom navigation and no horizontal overflow',
    (tester) async {
      await pumpAt(tester, const Size(390, 844));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const Key('add-device')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('device controls are interactive', (tester) async {
    await pumpAt(tester, const Size(800, 600));

    final slider = find.byKey(const Key('light-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.tap(slider);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings offers close software while remaining in app chrome', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1440, 1000));

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const Key('close-software')), findsOneWidget);
    expect(find.text('Close software'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone layout exposes settings from the header', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(find.byKey(const Key('open-settings')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Close software'), findsOneWidget);
  });
}
