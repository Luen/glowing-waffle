import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glowing_waffle/providers/tts_providers.dart';
import 'package:glowing_waffle/state/tts_app_state.dart';
import 'package:glowing_waffle/state/tts_settings_store.dart';
import 'package:glowing_waffle/tts/tts_models.dart';

/// A container whose notifier writes to [store] instead of the platform, with
/// the asynchronous restore already applied.
Future<ProviderContainer> _restored(MemoryTtsSettingsStore store) async {
  final container = ProviderContainer(
    overrides: [
      ttsStateProvider.overrideWith(() => TtsStateNotifier(store: store)),
    ],
  );
  addTearDown(container.dispose);
  // Reading the provider runs build(), which starts the restore.
  container.read(ttsStateProvider);
  await pumpEventQueue();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores the stored model, voice, speed and backend', () async {
    final store = MemoryTtsSettingsStore(const TtsSettings(
      model: TtsModel.kitten,
      voicePicks: {TtsModel.kitten: 'Luna'},
      speed: 1.5,
      backend: TtsBackend.cpu,
    ));
    final container = await _restored(store);

    final state = container.read(ttsStateProvider);
    expect(state.model, TtsModel.kitten);
    expect(state.voice, 'Luna');
    expect(state.speed, 1.5);
    expect(state.backend, TtsBackend.cpu);
  });

  test('starts from the defaults when nothing is stored', () async {
    final container = await _restored(MemoryTtsSettingsStore());

    final state = container.read(ttsStateProvider);
    expect(state.model, TtsModel.kokoro);
    expect(state.voice, kDefaultVoice);
    expect(state.speed, 1.0);
    expect(state.backend, TtsBackend.auto);
  });

  test('writes a change through to the store', () async {
    final store = MemoryTtsSettingsStore();
    final container = await _restored(store);

    container.read(ttsStateProvider.notifier).setSpeed(1.25);
    await pumpEventQueue();

    expect(store.settings?.speed, 1.25);
    expect(store.saves, 1);
  });

  test('stores the voice per model', () async {
    final store = MemoryTtsSettingsStore();
    final container = await _restored(store);
    final notifier = container.read(ttsStateProvider.notifier);

    notifier.setModel(TtsModel.kitten);
    notifier.setVoice('Luna');
    await pumpEventQueue();

    expect(store.settings?.model, TtsModel.kitten);
    expect(store.settings?.voicePicks[TtsModel.kitten], 'Luna');
  });

  test('a stored voice the model does not have falls back to its default',
      () async {
    // af_heart is a Kokoro id; a Kitten model must not try to use it.
    final store = MemoryTtsSettingsStore(const TtsSettings(
      model: TtsModel.kitten,
      voicePicks: {TtsModel.kitten: 'af_heart'},
      speed: 1.0,
      backend: TtsBackend.auto,
    ));
    final container = await _restored(store);

    expect(
        container.read(ttsStateProvider).voice, TtsModel.kitten.defaultVoice);
  });

  test('clamps a stored speed to the slider range', () async {
    final store = MemoryTtsSettingsStore(const TtsSettings(
      model: TtsModel.kokoro,
      voicePicks: {},
      speed: 9,
      backend: TtsBackend.auto,
    ));
    final container = await _restored(store);

    expect(container.read(ttsStateProvider).speed, kMaxSpeed);
  });

  test('the platform store round-trips the settings', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsTtsSettingsStore();
    expect(await store.load(), isNull);

    await store.save(const TtsSettings(
      model: TtsModel.kitten,
      voicePicks: {TtsModel.kitten: 'Luna', TtsModel.kokoro: 'am_adam'},
      speed: 1.5,
      backend: TtsBackend.gpu,
    ));
    final loaded = await store.load();

    expect(loaded!.model, TtsModel.kitten);
    expect(loaded.voicePicks[TtsModel.kitten], 'Luna');
    expect(loaded.voicePicks[TtsModel.kokoro], 'am_adam');
    expect(loaded.speed, 1.5);
    expect(loaded.backend, TtsBackend.gpu);
  });

  test('a stored name this build does not know is ignored', () async {
    // A downgrade (or a renamed enum value) must not break startup.
    SharedPreferences.setMockInitialValues({
      'tts.model': 'whisper',
      'tts.backend': 'tpu',
      'tts.speed': 1.2,
    });

    final loaded = await PrefsTtsSettingsStore().load();

    expect(loaded!.model, isNull);
    expect(loaded.backend, TtsBackend.auto);
    expect(loaded.speed, 1.2);
  });
}
