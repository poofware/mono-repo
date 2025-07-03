import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView wrapper for the Checkr **hosted invitation flow**.
///
/// • Occupies the whole screen inside a modal dialog
///   (see `_showInviteOverlay` in *CheckrInProgressPage*).
/// • Closes itself with `Navigator.pop(context)` when the user taps ✕
///   or when the hosted page signals success.
///
/// No backend polling lives here any more; the in‑progress page owns that.
class CheckrInviteWebViewPage extends ConsumerStatefulWidget {
  final String invitationUrl;
  const CheckrInviteWebViewPage({super.key, required this.invitationUrl});

  @override
  ConsumerState<CheckrInviteWebViewPage> createState() =>
      _CheckrInviteWebViewPageState();
}

class _CheckrInviteWebViewPageState
    extends ConsumerState<CheckrInviteWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  // --------------------------------------------------------------
  //  JavaScript that detects the success DOM and notifies Flutter.
  // --------------------------------------------------------------
  static const String _successDetectorJs = r'''
(function () {
  function isSuccess() {
    const headers = Array.from(document.querySelectorAll('h4, h5'))
      .some(h => /what'?s\s+next/i.test(h.textContent || ''));
    const bodyText = document.body ? document.body.textContent || '' : '';
    const startedCopy =
      /we\s*(?:'ve|)?\s*started[^]{0,60}background\s+check/i.test(bodyText);
    return headers && startedCopy;
  }

  if (isSuccess()) {
    CheckrBridge.postMessage('success');
    return;
  }
  const obs = new MutationObserver(() => {
    if (isSuccess()) {
      CheckrBridge.postMessage('success');
      obs.disconnect();
    }
  });
  obs.observe(document.documentElement, { childList: true, subtree: true });
})();
''';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'CheckrBridge',
        onMessageReceived: (msg) {
          if (msg.message == 'success') _close();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // Catch the mobile “instant exceptions” URL and close instantly.
          onNavigationRequest: (request) {
            final uri = Uri.parse(request.url);
            final isInstantExceptions = uri.path.startsWith('/instant_exceptions/') &&
                (uri.host == 'candidate.checkrhq.net' ||
                 uri.host == 'candidate.checkrhq-staging.net');
            if (isInstantExceptions) {
              _close();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) {
            setState(() => _isLoading = false);
            _controller.runJavaScript(_successDetectorJs);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.invitationUrl));
  }

  void _close() {
    if (mounted) Navigator.pop(context); // pops only the dialog
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The WebView fills the entire space.
        WebViewWidget(controller: _controller),

        // A loading indicator is positioned at the top.
        if (_isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),

        // A floating close button is positioned at the top-right.
        Positioned(
          top: 16,
          right: 16,
          child: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            child: IconButton(
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: _close,
            ),
          ),
        ),
      ],
    );
  }
}
