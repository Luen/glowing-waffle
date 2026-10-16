import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/app.dart';
import 'package:glowing_waffle/providers/tts_providers.dart';
import 'package:glowing_waffle/state/tts_app_state.dart';
import 'package:glowing_waffle/tts/tts_engine.dart';
import 'package:glowing_waffle/widgets/playback_controls.dart';

class FakeEngine extends TtsEngine {
  FakeEngine({this.error});
  final Object? error;
  final spoken = <String>[];
  String? lastVoice;
  double? lastSpeed;
  TtsBackend? lastBackend;

  @override
  Future<void> synthesizeAndPlay(String text) async {
    spoken.add(text);
    if (error != null) throw error!;
  }

  @override
  Future<void> setVoice(String voice) async {
    lastVoice = voice;
  }

  @override
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> setBackend(TtsBackend backend) async {
    lastBackend = backend;
  }
}

Future<void> pumpApp(WidgetTester tester, TtsEngine engine) async {
  // Use a tall surface so the whole form (text field, controls, buttons) fits
  // without depending on scroll position.
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(child: GlowingWaffleApp(engine: engine)));
}

Future<void> tapPlay(WidgetTester tester) async {
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reads entered text with the engine', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine);
    expect(find.text('Read aloud'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Hello world');
    await tapPlay(tester);

    expect(engine.spoken, ['Hello world']);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('shows engine errors instead of swallowing them', (tester) async {
    await pumpApp(tester, FakeEngine(error: StateError('model missing')));

    await tester.enterText(find.byType(TextField).first, 'Hi');
    await tapPlay(tester);

    expect(find.textContaining('model missing'), findsOneWidget);
  });

  testWidgets('ignores empty text', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine);
    await tapPlay(tester);
    expect(engine.spoken, isEmpty);
  });

  testWidgets('applies the selected voice and speed before speaking',
      (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine);

    // Default settings are applied.
    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tapPlay(tester);
    expect(engine.lastVoice, kDefaultVoice);
    expect(engine.lastSpeed, 1.0);

    // Pick another voice from the dropdown.
    await tester.tap(find.text('af_heart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('am_adam').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Again');
    await tapPlay(tester);
    expect(engine.lastVoice, 'am_adam');
  });

  testWidgets('hides the acceleration picker off web', (tester) async {
    await pumpApp(tester, FakeEngine());
    expect(find.text('Acceleration'), findsNothing);
  }, skip: kIsWeb);

  testWidgets('shows the acceleration picker on web', (tester) async {
    await pumpApp(tester, FakeEngine());
    expect(find.text('Acceleration'), findsOneWidget);
  }, skip: !kIsWeb);

  testWidgets('applies the selected acceleration backend before speaking',
      (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine);

    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tapPlay(tester);
    expect(engine.lastBackend, TtsBackend.auto);

    // The web home screen shows the picker; drive the same state here.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GlowingWaffleApp)),
      listen: false,
    );
    container.read(ttsStateProvider.notifier).setBackend(TtsBackend.cpu);
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'Again');
    await tapPlay(tester);
    expect(engine.lastBackend, TtsBackend.cpu);
  });

  testWidgets('acceleration picker lists the backends when shown',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PlaybackControls(showBackend: true)),
        ),
      ),
    );

    expect(find.text('Acceleration'), findsOneWidget);
    expect(container.read(ttsStateProvider).backend, TtsBackend.auto);

    await tester.tap(find.text('Auto').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CPU (WASM)').last);
    await tester.pumpAndSettle();

    expect(container.read(ttsStateProvider).backend, TtsBackend.cpu);
  });
}
