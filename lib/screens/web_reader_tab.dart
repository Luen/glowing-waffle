import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/tts_providers.dart';
import '../state/tts_app_state.dart';

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
  Future<void> _extractAndSend() async {
    const String script = '''
      (function() {
        var text = '';
        var sel = window.getSelection();
        if (sel && sel.toString().trim().length > 0) {
          text = sel.toString().trim();
        } else {
          var nodes = document.querySelectorAll('p, article, main');
          var parts = [];
          nodes.forEach(function(n) {
            var t = n.innerText ? n.innerText.trim() : '';
            if (t) parts.push(t);
          });
          text = parts.join('\\n\\n');
        }
        if (text && window.$_textChannelName) {
          window.$_textChannelName.postMessage(text);
        }
      })();
    '''.replaceAll('$_textChannelName', _textChannelName);

    await _webController.runJavaScript(script);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttsStateProvider);
    final isBusy = state.status != AppStatus.idle && state.status != AppStatus.error;

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
          child: FilledButton.icon(
            onPressed: isBusy
                ? null
                : () async {
                    await _extractAndSend();
                  },
            icon: const Icon(Icons.article),
            label: const Text('Extract & Read'),
          ),
        ),
        const SizedBox(height: 8),
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
