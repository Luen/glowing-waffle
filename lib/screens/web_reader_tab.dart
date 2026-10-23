import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/tts_providers.dart';
import '../state/tts_app_state.dart';
import '../widgets/playback_controls.dart';

/// Tab for loading a URL and extracting text to read (mobile/macOS only).
class WebReaderTab extends ConsumerStatefulWidget {
  const WebReaderTab({
    super.key,
    required this.onExtractAndPlay,
    required this.onStop,
    required this.onSave,
  });

  final void Function(String text) onExtractAndPlay;

  /// Stops playback started from this tab, which otherwise would keep reading
  /// until the user switched to the Text tab.
  final VoidCallback onStop;

  /// Called with the extracted text when Save is pressed.
  final void Function(String text) onSave;

  @override
  ConsumerState<WebReaderTab> createState() => _WebReaderTabState();
}

class _WebReaderTabState extends ConsumerState<WebReaderTab> {
  final TextEditingController _urlController = TextEditingController(
    text: 'https://flutter.dev',
  );
  late final WebViewController _webController;
  static const String _textChannelName = 'TextChannel';

  /// Completed by the page when it posts its text back; see [_extractText].
  Completer<String>? _pendingText;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _textChannelName,
        onMessageReceived: _handleExtractedText,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {},
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.tryParse('https://$url');
    }
    if (uri != null) {
      await _webController.loadRequest(uri);
    }
  }

  /// Text extraction script injected into the page. Paragraphs are preferred
  /// because they also cover content inside `article`/`main`; selecting those
  /// too used to read nested paragraphs twice. Duplicate blocks are dropped as a
  /// second guard.
  String get _extractScript => '''
      (function() {
        var text = '';
        var sel = window.getSelection();
        if (sel && sel.toString().trim().length > 0) {
          text = sel.toString().trim();
        } else {
          var nodes = document.querySelectorAll('p');
          if (nodes.length === 0) {
            nodes = document.querySelectorAll('article, main');
          }
          if (nodes.length === 0) {
            nodes = document.querySelectorAll('h1, h2, h3, li, blockquote');
          }
          var seen = {};
          var parts = [];
          nodes.forEach(function(n) {
            var t = n.innerText ? n.innerText.trim() : '';
            if (!t || seen[t]) return;
            seen[t] = true;
            parts.push(t);
          });
          text = parts.join('\\n\\n');
        }
        if (text && window.__CHANNEL__) {
          window.__CHANNEL__.postMessage(text);
        }
      })();
    '''
        .replaceAll('__CHANNEL__', _textChannelName);

  /// Completes [_pendingText], if a caller is waiting for the page text.
  void _handleExtractedText(JavaScriptMessage message) {
    final text = message.message.trim();
    final pending = _pendingText;
    if (text.isEmpty || pending == null || pending.isCompleted) return;
    pending.complete(text);
  }

  /// Extracts the current selection, or the page's paragraphs, and returns it.
  ///
  /// The page posts its text through JavaScript channel [_textChannelName];
  /// calls that nothing answers (empty page, blocked JavaScript) resolve to an
  /// empty string after a short wait instead of hanging.
  Future<String> _extractText() async {
    final completer = Completer<String>();
    _pendingText = completer;
    try {
      await _webController.runJavaScript(_extractScript);
      return await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return '';
    } finally {
      _pendingText = null;
    }
  }

  /// Reads the page's text aloud.
  Future<void> _readPage() async {
    final text = await _extractText();
    if (text.isEmpty) return;
    widget.onExtractAndPlay(text);
  }

  /// Saves the page's text as one audio file.
  Future<void> _savePage() async {
    final text = await _extractText();
    if (text.isEmpty) return;
    widget.onSave(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttsStateProvider);
    final isBusy =
        state.status != AppStatus.idle && state.status != AppStatus.error;
    final canExtract = !isBusy && state.modelReady;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://example.com',
                  ),
                  onSubmitted: (_) => _loadUrl(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _loadUrl(),
                child: const Text('Go'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Wrap, not Row: three labelled buttons overflow narrow phones.
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: canExtract ? _readPage : null,
                    icon: const Icon(Icons.article),
                    label: const Text('Extract & Read'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.status == AppStatus.playing
                        ? widget.onStop
                        : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canExtract ? _savePage : null,
                    icon: const Icon(Icons.download),
                    label: Text(
                      state.status == AppStatus.exportingAudio
                          ? 'Saving…'
                          : 'Save WAV',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // The Web Reader only exists on native builds, which can pick a
              // model (web is Kokoro-only).
              const PlaybackControls(showModelPicker: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: WebViewWidget(controller: _webController),
        ),
      ],
    );
  }
}

/// Returns true when WebView is available (Android, iOS, macOS).
bool get isWebViewSupported {
  try {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  } catch (_) {
    return false;
  }
}
