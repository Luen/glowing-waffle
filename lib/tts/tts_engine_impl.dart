import 'tts_engine.dart';
import 'tts_engine_web.dart'
    if (dart.library.io) 'tts_engine_mobile.dart' as impl;

/// Returns the platform-specific TTS engine.
/// Web: TtsEngineWeb (Phase 3). Native: TtsEngineMobile (Phase 4).
TtsEngine getTtsEngine() => impl.getTtsEngineImpl();
