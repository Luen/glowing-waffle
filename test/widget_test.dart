import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/app.dart';
import 'package:glowing_waffle/providers/tts_providers.dart';
import 'package:glowing_waffle/state/tts_app_state.dart';
import 'package:glowing_waffle/tts/audio_saver.dart';
import 'package:glowing_waffle/tts/tts_engine.dart';
import 'package:glowing_waffle/widgets/playback_controls.dart';

class FakeEngine extends TtsEngine {
  FakeEngine({this.error, this.sampleCount = 2400});
  final Object? error;

  /// Samples produced by [renderSamples] (2400 = 0.1 s at 24 kHz).
  final int sampleCount;

  final spoken = <String>[];
  final rendered = <String>[];
  String? lastVoice;
  double? lastSpeed;
  TtsBackend? lastBackend;

  @override
  Future<void> synthesizeAndPlay(String text) async {
    spoken.add(text);
    if (error != null) throw error!;
  }

  @override
  Future<RenderedAudio> renderSamples(String text) async {
    rendered.add(text);
    if (error != null) throw error!;
    return RenderedAudio(Float32List(sampleCount));
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

/// Engine that cannot render audio without playing it (the [TtsEngine] default).
class NoExportEngine extends TtsEngine {
  @override
  Future<void> synthesizeAndPlay(String text) async {}
}

class FakeAudioSaver implements AudioSaver {
  /// Fails [save] with this error when set.
  Object? error;

  final saved = <({String fileName, Uint8List bytes})>[];

  @override
  Future<String> save(Uint8List bytes, String fileName) async {
    if (error != null) throw error!;
    saved.add((fileName: fileName, bytes: bytes));
    return '/tmp/downloads';
  }
}

Future<void> pumpApp(
  WidgetTester tester,
  TtsEngine engine, {
  AudioSaver? saver,
}) async {
  // Use a tall surface so the whole form (text field, controls, buttons) fits
  // without depending on scroll position.
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: GlowingWaffleApp(
        engine: engine,
        // Never write to the real filesystem from a widget test.
        audioSaver: saver ?? FakeAudioSaver(),
      ),
    ),
  );
}

Future<void> tapPlay(WidgetTester tester) async {
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Save WAV'));
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

  testWidgets('saves the whole text as one wav file', (tester) async {
    final engine = FakeEngine(sampleCount: 2400); // 0.1 s at 24 kHz
    final saver = FakeAudioSaver();
    await pumpApp(tester, engine, saver: saver);

    const text = 'Hello world. This is a second sentence.';
    await tester.enterText(find.byType(TextField).first, text);
    await tapSave(tester);

    expect(engine.rendered, [text]);
    expect(engine.spoken, isEmpty, reason: 'saving must not play anything');
    expect(saver.saved, hasLength(1));

    final saved = saver.saved.single;
    expect(saved.fileName, 'aloud-hello-world-this-is-a-second-af_heart.wav');
    // A 44-byte WAV header plus 2400 16-bit mono samples.
    expect(saved.bytes.length, 44 + 2400 * 2);
    expect(String.fromCharCodes(saved.bytes.sublist(0, 4)), 'RIFF');
    expect(saved.bytes.sublist(8, 12), 'WAVE'.codeUnits);

    expect(
      find.textContaining('Saved aloud-hello-world-this-is-a-second-af_heart.wav'),
      findsOneWidget,
    );
    expect(find.text('Save WAV'), findsOneWidget);
  });

  testWidgets('saves with the selected voice and speed', (tester) async {
    final engine = FakeEngine();
    final saver = FakeAudioSaver();
    await pumpApp(tester, engine, saver: saver);

    await tester.tap(find.text('af_heart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('am_adam').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Hi');
    await tapSave(tester);

    expect(engine.lastVoice, 'am_adam');
    expect(engine.lastSpeed, 1.0);
    expect(saver.saved.single.fileName, 'aloud-hi-am_adam.wav');
  });

  testWidgets('ignores empty text when saving', (tester) async {
    final engine = FakeEngine();
    final saver = FakeAudioSaver();
    await pumpApp(tester, engine, saver: saver);
    await tapSave(tester);
    expect(engine.rendered, isEmpty);
    expect(saver.saved, isEmpty);
  });

  testWidgets('reports when the engine cannot export audio', (tester) async {
    await pumpApp(tester, NoExportEngine());
    await tester.enterText(find.byType(TextField).first, 'Hi');
    await tapSave(tester);
    expect(find.textContaining('cannot export audio'), findsOneWidget);
  });

  testWidgets('reports when the file cannot be written', (tester) async {
    final saver = FakeAudioSaver()..error = StateError('disk full');
    await pumpApp(tester, FakeEngine(), saver: saver);
    await tester.enterText(find.byType(TextField).first, 'Hi');
    await tapSave(tester);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(find.text('Save WAV'), findsOneWidget);
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

  testWidgets('fits Play, Stop and Save on a narrow phone', (tester) async {
    // 360x640 logical pixels: the three labelled buttons must not overflow.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: GlowingWaffleApp(
          engine: FakeEngine(),
          audioSaver: FakeAudioSaver(),
        ),
      ),
    );

    expect(find.text('Save WAV'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
