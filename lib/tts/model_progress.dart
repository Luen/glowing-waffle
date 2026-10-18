import 'package:flutter/foundation.dart';

/// Progress of the on-device model download, 0.0 - 1.0, or `null` when no
/// download is running.
///
/// The native engine writes to this while it fetches the Kokoro model on first
/// run and the setup card listens to it. It stays `null` on platforms that
/// never download (web), so shared widgets can use it unconditionally.
final ValueNotifier<double?> modelDownloadProgress = ValueNotifier<double?>(null);
