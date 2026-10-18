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
  });

  final void Function(String text) onExtractAndPlay;
  final VoidCallback onStop;

  @override
  ConsumerState<WebReaderTab> createState() => _WebReaderTabState();
}

class _WebReaderTabState extends ConsumerState<WebReaderTab> {
  final TextEditingController _urlController = TextEditingController(
    text: 'https://flutter.dev',
  );
  late final WebViewController _webController;
  static const String _textChannelName = 'TextChannel';

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _textChannelName,
        onMessageReceived: (JavaScriptMessage message) {
          final text = message.message.trim();
          if (text.isNotEmpty) {
            widget.onExtractAndPlay(text);
          }
        },
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

  /// Injects script to extract paragraph text or selection and send to Dart.
  ///
  /// Paragraphs are preferred because they also cover content inside
  /// `article`/`main`; selecting those too used to read nested paragraphs
  /// twice. Duplicate blocks are dropped as a second guard.
  Future<void> _extractAndSend() async {
    final String script = '''
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
    '''.replaceAll('__CHANNEL__', _textChannelName);

    await _webController.runJavaScript(script);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttsStateProvider);
    final isBusy = state.status != AppStatus.idle && state.status != AppStatus.error;
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
                    border: OutlineInputBorder(),
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
              FilledButton.icon(
                onPressed: canExtract
                    ? () async {
                        await _extractAndSend();
                      }
                    : null,
                icon: const Icon(Icons.article),
                label: const Text('Extract & Read'),
              ),
              const SizedBox(height: 12),
              const PlaybackControls(),
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
