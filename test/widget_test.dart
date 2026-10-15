import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/app.dart';
import 'package:glowing_waffle/tts/tts_engine.dart';

class FakeEngine extends TtsEngine {
  FakeEngine({this.error});
  final Object? error;
  final spoken = <String>[];

  @override
  Future<void> synthesizeAndPlay(String text) async {
    spoken.add(text);
    if (error != null) throw error!;
  }
}

Future<void> pumpApp(WidgetTester tester, TtsEngine engine) =>
    tester.pumpWidget(ProviderScope(child: GlowingWaffleApp(engine: engine)));

void main() {
  testWidgets('reads entered text with the engine', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine);
    expect(find.text('Read aloud'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Hello world');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(engine.spoken, ['Hello world']);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('shows engine errors instead of swallowing them', (tester) async {
    await pumpApp(tester, FakeEngine(error: StateError('model missing')));

    await tester.enterText(find.byType(TextField).first, 'Hi');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.textContaining('model missing'), findsOneWidget);
  });

  testWidgets('ignores empty text', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(engine.spoken, isEmpty);
  });
}
