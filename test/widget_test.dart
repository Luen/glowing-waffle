import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/app.dart';
import 'package:glowing_waffle/providers/tts_providers.dart';
import 'package:glowing_waffle/state/tts_app_state.dart';
import 'package:glowing_waffle/tts/model_progress.dart';
import 'package:glowing_waffle/tts/tts_engine.dart';
import 'package:glowing_waffle/widgets/playback_controls.dart';

class FakeEngine extends TtsEngine {
  FakeEngine({this.error, this.downloadError, this.modelReady = true});
  final Object? error;
  final Object? downloadError;
  final spoken = <String>[];
  String? lastVoice;
  double? lastSpeed;
  TtsBackend? lastBackend;

  /// Whether [isModelReady] reports the model as installed.
  bool modelReady;

  /// Number of times [downloadModel] was called.
  int downloadCalls = 0;

  /// When set, [downloadModel] waits for it, so a download can be observed
  /// in flight.
  Completer<void>? downloadPending;

  @override
  Future<void> synthesizeAndPlay(String text) async {
    spoken.add(text);
    if (error != null) throw error!;
  }

  @override
  Future<bool> isModelReady() async => modelReady;

  @override
  Future<void> downloadModel() async {
    downloadCalls++;
    if (downloadPending != null) await downloadPending!.future;
    if (downloadError != null) throw downloadError!;
    modelReady = true;
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

/// The tab's Play button, so tests can check whether it is enabled.
FilledButton playButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Play'));

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

  testWidgets('shows no model setup card once the model is installed',
      (tester) async {
    await pumpApp(tester, FakeEngine());
    await tester.pumpAndSettle();

    expect(find.text('Voice model needed'), findsNothing);
    expect(find.text('Download model'), findsNothing);
  });

  testWidgets('offers the model download when it is missing', (tester) async {
    final engine = FakeEngine(modelReady: false);
    await pumpApp(tester, engine);
    await tester.pumpAndSettle();

    expect(find.text('Voice model needed'), findsOneWidget);
    expect(find.textContaining('~350 MB'), findsOneWidget);
    // Nothing can be played until the model is there.
    expect(playButton(tester).onPressed, isNull);

    await tester.tap(find.text('Download model'));
    await tester.pumpAndSettle();

    expect(engine.downloadCalls, 1);
    expect(find.text('Voice model needed'), findsNothing);
    expect(playButton(tester).onPressed, isNotNull);
  });

  testWidgets('shows download and unpacking progress', (tester) async {
    final engine = FakeEngine(modelReady: false)
      ..downloadPending = Completer<void>();
    addTearDown(() => modelDownloadProgress.value = null);
    await pumpApp(tester, engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download model'));
    await tester.pump();

    expect(find.text('Downloading…'), findsOneWidget);
    expect(find.text('Starting…'), findsOneWidget);

    modelDownloadProgress.value = 0.42;
    await tester.pump();
    expect(find.text('Downloading 42%'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      ).value,
      closeTo(0.42, 0.001),
    );

    // The last fifth of the bar is unpacking the archive.
    modelDownloadProgress.value = 0.9;
    await tester.pump();
    expect(find.text('Unpacking…'), findsOneWidget);

    engine.downloadPending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Voice model needed'), findsNothing);
  });

  testWidgets('reports a failed model download and keeps the card',
      (tester) async {
    final engine = FakeEngine(
      modelReady: false,
      downloadError: StateError('no network'),
    );
    await pumpApp(tester, engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download model'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no network'), findsOneWidget);
    expect(find.text('Voice model needed'), findsOneWidget);
    expect(playButton(tester).onPressed, isNull);
  });
}
